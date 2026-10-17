# Dock recommendation inputs and examples

`optimize_docks()` in `dock_projection.R` ranks eligible docks by shortest
mode-specific road/path distance from a saved user location. This is a transparent
distance-ranking rule, not a global fleet or truck-route optimization algorithm.
Sourcing the R file now loads functions without running historical examples or plots;
running it directly retains the existing Milwaukee analysis.

## Saved real user locations

`user_locations.csv` contains 10 real public street junctions per city: Jersey
City, Milwaukee and Tampa (30 total). They are reproducibly sampled with seeds
5309, 5310 and 5311 from the cached OpenStreetMap road extracts within 0.75 miles
of the same downtown centers used for the demo stations. These are real
intersections, not simulated street names or real rider traces. Public junctions
are representative user locations, not guarantees of wheelchair-accessible
standing or crossing points.

Columns: `city`, `location_id` (unique saved input), `name` (named intersecting
streets), `lat`, `lon` (WGS84 decimal degrees), `osm_node_id`, `source_url`.
Each source node joins at least two named streets and three road branches.
Locations are at least 0.03 miles from a dock and 0.04 miles apart.

`user_dock_distances.csv` contains 1,620 rows: 30 locations × 27 docks × 2 modes.
Columns: `city`, `location_id`, `mode`, `dockID`, `distance` (miles).
`pickup` follows a walking graph; `return` follows a bicycle graph. These are
user-to-dock directions, not the reverse. No straight-line distance is used to
rank docks; straight-line distances are only used for initial sampling,
nearest-node connectors and checking road-distance lower bounds.

Roads come from the same cached OSM extracts as the city distance matrices.
Shortest paths respect ordinary access and mode-specific one-way rules;
pedestrian routing ignores vehicle one-way restrictions. Motorways and private
roads are excluded. Small straight-line connectors join points to the largest
strongly connected graph component; preparation rejects connectors over 0.15
miles. Turn restrictions, conditional access, temporary closures, safety,
crossing detail and exact sidewalk geometry are not modeled. Routes are
shortest on this graph, not guaranteed globally shortest or navigation-ready.
Source: © [OpenStreetMap contributors](https://www.openstreetmap.org/copyright).

## R function inputs and rules

```r
source("dock_projection.R")
locations <- read.csv("data/optimizer/user_locations.csv")
locations[locations$city == "milwaukee", ]
```

`optimize_docks(user_location, stations, rates, mode, now, ...)` accepts:

- `user_location`: one saved `location_id`, such as `MKE-U01`.
- `stations`: one city's rows with `dockID`, `live_bikes`, and `capacity`.
  Counts must describe the reference time `now`; use each station's actual
  operational capacity for real data. The demo capacity is 30.
- `rates`: output of `compute_dock_rates()` for that city, with the correct
  local timezone. Fit using history available before the prediction reference.
- `mode`: `"pickup"` or `"return"`.
- `now`: reference timestamp; timezone-free strings use the city timezone.
- Optional `user_distances`: a replacement table with the same route schema.
- Optional `travel_speed_mph`: default **3 mph walking**, **10 mph cycling**.
  These are illustrative average-speed assumptions, not measured local speeds.
- Optional `smooth_min`, `bin_minutes`, and `tz`: forwarded to the existing
  projection model. The timezone must match the historical rates.

Arrival minutes = road miles / mph × 60. Each dock is projected at its own
arrival time using `predict_dock()`. Pickup requires at least one projected
bike; return requires at least one projected free space. Fractional estimates
below one do not qualify. These projections are historical baselines, not
guaranteed inventory or calibrated success probabilities.

Return discounts use projected occupancy **before the user's bike is added**:
below 25% → 20%; 25% to below 50% → 10%; at least 50% → 0%. Pickup discounts
are zero. Discounts do not change distance order; dock name breaks distance
ties. Incentives are proposed simulated percentages, not real billing credits.

Returned rows contain `rank`, `dockID`, `distance_miles`, `live_bikes`,
`capacity`, `travel_minutes`, `arrival_time`, `projected_bikes`,
`projected_spaces`, `projected_occupancy` (fraction), `discount_percent`.
`attr(result, "excluded_docks")` retains excluded docks and the reason,
including explicit missing routes. An empty result means no dock qualifies.
Missing historical predictions raise a clear error rather than becoming zero.

## Example using a recorded snapshot

```r
source("dock_projection.R")
history <- readRDS("data/milwaukee.rds")
now <- as.POSIXct("2026-10-15 23:55:00", tz = "America/New_York")
stations <- read.csv("data/stations/milwaukee.csv")
snapshot <- history[history$time == now & history$DOCID != "0", ]
inventory <- table(snapshot$DOCID)
stations$live_bikes <- as.integer(inventory[stations$dockID])
stations$live_bikes[is.na(stations$live_bikes)] <- 0L
stations$capacity <- 30L
# Keep the fit strictly before the reference snapshot.
rates <- compute_dock_rates(history[history$time < now, ], tz = "America/Chicago")

pickups <- optimize_docks("MKE-U01", stations, rates, mode = "pickup", now = now)
returns <- optimize_docks("MKE-U01", stations, rates, mode = "return", now = now)
pickups
returns
attr(returns, "excluded_docks")
```

For Jersey City use `JC-U01`, `jersey_city.rds`, its station file, and
`America/New_York`. For Tampa use `TPA-U01`, `tampa.rds`, its station file,
and `America/New_York`. Custom locations require externally prepared road
distances; arbitrary coordinates are not silently geocoded or routed.

Rebuild saved inputs offline with `python3 data/optimizer/prepare_locations.py`
after obtaining the existing three road caches. Verify the optimizer with
`Rscript tests/test_dock_optimizer.R`.

Run `Rscript data/optimizer/run_demo.R` to exercise all 30 locations in both
modes at one shared instant: October 15, 2026 at 23:55 EDT (22:55 CDT in
Milwaukee). Each city uses its inventory snapshot at that same instant. Historical fits
exclude that reference snapshot. It writes `demo_recommendations.csv` and
`demo_exclusions.csv`, labeled by city, location and mode; timestamps have explicit
city-local offsets. These reports use simulated inventory, not today's live data.

## Interactive visual demo

Open **`data/optimizer/viewer/index.html`** in a browser (double-click it in
Finder, or run `open data/optimizer/viewer/index.html` on macOS). No server,
backend, API key or package installation is needed to view the generated page.

- Select one of the three cities, one of its ten saved user locations, and
  pickup or return mode.
- The map numbers eligible docks by rank, marks the user location, and shows
  excluded docks in gray. Return discount badges are shown where applicable.
- The eligible list shows saved road distance, travel time, arrival timestamp,
  projected availability, and incentives. The excluded tab explains removals.
- Click a card, map marker or occupancy bar to select a dock. Map/list/chart
  selections stay synchronized; occupancy bars also support Enter/Space keys.
- Occupancy bars include 25% and 50% threshold lines. Percentages refer to bike
  occupancy before the returning user's bike is added.

The viewer reads embedded copies of the saved CSV outputs, not live forecasts.
It renders and sorts existing results without recalculating projections or
discounts. Road outlines are embedded from the cached OSM extracts when they
are available at build time. They are background streets, not individual route
lines. OpenStreetMap raster tiles add richer street detail when internet is
available; controls, road outlines, markers and results work offline.

After rerunning the R demo, rebuild the viewer to refresh its data:

```sh
Rscript data/optimizer/run_demo.R
python3 data/optimizer/build_viewer.py
```

Source is `viewer_template.html`; generated output is `viewer/index.html`.
Leaflet assets and their license are included in `viewer/vendor/`. The builder
can initially copy them from the existing `bike-wise-ui/node_modules/leaflet`
installation; once included, no npm dependency is needed to open or rebuild
the page. Cached road extracts are needed to embed the offline street outlines.

`test_viewer.cjs` uses the existing UI's Playwright and installed macOS Google
Chrome to verify all 60 combinations, CSV/list agreement, dock markers,
exclusions, discount badges, keyboard interaction and a 390px mobile layout.
External network is blocked during this check. Preview screenshots are saved
as `viewer/preview.png` and `viewer/preview_mobile.png`.
