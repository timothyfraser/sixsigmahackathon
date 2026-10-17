source("simulate_data.R")
tiny <- data.frame(dockID = c("A", "B", "C"))
a <- simulate_bikes(tiny, "test", "America/New_York", days = 2,
                    bikes_per_dock = 2, capacity = 3)
b <- simulate_bikes(tiny, "test", "America/New_York", days = 2,
                    bikes_per_dock = 2, capacity = 3)
stopifnot(identical(a, b), identical(names(a), c("BIKEID", "DOCID", "time")))
idle <- simulate_bikes(tiny, "test", "America/New_York", days = 1,
  bikes_per_dock = 2, capacity = 3, target_usage = 0)
stopifnot(!any(idle$DOCID == "0"))
cat("PASS: seeded reproducibility and zero-demand edge case\n")
observation_counts <- list()
usage_summaries <- list()
hourly_summaries <- list()
for (city in c("jersey_city", "milwaukee", "atlantis")) {
  d <- readRDS(file.path("data", paste0(city, ".rds")))
  counts <- table(d$BIKEID)
  csv_ids <- read.csv(gzfile(file.path("data", paste0(city, ".csv.gz"))),
    colClasses = c("character", "NULL", "NULL"))
  csv_counts <- table(csv_ids$BIKEID)
  stopifnot(length(counts) == 405L, all(counts == 8640L),
    identical(counts, csv_counts))
  observation_counts[[city]] <- data.frame(city = city,
    BIKEID = names(counts), observations = as.integer(counts))
  cat(sprintf("PASS %s observations per BIKEID: %d bikes; min=%d; max=%d; CSV/RDS counts identical\n",
    city, length(counts), min(counts), max(counts)))
  rm(csv_ids, csv_counts)
  stations <- read.csv(file.path("data", "stations", paste0(city, ".csv")))
  grid <- read.csv(file.path("data", "distances", paste0(city, ".csv")))
  portable <- read.csv(gzfile(file.path("data", paste0(city, ".csv.gz"))),
                       nrows = 405, colClasses = "character")
  stopifnot(identical(names(portable), names(d)),
    identical(portable$BIKEID, d$BIKEID[1:405]),
    identical(portable$DOCID, d$DOCID[1:405]),
    identical(portable$time, format(d$time[1:405], "%Y-%m-%dT%H:%M:%S%z")))
  stopifnot(identical(names(d), c("BIKEID", "DOCID", "time")),
    nrow(d) == 3499200L, length(unique(d$BIKEID)) == 405L,
    length(unique(d$time)) == 8640L, !anyNA(d),
    all(d$DOCID %in% c("0", stations$dockID)))
  states <- matrix(match(d$DOCID, c("0", stations$dockID)) - 1L, nrow = 405L)
  stopifnot(!anyDuplicated(d[c("BIKEID", "time")]))
  usage <- mean(states == 0L)
  # Stochastic realizations may differ slightly from the calibrated expectation.
  stopifnot(abs(usage - 0.333) <= 0.002)
  snapshot_times <- unique(d$time)
  local_times <- as.POSIXlt(snapshot_times)
  snapshot_usage <- colMeans(states == 0L)
  rush <- local_times$wday %in% 1:5 & local_times$hour %in% c(7, 8, 16, 17, 18)
  slow <- local_times$wday %in% 1:5 & local_times$hour %in% c(2, 3, 4)
  stopifnot(mean(snapshot_usage[rush]) > mean(snapshot_usage[slow]))
  usage_summaries[[city]] <- data.frame(city = city, target_percent = 33.3,
    observed_percent = 100 * usage,
    weekday_rush_percent = 100 * mean(snapshot_usage[rush]),
    weekday_slow_percent = 100 * mean(snapshot_usage[slow]))
  hourly <- aggregate(100 * snapshot_usage,
    by = list(day_type = ifelse(local_times$wday %in% 1:5, "weekday", "weekend"),
              hour = local_times$hour), FUN = mean)
  names(hourly)[3] <- "undocked_percent"
  hourly_summaries[[city]] <- data.frame(city = city, hourly)
  cat(sprintf("PASS %s: %.3f%% undocked; target 33.3%% (+/-0.2 percentage points); weekday rush %.2f%% > slow %.2f%%; zero duplicate bike-timestamp pairs\n",
    city, 100 * usage, 100 * mean(snapshot_usage[rush]), 100 * mean(snapshot_usage[slow])))
  stopifnot(all(diff(as.numeric(unique(d$time))) == 300),
    identical(d$BIKEID, rep(d$BIKEID[1:405], 8640)),
    all(tabulate(states[, 1], nbins = 27) == 15), any(states == 0L))
  before <- states[, -ncol(states), drop = FALSE]
  after <- states[, -1, drop = FALSE]
  stopifnot(!any(before > 0 & after > 0 & before != after))
  for (step in seq_len(ncol(states)))
    stopifnot(max(tabulate(states[, step], nbins = 27)) <= 30)
  stopifnot(identical(names(grid), c("dockID1", "dockID2", "distance")),
    nrow(grid) == 729, !anyNA(grid), all(is.finite(grid$distance)),
    all(grid$distance[grid$dockID1 == grid$dockID2] == 0),
    all(grid$distance[grid$dockID1 != grid$dockID2] > 0),
    !anyDuplicated(grid[c("dockID1", "dockID2")]),
    setequal(grid$dockID1, stations$dockID), setequal(grid$dockID2, stations$dockID))
  if (city == "atlantis") {
    stopifnot(grid$distance[grid$dockID1 == "Atlantis Dock 01" &
                           grid$dockID2 == "Atlantis Dock 27"] == 2.5)
  }
  departures <- sum(before > 0 & after == 0)
  returns <- sum(before == 0 & after > 0)
  cat(sprintf("PASS %s: 3499200 rows; 405 bikes; 8640 five-minute snapshots; capacity <=30; 729 mile distances; %.2f departures/bike/day; %.3f return probability\n",
    city, departures / 405 / 30, returns / sum(before == 0)))
}
reference_counts <- sort(observation_counts[[1]]$observations)
stopifnot(all(vapply(observation_counts, function(x)
  identical(sort(x$observations), reference_counts), logical(1))))
dir.create("data/validation", showWarnings = FALSE)
write.csv(do.call(rbind, observation_counts),
  "data/validation/observations_per_bike.csv", row.names = FALSE)
write.csv(do.call(rbind, usage_summaries),
  "data/validation/usage_summary.csv", row.names = FALSE)
write.csv(do.call(rbind, hourly_summaries),
  "data/validation/usage_by_hour.csv", row.names = FALSE)
cat("PASS: observations per bike consistent across all three cities (8640 each); 1215 per-bike counts saved to data/validation/observations_per_bike.csv\n")
