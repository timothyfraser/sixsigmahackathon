# ==============================================================================
# dock_projection.R
# BikeSmart R Package - Dock Inventory Projection & Recommendation
# ------------------------------------------------------------------------------
# PURPOSE:
# Predicts arrival-time dock availability and provides distance-ranked station
# recommendations with rebalancing return incentives.
#
# Core functions:
#   - parse_city_time(): Safe timezone-aware timestamp parser
#   - compute_dock_rates(): Historical net docking rates by 5-min weekday slots
#   - predict_dock(): Arrival-time bike & space count projection
#   - return_discount(): Incentive discount based on projected station occupancy
#   - optimize_docks(): Distance-ranked dock optimizer for pickup and return
# ==============================================================================

#' @import dplyr
NULL

# ------------------------------------------------------------------------------
# parse_city_time
# ------------------------------------------------------------------------------
# Short description: Parses strings or timestamps safely into POSIXct for a
# specified city timezone, correctly interpreting ISO-8601 UTC offsets or local time.

#' Parse Timestamps into City Timezone
#'
#' @description
#' Converts timestamp inputs into a POSIXct instant. Preserves existing POSIXct
#' objects, parses ISO-8601 strings with explicit UTC offsets, and defaults
#' timezone-free strings to local city time.
#'
#' @param x Vector of character strings or POSIXt objects.
#' @param tz Character string naming the target IANA timezone (e.g. "America/Chicago").
#' @return A POSIXct vector formatted in the target timezone.
#' @export
parse_city_time <- function(x, tz) {
  if (inherits(x, "POSIXt")) {
    return(as.POSIXct(x))
  }

  x <- as.character(x)

  # Supports exported CSV timestamps with explicit UTC offsets
  if (all(grepl("T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{4}$", x))) {
    return(as.POSIXct(x, format = "%Y-%m-%dT%H:%M:%S%z", tz = tz))
  }

  # Timezone-free strings are interpreted as local city time
  as.POSIXct(x, format = "%Y-%m-%d %H:%M:%S", tz = tz)
}


# ------------------------------------------------------------------------------
# compute_dock_rates
# ------------------------------------------------------------------------------
# Short description: Aggregates historical bike snapshot data to calculate
# the average net docking rate (bikes/min) for every station and weekly time slot.

#' Compute Historical Net Docking Rates
#'
#' @description
#' Aggregates 5-minute snapshot logs across a multi-week historical observation
#' window to determine the typical arrival and departure rates at each dock for
#' every 5-minute slot of a 7-day week (2,016 weekly slots).
#'
#' @param df Data frame with columns `BIKEID`, `DOCID`, and `time`.
#' @param bin_minutes Integer slot width in minutes (default: 5; must divide 1440 evenly).
#' @param tz Local city timezone string (default: "America/Chicago").
#' @return A data frame containing columns `DOCID`, `weekday`, `day`, `tod`, `slot`,
#'   `n_days`, `avg_docked`, `prev_docked`, and `rate` (bikes/min).
#' @export
compute_dock_rates <- function(df, bin_minutes = 5, tz = "America/Chicago") {
  stopifnot(
    all(c("BIKEID", "DOCID", "time") %in% names(df)),
    length(bin_minutes) == 1,
    is.finite(bin_minutes),
    bin_minutes > 0,
    1440 %% bin_minutes == 0
  )

  bin_sec <- bin_minutes * 60
  slots_per_day <- 1440 / bin_minutes
  slots_per_week <- 7 * slots_per_day

  df <- df %>%
    mutate(
      BIKEID = as.character(BIKEID),
      DOCID = as.character(DOCID),
      time = parse_city_time(time, tz)
    )

  if (anyNA(df[c("BIKEID", "DOCID", "time")])) {
    stop("Missing bike IDs, dock IDs, or invalid timestamps.")
  }

  if (anyDuplicated(df[c("BIKEID", "time")])) {
    stop("Duplicate BIKEID/full-timestamp pairs found.")
  }

  df <- df %>%
    mutate(
      bin = as.POSIXct(
        floor(as.numeric(time) / bin_sec) * bin_sec,
        origin = "1970-01-01",
        tz = tz
      )
    )

  counts <- df %>%
    filter(DOCID != "0") %>%
    group_by(DOCID, bin) %>%
    summarise(
      n_docked = n_distinct(BIKEID),
      .groups = "drop"
    )

  if (nrow(counts) == 0) {
    stop("No docked-bike observations found.")
  }

  all_bins <- seq(min(df$bin), max(df$bin), by = bin_sec)

  grid <- expand.grid(
    DOCID = unique(counts$DOCID),
    bin = all_bins,
    stringsAsFactors = FALSE
  )

  per_bin <- grid %>%
    left_join(counts, by = c("DOCID", "bin")) %>%
    mutate(
      n_docked = coalesce(n_docked, 0L),
      weekday = as.integer(format(bin, "%u", tz = tz)),
      minute = as.integer(format(bin, "%H", tz = tz)) * 60 +
        as.integer(format(bin, "%M", tz = tz)),
      slot = (weekday - 1) * slots_per_day + minute / bin_minutes
    )

  weekly <- per_bin %>%
    group_by(DOCID, weekday, slot, minute) %>%
    summarise(
      avg_docked = mean(n_docked),
      n_days = n(),
      .groups = "drop"
    )

  coverage <- weekly %>% count(DOCID, name = "n_slots")

  if (any(coverage$n_slots != slots_per_week)) {
    stop("History must cover every local weekday/time slot to construct a complete typical week.")
  }

  previous <- weekly %>%
    transmute(
      DOCID,
      slot = (slot + 1) %% slots_per_week,
      prev_docked = avg_docked
    )

  result <- weekly %>%
    left_join(previous, by = c("DOCID", "slot")) %>%
    mutate(
      day = c("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")[weekday],
      tod = sprintf("%02d:%02d", minute %/% 60, minute %% 60),
      rate = (avg_docked - prev_docked) / bin_minutes
    ) %>%
    select(DOCID, weekday, day, tod, slot, n_days, avg_docked, prev_docked, rate) %>%
    arrange(DOCID, slot)

  attr(result, "city_timezone") <- tz
  attr(result, "bin_minutes") <- bin_minutes

  result
}


# ------------------------------------------------------------------------------
# predict_dock
# ------------------------------------------------------------------------------
# Short description: Forecasts expected bike and space counts at a specific dock
# when the user arrives, by applying the typical-week change curve to live inventory.

#' Forecast Dock Availability at User Arrival
#'
#' @description
#' Uses smoothed typical-week docking profiles to estimate net inventory changes
#' over the user's travel time, projecting available bikes and free spaces upon arrival.
#'
#' @param rates Data frame of historical rates produced by [compute_dock_rates()].
#' @param dock Station identifier string (`DOCID`).
#' @param live_bikes Numeric count of bikes currently docked at departure time.
#' @param capacity Total docking slot capacity at the station.
#' @param walk_min Numeric travel time to the dock in minutes.
#' @param now Departure timestamp (default: `Sys.time()`).
#' @param smooth_min Minutes for moving-average smoothing of weekly profile (default: 30).
#' @param bin_minutes Bin size in minutes (default: 5).
#' @param tz City timezone string (default: "America/Chicago").
#' @return Named numeric vector with `expected_bikes`, `expected_spaces`, and `change`.
#' @export
predict_dock <- function(
    rates,
    dock,
    live_bikes,
    capacity,
    walk_min,
    now = Sys.time(),
    smooth_min = 30,
    bin_minutes = 5,
    tz = "America/Chicago"
) {
  stopifnot(
    length(live_bikes) == 1,
    length(capacity) == 1,
    length(walk_min) == 1,
    is.finite(live_bikes),
    is.finite(capacity),
    is.finite(walk_min),
    capacity > 0,
    live_bikes >= 0,
    live_bikes <= capacity,
    walk_min >= 0,
    bin_minutes > 0,
    smooth_min >= 0
  )

  stored_tz <- attr(rates, "city_timezone")
  stored_bin <- attr(rates, "bin_minutes")

  if (!is.null(stored_tz) && stored_tz != tz) {
    stop("Prediction timezone must match historical rates.")
  }

  if (!is.null(stored_bin) && stored_bin != bin_minutes) {
    stop("Prediction bin size must match historical rates.")
  }

  week_min <- 7 * 1440
  slots_per_week <- week_min / bin_minutes

  d <- rates %>%
    filter(DOCID == dock) %>%
    arrange(slot)

  if (nrow(d) == 0) {
    stop("Unknown dock: ", dock)
  }

  if (
    nrow(d) != slots_per_week ||
    anyDuplicated(d$slot) ||
    !all(d$slot == seq.int(0, slots_per_week - 1))
  ) {
    stop("Dock history must contain a complete typical week.")
  }

  avg <- d$avg_docked
  k <- max(1L, as.integer(round(smooth_min / bin_minutes)))

  if (k > length(avg)) {
    stop("Smoothing window exceeds the available weekly history.")
  }

  if (k > 1) {
    avg <- as.numeric(stats::filter(
      avg,
      rep(1 / k, k),
      sides = 2,
      circular = TRUE
    ))
  }

  anchors <- d$slot * bin_minutes

  typical <- stats::approxfun(
    c(anchors - week_min, anchors, anchors + week_min),
    rep(avg, 3),
    rule = 2
  )

  now <- parse_city_time(now, tz)

  if (length(now) != 1 || is.na(now)) {
    stop("Provide one valid prediction timestamp.")
  }

  local_now <- as.POSIXlt(now, tz = tz)

  now_min <-
    (as.integer(format(now, "%u", tz = tz)) - 1) * 1440 +
    local_now$hour * 60 +
    local_now$min +
    local_now$sec / 60

  arrive_min <- (now_min + walk_min) %% week_min

  change <- typical(arrive_min) - typical(now_min)
  bikes <- min(max(live_bikes + change, 0), capacity)

  c(
    expected_bikes = unname(bikes),
    expected_spaces = unname(capacity - bikes),
    change = unname(change)
  )
}


# ------------------------------------------------------------------------------
# return_discount
# ------------------------------------------------------------------------------
# Short description: Calculates rider return incentive discount percentages based
# on projected station occupancy before the return (20% for <25%, 10% for 25-50%).

#' Calculate Return Rebalancing Incentive Discount
#'
#' @description
#' Computes discount percentage for returning a bike to under-utilized stations:
#'   - Occupancy < 25%: 20% discount
#'   - Occupancy 25% - <50%: 10% discount
#'   - Occupancy >= 50%: 0% discount
#'
#' @param projected_bikes Numeric vector of projected bike counts before return.
#' @param capacity Numeric vector of station capacities.
#' @return Integer vector of discount percentages (0, 10, or 20).
#' @export
return_discount <- function(projected_bikes, capacity) {
  if (any(!is.finite(projected_bikes)) || any(!is.finite(capacity)) ||
      any(capacity <= 0) || any(projected_bikes < 0) ||
      any(projected_bikes > capacity)) {
    stop("Invalid projected occupancy")
  }
  occupancy <- projected_bikes / capacity
  as.integer(ifelse(occupancy < 0.25, 20L, ifelse(occupancy < 0.5, 10L, 0L)))
}


# ------------------------------------------------------------------------------
# optimize_docks
# ------------------------------------------------------------------------------
# Short description: Filters and ranks stations by road distance from user location,
# excluding docks projected to have zero bikes (pickup) or zero spaces (return).

#' Rank Stations by Distance with Projected Inventory Checks
#'
#' @description
#' Evaluates candidate docks relative to a user location. Projects bike/space
#' availability at arrival time, excludes docks with fewer than 1 projected bike
#' (pickup mode) or fewer than 1 projected space (return mode), and returns valid
#' docks ordered by road distance.
#'
#' @param user_location Character ID matching `location_id` in `user_distances`.
#' @param stations Data frame with `dockID`, `live_bikes`, and `capacity`.
#' @param rates Data frame of historical rates from [compute_dock_rates()].
#' @param mode Mode of travel: `"pickup"` (walking) or `"return"` (biking).
#' @param now POSIXct or character departure time (default: `Sys.time()`).
#' @param user_distances Data frame of road distances with `location_id`, `mode`, `dockID`, `distance`.
#' @param travel_speed_mph Numeric travel speed (default: 3 mph for pickup, 10 mph for return).
#' @param smooth_min Smoothing window in minutes (default: 30).
#' @param bin_minutes Bin size in minutes (default: 5).
#' @param tz City timezone string (default: from rates attribute).
#' @return Data frame of eligible stations ordered by distance, with arrival projections and discounts.
#' @export
optimize_docks <- function(
    user_location,
    stations,
    rates,
    mode = c("pickup", "return"),
    now = Sys.time(),
    user_distances,
    travel_speed_mph = NULL,
    smooth_min = 30,
    bin_minutes = 5,
    tz = attr(rates, "city_timezone")
) {
  mode <- match.arg(mode)
  if (is.null(travel_speed_mph)) {
    travel_speed_mph <- if (mode == "pickup") 3 else 10
  }
  if (length(travel_speed_mph) != 1 || !is.finite(travel_speed_mph) || travel_speed_mph <= 0) {
    stop("Travel speed must be positive mph")
  }
  if (length(user_location) != 1 || is.na(user_location) || !nzchar(user_location)) {
    stop("Provide one saved user location ID")
  }
  if (is.null(tz) || length(tz) != 1 || !tz %in% OlsonNames()) {
    stop("Provide the city timezone or rates with a city_timezone attribute")
  }

  required <- c("dockID", "live_bikes", "capacity")
  if (!all(required %in% names(stations)) || nrow(stations) == 0) {
    stop("stations needs dockID, live_bikes, capacity and at least one row")
  }
  if (anyNA(stations[required]) || anyDuplicated(stations$dockID) ||
      any(!nzchar(as.character(stations$dockID))) ||
      !is.numeric(stations$live_bikes) || !is.numeric(stations$capacity) ||
      any(!is.finite(stations$live_bikes)) || any(!is.finite(stations$capacity)) ||
      any(stations$capacity <= 0) || any(stations$live_bikes < 0) ||
      any(stations$live_bikes > stations$capacity)) {
    stop("Invalid station inventory")
  }

  if (missing(user_distances) || is.null(user_distances)) {
    if (file.exists("data/optimizer/user_dock_distances.csv")) {
      user_distances <- utils::read.csv("data/optimizer/user_dock_distances.csv")
    } else {
      stop("Distance input needs location_id, mode, dockID, distance in miles")
    }
  }

  if (!all(c("location_id", "mode", "dockID", "distance") %in% names(user_distances))) {
    stop("Distance input needs location_id, mode, dockID, distance in miles")
  }

  routes <- user_distances[user_distances$location_id == user_location &
                           user_distances$mode == mode, , drop = FALSE]
  if (nrow(routes) == 0) {
    stop("Unknown user location or missing route mode")
  }
  if (anyNA(routes$dockID) || anyDuplicated(routes$dockID) ||
      !is.numeric(routes$distance) || any(routes$distance < 0, na.rm = TRUE) ||
      any(is.infinite(routes$distance))) {
    stop("Invalid or duplicate road distances")
  }
  if (!all(stations$dockID %in% routes$dockID)) {
    stop("Missing station routes")
  }

  reference <- parse_city_time(now, tz)
  if (length(reference) != 1 || is.na(reference)) {
    stop("Invalid reference time")
  }

  result <- data.frame(
    dockID = as.character(stations$dockID),
    distance_miles = routes$distance[match(stations$dockID, routes$dockID)],
    live_bikes = stations$live_bikes,
    capacity = stations$capacity,
    stringsAsFactors = FALSE
  )
  result$travel_minutes <- result$distance_miles / travel_speed_mph * 60
  result$arrival_time <- reference + result$travel_minutes * 60
  attr(result$arrival_time, "tzone") <- tz

  result$projected_bikes <- result$projected_spaces <- NA_real_
  result$exclusion_reason <- ifelse(is.na(result$distance_miles), "no_route", "")

  for (i in seq_len(nrow(result))) {
    if (result$exclusion_reason[i] != "") next
    projection <- predict_dock(
      rates,
      result$dockID[i],
      result$live_bikes[i],
      result$capacity[i],
      walk_min = result$travel_minutes[i],
      now = reference,
      smooth_min = smooth_min,
      bin_minutes = bin_minutes,
      tz = tz
    )
    result$projected_bikes[i] <- projection["expected_bikes"]
    result$projected_spaces[i] <- projection["expected_spaces"]

    quantity <- if (mode == "pickup") result$projected_bikes[i] else result$projected_spaces[i]
    if (quantity < 1) {
      result$exclusion_reason[i] <-
        if (mode == "pickup") "fewer_than_one_projected_bike" else "fewer_than_one_projected_space"
    }
  }

  excluded <- result[result$exclusion_reason != "", , drop = FALSE]
  result <- result[result$exclusion_reason == "", , drop = FALSE]
  result$exclusion_reason <- NULL
  result$projected_occupancy <- result$projected_bikes / result$capacity
  result$discount_percent <- if (mode == "return") {
    return_discount(result$projected_bikes, result$capacity)
  } else {
    rep(0L, nrow(result))
  }

  result <- result[order(result$distance_miles, result$dockID), , drop = FALSE]
  result$rank <- seq_len(nrow(result))
  result <- result[c("rank", setdiff(names(result), "rank"))]
  rownames(result) <- NULL

  attr(result, "excluded_docks") <- excluded
  attr(result, "user_location") <- user_location
  attr(result, "mode") <- mode
  attr(result, "travel_speed_mph") <- travel_speed_mph

  result
}

