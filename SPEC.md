# SPEC: Six Sigma Hackathon team project

What your tool IS. Your agent reads this before every task. Where the code and this file
disagree, the code is the bug: change this file first, then the code.

Most of this page is already decided by the event and the [rubric](docs/criteria.md).
**Only the `FILL IN` lines change, and you do not have to write them by hand:** describe your app and ask your agent to update them. They depend on the prompt your team picks at kickoff
(prompts are secret until then, see [`docs/prompts.md`](docs/prompts.md)) and on your team.
The examples after each `FILL IN` show the shape of an answer. They are not hints about the prompts.

## 1. Team and prompt
- **Team name:** Team Vanta. Product: DockWatch. Members: Raymond Xu, Chi Zhang, Siyu Yao, Ruoxi Wang, Huiyu Zhu.
- **Track:** On-campus (24 hours), October 16–17, 2026. Submit October 17 by 1 PM America/New_York; showcase 2–3 PM.
- **Prompt we chose:** Urban Systems — Bikeshare Fleets ([Devpost](https://six-sigma-hackathon.devpost.com/)); no numeric identifier was published. Track station availability and support informed rebalancing.
- **Our public repo:** https://github.com/raymondBRXu/sixsigmahackathon-vanta

## 2. User and use case (rubric: scope 5, user and use case 5)
- **User:** The supervisor of a fictional bikeshare network in the Ithaca, New York area, supported by field workers counting bikes once per station per hour.
- **Decision the tool helps them make, and when:** At each hourly review, identify empty/full or low/high-stock stations, investigate unusual inventory for that station and hour, and prioritize bike replenishment or removal.
- **Why this matches the prompt:** Uses directly observable station inventory to reveal where and when service is unavailable and to provide explained rebalancing suggestions without assuming access to unobserved customer attempts.

## 3. Inputs (rubric: minimal inputs 5)
Only what this user can actually measure or already knows. Fewer is better; every input a user
cannot measure costs points.

| Input | Type and units | Where the user gets it |
|---|---|---|
| Hourly inspection CSV: `timestamp`, `station_id`, `bikes` | Timestamp with timezone; station identifier; integer bikes | Worker records bike count once per station per hour; time is filled automatically |
| Station configuration: `station_id`, `name`, `area`, `type`, `latitude`, `longitude`, `capacity` | Identifier, display name, area/type labels, WGS84 decimal-degree coordinates, positive integer positions | Configured once for 20 fictional Ithaca-area stations; field workers do not enter coordinates at every inspection |

Require 0 <= bikes <= capacity and one record per station/scheduled hourly slot. Preserve
missing readings as missing, never zero; reject invalid and duplicate rows. MVP capacity
is fixed at 30 positions for each of 20 stations; the fleet totals 300 bikes.
The synthetic instantaneous-transfer model conserves 300 bikes across all stations
at every complete snapshot (600 total positions, 50% network occupancy). Stations are open, and all bikes/docks usable, so free docks = capacity - bikes.
Faults and closures require an explicit future schema extension. Use actual observation
times; the demo is exactly on the hour, while manual-entry slot tolerance is a disclosed
collection rule. Compare matched scheduled hours and show missing coverage.

Geographic setting: Ithaca, New York and nearby areas shown in the team's reference
screenshot, rather than a strict municipal-boundary model. Place 20 fictional stations
around Downtown Ithaca, the Cornell area, the waterfront/Stewart Park area, Cayuga
Heights, East Ithaca and South Hill. Exact station locations will be set and visually
checked during data preparation; do not claim they are existing bikeshare facilities.
Use the same station IDs and coordinates in all scenarios. The map is labeled
“Ithaca — simulated bikeshare network”; coordinates locate stations but do not change
the statistical formulas or imply measured local demand.

## 4. The statistics, and why (rubric: valid QC analysis 25)
Say the method in words before any code exists. Load the `stats-first-steering` skill first.
- **Method:** Descriptive snapshot metrics plus a conditional Individuals (I) control chart of bike counts across comparable service dates at the SAME station and clock hour. For valid snapshots, occupancy = bikes/capacity; empty proportion = count(bikes=0)/N; full proportion = count(bikes=capacity)/N; two-way availability = count(0<bikes<capacity)/N. Report N and observation coverage. Hourly net change = current bikes minus previous bikes only for adjacent, one-hour-separated observations within the same service day. For an eligible baseline sequence x, MR_i=abs(x_i-x_(i-1)), MR_bar=mean(MR_i), sigma_hat=MR_bar/1.128, CL=mean(x), LCL=CL-3*sigma_hat, UCL=CL+3*sigma_hat. Freeze baseline limits before monitoring. Only strict single-point crossings signal; no additional run rules. Moving ranges estimate the I-chart limits; a separate MR chart is not promised.
- **Why it fits the use case:** The measured unit is a bike count at a scheduled inspection, not a customer success/failure. Comparing the same hour across similar days avoids treating the normal morning/evening pattern as a process change. The I chart is an approximate method for sufficiently well-behaved counts, not universally valid for bounded inventories.
- **Assumptions and how the tool checks them:** MVP assumes all stations are open and all bikes/docks usable, with positive fixed capacity. Use at least 20 valid baseline dates and 15 valid adjacent scheduled-date pairs per station/hour as project data gates. Do not compute moving ranges across missing scheduled dates. Check and display baseline sequence, distribution, boundary frequency, and lag-one correlation; require explicit baseline suitability review before enabling statistical alarms. Approximate stationarity, weak serial dependence and a reasonably symmetric non-boundary-dominated distribution are required. Unreviewed or unsuitable data retain descriptive metrics and inventory business warnings only, not statistically calibrated alarms. Constant baseline or too few pairs yields an explicit unsupported state. Do not claim aggregation removes dependence. Do not clip I-chart limits to physical capacity or confuse them with stock targets. Multiple-chart signals are investigation cues, not proof of failure. Synthetic scenario parameters are never read by the detector.
- **Known-answer check:** Snapshot fixture with capacity 30 and hourly bikes [0,0,9,15,30] gives empty=2/5=40%, full=1/5=20%, two-way availability=2/5=40%, and mean occupancy=36%; net changes are [0,9,6,15]. Formula-only I-chart fixture [10,12,11,13,14] gives mean=12, MR=[2,1,2,1], MR_bar=1.5, sigma_hat=1.329787234, LCL=8.010638298 and UCL=15.989361702; 7 and 17 cross the limits. This five-point fixture tests arithmetic only; production analysis still enforces baseline eligibility. Test constant data, one value, missing hours, duplicate keys, invalid counts, frozen baseline, and exact-limit equality. Source: [NIST Individuals charts](https://www.itl.nist.gov/div898/handbook/pmc/section3/pmc322.htm).

Fixed for every team:
- The statistic lives in **one plain, tested function** (`app/qc.py` or `app/qc.R`). The API, app or
  package only calls it and displays the result. No statistics inside UI code.
- Every statistic has a test against a known answer and a degenerate case (constant data, n = 1, missing values).
- You can explain every number the tool prints. If you cannot, it is not done.

## 5. Delivery (rubric: working tool 25)
- **Stack:** React/Vite dashboard plus a public FastAPI REST API with plain Python statistical functions; deploy both to the course Posit Connect server.
- **Starting demo:** Copy demos/fastapi/ to app/ as the primary template; adapt demos/reactfront/ into app/frontend/. Python app/qc.py owns the calculations. Adapt the example control chart to our same-hour-across-dates design; do not apply its calculations to a pooled hourly stream. Use the separate API and React deployment workflows.

Fixed for every team:
- Start from **one** demo in `demos/`, copied to `app/`. Keep its four-script contract
  (`testme`, `manifestme`, `deployme`, `README.md`); `testme` starts the tool with one command.
- Deployed on the course **Posit Connect** server with a public URL (publisher key handed out at the
  event). Deploy early: copy one workflow from
  [`.claude/skills/connect-publish/workflows/`](.claude/skills/connect-publish/workflows/).
- A small tool that runs beats a large tool that does not.

## 6. Outputs
- **What the user sees:** An interactive Ithaca-area map with all 20 simulated stations, a scenario date/hour selector, and clickable station markers showing bike count out of 30, free docks, observation time, status, and action suggestion. Missing/stale observations have their own marker states. Selecting a station opens its detail chart. Also show hourly inventory and occupancy, empty/full/two-way-available observation proportions with counts and coverage, station/hour heatmaps, adjacent-hour net changes, and a station detail chart. Eligible reviewed strata show I-chart limits; all others show descriptive history and a clear reason alarms are unavailable. Forms accept hourly counts and CSV uploads. All demo data are labeled synthetic.

Suggestions use the most recent eligible snapshot, never inferred customer demand. As an
explicit demo policy, occupancy below 20% suggests adding bikes toward floor(capacity/2);
above 80% suggests removing bikes toward that target. Exactly 20% or 80% does not trigger.
For capacity 30, bikes=3 suggests add 12; bikes=27 suggests remove 12. The target is 15 bikes per station. These are business
rules, not statistical conclusions. Missing records or records at least 60 minutes old
require reinspection; even fresh counts are labeled with their timestamp and require
confirmation before a physical move. Demo freshness uses the displayed scenario time.
Rank fresh empty/full stations first, then low/high stock, using eligible same-hour
statistical signals as additional evidence. No automatic dispatch or guaranteed route.

Hourly snapshots do not measure failed attempts, exact downtime, separate pickup/return
counts, or the cause of inventory changes. Session logging/export is supported without
claiming a shared live database.
  Example: "a control chart with out-of-control points in red, plus 'stop the line: yes/no'"

## 7. Test datasets and codebook (rubric: demo 10, datasets 5, codebook 5)
2-3 small CSVs in `data/`, invented but shaped like real field data, each showing one behavior.
`data/README.md` is the codebook: every file, every column with units, and what it would take to
collect this data for real.
- **Datasets:** normal.csv (hourly inventory under a repeatable daily pattern), disruption.csv (identical baseline, stronger morning residential-to-office transfers in monitoring), and edge_cases.csv (valid empty/full, missing-hour, constant-baseline and insufficient-history examples). Schema: timestamp, station_id, bikes; capacity is in stations.json. Generator scale: 20 fictional Ithaca-area stations with fixed mapped locations, capacity 30 each, total fleet 300 bikes, 12 hourly snapshots from 08:00 through 19:00, 40 comparable synthetic service days; first 25 baseline, last 15 monitoring (9,600 rows per complete scenario). Start from 15 bikes per station and apply conserving random transfers for variation. A fixed-seed, bounded, fleet-conserving transfer simulator produces snapshots; generation-only transfers and scenario labels are not product inputs. Daily resets represent documented overnight rebalancing, not unexplained vehicle creation. Include a generator, metadata and codebook. Invalid records belong in test fixtures. No customer failure probabilities or attempted-trip counts are required. Morning/evening transfer weights may reflect hypothetical residential-to-campus/employment-area travel, but are disclosed synthetic assumptions, not measured Ithaca commuting patterns. The initial map uses the team screenshot as a geographic reference, not as live telemetry.

## 8. Documentation and reproducibility (rubric: docs 10, public repo 5)
- `README.md` says what the tool does, for whom, every input and parameter, how to run it in one
  command, and walks through the demo on each test dataset.
- Public GitHub repo; a fresh clone runs `testme` and the tests pass with no extra steps.
- Submit on Devpost: the repo link plus a demo.

## 9. Out of scope
What we will NOT build, so nobody (human or agent) builds it by accident.
- Default: logins, databases, real customer data, a second statistic before the first one is tested.
- No customer-attempt or failure-rate inference, exact stockout duration, demand forecasting, machine learning, route optimization, automatic dispatch, faults/closures, real telemetry, or causal claims about rebalancing. No p chart treating successive inventory snapshots as independent customer trials. The data generator uses a minimal instantaneous-transfer abstraction, not a travel-time or full traffic simulator.
