# Plan: Big Red Crew, bike share dock recommender (on-campus, due Sat Oct 17 1 PM ET)

Read `SPEC.md` first. Any agent (Claude, Codex, Gemini, Copilot): start with "Read AGENTS.md, SPEC.md
and docs/plan.md. Work ONLY on task H-0n; write only inside its owns paths." One branch per task
(`h03-availability`), small PRs into `main` of the shared fork, a teammate reads each diff.

## Interface contract (agree once, then everyone builds against it in parallel)
- Data columns: `date, slot (0-95), dock_id, name, lat, lon, capacity, bikes, pickups, dropoffs`.
- `app/qc.py`: `estimate_rates(history, day_type) -> DataFrame[dock_id, slot, lam_out, lam_in, vm_out, vm_in]`;
  `p_bike_available(b0, lam_out, lam_in) -> float`; `p_slot_open(b0, capacity, lam_out, lam_in) -> float`
  (rates already summed over the slots crossed); `recommend(candidates, threshold=0.90) -> dict`
  (candidates: `[{dock_id, minutes, p}]`).
- `app/pchart.py`: `daily_failures(history) -> DataFrame[dock_id, date, x, n]`;
  `p_chart(daily, baseline_days=14) -> {dock_id: {p_bar, ucl, lcl, days: [{date, p, flag}], message}}`.
- API: `GET /health`; `GET /docks?dataset=`; `POST /recommend {dataset, start:{lat,lon}, dest:{lat,lon}, depart}`
  -> `{pickup:{dock_id, walk_min, p_bike, alternatives}, dropoff:{dock_id, ride_min, p_slot, discount}, assumptions}`;
  `GET /pchart?dataset=&dock_id=`; `GET /flagged?dataset=&date=`.
- Until the real functions land, the API returns fixed fake JSON of this shape and the page uses it.

## Who does what (five people, disjoint files)
Step-by-step instructions, agent prompts and done checks per person: [`assignments.md`](assignments.md).
| Person | Task | Owns | Proves it with | Est. |
|---|---|---|---|---|
| 1 Stats A | H-03 Poisson availability + recommend | `app/qc.py`, `tests/test_qc.py`, `app/requirements.txt` | SPEC 4 cases A (0.6065), B (0.7358), C (0.3935), recommend picks B; degenerate b0=0, rates 0 -> 0 | 3 h |
| 2 Stats B | H-09 (proposed) p-chart, then review Person 1 | `app/pchart.py`, `tests/test_pchart.py` | x=8,10,12,9,9 -> p_bar 0.1000, UCL 0.1919, LCL 0.0081; x=20 flagged, 15 not; p_bar 0 or 1 -> no limits + message | 3 h |
| 3 Data + docs | H-02 datasets, then H-07 README | `data/` (incl. `simulate.py`), then `README.md` | 3 CSVs + `data/README.md` codebook; seeded rebuild gives identical files; planted shift starts day 21 | 3 h + 2 h |
| 4 Backend + deploy | H-04 API, H-06 deploy, H-08 repo | `app/` minus the files above and `app/frontend/`; `.github/`; `.gitignore` | `testme` starts it; `curl /recommend` on a data file matches H-03 numbers; public URL answers 200 | 3 h + 2 h |
| 5 Front end + demo | H-05 dashboard and walkthrough | `app/frontend/`, `demo/` | rider map + operator p-chart render from the API; `demo/README.md` walks all 3 CSVs | 5 h |

H-01 (this SPEC) is done once the Devpost prompt number is pasted into SPEC section 1.
H-09 is new: the team must agree to add it to `CONTRACT.yaml` (owns `app/pchart.py`, `tests/test_pchart.py`).

## Timeline (Fri 3 PM -> Sat 1 PM)
- Fri by 6 PM: interface agreed; Person 4 has the stub API running, Person 5 the page on fake JSON.
- Fri by 10 PM: H-02 CSVs pushed; H-03 and H-09 tests pass; Person 2 reviews H-03 (PASS table).
- Fri by midnight: stub app deployed to Posit Connect (H-06), so deploy problems surface early.
- Sat by 9 AM: real functions wired in, both views on real data. Feature freeze.
- Sat 9-12: H-05 walkthrough, H-07 README, fresh-clone test (H-08). Sat 12:30: submit on Devpost.

## Decisions
- Track: on-campus. Team Big Red Crew, shared fork `collinshiang/sixsigmahackathonBRC`.
- Statistics: Poisson dock availability (rider) + p-chart of empty/full snapshots (operator). Picked as default; team had no preference.
- Stack: FastAPI + React from `demos/fastapi` and `demos/reactfront`. Picked as default; webR dropped (no scaffold, riskier deploy).
- Data is dock-level snapshots, not per-bike rows: per-bike every 15 min is about 1.7M rows and only the
  out-of-scope maintenance piece needs it.

## Risks
1. Statistics wrong under a nice UI: no wiring into the API until the SPEC 4 tests pass and Person 2's review is PASS.
2. Deploy fails late: deploy the stub Friday night; ask a mentor for the publisher key early.
3. Merge conflicts across five agents: owns paths never overlap; change the interface contract only by team agreement, in this file.
