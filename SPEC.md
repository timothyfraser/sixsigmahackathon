# SPEC: Six Sigma Hackathon team project

What your tool IS. Your agent reads this before every task. Where the code and this file
disagree, the code is the bug: change this file first, then the code.

Most of this page is already decided by the event and the [rubric](docs/criteria.md).
**Only the `FILL IN` lines change, and you do not have to write them by hand:** describe your app and ask your agent to update them. They depend on the prompt your team picks at kickoff
(prompts are secret until then, see [`docs/prompts.md`](docs/prompts.md)) and on your team.
The examples after each `FILL IN` show the shape of an answer. They are not hints about the prompts.

## 1. Team and prompt
- **Team name:** Big Red Crew
- **Track:** on-campus (24 hours). Submissions due Sat Oct 17, 1 PM ET. See [`docs/schedule.md`](docs/schedule.md).
- **Prompt we chose:** FILL IN, the prompt number and exact title from Devpost. Working name: Urban Systems, bike share fleet management.
- **Our public repo:** github.com/collinshiang/sixsigmahackathonBRC (one shared fork for all five teammates)

## 2. User and use case (rubric: scope 5, user and use case 5)
- **User:** a rider of a docked bike share system (our test cases: Citi Bike in New York City and Jersey City) who is about to start a trip.
- **Decision the tool helps them make, and when:** before walking to a dock, which pickup dock to walk to and which drop-off dock to ride to, so that a bike is there when they arrive and an open slot is there when they finish. A farther dock can win: a 20-minute walk beats a 10-minute walk if the closer dock will probably be empty.
- **Why this matches the prompt:** it treats an empty or full dock as a service failure, predicts that failure from dock history, steers riders around it (with a discount nudge, never a mandate), and flags the docks the rebalancing trucks should service.

## 3. Inputs (rubric: minimal inputs 5)
Only what this user can actually measure or already knows. Fewer is better; every input a user
cannot measure costs points.

| Input | Type and units | Where the user gets it |
|---|---|---|
| Start location | latitude, longitude (degrees) | their phone's map, or a click on the dashboard map |
| Destination | latitude, longitude (degrees) | the same map |
| Departure time | date and time, local (defaults to now) | their clock |
| Dock status history (operator side, loaded once, not typed by the rider) | CSV, one row per dock per 15-minute snapshot: `date`, `slot` (0-95), `dock_id`, `lat`, `lon`, `capacity` (slots), `bikes` (count), `pickups` and `dropoffs` (counts in that slot) | the operator's dock feed; for real, the public GBFS `station_status` feed polled every 15 minutes plus trip logs |

## 4. The statistics, and why (rubric: valid QC analysis 25)
Say the method in words before any code exists. Load the `stats-first-steering` skill first.
- **Method:** two statistics, one function each.
  1. **Dock availability probability (Poisson).** For each dock and each 15-minute slot of the day
     (weekdays and weekends kept apart), estimate the pickup rate `lam_out` and drop-off rate `lam_in` as
     the mean count per slot over the history before the trip's date. An empty dock hides pickup
     demand and a full dock hides drop-off demand, so `lam_out` uses only snapshots where the dock had
     at least one bike, and `lam_in` only those with at least one open slot. Over the time until the rider arrives, pickups
     `Out ~ Poisson(sum of lam_out over the slots crossed)` and drop-offs `In ~ Poisson(sum of lam_in)`,
     independent. With `b0` bikes now and capacity `c`:
     `P(bike available) = P(b0 + In - Out >= 1)` and `P(slot open) = P((c - b0) + Out - In >= 1)`.
     **Recommendation:** among docks within the walk limit, the nearest dock with probability >= 0.90; if
     none reaches 0.90, the dock with the highest probability. Walk time = straight-line (haversine)
     distance / 80 m per minute; ride time = distance / 250 m per minute.
  2. **p-chart of dock failures (SPC).** A dock "fails" in a 15-minute snapshot when it is empty
     (`bikes = 0`) or full (`bikes = capacity`). Per dock per day, `x` = failed snapshots out of `n = 96`.
     Limits from a baseline period (the first 14 days by default; at least 2): `p_bar = sum(x) / sum(n)`,
     `UCL = p_bar + 3*sqrt(p_bar*(1 - p_bar)/n)`, `LCL = max(0, p_bar - 3*sqrt(p_bar*(1 - p_bar)/n))`.
     A day above the UCL (Western Electric rule 1 only) puts the dock on the rebalancing truck's list.
- **Why it fits the use case:** the Poisson probability answers the rider's question ("will it be empty when I get there?"), and the p-chart tells the operator which docks are failing more often than usual, so trucks and discounts go where they matter.
- **Assumptions and how the tool checks them:**
  - Pickups and drop-offs are Poisson within a slot (counts independent, mean = variance). The demo prints the variance/mean ratio per dock-slot; a ratio far from 1 is shown as a warning.
  - Rates repeat by time of day and day type. The p-chart is that check: a dock out of control breaks this assumption, and the tool says so next to its recommendation.
  - The projection ignores the empty and full boundaries between now and arrival (a dock cannot go below 0 bikes). This is accurate for short trips (under about 30 minutes) and is stated in the output.
  - Capacity is fixed; a broken slot counts as missing capacity.
- **Known-answer check:** worked by hand.
  - Availability A: `b0 = 1`, `lam_out = 0.5` per slot, `lam_in = 0`, one slot ahead. `P(bike) = P(Out = 0) = e^-0.5 = 0.6065`.
  - Availability B: `b0 = 2`, `lam_out = 1.0`, `lam_in = 0`, one slot ahead. `P(bike) = P(Out <= 1) = e^-1 * (1 + 1) = 0.7358`.
  - Availability C (drop-off): `c = 10`, `b0 = 10` (full), `lam_in = 0`, `lam_out = 0.5`, one slot ahead. `P(slot open) = P(Out >= 1) = 1 - e^-0.5 = 0.3935`.
  - Recommendation: dock A is a 10-minute walk with `P = 0.6065`, dock B a 20-minute walk with `P = 0.95`. The nearest dock with `P >= 0.90` is B, so the tool recommends B.
  - p-chart: 5 baseline days, `n = 96` each, `x = 8, 10, 12, 9, 9`. `p_bar = 48/480 = 0.1000`. `sqrt(0.1*0.9/96) = sqrt(0.0009375) = 0.030619`. `UCL = 0.1000 + 0.091856 = 0.1919`, `LCL = 0.1000 - 0.091856 = 0.0081`. A new day with `x = 20` (`p = 0.2083`) is flagged; `x = 15` (`p = 0.1563`) is not.
  - Degenerate cases: a dock with `b0 = 0` and zero rates gives `P(bike) = 0`, not an error. A baseline whose `x` is all 0 (`p_bar = 0`) or all 96 (`p_bar = 1`) has no variation: the function returns no limits and a message ("no failures in baseline" or "failed in every baseline snapshot; chart undefined"), never limits of 0 or 1. Fewer than 2 baseline days, or a dock with no history, raises a clear error.

Fixed for every team:
- The statistic lives in **one plain, tested function** (`app/qc.py` or `app/qc.R`). The API, app or
  package only calls it and displays the result. No statistics inside UI code.
- Every statistic has a test against a known answer and a degenerate case (constant data, n = 1, missing values).
- You can explain every number the tool prints. If you cannot, it is not done.

## 5. Delivery (rubric: working tool 25)
- **Stack:** REST API (FastAPI, Python) plus a React dashboard. The statistics are a plain Python module, `app/qc.py`, that the API imports.
- **Starting demo:** `demos/fastapi/`, with `demos/reactfront/` as `app/frontend/` (the `fastapi-react-scaffold` skill).

Fixed for every team:
- Start from **one** demo in `demos/`, copied to `app/`. Keep its four-script contract
  (`testme`, `manifestme`, `deployme`, `README.md`); `testme` starts the tool with one command.
- Deployed on the course **Posit Connect** server with a public URL (publisher key handed out at the
  event). Deploy early: copy one workflow from
  [`.claude/skills/connect-publish/workflows/`](.claude/skills/connect-publish/workflows/).
- A small tool that runs beats a large tool that does not.

## 6. Outputs
- **What the user sees:**
  - **Rider view:** the recommended pickup dock and drop-off dock on a map, each with walk or ride minutes and "chance a bike is there: 95%" / "chance a slot is open: 92%", plus the two nearest alternatives. A recommended dock that is underfilled (for drop-off) carries a "discount" badge. How to read this: go to the highlighted dock; the percentage is how often, in the history, a dock in this state at this time still had a bike (or slot) when you would arrive.
  - **Operator view:** a p-chart per dock (daily failure fraction, with center line and UCL; days above the UCL in red) and a list of docks out of control today, for the rebalancing truck. How to read this: a red day means that dock was empty or full far more often than its own normal.

## 7. Test datasets and codebook (rubric: demo 10, datasets 5, codebook 5)
2-3 small CSVs in `data/`, invented but shaped like real field data, each showing one behavior.
`data/README.md` is the codebook: every file, every column with units, and what it would take to
collect this data for real.
- **Datasets:** simulated with a seeded script, `data/simulate.py`, so anyone can rebuild them. All three use the dock-snapshot columns in section 3.
  - `nyc_in_control.csv`: 30 days, 15 Manhattan docks at their real public locations, steady rush-hour patterns. The p-chart shows no flagged days.
  - `jc_planted_shift.csv`: 30 days, 12 Jersey City docks. From day 21, morning pickups at one dock near PATH triple, so it runs empty. The p-chart must flag that dock on days 21-30, and the recommender must start sending riders to its neighbors.
  - `edge_case.csv`: 1 dock, 2 days, always empty, zero pickups and drop-offs. Availability is 0, and since the dock failed in every snapshot (`p_bar = 1`) the p-chart returns no limits with a clear message.

## 8. Documentation and reproducibility (rubric: docs 10, public repo 5)
- `README.md` says what the tool does, for whom, every input and parameter, how to run it in one
  command, and walks through the demo on each test dataset.
- Public GitHub repo; a fresh clone runs `testme` and the tests pass with no extra steps.
- Submit on Devpost: the repo link plus a demo.

## 9. Out of scope
What we will NOT build, so nobody (human or agent) builds it by accident.
- Default: logins, databases, real customer data, a second statistic before the first one is tested.
- Dockless bikes and scooters; choosing where to build new docks (we optimize the current system only).
- A mobile app, live GPS of bikes in transit, and predicting where an individual bike goes.
- Setting discount prices or truck routes: we flag the docks; pricing and routing are the operator's.
- Bike-level maintenance and reliability modeling (miles per bike, defects): a stretch goal only if both statistics above pass review before Saturday 9 AM.
- Real Citi Bike trip data: dock locations may be real public locations, every count is simulated and labeled as such.
