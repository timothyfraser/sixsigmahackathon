# Applying BikeWise to another city

This guide describes the information a city/operator would supply, separately
from what a rider would enter. It distinguishes the current simulator from
the future availability and recommendation software. Proposed production
schemas below are design guidance, not an implemented city import interface.

## 1. City and operator setup

| Information | Purpose | Suggested source |
|---|---|---|
| Dock IDs, names, latitude and longitude | Identify locations and display them on a map. | Operator station register or public station-information feed. |
| Operational capacity at each dock | Determine whether a returned bike can be accepted. | Operator infrastructure/maintenance records. |
| Current rentable bikes and free docks, with observation time | Establish the starting inventory for a forecast. | Operator status feed. |
| Historical rental/return activity | Estimate station demand by local time and weekday/weekend. | Trip events, dock entry/exit events, or repeated bike snapshots. |
| Bicycle road distances and/or travel times between docks | Estimate arrival times and compare candidate locations. | A reviewed bicycle routing network or externally supplied matrix. |
| Local timezone | Interpret commute periods, timestamps and daylight-saving transitions. | City configuration, using an IANA name such as `America/New_York`. |
| Zoning, where available | Provide an explanatory demand signal or a synthetic scenario. | Operator-supplied classification or verified land-use data. |

Keep stable dock IDs separate from display names. Names can change or repeat.
Use WGS84 decimal-degree coordinates, miles for distance and mph for speed
assumptions. Time durations, if supplied, should explicitly use minutes.

### Capacity and inventory definitions

Distinguish installed capacity, operational capacity, rentable bikes,
unrentable bikes occupying usable docks, and free usable docks. A disabled
bike may occupy a dock without being available for pickup. Do not assume
`free_docks = capacity - rentable_bikes` unless those definitions justify it.
Record capacity changes over time where infrastructure becomes unavailable.

Zoning need not be split equally in a real city. Our nine residential, nine
office and nine retail assignments are synthetic demonstration choices, not
verified real land use. With sufficient activity history, zoning could be
optional; the future forecasting method must define how it uses missing or
mixed classifications.

## 2. Historical activity: two alternatives

**Bike snapshots:** the current movement format is exactly:

| Column | Meaning |
|---|---|
| `BIKEID` | Persistent bike identifier. |
| `DOCID` | Dock reference, or the string `"0"` while away from docks. |
| `time` | Full date/time including timezone information, every five minutes. |

The demos use dock names as `DOCID`. A production interface should use stable
dock IDs consistently, resolving names through the station lookup. This change
requires an agreed interface; simply mixing IDs and names will break joins.

**Rental/return events:** a proposed alternative is `event_id`, `dock_id`,
`event_type` (`rental` or `return`), and `time`, with an optional `bike_id`.
Station-level events can support arrival/departure estimates without individual
bike identities. They still need an inventory starting point and records of
non-rider inventory changes.

Five-minute snapshots can miss departures and returns occurring between
observations. A bike seen at the same dock twice may have taken a short trip.
Do not interpret snapshot-derived counts as a complete event log.

The demo has 30 days of history. This is not a universal minimum or a guarantee
of forecast accuracy. The eventual model must assess coverage, missing data,
weekday/weekend representation and changes in demand before making claims.

## 3. Proposed production files

| File | Proposed fields |
|---|---|
| `city_config` | `city_id`, `timezone`, distance/time units, source dates. |
| `stations.csv` | `dock_id`, `name`, `lat`, `lon`, `operational_capacity`. |
| `station_status.csv` | `dock_id`, `time`, `rentable_bikes`, `free_docks`; optional disabled-bike counts. |
| `zoning.csv` | `dock_id`, `zone`; optional for a history-based model. |
| `distances.csv` | `dockID1`, `dockID2`, `distance` in miles, matching our current distance format. |
| History | Either the three-column bike snapshots or the event schema above. |

For N docks, a complete distance matrix has N² ordered pairs, including zero
self-distances. Opposite directions can differ. Label whether routes minimize
distance or time, identify the bicycle access rules and retain routing source
and retrieval date. An unreachable pair should be explicitly unavailable,
never given a fabricated distance or a zero distance.

If travel time is calculated from distance and an assumed speed, disclose the
assumption. The current simulator deliberately does not use distances to
determine transit persistence; using them for rider arrival predictions is a
separate future feature.

## 4. Rider inputs

The rider should not upload city infrastructure or historical records. A future
rider interface would ask for their starting location, intended destination
or return area, departure time (possibly defaulting to now), and acceptable
walking/search distance. Pickup versus return mode determines which inventory
is relevant. Walking/cycling speeds may be documented defaults rather than
additional mandatory rider inputs.

## 5. Creating another synthetic demonstration

In addition to locations and zone assignments, specify:

- Fleet size and initial distribution across docks.
- Station capacities and initial availability.
- Simulation dates, timezone, interval and random seed.
- Average undocked usage target.
- Departure/destination patterns by zone, hour and day type.
- Return/persistence behavior and treatment of full destinations.

Our current assumptions are 15 initial bikes per dock, synthetic capacity 30,
five-minute observations, 33.3% average undocked usage, and a 25% return chance
per five-minute step. These are configurable scenario choices, not measured
real-world constants. The return rule permits long undocked periods and, with
the usage target, generates roughly 24 departures per bike per day.

`simulate_bikes()` accepts a station data frame, optional `zone` column, city
label, timezone, dates, seed and simulation parameters. `generate_all()` still
enumerates the three demo cities, and the validation script expects 27 docks
and 405 bikes. Supporting arbitrary cities through one import command will
require generalizing those wrappers and checks. Per-station capacities and
real event ingestion are proposed capabilities, not currently implemented.

## 6. Validation before using a new city

- Confirm unique dock IDs and valid coordinates. Real intersections do not
  establish that actual bike docks exist there; label hypothetical docks.
- Check every history/status/zoning/matrix reference against the station lookup.
- Reject duplicate bike/full-timestamp pairs and invalid inventory counts.
- Parse full dates, offsets and local timezone; define how gaps and DST are handled.
- Validate snapshot spacing and per-bike coverage for the declared observation window.
- Reconcile inventory with pickups, returns and any truck, maintenance or fleet changes.
- Check capacities, distance units, routing coverage and unavailable pairs.
- Keep synthetic behavior separate from measured activity, with source metadata.
- Evaluate future forecasts on later observations excluded from fitting, and
  report limitations before treating predictions as reliable probabilities.

Optional later inputs include planned rebalancing events, maintenance status,
weather, holidays and local events. Their usefulness depends on the chosen
model; they are not prerequisites for our current simulator.

See [the data codebook](README.md) for current demo files, provenance,
simulation assumptions and commands to reproduce their validation.
