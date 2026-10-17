# bikesmart: Bike-Share Quality Control, Predictive Dock Balancing & Fleet Reliability

> **Big Red Crew** — Cornell Six Sigma Hackathon, October 2026  
> An integrated R package for predictive micro-mobility fleet management, statistical quality control, and rebalancing optimization.

---

## 1. Overview & Capabilities

`bikesmart` packages the core analytical and quality engineering components developed by the Big Red Crew into a modular, production-ready R package. The package addresses both sides of the micro-mobility challenge:
1. **Rider Experience & Predictive Rebalancing:** Accurate forecast of dock availability at arrival time, road distance ranking, and incentive pricing to encourage rider-driven system rebalancing.
2. **Fleet Quality Control & Reliability:** Multiplicative defect survival modeling (Rolled Throughput Yield), Statistical Process Control attribute P-charts with dynamic 3-sigma limits, and operational maintenance dispatch optimization with stuck-bike anomaly detection.

---

## 2. Package Architecture & Functions

```
bikesmart/
├── R/
│   ├── dock_projection.R  # Arrival forecasting, rates, return discounts & dock ranking
│   ├── failure_factor.R   # Usable fleet reliability, defect breakdown & scaling
│   ├── pchart.R           # SPC P-chart statistics, control limits & visualization
│   ├── maintenance_qc.R   # Maintenance dispatch, stuck alerts & station priority
│   ├── availability.R     # Poisson probability functions for bike/slot availability
│   ├── recommend.R        # Threshold-based dock recommendation rule
│   ├── aggregate.R        # Collapses 5-min movement logs to dock-level counts
│   └── distances.R        # Distance lookup and filtering
├── tests/
│   ├── testthat/          # Comprehensive unit test suites (known-answer & edge cases)
│   └── test_all.R         # Test runner verifying all package functionalities
├── man/                   # Standard R documentation (.Rd) manual pages
├── DESCRIPTION            # Package metadata, dependencies (dplyr) & suggestions
└── NAMESPACE              # Public exported function interface
```

### Exported Functions Reference

#### A. Predictive Dock Projection & Optimization (`dock_projection.R`)
- `compute_dock_rates(df, bin_minutes = 5, tz = "America/Chicago")`: Computes the 7-day typical-week arrival and departure rate (bikes/min) for every 5-minute slot.
- `predict_dock(rates, dock, live_bikes, capacity, walk_min, now = Sys.time(), smooth_min = 30, ...)`: Integrates net arrival rates over the travel window to project expected bikes and empty spaces upon arrival.
- `return_discount(projected_bikes, capacity)`: Assigns rebalancing discount percentages (20% for <25% occupancy; 10% for 25%–50% occupancy; 0% otherwise).
- `optimize_docks(user_location, stations, rates, mode = c("pickup", "return"), ...)`: Evaluates candidate docks by walking/cycling road distances, excludes docks with <1 projected unit, and provides distance-ordered recommendations.
- `parse_city_time(x, tz)`: Safely parses date-time strings with UTC offsets into POSIXct for a given city timezone.

#### B. Usable Fleet Reliability & Failure Factor (`failure_factor.R`)
- `failure_factor(rates)`: Computes the multiplicative survival factor across independent defect rates: $\prod (1 - r_i)$.
- `failure_breakdown(rates)`: Generates a Pareto table of individual failure rates, isolated survival rates, and cumulative usable factor, sorted worst-first.
- `apply_failure_factor(predicted, rates)`: Scales predicted bike counts by the fleet failure factor to determine actual usable/rentable bikes.
- `check_rates(rates)`: Validates that defect inputs are named proportions strictly within $[0, 1]$.

#### C. Statistical Process Control (SPC) P-Charts (`pchart.R`)
- `daily_service_counts(data, service_interval_h, tz = "America/New_York", ...)`: Tracks cumulative ride hours from 5-minute logs and aggregates daily subgroup sizes ($n$) and bikes requiring service ($d$).
- `p_chart(d, n, label = seq_along(d))`: Computes sample proportions ($p_i = d_i / n_i$), center line ($\bar{p}$), 3-sigma control limits ($UCL_i, LCL_i$), and flags out-of-control days.
- `plot_p_chart(chart, main = ...)`: Plots a publication-ready control chart with sample-size-stepped limits and red out-of-control alarm points using base R graphics.
- `pc_parse_time(x)`: Internal ISO-8601 parser for P-chart time logs.

#### D. Maintenance Fleet Dispatch & Anomaly Detection (`maintenance_qc.R`)
- `service_status(data, service_interval_h, service_log = NULL, ..., assume_service_h = 70)`: Accumulates ride hours per bike (assuming a bike is serviced and its hours restart after `assume_service_h` = 70 h of use, so not every bike shows as due) and flags whether a bike is due for preventive maintenance (`due = TRUE`) and the exact timestamp (`due_at`).
- `maintenance_alerts(data, threshold_min = 90, ...)`: Flags bikes currently away from any dock past a duration threshold (e.g., 90 min) indicating abandonment, theft, or breakdown.
- `station_service_priority(data, service_interval_h, ...)`: Ranks stations by the number of docked due bikes (`n_due`) and cumulative overdue hours to maximize mobile van service efficiency.
- `simulate_start_hours(bike_ids, service_interval_h, seed = 42)`: Generates uniform staggered initial ride hours (0 to $x$) so fleet maintenance cycles do not artificially synchronize.
- `dispatch_recommendation(data, service_interval_h, threshold_min = 90, ...)`: Unified operational call returning stuck alerts, service due bikes, and ranked van station visits in one list.

#### E. Probabilistic Availability & Distance Helpers (`availability.R`, `recommend.R`, `distances.R`, `aggregate.R`)
- `get_bike_availability(b0, lam_out, lam_in)`: Evaluates bivariate Poisson summation to determine the probability of finding $\ge 1$ bike.
- `get_slot_availability(b0, capacity, lam_out, lam_in)`: Evaluates bivariate Poisson summation to determine the probability of finding $\ge 1$ open docking slot.
- `recommend_dock(candidates, threshold = 0.90)`: Applies a threshold decision rule to select the nearest dock with high confidence.
- `dock_distances(distance_grid, from, to, max_miles)`: Looks up and filters pre-computed road network distances.
- `aggregate_snapshots(snapshots, stations, default_capacity = 30)`: Converts raw 3-column movement logs into station-level counts.

---

## 3. Installation & Loading

```r
# Option 1: Load during development (from repo root)
devtools::load_all("bikesmart")

# Option 2: Build and install local package tarball
# R CMD build bikesmart
# R CMD INSTALL bikesmart_0.1.0.tar.gz
library(bikesmart)
```

---

## 4. End-to-End Usage Examples

### Example 1: Predictive Dock Arrival & Return Rebalancing
```r
library(bikesmart)

# Load movement history and road distances
mke_history <- readRDS("data/milwaukee.rds")
mke_distances <- read.csv("data/optimizer/user_dock_distances.csv")

# 1. Compute historical 5-minute net docking rates
rates <- compute_dock_rates(mke_history, bin_minutes = 5, tz = "America/Chicago")

# 2. Live stations snapshot
stations <- data.frame(
  dockID = c("Discovery World", "411 East Wisconsin ", "Cathedral Square"),
  live_bikes = c(2, 5, 28),
  capacity = c(30, 30, 30),
  stringsAsFactors = FALSE
)

# 3. Find closest eligible pickup dock (excludes docks projected < 1 bike)
pickup_rec <- optimize_docks(
  user_location = "MKE-LOC01",
  stations = stations,
  rates = rates,
  mode = "pickup",
  now = "2026-10-19 08:00:00",
  user_distances = mke_distances,
  tz = "America/Chicago"
)
head(pickup_rec)

# 4. Find return dock with rebalancing discount
return_rec <- optimize_docks(
  user_location = "MKE-LOC01",
  stations = stations,
  rates = rates,
  mode = "return",
  now = "2026-10-19 08:30:00",
  user_distances = mke_distances,
  tz = "America/Chicago"
)
head(return_rec)
```

### Example 2: Maintenance Dispatch & Anomaly Detection
```r
library(bikesmart)

bikes_data <- readRDS("data/jersey_city.rds")
start_hours <- simulate_start_hours(unique(bikes_data$BIKEID), service_interval_h = 60, seed = 42)

# Run complete maintenance dispatch
dispatch <- dispatch_recommendation(
  data = bikes_data,
  service_interval_h = 60,
  threshold_min = 90,
  start_hours = start_hours
)

# Stuck bike alerts (lost/stolen/broken)
head(dispatch$stuck_alerts)

# Stations prioritized for maintenance van stop
head(dispatch$stations)
```

### Example 3: Attribute Statistical Process Control (P-Chart)
```r
library(bikesmart)

# Daily counts of bikes reaching service threshold
counts <- daily_service_counts(
  data = bikes_data,
  service_interval_h = 60,
  start_hours = start_hours
)

# Compute P-chart center line & 3-sigma limits
chart <- p_chart(d = counts$d, n = counts$n, label = counts$day)

# Plot control chart
plot_p_chart(chart, main = "P-Chart: Daily Share of Bikes Due for Maintenance")
```

### Example 4: Fleet Usable Factor & Reliability
```r
library(bikesmart)

# Define known or surveyed defect rates
defect_rates <- c(flat_tire = 0.02, dead_battery = 0.05, chain_brakes = 0.015)

# Calculate rolled usable share
usable_factor <- failure_factor(defect_rates)
cat(sprintf("Expected usable fleet percentage: %.2f%%\n", usable_factor * 100))

# Defect contribution breakdown
failure_breakdown(defect_rates)

# Scale projected inventory to usable rentable bikes
projected_bikes <- c(10, 15, 20)
usable_bikes <- apply_failure_factor(projected_bikes, defect_rates)
print(usable_bikes)
```

---

## 5. Verification & Tests

To execute all unit tests across all 5 test suites:
```bash
Rscript bikesmart/tests/test_all.R
```
All tests verify known-answer hand calculations, boundary conditions, and degenerate cases.
