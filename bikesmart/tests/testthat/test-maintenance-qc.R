# test-maintenance-qc.R
# Tests for maintenance QC, transit runs, stuck-bike alerts, service status, and station priority

make_rows <- function(bike, dock, times) {
  data.frame(BIKEID = bike, DOCID = dock, time = times, stringsAsFactors = FALSE)
}
at <- function(hhmm) as.POSIXct(paste0("2026-01-01 ", hhmm, ":00"), tz = "UTC")

times <- seq(at("00:00"), at("01:00"), by = "5 min")
stopifnot(length(times) == 13)

docA <- c(rep("X", 3), rep("0", 7), rep("Y", 3))
docB <- rep("Y", 13)
docC <- c(rep("X", 4), rep("0", 9))

known_data <- rbind(
  make_rows("A", docA, times),
  make_rows("B", docB, times),
  make_rows("C", docC, times)
)

# 1. Transit runs
runs <- transit_runs(known_data)
stopifnot(
  nrow(runs) == 2,
  identical(runs$BIKEID, c("A", "C")),
  identical(runs$duration_min, c(35, 45)),
  runs$start[1] == at("00:15"),
  runs$end[1] == at("00:45"),
  runs$start[2] == at("00:20"),
  runs$end[2] == at("01:00")
)

# 2. Maintenance alerts (only run open at latest snapshot alerts)
al_40 <- maintenance_alerts(known_data, threshold_min = 40)
stopifnot(
  nrow(al_40) == 1,
  al_40$BIKEID[1] == "C",
  al_40$flagged[1] == TRUE
)
al_50 <- maintenance_alerts(known_data, threshold_min = 50)
stopifnot(al_50$flagged[1] == FALSE)

# 3. Service status (known answer at 0.5 h = 30 min)
st <- service_status(known_data, service_interval_h = 0.5)
stopifnot(
  abs(st$ride_hours[st$BIKEID == "A"] - 35/60) < 1e-6,
  abs(st$ride_hours[st$BIKEID == "B"] - 0) < 1e-6,
  abs(st$ride_hours[st$BIKEID == "C"] - 45/60) < 1e-6,
  st$due[st$BIKEID == "A"] == TRUE,
  st$due[st$BIKEID == "B"] == FALSE,
  st$due[st$BIKEID == "C"] == TRUE,
  st$due_at[st$BIKEID == "A"] == at("00:40"),
  st$due_at[st$BIKEID == "C"] == at("00:45"),
  st$current_dock[st$BIKEID == "A"] == "Y",
  st$current_dock[st$BIKEID == "C"] == "0"
)

# 4. Station priority ranking
prio <- station_service_priority(known_data, service_interval_h = 0.5)
stopifnot(
  nrow(prio) == 1,
  prio$DOCID[1] == "Y",
  prio$n_bikes[1] == 2,
  prio$n_due[1] == 1,
  abs(prio$overdue_hours[1] - (35/60 - 0.5)) < 1e-6
)

# 5. Service log reset
slog <- data.frame(BIKEID = "A", service_time = "2026-01-01 00:30:00", stringsAsFactors = FALSE)
st_serviced <- service_status(known_data, service_interval_h = 0.5, service_log = slog)
stopifnot(
  abs(st_serviced$ride_hours[st_serviced$BIKEID == "A"] - 15/60) < 1e-6,
  st_serviced$due[st_serviced$BIKEID == "A"] == FALSE
)

# 6. Unified dispatch recommendation
rec <- dispatch_recommendation(known_data, service_interval_h = 0.5, threshold_min = 40)
stopifnot(
  identical(names(rec), c("stuck_alerts", "service_due", "stations")),
  nrow(rec$stuck_alerts) == 1,
  nrow(rec$service_due) == 2,
  nrow(rec$stations) == 1
)

cat("PASS test-maintenance-qc: transit runs, alerts, service status, van priorities, and dispatch unified output verified.\n")


local({ # Base-R runner: verify the new assumed-service behavior without testthat.
  # 1 bike, in transit for 15 snapshots at 5 min = 1.25 h total
  d <- data.frame(
    BIKEID = "A",
    DOCID = "0",
    time = format(as.POSIXct("2026-09-16 00:00:00", tz = "UTC") + 300 * (0:14), "%Y-%m-%d %H:%M:%S"),
    stringsAsFactors = FALSE
  )
  # interval 0.5 h, assumed service at 1 h: reset at 12 snapshots, 3 left = 0.25 h, not due
  s <- service_status(d, service_interval_h = 0.5, assume_service_h = 1)
  stopifnot(isTRUE(all.equal(s$ride_hours, 0.25)))
  stopifnot(!s$due)
  # disabled: stays due forever
  s0 <- service_status(d, service_interval_h = 0.5, assume_service_h = NULL)
  stopifnot(isTRUE(all.equal(s0$ride_hours, 1.25)))
  stopifnot(s0$due)
  stopifnot(inherits(try(service_status(d, service_interval_h = 0.5, assume_service_h = -1), silent = TRUE), "try-error"))
  cat("PASS assumed-service: 1.25 h resets to 0.25 h at 1 h; disabling reset stays due; invalid threshold rejected.\n")
})
