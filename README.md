![](docs/images/banner_thin.png)

# 🎯 Cornell Six Sigma Hackathon

*Tackle real-world quality control problems drawn from industrial engineering,
healthcare systems, and energy systems!*

Your team picks a prompt, invents the data, and ships a working quality-control
tool. **👉 [Register on Devpost](https://six-sigma-hackathon.devpost.com/)**
(required, even if you don't have a team yet).

> ### 📘 New here? Read the [step-by-step start tutorial](docs/start.md) first
> Ten minutes, for the whole team: set up your agent, **plan with `/superagent` on your
> strongest model**, then **switch to a cheaper model** that builds and checks each task with
> helper agents. **[→ docs/start.md](docs/start.md)**

---

### 📍 When & where

| | 🏫 On-campus (24 hours) | 🌐 Virtual DL Challenge (7 days) |
|---|---|---|
| **Who** | on-campus students (required unless excused) | distance-learning students, and anyone who can't attend in person |
| **Runs** | Fri Oct 16, 3 PM → Sat Oct 17, 3 PM ET | Fri Oct 16, 3 PM → Fri Oct 23, 3 PM ET |
| **Where** | Upson Hall 116 | online |
| **Submissions due** | Sat Oct 17, **1 PM ET** sharp | Fri Oct 23, **3 PM ET** |
| **Showcase** | Sat Oct 17, 2-3 PM (must attend) | — |

Submit on **[Devpost](https://six-sigma-hackathon.devpost.com/)**: your repo
link plus a demo. Full run of show: [🗓️ Schedule](docs/schedule.md).

---

### 🚀 Start here in 3 steps

The short version is below. The full walkthrough, with the plan-then-switch routine and a sample
first hour, is the **[start tutorial](docs/start.md)**.

**1. Get an agent.** Any one of these works: Claude Code, OpenCode, Cursor,
Codex, GitHub Copilot, or the Gemini / Antigravity CLI. **No paid AI plan?**
[OpenCode with a free Google AI Studio key](docs/opencode.md) costs $0. How to
pick, and what each costs: [docs/agents.md](docs/agents.md).

**2. Fork or clone this repo, open your agent in it, and type `/superagent`.**
After it, write a few sentences about your app: who uses it, what data they
have, which statistic answers their question, and what they see. For example:

```text
/superagent A line supervisor uploads bolt-torque readings and sees whether the
process is in control and whether it is capable.
```

Plan on your strongest model (Claude Code: `/model opus`), then switch to a cheaper one
(`/model sonnet`) and type `/superagent keep going` to build. Why, and how in every agent:
[the start tutorial](docs/start.md).

That is the whole job. The agent writes your [`SPEC.md`](SPEC.md), asks your
design decisions as multiple-choice questions, plans, builds one task at a time
from [`CONTRACT.yaml`](CONTRACT.yaml), and checks the statistics. It also offers
to install its tools (Playwright, Context7, impeccable, motion.dev); say yes. You
never need to name a skill. Does your agent have no slash commands? Paste the one
starter prompt from [`docs/prompts-starter.md`](docs/prompts-starter.md) instead.

**3. Deploy with one workflow.** Copy the matching workflow from
[`.claude/skills/connect-publish/workflows/`](.claude/skills/connect-publish/workflows/)
into your repo's `.github/workflows/` and it publishes your tool to the course
**Posit Connect** server. Which file fits your app, and which script goes with
it: [`.claude/skills/connect-publish/README.md`](.claude/skills/connect-publish/README.md).
Publisher credentials are handed out at the event.

#### Templates the agent uses

The agent picks your starting template. You can look too: each is a folder to
copy into your own repo.

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

### Quick Links

- [🗓️ Schedule of Events](docs/schedule.md)
- [💬 Prompts](docs/prompts.md) — *revealed at the start of the event*
- [🔢 Evaluation Criteria](docs/criteria.md)
- [📚 Resources for Building Your Tool](docs/resources.md)
- [🧰 Starter Templates](demos/README.md)
- [🤖 Agent context bundle](CLAUDE.md) — type `/superagent` and your agent reads it for you
- [⁉️ FAQ](#️-frequently-asked-questions)

---

### 💡 The Challenge

Your team tackles one real-world quality control and reliability problem.

- 🧩 Prompts are released **at kickoff** — each tied to a dataset you design and
  build yourself
- 📊 **The statistics are the graded core.** Statistical process control,
  process capability, reliability modeling, failure analysis. The app is the
  delivery vehicle for the analysis, not the point
- 🧱 Ship **one** of: an R package or Python library, a public REST API
  (FastAPI or plumber), or a dashboard / web app (React or Shiny)
- 🚀 Deploy it live to the course **Posit Connect** server
- 🔢 Every project is scored 0-100 by the event staff.
  [Read the criteria](docs/criteria.md)

---

### 🤖 Build with AI — bring your own agent

AI-assisted development is **expected and encouraged**. Use whatever you already
have. The skill being tested is steering a capable assistant toward
statistically correct work — which is exactly the skill this course is about.

- [🧠 AI coding agents](docs/agents.md) — the popular ones, and how to pick
- [🎙️ Tools](docs/tools.md) — Wispr Flow (talk to your agent) and Open Design
- [`CLAUDE.md`](CLAUDE.md) / [`AGENTS.md`](AGENTS.md) — what the event is, the
  repo map, the deploy target, the four-script contract
- [`.claude/skills/superagent/`](.claude/skills/superagent/SKILL.md) — the one
  skill you need: type `/superagent` and it routes to every other skill and
  template for you. They all live in [`.claude/skills/`](.claude/skills/) if you
  want to read them

Two rules: everything you ship is **public and reproducible**, and you must be
able to **explain every number your tool prints**.

---

### ⁉️ Frequently Asked Questions

- **Who can participate?** Cornell students who are (a) in the Systems
  Engineering MEng/MS program, OR (b) enrolled in SYSEN 5300 / MAE 5390, OR
  (c) enrolled in SYSEN 5900. Teams of **2 to 5**.

- **On-campus or virtual?** On-campus students do the 24-hour event in Upson
  Hall 116 (required unless excused). Distance-learning students, and anyone
  who can't attend in person, do the 7-day Virtual DL Challenge.
  [Dates above](#-when--where).

- **What are the deadlines?** On-campus: submissions due Sat Oct 17, 1 PM ET
  sharp; showcase Sat Oct 17, 2-3 PM (must attend). DL: submissions due
  Fri Oct 23, 3 PM ET.

- **What do we win?** On-campus winners: dinner for the team at the Statler
  Dining Room. DL winners: bragging rights — infamy for all time.

- **Do I need Six Sigma experience?** No. Trainings are provided during the
  event, and many of the analyses can be learned in a few minutes. The
  [course textbook](https://timothyfraser.com/sigma/) is open to everyone.

- **Do I have to be a coding wizard?** No. Some prior experience in R or Python
  is enough, and AI assistants close a lot of the gap. A winning project is a
  smart, correct solution to a quality-control problem — not fancy code.

- **What if I can't find team members?** Register on
  [Devpost](https://six-sigma-hackathon.devpost.com/) anyway; we will match
  you with a team.

- **Do I have to be there the whole 24 hours?** A successful team works most of
  it. Step out, sleep, stagger breaks — just keep someone on the team present.

- **Can a teammate join the on-campus event remotely?** No. Anyone who can't
  attend in person does the Virtual DL Challenge instead.

- **What do we submit?** On Devpost: a link to your public GitHub repository
  and a demo of a working prototype, deployed live to Posit Connect. At least
  one team member needs a working (non-Cornell) GitHub account.

- **What software do I need?** Install R or Python and at least one coding
  interface (RStudio, VSCode, Cursor, Positron, ...) **before** the event
  starts. If you plan to use an AI assistant, set it up beforehand too.

- **What language should I use?** R, Python, or both. Code must be fully
  reproducible and public.

- **How are products evaluated?** Scored 0-100 by event staff on
  [the criteria](docs/criteria.md): tool implementation (50), tool design
  (25), documentation (25).

---

### 👥 How to Join

[Register on Devpost](https://six-sigma-hackathon.devpost.com/) — registration
is required. Form a team of 2 to 5, or register solo and we'll match you.

---

### 📚 Sign Up to Mentor

Faculty, postdocs, PhD students, and developers are welcome as mentors.
[Details here](docs/mentors.md).

---

![](docs/images/banner_icons.png)
