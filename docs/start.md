# Start here: your first hour with the superagent

A step-by-step tutorial for your whole team. Read it together before you build anything (10 minutes).

**Contents:** [The idea](#the-idea) · [1. Set up once](#1-set-up-once-10-minutes) ·
[2. Plan on your strongest model](#2-plan-on-your-strongest-model-20-30-minutes) ·
[3. Switch to a cheaper model to build](#3-switch-to-a-cheaper-model-to-build) ·
[4. Between tasks](#4-between-tasks) · [5. Deploy early](#5-deploy-early) ·
[6. When it goes wrong](#6-when-it-goes-wrong) · [Which model, in which agent](#which-model-in-which-agent) ·
[A sample first hour](#a-sample-first-hour)


### 🚀 Start here in 3 steps

## Idea: Use Effective Vibecoding so You can focus on **Engineering**

You are the engineer. The agent types. You decide what is correct, and a test proves it.

You only need one command: **`/superagent`**. It reads your project files, writes your spec, asks
your design questions, plans, and builds one task at a time. It loads every other skill and template
by itself. You never need to know their names.

The routine has two halves, because good models are expensive:

1. **Plan** on your strongest model. Planning is where a smart model pays off.
2. **Build** on a cheaper model. The plan is written down, so a cheaper model can follow it.
   It hands each task to a helper agent (a "subagent") and checks the statistics with another one.

## 1. Set up once (10 minutes)

1. **Get an agent.** Any one: Claude Code, Codex, Cursor, GitHub Copilot, or OpenCode.
   No paid plan? Use [OpenCode with a free Google key](opencode.md). Prices: [agents.md](agents.md).
2. **Fork or clone this repo**, then open your agent inside the repo folder.
3. **Claude Code only:** it asks "Do you trust the files in this folder?" Say **yes**. Until you do,
   it ignores this repo's settings, and every command asks for your permission. Then it asks to
   approve the project's tool servers (Playwright and Context7) and to install plugins
   (impeccable, posit-dev). Say yes to both.
4. **Let it install its tools.** The first time you run `/superagent` it offers to set up
   Playwright (a browser it can see), Context7 (current library docs), impeccable (good UI design)
   and motion.dev (animation). Say yes. The steps are in
   [setup.md](../.claude/skills/superagent/setup.md). One step you type yourself in a terminal:
   `npx motion-ai` (only if your app will animate anything).

---

## 2. Plan on your strongest model (20-30 minutes)

**Switch to the strongest model first.** In Claude Code type `/model opus`. Other agents: see
[the table below](#which-model-in-which-agent).

**Then type `/superagent` and describe your app** in a few sentences. Say who uses it, what data
they have, which statistic answers their question, and what they see:

```text
/superagent A quality engineer on a bolt-tightening line uploads torque readings as a CSV.
We use an X-bar and R chart with subgroups of 5, plus Cp and Cpk against a spec of 25 +/- 1.5 N-m.
They see "in control: yes/no", which subgroups are out of control, Cp, Cpk and a chart.
A Python FastAPI app with one simple page.
<ADD MUCH MORE SPECIFICATIONS FOR BETTER RESULTS, eg. MULTIPLE PAGES>
```

The agent then does four things. **Stop and read each one as a team:**

| The agent... | Your job |
|---|---|
| fills in [`SPEC.md`](../SPEC.md) from your description and shows the changes | Is the user right? The statistic? The known-answer numbers? Say what to fix. |
| asks every open design decision at once, as multiple choice | Answer them all in one reply. Its recommended option is listed first. |
| writes `docs/plan.md`: each task, its files, its tests, and each formula written out | Check every formula. Fixing a sentence now is free; fixing code later is not. |
| tells you where you are and what comes next | Agree on the order. |

**You are done planning when** the plan states every formula and a known-answer test for each
statistic, and nobody on the team is confused by it.

## 3. Switch to a cheaper model to build

**Switch down.** In Claude Code type `/model sonnet`. Then type:

```text
/superagent keep going
```

Now the agent **orchestrates**. It does not write all the code itself. For each task in
[`CONTRACT.yaml`](../CONTRACT.yaml) it:

1. hands the task to the **implementer** subagent, which writes the tests first, then the code,
   and runs them;
2. hands any statistics to the **stats-reviewer** subagent, which checks every number against your
   known answer and a degenerate case (for example, all readings equal);
3. shows you the results, then asks before it commits.

**Your job while it builds:**
- Read the `STATISTICS:` lines and the review's PASS/FAIL table. If you cannot explain a number,
  the task is not done.
- Read the diff before you say yes to a commit.
- Teams of 3-5: two subagents may run at once only when their files do not overlap (for example,
  the README and the test data). The agent decides; you can ask it why.

**On the free Google tier (OpenCode):** run one agent at a time, no parallel subagents. Plan on
`google/gemini-3.5-flash`, build on `google/gemini-3.1-flash-lite`. If a step stalls, use the
by-hand commands in [opencode.md](opencode.md).

#### Templates the agent uses

The agent picks your starting template. You can look too: each is a folder to
copy into your own repo. Want to build something more specific? Find examples, templates, etc. and supply them!

| You want to build… | Starter |
|---|---|
| a Python API | [`demos/fastapi/`](demos/fastapi/) |
| an R API | [`demos/plumber/`](demos/plumber/) |
| a web front end | [`demos/reactfront/`](demos/reactfront/) |
| a dashboard | [`demos/shinyapp/`](demos/shinyapp/) |
| a reusable library | [`demos/pypackage/`](demos/pypackage/) or [`demos/rpackage/`](demos/rpackage/) |

Blank SPEC and CONTRACT copies live in
[`.claude/templates/`](.claude/templates/README.md).

---

## 4. Between tasks

- **'Compact' the Agent's Transcript or Start fresh for New Tasks.** Claude Code: `/clear`. OpenCode and Codex: `/new`. The files hold
  the memory (`SPEC.md`, `CONTRACT.yaml`, `docs/plan.md`), not the chat. A long chat makes any
  model slower and sloppier.
- **Lost? Ask it:** `/superagent where are we`. Or run the check yourself:
  `bash .claude/skills/superagent/scripts/check.sh`
- **Switch back to the strong model** only for a hard design plan or a bug the cheaper model
  failed twice. Then switch down again.

---

## 5. Deploy early

As soon as the app runs on your laptop (task H-04), type `/superagent deploy`. A tool that is live by
the middle of the event leaves time to fix what breaks. The agent sets up the deploy; **you** paste the
publisher key (handed out at the event) into your GitHub repo's secrets, never into the chat or a file.

## 6. When it goes wrong

| You see | Do this |
|---|---|
| The same error three times | Stop it. Type `/clear`, then tell it the error and ask for ONE small fix. |
| A rate-limit or quota message | Wait a minute and type `continue`, or switch to another model. |
| It wants to edit files outside the task | Say no and ask why. Each task lists the files it may touch. |
| A number you cannot explain | Do not move on. Ask: "Show me this calculation by hand on our known-answer data." |
| It says "done" with no test output | It is not done. Ask it to run the task's definition of done and paste the output. |

---


## Which model, in which agent

| Agent | Plan on | Build on | How to switch |
|---|---|---|---|
| Claude Code (Pro or Max plan) | Opus | Sonnet | `/model opus`, later `/model sonnet` |
| Codex (ChatGPT plan) | its strongest model, high reasoning | a cheaper model, or lower reasoning | `/model` opens the picker (model and reasoning effort) |
| Cursor | the strongest model in the picker | a cheaper model, or Auto | the model menu in the chat box |
| GitHub Copilot (agent mode) | the strongest model your plan offers | a cheaper model, or Auto | the model menu in the chat box |
| OpenCode + free Google key | `google/gemini-3.5-flash` | `google/gemini-3.1-flash-lite` | `/models` |

Cursor, Copilot and other agents without a `/superagent` command: paste the one starter prompt from
[prompts-starter.md](prompts-starter.md) instead. It does the same thing.

## A sample first hour

| Minutes | Model | What you type | What you check |
|---|---|---|---|
| 0-10 | any | open the repo; accept trust and tools | the agent can see `SPEC.md` |
| 10-20 | strongest | `/superagent <your app in a few sentences>` | the `SPEC.md` changes and the known answer |
| 20-30 | strongest | your answers to its questions, in one reply | `docs/plan.md`: every formula |
| 30-55 | cheaper | `/superagent keep going` | the first statistics task: tests pass, review table all PASS |
| 55-60 | cheaper | `yes` to the commit, then `/clear` | `check.sh` shows one task done |

Two rules, all event long: **everything you ship is public and reproducible**, and **you must be able
to explain every number your tool prints.**
