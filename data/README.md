# BikeWise simulated data

For requirements to apply BikeWise to another city, see
[City input requirements](CITY_INPUT_REQUIREMENTS.md).

These datasets implement `system_architecture.md` plus the team's approved
simulation decisions, including replacing the fictional network with Tampa.
Only the location identities and coordinates are real. All bikes,
movements, zoning, demand, inventory and capacities are
synthetic; this is not measured Citi Bike or Bublr ridership.

## Files and use

Each of `jersey_city`, `milwaukee`, and `tampa` has:

- `<city>.csv.gz`: the complete movement dataset, compressed CSV.
- `<city>.rds`: the same data frame with a timezone-aware POSIXct time column.
- `distances/<city>.csv`: 27-by-27 distance matrix in long form, 729 rows.
- `stations/<city>.csv`: station metadata lookup, not additional movement columns.
- `zoning/<city>.csv`: synthetic zone assignment for each selected station.

```r
movement <- readRDS("data/jersey_city.rds")
grid <- read.csv("data/distances/jersey_city.csv")
snapshot <- movement[movement$time == movement$time[1], ]
# Alternatively, read the portable CSV and explicitly parse its offset:
movement_csv <- read.csv(gzfile("data/jersey_city.csv.gz"), colClasses = "character")
movement_csv$time <- as.POSIXct(movement_csv$time,
  format = "%Y-%m-%dT%H:%M:%S%z", tz = "America/New_York")
```

There are 405 bikes (15 initially per station), 8,640 five-minute snapshots
and 3,499,200 rows per city. Dates are September 16 through October 15, 2026,
inclusive; final snapshot is 23:55. Jersey City and Tampa use
`America/New_York`; Milwaukee uses `America/Chicago`. CSV timestamps include
UTC offsets; RDS timestamps retain their local timezone. Dates are fixed so
a later rebuild produces the same history. This period does not cross DST.

## Movement codebook: exactly three columns

| Column | Type | Meaning |
|---|---|---|
| `BIKEID` | character | Persistent simulated bike identifier, unique within and across cities. |
| `DOCID` | character | Published station name in Jersey City/Milwaukee, real intersection name in Tampa, or the string `"0"` while away from all docks. |
| `time` | POSIXct in RDS; offset timestamp in CSV | Date and time of the five-minute snapshot. |

Every bike appears once at every snapshot. No duration, destination, mileage,
maintenance, speed or extra status column is included. Dock changes require
at least one intermediate `"0"` observation. Same-station returns are allowed.

## Distance codebook: exactly three columns

| Column | Type | Meaning |
|---|---|---|
| `dockID1` | character | Origin station name, matching `DOCID`. |
| `dockID2` | character | Destination station name, matching `DOCID`. |
| `distance` | numeric, miles | Shortest distance on the modeled bicycle road network, including station-to-node connectors. |

All ordered pairs are included; self-distance is zero. Real-city distances
can be asymmetric because bicycle one-way rules are respected. `"0"` is not
a location and has no distance row. Distances never influence simulation
transit persistence or departure/return selection.

## Metadata and provenance

The station lookup columns are `station_id` (official character ID in Jersey
City/Milwaukee; `osm-node-<node ID>` in Tampa), `dockID` (published station name
or real Tampa intersection name), `lat` and `lon` (WGS84 decimal degrees).
Tampa replaces the previous fictional network. Its locations are real street
intersections; the bike docks at those locations are hypothetical, not claims
that an installed dock exists there. All bike activity and zoning remain synthetic.

- Citi Bike station information: https://gbfs.lyft.com/gbfs/2.3/bkn/en/station_information.json
- Citi Bike region identification: https://gbfs.lyft.com/gbfs/2.3/bkn/en/system_regions.json
- Bublr station information: https://gbfs.bcycle.com/1/bcycle_bublr/station_information.json
- Tampa intersections: shared road-junction nodes in the cached OpenStreetMap extract.
- Road/path source: OpenStreetMap contributors, https://www.openstreetmap.org/copyright
- Download service: https://overpass-api.de/api/interpreter

`sources/<city>_stations.json` records selected station metadata, source URL,
retrieval UTC timestamp and selection center. It does not retain live inventory
or real trip counts. Cached OSM roads are in `sources/<city>_roads.json` and
include their OSM base timestamp. Station inputs are reusable for later runs;
do not refetch them unless deliberately changing the network.

Jersey City uses the official `JC District` region, excluding Hoboken, and the
27 nearest stations to (40.7178, -74.0431). Milwaukee uses the 27 nearest Bublr
stations to (43.0389, -87.9065). These are downtown subsets, not full networks.
Station names are kept exactly as published, including any trailing spaces.
Tampa uses the 27 nearest distinct named intersections to (27.9486, -82.4572),
within downtown Tampa. Each selected OSM node belongs to at least two named
streets and has at least three road branches, excluding simple street-name
changes. Intersection names are joined with ` & `. `sources/tampa_stations.json`
records the source node IDs, coordinates, center, retrieval UTC timestamp and
OSM base timestamp. No real Tampa bike inventory or trip activity is imported.

## Distance method and limits

`prepare_networks.py` builds a directed graph of OSM ways. Edge weights sum
haversine segment lengths in miles. It includes ordinary roads/cycleways and
paths explicitly permitting bicycles, excludes motorways/steps and prohibited
bicycle access, and honors ordinary and bicycle-specific one-way tags.
Dijkstra's algorithm finds shortest-distance paths, not fastest driving routes.

Stations connect to the nearest node in the largest strongly connected road
component, using a straight-line connector. Preparation fails if a connector
exceeds 0.15 miles. Roads are downloaded within the station envelope plus a
0.04-degree margin. Thus these are shortest paths **on this modeled graph**,
not a guarantee of globally shortest or fully legally navigable routes.
Turn restrictions, conditional access, elevation, crossings, road works,
safety preferences and exact dock access geometry are not modeled. These
limitations matter before using the matrices for actual rider navigation.

Tampa uses the same directed bicycle road/path graph and shortest-distance
method as the other real cities. Its OSM download bounds are 27.9086–27.9886
latitude and -82.4972–-82.4172 longitude. Its real road matrix replaces the
previous fictional rectangular-grid matrix.

## Synthetic movement model

`simulate_bikes()` is a seeded discrete-time simulation. It conserves all
405 bikes, and each station has synthetic capacity 30. The initial state
places exactly 15 bikes at every dock. These capacities are not real metadata.

At each step, docked bikes may depart according to a relative time-of-day
profile: weekday peaks at 08:30 and 17:30, smaller lunch/evening peaks,
later weekend activity, Friday/Saturday nightlife and corresponding early
morning activity. Gaussian bumps are defined in `demand_profile()`.
Station activity/attractiveness multipliers are seeded uniform draws from
0.75 to 1.25. There is no separate student factor, measured land-use
classification, observed ridership calibration, weather or holiday model.

Each city has exactly nine residential, nine office and nine retail stations.
The assignments are **synthetic zoning**, not verified real land use. Real-city
stations are sorted west to east (latitude/name break ties) and divided into
three contiguous groups: residential, office, retail. Tampa follows the same
geographic assignment rule; the zone labels do not describe verified land use.
`zoning/<city>.csv` has two columns: `dockID` (station name) and `zone`
(`residential`, `office` or `retail`). Existing mappings are reused on rebuild;
edit those lookup files to change assignments. Custom calls may instead pass a
`zone` column in the station input. The movement data still has only three columns.

`zone_profiles()` adds synthetic time-dependent departure and destination
weights, separately from overall demand:

- Weekday mornings: residential departures and office destinations peak at
  08:30. Office destinations remain attractive through the workday, with low
  ordinary departures while people are working.
- Weekday evenings: office departures and residential destinations peak at
  17:30. Residential departures are suppressed during this return-home peak.
- Lunch: office departures toward residential/retail peak around noon;
  return-to-office weights peak around 13:00, with inverse residential movement.
- Retail: destination weights rise on evenings and weekend daytime. Departures
  are random, with additional late-evening and weekend-late-afternoon activity.
  There is no fixed visit or return deadline: retail dwell and transit are
  stochastic. Bikes can stay for multiple snapshots or return to the same dock.

These weights generate imbalance through actual departures and arrivals.
No bikes are teleported, relabeled after generation, or rebalanced by a truck.
Weights favor zones rather than requiring a particular origin/destination pair;
the model does not track individual rider itineraries or validate human behavior.
The departure baseline is calibrated to target **33.3% undocked observations**
averaged over the complete 30-day history. `target_usage = 0.333` replaces the
earlier three-trips-per-bike-per-day setting. Calibration propagates expected
probabilities for each dock and the away state through all 8,640 time steps,
including the initially all-docked state, then solves for the departure-rate
multiplier. The hourly demand profile and station heterogeneity remain active:
usage is not fixed at 33.3% at every snapshot. Seeded random realizations can
differ slightly; validation allows 0.2 percentage points around the target.
Capacity is enforced during simulation, not during the expectation calculation.
If capacity changes the realized usage by more than 0.1 percentage points,
generation adjusts the departure multiplier using the realized usage odds and
replays the entire seeded simulation, up to six attempts. It never edits
individual observations to force the target. Future stochastic runs are still
validated within 0.2 percentage points of the target.
This is a synthetic utilization scenario, not an estimate of real ridership.

Previously undocked bikes have a 25% probability of returning per five-minute
step, independently of distance and time of day. This produces a geometric
number of away snapshots with mean four steps (20 minutes). It is an
explicit synthetic transition assumption, not an estimated trip duration.
Keeping this return probability while increasing usage raises trip frequency
to approximately 24 departures per bike per day, replacing the previous
roughly-three-trip scenario.
No mph parameter is needed. Returns choose randomly among docks with room,
weighted by time-dependent zone attraction and synthetic station attractiveness;
if all docks were full the bike
would remain away. This supersedes the earlier proposed nearest-dock rerouting,
which would couple movement to distance. No destination is preassigned.

Same-step departures free capacity before returns are assigned. Newly
departed bikes cannot return until the next step, guaranteeing an observable
`"0"` state. All bikes remain in the modeled system: there is no truck,
maintenance, loss, recovery, fleet addition or removal in this initial model.
This baseline is for exercising the UI and future projection code, not proof
that a future forecasting model will generalize to real systems.

## Rebuild and verify

From the repository root (R and Python 3 standard library; no extra packages):

```sh
python3 data/prepare_networks.py --stations-only
# Review printed selections; this only requests station metadata.
python3 data/prepare_networks.py
# Road download needs internet. Subsequent runs reuse source caches.
Rscript simulate_data.R
Rscript data/validate_simulation.R
python3 data/validate_tampa_locations.py
```

Movement generation and validation run offline once station/matrix inputs
exist. Rebuilding with the same inputs and seeds (5301, 5302, 5303) yields
identical data-frame contents. Compressed-file bytes may depend on tool versions.
Existing uncompressed `<city>.csv` exports are refreshed too, so local copies
cannot retain an older usage scenario. They remain excluded from Git because
of their size; the compressed CSV and RDS are the shared data formats.
Source the simulator to call `simulate_bikes()` for smaller custom runs without
automatically writing output. Live continuation is a later feature: concatenating
an independently initialized run would reset bikes and should not be done.

Validation checks seed reproducibility, zero-demand behavior, exact columns,
one record per bike per snapshot, five-minute spacing, fleet conservation,
capacity, valid dock states, intervening transit observations, complete pairwise
distances, and a hand-checkable shortest-path example. It explicitly rejects
duplicate bike/full-timestamp pairs, counts each bike in the complete CSV and
RDS, checks average usage against 33.3% (+/-0.2 percentage points), and verifies
weekday rush-hour usage exceeds weekday overnight usage. It prints observed
departure rate and return probability as simulation diagnostics.
Zoning checks verify nine stations per type, office morning gain/evening loss,
inverse residential flows, office/residential lunchtime reversals, retail
evening/weekend-morning inflows, and higher weekend midday retail inventory.

`validation/usage_summary.csv` records the target, realized overall usage and
weekday rush/slow-period averages for each city. `validation/usage_by_hour.csv`
records mean usage by city, weekday/weekend, and local hour. Both are validation
reports, not additional columns in the movement data. Per-bike counts remain
in `validation/observations_per_bike.csv`.

Additional zoning reports:

- `validation/zone_inventory_by_hour.csv`: `city`, `zone`, `day_type`, `hour`
  (local 0–23), `mean_bikes_per_station` (mean docked count, out of capacity 30).
- `validation/zone_net_flows.csv`: `city`, `period`, `zone`, `net_bikes`
  (total arrivals minus departures across all days in that period).
- `validation/station_imbalance.csv`: `city`, `dockID`, `zone`, `mean_bikes`,
  `min_bikes`, `max_bikes`, `empty_percent` and `full_percent` (percentage of
  snapshots with zero bikes or exactly 30 bikes). Counts refer to docked bikes.

Flow windows use local time: weekday morning 07:00–10:25, weekday evening
16:00–18:55, lunch-out 11:30–12:25, lunch-back 12:30–13:55, retail nights
19:00–21:55, weekend retail arrivals 08:00–10:55. Weekend retail stock is also
compared with weekday stock between 11:00 and 15:55. Net flows can be positive
or negative without violating bike conservation because other bikes are away.

`python3 data/plot_zone_imbalance.py` uses matplotlib to draw the hourly zone
inventory reports as `validation/zone_imbalance.png` and `.svg`.

Verified generated outputs:

Current measurements are regenerated by `Rscript data/validate_simulation.R`
and stored in `validation/usage_summary.csv` and `validation/usage_by_hour.csv`.

The zoning scenario supersedes the earlier unzoned usage measurements. Use the
generated reports above for current figures and zone-specific inventories.

`validate_tampa_locations.py` checks all 27 Tampa locations against the cached
OSM node coordinates, verifies named-street junctions and distinct IDs, confirms
all 729 road distances are at least the corresponding straight-line distances,
and reproduces a 5-mile shortest-path known answer. It runs offline with Python
3.9+ and requires the cached Tampa road extract (or rerun preparation to fetch it).

Rush-hour checks use 07:00–08:59 and 16:00–18:59; slow-hour checks use
02:00–04:59, always in each city's local timezone on weekdays.

Largest real-city station-to-road connectors were 0.0229 miles (Jersey City)
and 0.0215 miles (Milwaukee); all Tampa intersections are directly on graph nodes
(zero connector distance). Each CSV was independently checked to contain
3,499,200 data rows. A directed shortest-path known-answer check chooses the
5-mile route (2 + 3) instead of a direct 10-mile edge.

In a real system, the operator would derive these snapshots from persistent
bike IDs and dock entry/exit events, recording `0` between dock visits. A public
station-count feed alone cannot identify all individual bike movements. Road
distances would be supplied independently from a reviewed local bicycle network.
