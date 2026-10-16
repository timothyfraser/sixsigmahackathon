# 🚀 Start here: your first hour with the superagent

Read this together as a team before you build anything. It takes 10 minutes. ☕

**Jump to:** [💡 The idea](#-the-idea) · [🧰 Step 1: Set up](#-step-1-set-up-once) ·
[🧠 Step 2: Plan](#-step-2-plan-on-your-strongest-model) · [🛠️ Step 3: Build](#%EF%B8%8F-step-3-switch-to-a-cheaper-model-and-build) ·
[🔁 Between tasks](#-between-tasks) · [🌐 Deploy](#-deploy-early) · [🆘 Stuck?](#-when-it-goes-wrong) ·
[🎛️ Models](#%EF%B8%8F-which-model-in-which-agent) · [🧩 Templates](#-templates-the-agent-uses) · [⏱️ Sample hour](#%EF%B8%8F-a-sample-first-hour)

---

## 💡 The idea

**Vibe-code well so you can focus on the engineering.** 👷 You are the engineer: you decide what is
correct, and a test proves it. The agent does the typing.

You need **one command: `/superagent`**. It writes your spec, asks your design questions, plans,
and builds one task at a time. It finds every other skill and template on its own.

The routine has two halves, because good models are expensive:

| | Model | Why |
|---|---|---|
| 🧠 **Plan** | your strongest | a smart model makes the decisions that matter |
| 🛠️ **Build** | a cheaper one | the plan is written down, so a cheaper model can follow it |

---

## 🧰 Step 1: Set up once

1. 🤖 **Get an agent:** Claude Code, Codex, Cursor, GitHub Copilot or OpenCode.
   No paid plan? [OpenCode + a free Google key](opencode.md) costs $0. Compare them: [agents.md](agents.md).
2. 📂 **Fork or clone this repo** and open your agent inside the repo folder.
3. ✅ **Say yes to the prompts.** Claude Code asks you to *trust this folder*, approve its tool servers and
   install its plugins. Say yes to all three. (Until you trust the folder, every command asks permission.)
4. 🔌 **Let it install its tools.** On your first `/superagent` it offers Playwright 🌐 (a browser it can
   see), Context7 📚 (current library docs), impeccable 🎨 (good design) and motion.dev ✨ (animation).
   Say yes. Details: [setup.md](../.claude/skills/superagent/setup.md).

---

## 🧠 Step 2: Plan on your strongest model

**1. Switch up.** Claude Code: `/model opus`. Other agents: [see the models table](#%EF%B8%8F-which-model-in-which-agent).

**2. Type `/superagent` and describe your app.** 📝 **More detail = better results.** Say:

- 👤 **who** uses it, and the decision they make;
- 📊 **what data** they have (columns, units, how often);
- 🧮 **which statistic** answers their question;
- 🖥️ **what they see**: every page, chart and button;
- 🧱 **your stack** (Python or R; API, dashboard or library).

```text
/superagent A quality engineer on a bolt-tightening line uploads torque readings as a CSV
(columns: subgroup, value, in N-m; 5 readings per subgroup, one subgroup per hour).
We use an X-bar and R chart, plus Cp and Cpk against a spec of 25 +/- 1.5 N-m.
Three pages: (1) Upload: drop a CSV and see a preview table; (2) Control charts: X-bar and R
charts with limits, out-of-control subgroups in red, and "in control: yes/no" at the top;
(3) Capability: Cp, Cpk, a histogram with the spec limits, and one plain sentence on whether
the process is capable. A Python FastAPI app with a simple web page.
```

**3. Read what it gives back, together.** 👀

| The agent… | You check… |
|---|---|
| 📝 fills in [`SPEC.md`](../SPEC.md) and shows the changes | the user, the statistic, the known-answer numbers |
| ❓ asks every open decision at once, as multiple choice | answer them all in one reply (its pick comes first) |
| 🗺️ writes `docs/plan.md`: tasks, files, tests, formulas | every formula. Fixing a sentence now is free; fixing code later is not |

✅ **Planning is done** when every formula and its known-answer test are written down, and nobody on
the team is confused.

---

## 🛠️ Step 3: Switch to a cheaper model and build

**1. Switch down.** Claude Code: `/model sonnet`.

**2. Type:**

```text
/superagent keep going
```

**3. Watch it orchestrate.** 🎼 For each task in [`CONTRACT.yaml`](../CONTRACT.yaml) it:

1. 👷 hands the task to the **implementer** helper agent: tests first, then code, then run them;
2. 🔍 hands any statistics to the **stats-reviewer** helper agent: every number vs. your known answer;
3. 🙋 shows you the results and **asks before it commits**.

**Your job:** read the `STATISTICS:` lines and the PASS/FAIL table, then read the diff before you say
yes. ❗ If nobody can explain a number, the task is not done.

🆓 **Free Google tier (OpenCode)?** One agent at a time. Plan on `google/gemini-3.5-flash`, build on
`google/gemini-3.1-flash-lite`. More in [opencode.md](opencode.md).

---

## 🔁 Between tasks

- 🧹 **Compact or start fresh.** `/compact` shrinks a long chat; `/clear` (Claude Code) or `/new`
  (OpenCode, Codex) starts over. Your files hold the memory, not the chat. Long chats make any model
  slower and sloppier.
- 🧭 **Lost?** Type `/superagent where are we`.
- ⬆️ **Switch back up** only for a hard design plan, or a bug the cheaper model failed twice. Then
  switch down again.

---

## 🌐 Deploy early

As soon as the app runs on your laptop, type `/superagent deploy`. 🚢 A tool that is live halfway through
the event leaves time to fix what breaks. 🔑 You paste the publisher key (handed out at the event) into
your GitHub repo's secrets. Never into the chat or a file.

---

## 🆘 When it goes wrong

| 😬 You see | 👉 Do this |
|---|---|
| the same error three times | `/clear`, then give it the error and ask for ONE small fix |
| a rate-limit or quota message | wait a minute and type `continue`, or switch models |
| it wants to edit files outside the task | say no, and ask why |
| a number you cannot explain | "Show me this calculation by hand on our known-answer data." |
| "done" with no test output | not done: "Run the definition of done and paste the output." |

---

## 🎛️ Which model, in which agent

| Agent | 🧠 Plan on | 🛠️ Build on | How to switch |
|---|---|---|---|
| Claude Code (Pro or Max) | Opus | Sonnet | `/model opus`, then `/model sonnet` |
| Codex (ChatGPT plan) | the strongest model, high reasoning | a cheaper model or lower reasoning | `/model` |
| Cursor | the strongest in the menu | a cheaper one, or Auto | the model menu in the chat box |
| GitHub Copilot | the strongest your plan offers | a cheaper one, or Auto | the model menu in the chat box |
| OpenCode + free key | `google/gemini-3.5-flash` | `google/gemini-3.1-flash-lite` | `/models` |

No `/superagent` command in your agent? Paste the starter prompt from [prompts-starter.md](prompts-starter.md). Same result.

---

## 🧩 Templates the agent uses

The agent picks your starting template, and you can look too. 🔎 Building something more specific? Find
examples or templates you like and hand them to the agent.

| You want to build… | Starter |
|---|---|
| 🐍 a Python API | [`demos/fastapi/`](../demos/fastapi/) |
| 📐 an R API | [`demos/plumber/`](../demos/plumber/) |
| 🖥️ a web front end | [`demos/reactfront/`](../demos/reactfront/) |
| 📊 a dashboard | [`demos/shinyapp/`](../demos/shinyapp/) |
| 📦 a reusable library | [`demos/pypackage/`](../demos/pypackage/) or [`demos/rpackage/`](../demos/rpackage/) |

Blank SPEC and CONTRACT copies: [`.claude/templates/`](../.claude/templates/README.md).

---

## ⏱️ A sample first hour

| ⏰ Min | Model | You type | You check |
|---|---|---|---|
| 0-10 | any | open the repo, say yes to the prompts | the agent can see `SPEC.md` |
| 10-20 | 🧠 strong | `/superagent` + your detailed description | the `SPEC.md` changes |
| 20-30 | 🧠 strong | your answers, in one reply | every formula in `docs/plan.md` |
| 30-55 | 🛠️ cheap | `/superagent keep going` | tests pass, review all PASS |
| 55-60 | 🛠️ cheap | `yes` to the commit, then `/clear` | one task done 🎉 |

---

**Two rules, all event long:** 🔓 everything you ship is public and reproducible, and 🧠 you can
explain every number your tool prints. Have fun! 🎯
