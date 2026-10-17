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
#   4. one day                state_at, explain_exclusion, station_popup, rank_stations, station_table,
#                             kpi_summary
#   5. charts' inputs         hour_station_matrix, pareto_order
#   6. baseline               baseline_count, baseline_flags
#   7. data source            builtin_scenarios, default_scenario_path
#   8. data health            table_health, table_block_message, issue_summary, issue_detail,
#                             signal_label, format_p, as_whole_numbers
#   8b. tier 2 tables         onset_window_table, c_chart_table, xbar_r_table, capability_table
#   9. simulation display    SIM_METRIC_LABELS, paired_table_display, policy_summary_display
#  10. Kaplan-Meier display  km_days, km_counts_table, km_horizon_table, km_mean_table,
#                            km_excluded_table, km_plot_data (needs app/survival.R sourced)
#  11. Now forecast display  forecast_p_text, forecast_table_display, forecast_boot_display, forecast_transit_display,
#                            forecast_rate_display, forecast_plot_data (numbers from app/forecast.R)

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

# Map popup HTML for each station. Names and IDs come from the uploaded file, so they are
# HTML-escaped. A count that is NA (unknown/stale minute) is shown as "unknown", never "NA".
station_popup <- function(name, id, state, bikes, docks) {
  count_text <- function(x) ifelse(is.na(x), "unknown", as.character(x))
  paste0("<b>", htmltools::htmlEscape(name), "</b> (", htmltools::htmlEscape(id), ")<br>state: ", state,
         "<br>bikes: ", count_text(bikes), ", docks: ", count_text(docks))
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

# The formal scenario files the app can offer without an upload (task H-02's data/).
# For each scenario the first existing file wins: the gzip copy shipped inside the app bundle
# (app/data/<name>.csv.gz, written by make_app_data.R, used on Posit Connect), then the repo
# file (../data/<name>.csv, when running from a clone). Output: named character vector of
# paths, in the order baseline, planted_shift, edge_case; scenarios with no file are left out.
builtin_scenarios <- function(app_dir = ".", names = c("baseline", "planted_shift", "edge_case")) {
  found <- vapply(names, function(s) {
    paths <- file.path(app_dir, c(file.path("data", paste0(s, ".csv.gz")),
                                  file.path("..", "data", paste0(s, ".csv"))))
    hit <- paths[file.exists(paths)]
    if (length(hit) == 0) NA_character_ else hit[1]
  }, character(1))
  found[!is.na(found)]
}

# First existing default scenario file, looked up relative to the app folder; NA if none.
default_scenario_path <- function(app_dir = ".",
                                  candidates = c("../data/baseline.csv",
                                                 "../tests/fixtures/edge_small.csv")) {
  paths <- file.path(app_dir, candidates)
  hit <- paths[file.exists(paths)]
  if (length(hit) == 0) NA_character_ else hit[1]
}

# ---------------------------------------------------------------- 8. data health

# Per record type: how many rows the file had and what the loader did with them.
#   valid     rows kept after validation
#   rejected  rows the loader rejected (issues action "rejected")
#   kept_once identical duplicates dropped as copies (issues action "kept once")
#   in_file   valid + rejected + kept_once
#   state     "no records"   the file has no rows of this type (nothing was rejected)
#             "all rejected" the file has rows of this type but none is valid
#             "some rejected" / "ok"
# Input: the load_scenario() result. Output: one row per record type.
table_health <- function(sc, tables = c("stations", "status", "attempts", "tasks")) {
  iss <- sc$issues
  rows <- lapply(tables, function(t) {
    valid <- if (is.null(sc[[t]])) 0L else nrow(sc[[t]])
    rejected <- sum(iss$table == t & iss$action == "rejected")
    kept_once <- sum(iss$table == t & iss$action == "kept once")
    in_file <- valid + rejected + kept_once
    state <- if (in_file == 0) "no records" else if (valid == 0) "all rejected" else
      if (rejected > 0) "some rejected" else "ok"
    data.frame(table = t, in_file = in_file, valid = valid, rejected = rejected,
               kept_once = kept_once, state = state, stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

# A plain message when a record type cannot be used, or NULL when it can.
# `needed_for` names the features that pause. The most common rejection rule is quoted.
table_block_message <- function(health, iss, table, needed_for) {
  h <- health[health$table == table, ]
  if (nrow(h) == 0 || h$valid > 0) return(NULL)
  if (h$state == "no records") {
    return(sprintf("The file has no %s records, so %s cannot be shown.", table, needed_for))
  }
  rules <- sort(table(iss$rule[iss$table == table & iss$action == "rejected"]), decreasing = TRUE)
  sprintf("All %d %s rows in the file were rejected (most common reason: %s, %d rows), so %s %s paused. See Data issues.",
          h$in_file, table, names(rules)[1], as.integer(rules[1]), needed_for,
          if (grepl(" and |, ", needed_for)) "are" else "is")
}

# Issues counted by record type, rule and action, largest first.
issue_summary <- function(iss) {
  if (nrow(iss) == 0) {
    return(data.frame(table = character(0), rule = character(0), action = character(0),
                      rows = integer(0), stringsAsFactors = FALSE))
  }
  key <- paste(iss$table, iss$rule, iss$action, sep = "\r")
  n <- table(key)
  parts <- strsplit(names(n), "\r", fixed = TRUE)
  out <- data.frame(table = vapply(parts, `[`, "", 1), rule = vapply(parts, `[`, "", 2),
                    action = vapply(parts, `[`, "", 3), rows = as.integer(n),
                    stringsAsFactors = FALSE)
  out <- out[order(-out$rows, out$table, out$rule), ]
  rownames(out) <- NULL
  out
}

# The first max_rows issue rows (the full list can be hundreds of thousands of rows).
issue_detail <- function(iss, max_rows = 200) {
  utils::head(iss, max_rows)
}

# Signal wording for p chart points. When qc.R's dispersion check warns, the binomial limits
# are likely too narrow, so a point beyond them is a prompt to investigate, not a confirmed
# special cause, and a point inside them is only "within limits".
# ooc: TRUE / FALSE / NA (not assessed); overdispersed: the dispersion warning (TRUE/FALSE/NA).
signal_label <- function(ooc, overdispersed, model = "binomial") {
  warn <- isTRUE(overdispersed)
  ifelse(is.na(ooc), "not assessed",
         ifelse(ooc, if (warn) paste0("beyond ", model, " limit (investigate; not a confirmed special cause)") else "OUT OF CONTROL",
                if (warn) "within limits" else "in control"))
}

# A p-value as text: 3 significant digits, or "< 0.0001".
format_p <- function(p) {
  if (is.na(p)) return("n/a")
  if (p < 1e-4) "< 0.0001" else format(signif(p, 3), scientific = FALSE)
}

# Columns that hold whole-number counts -> integer, so tables print "2", not "2.00".
as_whole_numbers <- function(df, cols) {
  for (col in intersect(cols, names(df))) df[[col]] <- as.integer(round(df[[col]]))
  df
}

# ---------------------------------------------------------------- 8b. tier 2 inputs and tables (H-11)
# Counting rows and shaping tables only; the statistics are in qc.R.

# Anomaly onsets per date on the fixed station set (qc.R count_onsets). Output: window, onsets.
onset_window_table <- function(grids, fixed_ids, dates) {
  onsets <- vapply(dates, function(d) count_onsets(grids[[d]], fixed_ids), numeric(1))
  data.frame(window = dates, onsets = unname(onsets), stringsAsFactors = FALSE)
}

# c chart table: one row per included window.
# w = included rows of window_table (window, known, coverage), counts = onsets in the same
# order, res = qc.R c_chart result.
c_chart_table <- function(w, res) {
  d <- res$data
  data.frame(window = w$window, onsets = as.integer(d$count), known_min = w$known,
             coverage_pct = round(100 * w$coverage, 1), centre = round(d$center, 3),
             UCL = round(d$ucl, 3), LCL = round(d$lcl, 3),
             signal = signal_label(d$out_of_control, res$dispersion$warning, model = "Poisson"),
             stringsAsFactors = FALSE)
}

# X-bar/R table: the 3 response times, mean, range, limits and the signal of each subgroup.
# sub = qc.R response_subgroups result, res = qc.R xbar_r_chart result.
xbar_r_table <- function(sub, res) {
  d <- res$data
  v <- sub$values
  data.frame(window = sub$windows, time_1_min = v[, 1], time_2_min = v[, 2], time_3_min = v[, 3],
             mean_min = round(d$xbar, 3), range_min = round(d$range, 3),
             xbar_LCL = round(d$x_lcl, 3), xbar_UCL = round(d$x_ucl, 3),
             R_LCL = round(d$r_lcl, 3), R_UCL = round(d$r_ucl, 3),
             signal = ifelse(is.na(d$out_of_control), "not assessed",
                             ifelse(d$out_of_control, "OUT OF CONTROL", "in control")),
             stringsAsFactors = FALSE)
}

# Capability result (qc.R capability_indices) -> one row per index, with the reason when NA.
capability_table <- function(cap) {
  num <- function(x) if (is.na(x)) NA_real_ else round(x, 3)
  data.frame(
    index = c("Cpu", "Cpl", "Cp", "Cpk"),
    value = c(num(cap$cpu), num(cap$cpl), num(cap$cp), num(cap$cpk)),
    reason_if_not_computed = c(cap$cpu_note, cap$cpl_note, cap$cp_note, cap$cpk_note),
    stringsAsFactors = FALSE)
}

# ---------------------------------------------------------------- 9. simulation display
# Wording and rounding only; every number comes from app/sim.R.

SIM_METRIC_LABELS <- c(
  either_min = "Either-unusable station-minutes (PRIMARY)",
  fail_prop = "Failed attempts, percentage points of all attempts",
  van_km = "Van distance, km (estimated, not a road route)",
  recovery_min = "Recovery time, minutes from failure onset to usable")

# Paired-difference table (sim.R paired_tables) -> readable table. d = metric(first policy) - metric(second
# policy) of the `pair` column, so a positive difference means the SECOND policy is better.
# The failed share is shown in percentage points (x 100). Numbers are printed as text with 4
# significant digits, so a small difference (e.g. 0.01318 pp) is not rounded to "0.00".
paired_table_display <- function(tbl) {
  scale <- ifelse(tbl$metric == "fail_prop", 100, 1)
  num <- function(x) ifelse(is.na(x), NA_character_,
                            formatC(signif(x * scale, 4), format = "fg", digits = 4))
  out <- data.frame(
    metric = unname(SIM_METRIC_LABELS[tbl$metric]), role = tbl$role,
    seeds_used = as.integer(tbl$n), mean_difference = num(tbl$mean_d),
    CI_low = num(tbl$ci_low), CI_high = num(tbl$ci_high),
    CI_level = paste0(format(round(tbl$ci_level_pct, 3), nsmall = 0), "%"),
    label = tbl$label, note = tbl$note, stringsAsFactors = FALSE)
  if ("pair" %in% names(tbl)) out <- cbind(data.frame(pair = tbl$pair, stringsAsFactors = FALSE), out)
  out
}

# Per-policy means (sim.R compare_policies$summary) -> readable table; the failed share is in percent.
policy_summary_display <- function(s) {
  data.frame(
    policy = ifelse(s$policy == "none", "none (no rebalancing)", s$policy),
    seeds = as.integer(s$seeds),
    # 2 decimals, like the paired table, so the two means visibly differ by the mean difference
    mean_either_unusable_min = round(s$either_min, 2),
    mean_failed_attempts_pct = round(100 * s$fail_prop, 2),
    mean_van_km = round(s$van_km, 2),
    mean_van_tasks = round(s$tasks, 2),
    mean_recovery_min = round(s$recovery_min, 2),
    seeds_with_a_recovery = as.integer(s$recovery_seeds),
    stringsAsFactors = FALSE)
}

# ---------------------------------------------------------------- 10. Kaplan-Meier display
# Wording, rounding and picking days only; every number comes from app/survival.R.

KM_FAILURE_LABELS <- c(either = "either-unusable (rent or return)", rent = "rent-unusable", `return` = "return-unusable")

# Which weekdays the History panel uses: "all" weekdays, or those up to and including `chosen`.
km_days <- function(dates, scope = "all", chosen = NULL) {
  if (identical(scope, "upto") && !is.null(chosen) && nzchar(chosen)) dates[dates <= chosen] else dates
}

# "0.123 [0.100, 0.150]" or "0.123 (interval n/a)"; NA estimate -> "n/a".
km_interval_text <- function(est, lo, hi, digits = 3) {
  f <- function(x) formatC(x, format = "f", digits = digits)
  ifelse(is.na(est), "n/a",
         ifelse(is.na(lo) | is.na(hi), paste0(f(est), " (95% interval n/a)"),
                paste0(f(est), "  [", f(lo), ", ", f(hi), "]")))
}

# Counts table: what went into the estimate (station-days, events, censored, excluded at 07:00).
km_counts_table <- function(h) {
  c <- h$counts
  data.frame(
    item = c("weekdays used", "station-days usable at 07:00 (n)", "failures (events)",
             "censored at 10:00 (never unusable)", "censored at an unknown gap (start of the gap)",
             "left out: 07:00 unknown or stale", "left out: already unusable at 07:00"),
    count = as.integer(c(c$days, c$n, c$events, c$cens_end, c$cens_gap, c$excl_unknown, c$excl_unusable)),
    stringsAsFactors = FALSE)
}

# F(10/20/30) with 95% Greenwood (log-log) intervals; the reason when there is none.
km_horizon_table <- function(s) {
  h <- s$horizons
  data.frame(
    `minutes after a usable 07:00` = as.integer(h$t),
    `F(t) = share failed by t  [95% CI]` = km_interval_text(h$F, h$F_low, h$F_high),
    `S(t) = still unfailed` = ifelse(is.na(h$surv), "n/a", formatC(h$surv, format = "f", digits = 3)),
    reason_if_missing = h$note,
    check.names = FALSE, stringsAsFactors = FALSE)
}

# RMST and MTTF, each with its reason when it is not reported.
km_mean_table <- function(s) {
  num <- function(x) if (is.na(x)) "n/a" else paste(formatC(x, format = "f", digits = 2), "min")
  data.frame(
    measure = c(paste0("RMST to ", s$rmst_tau, " min (restricted mean time to first failure)"),
                "MTTF (mean time to first failure, full area under the curve)"),
    value = c(num(s$rmst), num(s$mttf)),
    reason_if_not_reported = c(s$rmst_note, s$mttf_note),
    stringsAsFactors = FALSE)
}

# Station-days left out at 07:00, by reason (one row per reason; none -> a note row).
km_excluded_table <- function(h) {
  c <- h$counts
  data.frame(reason = c("unknown or stale at 07:00", "unusable at 07:00 (already empty, full or switched off)"),
             station_days = c(c$excl_unknown, c$excl_unusable), stringsAsFactors = FALSE)
}

# Curve data for plot_km(): S and its interval on every minute 0..tau (a step on [m, m+1)),
# plus one censoring tick per distinct censored time. Times are whole minutes.
km_plot_data <- function(h, xmax = SURVIVAL_TAU) {
  s <- h$summary
  grid_t <- 0:xmax
  at <- km_at(s$fit, grid_t)
  curve <- data.frame(t = grid_t, surv = at$surv, lo = at$ci_low, hi = at$ci_high)
  cens <- h$obs[h$obs$event == 0 & h$obs$time <= xmax, ]
  ticks <- if (nrow(cens) == 0) data.frame(t = numeric(0), surv = numeric(0)) else {
    tt <- sort(unique(cens$time))
    data.frame(t = tt, surv = km_at(s$fit, tt)$surv)
  }
  list(curve = curve, ticks = ticks[!is.na(ticks$surv), ])
}

# ---------------------------------------------------------------- 11. Now forecast display (H-13)
# Wording and rounding only; every number comes from app/forecast.R.

# "0.264 (SE 0.003)"; an NA probability -> "n/a".
forecast_p_text <- function(p, se) {
  ifelse(is.na(p), "n/a", paste0(formatC(p, format = "f", digits = 3), " (SE ", formatC(se, format = "f", digits = 3), ")"))
}

# One row per station, sorted as forecast_now() sorted it (highest 30-minute risk first).
# Columns: station, bikes / docks at t0, snapshot age, P(rent-unusable) and P(return-unusable) for
# each horizon with the simulation SE, and the flags or the reason there is no forecast.
forecast_table_display <- function(f) {
  tb <- f$table
  out <- data.frame(station = tb$station_id,
                    `bikes / docks at t0` = ifelse(tb$known, paste(tb$bikes, "/", tb$docks), "unknown"),
                    `snapshot age (min)` = ifelse(tb$known, formatC(tb$age, format = "f", digits = 1), "n/a"),
                    check.names = FALSE, stringsAsFactors = FALSE)
  for (type in c("rent", "return")) {
    for (h in f$horizons) {
      label <- paste0("P(", type, "-unusable) within ", h, " min", if (isTRUE(f$past_10[[as.character(h)]])) " *" else "")
      out[[label]] <- forecast_p_text(tb[[paste0("p_", type, "_", h)]], tb[[paste0("se_", type, "_", h)]])
    }
  }
  if (isTRUE(f$bootstrap$ok)) {            # step 5b: the 30-minute parameter range (details table has 10/20/30)
    h <- max(f$horizons)
    for (type in c("rent", "return")) {
      label <- paste0("(iii) parameter uncertainty, ", type, "-unusable within ", h, " min (day bootstrap, B = ",
                      f$bootstrap$B, " sets): 2.5-97.5%")
      out[[label]] <- forecast_range_text(tb[[paste0("boot_lo_", type, "_", h)]], tb[[paste0("boot_hi_", type, "_", h)]])
    }
  }
  out$`flags / reason` <- ifelse(tb$reason != "", tb$reason, tb$flags)
  out
}

# "0.985 to 1.000"; an NA range -> "n/a".
forecast_range_text <- function(lo, hi) {
  ifelse(is.na(lo) | is.na(hi), "n/a", paste(formatC(lo, format = "f", digits = 3), "to", formatC(hi, format = "f", digits = 3)))
}

# Details of the day bootstrap for every horizon: the 2.5-97.5% range (iii) next to the 5a point
# estimate and its simulation SE (ii), and the mean simulation SE inside the bootstrap sets (so a reader
# sees how much of the range is simulation noise). NULL-safe: a message table when there is no range.
forecast_boot_display <- function(f) {
  b <- f$bootstrap
  if (is.null(b)) return(data.frame(note = "Not computed: tick the day bootstrap and run the forecast again."))
  if (!isTRUE(b$ok)) return(data.frame(note = paste0("Not available: ", b$reason, ".")))
  tb <- f$table
  tb <- tb[!is.na(tb$p_rent_10), ]
  out <- data.frame(station = tb$station_id, stringsAsFactors = FALSE)
  for (type in c("rent", "return")) {
    for (h in f$horizons) {
      out[[paste0(type, " ", h, " min: 5a estimate (ii) SE")]] <-
        forecast_p_text(tb[[paste0("p_", type, "_", h)]], tb[[paste0("se_", type, "_", h)]])
      out[[paste0(type, " ", h, " min: (iii) 2.5-97.5%")]] <-
        forecast_range_text(tb[[paste0("boot_lo_", type, "_", h)]], tb[[paste0("boot_hi_", type, "_", h)]])
      out[[paste0(type, " ", h, " min: mean SE inside sets")]] <-
        formatC(tb[[paste0("boot_mean_se_", type, "_", h)]], format = "f", digits = 3)
    }
  }
  out
}

# The in-transit van tasks, for display.
forecast_transit_display <- function(f) {
  it <- f$in_transit
  if (nrow(it) == 0) return(data.frame(note = "No van task is in transit at t0 (assigned by t0 and not yet completed)."))
  data.frame(task = it$task_id, from = it$source, to = it$destination, bikes = it$planned,
             `assigned at` = format(it$assigned_at, "%H:%M", tz = APP_TZ),
             `estimated arrival (min after t0)` = round(it$eta_min, 1),
             counted = ifelse(it$known_destination, "yes", "no: destination not forecast"),
             check.names = FALSE, stringsAsFactors = FALSE)
}

# The mean bin rates (attempts per station-minute, 12 bins) of the stations used, for display.
forecast_rate_display <- function(f) {
  if (is.null(f$rates)) return(data.frame(note = "No rates: nothing could be estimated."))
  r <- f$rates
  bins <- sprintf("%02d:%02d", 7 + ((seq_len(dim(r)[3]) - 1) * 15) %/% 60, ((seq_len(dim(r)[3]) - 1) * 15) %% 60)
  data.frame(`15-min bin starts` = bins,
             `rent, network mean (per station-min)` = round(apply(r[, "rent", , drop = FALSE], 3, mean), 4),
             `return, network mean (per station-min)` = round(apply(r[, "return", , drop = FALSE], 3, mean), 4),
             check.names = FALSE, stringsAsFactors = FALSE)
}

# Top stations by the larger of their 30-minute rent and return risk: long table for the plot.
forecast_plot_data <- function(f, top = 10) {
  h <- max(f$horizons)
  tb <- f$table[!is.na(f$table[[paste0("p_rent_", h)]]), ]
  if (nrow(tb) == 0) return(NULL)
  worst <- pmax(tb[[paste0("p_rent_", h)]], tb[[paste0("p_return_", h)]])
  tb <- head(tb[order(-worst, tb$station_id, method = "radix"), ], top)
  col <- function(name) if (name %in% names(tb)) tb[[name]] else rep(NA_real_, nrow(tb))   # NA without the bootstrap
  rbind(data.frame(station = tb$station_id, type = "rent-unusable", p = tb[[paste0("p_rent_", h)]], se = tb[[paste0("se_rent_", h)]],
                   lo = col(paste0("boot_lo_rent_", h)), hi = col(paste0("boot_hi_rent_", h))),
        data.frame(station = tb$station_id, type = "return-unusable", p = tb[[paste0("p_return_", h)]], se = tb[[paste0("se_return_", h)]],
                   lo = col(paste0("boot_lo_return_", h)), hi = col(paste0("boot_hi_return_", h))))
}

# ---------------------------------------------------------------- 12. Availability and reliability display (H-16)
# Wording, rounding and choosing stations only; every number comes from app/reliability.R.

# Station ids of one region (stations table column `region`), in the order of the table.
region_station_ids <- function(stations, region) stations$station_id[stations$region %in% region]

# Default k for k-out-of-n: half of the stations, rounded up (a demo choice).
default_k <- function(n) max(1L, as.integer(ceiling(n / 2)))

# "0.400 (2/5)" or "n/a"
reliability_share_text <- function(value, hold, n) {
  ifelse(is.na(value), "n/a", paste0(formatC(value, format = "f", digits = 3), " (", hold, "/", n, ")"))
}

# One row per structure. `results` is a named list of reliability_summary() outputs (names = the
# structure descriptions shown to the user); `rules` the condition in words, same names.
reliability_display <- function(results, rules) {
  one <- function(name) {
    r <- results[[name]]
    data.frame(
      structure = name,
      condition = rules[[name]],
      `eligible minutes` = as.integer(r$avail_n),
      availability = reliability_share_text(r$availability, r$avail_hold, r$avail_n),
      `independence formula (contrast only)` = ifelse(is.na(r$independence), "n/a", formatC(r$independence, format = "f", digits = 3)),
      tau = paste(r$tau, "min"),
      `reliability R(tau)` = reliability_share_text(r$reliability, r$rel_hold, r$rel_n),
      `eligible start minutes` = as.integer(r$rel_n),
      `reason if n/a` = unique(c(r$avail_reason, r$rel_reason)[nzchar(c(r$avail_reason, r$rel_reason))]) |>
        paste(collapse = "; "),
      check.names = FALSE, stringsAsFactors = FALSE)
  }
  do.call(rbind, lapply(names(results), one))
}

# ---------------------------------------------------------------- 13. Diagnosis display (H-17)
# Scope and wording only; every number comes from app/faulttree.R.

# Attempts that fall inside the 07:00-10:00 window of the given dates (one date or all weekdays).
scope_attempts <- function(attempts, dates, start = "07:00", end = "10:00", tz = APP_TZ) {
  if (length(dates) == 0) return(attempts[0, ])
  secs <- as.numeric(attempts$timestamp)
  keep <- rep(FALSE, length(secs))
  for (d in dates) {
    b <- window_bounds(d, start, end, tz)
    keep <- keep | (!is.na(secs) & secs >= as.numeric(b$start) & secs < as.numeric(b$end))
  }
  attempts[keep, ]
}

# Stack the day grids of the chosen dates into one grid (station + minute is unique across days).
pooled_grid <- function(grids, dates) {
  if (length(dates) == 0) return(NULL)
  do.call(rbind, unname(grids[dates]))
}

# "60.0% (6)" or "n/a" (a share that is not defined).
share_count_text <- function(share, count) {
  ifelse(is.na(share), paste0("n/a (", count, ")"), paste0(sprintf("%.1f", 100 * share), "% (", count, ")"))
}

# Action table: counts and shares of failed attempts after the contradiction rule, with the logged view.
fault_action_display <- function(ft) {
  data.frame(action = ft$by_action$action,
             `as logged (before the status rule)` = share_count_text(ft$logged_by_action$share, ft$logged_by_action$count),
             `after the status rule` = share_count_text(ft$by_action$share, ft$by_action$count),
             check.names = FALSE, stringsAsFactors = FALSE)
}

# Logged reasons with their action.
fault_reason_display <- function(ft) {
  data.frame(`logged reason` = ft$by_reason$reason, `points to` = ft$by_reason$action,
             `failed attempts (share)` = share_count_text(ft$by_reason$share, ft$by_reason$count),
             check.names = FALSE, stringsAsFactors = FALSE)
}

# One line per failure type: n, failed, failed share, the rule counts.
fault_summary_text <- function(ft) {
  label <- if (ft$type == "rent") "Rent" else "Return"
  share <- if (is.na(ft$failed_share)) paste0("n/a (", ft$failed_share_reason, ")")
           else paste0(sprintf("%.1f", 100 * ft$failed_share), "%")
  rule <- if (!ft$rule_applied) "status/attempt rule not applied (no usable status records)."
          else paste0(ft$reclassified, " reclassified as data check (status contradicts the log); ",
                      ft$not_checked, " could not be checked (unknown minute); ", ft$checked, " checked.")
  paste0(label, " failures: ", ft$n_failed, " of ", ft$n, " attempts failed (", share, "). ", rule,
         if (nzchar(ft$shares_reason)) paste0(" Shares: ", ft$shares_reason, ".") else "")
}

# Per-station table text: counts per action and the top cause.
fault_station_display <- function(st, top = 10) {
  if (nrow(st) == 0) return(data.frame(note = "No failed attempts in this scope."))
  st <- utils::head(st, top)
  st <- as_whole_numbers(st, c("n_failed", "rebalancing", "maintenance", "data check", "data_check"))
  names(st)[names(st) == "n_failed"] <- "failed attempts"
  names(st)[names(st) == "top_cause"] <- "top cause"
  st
}

# ---- Simulated task table (H-18): formatting only; the rules are in tasks.R
# The task table for the page: times as New York clock text (HH:MM), empty cells as "".
tasks_display <- function(tasks, tz = APP_TZ) {
  if (is.null(tasks) || nrow(tasks) == 0) return(data.frame(note = "No simulated tasks yet."))
  clock <- function(x) ifelse(is.na(x), "", format(x, "%H:%M", tz = tz))
  text <- function(x) ifelse(is.na(x), "", as.character(x))
  data.frame(task_id = tasks$task_id, status = tasks$status, from = tasks$source_station_id,
             to = tasks$destination_station_id, planned_bikes = tasks$planned_quantity,
             actual_bikes = text(tasks$actual_quantity), van_id = text(tasks$van_id),
             assigned = clock(tasks$assigned_at), arrived = clock(tasks$arrived_at),
             completed = clock(tasks$completed_at), stringsAsFactors = FALSE)
}

# The time for a move: the chosen date + observation minute (minutes after 07:00), New York clock.
task_time_default <- function(date, minute, tz = APP_TZ) {
  format(as.POSIXct(paste(date, "07:00:00"), tz = tz) + 60 * minute, "%H:%M", tz = tz)
}

# Read "HH:MM" on a date as a POSIXct (New York); NA when the text is not a valid time.
task_time_parse <- function(date, text, tz = APP_TZ) {
  text <- trimws(as.character(text))
  if (length(text) != 1 || is.na(text) || !grepl("^([01][0-9]|2[0-3]):[0-5][0-9]$", text)) {
    return(as.POSIXct(NA, tz = tz))
  }
  as.POSIXct(paste0(date, " ", text, ":00"), tz = tz)
}
