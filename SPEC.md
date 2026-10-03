# SPEC: Six Sigma Hackathon team project

What your tool IS. Your agent reads this before every task. Where the code and this file
disagree, the code is the bug: change this file first, then the code.

Most of this page is already decided by the event and the [rubric](docs/criteria.md).
**Only the `FILL IN` lines are yours.** They depend on the prompt your team picks at kickoff
(prompts are secret until then, see [`docs/prompts.md`](docs/prompts.md)) and on your team.
The examples after each `FILL IN` show the shape of an answer. They are not hints about the prompts.

## 1. Team and prompt
- **Team name:** FILL IN. Example: "Control Freaks"
- **Track:** FILL IN, on-campus (24 hours) or Virtual DL Challenge (7 days). See [`docs/schedule.md`](docs/schedule.md).
- **Prompt we chose:** FILL IN, the prompt number and title, copied from `docs/prompts.md` at kickoff.
- **Our public repo:** FILL IN. Example: "github.com/our-team/our-tool"

## 2. User and use case (rubric: scope 5, user and use case 5)
- **User:** FILL IN, one named kind of person, not "everyone". Example: "the supervisor who checks part diameters at the end of each shift"
- **Decision the tool helps them make, and when:** FILL IN. Example: "whether to stop the line and recalibrate before the next shift starts"
- **Why this matches the prompt:** FILL IN, one sentence.

## 3. Inputs (rubric: minimal inputs 5)
Only what this user can actually measure or already knows. Fewer is better; every input a user
cannot measure costs points.

| Input | Type and units | Where the user gets it |
|---|---|---|
| FILL IN. Example: `measurements.csv`, one row per part | numeric, mm | their gauge log |

## 4. The statistics, and why (rubric: valid QC analysis 25)
Say the method in words before any code exists. Load the `stats-first-steering` skill first.
- **Method:** FILL IN. Example: "X-bar and R chart, subgroups of 5, limits from the average range"
- **Why it fits the use case:** FILL IN, one sentence.
- **Assumptions and how the tool checks them:** FILL IN. Example: "normality: histogram plus Shapiro-Wilk in the demo"
- **Known-answer check:** FILL IN, a textbook example or hand calculation the function must reproduce.

Fixed for every team:
- The statistic lives in **one plain, tested function** (`app/qc.py` or `app/qc.R`). The API, app or
  package only calls it and displays the result. No statistics inside UI code.
- Every statistic has a test against a known answer and a degenerate case (constant data, n = 1, missing values).
- You can explain every number the tool prints. If you cannot, it is not done.

## 5. Delivery (rubric: working tool 25)
- **Stack:** FILL IN, one of: R package, Python library, REST API (FastAPI or plumber), dashboard (React or Shiny).
- **Starting demo:** FILL IN, the one folder copied from [`demos/`](demos/README.md) into `app/`. Example: `demos/fastapi/`

Fixed for every team:
- Start from **one** demo in `demos/`, copied to `app/`. Keep its four-script contract
  (`testme`, `manifestme`, `deployme`, `README.md`); `testme` starts the tool with one command.
- Deployed on the course **Posit Connect** server with a public URL (publisher key handed out at the
  event). Deploy early: copy one workflow from
  [`.claude/skills/connect-publish/workflows/`](.claude/skills/connect-publish/workflows/).
- A small tool that runs beats a large tool that does not.

## 6. Outputs
- **What the user sees:** FILL IN, a number, chart or pass/fail, with units and a one-line "how to read this".
  Example: "a control chart with out-of-control points in red, plus 'stop the line: yes/no'"

## 7. Test datasets and codebook (rubric: demo 10, datasets 5, codebook 5)
2-3 small CSVs in `data/`, invented but shaped like real field data, each showing one behavior.
`data/README.md` is the codebook: every file, every column with units, and what it would take to
collect this data for real.
- **Datasets:** FILL IN. Example: "`in_control.csv`, `planted_shift.csv` (mean shifts at row 40), `edge_case.csv` (one subgroup)"

## 8. Documentation and reproducibility (rubric: docs 10, public repo 5)
- `README.md` says what the tool does, for whom, every input and parameter, how to run it in one
  command, and walks through the demo on each test dataset.
- Public GitHub repo; a fresh clone runs `testme` and the tests pass with no extra steps.
- Submit on Devpost: the repo link plus a demo.

## 9. Out of scope
What we will NOT build, so nobody (human or agent) builds it by accident.
- Default: logins, databases, real customer data, a second statistic before the first one is tested.
- FILL IN, anything else. Example: "no forecasting; no multi-plant comparison"
