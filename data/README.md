# BikeWise simulated data

These datasets implement `system_architecture.md` plus the team's approved
simulation decisions. Real station identities/coordinates are the only real
bikeshare inputs. All bikes, movements, demand, inventory and capacities are
synthetic; this is not measured Citi Bike or Bublr ridership.

## Files and use

Each of `jersey_city`, `milwaukee`, and `atlantis` has:

- `<city>.csv.gz`: the complete movement dataset, compressed CSV.
- `<city>.rds`: the same data frame with a timezone-aware POSIXct time column.
- `distances/<city>.csv`: 27-by-27 distance matrix in long form, 729 rows.
- `stations/<city>.csv`: station metadata lookup, not additional movement columns.

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
inclusive; final snapshot is 23:55. Jersey City and Atlantis use
`America/New_York`; Milwaukee uses `America/Chicago`. CSV timestamps include
UTC offsets; RDS timestamps retain their local timezone. Dates are fixed so
a later rebuild produces the same history. This period does not cross DST.

## Movement codebook: exactly three columns

| Column | Type | Meaning |
|---|---|---|
| `BIKEID` | character | Persistent simulated bike identifier, unique within and across cities. |
| `DOCID` | character | Real station name (fictional station name for Atlantis), or the string `"0"` while away from all docks. |
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

The station lookup columns are `station_id` (official character ID), `dockID`
(published station name), `lat` and `lon` (WGS84 decimal degrees). Atlantis
has fictional IDs/names and blank geographic coordinates: its network is
defined in miles rather than placed at an invented real-world location.

- Citi Bike station information: https://gbfs.lyft.com/gbfs/2.3/bkn/en/station_information.json
- Citi Bike region identification: https://gbfs.lyft.com/gbfs/2.3/bkn/en/system_regions.json
- Bublr station information: https://gbfs.bcycle.com/1/bcycle_bublr/station_information.json
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

Atlantis has a fully synthetic, connected 9-column by 3-row rectangular
street grid, with 0.25-mile blocks. Distance is the Manhattan shortest path
along its streets. Dock 01 to Dock 27 is (8 + 2) * 0.25 = 2.5 miles.

## Synthetic movement model

`simulate_bikes()` is a seeded discrete-time simulation. It conserves all
405 bikes, and each station has synthetic capacity 30. The initial state
places exactly 15 bikes at every dock. These capacities are not real metadata.

At each step, docked bikes may depart according to a relative time-of-day
profile: weekday peaks at 08:00 and 17:30, smaller lunch/evening peaks,
later weekend activity, Friday/Saturday nightlife and corresponding early
morning activity. Gaussian bumps are defined in `demand_profile()`.
Station activity/attractiveness multipliers are seeded uniform draws from
0.75 to 1.25. There is no separate student factor, measured land-use
classification, observed ridership calibration, weather or holiday model.
The departure baseline targets roughly three trips per bike per day, with
actual counts dependent on demand and constraints.

Previously undocked bikes have a 25% probability of returning per five-minute
step, independently of distance and time of day. This produces a geometric
number of away snapshots with mean four steps (20 minutes). It is an
explicit synthetic transition assumption, not an estimated trip duration.
No mph parameter is needed. Returns choose randomly among docks with room,
weighted by synthetic station attractiveness; if all docks were full the bike
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
```

Movement generation and validation run offline once station/matrix inputs
exist. Rebuilding with the same inputs and seeds (5301, 5302, 5303) yields
identical data-frame contents. Compressed-file bytes may depend on tool versions.
Source the simulator to call `simulate_bikes()` for smaller custom runs without
automatically writing output. Live continuation is a later feature: concatenating
an independently initialized run would reset bikes and should not be done.

Validation checks seed reproducibility, zero-demand behavior, exact columns,
one record per bike per snapshot, five-minute spacing, fleet conservation,
capacity, valid dock states, intervening transit observations, complete pairwise
distances, and the hand-checkable fictional-grid distance. It prints observed
departure rate and return probability as simulation diagnostics.

Verified generated outputs:

| City | Departures per bike per day | Observed return probability per step |
|---|---:|---:|
| Jersey City | 2.82 | 0.249 |
| Milwaukee | 2.91 | 0.251 |
| Atlantis | 3.01 | 0.250 |

Largest real-city station-to-road connectors were 0.0229 miles (Jersey City)
and 0.0215 miles (Milwaukee). Each CSV was independently checked to contain
3,499,200 data rows. A directed shortest-path known-answer check chooses the
5-mile route (2 + 3) instead of a direct 10-mile edge.

In a real system, the operator would derive these snapshots from persistent
bike IDs and dock entry/exit events, recording `0` between dock visits. A public
station-count feed alone cannot identify all individual bike movements. Road
distances would be supplied independently from a reviewed local bicycle network.
