# app/prep.R - data shaping for the dashboard (team 2027win)
#
# Plain base-R helpers. NO statistics are computed here: every control limit, rate and
# plan comes from app/qc.R. These functions only pick rows, count rows, sort and join.
# (Counting attempts and failures is counting rows of the attempt log; failures are
# never inferred from inventory.)
#
# Contents
#   1. dates and windows      local_date, scenario_dates, window_bounds
#   2. attempts               attempts_by_day
#   3. grids                  fixed_station_set, build_day_grids, window_table,
#                             set_warning_threshold
#   4. one day                state_at, explain_exclusion, rank_stations, station_table,
#                             kpi_summary
#   5. charts' inputs         hour_station_matrix, pareto_order
#   6. baseline               baseline_count, baseline_flags
#   7. data source            default_scenario_path

APP_TZ <- "America/New_York"
STATE_LEVELS <- c("rent-unusable", "return-unusable", "rent- and return-unusable",
                  "early warning", "usable", "unknown / stale data")

# ---------------------------------------------------------------- 1. dates and windows

# POSIXct -> "YYYY-MM-DD" on the local (New York) calendar.
local_date <- function(x, tz = APP_TZ) format(x, "%Y-%m-%d", tz = tz)

# Sorted weekday dates (Mon-Fri) that have at least one status or attempt row.
scenario_dates <- function(status, attempts, tz = APP_TZ) {
  all_ts <- c(status$timestamp, attempts$timestamp)
  all_ts <- all_ts[!is.na(all_ts)]
  if (length(all_ts) == 0) return(character(0))
  d <- sort(unique(local_date(all_ts, tz)))
  weekday_number <- as.POSIXlt(as.Date(d))$wday        # 0 = Sunday ... 6 = Saturday
  d[weekday_number %in% 1:5]
}

# Start and end (POSIXct) of the rush window on one date.
window_bounds <- function(date, start = "07:00", end = "10:00", tz = APP_TZ) {
  list(start = as.POSIXct(paste(date, start), tz = tz, format = "%Y-%m-%d %H:%M"),
       end = as.POSIXct(paste(date, end), tz = tz, format = "%Y-%m-%d %H:%M"))
}

# ---------------------------------------------------------------- 2. attempts

# Attempts and failures per rush window, counted from the attempt rows.
# Output: date, rent_n, rent_fail, return_n, return_fail (all counts; 0 when no attempts).
attempts_by_day <- function(attempts, dates, start = "07:00", end = "10:00", tz = APP_TZ) {
  empty <- data.frame(date = character(0), rent_n = integer(0), rent_fail = integer(0),
                      return_n = integer(0), return_fail = integer(0),
                      stringsAsFactors = FALSE)
  if (length(dates) == 0) return(empty)
  rows <- lapply(dates, function(d) {
    b <- window_bounds(d, start, end, tz)
    secs <- as.numeric(attempts$timestamp)       # compare as seconds: time zones do not matter
    a <- attempts[!is.na(secs) & secs >= as.numeric(b$start) & secs < as.numeric(b$end), ]
    is_rent <- a$attempt_type == "rent"
    is_return <- a$attempt_type == "return"
    data.frame(date = d,
               rent_n = sum(is_rent), rent_fail = sum(is_rent & !a$success),
               return_n = sum(is_return), return_fail = sum(is_return & !a$success),
               stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

# ---------------------------------------------------------------- 3. grids

# The fixed station set: stations with at least one status row on EVERY date given.
fixed_station_set <- function(status, stations, dates, tz = APP_TZ) {
  if (length(dates) == 0) return(character(0))
  status_dates <- local_date(status$timestamp, tz)
  ids <- stations$station_id
  present <- vapply(ids, function(id) all(dates %in% status_dates[status$station_id == id]),
                    logical(1))
  ids[present]
}

# One station-minute grid per date (qc.R build_grid). Returns a list named by date.
# A date with no status rows gives a grid where every minute is unknown.
build_day_grids <- function(status, stations, dates, stale_limit = 2,
                            start = "07:00", end = "10:00", tz = APP_TZ) {
  grids <- lapply(dates, function(d) build_grid(status, stations, d, start, end, tz, stale_limit))
  names(grids) <- dates
  grids
}

# One row per date: known/unknown station-minutes of the fixed set, coverage, either-unusable
# share and the inclusion decision (qc.R grid_window_counts + window_summary).
window_table <- function(grids, fixed_ids, dates, min_coverage = 0.95) {
  if (length(dates) == 0) {
    return(window_summary(numeric(0), numeric(0), numeric(0), window = character(0),
                          min_coverage = min_coverage))
  }
  counts <- do.call(rbind, lapply(dates, function(d) grid_window_counts(grids[[d]], fixed_ids, window = d)))
  window_summary(counts$known, counts$unknown, counts$either_min, window = counts$window,
                 min_coverage = min_coverage)
}

# qc.R fixes the early-warning threshold at 2. This recomputes the two warning columns
# for another threshold k (0 < count <= k). Unknown minutes stay NA.
set_warning_threshold <- function(grid, k = 2) {
  grid$warn_bike <- grid$bikes_available > 0 & grid$bikes_available <= k
  grid$warn_dock <- grid$docks_available > 0 & grid$docks_available <= k
  grid
}

# ---------------------------------------------------------------- 4. one day

# The station state at one minute of a day's grid (minute_offset = minutes after the first
# grid minute). `state` is one of STATE_LEVELS; an unknown/stale minute is NEVER "usable".
# Priority: unknown, both, rent, return, early warning, usable.
state_at <- function(grid, minute_offset) {
  if (nrow(grid) == 0) return(grid)
  target <- as.numeric(min(grid$minute)) + 60 * minute_offset
  g <- grid[as.numeric(grid$minute) == target, ]
  g$state <- ifelse(!g$known, "unknown / stale data",
             ifelse(g$rent_unusable & g$return_unusable, "rent- and return-unusable",
             ifelse(g$rent_unusable, "rent-unusable",
             ifelse(g$return_unusable, "return-unusable",
             ifelse(g$warn_bike | g$warn_dock, "early warning", "usable")))))
  rownames(g) <- NULL
  g
}

# Explain why rebalance_plan() left a station out. qc.R only says "missing station data"
# when the state at the chosen minute is unknown; this splits that into what really happened,
# using the validated status rows (rejected rows are not in `status`) and the issues table:
#   - "stale station data": a valid snapshot exists at or before the minute, but it is older
#     than stale_limit (its age is shown);
#   - "missing station data": no valid snapshot at or before the minute;
#   - either one gets "+ N invalid status row(s) rejected" when the loader rejected status
#     rows for that station (see the Data issues table).
# Other reasons (e.g. renting or returning switched off) are passed through unchanged.
# Output: `excluded` with a `detail` column added.
explain_exclusion <- function(excluded, status, at_time, stale_limit, issues = NULL) {
  if (is.null(excluded) || nrow(excluded) == 0) return(excluded)
  detail <- excluded$reason
  rejected <- if (is.null(issues) || nrow(issues) == 0) character(0) else
    issues$id[issues$table == "status" & issues$action == "rejected"]
  for (i in seq_len(nrow(excluded))) {
    if (excluded$reason[i] != "missing station data") next
    id <- excluded$station_id[i]
    ts <- status$timestamp[status$station_id == id & !is.na(status$timestamp)]
    ts <- ts[as.numeric(ts) <= as.numeric(at_time)]
    detail[i] <- if (length(ts) == 0) {
      "missing station data: no valid snapshot at or before this minute"
    } else {
      age <- (as.numeric(at_time) - max(as.numeric(ts))) / 60
      sprintf("stale station data: last valid snapshot is %s min old (stale_limit %s min)",
              format(round(age, 1)), format(stale_limit))
    }
    n_bad <- sum(rejected == id)
    if (n_bad > 0) detail[i] <- sprintf("%s; %d invalid status row(s) rejected (see Data issues)",
                                        detail[i], n_bad)
  }
  excluded$detail <- detail
  excluded
}

# Ranking: worst first by (either-unusable minutes + early-warning minutes); ties by station_id.
# Adds priority_min and rank (1 = worst) to qc.R unusable_summary output.
rank_stations <- function(summary) {
  if (is.null(summary) || nrow(summary) == 0) return(summary)
  summary$priority_min <- summary$either_unusable_min + summary$warn_bike_min + summary$warn_dock_min
  summary <- summary[order(-summary$priority_min, summary$station_id, method = "radix"), ]
  summary$rank <- seq_len(nrow(summary))
  rownames(summary) <- NULL
  summary
}

# Per-station table for display: name, minutes, known minutes, coverage in percent.
station_table <- function(summary, stations) {
  if (is.null(summary) || nrow(summary) == 0) return(data.frame())
  name <- stations$station_name[match(summary$station_id, stations$station_id)]
  data.frame(station_id = summary$station_id, station = name,
             rent_unusable_min = summary$rent_unusable_min,
             return_unusable_min = summary$return_unusable_min,
             either_unusable_min = summary$either_unusable_min,
             warning_min = summary$warn_bike_min + summary$warn_dock_min,
             known_min = summary$known_min, unknown_min = summary$unknown_min,
             coverage_pct = round(100 * summary$coverage, 1),
             stringsAsFactors = FALSE)
}

# Percent, or NA when there are no attempts.
failure_pct <- function(fail, n) if (n > 0) 100 * fail / n else NA_real_

# KPI numbers for one day. counts = one row from qc.R grid_window_counts, att = one row of
# attempts_by_day. Shares are per KNOWN minute; with nothing known the share is NA.
kpi_summary <- function(counts, att) {
  total <- counts$known + counts$unknown
  list(known = counts$known, unknown = counts$unknown,
       coverage = if (total > 0) counts$known / total else NA_real_,
       either_share_pct = if (counts$known > 0) 100 * counts$either_min / counts$known else NA_real_,
       rent_fail = att$rent_fail, rent_n = att$rent_n,
       rent_fail_pct = failure_pct(att$rent_fail, att$rent_n),
       return_fail = att$return_fail, return_n = att$return_n,
       return_fail_pct = failure_pct(att$return_fail, att$return_n))
}

# ---------------------------------------------------------------- 5. charts' inputs

# Either-unusable minutes (and known minutes) per station and clock hour.
hour_station_matrix <- function(grid) {
  empty <- data.frame(station_id = character(0), hour = integer(0),
                      either_unusable_min = numeric(0), known_min = numeric(0),
                      stringsAsFactors = FALSE)
  if (nrow(grid) == 0) return(empty)
  hour <- as.integer(format(grid$minute, "%H"))
  combos <- unique(data.frame(station_id = grid$station_id, hour = hour, stringsAsFactors = FALSE))
  pick <- function(i) grid$station_id == combos$station_id[i] & hour == combos$hour[i]
  combos$either_unusable_min <- vapply(seq_len(nrow(combos)),
    function(i) sum(grid$either_unusable[pick(i)], na.rm = TRUE), numeric(1))
  combos$known_min <- vapply(seq_len(nrow(combos)),
    function(i) sum(grid$known[pick(i)]), numeric(1))
  combos
}

# Pareto order: stations by either-unusable minutes, largest first (ties: station_id),
# with the cumulative share of all either-unusable minutes (NA when the total is 0).
pareto_order <- function(summary) {
  if (is.null(summary) || nrow(summary) == 0) return(data.frame())
  out <- summary[order(-summary$either_unusable_min, summary$station_id, method = "radix"),
                 c("station_id", "either_unusable_min")]
  total <- sum(out$either_unusable_min)
  out$cum_share <- if (total > 0) cumsum(out$either_unusable_min) / total else NA_real_
  rownames(out) <- NULL
  out
}

# ---------------------------------------------------------------- 6. baseline

# How many of n windows form the baseline: the first `share` of them, at least 1, at most n.
baseline_count <- function(n, share = 0.5) {
  if (n <= 0) return(0)
  min(n, max(1, floor(n * share)))
}

# TRUE for the first baseline_count() of the ELIGIBLE entries, FALSE elsewhere.
baseline_flags <- function(eligible, share = 0.5) {
  k <- baseline_count(sum(eligible), share)
  flags <- rep(FALSE, length(eligible))
  flags[which(eligible)[seq_len(k)]] <- TRUE
  flags
}

# ---------------------------------------------------------------- 7. data source

# First existing default scenario file, looked up relative to the app folder; NA if none.
default_scenario_path <- function(app_dir = ".",
                                  candidates = c("../data/baseline.csv",
                                                 "../tests/fixtures/edge_small.csv")) {
  paths <- file.path(app_dir, candidates)
  hit <- paths[file.exists(paths)]
  if (length(hit) == 0) NA_character_ else hit[1]
}
