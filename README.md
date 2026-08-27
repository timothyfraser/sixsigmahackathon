![](docs/images/banner_thin.png)

# 🎯 Six Sigma Hackathon

A **24-hour team sprint** for Cornell Systems Engineering students. Your team
picks a prompt, invents the data, and ships a working quality-control tool.

- **Who:** on-campus Cornell students in the Systems Engineering MEng/MS program
  or enrolled in SYSEN 5300 / MAE 5390 — up to 5 per team
- **Where / when:** announced with registration
- **Submissions:** on **[Devpost](https://devpost.com/)** — the event page and
  submission instructions are shared at the event

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

Over 24 hours your team tackles one real-world quality control and reliability
problem, drawn from industry, healthcare, energy, or infrastructure.

- 🧩 Prompts are released **at kickoff** — each tied to a dataset you design and
  build yourself
- 📊 **The statistics are the graded core.** Statistical process control,
  process capability, reliability modeling, failure analysis. The app is the
  delivery vehicle for the analysis, not the point
- 🧱 Ship **one** of: an R package or Python library, a public REST API
  (FastAPI or plumber), or a dashboard / web app (React or Shiny)
- 🚀 Deploy it live to the course **Posit Connect** server — publisher
  credentials are handed out at the event
- 🔢 Every project is scored 0-100 by the event staff.
  [Read the criteria](docs/criteria.md)
- 🏆 Top team wins a prize and bragging rights

---

### 🤖 Build with AI — bring your own agent

AI-assisted development is **expected and encouraged**. Use whatever you already
have: Claude Code, Cursor, Copilot, Codex, Gemini CLI. The skill being tested is
steering a capable assistant toward statistically correct work — which is
exactly the skill this course is about.

This repo ships an agent context bundle so your assistant starts oriented:

- [`CLAUDE.md`](CLAUDE.md) / [`AGENTS.md`](AGENTS.md) — what the event is, the
  repo map, the deploy target, the four-script contract
- [`.claude/skills/`](.claude/skills/) — `connect-publish`,
  `fastapi-react-scaffold`, `plumber-react-scaffold`, and
  [`stats-first-steering`](.claude/skills/stats-first-steering/SKILL.md)

Two rules: everything you ship is **public and reproducible**, and you must be
able to **explain every number your tool prints**.

---

### 🧰 Starter Templates

| Template | What it is |
|---|---|
| [`demos/fastapi/`](demos/fastapi/) | Python REST API (FastAPI) |
| [`demos/plumber/`](demos/plumber/) | R REST API (plumber) |
| [`demos/reactfront/`](demos/reactfront/) | React front end for either API |
| [`demos/shinyapp/`](demos/shinyapp/) | R Shiny dashboard |
| [`demos/rpackage/`](demos/rpackage/) | R package skeleton |
| [`demos/making_readmes/`](demos/making_readmes/) | writing a README judges can follow |

Every deployable template follows the same **four-script contract**:
`testme` (run it locally) → `manifestme` (write the Connect manifest) →
`deployme` (publish) → `README.md`.

---

### ⁉️ Frequently Asked Questions

- **Who can participate?** All team members must be (1) on-campus, enrolled
  Cornell students and (2a) in the Systems Engineering MEng program OR (2b)
  enrolled in SYSEN 5300 / MAE 5390.

- **Do I need Six Sigma experience?** No. Trainings are provided during the
  event, and many of the analyses can be learned in a few minutes. The
  [course textbook](https://timothyfraser.com/sigma/) is open to everyone.

- **Do I have to be a coding wizard?** No. Some prior experience in R or Python
  is enough, and AI assistants close a lot of the gap. A winning project is a
  smart, correct solution to a quality-control problem — not fancy code.

- **What if I can't find team members?** Sign up anyway; we will match you with
  a team. It's a good way to meet people in the program.

- **Do I have to participate the whole 24 hours?** You do you — a successful
  team works most of it. Stagger breaks across team members.

- **Can I step out? Sleep? Work from a coffee shop?** Yes, yes, and yes. Keep
  absences brief and keep someone on the team present.

- **Can a teammate join remotely?** No. All team members attend in person.

- **What do I need to make?** A working prototype you can demo at the end.

- **What software do I need?** Install R or Python and at least one coding
  interface (RStudio, VSCode, Cursor, Positron, ...) **before** you arrive. If
  you plan to use an AI assistant, set it up beforehand too.

- **How do we share our final product?** A public GitHub repository, submitted
  through Devpost. At least one team member needs a working (non-Cornell)
  GitHub account.

- **What language should I use?** R, Python, or both. Code must be fully
  reproducible and public.

- **What skills help?** Writing functions, building a package, using GitHub,
  statistical analysis, reliability analysis, Six Sigma techniques, building or
  querying an API, building a dashboard.

- **How are products evaluated?** See [the criteria](docs/criteria.md): tool
  implementation (50), tool design (15), documentation (35).

---

### 👥 How to Join

Form a team (max 5) and register — the signup link is circulated with the event
announcement. No team? Sign up anyway and we'll match you.

---

### 📚 Sign Up to Mentor

Faculty, postdocs, PhD students, and developers are welcome as mentors.
[Details here](docs/mentors.md).

---

![](docs/images/banner_icons.png)
