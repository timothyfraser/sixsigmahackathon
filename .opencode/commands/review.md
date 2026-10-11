---
description: "Check a task's statistic against a known answer and a degenerate case (e.g. /review H-03); edits nothing"
agent: build
model: google/gemini-3.1-flash-lite
---
Task id: $1
If the task id above is blank, review the task in CONTRACT.yaml that is in_progress; if there is none, or more than one, ask me which.

Review the statistics in this task. Do not edit any file. If you can launch a subagent named stats-reviewer (in OpenCode you can), launch it with the task id and wait for its report; if the launch fails, stop and tell me the exact error, and never substitute a different agent. Otherwise do the review yourself:

1. Load the stats-first-steering skill (.claude/skills/stats-first-steering/SKILL.md).
2. Read SPEC.md section 4, the files in the task's owns list, and its tests.
3. Write the formula the code uses in one line, and say whether it matches the method in SPEC.md. Name any trap from the skill that applies (for example Cp labelled as Cpk, or control limits mixed up with spec limits).
4. Known answer: run the code on the SPEC.md known-answer data. Show expected and got for every number.
5. Degenerate case: run it on constant data (or n = 1). It must raise a clear error or report "undefined", never a confident number.
6. Report a table with the columns check, expected, got, PASS/FAIL, then one overall PASS or FAIL. On FAIL, say in one sentence what to fix. Do not fix it yourself.
