---
description: "Build ONE CONTRACT task (e.g. /build H-03): implementer subagent, then stats-reviewer, one after the other"
agent: build
model: google/gemini-3.1-flash-lite
---
Task id: $1
If the task id above is blank, list the todo tasks in CONTRACT.yaml and ask me which one. Do not guess.

Build exactly this ONE task from CONTRACT.yaml, following docs/plan.md if it exists. You are the coordinator. The work has two roles, done strictly one after the other, never at the same time (a free AI key allows only one agent working at once):

- IMPLEMENTER: loads the contract-ledger skill; checks the task out (status: in_progress, with owner and started_at filled in, never deleted); edits only the paths in the task's owns list; for any statistic also loads the stats-first-steering skill; writes the tests first (a known answer AND a degenerate case), then the code; runs the tests after each small step; runs the task's definition_of_done; reports every command it ran with its real output. It does not check the task in and does not commit.
- REVIEWER (only if the task computes a statistic): loads the stats-first-steering skill; edits nothing; runs the code on the known answer AND the degenerate case; reports PASS or FAIL with the numbers.

How to run the roles:
1. Before starting, if you do not know my name for the owner field, ask me once.
2. If you can launch subagents and agents named implementer and stats-reviewer exist (in OpenCode they do), launch implementer with the task id and wait for it to finish; then, if the task computes a statistic, launch stats-reviewer with the task id and wait for it. If launching a subagent fails for any reason, stop and tell me the exact error. Never substitute a different agent, and never say a role ran when it did not.
3. If you cannot launch subagents, do the IMPLEMENTER role yourself, then the REVIEWER role yourself, one after the other, and label each part.
4. If the reviewer says FAIL, run the implementer once more with the reviewer's numbers, then review again. If it still fails, stop and show me both reports.
5. If the implementer needs a file outside the owns list, stop and ask me.
6. If you get a 429, quota or rate-limit error, stop and tell me. Do not retry in a loop.
7. Do not start another task, and do not check this one in (that is the check-in step, after I have read the diff).

End your final message with these three parts, pasted, not summarized:
TESTS: the test command and its real output
DEFINITION OF DONE: the definition_of_done command and its real output
REVIEW: PASS or FAIL with the numbers, or "not a statistics task"
