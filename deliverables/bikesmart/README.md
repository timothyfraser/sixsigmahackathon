# bikesmart

> R package — Bike Dock Availability and Recommendation Tool  
> Cornell Six Sigma Hackathon, Big Red Crew, October 2026

---

## What it does

`bikesmart` analyzes simulated bike-share snapshots and tells a rider:

- **Where to pick up a bike** — the closest dock with a high probability of having a bike available when you arrive.
- **Where to drop off a bike** — the closest dock near your destination with a high probability of having an open slot.

The package works directly on the raw three-column snapshot data produced by `simulate_data.R` (`BIKEID`, `DOCID`, `time`). An internal helper aggregates those rows to dock-level counts before computing probabilities.

---

## Functions

| Function | What it does |
|---|---|
| `aggregate_snapshots(snapshots, stations)` | Collapses raw per-bike rows into one row per dock per snapshot with a `bikes` count. First step before any analysis. |
| `get_bike_availability(b0, lam_out, lam_in)` | Returns P(at least one bike present) when the rider arrives, given current bike count and Poisson flow rates. |
| `get_slot_availability(b0, capacity, lam_out, lam_in)` | Returns P(at least one open slot) for a rider returning their bike. |
| `dock_distances(distance_grid, from, to, max_miles)` | Filters the pre-computed pairwise distance matrix to find nearby docks. |
| `recommend_dock(candidates, threshold)` | Picks the closest dock meeting a probability threshold; falls back to best available. |

---

## Install and load

```r
# From the built tarball (after running buildme.R)
install.packages("bikesmart_0.1.0.tar.gz", type = "source", repos = NULL)
library("bikesmart")

# Or load temporarily during development (no install needed)
devtools::load_all("deliverables/bikesmart")
```

---

## Quick example

```r
library("bikesmart")

# Load the Jersey City data (produced by simulate_data.R)
movement <- readRDS("data/jersey_city.rds")
stations <- read.csv("data/stations/jersey_city.csv", colClasses = "character")
grid     <- read.csv("data/distances/jersey_city.csv",
                      colClasses = c("character", "character", "numeric"))

# Step 1: aggregate raw snapshots to dock level
# Pick one timestamp (e.g. 8 AM on a weekday) as the "now" state
now <- as.POSIXct("2026-09-21 08:00:00", tz = "America/New_York")
dock_counts <- aggregate_snapshots(
  movement[movement$time == now, ],
  stations
)

# Step 2: find nearby docks (within 0.5 miles of "Hamilton Park")
nearby <- dock_distances(grid, from = "Hamilton Park", max_miles = 0.5)

# Step 3: for each nearby dock, compute availability probability
# (Flow rates lam_out and lam_in would come from your teammates'
# projection functions; using illustrative values here.)
candidates <- data.frame(
  dock_id = nearby$dockID2,
  minutes = nearby$distance / 0.05,   # rough: 0.05 miles/min walking
  p       = mapply(function(d) {
    b0 <- dock_counts$bikes[dock_counts$DOCID == d]
    if (length(b0) == 0) return(NA_real_)
    get_bike_availability(b0 = b0, lam_out = 1.2, lam_in = 0.8)
  }, nearby$dockID2)
)

# Step 4: recommend the best dock
recommend_dock(candidates, threshold = 0.90)
```

---

## Build from source

```r
# From the repository root:
source("deliverables/bikesmart/buildme.R")
```

See [`buildme.R`](buildme.R) for the full step-by-step workflow.

---

## Adding new functions

1. Add your function to an existing `R/*.R` file (if it fits thematically) or create a new `R/myfeature.R`.
2. Add roxygen2 tags (`@param`, `@return`, `@export`, etc.) above the function — see the existing functions as a template.
3. Run `devtools::document("deliverables/bikesmart")` — it regenerates `NAMESPACE` and `man/` automatically.
4. Add the function name to the `export(...)` list in `NAMESPACE` if `devtools::document()` did not do so automatically.
5. Write a test in `tests/` (testthat) and verify it passes before merging.

---

## Package structure

```
deliverables/bikesmart/
├── DESCRIPTION          # package metadata, authors, dependencies
├── NAMESPACE            # exported functions and imports (auto-generated)
├── LICENSE              # MIT
├── .Rbuildignore        # files excluded from the built tarball
├── buildme.R            # developer workflow (document → load → test → build)
├── README.md            # this file
├── R/
│   ├── aggregate.R      # aggregate_snapshots(): raw rows → dock counts
│   ├── availability.R   # get_bike_availability(), get_slot_availability()
│   ├── distances.R      # dock_distances()
│   └── recommend.R      # recommend_dock()
└── man/
    ├── aggregate_snapshots.Rd
    ├── get_bike_availability.Rd
    ├── get_slot_availability.Rd
    ├── dock_distances.Rd
    └── recommend_dock.Rd
```

