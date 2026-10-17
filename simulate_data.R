# BikeWise: three-column synthetic bike snapshots. Run from repository root:
# Rscript simulate_data.R
# Source this file to use simulate_bikes() without writing output.

demand_profile <- function(time, tz) {
  local <- as.POSIXlt(time, tz = tz)
  hour <- local$hour + local$min / 60
  weekday <- local$wday %in% 1:5
  bump <- function(center, width) exp(-0.5 * ((hour - center) / width)^2)
  # Synthetic relative demand; not fitted to observed ridership.
  profile <- 0.12 + ifelse(weekday,
    1.8 * bump(8.5, 1) + 1.9 * bump(17.5, 1.25) +
      0.5 * bump(12.5, 1) + 0.5 * bump(20, 1.5),
    1.0 * bump(12.5, 2) + 1.0 * bump(18, 2))
  # Friday/Saturday evenings and Saturday/Sunday early mornings.
  profile <- profile + ifelse(local$wday %in% c(5, 6), 0.8 * bump(23, 1), 0) +
    ifelse(local$wday %in% c(6, 0), 0.7 * bump(1, 1), 0)
  profile
}

station_zones <- function(stations) {
  # Explicit user-supplied zoning wins; otherwise assign equal synthetic groups.
  if ("zone" %in% names(stations)) {
    stopifnot(!anyNA(stations$zone),
      all(stations$zone %in% c("residential", "office", "retail")))
    return(as.character(stations$zone))
  }
  # Stable contiguous geographic bands, not random labels or actual land use.
  order_ids <- if (all(c("lat", "lon") %in% names(stations)) &&
    all(is.finite(suppressWarnings(as.numeric(stations$lon)))))
      order(as.numeric(stations$lon), as.numeric(stations$lat), stations$dockID) else
      order(stations$dockID)
  result <- character(nrow(stations))
  sizes <- tabulate(rep(seq_len(3), length.out = nrow(stations)), nbins = 3)
  result[order_ids] <- rep(c("residential", "office", "retail"), times = sizes)
  result
}

zone_profiles <- function(times, tz, zones) {
  local <- as.POSIXlt(times, tz = tz)
  hour <- local$hour + local$min / 60
  weekday <- as.numeric(local$wday %in% 1:5)
  bump <- function(center, width) exp(-0.5 * ((hour - center) / width)^2)
  morning <- weekday * bump(8.5, 0.9)
  evening <- weekday * bump(17.5, 0.65)
  lunch_out <- weekday * bump(12, 0.45)
  lunch_back <- weekday * bump(13, 0.5)
  work <- weekday * (plogis(3 * (hour - 9)) - plogis(3 * (hour - 17)))
  night <- bump(20.5, 1.8)
  weekend_day <- (1 - weekday) * bump(14, 3)
  departure <- cbind(
    residential = (0.5 + 4 * morning + 0.8 * lunch_back) * (1 - 0.8 * evening),
    office = 0.15 * (1 - work) + 0.025 * work + 4 * evening + 2 * lunch_out,
    retail = 0.5 + 1.5 * bump(23, 2) + (1 - weekday) * bump(18, 2.5))
  destination <- cbind(
    residential = 0.5 + 4 * evening + 1.5 * lunch_out + 0.8 * (1 - work),
    office = 0.35 + 4 * morning + 1.7 * work + 2 * lunch_back,
    retail = 0.4 + 4 * night + 3 * weekend_day + 1.5 * lunch_out)
  list(departure = departure[, zones, drop = FALSE],
       destination = destination[, zones, drop = FALSE])
}

simulate_bikes <- function(stations, city, tz, seed = 5300L,
                           start_date = "2026-09-16", days = 30L,
                           bikes_per_dock = 15L, capacity = 30L,
                           return_probability = 0.25, target_usage = 0.333,
                           departure_adjustment = 1) {
  stopifnot(is.data.frame(stations), "dockID" %in% names(stations),
    nrow(stations) >= 2, !anyDuplicated(stations$dockID),
    !anyNA(stations$dockID), all(nzchar(stations$dockID)),
    !"0" %in% stations$dockID, days >= 1, days == as.integer(days),
    bikes_per_dock >= 1, bikes_per_dock == as.integer(bikes_per_dock),
    capacity >= bikes_per_dock, capacity == as.integer(capacity),
    return_probability > 0, return_probability <= 1,
    length(departure_adjustment) == 1L, is.finite(departure_adjustment),
    departure_adjustment > 0,
    length(target_usage) == 1L, is.finite(target_usage),
    target_usage >= 0, target_usage < 1)
  set.seed(seed)
  start <- as.POSIXct(paste(start_date, "00:00:00"), tz = tz)
  # Calendar-day boundary, preserving DST correctly for arbitrary future dates.
  end <- as.POSIXct(paste(as.Date(start_date) + days, "00:00:00"), tz = tz)
  times <- seq(start, end - 300, by = 300)
  n_stations <- nrow(stations)
  n_bikes <- n_stations * bikes_per_dock
  bike_ids <- sprintf("%s-B%04d", toupper(city), seq_len(n_bikes))
  current <- rep(seq_len(n_stations), each = bikes_per_dock)
  states <- matrix(0L, nrow = n_bikes, ncol = length(times))
  states[, 1] <- current
  # Fixed heterogeneity is synthetic and independent of geography/student use.
  activity <- runif(n_stations, 0.75, 1.25)
  appeal <- runif(n_stations, 0.75, 1.25)
  zoning <- zone_profiles(times, tz, station_zones(stations))
  profile <- demand_profile(times, tz)
  profile <- profile / mean(profile)
  departure_weights <- sweep(zoning$departure, 2, activity, "*") * profile
  destination_weights <- sweep(zoning$destination, 2, appeal, "*")
  destination_weights <- destination_weights / rowSums(destination_weights)
  # Calibrate expected whole-history usage, including the all-docked initial state.
  # Propagate dock/away state probabilities through the complete demand profile.
  # This changes departure frequency, not return persistence or recorded columns.
  expected_usage <- function(scale) {
    dock_probability <- rep(1 / n_stations, n_stations)
    away_probability <- 0
    total_away <- 0
    for (step in 2:length(times)) {
      leaving_probability <- dock_probability * pmin(1, scale * departure_weights[step, ])
      returning_probability <- away_probability * return_probability
      dock_probability <- dock_probability - leaving_probability +
        returning_probability * destination_weights[step, ]
      away_probability <- away_probability + sum(leaving_probability) - returning_probability
      total_away <- total_away + away_probability
    }
    total_away / length(times)
  }
  if (target_usage > expected_usage(100))
    stop("Requested usage exceeds what the return probability permits")
  base_departure <- if (target_usage == 0) 0 else
    uniroot(function(scale) expected_usage(scale) - target_usage,
            c(0, 100), tol = 1e-9)$root
  base_departure <- base_departure * departure_adjustment
  for (step in 2:length(times)) {
    # Snapshot semantics: previous docked bikes may leave; previous away bikes may return.
    docked <- which(current > 0L)
    away <- which(current == 0L)
    leaving <- docked[runif(length(docked)) < pmin(1,
      base_departure * departure_weights[step, current[docked]])]
    previous <- current
    current[leaving] <- 0L
    returning <- away[runif(length(away)) < return_probability]
    counts <- tabulate(current, nbins = n_stations)
    # No distance or speed enters this transition; a full network extends time away.
    if (length(returning)) for (bike in returning[sample.int(length(returning))]) {
      candidates <- which(counts < capacity)
      if (!length(candidates)) break
      destination <- candidates[sample.int(length(candidates), 1,
        prob = destination_weights[step, candidates])]
      current[bike] <- destination
      counts[destination] <- counts[destination] + 1L
    }
    if (any(counts > capacity)) stop("Capacity invariant violated")
    if (any(previous > 0L & current > 0L & previous != current))
      stop("Dock change without a transit snapshot")
    states[, step] <- current
  }
  labels <- c("0", as.character(stations$dockID))
  data.frame(BIKEID = rep(bike_ids, times = length(times)),
    DOCID = labels[as.vector(states) + 1L],
    time = rep(times, each = n_bikes), stringsAsFactors = FALSE)
}

generate_all <- function() {
  cities <- c("jersey_city", "milwaukee", "tampa")
  zones <- c("America/New_York", "America/Chicago", "America/New_York")
  for (i in seq_along(cities)) {
    city <- cities[i]
    station_path <- file.path("data", "stations", paste0(city, ".csv"))
    if (!file.exists(station_path))
      stop("Prepare station inputs first: python3 data/prepare_networks.py")
    stations <- read.csv(station_path, colClasses = "character")
    zoning_dir <- file.path("data", "zoning")
    dir.create(zoning_dir, showWarnings = FALSE)
    zoning_path <- file.path(zoning_dir, paste0(city, ".csv"))
    if (file.exists(zoning_path)) {
      existing_zones <- read.csv(zoning_path, colClasses = "character")
      stopifnot(setequal(existing_zones$dockID, stations$dockID),
        !anyDuplicated(existing_zones$dockID))
      stations$zone <- existing_zones$zone[match(stations$dockID, existing_zones$dockID)]
    }
    stations$zone <- station_zones(stations)
    write.csv(stations[c("dockID", "zone")],
      zoning_path, row.names = FALSE)
    adjustment <- 1
    for (attempt in 1:6) {
      movement <- simulate_bikes(stations, city, zones[i], seed = 5300L + i,
        departure_adjustment = adjustment)
      usage <- mean(movement$DOCID == "0")
      if (abs(usage - 0.333) <= 0.001) break
      # Capacity can redirect zoned arrivals; correct expected-rate calibration
      # using realized usage odds. Replay the entire simulation, never edit rows.
      adjustment <- adjustment * (0.333 / (1 - 0.333)) / (usage / (1 - usage))
    }
    if (abs(usage - 0.333) > 0.001) stop("Usage calibration did not converge")
    # The RDS preserves the POSIXct timezone and exact three-column data frame.
    saveRDS(movement, file.path("data", paste0(city, ".rds")))
    movement$time <- format(movement$time, "%Y-%m-%dT%H:%M:%S%z", tz = zones[i])
    connection <- gzfile(file.path("data", paste0(city, ".csv.gz")), "wt")
    tryCatch(write.csv(movement, connection, row.names = FALSE),
             finally = close(connection))
    # Refresh existing uncompressed exports so they cannot silently stay stale.
    plain_path <- file.path("data", paste0(city, ".csv"))
    if (file.exists(plain_path)) write.csv(movement, plain_path, row.names = FALSE)
    cat(sprintf("%s: %s rows; 405 bikes; 8640 snapshots; %.3f%% undocked (target 33.3%%); columns BIKEID, DOCID, time\n",
      city, format(nrow(movement), big.mark = ","), 100 * usage))
  }
}

if (sys.nframe() == 0L) generate_all()
