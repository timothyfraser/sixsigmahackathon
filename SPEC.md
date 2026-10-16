# SPEC: Six Sigma Hackathon team project

What your tool IS. Your agent reads this before every task. Where the code and this file
disagree, the code is the bug: change this file first, then the code.

Most of this page is already decided by the event and the [rubric](docs/criteria.md).
**Only the `FILL IN` lines change, and you do not have to write them by hand:** describe your app and ask your agent to update them. They depend on the prompt your team picks at kickoff
(prompts are secret until then, see [`docs/prompts.md`](docs/prompts.md)) and on your team.
The examples after each `FILL IN` show the shape of an answer. They are not hints about the prompts.

## 1. Team and prompt
- **Team name:** 2027win (tool: Rush Hour Autopilot, a web dashboard). Example: "Control Freaks"
- **Track:** on-campus (24 hours); submissions due Sat Oct 17, 1 PM ET. See [`docs/schedule.md`](docs/schedule.md).
- **Prompt we chose:** "Bikeshare Fleets": *A municipal bikeshare system is suffering from a "docks full / docks empty" crisis during rush hour. Maintenance vans are dispatched blindly. Design a system tool to track dock availability, when and where stations are unusable, and support the network's performance.*
- **Our public repo:** github.com/YuCiciFu/sixsigmahackathon (public: logged-out GitHub API and web page returned HTTP 200 on 2026-10-16). Example: "github.com/our-team/our-tool"

## 2. User and use case (rubric: scope 5, user and use case 5)
- **User:** the municipal bikeshare dispatcher who plans the rebalancing vans for the weekday morning rush. Example: "the supervisor who checks part diameters at the end of each shift"
- **Decision the tool helps them make, and when:** during the 07:00-10:00 ET weekday rush: which stations to handle first; whether a problem needs rebalancing, maintenance or a data check; where to take bikes from, where to bring them and how many; and whether service improved afterwards (details: [`docs/methods.md`](docs/methods.md) section 2). Example: "whether to stop the line and recalibrate before the next shift starts"
- **Why this matches the prompt:** it tracks dock availability minute by minute, shows when and where stations are unusable (empty or full), and replaces blind van dispatch with a ranked, statistically checked plan whose effect is measured.

## 3. Inputs (rubric: minimal inputs 5)
Only what this user can actually measure or already knows. Fewer is better; every input a user
cannot measure costs points.

| Input | Type and units | Where the user gets it |
|---|---|---|
| One scenario CSV with four record types (stations, minute status snapshots, rent and return attempts, van tasks) plus policy parameters; full schema in [`docs/methods.md`](docs/methods.md) sections 3 and 7 | IDs and names as text; coordinates in decimal degrees; capacity, bikes, docks and quantities as counts; ISO 8601 times with offset; TRUE/FALSE flags | the station list and status feed (GBFS-like), kiosk and app attempt logs, the dispatch task log; simulated in this version |

## 4. The statistics, and why (rubric: valid QC analysis 25)
Say the method in words before any code exists. Load the `stats-first-steering` skill first.
- **Method:** tier 1: rent- and return-failure p charts, an I-MR chart of the rush-hour unusable share, an unusable-minute ranking, a greedy rebalancing plan and a paired-seed policy simulation; tiers 2-3: c chart, X-bar/R with Cpu, Kaplan-Meier, a forward risk forecast, empirical availability and reliability, and fault trees (formulas in [`docs/methods.md`](docs/methods.md) 4.1-4.4). Example: "X-bar and R chart, subgroups of 5, limits from the average range"
- **Why it fits the use case:** rent and return attempts are pass/fail (p charts), rush-hour unusable share is one number per weekday (I-MR), and a rebalancing policy must be judged against the same simulated demand (paired seeds); the full reasoning is in [`docs/methods.md`](docs/methods.md) 4.2.
- **Assumptions and how the tool checks them:** limits come from a stated baseline; Western Electric rules 1 and 4; a fixed station set with at least 95% coverage for SPC; a dispersion check for Poisson counts; stability and normality before Cpu; NA with a reason when a value cannot be estimated (full list in [`docs/methods.md`](docs/methods.md) 4.1-4.2). Example: "normality: histogram plus Shapiro-Wilk in the demo"
- **Known-answer check:** for example KA-2: 5 rush windows of 100 rent attempts with 4, 6, 5, 3, 7 failures give p-bar = 0.050, UCL = 0.115, LCL = 0; every hand-worked check, KA-1 to KA-11, is in [`docs/methods.md`](docs/methods.md) 4.2.

Fixed for every team:
- The statistic lives in **one plain, tested function** (`app/qc.py` or `app/qc.R`). The API, app or
  package only calls it and displays the result. No statistics inside UI code.
- Every statistic has a test against a known answer and a degenerate case (constant data, n = 1, missing values).
- You can explain every number the tool prints. If you cannot, it is not done.

## 5. Delivery (rubric: working tool 25)
- **Stack:** dashboard: R Shiny (statistics in `app/qc.R`, tested with testthat; packages listed in [`docs/methods.md`](docs/methods.md) section 5).
- **Starting demo:** `demos/shinyapp/`, copied into `app/` (with R `testme`, `manifestme` and `deployme` scripts added, see [`docs/methods.md`](docs/methods.md) section 5). Example: `demos/fastapi/`

Fixed for every team:
- Start from **one** demo in `demos/`, copied to `app/`. Keep its four-script contract
  (`testme`, `manifestme`, `deployme`, `README.md`); `testme` starts the tool with one command.
- Deployed on the course **Posit Connect** server with a public URL (publisher key handed out at the
  event). Deploy early: copy one workflow from
  [`.claude/skills/connect-publish/workflows/`](.claude/skills/connect-publish/workflows/).
- A small tool that runs beats a large tool that does not.

## 6. Outputs
- **What the user sees:** a tabbed Shiny page (Overview, Stations, Quality, Forecast & Reliability, Diagnosis, Rebalancing, Improvement); every chart or number shows its unit, its sample size or coverage, and a one-line "how to read this" (tab contents in [`docs/methods.md`](docs/methods.md) section 6).
  Example: "a control chart with out-of-control points in red, plus 'stop the line: yes/no'"

## 7. Test datasets and codebook (rubric: demo 10, datasets 5, codebook 5)
2-3 small CSVs in `data/`, invented but shaped like real field data, each showing one behavior.
`data/README.md` is the codebook: every file, every column with units, and what it would take to
collect this data for real.
- **Datasets:** `data/baseline.csv`, `data/planted_shift.csv` (dock fault and demand surge from weekday 11), `data/edge_case.csv` (2 stations, 1 day, gaps and a conflicting duplicate); all simulated, one long-form file each with a `table` column (schema in [`docs/methods.md`](docs/methods.md) section 7). Example: "`in_control.csv`, `planted_shift.csv` (mean shifts at row 40), `edge_case.csv` (one subgroup)"

## 8. Documentation and reproducibility (rubric: docs 10, public repo 5)
- `README.md` says what the tool does, for whom, every input and parameter, how to run it in one
  command, and walks through the demo on each test dataset.
- Public GitHub repo; a fresh clone runs `testme` and the tests pass with no extra steps.
- Submit on Devpost: the repo link plus a demo.

## 9. Out of scope
What we will NOT build, so nobody (human or agent) builds it by accident.
- Default: logins, databases, real customer data, a second statistic before the first one is tested.
- No live GBFS feed, no vehicle-routing optimiser, no machine-learning demand forecast, no real dispatch integration, no mobile app; tiers 2-3 wait until tier 1 passes review (details in [`docs/methods.md`](docs/methods.md) section 9). Example: "no forecasting; no multi-plant comparison"
