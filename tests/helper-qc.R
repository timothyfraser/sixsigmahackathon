# Test helper: loads the code under test and builds small scenarios in code.
# Runs automatically before the tests in this folder (testthat helper-*.R files).

source(testthat::test_path("..", "app", "qc.R"), local = TRUE)

# A number is "near" its known answer when it agrees to 3 decimals.
expect_near <- function(actual, expected, tol = 5e-4) {
  testthat::expect_true(
    length(actual) == 1 && !is.na(actual) && abs(actual - expected) < tol,
    info = paste("actual", actual, "expected", expected)
  )
}

scenario_columns <- c(
  "table", "data_source", "station_id", "station_name", "latitude", "longitude",
  "capacity", "region", "timestamp", "bikes_available", "docks_available",
  "is_renting", "is_returning", "attempt_id", "attempt_type", "success",
  "failure_reason", "task_id", "van_id", "source_station_id",
  "destination_station_id", "planned_quantity", "actual_quantity",
  "assigned_at", "arrived_at", "completed_at", "status"
)

# n rows of the long-form scenario layout; every cell empty except table/data_source.
blank_rows <- function(n, table) {
  df <- as.data.frame(matrix(NA_character_, nrow = n, ncol = length(scenario_columns)),
                      stringsAsFactors = FALSE)
  names(df) <- scenario_columns
  df$table <- table
  df$data_source <- "simulated"
  df
}

# stations: data.frame(id, capacity, lat, lon) -> stations rows
make_station_rows <- function(id, capacity, lat = 42.44, lon = -76.50) {
  df <- blank_rows(length(id), "stations")
  df$station_id <- id
  df$station_name <- paste("Station", id)
  df$latitude <- as.character(rep_len(lat, length(id)))
  df$longitude <- as.character(rep_len(lon, length(id)))
  df$capacity <- as.character(capacity)
  df$region <- "test"
  df
}

# status rows for one station; times like "07:02:00" on 2026-10-05 (EDT, -04:00)
make_status_rows <- function(times, bikes, docks = NULL, station = "S1", capacity = 10) {
  if (is.null(docks)) docks <- capacity - bikes
  df <- blank_rows(length(times), "status")
  df$timestamp <- paste0("2026-10-05T", times, "-04:00")
  df$station_id <- station
  df$bikes_available <- as.character(bikes)
  df$docks_available <- as.character(docks)
  df$is_renting <- "TRUE"
  df$is_returning <- "TRUE"
  df
}

# KA-1 scenario: capacity 10, snapshots on the minute 07:00..07:09.
# drop = minutes to remove (e.g. 3:5); extra = more status rows.
ka1_scenario <- function(drop = integer(0), extra = NULL) {
  minutes <- 0:9
  bikes <- c(2, 1, 0, 0, 0, 1, 2, 8, 10, 10)
  keep <- !(minutes %in% drop)
  rows <- list(make_station_rows("S1", 10),
               make_status_rows(sprintf("07:%02d:00", minutes[keep]), bikes[keep]))
  if (!is.null(extra)) rows[[3]] <- extra
  do.call(rbind, rows)
}

# Scenario -> validated -> grid -> per-station summary (07:00 to 07:10 = 10 minutes)
ka1_summary <- function(sc, stale_limit = 2) {
  v <- validate_scenario(sc)
  g <- build_grid(v$status, v$stations, "2026-10-05", "07:00", "07:10",
                  stale_limit = stale_limit)
  unusable_summary(g)
}
