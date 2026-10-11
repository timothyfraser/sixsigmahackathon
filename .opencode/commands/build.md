---
description: "Build ONE CONTRACT task (e.g. /build H-03): reads SPEC.md first, writes tests then code, never commits. Review is a separate step: /new, then /review H-03"
agent: build
model: google/gemini-3.1-flash-lite
---
Task id: $1
If the task id above is blank, list the todo tasks in CONTRACT.yaml and ask me which one. Do not guess.

You build exactly this ONE task from CONTRACT.yaml. You are the IMPLEMENTER only. Do not launch subagents or any other agent, and do not review your own work: the review is a separate step that I run in a fresh session (/new, then /review with this task id).

1. Before anything else, read SPEC.md completely (section 4 is the method and the known-answer check), docs/plan.md if it exists, and this task's block in CONTRACT.yaml.
2. In one sentence, restate the statistic this task computes and its formula, exactly as SPEC.md section 4 states it. If SPEC.md section 4 still says FILL IN or has no known-answer check, stop and ask me. Never invent a statistic or a known answer.
3. If you do not know my name for the owner field, ask me once. Get the time by running this command: date "+%Y-%m-%d %H:%M" (if it fails, run: python -c "import datetime; print(datetime.datetime.now().strftime('%Y-%m-%d %H:%M'))"). Load the contract-ledger skill and check the task out: status: in_progress, owner, and started_at = the time the command printed, pasted (never a time you made up). Never delete a field. Quote any value that contains a colon.
4. If the task computes a statistic, load the stats-first-steering skill. Write the tests first, then the code:
   - a known-answer test whose data and expected numbers are copied from SPEC.md section 4, never made up;
   - a degenerate case (constant data, or n = 1). With zero spread, a capability index such as Cp or Cpk is undefined: the code must raise a clear error, or return NaN or None with a message. inf, 0 or any other confident number is wrong, and a test that accepts one is wrong.
5. Stay inside the task's owns list:
   - Edit only the paths in its owns list, plus this task's block in CONTRACT.yaml.
   - Never delete, move or rename a file. Never create a file outside the owns list; scratch checks go in tests/ (or another folder on the owns list), never at the repo root.
   - Every package you import that is not in the standard library goes into the requirements file (for example app/requirements.txt) in the same step. If that file is not on the owns list, stop and tell me the exact line to add.
   - If you need any other file, stop and ask me.
6. Work in small steps. After each step run the tests and read the real output.
7. Run the task's definition_of_done exactly as written. For an API or app task, start the app, call the endpoint (or open the page) on one data/ file, and paste the real response.
8. If you get a 429, quota or rate-limit error, stop and tell me. Do not retry in a loop.
9. Do not commit, do not push, do not check the task in, and do not start another task.

End your final message with these parts, pasted, not summarized:
STATISTIC: the one sentence from step 2
FILES: every file you created or changed
TESTS: the test command and its real output
DEFINITION OF DONE: the definition_of_done command and its real output
NEXT: type /new, then /review with this task id
