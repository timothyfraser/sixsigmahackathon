# Assignments: who builds what, step by step

Big Red Crew, on-campus track. Submit by **Sat Oct 17, 12:30 PM ET** (hard deadline 1 PM).
Read [`SPEC.md`](../SPEC.md) section 4 before your part; [`plan.md`](plan.md) has the overview.

## How everyone works (all agents: Claude, Codex, Gemini, Copilot)

1. `git clone https://github.com/collinshiang/sixsigmahackathonBRC.git`, then make your branch:
   `git switch -c <your-branch>` (branch names are listed per person below).
2. Start your agent in the repo folder and paste **your prompt** from your section. Every prompt
   begins the same way, so every agent reads the same rules.
3. Write only the files listed under **Owns**. Need another file? Ask the owner in the group chat.
4. Done means the **Done when** command printed what it says. Paste that output into your PR.
5. Push and open a PR into `main`: `git push -u origin <your-branch>` then
   `gh pr create --fill`. One teammate reads the diff and merges. Merge small and often.
6. Never put the Posit Connect key in a file, a commit or the chat. It goes into GitHub repo secrets.

### The shared interface: do not change it without telling everyone

Data (one row per dock per 15-minute snapshot, every CSV in `data/`):

| Column | Type | Meaning |
|---|---|---|
| `date` | YYYY-MM-DD | day of the snapshot |
| `slot` | int 0-95 | 15-minute slot of the day (slot 32 = 08:00-08:15) |
| `dock_id` | string | e.g. `NYC-001`, `JC-004` |
| `name` | string | dock name |
| `lat`, `lon` | float, degrees | dock location |
| `capacity` | int, slots | number of docking slots |
| `bikes` | int, count | bikes docked at the START of the slot |
| `pickups`, `dropoffs` | int, count | bikes taken out / returned during the slot |

Python functions (inputs and outputs are plain numbers, lists and pandas DataFrames):

```python
# app/qc.py  (Person 1)
estimate_rates(history: pd.DataFrame, before_date: str, day_type: str) -> pd.DataFrame
    # columns: dock_id, slot, lam_out, lam_in, n_out, n_in, vm_out, vm_in
p_bike_available(b0: int, lam_out: float, lam_in: float) -> float
p_slot_open(b0: int, capacity: int, lam_out: float, lam_in: float) -> float
recommend(candidates: list[dict], threshold: float = 0.90) -> dict
    # candidates: [{"dock_id", "minutes", "p"}]; returns {"choice": {...}, "alternatives": [2 dicts], "reason": str}

# app/pchart.py  (Person 2)
daily_failures(history: pd.DataFrame) -> pd.DataFrame          # columns: dock_id, date, x, n
p_chart(daily: pd.DataFrame, baseline_days: int = 14) -> dict
    # {dock_id: {"p_bar", "ucl", "lcl", "days": [{"date", "p", "flag"}], "message"}}

# app/trip.py  (Person 4)
haversine_m(lat1, lon1, lat2, lon2) -> float
window_rates(rates, dock_id, start_slot, minutes) -> tuple[float, float]   # (sum lam_out, sum lam_in)
plan_trip(history, start, dest, depart) -> dict                            # what POST /recommend returns
```

API (Person 4 builds it, Person 5 calls it):

| Route | Returns |
|---|---|
| `GET /health` | `{"status": "ok"}` |
| `GET /datasets` | `["nyc_in_control", "jc_planted_shift", "edge_case"]` |
| `GET /docks?dataset=jc_planted_shift` | `[{dock_id, name, lat, lon, capacity}]` |
| `POST /recommend` body `{dataset, start: {lat, lon}, dest: {lat, lon}, depart: "2026-09-25T08:10"}` | `{pickup: {dock_id, name, lat, lon, walk_min, p_bike, alternatives}, dropoff: {dock_id, name, lat, lon, ride_min, p_slot, discount, alternatives}, warnings: [...], assumptions: [...]}` |
| `GET /pchart?dataset=...&dock_id=...` | one dock's entry from `p_chart` |
| `GET /flagged?dataset=...&date=...` | `[{dock_id, name, p, ucl}]` docks above UCL that day, for the truck |

Until the real functions exist, Person 4's API returns **fake JSON of exactly this shape**, so
Person 5 is never blocked.

---

## Person 1: Stats A, dock availability and recommendation (task H-03)

**Goal:** given a dock's state now and its history, the probability a rider finds a bike (or an
open slot) when they arrive, and the rule that picks the dock.
**Branch:** `h03-availability` **Owns:** `app/qc.py`, `tests/test_qc.py`, `app/requirements.txt`
**Needs from others:** nothing to start (tests use hand-made numbers). Person 3's CSVs for step 6.
**Gives to:** Person 4 (`app/trip.py` imports your functions), Person 2 (reviews you).

Steps:
1. Load `.claude/skills/stats-first-steering/SKILL.md`. Read SPEC section 4, method 1.
2. Write `p_bike_available`: with `In ~ Poisson(lam_in)` and `Out ~ Poisson(lam_out)` independent,
   return `P(b0 + In - Out >= 1)`. Sum over the joint pmf with `scipy.stats.poisson` up to the
   99.9999% quantile of each (or use `scipy.stats.skellam`: `P(Out - In <= b0 - 1)`). Same for
   `p_slot_open` with `c - b0` open slots and the roles of In and Out swapped.
3. Write the tests from SPEC section 4 first, then make them pass:
   case A 0.6065, case B 0.7358, case C 0.3935 (to 4 decimals); `b0 = 0`, both rates 0 gives 0.0;
   `b0 = 5`, both rates 0 gives 1.0; negative `b0` or `b0 > capacity` raises `ValueError`.
4. Write `recommend`: drop docks with `p` missing, pick the smallest `minutes` with `p >= threshold`;
   if none, the largest `p` (tie: fewer minutes). `reason` says which rule fired. Test: the SPEC case
   (A 10 min 0.6065, B 20 min 0.95) picks B; an empty list raises `ValueError`.
5. Write `estimate_rates`: keep rows with `date < before_date` and the matching `day_type`
   (`"weekday"` Mon-Fri, `"weekend"` Sat-Sun). Per `dock_id, slot`: `lam_out` = mean `pickups` over
   rows with `bikes > 0`; `lam_in` = mean `dropoffs` over rows with `bikes < capacity`; `n_out`,
   `n_in` = how many rows were used; `vm_out`, `vm_in` = variance / mean (the Poisson check; near 1
   is good). No rows for a dock-slot raises `ValueError` naming it. Test on a 2-day, 1-dock,
   3-slot frame you build by hand in the test, with the means worked out in a comment.
6. When `data/` exists: run `estimate_rates` on `nyc_in_control.csv` and print the `vm_out`
   median. Paste it into your PR (the demo will quote it).
7. Add `scipy` and `pandas` with `==` versions to `app/requirements.txt` in the same commit.

**Prompt for your agent:**
> Read AGENTS.md, SPEC.md (section 4, method 1), docs/assignments.md (the interface and the
> Person 1 section) and .claude/skills/stats-first-steering/SKILL.md. You work ONLY on task H-03
> and write ONLY app/qc.py, tests/test_qc.py and app/requirements.txt. Do the Person 1 steps in
> order; write each test before its function. No FastAPI, no plotting in app/qc.py. When done,
> run `pytest tests/test_qc.py -v` and paste the full output. Do not commit.

**Done when:** `pytest tests/test_qc.py -v` shows every test passing, including the three SPEC
cases, the recommend case and the `b0 = 0` case. Then Person 2 reviews it (below).

---

## Person 2: Stats B, p-chart of dock failures (new task H-09), then reviewer

**Goal:** a daily p-chart per dock that flags docks failing (empty or full) more than usual.
**Branch:** `h09-pchart` **Owns:** `app/pchart.py`, `tests/test_pchart.py`, the H-09 block in `CONTRACT.yaml`
**Needs from others:** nothing to start. Person 3's `jc_planted_shift.csv` for step 6.
**Gives to:** Person 4 (`/pchart`, `/flagged`), Person 5 (the operator chart).

Steps:
1. First: get the team's OK in the chat, then add H-09 to `CONTRACT.yaml` (copy H-03's block;
   title "p-chart of daily dock failures"; owns the two files above; definition_of_done
   `pytest tests/test_pchart.py` passes with the SPEC known answer and degenerate cases).
2. Load the stats-first-steering skill. Read SPEC section 4, method 2.
3. `daily_failures`: per `dock_id, date`, `x` = snapshots with `bikes == 0` or `bikes == capacity`,
   `n` = snapshots that day (96 when the day is complete).
4. `p_chart`: the first `baseline_days` dates are the baseline. `p_bar = sum(x) / sum(n)` over the
   baseline. For every day, with that day's `n`: `UCL = p_bar + 3 * sqrt(p_bar * (1 - p_bar) / n)`,
   `LCL = max(0, p_bar - 3 * sqrt(...))`; `flag = p > UCL` (rule 1 only; we do not flag low days,
   being empty less often is good). Limits come from the baseline only, never from the whole series.
5. Tests: SPEC known answer (x = 8, 10, 12, 9, 9, n = 96, `baseline_days = 5`) gives
   `p_bar = 0.1000`, `UCL = 0.1919`, `LCL = 0.0081`; a sixth day with x = 20 flags, x = 15 does not.
   Degenerate: all x = 0, or all x = 96, gives `ucl = None` and a message; fewer than 2 baseline
   days raises `ValueError`.
6. When `data/` exists: run it on `jc_planted_shift.csv` and paste which dock and days are flagged.
   It must be the planted dock on days 21-30 and (almost) nothing else. A few false alarms in 30 x 12
   dock-days are expected at 3 sigma; say how many.
7. **Then review Person 1:** in a fresh agent session run the `stats-reviewer` agent on H-03
   (Claude: `.claude/agents/stats-reviewer.md`; other agents: paste `.opencode/commands/review.md`).
   Post the PASS/FAIL table on Person 1's PR. No PASS, no merge. Person 1 does the same for you.

**Prompt for your agent:**
> Read AGENTS.md, SPEC.md (section 4, method 2), docs/assignments.md (the interface and the
> Person 2 section) and .claude/skills/stats-first-steering/SKILL.md. You work ONLY on task H-09
> and write ONLY app/pchart.py and tests/test_pchart.py. Do Person 2 steps 3-5; write each test
> before its function. Control limits come from the baseline days only. No FastAPI, no plotting.
> Run `pytest tests/test_pchart.py -v` and paste the full output. Do not commit.

**Done when:** `pytest tests/test_pchart.py -v` passes, and step 6 printed the planted dock.

---

## Person 3: simulated data and codebook (H-02), then the README (H-07)

**Goal:** three CSVs that look like a real dock feed, each built to show one behavior, and a
codebook a judge can follow.
**Branch:** `h02-data`, later `h07-readme` **Owns:** `data/` (CSVs, `simulate.py`, `README.md`), later `README.md`
**Needs from others:** nothing. **Gives to:** everyone; push the CSVs by **Fri 10 PM** at the latest.

Steps:
1. `data/simulate.py`, plain Python + numpy + pandas, `seed = 5300`, run as
   `python data/simulate.py` from the repo root, writes the three CSVs.
2. Docks: 15 in Manhattan and 12 in Jersey City, with approximate locations of real public stations
   (taken from the public Citi Bike map, labeled "approximate" in the codebook), capacity 15-35.
   Give each dock a type: `residential` (people leave in the morning, come back in the evening),
   `office` (the reverse) or `transit` (busy at both rush hours).
3. Hourly rate profile per type, e.g. residential pickups 2.0 per slot 7-9 AM, 0.3 midday, 0.8 at
   6-8 PM; drop-offs mirror it. Weekends flatter and later. Write the table in the codebook.
4. Each slot: `pickups ~ Poisson(rate)` but at most `bikes`; `dropoffs ~ Poisson(rate)` but at most the
   open slots; `bikes_next = bikes + dropoffs - pickups`. Riders turned away are not recorded (that is
   what real feeds do too). At slot 0 every dock is reset to half full: the overnight truck.
5. Files:
   - `nyc_in_control.csv`: 30 days starting 2026-09-01, the 15 NYC docks, nothing planted.
   - `jc_planted_shift.csv`: 30 days, the 12 JC docks; from day 21 (2026-09-21) the morning pickup
     rate (7-10 AM) at ONE transit dock near a PATH station triples. Name the dock in the codebook.
   - `edge_case.csv`: 1 dock, 2 days, `bikes = 0` all day, all pickups and drop-offs 0.
6. `data/README.md` (the codebook): one section per file (what it shows, rows, date range, what the
   tool should do with it); a table of every column with units; the rate profiles; and "how to
   collect this for real": poll the public GBFS `station_status.json` every 15 minutes for `bikes`
   and `capacity`, and count trips from the monthly Citi Bike trip files for `pickups`/`dropoffs`.
   Say plainly that every count is simulated.
7. Sanity checks to paste in the PR: rows per file (43,200 / 34,560 / 192), no negative `bikes`, no
   `bikes > capacity`, and the planted dock's mean morning pickups before vs after day 21.
8. Later (H-07, Saturday from 9 AM): replace the root `README.md` with the tool's README following
   `demos/making_readmes/`: what it does, for whom, every input, every function and endpoint, how to
   run it in one command, the live URL, a link to `demo/README.md`.

**Prompt for your agent:**
> Read AGENTS.md, SPEC.md (sections 3, 7 and 9), and docs/assignments.md (the interface and the
> Person 3 section). You work ONLY on task H-02 and write ONLY files inside data/. Follow Person 3
> steps 1-7 exactly; use the data columns in the interface table, in that order. Every number is
> simulated: say so in data/README.md. Run `python data/simulate.py` and the step 7 checks and
> paste the output. Do not commit.

**Done when:** `ls data/*.csv` lists exactly the 3 files, `python data/simulate.py` rebuilds them
identically (`git diff --stat data/` empty after a rerun), and `data/README.md` names every file
and column.

---

## Person 4: API, trip logic, deploy (H-04, H-06, H-08)

**Goal:** the FastAPI app that turns a rider's trip into a recommendation, live on Posit Connect.
**Branch:** `h04-api`, then `h06-deploy` **Owns:** `app/app.py`, `app/trip.py`, `tests/test_trip.py`,
`app/testme.sh`, `app/manifestme.sh`, `app/deployme.sh`, `app/manifest.json`, `app/.python-version`,
`app/README.md`, `.github/`, `.gitignore`
**Needs from others:** Person 1's `qc.py` and Person 2's `pchart.py` (stub them until merged).
**Gives to:** Person 5 (the API URL), everyone (the live URL).

Steps:
1. **First hour:** copy `demos/fastapi/*` into `app/` (load `.claude/skills/fastapi-react-scaffold/SKILL.md`).
   Replace the example routes with the six routes in the interface table, each returning **fake JSON**
   of the right shape. Push it, so Person 5 can start.
2. Imports must work in both places: tests run from the repo root (`from app.qc import ...`), Posit
   Connect runs inside `app/` (`from qc import ...`). Use
   `try: from app.qc import ... except ImportError: from qc import ...`. The CSVs must be copied into
   the deploy too: read them from `app/data/` if present, else `../data/` (the deploy step copies them).
3. `app/trip.py`: `haversine_m`; `window_rates` sums `lam_out` and `lam_in` over the slots from
   `start_slot` that the trip's minutes cross (wrap past slot 95 to the next day; a partial slot counts
   pro rata). `plan_trip`: "now" is the dataset snapshot at the `depart` date and slot; rates from
   `estimate_rates(history, before_date = depart date, day_type)`; pickup candidates = docks within
   1,200 m (15 min at 80 m/min) of `start`; drop-off candidates within 1,200 m of `dest`, with
   arrival = depart + walk + ride (pickup dock to candidate at 250 m/min) and that dock's state now;
   `discount = bikes / capacity < 0.30` at the chosen drop-off. Every assumption from SPEC section 4
   goes in `assumptions`; a dock out of control in `p_chart` that day goes in `warnings`.
4. `tests/test_trip.py`: haversine from (40.70, -74.00) to (40.71, -74.00) is 1,111.9 m (0.01 degree of latitude, Earth radius 6,371 km); `window_rates` over
   exactly 1 slot equals that slot's rates, over 30 minutes equals the sum of 2 slots.
5. Swap the fake JSON for the real functions once H-03 and H-09 are merged. Check:
   `curl -X POST localhost:8000/recommend -H 'Content-Type: application/json' -d '{...}'` on
   `jc_planted_shift` at 2026-09-24 08:10 near the planted dock recommends a different dock.
6. **Deploy by Fri midnight (H-06),** even with fake JSON: load `.claude/skills/connect-publish/SKILL.md`,
   copy `deploy-fastapi.yml` to `.github/workflows/` with `APP_DIR: 'app'`, run
   `bash app/manifestme.sh` on your machine and commit `app/manifest.json`. Ask a mentor for the
   publisher key and add the `CONNECT_SERVER` and `CONNECT_API_KEY` repo secrets yourself
   (GitHub > Settings > Secrets). Open the URL logged out.
7. **Saturday 10 AM (H-08):** clone the repo into an empty folder, run `bash app/testme.sh` and
   `pytest`, both with no extra steps. `git grep -i api_key` finds no real key.

**Prompt for your agent:**
> Read AGENTS.md, SPEC.md, docs/assignments.md (the interface and the Person 4 section) and
> .claude/skills/fastapi-react-scaffold/SKILL.md. You work ONLY on task H-04 and write ONLY the
> Person 4 files. Do step 1 now: copy demos/fastapi into app/ and add the six routes from the
> interface table returning fake JSON of exactly that shape. No statistics in app/app.py: it only
> calls functions. Start the server in the background with a time limit, curl /health and
> /recommend, paste the output, stop it by its PID. Do not commit.

**Done when:** `bash app/testme.sh` starts it; `curl` on `/recommend` for a `data/` file returns
the same probability as calling `app.qc` directly; the Posit Connect URL answers 200 logged out.

---

## Person 5: dashboard and demo walkthrough (H-05)

**Goal:** the page judges use: a rider view and an operator view, plus a written walkthrough.
**Branch:** `h05-dashboard` **Owns:** `app/frontend/`, `demo/`, `.github/workflows/deploy-react-static.yml`
**Needs from others:** Person 4's fake API (first hour). **Gives to:** the demo at the showcase.

Steps:
1. Copy `demos/reactfront/*` into `app/frontend/`; `npm install`; `npm run dev`. Delete the SPC demo
   code (`spc.js`); this page computes **no statistics**, it only shows what the API returns.
2. In `src/api.js` add one function per route in the interface table. `VITE_API_URL` points at
   Person 4's server (local, then the Posit Connect URL).
3. **Rider tab:** a dataset picker; a map (`react-leaflet` with OpenStreetMap tiles) showing the docks;
   click to set start, click to set destination; a departure time picker limited to the dataset's
   dates. Show the recommended pickup and drop-off docks highlighted, each with
   "12 min walk, 94% chance a bike is there", the two alternatives, a "discount" badge when
   `discount` is true, and the `warnings` and `assumptions` lists under a "How to read this" line.
   If the map fights you for more than 45 minutes, use a plain list of docks instead.
4. **Operator tab:** a dock picker and a p-chart drawn as a plain SVG line chart: daily `p` dots,
   a center line at `p_bar`, a dashed UCL, flagged days in red, the baseline period shaded. Beside it
   the `/flagged` list for the chosen date: "send the truck here". If the API sends a `message`
   instead of limits (edge case), show the message, not a chart.
5. Screenshots of both tabs on each dataset go in `demo/`.
6. `demo/README.md`: for each of the 3 CSVs, the exact clicks (or `curl` command), the numbers the
   page shows, and one "how to read this" line. Cover: in-control NYC (no red days), JC planted
   shift (the PATH dock turns red from 2026-09-21 and riders get sent to a neighbor), edge case
   (0% chance, chart refuses). A teammate who did not write it follows it and gets the same numbers.
7. Deploy the page as a static site: copy `deploy-react-static.yml` (and the script it names) from
   `.claude/skills/connect-publish/` with the API URL set; coordinate with Person 4 on secrets.

**Prompt for your agent:**
> Read AGENTS.md, SPEC.md (section 6), and docs/assignments.md (the interface and the Person 5
> section). You work ONLY on task H-05 and write ONLY app/frontend/ and demo/. Do steps 1-4: copy
> demos/reactfront into app/frontend, call the API routes from the interface table, and compute
> nothing yourself; every number shown comes from the API. Run `npm run build`, start the dev
> server in the background, and check both tabs in a browser against the fake API. Do not commit.

**Done when:** `npm run build` succeeds in `app/frontend/`; both tabs show data from the API on
all three datasets; `demo/README.md` exists and a teammate followed it.

---

## Checkpoints (post in the group chat when you hit yours)

| By | Who | What |
|---|---|---|
| Fri 6 PM | 4, 5 | fake API pushed; page shows fake data |
| Fri 10 PM | 3 | 3 CSVs + codebook merged |
| Fri 10 PM | 1, 2 | tests pass; cross-review PASS tables posted |
| Fri midnight | 4 | stub API live on Posit Connect |
| Sat 9 AM | 4, 5 | real numbers on both tabs. **Feature freeze** |
| Sat 11 AM | 3, 5 | README and demo walkthrough merged |
| Sat 12 PM | 4 | fresh-clone test passes |
| Sat 12:30 PM | anyone | Devpost submission: repo link + demo |

Running early? The stretch goal (bike maintenance from miles ridden) needs the team's OK and a new
CONTRACT task. Nothing else gets added after Sat 9 AM.
