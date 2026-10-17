# Implementation Plan

Complete this before implementation and update it when the plan changes.

## Approach

TaskProcessor validates configuration in init and all job IDs (left-to-right Set scan) at the start of process, before any worker runs. Work then runs in a single withTaskGroup. A scheduling loop keeps at most maximumConcurrency child tasks alive: it fills free slots with the next unstarted job (left to right), then awaits one completion, then repeats. Each child returns (index, outcome); results are written into an index-addressed array, so output order always equals input order regardless of completion order.

Outcome mapping: return value -> .succeeded, CancellationError -> .cancelled, any other error -> .failed. Cancellation: at the top of each scheduling iteration the loop checks Task.isCancelled; once seen it calls group.cancelAll(), starts nothing new, drains running children, and every slot still nil (never started) becomes .cancelled. Completed results are kept.

Retry extension: same machinery with maximumAttempts; the retry loop lives inside the one child task, so a retry never occupies an extra slot. The base process is the same engine with one attempt.

## Milestones

- [x] Validate configuration and all job IDs before starting work.
- [x] Schedule jobs within the concurrency limit and preserve input order.
- [x] Map success, ordinary errors, and cancellation outcomes.
- [x] Handle caller cancellation and never-started jobs.
- [x] Add at least six distinct student-authored tests and run `swift test`.

## Risks and checks

Active count exceeding the limit -> testConcurrencyLimitRespected (Probe actor).
Wrong ordering -> gate-controlled out-of-order test.
Workers started after cancellation -> cancellation test asserts only "a" started.
Retry occupying extra slots -> by construction (loop inside one child task).
Assumption: after cancellation, a failed attempt is not retried and is .cancelled.
