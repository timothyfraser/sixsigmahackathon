# app/qc.R - tier-1 core QC statistics for Rush Hour Autopilot (team 2027win)
#
# Plain base-R functions (base, stats, utils only). No plotting, no Shiny.
# Every formula is written out in docs/methods.md sections 4.1-4.3 and checked
# against a hand-worked known answer (KA-1 ... KA-11) in tests/.
#
# Contents
#   1. Small helpers (blank cells, booleans, counts, the issues table)
#   2. parse_ts          ISO 8601 text with offset -> UTC time
#   3. read_scenario, validate_scenario, load_scenario   (loader + validator)
#   4. build_grid, unusable_summary, grid_window_counts, window_summary (4.1)
#   5. p_chart (+ p_dispersion, its overdispersion check), imr_chart (+ the run rule used by both)
#   6. rebalance_plan    (4.3)
#   7. paired_diff_ci

# ---------------------------------------------------------------- constants
IMR_D2 <- 1.128    # d2 for moving ranges of size 2: sigma-hat = MR-bar / 1.128
IMR_D4 <- 3.267    # D4 for moving ranges of size 2: MR UCL = 3.267 * MR-bar
SCENARIO_TABLES <- c("stations", "status", "attempts", "tasks")
RENT_FAILURE_CODES <- c("no_bike", "bike_fault", "dock_fault", "station_closed", "app_error")
RETURN_FAILURE_CODES <- c("no_dock", "dock_fault", "station_closed", "app_error")
TASK_STATUSES <- c("planned", "assigned", "in_progress", "completed", "cancelled")
REQUIRED_COLUMNS <- list(
  stations = c("station_id", "station_name", "latitude", "longitude", "capacity", "region"),
  status = c("timestamp", "station_id", "bikes_available", "docks_available",
             "is_renting", "is_returning"),
  attempts = c("attempt_id", "timestamp", "station_id", "attempt_type", "success",
               "failure_reason"),
  tasks = c("task_id", "van_id", "source_station_id", "destination_station_id",
            "planned_quantity", "actual_quantity", "assigned_at", "arrived_at",
            "completed_at", "status")
)

# ---------------------------------------------------------------- 1. helpers

# TRUE where a text cell is empty or missing.
is_blank <- function(x) is.na(x) | trimws(as.character(x)) == ""

# "TRUE"/"FALSE" text -> logical; anything else -> NA (a row-level problem).
to_bool <- function(x) {
  u <- toupper(trimws(as.character(x)))
  out <- rep(NA, length(u))
  out[u %in% "TRUE"] <- TRUE
  out[u %in% "FALSE"] <- FALSE
  out
}

# Text -> whole number >= 0; anything else (missing, negative, 2.5, "abc") -> NA.
to_count <- function(x) {
  n <- suppressWarnings(as.numeric(as.character(x)))
  n[!is.na(n) & (n < 0 | n != floor(n))] <- NA
  n
}

# The data-issues table: one row per rejected or flagged input row.
empty_issues <- function() {
  data.frame(table = character(0), row = integer(0), id = character(0),
             rule = character(0), action = character(0), stringsAsFactors = FALSE)
}

make_issues <- function(table, row, id, rule, action) {
  if (length(row) == 0) return(empty_issues())
  data.frame(table = table, row = as.integer(row), id = ifelse(is.na(id), "", id),
             rule = rule, action = action, stringsAsFactors = FALSE)
}

# Apply row-level checks in order. `checks` is a named list: the name is the rule,
# the value is a logical vector, TRUE = this row breaks the rule (NA also counts as
# a problem). A row is rejected by the FIRST rule it breaks.
# Returns list(keep = logical vector, issues = issues table).
apply_row_checks <- function(table, row, id, checks) {
  keep <- rep(TRUE, length(row))
  issues <- empty_issues()
  for (rule in names(checks)) {
    bad <- keep & (is.na(checks[[rule]]) | checks[[rule]])
    if (any(bad)) {
      issues <- rbind(issues, make_issues(table, row[bad], id[bad], rule, "rejected"))
      keep <- keep & !bad
    }
  }
  list(keep = keep, issues = issues)
}

# Duplicate handling among rows still kept. Rows with the same `key`:
#   identical `content`  -> keep the first, flag the others ("kept once")
#   different `content`  -> a conflict: reject ALL of them
resolve_duplicates <- function(table, row, id, key, content, keep) {
  issues <- empty_issues()
  idx <- which(keep)
  dup_keys <- unique(key[idx][duplicated(key[idx])])
  for (k in dup_keys) {
    members <- idx[key[idx] == k]
    if (length(unique(content[members])) == 1) {
      extra <- members[-1]
      issues <- rbind(issues, make_issues(table, row[extra], id[extra],
                                          "identical duplicate", "kept once"))
      keep[extra] <- FALSE
    } else {
      issues <- rbind(issues, make_issues(table, row[members], id[members],
                                          "conflicting duplicate", "rejected"))
      keep[members] <- FALSE
    }
  }
  list(keep = keep, issues = issues)
}

# ---------------------------------------------------------------- 2. parse_ts

#' Parse ISO 8601 timestamps that carry a UTC offset.
#' Input : character vector such as "2026-10-05T07:03:30-04:00" ("Z" also accepted).
#' Output: POSIXct vector in UTC; NA for anything that does not parse (row-level).
#' Method: the offset is read explicitly. The local clock part is read as if it
#'         were UTC, then the signed offset is subtracted:
#'         UTC = local - offset, e.g. 07:03:30-04:00 -> 11:03:30 UTC.
parse_ts <- function(x) {
  x <- as.character(x)
  pattern <- "^([0-9]{4}-[0-9]{2}-[0-9]{2})T([0-9]{2}:[0-9]{2}:[0-9]{2})(Z|[+-][0-9]{2}:[0-9]{2})$"
  ok <- !is.na(x) & grepl(pattern, x)
  out <- rep(as.POSIXct(NA, tz = "UTC"), length(x))
  if (any(ok)) {
    local_text <- paste(sub(pattern, "\\1", x[ok]), sub(pattern, "\\2", x[ok]))
    offset_text <- sub(pattern, "\\3", x[ok])
    sign <- ifelse(substr(offset_text, 1, 1) == "-", -1, 1)
    offset_sec <- ifelse(offset_text == "Z", 0,
                         sign * (as.numeric(substr(offset_text, 2, 3)) * 3600 +
                                 as.numeric(substr(offset_text, 5, 6)) * 60))
    local_as_utc <- as.POSIXct(local_text, tz = "UTC", format = "%Y-%m-%d %H:%M:%S")
    out[ok] <- local_as_utc - offset_sec
  }
  out
}

# ---------------------------------------------------------------- 3. loader

#' Read a long-form scenario CSV (all cells as text).
#' Input : path to the CSV. Output: data.frame with a `table` column.
#' Stops (structural error) if the file is missing, unreadable or has no `table` column.
read_scenario <- function(path) {
  if (!is.character(path) || length(path) != 1 || !file.exists(path)) {
    stop("Scenario file not found: ", paste(path, collapse = ", "), call. = FALSE)
  }
  sc <- tryCatch(
    utils::read.csv(path, colClasses = "character", na.strings = c("", "NA"),
                    stringsAsFactors = FALSE, check.names = FALSE,
                    fileEncoding = "UTF-8-BOM"),
    error = function(e) stop("Scenario file could not be read as CSV: ",
                             conditionMessage(e), call. = FALSE)
  )
  if (!"table" %in% names(sc)) {
    stop("Scenario file has no `table` column; it must be a long-form file with the ",
         "record types stations, status, attempts, tasks.", call. = FALSE)
  }
  sc
}

#' Check a scenario and split it into four clean tables plus a data-issues table.
#' Input : data.frame from read_scenario (long form, `table` column).
#' Output: list(stations, status, attempts, tasks, issues).
#'   STRUCTURAL problems stop() with a clear message (methods section 7):
#'     no `table`/`data_source` column, unknown table value, no stations rows,
#'     a required column missing for a record type that is present,
#'     a duplicated station_id in stations.
#'   ROW-LEVEL problems never stop. The row is rejected (left out) or flagged
#'   (kept once) and listed in `issues` (table, row, id, rule, action);
#'   `row` is the row number in the input data (header not counted).
#' Assumption: the text in the cells is the only source of truth; a bad value is
#'   never replaced by 0.
validate_scenario <- function(sc) {
  if (!is.data.frame(sc)) stop("The scenario must be a data.frame.", call. = FALSE)
  for (col in c("table", "data_source")) {
    if (!col %in% names(sc)) stop("Scenario has no `", col, "` column.", call. = FALSE)
  }
  sc[] <- lapply(sc, function(col) {
    col <- trimws(as.character(col))
    col[!is.na(col) & col == ""] <- NA
    col
  })

  bad_tables <- setdiff(unique(sc$table), SCENARIO_TABLES)
  if (length(bad_tables) > 0) {
    stop("Unknown `table` value(s): ", paste(bad_tables, collapse = ", "),
         ". Allowed: ", paste(SCENARIO_TABLES, collapse = ", "), ".", call. = FALSE)
  }
  if (!any(sc$table %in% "stations")) {
    stop("The scenario has no stations rows.", call. = FALSE)
  }
  for (type in SCENARIO_TABLES) {
    if (!any(sc$table %in% type)) next
    missing_cols <- setdiff(REQUIRED_COLUMNS[[type]], names(sc))
    if (length(missing_cols) > 0) {
      stop("Required column(s) missing for the ", type, " records: ",
           paste(missing_cols, collapse = ", "), ".", call. = FALSE)
    }
  }
  station_ids <- sc$station_id[sc$table %in% "stations"]
  dup_ids <- unique(station_ids[!is.na(station_ids) & duplicated(station_ids)])
  if (length(dup_ids) > 0) {
    stop("station_id duplicated in stations (capacity would be ambiguous): ",
         paste(dup_ids, collapse = ", "), call. = FALSE)
  }

  row_no <- seq_len(nrow(sc))
  stations <- clean_stations(sc[sc$table %in% "stations", ], row_no[sc$table %in% "stations"])
  status <- clean_status(sc[sc$table %in% "status", ], row_no[sc$table %in% "status"],
                         stations$data)
  attempts <- clean_attempts(sc[sc$table %in% "attempts", ], row_no[sc$table %in% "attempts"],
                             stations$data)
  tasks <- clean_tasks(sc[sc$table %in% "tasks", ], row_no[sc$table %in% "tasks"],
                       stations$data)

  issues <- rbind(stations$issues, status$issues, attempts$issues, tasks$issues)
  issues <- issues[order(match(issues$table, SCENARIO_TABLES), issues$row), ]
  rownames(issues) <- NULL
  list(stations = stations$data, status = status$data, attempts = attempts$data,
       tasks = tasks$data, issues = issues)
}

#' Read and validate in one step. Output: same list as validate_scenario.
load_scenario <- function(path) validate_scenario(read_scenario(path))

clean_stations <- function(raw, row) {
  lat <- suppressWarnings(as.numeric(raw$latitude))
  lon <- suppressWarnings(as.numeric(raw$longitude))
  cap <- to_count(raw$capacity)
  res <- apply_row_checks("stations", row, raw$station_id, list(
    "missing station_id" = is.na(raw$station_id),
    "invalid latitude/longitude" = is.na(lat) | is.na(lon) | abs(lat) > 90 | abs(lon) > 180,
    "invalid capacity" = is.na(cap) | cap <= 0
  ))
  keep <- res$keep
  data <- data.frame(row = row, station_id = raw$station_id, station_name = raw$station_name,
                     latitude = lat, longitude = lon, capacity = cap, region = raw$region,
                     stringsAsFactors = FALSE)[keep, ]
  rownames(data) <- NULL
  list(data = data, issues = res$issues)
}

clean_status <- function(raw, row, stations) {
  ts <- parse_ts(raw$timestamp)
  bikes <- to_count(raw$bikes_available)
  docks <- to_count(raw$docks_available)
  renting <- to_bool(raw$is_renting)
  returning <- to_bool(raw$is_returning)
  cap <- stations$capacity[match(raw$station_id, stations$station_id)]
  res <- apply_row_checks("status", row, raw$station_id, list(
    "unparseable timestamp" = is.na(ts),
    "negative or missing count" = is.na(bikes) | is.na(docks),
    "invalid flag" = is.na(renting) | is.na(returning),
    "unknown station_id" = is.na(cap),
    "bikes + docks > capacity" = bikes + docks > cap
  ))
  key <- paste(raw$station_id, as.numeric(ts))
  content <- paste(bikes, docks, renting, returning)
  dup <- resolve_duplicates("status", row, raw$station_id, key, content, res$keep)
  data <- data.frame(row = row, station_id = raw$station_id, timestamp = ts,
                     bikes_available = bikes, docks_available = docks,
                     is_renting = renting, is_returning = returning,
                     stringsAsFactors = FALSE)[dup$keep, ]
  data <- data[order(data$station_id, data$timestamp), ]
  rownames(data) <- NULL
  list(data = data, issues = rbind(res$issues, dup$issues))
}

clean_attempts <- function(raw, row, stations) {
  ts <- parse_ts(raw$timestamp)
  success <- to_bool(raw$success)
  reason <- raw$failure_reason
  type <- raw$attempt_type
  allowed <- ifelse(type %in% "rent", reason %in% RENT_FAILURE_CODES,
                    reason %in% RETURN_FAILURE_CODES)
  consistent <- (success %in% TRUE & is.na(reason)) | (success %in% FALSE & allowed)
  res <- apply_row_checks("attempts", row, raw$attempt_id, list(
    "missing attempt_id" = is.na(raw$attempt_id),
    "unparseable timestamp" = is.na(ts),
    "unknown station_id" = !(raw$station_id %in% stations$station_id),
    "invalid attempt_type" = !(type %in% c("rent", "return")),
    "invalid success flag" = is.na(success),
    "success inconsistent with failure_reason" = !consistent
  ))
  content <- paste(as.numeric(ts), raw$station_id, type, success, reason)
  dup <- resolve_duplicates("attempts", row, raw$attempt_id, raw$attempt_id, content, res$keep)
  data <- data.frame(row = row, attempt_id = raw$attempt_id, timestamp = ts,
                     station_id = raw$station_id, attempt_type = type, success = success,
                     failure_reason = reason, stringsAsFactors = FALSE)[dup$keep, ]
  rownames(data) <- NULL
  list(data = data, issues = rbind(res$issues, dup$issues))
}

clean_tasks <- function(raw, row, stations) {
  status <- raw$status
  planned <- to_count(raw$planned_quantity)
  actual <- to_count(raw$actual_quantity)
  t_assigned <- parse_ts(raw$assigned_at)
  t_arrived <- parse_ts(raw$arrived_at)
  t_completed <- parse_ts(raw$completed_at)
  bad_time <- (!is_blank(raw$assigned_at) & is.na(t_assigned)) |
    (!is_blank(raw$arrived_at) & is.na(t_arrived)) |
    (!is_blank(raw$completed_at) & is.na(t_completed))
  from_assigned <- status %in% c("assigned", "in_progress", "completed")
  from_in_progress <- status %in% c("in_progress", "completed")
  is_completed <- status %in% "completed"
  missing_required <-
    (!(status %in% "planned") & is.na(raw$van_id)) |
    (from_assigned & is.na(t_assigned)) |
    (from_in_progress & is.na(t_arrived)) |
    (is_completed & (is.na(t_completed) | is.na(actual)))
  bad_actual <- !is_blank(raw$actual_quantity) & (is.na(actual) | actual > planned)
  out_of_order <-
    (!is.na(t_assigned) & !is.na(t_arrived) & t_assigned > t_arrived) |
    (!is.na(t_arrived) & !is.na(t_completed) & t_arrived > t_completed) |
    (!is.na(t_assigned) & !is.na(t_completed) & t_assigned > t_completed)
  res <- apply_row_checks("tasks", row, raw$task_id, list(
    "missing task_id" = is.na(raw$task_id),
    "invalid status" = !(status %in% TASK_STATUSES),
    "unparseable timestamp" = bad_time,
    "source equals destination" = is.na(raw$source_station_id) | is.na(raw$destination_station_id) |
      raw$source_station_id == raw$destination_station_id,
    "unknown station_id" = !(raw$source_station_id %in% stations$station_id) |
      !(raw$destination_station_id %in% stations$station_id),
    "invalid planned_quantity" = is.na(planned) | planned <= 0,
    "missing required field for status" = missing_required,
    "invalid actual_quantity" = bad_actual,
    "task times out of order" = out_of_order
  ))
  content <- paste(raw$van_id, raw$source_station_id, raw$destination_station_id, planned,
                   actual, as.numeric(t_assigned), as.numeric(t_arrived),
                   as.numeric(t_completed), status)
  dup <- resolve_duplicates("tasks", row, raw$task_id, raw$task_id, content, res$keep)
  data <- data.frame(row = row, task_id = raw$task_id, van_id = raw$van_id,
                     source_station_id = raw$source_station_id,
                     destination_station_id = raw$destination_station_id,
                     planned_quantity = planned, actual_quantity = actual,
                     assigned_at = t_assigned, arrived_at = t_arrived,
                     completed_at = t_completed, status = status,
                     stringsAsFactors = FALSE)[dup$keep, ]
  rownames(data) <- NULL
  list(data = data, issues = rbind(res$issues, dup$issues))
}

# ---------------------------------------------------------------- 4. grid (methods 4.1)

#' Build the station-minute grid for one rush window.
#' Input : status  = cleaned status table (from validate_scenario),
#'         stations = cleaned stations table, date = "YYYY-MM-DD" (local date),
#'         start/end = "HH:MM" local clock, tz = time zone of the window,
#'         stale_limit = largest snapshot age (minutes) that still counts (demo assumption).
#' Output: one row per station x minute interval [m, m+1). Interval m takes the
#'         most recent valid snapshot with timestamp <= m (a snapshot later inside the
#'         minute is never used). age = m - snapshot time, in minutes (seconds count).
#'         age <= stale_limit -> known = TRUE, otherwise the minute is unknown and every
#'         state column is NA (never 0 or FALSE).
#' Columns: station_id, minute, known, age, bikes_available, docks_available, is_renting,
#'         is_returning, rent_unusable (bikes == 0 or not renting), return_unusable
#'         (docks == 0 or not returning), either_unusable (union), warn_bike
#'         (0 < bikes <= 2), warn_dock (0 < docks <= 2). Early warning is not a failure.
build_grid <- function(status, stations, date, start = "07:00", end = "10:00",
                       tz = "America/New_York", stale_limit = 2) {
  start_time <- as.POSIXct(paste(as.character(date), start), tz = tz, format = "%Y-%m-%d %H:%M")
  end_time <- as.POSIXct(paste(as.character(date), end), tz = tz, format = "%Y-%m-%d %H:%M")
  if (is.na(start_time) || is.na(end_time)) stop("date/start/end could not be read.", call. = FALSE)
  n_min <- round(as.numeric(difftime(end_time, start_time, units = "mins")))
  if (n_min < 1) stop("end must be after start.", call. = FALSE)
  minute_secs <- as.numeric(start_time) + 60 * (0:(n_min - 1))

  pieces <- lapply(stations$station_id, function(id) {
    snaps <- status[status$station_id == id, ]
    snaps <- snaps[order(snaps$timestamp), ]
    snap_secs <- as.numeric(snaps$timestamp)
    last <- findInterval(minute_secs, snap_secs)       # last snapshot at or before m; 0 = none
    age <- ifelse(last > 0, (minute_secs - snap_secs[pmax(last, 1)]) / 60, NA_real_)
    known <- !is.na(age) & age <= stale_limit + 1e-9
    pick <- function(v) { out <- v[pmax(last, 1)]; out[!known] <- NA; out }
    bikes <- pick(snaps$bikes_available)
    docks <- pick(snaps$docks_available)
    renting <- pick(snaps$is_renting)
    returning <- pick(snaps$is_returning)
    data.frame(
      station_id = id, minute = .POSIXct(minute_secs, tz = tz), known = known,
      age = ifelse(known, age, NA_real_),
      bikes_available = bikes, docks_available = docks,
      is_renting = renting, is_returning = returning,
      rent_unusable = bikes == 0 | !renting,
      return_unusable = docks == 0 | !returning,
      either_unusable = (bikes == 0 | !renting) | (docks == 0 | !returning),
      warn_bike = bikes > 0 & bikes <= 2,
      warn_dock = docks > 0 & docks <= 2,
      stringsAsFactors = FALSE
    )
  })
  grid <- do.call(rbind, pieces)
  rownames(grid) <- NULL
  grid
}

# Count minutes for one block of grid rows (unknown minutes are NA and not counted).
summarise_minutes <- function(g) {
  known <- sum(g$known)
  unknown <- sum(!g$known)
  data.frame(
    known_min = known, unknown_min = unknown,
    coverage = if (known + unknown > 0) known / (known + unknown) else NA_real_,
    rent_unusable_min = sum(g$rent_unusable, na.rm = TRUE),
    return_unusable_min = sum(g$return_unusable, na.rm = TRUE),
    either_unusable_min = sum(g$either_unusable, na.rm = TRUE),
    warn_bike_min = sum(g$warn_bike, na.rm = TRUE),
    warn_dock_min = sum(g$warn_dock, na.rm = TRUE),
    either_share = if (known > 0) sum(g$either_unusable, na.rm = TRUE) / known else NA_real_
  )
}

#' Per-station minute counts from the grid.
#' Output: station_id, known_min, unknown_min, coverage = known / (known + unknown),
#'         rent/return/either unusable minutes, warn_bike/warn_dock minutes,
#'         either_share = either / known (NA when nothing is known).
#' Coverage comes ONLY from the grid; unknown minutes are never counted as usable
#' or unusable. Compare stations by the share per known minute, not by raw totals.
unusable_summary <- function(grid) {
  ids <- unique(grid$station_id)
  rows <- lapply(ids, function(id) cbind(station_id = id, summarise_minutes(grid[grid$station_id == id, ])))
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

#' Window totals from a grid, for a fixed station set.
#' Input : grid (one rush window), station_ids = the fixed station set (NULL = all).
#' Output: one-row data.frame(window, known, unknown, either_min) for window_summary().
grid_window_counts <- function(grid, station_ids = NULL, window = NA_character_) {
  if (!is.null(station_ids)) grid <- grid[grid$station_id %in% station_ids, ]
  s <- summarise_minutes(grid)
  data.frame(window = window, known = s$known_min, unknown = s$unknown_min,
             either_min = s$either_unusable_min, stringsAsFactors = FALSE)
}

#' Rush-window coverage and inclusion rule for SPC (methods 4.1, KA-11).
#' Input : equal-length vectors known, unknown, either_min (station-minutes per window),
#'         optional window labels, min_coverage (default 0.95, a demo assumption).
#' Output: window, known, unknown, coverage, either_min, either_share_pct
#'         (100 * either / known), included (coverage >= min_coverage) and a reason
#'         when excluded. Excluded windows must stay out of the I-MR/c baseline.
window_summary <- function(known, unknown, either_min, window = NULL, min_coverage = 0.95) {
  if (length(unknown) != length(known) || length(either_min) != length(known)) {
    stop("known, unknown and either_min must have the same length.", call. = FALSE)
  }
  if (is.null(window)) window <- seq_along(known)
  total <- known + unknown
  coverage <- ifelse(total > 0, known / total, NA_real_)
  included <- !is.na(coverage) & coverage >= min_coverage - 1e-9
  reason <- ifelse(included, "",
                   ifelse(is.na(coverage), "no minutes in the window",
                          sprintf("coverage %.1f%% is below the %g%% minimum",
                                  100 * coverage, 100 * min_coverage)))
  data.frame(window = window, known = known, unknown = unknown, coverage = coverage,
             either_min = either_min,
             either_share_pct = ifelse(known > 0, 100 * either_min / known, NA_real_),
             included = included, reason = reason, stringsAsFactors = FALSE)
}

# ---------------------------------------------------------------- 5. control charts

# Western Electric rule 4: flag a point when it is the 8th (or later) in a row on the
# same side of the centre line. A point on the centre line, or NA, breaks the run.
run_flags <- function(x, center, run_length = 8) {
  d <- x - center
  side <- ifelse(is.na(d), NA, ifelse(abs(d) < 1e-12, 0, sign(d)))
  flag <- rep(FALSE, length(x))
  run <- 0
  previous <- 0
  for (i in seq_along(x)) {
    if (is.na(side[i]) || side[i] == 0) {
      run <- 0
      previous <- 0
    } else {
      run <- if (side[i] == previous) run + 1 else 1
      previous <- side[i]
      flag[i] <- run >= run_length
    }
  }
  flag
}

# baseline: logical vector (same length) or index numbers -> logical vector.
as_baseline_flag <- function(baseline, k) {
  if (is.logical(baseline)) {
    if (length(baseline) != k || anyNA(baseline)) {
      stop("baseline must be TRUE/FALSE for every subgroup, with no NA.", call. = FALSE)
    }
    return(baseline)
  }
  if (!is.numeric(baseline) || any(baseline < 1 | baseline > k | baseline != floor(baseline))) {
    stop("baseline must be TRUE/FALSE flags or subgroup index numbers.", call. = FALSE)
  }
  seq_len(k) %in% baseline
}

#' p chart for a proportion of failures (rent or return attempts per rush window).
#' Input : failures (counts), n (attempts per subgroup), baseline (TRUE/FALSE or index
#'         numbers: the subgroups used to estimate p-bar; default all).
#' Method: p_i = failures_i / n_i. p-bar = sum(baseline failures) / sum(baseline n).
#'         Limits p-bar +/- 3*sqrt(p-bar*(1 - p-bar)/n_i) for each subgroup, UCL capped
#'         at 1 and LCL floored at 0. Out of control = Western Electric rule 1 (outside
#'         the limits) or rule 4 (8 in a row on one side of p-bar).
#' Output: list(data, p_bar, totals, note, dispersion). data has subgroup, failures, n, p,
#'         center, ucl, lcl, rule1, rule4, out_of_control. dispersion: see p_dispersion().
#' NA rules: p-bar = 0 or 1, or fewer than 2 usable baseline subgroups -> limits and
#'         signals are NA with a reason in `note`. n_i = 0 -> that p is NA. Counts,
#'         p and totals are always kept.
p_chart <- function(failures, n, baseline = rep(TRUE, length(failures))) {
  if (length(failures) != length(n)) stop("failures and n must have the same length.", call. = FALSE)
  if (any(failures < 0 | n < 0, na.rm = TRUE)) stop("failures and n cannot be negative.", call. = FALSE)
  if (any(failures > n, na.rm = TRUE)) stop("failures cannot be larger than n.", call. = FALSE)
  k <- length(failures)
  base <- as_baseline_flag(baseline, k)
  notes <- character(0)

  usable <- !is.na(failures) & !is.na(n) & n > 0
  if (any(!is.na(n) & n == 0)) notes <- c(notes, "n = 0 for some subgroups: p is NA for those subgroups")
  if (anyNA(failures) | anyNA(n)) notes <- c(notes, "missing values were excluded, not treated as 0")
  in_base <- base & usable
  p <- ifelse(usable, failures / n, NA_real_)
  p_bar <- if (any(in_base)) sum(failures[in_base]) / sum(n[in_base]) else NA_real_

  limits_ok <- TRUE
  if (!is.na(p_bar) && p_bar == 0) {
    limits_ok <- FALSE
    notes <- c(notes, "p-bar = 0: limits cannot be estimated; no failures observed does not mean zero risk")
  } else if (!is.na(p_bar) && p_bar == 1) {
    limits_ok <- FALSE
    notes <- c(notes, "p-bar = 1: limits cannot be estimated; every attempt failed")
  } else if (sum(in_base) < 2) {
    limits_ok <- FALSE
    notes <- c(notes, "fewer than 2 baseline subgroups: limits cannot be estimated")
  }

  if (limits_ok) {
    sigma <- sqrt(p_bar * (1 - p_bar) / n)
    ucl <- ifelse(usable, pmin(1, p_bar + 3 * sigma), NA_real_)
    lcl <- ifelse(usable, pmax(0, p_bar - 3 * sigma), NA_real_)
    rule1 <- !is.na(p) & (p > ucl | p < lcl)
    rule4 <- run_flags(p, p_bar)
    out <- rule1 | rule4
  } else {
    ucl <- lcl <- rep(NA_real_, k)
    rule1 <- rule4 <- out <- rep(NA, k)
  }
  data <- data.frame(subgroup = seq_len(k), failures = failures, n = n, p = p,
                     center = p_bar, ucl = ucl, lcl = lcl, rule1 = rule1, rule4 = rule4,
                     out_of_control = out)
  list(data = data, p_bar = p_bar,
       totals = c(failures = sum(failures[usable]), n = sum(n[usable])),
       note = paste(notes, collapse = "; "),
       dispersion = p_dispersion(failures[in_base], n[in_base]))
}

#' Overdispersion check for a p chart's baseline (does the baseline vary more than the
#' binomial model behind the limits allows?). It only adds information: the limits stay.
#' Input : failures and n of the usable baseline subgroups (n > 0).
#' Method: p-bar = sum(failures) / sum(n). Pearson chi-square
#'         X2 = sum((failures_i - n_i*p-bar)^2 / (n_i*p-bar*(1 - p-bar))), df = k - 1,
#'         ratio = X2 / df (about 1 under the binomial model), p_value = P(chi2_df > X2).
#'         warning = ratio > 1.5 (the same demo threshold as the c chart's variance/mean).
#'         The p-value relies on the chi-square approximation (expected counts n_i*p-bar and
#'         n_i*(1 - p-bar) of about 5 or more); the note says so when that does not hold.
#' Output: list(chi_sq, df, ratio, p_value, warning, note).
#' NA rules: fewer than 2 baseline subgroups, or p-bar = 0 or 1 -> all NA with a reason.
p_dispersion <- function(failures, n) {
  out <- list(chi_sq = NA_real_, df = NA_integer_, ratio = NA_real_, p_value = NA_real_,
              warning = NA, note = "")
  k <- length(failures)
  if (k < 2) {
    out$note <- "fewer than 2 baseline subgroups: dispersion cannot be estimated"
    return(out)
  }
  p_bar <- sum(failures) / sum(n)
  if (p_bar == 0 || p_bar == 1) {
    out$note <- sprintf("p-bar = %g: dispersion cannot be estimated", p_bar)
    return(out)
  }
  expected_fail <- n * p_bar
  chi_sq <- sum((failures - expected_fail)^2 / (expected_fail * (1 - p_bar)))
  df <- k - 1L
  ratio <- chi_sq / df
  out$chi_sq <- chi_sq
  out$df <- df
  out$ratio <- ratio
  out$p_value <- stats::pchisq(chi_sq, df, lower.tail = FALSE)
  out$warning <- ratio > 1.5
  notes <- if (out$warning) {
    sprintf(paste("dispersion ratio %.2f > 1.5: the baseline varies more than the binomial",
                  "model allows (for example, attempts at the same station and time are not",
                  "independent). The limits are likely too narrow, so a point beyond them is a",
                  "prompt to investigate, not a confirmed special cause"), ratio)
  } else {
    sprintf("dispersion ratio %.2f <= 1.5: no sign of extra-binomial variation in the baseline", ratio)
  }
  notes <- c(notes, "the ratio and p-value rely on the chi-square approximation and do not identify a cause")
  if (any(expected_fail < 5 | n * (1 - p_bar) < 5)) {
    notes <- c(notes, "some expected counts are below 5, so the p-value is only rough")
  }
  out$note <- paste(notes, collapse = "; ")
  out
}

#' I-MR chart for individual values (e.g. the either-unusable share per rush window).
#' Input : x (one value per subgroup), baseline (TRUE/FALSE or indexes; default all).
#' Method: center = mean of baseline x. MR_i = |x_i - x_(i-1)| (shown for every point).
#'         MR-bar = mean of the moving ranges between consecutive baseline points.
#'         sigma-hat = MR-bar / 1.128. I limits center +/- 3*sigma-hat.
#'         MR UCL = 3.267*MR-bar, MR LCL = 0. Rules: 1 (outside limits) and 4 (8 in a row
#'         on one side of the center); a moving range above its UCL is also flagged.
#' Output: list(data, center, mr_bar, sigma_hat, ucl, lcl, mr_ucl, mr_lcl, note).
#' NA rules: fewer than 2 baseline points, or MR-bar = 0 (constant data) -> limits and
#'         signals are NA with a note; x, center and the moving ranges are still returned.
imr_chart <- function(x, baseline = rep(TRUE, length(x))) {
  k <- length(x)
  base <- as_baseline_flag(baseline, k)
  in_base <- base & !is.na(x)
  xb <- x[in_base]
  center <- if (length(xb) >= 1) mean(xb) else NA_real_
  mr <- if (k >= 1) c(NA_real_, abs(diff(x))) else numeric(0)
  mr_bar <- if (length(xb) >= 2) mean(abs(diff(xb))) else NA_real_

  notes <- character(0)
  if (anyNA(x)) notes <- c(notes, "missing values were excluded, not treated as 0")
  limits_ok <- TRUE
  if (length(xb) < 2) {
    limits_ok <- FALSE
    notes <- c(notes, "fewer than 2 baseline points: limits cannot be estimated")
  } else if (mr_bar < 1e-12) {
    limits_ok <- FALSE
    notes <- c(notes, "zero variation: all baseline values are identical, so limits cannot be estimated")
  }

  if (limits_ok) {
    sigma_hat <- mr_bar / IMR_D2
    ucl <- center + 3 * sigma_hat
    lcl <- center - 3 * sigma_hat
    mr_ucl <- IMR_D4 * mr_bar
    mr_lcl <- 0
    rule1 <- !is.na(x) & (x > ucl | x < lcl)
    rule4 <- run_flags(x, center)
    mr_signal <- !is.na(mr) & mr > mr_ucl
    out <- rule1 | rule4 | mr_signal
  } else {
    sigma_hat <- ucl <- lcl <- mr_ucl <- mr_lcl <- NA_real_
    rule1 <- rule4 <- mr_signal <- out <- rep(NA, k)
  }
  data <- data.frame(subgroup = seq_len(k), x = x, center = center, mr = mr,
                     ucl = ucl, lcl = lcl, mr_ucl = mr_ucl, rule1 = rule1, rule4 = rule4,
                     mr_signal = mr_signal, out_of_control = out)
  list(data = data, center = center, mr_bar = mr_bar, sigma_hat = sigma_hat, ucl = ucl,
       lcl = lcl, mr_ucl = mr_ucl, mr_lcl = mr_lcl, note = paste(notes, collapse = "; "))
}

# ---------------------------------------------------------------- 6. rebalancing (methods 4.3)

# Great-circle distance in km between points given in decimal degrees.
haversine_km <- function(lat1, lon1, lat2, lon2) {
  rad <- pi / 180
  a <- sin((lat2 - lat1) * rad / 2)^2 +
    cos(lat1 * rad) * cos(lat2 * rad) * sin((lon2 - lon1) * rad / 2)^2
  2 * 6371.0088 * asin(pmin(1, sqrt(a)))
}

#' Greedy rebalancing plan (a demo heuristic, NOT an optimiser).
#' Input : state = one row per station with station_id, bikes_available, docks_available,
#'         is_renting, is_returning (the latest valid snapshot);
#'         stations = station_id, latitude, longitude, capacity;
#'         rank = optional data.frame(station_id, rank), 1 = worst (stations not listed
#'         come last); target_fill (0.5), van_capacity (12 bikes), detour (1.3) are
#'         demo assumptions.
#' Method: target = round(target_fill * capacity). Surplus = bikes above target, deficit =
#'         bikes below target. Closed stations (a flag FALSE or missing data) are left out
#'         and get a maintenance / data-check recommendation. Deficit stations are taken
#'         worst rank first (ties: station_id ascending); each gets ONE move from the
#'         nearest station that still has surplus (haversine km * detour; ties: station_id
#'         ascending). quantity = min(source surplus, destination deficit, destination free
#'         docks, van_capacity). Planned bikes and docks are reserved, so nothing is
#'         planned twice.
#' Output: list(moves = from_station, to_station, quantity, est_distance_km, distance_basis;
#'         excluded = station_id, reason, recommendation;
#'         unmet = station_id, remaining_deficit after the moves).
rebalance_plan <- function(state, stations, rank = NULL, target_fill = 0.5,
                           van_capacity = 12, detour = 1.3) {
  need_state <- c("station_id", "bikes_available", "docks_available", "is_renting", "is_returning")
  need_stations <- c("station_id", "latitude", "longitude", "capacity")
  if (length(setdiff(need_state, names(state))) > 0) {
    stop("state needs columns: ", paste(need_state, collapse = ", "), call. = FALSE)
  }
  if (length(setdiff(need_stations, names(stations))) > 0) {
    stop("stations needs columns: ", paste(need_stations, collapse = ", "), call. = FALSE)
  }
  pos <- match(state$station_id, stations$station_id)
  if (anyNA(pos)) stop("state has a station_id that is not in stations.", call. = FALSE)
  d <- data.frame(station_id = state$station_id, bikes = state$bikes_available,
                  docks = state$docks_available, renting = state$is_renting,
                  returning = state$is_returning, capacity = stations$capacity[pos],
                  lat = stations$latitude[pos], lon = stations$longitude[pos],
                  stringsAsFactors = FALSE)
  d <- d[order(d$station_id, method = "radix"), ]

  no_data <- is.na(d$bikes) | is.na(d$docks) | is.na(d$renting) | is.na(d$returning)
  closed <- no_data | !d$renting | !d$returning
  excluded <- data.frame(
    station_id = d$station_id[closed],
    reason = ifelse(no_data[closed], "missing station data", "renting or returning is switched off"),
    recommendation = ifelse(no_data[closed], "data check, not a rebalancing move",
                            "maintenance or data check, not a rebalancing move"),
    stringsAsFactors = FALSE)
  a <- d[!closed, ]
  target <- round(target_fill * a$capacity)
  surplus <- pmax(a$bikes - target, 0)
  deficit <- pmax(target - a$bikes, 0)
  free_docks <- a$docks

  rank_value <- rep(0, nrow(a))
  if (!is.null(rank)) {
    rank_value <- rank$rank[match(a$station_id, rank$station_id)]
    rank_value[is.na(rank_value)] <- Inf
  }
  todo <- which(deficit > 0)
  todo <- todo[order(rank_value[todo], a$station_id[todo], method = "radix")]

  moves <- list()
  for (i in todo) {
    sources <- which(surplus > 0)
    if (length(sources) == 0) break
    km <- haversine_km(a$lat[i], a$lon[i], a$lat[sources], a$lon[sources]) * detour
    best <- sources[order(round(km, 9), a$station_id[sources], method = "radix")[1]]
    qty <- min(surplus[best], deficit[i], free_docks[i], van_capacity)
    if (qty <= 0) next
    surplus[best] <- surplus[best] - qty
    deficit[i] <- deficit[i] - qty
    free_docks[i] <- free_docks[i] - qty
    moves[[length(moves) + 1]] <- data.frame(
      from_station = a$station_id[best], to_station = a$station_id[i], quantity = qty,
      est_distance_km = round(haversine_km(a$lat[best], a$lon[best], a$lat[i], a$lon[i]) * detour, 2),
      distance_basis = "estimated travel distance (straight line x detour factor), not a road route",
      stringsAsFactors = FALSE)
  }
  moves <- if (length(moves) > 0) do.call(rbind, moves) else
    data.frame(from_station = character(0), to_station = character(0), quantity = numeric(0),
               est_distance_km = numeric(0), distance_basis = character(0))
  unmet <- data.frame(station_id = a$station_id[deficit > 0], remaining_deficit = deficit[deficit > 0],
                      stringsAsFactors = FALSE)
  list(moves = moves, excluded = excluded, unmet = unmet)
}

# ---------------------------------------------------------------- 7. paired difference CI

#' Confidence interval for the mean of paired differences (e.g. unusable minutes saved).
#' Input : d = one paired difference per seed; conf = family confidence (0.95);
#'         family_size = number of comparisons in the family (Bonferroni).
#' Method: per-comparison level = 1 - (1 - conf)/family_size.
#'         mean +/- t(1 - (1 - level)/2, n - 1) * s / sqrt(n).
#' Output: one-row data.frame(n, n_missing, mean, sd, se, t, lower, upper, conf_level, note).
#' NA rules: missing differences are excluded and counted. n < 2 -> the mean is kept;
#'         sd, se, t and the interval are NA with a note.
paired_diff_ci <- function(d, conf = 0.95, family_size = 1) {
  if (!is.numeric(conf) || conf <= 0 || conf >= 1) stop("conf must be between 0 and 1.", call. = FALSE)
  if (!is.numeric(family_size) || family_size < 1) stop("family_size must be at least 1.", call. = FALSE)
  n_missing <- sum(is.na(d))
  d <- d[!is.na(d)]
  n <- length(d)
  level <- 1 - (1 - conf) / family_size
  out <- data.frame(n = n, n_missing = n_missing, mean = if (n >= 1) mean(d) else NA_real_,
                    sd = NA_real_, se = NA_real_, t = NA_real_, lower = NA_real_,
                    upper = NA_real_, conf_level = level, note = "")
  if (n < 2) {
    out$note <- "n < 2: no interval can be estimated"
    return(out)
  }
  out$sd <- stats::sd(d)
  out$se <- out$sd / sqrt(n)
  out$t <- stats::qt(1 - (1 - level) / 2, df = n - 1)
  out$lower <- out$mean - out$t * out$se
  out$upper <- out$mean + out$t * out$se
  if (out$sd == 0) out$note <- "all differences are identical: the interval has zero width"
  out
}
