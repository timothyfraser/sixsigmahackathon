---
description: "Check a task's statistic against SPEC.md's known answer and a degenerate case (e.g. /review H-03); run it in a NEW session after /build; edits nothing"
agent: build
model: google/gemini-3.1-flash-lite
---
Task id: $1
If the task id above is blank, review the task in CONTRACT.yaml that is in_progress; if there is none, or more than one, ask me which.

You are the REVIEWER for this task. I run you in a fresh session (/new), after /build. Do the review yourself: do not launch subagents or any other agent. Do not edit, create or delete any file; run scratch checks as one-line python -c or Rscript -e commands.

1. Load the stats-first-steering skill (.claude/skills/stats-first-steering/SKILL.md).
2. Read SPEC.md section 4 (the method and the known-answer check), the task's block in CONTRACT.yaml, the files in its owns list, and its tests.
3. List every statistic SPEC.md names. For each one, write the formula the code uses in one line and say whether it matches SPEC.md. A statistic SPEC.md names that the code does not compute is a FAIL. Code that computes a different statistic is a FAIL. Name any trap from the skill that applies. For an X-bar and R chart, check all of these:
   - R chart limits exist (constants D3 and D4);
   - Cp and Cpk use sigma-hat = R-bar/d2. The overall standard deviation gives Pp and Ppk: FAIL;
   - each subgroup gets an out-of-control flag.
4. Known answer: import the task's function from its file and call it on the known-answer data from SPEC.md (the numbers in SPEC.md, not the ones in the tests), for example python -c "from app.qc import my_function; print(my_function(...))". Do this for EVERY statistic. If SPEC.md gives no expected number for a statistic, recompute it from the SPEC.md formula with one python -c line and mark it "recomputed".
5. Degenerate case: call the same function on constant data (or n = 1) and paste what it printed or raised. PASS only if it raises a clear error or returns NaN or None with a message. inf, 0 or any other confident number is a FAIL, even if a test accepts it.
6. Run the task's tests and paste the real output.
7. Report this table, one row per statistic, plus one row for the degenerate case and one for the tests:
   | statistic | expected | got | verdict |
   Then one line: OVERALL: PASS or OVERALL: FAIL. A bare PASS with no table is forbidden: no table means OVERALL: FAIL. On FAIL, say in one sentence what to fix. Do not fix it yourself. Never report a number you did not see printed.
