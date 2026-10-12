# Starter prompts for any AI agent

Seven prompts that take a team from a description of their app to a checked-in, tested task:
**spec** (the agent writes `SPEC.md` from your description), **plan, decide, build, review, check in**, and **stuck** for when something goes wrong. They work
pasted into any coding agent: OpenCode, Claude Code, Codex, GitHub Copilot agent mode, and the
Gemini or Antigravity CLI.

- **OpenCode** (the free path, see [`opencode.md`](opencode.md)): you do not paste anything. Each
  prompt is a slash command in this repo: type `/spec <your description>`, `/plan`, `/decide`, `/build H-03`, `/review H-03`,
  `/checkin H-03` or `/stuck`. Each command is set to the free Gemini model that suits its job:
  `/plan` and `/decide` use `gemini-3.5-flash` (the better thinker, about 20 requests a day), the
  others (including `/spec`) use `gemini-3.1-flash-lite` (the workhorse, about 500 a day). If a command's model is out of
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
- **The order:** `spec` once, then `plan` once, `decide` when a choice is open, then for each task `build`, then
  `review` **in a fresh session**, then `checkin`. Use `stuck` whenever you need it.
- **A per-minute limit (`429`) mid-answer?** Wait one minute and type `continue` in the **same**
  session. A fresh session repeats every step it already did and hits the same limit.
- **One agent at a time per key.** On a free Google key, two agents working at once run out of the
  per-minute allowance. Teams work in parallel across people, each on their own key.

The examples below use a made-up bolt-torque line (X-bar and R chart, subgroups of 5, plus Cpk). They
show the shape of good output; they are not hints about the event prompts.


## Start here: Write our SPEC  (OpenCode: `/spec <your description>`)

**When:** First, before `/plan`. You do not fill in `SPEC.md` by hand and you do not need to read all of it. Describe your app in a few sentences (who uses it, what data they have, what statistic answers their question, what they should see) and the agent writes the `FILL IN` lines for you.

**Before pasting:** Replace `$ARGUMENTS` on the first line with your description. In OpenCode, type it after the command: `/spec a quality engineer on a bolt line uploads torque readings; X-bar and R chart, subgroups of 5; Cp and Cpk; they see in control yes/no`.

<!-- prompt: spec -->
```text
My team's description of our app: $ARGUMENTS

You are writing our SPEC, not coding. Do not create or edit any file except SPEC.md.

1. Read SPEC.md completely. Do not search or re-read a file.
2. From my description above, update ONLY the lines of SPEC.md that say FILL IN: the user, the decision they make, the inputs, the method and why it fits, the known-answer check, the stack, the starting demo, what the user sees, the datasets, and anything else. Keep the headings, tables, rubric text and examples as they are. Replace each FILL IN with a real answer. Do not copy the Example text unless it truly is our app.
3. Never invent the team name, the track, the chosen prompt or the repo address. If my description does not give a fact you need, ask me ALL your questions in ONE numbered message (at most 5 questions, each with at most 4 numbered options; mark the one you recommend and say why in one line) and wait before you edit.
4. For the known-answer check, work the numbers out by hand in your message (show the arithmetic) and put the data and the expected result in SPEC.md. Never make up an answer.
5. When SPEC.md is saved, run git diff SPEC.md, show me the diff, and say in two sentences what changed. Then stop and wait: we will read the diff together and tell you what to fix.

We are beginners: short sentences, and explain any jargon in a few words. When SPEC.md is updated, say SPEC WRITTEN and stop.
```

**What good output looks like:** A diff of `SPEC.md` where only the former `FILL IN` lines changed, each with a concrete answer, a hand-worked known answer in section 4 (data, arithmetic, expected numbers) and no invented team name or prompt. Read the diff with your team. Anything wrong or vague: say what to change and ask again. `grep -c "FILL IN[.,]" SPEC.md` should print 0 when you are done.

**Works the same in every agent.** Nothing here needs subagents or a question tool.


## 1. Write the plan  (OpenCode: `/plan`)

**When:** Once `SPEC.md` has no `FILL IN` lines left (the Write our SPEC prompt above gets you there), and before anyone writes code. Start a fresh session for it.

<!-- prompt: plan -->
```text
You are planning, not coding. Do not create or edit any file except docs/plan.md. This model allows only 5 requests a minute, so use as few steps as you can.

1. In one step, read SPEC.md, CONTRACT.yaml and docs/plan.md (if it exists) completely, before you say anything. Do not search, list folders or re-read a file.
2. In one sentence each, state: the user, the question the tool answers, every statistic, and the formula for each statistic (write the formula out). If SPEC.md leaves any of these unclear or still says FILL IN, stop and ask me before going on. A known-answer check with no concrete numbers (the input data AND the expected values) counts as FILL IN: stop, and offer to work out the numbers with me.
3. List every design decision that is still open (data shape, where the data comes from, what the function or API returns, what the user sees, what counts as "in control" or "capable"). Ask them ALL in this ONE message, as a numbered list: at most 5 questions, each with at most 4 numbered options; mark the option you recommend and say why in one line. Then stop and wait. I will answer in one reply, for example "1-1, 2-3, 3-1". If nothing is open, say so and go straight to step 4.
4. In your next turn, after my answers, write docs/plan.md: a numbered list of tasks, each mapped to one task id from CONTRACT.yaml (use the real ids; never invent one). For each task give: the files it may touch (from its owns list), the test that proves it (the known answer from SPEC.md section 4, AND a degenerate case such as constant data), and a time estimate. Every statistic comes first, each with its formula written out, then the tool around it, then the page or chart. Nothing about styling until the numbers are proven.
5. Under the tasks, list the decisions I made in step 3, one line each.
6. End with the three biggest risks and what we will do about each.

Keep docs/plan.md under 60 lines. We are beginners: short sentences, and explain any jargon in a few words. When docs/plan.md is written, say PLAN WRITTEN and stop.
```

**What good output looks like:** The agent writes four one-sentence statements (user, question, statistic, formula) and asks you 3 to 5 multiple-choice questions **in one message**. You answer them all in one reply (for example `1-1, 2-3, 3-1`), and it writes `docs/plan.md`. For a bolt-torque example (X-bar and R chart, subgroups of 5, plus Cpk), a good first task reads like: *"1. H-03, `app/qc.py` and `tests/`: `xbar_r_limits()` and `cpk()`; test a hand-worked example and constant data (Cpk must be undefined, not a number). 30 min."* Statistics first, styling nowhere.

**Answer in one reply,** question number then option number: `1-1, 2-3`.


## 2. Make the design decisions  (OpenCode: `/decide`)

**When:** Whenever a choice is still open: the shape of the data, what the tool returns, what the user sees, which run rules count as "out of control". `/plan` asks the first round; run this for anything left over.

<!-- prompt: decide -->
```text
You are helping my team make design decisions. Do not write code. The only file you may edit is docs/plan.md. This model allows only 5 requests a minute, so use as few steps as you can.

1. In one step, read SPEC.md, CONTRACT.yaml and docs/plan.md (if it exists). Do not search or re-read a file.
2. Find the design decisions that are still open: anything SPEC.md or docs/plan.md leaves undecided or marks as a question, and anything two tasks disagree about.
3. Ask them ALL in this ONE message, as a numbered list: at most 5 questions (if more are open, pick the ones that change the statistic or the inputs), each with at most 4 numbered options. Mark the option you recommend and give the reason in one line, tied to SPEC.md (the user, the statistic, or the rubric). Then stop and wait. I will answer in one reply, for example "1-1, 2-3, 3-1".
4. In your next turn, after my answers, add or update a "Decisions" section in docs/plan.md: one line per decision, what we chose and why. If an answer changes SPEC.md, tell me the exact line to change; do not edit SPEC.md yourself.
5. Say DECISIONS RECORDED and stop.
```

**What good output looks like:** All the open questions in one numbered list, each short:

```
1. How should the tool receive the torque readings?
   1. CSV upload, columns subgroup and torque_nm   (recommended: matches SPEC.md)
   2. Paste a table into a text box
   3. Typed into a form
2. What should the tool say when a point is outside the limits?
   1. "Stop the line: yes" in red   (recommended: the decision in SPEC.md)
   2. Only a red point on the chart
```

You answer every question in one reply, for example `1-1, 2-1`. Asking them all at once saves
requests: the free planning model allows only 5 a minute. At the end `docs/plan.md` has a **Decisions** section, one line per answer.

**Answer in one reply,** question number then option number: `1-1, 2-3`.


## 3. Build one task  (OpenCode: `/build H-03`)

**When:** For exactly one task from `CONTRACT.yaml`, after the plan exists. Start a fresh session for every task.

**Before pasting:** Replace `$1` on the first line with your task id, for example `H-03`.

<!-- prompt: build -->
```text
Task id: $1
If the task id above is blank, list the todo tasks in CONTRACT.yaml and ask me which one. Do not guess.

You build exactly this ONE task from CONTRACT.yaml. You are the IMPLEMENTER only. Do not launch subagents or any other agent, and do not review your own work: the review is a separate step that I run in a fresh session (/new, then /review with this task id).

1. Before anything else, read SPEC.md completely (section 4 is the method and the known-answer check), docs/plan.md if it exists, and this task's block in CONTRACT.yaml.
2. In one sentence, restate the statistic this task computes and its formula, exactly as SPEC.md section 4 states it. Stop and ask me if SPEC.md section 4 still says FILL IN, or if its known-answer check has no concrete numbers (the input data AND the expected values). A known-answer check with no concrete numbers counts as FILL IN. Never invent a statistic or a known answer.
3. If you do not know my name for the owner field, ask me once. Get the time by running this command: date "+%Y-%m-%d %H:%M" (if it fails, run: python -c "import datetime; print(datetime.datetime.now().strftime('%Y-%m-%d %H:%M'))"). Load the contract-ledger skill and check the task out: status: in_progress, owner, and started_at = the time the command printed, pasted (never a time you made up). Never delete a field. Quote any value that contains a colon.
4. If the task computes a statistic, load the stats-first-steering skill. Write the tests first, then the code:
   - a known-answer test whose data and expected numbers are copied from SPEC.md section 4, never made up;
   - a degenerate case (constant data, or n = 1). With zero spread, a capability index such as Cp or Cpk is undefined: the code must raise a clear error, or return NaN or None with a message. inf, 0 or any other confident number is wrong, and a test that accepts one is wrong.
5. Deliver EVERY statistic SPEC.md names, not just the first one. For an X-bar and R chart that means all of these:
   - X-bar chart limits (constant A2);
   - R chart limits (constants D3 and D4);
   - sigma-hat = R-bar/d2 for Cp and Cpk. Never use the overall standard deviation: that gives Pp and Ppk, a different statistic;
   - an out-of-control flag for each subgroup.
6. Stay inside the task's owns list:
   - Edit only the paths in its owns list, plus this task's block in CONTRACT.yaml.
   - Never delete, move or rename a file. Never create a file outside the owns list; scratch checks go in tests/ (or another folder on the owns list), never at the repo root.
   - Every third-party package you import (numpy, pandas, scipy, ...) goes into the requirements file (for example app/requirements.txt) in the same step. If that file is not on the owns list, stop and tell me the exact line to add.
   - Use absolute package imports (from app.qc import ...), never relative ones (from .qc import ...). The app and every script must start from the repo root with one command.
   - If you need any other file, stop and ask me.
7. Never run a server, testme.sh or any other long-running command in the foreground: it hangs the session. Start it in the background with a time limit (for example: timeout 120 bash app/testme.sh &), or ask me to run it. Stop only the process you started, by its PID. Never kill processes by name (taskkill /IM, pkill, killall, Stop-Process -Name).
8. Work in small steps. After each step run the tests and read the real output.
9. Run the task's definition_of_done exactly as written. For an API or app task, start the app in the background (step 7), call the endpoint (or open the page) on one data/ file, and paste the real response.
10. If you get a 429, quota or rate-limit error, stop and tell me. Do not retry in a loop.
11. Do not commit, do not push, do not check the task in, and do not start another task.

End your final message with these parts, pasted, not summarized:
STATISTIC: the one sentence from step 2
STATISTICS: every statistic SPEC.md names, one per line, with its value on the known-answer data. A missing one means the task is NOT DONE.
FILES: every file you created or changed
RUN: the one command, run from the repo root, that starts the app
TESTS: the test command and its real output
DEFINITION OF DONE: the definition_of_done command and its real output
NEXT: type /new, then /review with this task id
```

**What good output looks like:** The task is checked out in `CONTRACT.yaml` with `owner` and `started_at` filled in (`started_at` is the real time, from the `date` command). The final message starts from the statistic in `SPEC.md` and ends with real output, not a claim:

```
STATISTIC: X-bar and R chart (subgroups of 5, limits from R-bar with A2, D3, D4), plus Cp and Cpk with sigma-hat = R-bar / d2
FILES: app/qc.py, tests/test_qc.py, CONTRACT.yaml
TESTS: pytest tests
  2 passed in 0.21s
DEFINITION OF DONE: pytest tests  ->  2 passed
NEXT: type /new, then /review H-03
```

If the last message only says "DONE", ask for the test output. If the statistic is not the one in
`SPEC.md` section 4, stop it there: the code is wrong however many tests pass.

**Build and review are separate on purpose.** An agent that reviews its own work in the same session passes its own mistakes. Start a fresh session (`/new`) and run the review prompt next.


## 4. Review a statistic  (OpenCode: `/review H-03`)

**When:** Right after `/build` on any statistics task, in a **fresh session** (`/new`, then `/review H-03`), and again after any change to the statistic. Always before `/checkin`.

**Before pasting:** Replace `$1` on the first line with your task id, for example `H-03`.

<!-- prompt: review -->
```text
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
```

**What good output looks like:** A table you could show a judge. For the bolt-torque example (mean of subgroup means 10.50 N·m, average range 1.00 N·m, n = 5, spec limits 8 to 12 N·m):

```
check                 expected   got     
X-bar UCL             11.077     11.077  PASS
Cpk                   1.163      1.163   PASS
constant data         error/NaN  error   PASS
OVERALL: PASS
```

Constant data has zero spread, so Cp and Cpk are undefined. A tool that prints `inf` (or any
number) for them fails the review, even if a test accepts it.

**Works the same in every agent.** The reviewer runs in its own fresh session and needs no subagents.


## 5. Check the task in  (OpenCode: `/checkin H-03`)

**When:** When the build passed, the review passed, and someone on the team has read the diff.

**Before pasting:** Replace `$1` on the first line with your task id, for example `H-03`.

<!-- prompt: checkin -->
```text
Task id: $1
If the task id above is blank, use the task in CONTRACT.yaml that is in_progress; if there is none, or more than one, ask me which.

Check this task in, following the contract-ledger skill (.claude/skills/contract-ledger/SKILL.md).

1. Run the task's definition_of_done exactly as written in CONTRACT.yaml. Paste the command and its real output. Never swap in a different command.
2. If it failed, stop: the task is not done. Leave status: in_progress, write what is missing in result, and tell me.
3. If it passed, change exactly two lines in this task's block in CONTRACT.yaml, one small edit each (the two lines are not next to each other, so never try to replace both in one edit): the status line becomes status: done, and the result line becomes result: "one line saying what exists now and the check that proved it". Do not rewrite or replace the block: owner, started_at, owns, notes and definition_of_done stay exactly as they are. In every edit, the new text keeps every line of the old text; only the status value and the result value change. If started_at is blank, run date "+%Y-%m-%d %H:%M" and paste what it prints (never a time you made up). Quote any value that contains a colon.
4. Check the ledger: run python -c "import yaml; yaml.safe_load(open('CONTRACT.yaml'))" and git diff CONTRACT.yaml. If any line other than status and result changed, put it back before going on.
5. Show me git status, the diff, and the exact commit command, staging files by name (the task's owned files plus CONTRACT.yaml; never git add . or git add -A). Then stop: end your message with the question "Commit these files? (yes/no)" and run nothing else. Commit only after I answer yes in my next message. Never push.
6. After the commit, paste the definition_of_done output again and the commit hash.
```

**What good output looks like:** The `definition_of_done` output pasted, the task's block in `CONTRACT.yaml` showing `status: done`, a one-line `result` and `owner`/`started_at` still filled in, the diff, and a `git add` that names files, ending with "Commit these files? (yes/no)". It commits only after you type yes. In OpenCode the repo's `opencode.json` also makes OpenCode ask before any `git commit` or `git push`: choose **allow once** only after you have read the diff.

**Works the same in every agent.** Nothing here needs subagents or a question tool.


## 6. When you are stuck  (OpenCode: `/stuck <paste the error>`)

**When:** Any time: a `429` or "quota" error, the agent says nothing at all, the same error three times, or answers that get slow and vague.

**Before pasting:** Replace `$ARGUMENTS` on the first line with the error text or a one-line description of what you see.

<!-- prompt: stuck -->
```text
I am stuck. What I see (the error text or the symptom): $ARGUMENTS

Diagnose before doing anything else. Do not edit any file in this step.

1. Restate the problem in one sentence and say which of these it is:
   a. 429, RESOURCE_EXHAUSTED, "quota" or "rate limit": the free key's per-minute or per-day allowance is used up. Fixes, in this order: for a per-minute limit (the error says "retry in" some seconds), wait one minute, then type continue in the SAME session (do not start a new session: a new one repeats every step it already did and hits the same limit); for a daily limit, step down the model ladder (another model ending in -flash for planning and thinking, the other model ending in -flash-lite for building); a teammate's key from their own Google account; and only if your employer allows third-party AI vendors, a Zen model whose name ends in -free, or GitHub Copilot. After switching models, if a slash command still fails the same way, paste that command's prompt from docs/prompts-starter.md instead, because each slash command asks for a fixed model.
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
