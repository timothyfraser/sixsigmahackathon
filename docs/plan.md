# Plan: Rush Hour Autopilot (team 2027win)

Source of truth: `SPEC.md` (template answers) and `docs/methods.md` (rules, formulas, KA-n known answers; same section numbers). This plan only orders the work.
Stack: R Shiny in `app/`; statistics in `app/qc.R`, simulation in `app/sim.R`; tests in `tests/test-*.R` (testthat).
Tasks H-10 to H-18 are **PROPOSED** and are not in `CONTRACT.yaml` until the team says yes.
Because they all edit `app/qc.R` and `app/app.R`, they run **one at a time**.

## Tier 1 (core): a runnable tool first
| Id | Work | Owns | Needs | Acceptance (known answer + degenerate) | Est |
|---|---|---|---|---|---|
| H-02 | Seeded generator, 3 scenario CSVs, codebook | `data/` | methods section 7 schema | CONTRACT DoD as written; re-running `data/generate_data.R` reproduces the files byte for byte; `planted_shift` starts on weekday 11 | 1.5 h |
| H-03 | Loader and schema validator, 4.1 grid, unusable minutes and coverage, p charts, I-MR, greedy plan, paired CI | `app/qc.R`, `tests/` | H-01 | KA-1, KA-1b(a-d), KA-2, KA-2b, KA-2c, KA-3 (+ constant data: limits NA, data shown), KA-4, KA-5, KA-5b, KA-11; structural errors stop; row-level problems are rejected or flagged and listed (methods section 7), never stopping the load | 2.5 h |
| H-04 | Copy `demos/shinyapp` to `app/`; Overview, Stations, Quality (p, I-MR) and Rebalancing tabs; four R scripts | `app/` except `qc.R` | H-02, H-03 | CONTRACT DoD; Playwright shows the H-03 numbers for `data/baseline.csv` | 2 h |
| H-06 | Deploy: `deploy-shiny-r.yml`, `manifest.json` | CONTRACT list | H-04 | CONTRACT DoD; **prepared only**, deploy only after the team says yes | 1 h |
| H-10 | Simulation engine: van, task and event model, reservations, policies none and reactive, paired seeds; Improvement tab | `app/sim.R`, `tests/test-sim.R`, `app/app.R` | H-03, H-04 | KA-4b; conservation holds at every event; same seed gives identical output; primary CI already uses 98.333% (the alpha = 0.05/3 family) | 2.5 h |
| H-05 | Demo walkthrough for each scenario | `demo/` | H-04, H-10 | CONTRACT DoD | 0.5 h |
| H-07 | README (draft now, final at the end) | `README.md`, `app/README.md` | H-04 | CONTRACT DoD | 1 h |

## Tier 2: in scope, after tier 1 passes review
| Id | Work | Acceptance | Est |
|---|---|---|---|
| H-11 | c chart, X-bar/R response time, Cpu (only with a USL entered and the process in control) | KA-6, KA-7; R-bar = 0, a missing USL or an out-of-control chart gives NA with a reason; dispersion warning above 1.5 | 1.5 h |
| H-12 | Historical Kaplan-Meier, RMST, F(10/20/30) ("History" panel) | KA-8; no usable 07:00 starts gives NA with a reason; censoring at unknown gaps tested | 1 h |
| H-13 | Forecast step 5a, fixed Poisson rates ("Now" panel) | KA-8b (within 4 simulation SE), KA-8c no look-ahead; stale inventory gives NA | 1.5 h |
| H-14 | Forecast step 5b, day bootstrap | KA-8d; output keeps the simulation SE and the parameter range as separate fields | 1 h |
| H-15 | Predictive policy; 3-policy comparison | identical demand streams across the 3 policies for each seed; KA-5 (primary at 98.333%, secondary labelled unadjusted 95%) | 1.5 h |

## Tier 3: in scope, after tier 2
| Id | Work | Acceptance | Est |
|---|---|---|---|
| H-16 | Empirical availability and R(tau) for series, parallel and k-out-of-n | KA-9; zero known minutes gives NA; the independence value is shown only as a contrast | 1 h |
| H-17 | Qualitative fault trees and the cause mapping (Diagnosis tab) | KA-10 and the contradiction rule; zero failures shows counts of 0 and shares as NA | 1 h |
| H-18 | Task status updates in the web page (session only, no database) | the section 7 transition and time rules; invalid moves are rejected; checked with Playwright | 1 h |

**Order:** H-09 (SPEC/methods split, in progress) and H-01 review, then H-02 and H-03 in parallel (disjoint files), H-04, H-06 (prepare), H-10, H-05 and H-07 drafts, H-11 to H-18 in turn, H-07 final, H-08.
**Teammate-owned, independent of the agent:**
- H-02 (`data/generate_data.R`, the 3 CSVs, `data/README.md`), from the `docs/methods.md` section 7 schema.
- H-05 (`demo/README.md`).
- H-07 drafting.
- Each person checks out only their own task in `CONTRACT.yaml`.

## Decisions
- Stack: R Shiny from `demos/shinyapp`; no separate API.
- Scope: three tiers; tier 1 must run end to end before tier 2 starts.
- Failure: strict zero or a closed flag; early warning (2 bikes or 2 docks) is for ranking only.
- USL: entered by the operator; no USL means no Cpu.
- D-1: three long-form scenario CSVs with a `table` column; an internal format, not native GBFS.
- D-2: Poisson per station x 15-min bin, fixed rates first, then day bootstrap; the three uncertainty sources are reported separately; no look-ahead.
- D-3: `stale_limit` = 2 min (demo assumption); interval [m, m+1) uses the latest valid snapshot at or before m.
- D-4: primary metric = unusable minutes, Bonferroni 98.333% for the 3 pairwise comparisons; secondary metrics exploratory, unadjusted 95%.

## Risks
1. **Scope against time** (about 19 h to the Sat 1 PM deadline). Feature freeze at Sat 09:00; cut tiers from the bottom (H-18 first). Docs and the Devpost entry are never cut.
2. **Deploy failures** (package versions, a stale manifest). Deploy right after H-04 and rewrite `manifest.json` after every package change.
3. **Large status data slows Shiny.** Build the grid once at startup and cache it; if the app is still slow, shrink the status window to 06:30-10:30.
