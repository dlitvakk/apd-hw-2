//
//  StudentTests.swift
//  apd-hw-2
//
//  Created by Dana Litvak on 17.10.2026.
//

import XCTest
@testable import TaskProcessor

private actor Probe {
    private(set) var active = 0
    private(set) var maxActive = 0
    private(set) var started: [String] = []
    func enter(_ id: String) { active += 1; maxActive = max(maxActive, active); started.append(id) }
    func leave() { active -= 1 }
}

private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

private struct Boom: Error {}

private func jobs(_ ids: String...) -> [Job] {
    ids.enumerated().map { Job(id: $1, input: $0 + 1) }
}

final class StudentTaskProcessorTests: XCTestCase {
    func testNonPositiveConcurrencyThrows() {
        XCTAssertThrowsError(try TaskProcessor(maximumConcurrency: 0)) {
            XCTAssertEqual($0 as? TaskProcessorError, .nonPositiveMaximumConcurrency)
        }
        XCTAssertThrowsError(try TaskProcessor(maximumConcurrency: -3))
    }

    func testFirstRepeatedIDThrowsBeforeAnyWorker() async throws {
        let probe = Probe()
        let processor = try TaskProcessor(maximumConcurrency: 2)
        let input = jobs("a", "b", "c", "b", "a") // "b" repeats first
        do {
            _ = try await processor.process(input) { job in
                await probe.enter(job.id); return 0
            }
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? TaskProcessorError, .duplicateID("b"))
        }
        let started = await probe.started
        XCTAssertTrue(started.isEmpty)
    }

    func testEmptyJobsReturnsEmpty() async throws {
        let processor = try TaskProcessor(maximumConcurrency: 1)
        let result = try await processor.process([]) { _ in XCTFail("no worker"); return 0 }
        XCTAssertEqual(result, [])
    }

    func testConcurrencyLimitRespected() async throws {
        let probe = Probe()
        let processor = try TaskProcessor(maximumConcurrency: 2)
        let input = jobs("a", "b", "c", "d", "e", "f")
        let results = try await processor.process(input) { job in
            await probe.enter(job.id)
            for _ in 0..<20 { await Task.yield() }
            await probe.leave()
            return job.input
        }
        let maxActive = await probe.maxActive
        XCTAssertLessThanOrEqual(maxActive, 2)
        XCTAssertEqual(results.count, 6)
    }

    func testLeftToRightSchedulingWithOneSlot() async throws {
        let probe = Probe()
        let processor = try TaskProcessor(maximumConcurrency: 1)
        _ = try await processor.process(jobs("a", "b", "c")) { job in
            await probe.enter(job.id); await probe.leave(); return 0
        }
        let started = await probe.started
        XCTAssertEqual(started, ["a", "b", "c"])
    }

    func testResultsKeepInputOrderDespiteOutOfOrderCompletion() async throws {
        let gate = Gate()
        let processor = try TaskProcessor(maximumConcurrency: 3)
        let results = try await processor.process(jobs("a", "b", "c")) { job in
            switch job.id {
            case "a": await gate.wait(); return 10
            case "b": return 20
            default: await gate.open(); return 30
            }
        }
        XCTAssertEqual(results, [
            JobResult(id: "a", outcome: .succeeded(10)),
            JobResult(id: "b", outcome: .succeeded(20)),
            JobResult(id: "c", outcome: .succeeded(30)),
        ])
    }

    func testOutcomeMapping() async throws {
        let processor = try TaskProcessor(maximumConcurrency: 2)
        let results = try await processor.process(jobs("ok", "bad", "cancel", "ok2")) { job in
            switch job.id {
            case "bad": throw Boom()
            case "cancel": throw CancellationError()
            default: return job.input * 2
            }
        }
        XCTAssertEqual(results.map(\.outcome), [.succeeded(2), .failed, .cancelled, .succeeded(8)])
    }

    func testCallerCancellationMarksQueuedJobsCancelled() async throws {
        let probe = Probe()
        let processor = try TaskProcessor(maximumConcurrency: 1)
        let input = jobs("a", "b", "c")
        let task = Task {
            try await processor.process(input) { job in
                await probe.enter(job.id)
                try await Task.sleep(nanoseconds: 60_000_000_000) // throws on cancel
                return 0
            }
        }
        while await probe.started.isEmpty { await Task.yield() }
        task.cancel()
        let results = try await task.value
        XCTAssertEqual(results.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(results.map(\.outcome), [.cancelled, .cancelled, .cancelled])
        let started = await probe.started
        XCTAssertEqual(started, ["a"])
    }

    func testRetryPolicyValidationAndAttempts() async throws {
        XCTAssertThrowsError(try RetryPolicy(maximumAttempts: 0)) {
            XCTAssertEqual($0 as? RetryPolicyError, .nonPositiveMaximumAttempts)
        }
        let processor = try TaskProcessor(maximumConcurrency: 2)
        let policy = try RetryPolicy(maximumAttempts: 3)
        let results = try await processor.process(jobs("recover", "fail", "cancel"), retryPolicy: policy) { job, attempt in
            switch job.id {
            case "recover": if attempt < 3 { throw Boom() }; return attempt
            case "fail": throw Boom()
            default: throw CancellationError()
            }
        }
        XCTAssertEqual(results.map(\.outcome), [.succeeded(3), .failed, .cancelled])
    }
}
