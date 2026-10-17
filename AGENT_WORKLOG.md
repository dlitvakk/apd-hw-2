# Agent Worklog

Name the tools you used. If you used no coding agent, state that explicitly.
Do not paste secrets or an unreviewed raw transcript.

| Date | Tool / model | Task or recommendation | My review and decision | Evidence |
| --- | --- | --- | --- | --- |
| 2026-10-17 | Claude Haiku 5.5 | Asked to review my plan of this task completion | Accepted rephrasing, rejected few ideas as AI had only a little context, not a full task. | Basically, it is the same plan in PLAN.MD (rephrased as I asked to do so) |
| 2026-10-17 | Claude Sonnet 5.5 | Drafted TaskProcessor (base + retry extension), 9 XCTest methods | Rejected Tests -> some of them replicated those in TaskProcessorPublicTests. Added clarification on what test cases to add / reject. F.e. caller-cancellation test waits for the first worker to start by polling probe.started in a loop with Task.yield()6 when example tests used waitUntilWaiting | swift test: Executed 5 tests, with 0 failures (0 unexpected) in 0.010 (0.011) seconds, Executed 9 tests, with 0 failures (0 unexpected) in 0.110 (0.113) seconds |
| 2026-10-17 | Claude Haiku 5.5 | Asked to generate a template of Agent Worklog based on our conversation | It indeed pasted two lines, and asked to add my own conclusions:) I accepted all of those as basically I wrote that | AGENT_WORKLOG.md |


## Final review

Risk: the draft was written in an environment without a Swift toolchain, so it was not compiled there; fixed compiler warnings/errors on first build.

Also, I intentionally did not opened Claude Code, or give any path to my assignment folder. I did not want AI to know the full context and initial templates of the file. I explained the task, asked to generate a draft (step-by-step in an educational manner). Basically each time, I asked to give me prompts on what to do / what to fix / what to add. After my suggestions, AI proposed its, and we both agreed on the thing we would move on.

I also reviewed the implementation with the lecture materials we had. My question was why we use withTaskGroup instead of withThrowingTaskGroup. Response:

The slide uses withThrowingTaskGroup and starts every task at once. The assignment needs a concurrency limit, so I only start tasks while active < limit and start a replacement each time one finishes. The slides don’t show that part. The closest lecture idea is the Operation Queue slide (“Concurrency Control: Limit the number of concurrent tasks”), but that is a GCD-era tool and the assignment forbids it.
I used the non-throwing withTaskGroup, because each child turns a worker error into a JobOutcome. The slide’s throwing group would cancel all the other tasks as soon as one threw, which would break the rule that other jobs continue after an error.
