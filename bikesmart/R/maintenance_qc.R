# ==============================================================================
# maintenance_qc.R
# BikeSmart R Package - Maintenance Crew Dispatch & Stuck-Bike Anomaly Detection
# ------------------------------------------------------------------------------
# PURPOSE:
# Answers operational quality control and logistics questions for fleet maintenance:
#   1) Which bikes are due for preventive maintenance based on accumulated ride hours?
#   2) Which bikes are stuck away from docks beyond reasonable trip duration (anomalies)?
#   3) How should the mobile maintenance van rank station visits to service the most bikes?
#
# Core functions:
#   - parse_time(): Safe ISO-8601 timestamp parser
#   - transit_runs(): Computes contiguous away-from-dock trip durations
#   - maintenance_alerts(): Flags bikes stuck in transit past a threshold duration
#   - service_status(): Tracks accumulated ride hours and flags service due status
#   - station_service_priority(): Ranks stations by number of docked due bikes
#   - simulate_start_hours(): Generates realistic staggered initial ride hours
#   - dispatch_recommendation(): Unified output combining alerts, due bikes, and van priorities
# ==============================================================================

#' @import dplyr
NULL

# ------------------------------------------------------------------------------
# parse_time
# ------------------------------------------------------------------------------
# Short description: Safely parses ISO-8601 timestamps with UTC offsets, falling
# back to date-time without offsets, avoiding silent time-of-day truncation.

#' Parse Timestamps Safely to UTC
#'
#' @description
#' Robust parser for ISO-8601 date-time strings ensuring the time of day and timezone
#' offsets are not silently dropped.
#'
#' @param x Vector of character strings or POSIXct objects.
#' @return POSIXct vector in UTC.
#' @export
parse_time <- function(x) {
  if (inherits(x, "POSIXct")) {
    return(x)
  }
  out <- as.POSIXct(as.character(x), format = "%Y-%m-%dT%H:%M:%S%z", tz = "UTC")
  if (anyNA(out)) {
    alt <- as.POSIXct(as.character(x), format = "%Y-%m-%d %H:%M:%S", tz = "UTC")
    out <- ifelse(is.na(out), alt, out)
    out <- as.POSIXct(out, origin = "1970-01-01", tz = "UTC")
  }
  if (anyNA(out)) {
    stop("parse_time(): some timestamps could not be parsed; expected e.g. 2026-09-16T00:00:00-0400")
  }
  out
}


# ------------------------------------------------------------------------------
# transit_runs
# ------------------------------------------------------------------------------
# Short description: Groups consecutive snapshots where a bike is away from a dock
# (DOCID == '0') into distinct transit trips and calculates their duration in minutes.

#' Identify Contiguous In-Transit Runs per Bike
#'
#' @description
#' Segments snapshot sequences where `DOCID == "0"` into distinct contiguous ride runs,
#' computing the start time, end time, and duration in minutes.
#'
#' @param data Data frame containing `BIKEID`, `DOCID`, and `time`.
#' @param interval_min Numeric sampling interval in minutes (default: 5).
#' @return Data frame with columns `BIKEID`, `run_id`, `start`, `end`, and `duration_min`.
#' @export
transit_runs <- function(data, interval_min = 5) {
  stopifnot(all(c("BIKEID", "DOCID", "time") %in% names(data)))

  data <- data %>%
    mutate(time = parse_time(time)) %>%
    arrange(BIKEID, time) %>%
    mutate(is_transit = (DOCID == "0"))

  if (nrow(data) == 0) {
    return(data.frame(
      BIKEID = character(),
      run_id = integer(),
      start = as.POSIXct(character()),
      end = as.POSIXct(character()),
      duration_min = numeric(),
      stringsAsFactors = FALSE
    ))
  }

  data <- data %>%
    group_by(BIKEID) %>%
    mutate(run_change = cumsum(is_transit != lag(is_transit, default = first(is_transit)))) %>%
    ungroup()

  data %>%
    filter(is_transit) %>%
    group_by(BIKEID, run_id = run_change) %>%
    summarise(start = min(time), end = max(time), n = n(), .groups = "drop") %>%
    mutate(duration_min = as.numeric(difftime(end, start, units = "mins")) + interval_min)
}


# ------------------------------------------------------------------------------
# maintenance_alerts
# ------------------------------------------------------------------------------
# Short description: Identifies bikes currently in transit at the latest snapshot
# whose trip duration exceeds a threshold, indicating potential loss, theft, or breakdown.

#' Flag Currently Stuck or Abandoned Bikes
#'
#' @description
#' Evaluates the latest recorded snapshot and flags any bike currently away from
#' docks (`DOCID == "0"`) whose continuous transit duration meets or exceeds `threshold_min`.
#'
#' @param data Data frame with columns `BIKEID`, `DOCID`, and `time`.
#' @param threshold_min Minutes away from dock before alerting (default: 90).
#' @param interval_min Sampling interval in minutes (default: 5).
#' @return Data frame with `BIKEID`, `duration_min`, and `flagged` logical, ordered longest first.
#' @export
maintenance_alerts <- function(data, threshold_min = 90, interval_min = 5) {
  stopifnot(is.numeric(threshold_min), threshold_min > 0)
  empty <- data.frame(
    BIKEID = character(),
    duration_min = numeric(),
    flagged = logical(),
    stringsAsFactors = FALSE
  )
  if (nrow(data) == 0) return(empty)

  data <- data %>% mutate(time = parse_time(time))
  latest_time <- max(data$time)

  runs <- transit_runs(data, interval_min = interval_min)
  if (nrow(runs) == 0) return(empty)

  runs %>%
    filter(end == latest_time) %>%
    group_by(BIKEID) %>%
    slice_max(duration_min, n = 1, with_ties = FALSE) %>%
    ungroup() %>%
    transmute(BIKEID, duration_min, flagged = duration_min >= threshold_min) %>%
    arrange(desc(duration_min))
}


# ------------------------------------------------------------------------------
# check_start_hours
# ------------------------------------------------------------------------------
# Short description: Validates the format and values of a starting ride hours table.

#' Validate Starting Ride Hours Table
#'
#' @param start_hours Data frame with `BIKEID` and `start_hours`.
#' @return Validated data frame with clean types.
#' @export
check_start_hours <- function(start_hours) {
  if (!all(c("BIKEID", "start_hours") %in% names(start_hours))) {
    stop("start_hours needs columns BIKEID and start_hours")
  }
  if (anyNA(start_hours$start_hours) || any(start_hours$start_hours < 0)) {
    stop("start_hours must be zero or more, with no NA")
  }
  if (anyDuplicated(start_hours$BIKEID)) {
    stop("start_hours has a bike listed twice")
  }
  data.frame(
    BIKEID = as.character(start_hours$BIKEID),
    start_hours = start_hours$start_hours,
    stringsAsFactors = FALSE
  )
}


# ------------------------------------------------------------------------------
# service_status
# ------------------------------------------------------------------------------
# Short description: Calculates accumulated ride hours for each bike since last service
# and flags whether it has crossed the preventive maintenance service interval.

#' Evaluate Fleet Ride Hours and Service Due Status
#'
#' @description
#' Tracks usage accumulation across 5-minute snapshot logs for every bike. When
#' cumulative ride hours exceed `service_interval_h`, flags `due = TRUE` and records `due_at`.
#'
#' @param data Data frame with columns `BIKEID`, `DOCID`, and `time`.
#' @param service_interval_h Positive numeric ride hour threshold between services (required).
#' @param service_log Optional data frame (`BIKEID`, `service_time`) of previous maintenance events.
#' @param interval_min Snapshot spacing in minutes (default: 5).
#' @param start_hours Optional data frame (`BIKEID`, `start_hours`) of initial usage offsets.
#' @param assume_service_h Assumed hard service point in ride hours (default: 70). Once a
#'   bike accumulates this many ride hours it is assumed to have been serviced, and its
#'   hours restart from zero. This stops every bike from showing as due forever when the
#'   data spans a long period. Use `NULL` to disable. Has no effect on a bike that is
#'   never due before this point, and a bike is never due if `service_interval_h` is at
#'   or above this value.
#' @return Data frame with columns `BIKEID`, `ride_hours` (hours since the last service,
#'   real or assumed), `due`, `due_at`, and `current_dock`.
#' @export
service_status <- function(
    data,
    service_interval_h,
    service_log = NULL,
    interval_min = 5,
    start_hours = NULL,
    assume_service_h = 70
) {
  if (missing(service_interval_h) || !is.numeric(service_interval_h) ||
      length(service_interval_h) != 1 || is.na(service_interval_h) || service_interval_h <= 0) {
    stop("service_interval_h is required: a positive number of ride hours between services")
  }
  if (!is.null(assume_service_h) && (!is.numeric(assume_service_h) ||
      length(assume_service_h) != 1 || is.na(assume_service_h) || assume_service_h <= 0)) {
    stop("assume_service_h must be NULL or a positive number of ride hours")
  }

  if (nrow(data) == 0) {
    return(data.frame(
      BIKEID = character(),
      ride_hours = numeric(),
      due = logical(),
      due_at = as.POSIXct(character(), tz = "UTC"),
      current_dock = character(),
      stringsAsFactors = FALSE
    ))
  }

  data <- data %>%
    mutate(time = parse_time(time), DOCID = as.character(DOCID)) %>%
    arrange(BIKEID, time)
  latest_time <- max(data$time)

  current <- data %>%
    group_by(BIKEID) %>%
    slice_max(time, n = 1, with_ties = FALSE) %>%
    ungroup() %>%
    select(BIKEID, current_dock = DOCID)

  if (!is.null(service_log)) {
    stopifnot(all(c("BIKEID", "service_time") %in% names(service_log)))
    last_service <- service_log %>%
      mutate(service_time = parse_time(service_time)) %>%
      filter(service_time <= latest_time) %>%
      group_by(BIKEID) %>%
      summarise(last_service = max(service_time), .groups = "drop")
    data <- data %>%
      left_join(last_service, by = "BIKEID") %>%
      filter(is.na(last_service) | time > last_service)
  }

  data$offset_min <- 0
  if (!is.null(start_hours)) {
    sh <- check_start_hours(start_hours)
    data <- data %>%
      left_join(sh, by = "BIKEID", suffix = c("", ".sh")) %>%
      mutate(offset_min = coalesce(start_hours, 0) * 60) %>%
      select(-start_hours)
    if ("last_service" %in% names(data)) {
      data <- data %>% mutate(offset_min = ifelse(is.na(last_service), offset_min, 0))
    }
  }

  limit_min <- service_interval_h * 60
  # Assumed service: every `assume_service_h` of use resets the counter, so only the
  # current cycle decides whether a bike is due now.
  auto_min <- if (is.null(assume_service_h)) Inf else assume_service_h * 60
  usage <- data %>%
    group_by(BIKEID) %>%
    mutate(
      total_min = offset_min + cumsum(DOCID == "0") * interval_min,
      cycle = if (is.finite(auto_min)) floor((total_min + 1e-9) / auto_min) else 0,
      ride_min = if (is.finite(auto_min)) total_min - cycle * auto_min else total_min
    ) %>%
    filter(cycle == max(cycle)) %>%
    summarise(
      ride_hours = max(ride_min) / 60,
      due_at = time[which(ride_min >= limit_min - 1e-9)[1]],
      .groups = "drop"
    )

  current %>%
    left_join(usage, by = "BIKEID") %>%
    mutate(
      ride_hours = coalesce(ride_hours, 0),
      due = !is.na(due_at)
    ) %>%
    select(BIKEID, ride_hours, due, due_at, current_dock) %>%
    arrange(desc(ride_hours))
}


# ------------------------------------------------------------------------------
# rank_stations
# ------------------------------------------------------------------------------
# Short description: Internal helper that aggregates service_status across docked bikes
# to rank stations by due bike count and total overdue hours.

#' Internal Station Ranking by Maintenance Priority
#'
#' @param status Output data frame from [service_status()].
#' @param service_interval_h Numeric threshold for service in hours.
#' @return Ranked data frame of stations.
#' @export
rank_stations <- function(status, service_interval_h) {
  status %>%
    filter(current_dock != "0") %>%
    group_by(DOCID = current_dock) %>%
    summarise(
      n_bikes = n(),
      n_due = sum(due),
      overdue_hours = sum(pmax(ride_hours - service_interval_h, 0)),
      total_ride_hours = sum(ride_hours),
      .groups = "drop"
    ) %>%
    arrange(desc(n_due), desc(overdue_hours))
}


# ------------------------------------------------------------------------------
# station_service_priority
# ------------------------------------------------------------------------------
# Short description: Ranks stations by how many maintenance-due bikes are currently
# docked there, optimizing mobile service van route planning.

#' Rank Stations by Due-for-Service Bikes Docked Now
#'
#' @description
#' Prioritizes station visits for the maintenance crew by sorting stations with the
#' largest count of due bikes currently docked, breaking ties by cumulative overdue hours.
#' Bikes in transit are excluded as they cannot be accessed by the van.
#'
#' @inheritParams service_status
#' @return Data frame with columns `DOCID`, `n_bikes`, `n_due`, `overdue_hours`, `total_ride_hours`.
#' @export
station_service_priority <- function(
    data,
    service_interval_h,
    service_log = NULL,
    interval_min = 5,
    start_hours = NULL,
    assume_service_h = 70
) {
  status <- service_status(data, service_interval_h, service_log, interval_min, start_hours,
                           assume_service_h)
  rank_stations(status, service_interval_h)
}


# ------------------------------------------------------------------------------
# simulate_start_hours
# ------------------------------------------------------------------------------
# Short description: Generates reproducible random starting ride hours for each bike,
# simulating staggered maintenance histories and preventing synchronized failure waves.

#' Generate Staggered Starting Ride Hours for Fleet Simulation
#'
#' @description
#' Assigns a uniform random baseline of prior ride hours between 0 and `service_interval_h`
#' to each bike in the fleet, simulating realistic asynchronous maintenance schedules.
#'
#' @param bike_ids Vector of bike identifier strings.
#' @param service_interval_h Numeric service limit in hours.
#' @param seed Random seed for full reproducibility (default: 42).
#' @return Data frame with columns `BIKEID` and `start_hours`.
#' @export
simulate_start_hours <- function(bike_ids, service_interval_h, seed = 42) {
  if (!is.numeric(service_interval_h) || length(service_interval_h) != 1 || service_interval_h <= 0) {
    stop("service_interval_h must be a positive number")
  }
  bike_ids <- unique(as.character(bike_ids))
  set.seed(seed)
  data.frame(
    BIKEID = bike_ids,
    start_hours = round(stats::runif(length(bike_ids), 0, service_interval_h), 2),
    stringsAsFactors = FALSE
  )
}


# ------------------------------------------------------------------------------
# dispatch_recommendation
# ------------------------------------------------------------------------------
# Short description: High-level unified function that returns a complete operational
# package: stuck-bike alerts, all bikes currently due, and ranked van station stops.

#' Unified Maintenance Dispatch Recommendations
#'
#' @description
#' Primary entry point for maintenance fleet operations. Combines anomaly detection
#' for stuck bikes, individual bike service statuses, and ranked station routing priorities.
#'
#' @inheritParams service_status
#' @param threshold_min Minutes in transit before a stuck-bike alert triggers (default: 90).
#' @return A named list containing:
#'   \describe{
#'     \item{`stuck_alerts`}{Data frame of bikes currently away exceeding `threshold_min`.}
#'     \item{`service_due`}{Data frame of bikes currently meeting or exceeding `service_interval_h`.}
#'     \item{`stations`}{Data frame of stations ranked by number of docked due bikes for van visits.}
#'   }
#' @export
dispatch_recommendation <- function(
    data,
    service_interval_h,
    threshold_min = 90,
    service_log = NULL,
    interval_min = 5,
    start_hours = NULL,
    assume_service_h = 70
) {
  status <- service_status(data, service_interval_h, service_log, interval_min, start_hours,
                           assume_service_h)
  list(
    stuck_alerts = maintenance_alerts(data, threshold_min = threshold_min, interval_min = interval_min),
    service_due  = status %>% filter(due),
    stations     = rank_stations(status, service_interval_h)
  )
}

