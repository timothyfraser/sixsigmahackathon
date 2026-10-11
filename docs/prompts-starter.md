# Starter prompts for any AI agent

Six prompts that take a team from a filled-in `SPEC.md` to a checked-in, tested task:
**plan, decide, build, review, check in**, and **stuck** for when something goes wrong. They work
pasted into any coding agent: OpenCode, Claude Code, Codex, GitHub Copilot agent mode, and the
Gemini or Antigravity CLI.

- **OpenCode** (the free path, see [`opencode.md`](opencode.md)): you do not paste anything. Each
  prompt is a slash command in this repo: type `/plan`, `/decide`, `/build H-03`, `/review H-03`,
  `/checkin H-03` or `/stuck`. Each command is set to the free Gemini model that suits its job:
  `/plan` and `/decide` use `gemini-3.5-flash` (the better thinker, about 20 requests a day), the
  others use `gemini-3.1-flash-lite` (the workhorse, about 500 a day). If a command's model is out of
  quota, switch with `/models` and paste the prompt from this page instead.
- **Any other agent:** copy the grey block, change the placeholder on its first line if it has one,
  and paste it as your message.

The prompt text below is exactly the text of the OpenCode commands in
[`.opencode/commands/`](../.opencode/commands/), so every team gets the same instructions whichever
agent they use.

## How to use them well

- **One task per session.** Start a fresh chat (`/new` in OpenCode) before each prompt. Short sessions
  are faster, cheaper, and stay under a free key's per-minute limit.
- **Read what the agent prints.** Every prompt ends with real output: a test result, a table, a diff.
  If you get a claim ("DONE", "should work") instead of output, ask for the output.
- **The order:** `plan` once, `decide` when a choice is open, then for each task `build`, `review`,
  `checkin`. Use `stuck` whenever you need it.
- **One agent at a time per key.** On a free Google key, two agents working at once run out of the
  per-minute allowance. Teams work in parallel across people, each on their own key.

The examples below use a made-up bolt-torque line (X-bar and R chart, subgroups of 5, plus Cpk). They
show the shape of good output; they are not hints about the event prompts.


## 1. Write the plan  (OpenCode: `/plan`)

**When:** Once `SPEC.md` has no `FILL IN` lines left, and before anyone writes code. Start a fresh session for it.

<!-- prompt: plan -->
```text
You are planning, not coding. Do not create or edit any file except docs/plan.md.

1. Read SPEC.md and CONTRACT.yaml completely before you say anything.
2. In one sentence each, state: the user, the question the tool answers, the statistic, and the formula for that statistic (write the formula out). If SPEC.md leaves any of these unclear or still says FILL IN, stop and ask me before going on.
3. List every design decision that is still open (data shape, where the data comes from, what the function or API returns, what the user sees, what counts as "in control" or "capable"). Ask them ONE AT A TIME as multiple-choice questions with at most 4 options each, and say which option you recommend and why in one line. Use your question tool if you have one; otherwise ask as a numbered list and wait for my answer. Never ask the next question before I answer the current one.
4. Then write docs/plan.md: a numbered list of tasks, each mapped to one task id from CONTRACT.yaml (use the real ids; never invent one). For each task give: the files it may touch (from its owns list), the test that proves it (a known answer from a textbook or a hand calculation, AND a degenerate case such as constant data), and a time estimate. The statistic comes first, then the tool around it, then the page or chart. Nothing about styling until the numbers are proven.
5. Under the tasks, list the decisions I made in step 3, one line each.
6. End with the three biggest risks and what we will do about each.

Keep docs/plan.md under 60 lines. We are beginners: short sentences, and explain any jargon in a few words. When docs/plan.md is written, say PLAN WRITTEN and stop.
```

**What good output looks like:** The agent writes four one-sentence statements (user, question, statistic, formula), asks you 3 to 5 multiple-choice questions, then writes `docs/plan.md`. For a bolt-torque example (X-bar and R chart, subgroups of 5, plus Cpk), a good first task reads like: *"1. H-03, `app/qc.py` and `tests/`: `xbar_r_limits()` and `cpk()`; test a hand-worked example and constant data (Cpk must be undefined, not a number). 30 min."* Statistics first, styling nowhere.

**No question tool in your agent?** The prompt already says it: the agent asks as a numbered list and waits. Answer with the number.


## 2. Make the design decisions  (OpenCode: `/decide`)

**When:** Whenever a choice is still open: the shape of the data, what the tool returns, what the user sees, which run rules count as "out of control". `/plan` asks the first round; run this for anything left over.

<!-- prompt: decide -->
```text
You are helping my team make design decisions. Do not write code. The only file you may edit is docs/plan.md.

1. Read SPEC.md, CONTRACT.yaml and docs/plan.md (if it exists).
2. Find the design decisions that are still open: anything SPEC.md or docs/plan.md leaves undecided or marks as a question, and anything two tasks disagree about.
3. Ask them ONE AT A TIME. Each question has at most 4 options, numbered 1 to 4. Mark the option you recommend and give the reason in one line, tied to SPEC.md (the user, the statistic, or the rubric). Use your question tool if you have one; otherwise ask as a numbered list and wait for my answer. Never ask the next question before I answer the current one. Ask at most 5 questions; if more are open, ask first the ones that change the statistic or the inputs.
4. After my last answer, add or update a "Decisions" section in docs/plan.md: one line per decision, what we chose and why. If an answer changes SPEC.md, tell me the exact line to change; do not edit SPEC.md yourself.
5. Say DECISIONS RECORDED and stop.
```

**What good output looks like:** One question at a time, never a wall of text:

```
How should the tool receive the torque readings?
  1. CSV upload, columns subgroup and torque_nm   (recommended: matches SPEC.md)
  2. Paste a table into a text box
  3. Typed into a form
  4. Read from a shared sheet
```

You answer with a number. At the end `docs/plan.md` has a **Decisions** section, one line per answer.

**No question tool in your agent?** The prompt already says it: the agent asks as a numbered list and waits. Answer with the number.


## 3. Build one task  (OpenCode: `/build H-03`)

**When:** For exactly one task from `CONTRACT.yaml`, after the plan exists. Start a fresh session for every task.

**Before pasting:** Replace `$1` on the first line with your task id, for example `H-03`.

<!-- prompt: build -->
```text
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
```

**What good output looks like:** The task is checked out in `CONTRACT.yaml` with `owner` and `started_at` filled in. The final message ends with real output, not a claim:

```
TESTS: pytest tests
  2 passed in 0.21s
DEFINITION OF DONE: pytest tests  ->  2 passed
REVIEW: PASS - X-bar UCL expected 11.077, got 11.077; constant data -> "undefined", as expected
```

If the last message only says "DONE", ask for the test output.

**No subagents in your agent?** The prompt already says it: the agent does the implementer part, then the reviewer part, itself, one after the other. That is fine: OpenCode runs the same two roles in the same order, only as separate child sessions.


## 4. Review a statistic  (OpenCode: `/review H-03`)

**When:** Before you trust any number the tool prints, and always before `/checkin` on a statistics task. `/build` already runs this once; run it again after any change to the statistic.

**Before pasting:** Replace `$1` on the first line with your task id, for example `H-03`.

<!-- prompt: review -->
```text
Task id: $1
If the task id above is blank, review the task in CONTRACT.yaml that is in_progress; if there is none, or more than one, ask me which.

Review the statistics in this task. Do not edit any file. If you can launch a subagent named stats-reviewer (in OpenCode you can), launch it with the task id and wait for its report; if the launch fails, stop and tell me the exact error, and never substitute a different agent. Otherwise do the review yourself:

1. Load the stats-first-steering skill (.claude/skills/stats-first-steering/SKILL.md).
2. Read SPEC.md section 4, the files in the task's owns list, and its tests.
3. Write the formula the code uses in one line, and say whether it matches the method in SPEC.md. Name any trap from the skill that applies (for example Cp labelled as Cpk, or control limits mixed up with spec limits).
4. Known answer: run the code on the SPEC.md known-answer data. Show expected and got for every number.
5. Degenerate case: run it on constant data (or n = 1). It must raise a clear error or report "undefined", never a confident number.
6. Report a table with the columns check, expected, got, PASS/FAIL, then one overall PASS or FAIL. On FAIL, say in one sentence what to fix. Do not fix it yourself.
```

**What good output looks like:** A table you could show a judge. For the bolt-torque example (mean of subgroup means 10.50 N·m, average range 1.00 N·m, n = 5, spec limits 8 to 12 N·m):

```
check                 expected   got     
X-bar UCL             11.077     11.077  PASS
Cpk                   1.163      1.163   PASS
constant data         undefined  error   PASS
OVERALL: PASS
```

**No subagents in your agent?** The prompt already says it: the agent does the implementer part, then the reviewer part, itself, one after the other. That is fine: OpenCode runs the same two roles in the same order, only as separate child sessions.


## 5. Check the task in  (OpenCode: `/checkin H-03`)

**When:** When the build passed, the review passed, and someone on the team has read the diff.

**Before pasting:** Replace `$1` on the first line with your task id, for example `H-03`.

<!-- prompt: checkin -->
```text
Task id: $1
If the task id above is blank, use the task in CONTRACT.yaml that is in_progress; if there is none, or more than one, ask me which.

Check this task in, following the contract-ledger skill (.claude/skills/contract-ledger/SKILL.md).

1. Run the task's definition_of_done exactly as written in CONTRACT.yaml. Paste the command and its real output.
2. If it failed, stop: the task is not done. Leave status: in_progress, write what is missing in result, and tell me.
3. If it passed, edit only this task's block in CONTRACT.yaml: status: done, and result = one line saying what exists now and the check that proved it. Keep owner and started_at filled in (fill them if they are blank); never delete a field. Quote any value that contains a colon.
4. Check the ledger still parses: python -c "import yaml; yaml.safe_load(open('CONTRACT.yaml'))"
5. Show me git status, the diff, and the exact commit command, staging files by name (the task's owned files plus CONTRACT.yaml; never git add . or git add -A). Wait for my yes before committing. Never push.
6. End your final message with the definition_of_done output, pasted again, and the commit hash.
```

**What good output looks like:** The `definition_of_done` output pasted, the task's block in `CONTRACT.yaml` showing `status: done`, a one-line `result` and `owner`/`started_at` still filled in, the diff, and a `git add` that names files. It commits only after you say yes.

**Works the same in every agent.** Nothing here needs subagents or a question tool.


## 6. When you are stuck  (OpenCode: `/stuck <paste the error>`)

**When:** Any time: a `429` or "quota" error, the agent says nothing at all, the same error three times, or answers that get slow and vague.

**Before pasting:** Replace `$ARGUMENTS` on the first line with the error text or a one-line description of what you see.

<!-- prompt: stuck -->
```text
I am stuck. What I see (the error text or the symptom): $ARGUMENTS

Diagnose before doing anything else. Do not edit any file in this step.

1. Restate the problem in one sentence and say which of these it is:
   a. 429, RESOURCE_EXHAUSTED, "quota" or "rate limit": the free key's per-minute or per-day allowance is used up. Fixes, in this order: wait one minute, start a fresh session (/new in OpenCode) and run the last prompt again; step down the model ladder (another model ending in -flash for planning and thinking, the other model ending in -flash-lite for building); a teammate's key from their own Google account; and only if your employer allows third-party AI vendors, a Zen model whose name ends in -free, or GitHub Copilot. After switching models, if a slash command still fails the same way, paste that command's prompt from docs/prompts-starter.md instead, because each slash command asks for a fixed model.
   b. Nothing happens, no answer and no error: usually no key is connected. In OpenCode type /connect, choose Google, paste your key, then pick a model with /models.
   c. "Model ... has been deprecated": the agent was started outside the repo folder. Close it, cd into the repo, and start it again.
   d. The same error three times in a row: the task is too big. Start a fresh session, shrink the task to the smallest piece that can be tested, and put the error text in the new prompt.
   e. Answers are slow or vague: the session is too long. Compact it (/compact in OpenCode) or start a fresh one.
   f. A test or a command fails: show the exact command and its output, and say what you think is wrong in one sentence.
   g. Something else: say so plainly.
2. Give me ONE next step to try, as a command or a sentence I can type. If it is a code change, describe it and wait for my yes.
3. If you do not know, say "I don't know" and suggest asking a mentor. Never guess at a fix to a statistic.
```

**What good output looks like:** One sentence naming the problem (for example "429 on the per-minute token limit") and ONE next step you can type. It does not start editing code.

**Works the same in every agent.** Nothing here needs subagents or a question tool.
