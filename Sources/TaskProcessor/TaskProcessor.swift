public struct Job: Sendable, Equatable {
    public let id: String
    public let input: Int
    
    public init(id: String, input: Int) {
        self.id = id
        self.input = input
    }
}

public enum JobOutcome: Sendable, Equatable {
    case succeeded(Int)
    case failed
    case cancelled
}

public struct JobResult: Sendable, Equatable {
    public let id: String
    public let outcome: JobOutcome
    
    public init(id: String, outcome: JobOutcome) {
        self.id = id
        self.outcome = outcome
    }
}

public enum TaskProcessorError: Error, Equatable {
    case nonPositiveMaximumConcurrency
    case duplicateID(String)
}

public struct RetryPolicy: Sendable, Equatable {
    public let maximumAttempts: Int
    public init(maximumAttempts: Int) throws {
        guard maximumAttempts > 0 else { throw RetryPolicyError.nonPositiveMaximumAttempts }
        self.maximumAttempts = maximumAttempts
    }
}

public enum RetryPolicyError: Error, Equatable {
    case nonPositiveMaximumAttempts
}

public actor TaskProcessor {
    private let maximumConcurrency: Int

    public init(maximumConcurrency: Int) throws {
        guard maximumConcurrency > 0 else {
            throw TaskProcessorError.nonPositiveMaximumConcurrency
        }
        self.maximumConcurrency = maximumConcurrency
    }

    public func process(
        _ jobs: [Job],
        worker: @escaping @Sendable (Job) async throws -> Int
    ) async throws -> [JobResult] {
        try Self.validate(jobs)
        return await Self.run(
            jobs, limit: maximumConcurrency, maximumAttempts: 1
        ) { job, _ in try await worker(job) }
    }

    fileprivate func process(
        _ jobs: [Job],
        maximumAttempts: Int,
        worker: @escaping @Sendable (Job, Int) async throws -> Int
    ) async throws -> [JobResult] {
        try Self.validate(jobs)
        return await Self.run(
            jobs, limit: maximumConcurrency, maximumAttempts: maximumAttempts, worker: worker
        )
    }

    private static func validate(_ jobs: [Job]) throws {
        var seen = Set<String>()
        for job in jobs {
            if !seen.insert(job.id).inserted {
                throw TaskProcessorError.duplicateID(job.id)
            }
        }
    }

    private static func attempt(
        _ job: Job,
        maximumAttempts: Int,
        worker: @Sendable (Job, Int) async throws -> Int
    ) async -> JobOutcome {
        var attemptNumber = 1
        while true {
            do {
                return .succeeded(try await worker(job, attemptNumber))
            } catch is CancellationError {
                return .cancelled
            } catch {
                if attemptNumber >= maximumAttempts { return .failed }
                if Task.isCancelled { return .cancelled }
                attemptNumber += 1
            }
        }
    }

    private static func run(
        _ jobs: [Job],
        limit: Int,
        maximumAttempts: Int,
        worker: @escaping @Sendable (Job, Int) async throws -> Int
    ) async -> [JobResult] {
        let outcomes: [JobOutcome?] = await withTaskGroup(of: (Int, JobOutcome).self) { group in
            var results = [JobOutcome?](repeating: nil, count: jobs.count)
            var next = 0
            var active = 0
            var cancelled = false

            while true {
                if !cancelled && Task.isCancelled {
                    cancelled = true
                    group.cancelAll()
                }
                while !cancelled && active < limit && next < jobs.count {
                    let index = next
                    let job = jobs[index]
                    group.addTask {
                        let outcome = await attempt(
                            job, maximumAttempts: maximumAttempts, worker: worker)
                        return (index, outcome)
                    }
                    next += 1
                    active += 1
                }
                guard active > 0 else { break }
                if let (index, outcome) = await group.next() {
                    results[index] = outcome
                    active -= 1
                }
            }
            return results
        }

        return jobs.enumerated().map { index, job in
            JobResult(id: job.id, outcome: outcomes[index] ?? .cancelled)
        }
    }
}

public extension TaskProcessor {
    func process(
        _ jobs: [Job],
        retryPolicy: RetryPolicy,
        worker: @escaping @Sendable (Job, Int) async throws -> Int
    ) async throws -> [JobResult] {
        try await process(
            jobs, maximumAttempts: retryPolicy.maximumAttempts, worker: worker)
    }
}
