![](docs/images/banner_thin.png)

# 🎯 Cornell Six Sigma Hackathon

*Tackle real-world quality control problems drawn from industrial engineering,
healthcare systems, and energy systems!*

Your team picks a prompt, invents the data, and ships a working quality-control
tool. **👉 [Register on Devpost](https://six-sigma-hackathon.devpost.com/)**
(required, even if you don't have a team yet).

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

**1. Pick your stack.** Copy one template folder into your own repo.

| You want to build… | Start from |
|---|---|
| a Python API | [`demos/fastapi/`](demos/fastapi/) |
| an R API | [`demos/plumber/`](demos/plumber/) |
| a web front end | [`demos/reactfront/`](demos/reactfront/) |
| a dashboard | [`demos/shinyapp/`](demos/shinyapp/) |
| a reusable library | [`demos/pypackage/`](demos/pypackage/) or [`demos/rpackage/`](demos/rpackage/) |

**2. Write your SPEC and CONTRACT first.** Copy [`kit/`](kit/README.md) into
your repo: a `SPEC.md` (what you are building and for whom), a `CONTRACT.yaml`
task list your team and your agents check tasks in and out of, and a
`CLAUDE.md` / `AGENTS.md` so your AI assistant starts oriented.

**3. Deploy with one workflow.** Drop the matching workflow from
[`demos/positconnect/`](demos/positconnect/README.md) into your repo and it
publishes your tool to the course **Posit Connect** server. Publisher
credentials are handed out at the event.

---

### Quick Links

- [🗓️ Schedule of Events](docs/schedule.md)
- [💬 Prompts](docs/prompts.md) — *revealed at the start of the event*
- [🔢 Evaluation Criteria](docs/criteria.md)
- [📚 Resources for Building Your Tool](docs/resources.md)
- [🧰 Starter Templates](demos/README.md)
- [🤖 Agent context bundle](CLAUDE.md) — read this before you start building
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
- [`.claude/skills/`](.claude/skills/) — `connect-publish`,
  `fastapi-react-scaffold`, `plumber-react-scaffold`, `contract-ledger`,
  `od-setup`, `od-pull`, and
  [`stats-first-steering`](.claude/skills/stats-first-steering/SKILL.md)

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
