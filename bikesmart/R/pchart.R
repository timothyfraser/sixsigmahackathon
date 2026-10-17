# ==============================================================================
# pchart.R
# BikeSmart R Package - Statistical Process Control (P-Chart) for Fleet Quality
# ------------------------------------------------------------------------------
# PURPOSE:
# Evaluates whether the daily proportion of bikes requiring maintenance is in
# statistical control or exhibiting out-of-control special-cause spikes.
#
# Follows Montgomery, Introduction to Statistical Quality Control:
#   p_i   = d_i / n_i
#   p_bar = sum(d_i) / sum(n_i)
#   UCL_i = p_bar + 3 * sqrt(p_bar * (1 - p_bar) / n_i)
#   LCL_i = max(0, p_bar - 3 * sqrt(p_bar * (1 - p_bar) / n_i))
#
# Core functions:
#   - pc_parse_time(): Helper to parse ISO-8601 timestamps
#   - p_chart(): Computes P-chart center line, 3-sigma limits, and flags
#   - daily_service_counts(): Extracts daily n (inspected) and d (due) from logs
#   - plot_p_chart(): Draws standard base-R control chart
# ==============================================================================

#' @import dplyr
NULL

# ------------------------------------------------------------------------------
# pc_parse_time
# ------------------------------------------------------------------------------
# Short description: Safely converts date-time strings with UTC offsets into POSIXct.

#' Internal Timestamp Parser for P-Chart Logs
#'
#' @description
#' Helper function that parses ISO-8601 timestamp strings with UTC offsets into POSIXct objects.
#'
#' @param x Vector of character timestamps or POSIXct objects.
#' @return POSIXct vector in UTC.
#' @export
pc_parse_time <- function(x) {
  if (inherits(x, "POSIXct")) {
    return(x)
  }
  out <- as.POSIXct(as.character(x), format = "%Y-%m-%dT%H:%M:%S%z", tz = "UTC")
  if (anyNA(out)) {
    stop("pc_parse_time(): some timestamps could not be parsed; expected e.g. 2026-09-16T00:00:00-0400")
  }
  out
}


# ------------------------------------------------------------------------------
# p_chart
# ------------------------------------------------------------------------------
# Short description: Computes p-bar, sample proportions, sample-size-dependent
# 3-sigma control limits (UCL/LCL), and out-of-control indicators for subgroups.

#' Statistical Process Control P-Chart
#'
#' @description
#' Calculates binomial attribute control chart statistics (proportions, center line,
#' upper/lower control limits, and out-of-control flags) following standard SQC formulas.
#'
#' @param d Integer vector of defect counts in each subgroup (e.g. bikes due on day i).
#' @param n Integer vector of subgroup sample sizes (e.g. active bikes on day i).
#' @param label Optional character/Date vector naming each subgroup (default: indices).
#' @return Data frame with columns `label`, `n`, `d`, `p`, `p_bar`, `lcl`, `ucl`, and `out_of_control`.
#' @export
#' @examples
#' p_chart(d = c(5, 10, 15), n = c(100, 100, 100), label = c("Day 1", "Day 2", "Day 3"))
p_chart <- function(d, n, label = seq_along(d)) {
  if (length(d) == 0) {
    stop("p_chart(): need at least one subgroup")
  }
  if (length(d) != length(n) || length(label) != length(d)) {
    stop("p_chart(): d, n and label must be the same length")
  }
  if (anyNA(d) || anyNA(n)) {
    stop("p_chart(): d and n must not contain NA")
  }
  if (any(n <= 0)) {
    stop("p_chart(): every subgroup size n must be positive")
  }
  if (any(d < 0) || any(d > n)) {
    stop("p_chart(): need 0 <= d <= n in every subgroup")
  }

  p_bar <- sum(d) / sum(n)
  se <- sqrt(p_bar * (1 - p_bar) / n)
  p <- d / n
  ucl <- pmin(1, p_bar + 3 * se)
  lcl <- pmax(0, p_bar - 3 * se)

  data.frame(
    label = label,
    n = n,
    d = d,
    p = p,
    p_bar = p_bar,
    lcl = lcl,
    ucl = ucl,
    out_of_control = (p > ucl | p < lcl),
    stringsAsFactors = FALSE
  )
}


# ------------------------------------------------------------------------------
# daily_service_counts
# ------------------------------------------------------------------------------
# Short description: Analyzes raw bike logs to track accumulated ride hours per bike
# and aggregates daily counts of observed bikes (n) and bikes crossing service thresholds (d).

#' Extract Daily Service and Subgroup Counts from Bike Logs
#'
#' @description
#' Evaluates continuous usage from 5-minute snapshot logs, tracking cumulative ride hours
#' (snapshots where `DOCID == "0"`). Whenever a bike crosses an integer multiple of
#' `service_interval_h`, it is flagged as due for service on that day.
#'
#' @param data Data frame with columns `BIKEID`, `DOCID`, and `time`.
#' @param service_interval_h Positive numeric service limit in ride hours (required).
#' @param tz Timezone used to determine daily calendar boundaries (default: "America/New_York").
#' @param interval_min Snapshot spacing in minutes (default: 5).
#' @param start_hours Optional data frame (`BIKEID`, `start_hours`) of initial usage offsets.
#' @return Data frame with columns `day`, `n` (observed bikes), and `d` (bikes due).
#' @export
daily_service_counts <- function(
    data,
    service_interval_h,
    tz = "America/New_York",
    interval_min = 5,
    start_hours = NULL
) {
  if (missing(service_interval_h) || !is.numeric(service_interval_h) ||
      length(service_interval_h) != 1 || is.na(service_interval_h) || service_interval_h <= 0) {
    stop("service_interval_h is required: a positive number of ride hours between services")
  }
  if (nrow(data) == 0) {
    return(data.frame(day = as.Date(character()), n = integer(), d = integer()))
  }

  limit_min <- service_interval_h * 60
  data <- data %>% mutate(BIKEID = as.character(BIKEID), offset_min = 0)

  if (!is.null(start_hours)) {
    if (!all(c("BIKEID", "start_hours") %in% names(start_hours))) {
      stop("start_hours needs columns BIKEID and start_hours")
    }
    if (anyNA(start_hours$start_hours) || any(start_hours$start_hours < 0)) {
      stop("start_hours must be zero or more, with no NA")
    }
    sh <- data.frame(
      BIKEID = as.character(start_hours$BIKEID),
      sh = start_hours$start_hours,
      stringsAsFactors = FALSE
    )
    data <- data %>%
      left_join(sh, by = "BIKEID") %>%
      mutate(offset_min = coalesce(sh, 0) * 60) %>%
      select(-sh)
  }

  data %>%
    mutate(time = pc_parse_time(time), DOCID = as.character(DOCID)) %>%
    arrange(BIKEID, time) %>%
    group_by(BIKEID) %>%
    mutate(
      ride_min = offset_min + cumsum(DOCID == "0") * interval_min,
      cycles   = floor(ride_min / limit_min + 1e-9),
      event    = cycles > lag(cycles, default = floor(first(offset_min) / limit_min + 1e-9))
    ) %>%
    ungroup() %>%
    mutate(day = as.Date(time, tz = tz)) %>%
    group_by(day, BIKEID) %>%
    summarise(due = any(event), .groups = "drop") %>%
    group_by(day) %>%
    summarise(n = n(), d = sum(due), .groups = "drop") %>%
    arrange(day)
}


# ------------------------------------------------------------------------------
# plot_p_chart
# ------------------------------------------------------------------------------
# Short description: Generates a publication-ready control chart plot using base R,
# rendering center line (p-bar), stepped 3-sigma control limits, and red alarm points.

#' Plot a Statistical Quality Control P-Chart
#'
#' @description
#' Draws a P-chart display showing subgroup proportions, center line, stepped limits
#' (to accommodate sample size differences), and highlighted out-of-control points.
#'
#' @param chart Data frame output produced by [p_chart()].
#' @param main Title for the chart.
#' @return Invisibly returns the input `chart` data frame.
#' @export
plot_p_chart <- function(
    chart,
    main = "P chart: share of bikes needing maintenance per day"
) {
  x <- seq_len(nrow(chart))
  yr <- range(c(0, chart$p, chart$ucl, chart$lcl), na.rm = TRUE)

  graphics::plot(
    x, chart$p,
    type = "b",
    pch = 19,
    ylim = yr,
    xaxt = "n",
    xlab = "Day",
    ylab = "Proportion of bikes needing maintenance",
    main = main,
    col = ifelse(chart$out_of_control, "red", "black")
  )
  graphics::axis(1, at = x, labels = as.character(chart$label), las = 2, cex.axis = 0.7)
  graphics::abline(h = chart$p_bar[1], col = "blue")
  graphics::lines(x, chart$ucl, type = "s", lty = 2, col = "darkgray")
  graphics::lines(x, chart$lcl, type = "s", lty = 2, col = "darkgray")
  graphics::legend(
    "topright",
    legend = c("Daily share", "Out of control", "Center (p-bar)", "3-sigma limits"),
    col = c("black", "red", "blue", "darkgray"),
    pch = c(19, 19, NA, NA),
    lty = c(NA, NA, 1, 2),
    bty = "n",
    cex = 0.8
  )
  invisible(chart)
}

