# Rush Hour Autopilot — H-02 simulated datasets

**Source:** All rows are synthetic (`data_source=simulated`), produced by `generate_data.R` with seed **20261016**. No personal or municipal transaction data are included. No external dataset or third-party data license is involved. The schema is an internal adaptation inspired by GBFS, **not** a native GBFS feed. See https://github.com/MobilityData/gbfs for GBFS specifications. Demo geography near Ithaca is invented and does not identify actual docks.

Run `Rscript data/generate_data.R` from repository root. The script uses only base R and overwrites exactly three scenario CSVs. Output is deterministic under the same R version/time-zone database. Time zone is `America/New_York` (all example dates are EDT, -04:00). `timestamp` denotes the instant of a snapshot; interval `[m,m+1)` uses the latest valid snapshot at or before m, subject to a 2-minute staleness limit. A missing snapshot is **not** zero inventory.

## Files

- `baseline.csv`: 25 stations, 2 vans, 20 weekdays, snapshots 06:00–11:00 ET. Three completed tasks per weekday for response-time analysis.
- `planted_shift.csv`: identical station layout; from weekday 11, first eight stations exhibit planted return-side dock faults and demand surge. First ten weekdays serve as baseline. These are intentionally artificial anomalies, not measured operating conditions.
- `edge_case.csv`: two stations, one weekday; station S001 never fails; S002 includes an omitted snapshot at 07:05, conflicting duplicates at 07:06 and a gap at 07:10–07:13. These rows are deliberately invalid for the status-grid parser; they must be flagged rather than silently repaired.

All files use the union schema below with `table` in {`stations`,`status`,`attempts`,`tasks`}. Non-applicable columns are empty strings. Booleans are uppercase `TRUE`/`FALSE`. Count units are bikes or docks, time durations are minutes, coordinates WGS84 decimal degrees.

| Field | Applies to | Type / units | Rule |
|---|---|---|---|
| table | all | string | One of four table names |
| data_source | all | string | Always `simulated` |
| station_id | stations/status/attempts | string | Foreign key to stations |
| station_name | stations | string | Display label |
| latitude, longitude | stations | numeric degrees | WGS84; [-90,90], [-180,180] |
| capacity | stations | integer docks | >0 |
| region | stations | string | Residential, Office, Mixed |
| timestamp | status/attempts | ISO8601 offset | America/New_York |
| bikes_available, docks_available | status | integer counts | >=0; sum <= capacity |
| is_renting, is_returning | status | boolean | Service-enabled flags |
| attempt_id | attempts | string | Unique |
| attempt_type | attempts | enum | rent / return |
| success | attempts | boolean | Attempt outcome, never inferred from inventory |
| failure_reason | attempts | enum | Empty on success; rent: no_bike/bike_fault/dock_fault/station_closed/app_error; return: no_dock/dock_fault/station_closed/app_error |
| task_id | tasks | string | Unique |
| van_id | tasks | string | Required except planned |
| source_station_id, destination_station_id | tasks | string | Existing distinct stations |
| planned_quantity | tasks | integer bikes | >0 |
| actual_quantity | tasks | integer bikes | 0..planned, required when completed |
| assigned_at, arrived_at, completed_at | tasks | ISO8601 offset | Ordered timestamps; required according to task state |
| status | tasks | enum | planned / assigned / in_progress / completed / cancelled |

Missing-value rules: empty means not applicable or missing, **never zero**. For station status, reject missing/negative counts, unknown station IDs and capacity violations. Identical duplicate snapshots are deduplicated; all differing rows at a station/timestamp are rejected. Unknown minutes are excluded from numerator and denominator. Early warning means 0 < bikes <= 2 or 0 < docks <= 2 and is not itself failure. Failure means zero bikes or disabled renting, zero docks or disabled returning. Either-unusable is the union.

**Caveats:** Synthetic attempts are explicit simulated events, not estimates of people turned away. The scenarios illustrate chart behavior but do not establish real-world process capability or demand. The planted anomaly is engineered, not a statistical guarantee of every chart implementation. The generator is a test fixture, not the event-conserving policy simulator in `app/sim.R`.


## Collecting equivalent real inputs

For real deployment, obtain the station registry (IDs, coordinates, capacity and region) from the operator; poll station status and service flags about once per minute, preserving the feed's actual observation time; collect each successful and failed rent/return attempt from kiosk/app transaction logs with its recorded reason; and obtain van IDs, quantities, task states and event times from the dispatch system. Keep the source observation times and missing fields. Native GBFS needs an adapter and does not supply the attempt and dispatch logs.

## Additional local checks

After generation, run `python3 tests/validate_schema.py` and `python3 data/check_scenarios.py` from the repository root. The second command checks scenario dimensions, references, booleans, reason codes, offset timestamps, intentional edge conflicts/gaps, and day-11 return-p and I-MR signals against the first ten weekdays. It verifies KA-2 and KA-3 arithmetic and degenerate limits before applying them. This is independent fixture validation; the application loader and simulation engine are not present on this branch and are not verified by these checks.

`data/run_h02.command` regenerates (overwriting the three CSVs) and runs both validators. It uses Rscript from PATH, or an executable specified with RSCRIPT_BIN. In the original local task workspace it also recognizes the isolated runtime at ../../work/r-runtime/bin/Rscript relative to the repository. No runtime is bundled in this repository.

Validation note for this seed: the planted return-p chart signals on weekdays 9 and 10 as well as 11–20 when limits are estimated from weekdays 1–10. The I-MR chart signals exactly on weekdays 11–20. This demonstrates detection of the planted change but does not establish a statistically in-control pre-change p-chart baseline. Further calibration and application-level review remain necessary before calling the complete H-02 statistical acceptance finished.
