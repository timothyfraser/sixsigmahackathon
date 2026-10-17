# app/forecast.R - current-state risk forecast, step 5a: fixed Poisson rates (task H-13, team 2027win)
#
# Plain base-R functions (base, stats only; needs app/qc.R, app/sim.R and app/prep.R sourced first).
# The rules are in docs/methods.md 4.1, 4.2 tier 2 item 5, 4.4 and decision D-2.
#
# Question: starting from the inventory a station has at the forecast origin t0, what is the
# probability of AT LEAST ONE rent-unusable (or return-unusable) minute within the next 10, 20 and
# 30 minutes? It is simulated forward (Monte Carlo) with Poisson rider arrivals. It is a model with
# demo assumptions, not a measurement, and it is a different question from the historical
# Kaplan-Meier (that one describes past days).
#
# Assumptions (all shown on the page too)
#   * Rents and returns arrive as independent Poisson processes per station; the rate is constant
#     inside each 15-minute bin; stations are independent (no interactions between stations).
#   * Rate = attempts (successful + failed) / known station-minutes in that bin, over the weekdays
#     STRICTLY BEFORE t0's date (sim.R estimate_demand, the same definition as the simulation).
#     No data after t0 is used anywhere (D-2). A rate of 0 is valid.
#   * Riders who gave up without trying are not in the log, so demand may be understated.
#   * The renting / returning flags stay at their t0 values.
#   * A successful rent needs a bike and renting on; a successful return needs a free dock and
#     returning on; a failed attempt changes nothing.
#   * Fixed rates (step 5a): the rates are taken as known. Parameter-estimation uncertainty is
#     added in step 5b (H-14).
#
# Time convention (same as sim.R / methods 4.1)
#   Minute k (k = 0, 1, ...) after t0 holds the events of [t0+k, t0+k+1). The state of the interval
#   starting at t0+k is read after every event before it. The start state (k = 0) is the grid state
#   at t0 and is not part of "the next h minutes". The next h minutes are the intervals that start
#   at t0+1, ..., t0+h (the last one starts when the horizon ends, so events of all h minutes
#   count). This is what makes KA-8b exact: a station with 2 bikes, rent rate 0.1/min and no
#   returns is rent-unusable at some start t0+k, k <= h, if and only if N >= 2 rents arrived in
#   h minutes, N ~ Poisson(0.1 h).
#   Past 10:00: the grid ends at 10:00, so when t0 + h goes past it the rates of the last 15-min bin
#   (09:45-10:00) are reused and the horizon is labelled "extends past 10:00" (demo assumption).

FORECAST_HORIZONS <- c(10, 20, 30)
FORECAST_UNCERTAINTY <- c(
  "(i) Demand randomness: this is what each probability describes (the same rates give different futures).",
  paste("(ii) Simulation error: the Monte Carlo standard error sqrt(p(1-p)/R) of using a finite R;",
        "it is not a statement about the real world."),
  "(iii) Parameter-estimation uncertainty (are the rates right?): added in step 5b (H-14).")

# ---------------------------------------------------------------- 1. the Monte Carlo core

#' Simulate R paths of the inventory of S stations and count how often each station has a
#' rent-unusable / return-unusable interval within each horizon.
#' Input : world = list(bikes, docks, renting, returning), vectors of length S (the state at t0);
#'         lambda = array [minute 0..Hmax-1, S, 2] of attempts per minute (type 1 = rent, 2 = return);
#'         arrivals = NULL or data.frame(step, station (index 1..S), qty): bikes a van adds at the
#'           start of minute `step` (capped by the free docks then);
#'         horizons (minutes), R (paths), seed.
#' Method: in each minute the number of attempts of a station is Poisson(lambda_rent + lambda_return);
#'         each attempt is a rent with probability lambda_rent / (lambda_rent + lambda_return)
#'         (the same as two independent Poisson streams in random order). Success needs a bike (rent)
#'         or a free dock (return) and the flag on. After the events of minute k the interval that
#'         starts at t0+k+1 is checked: rent-unusable = bikes 0 or not renting; return-unusable =
#'         docks 0 or not returning. "Hit" = at least one such interval within the horizon.
#' Output: list(p_rent, p_return, se_rent, se_return) matrices [S, horizons];
#'         p = hits / R, se = sqrt(p (1 - p) / R) (simulation error only).
#' Side effect: set.seed(seed): the same seed gives the same output.
forecast_simulate <- function(world, lambda, arrivals = NULL, horizons = FORECAST_HORIZONS,
                              R = 2000, seed = 1) {
  if (!is.numeric(R) || length(R) != 1 || is.na(R) || R < 1) stop("R must be a whole number of at least 1.", call. = FALSE)
  if (!is.numeric(seed) || length(seed) != 1 || is.na(seed)) stop("seed must be a number.", call. = FALSE)
  R <- round(R)
  S <- length(world$bikes)
  h_max <- max(horizons)
  if (dim(lambda)[1] < h_max || dim(lambda)[2] != S) stop("lambda must have one row per minute and one column per station.", call. = FALSE)
  if (anyNA(lambda) || any(lambda < 0)) stop("lambda must be non-negative numbers without NA.", call. = FALSE)
  set.seed(seed)
  # one row per path, one column per station
  spread <- function(v) matrix(rep(as.numeric(v), each = R), R, S)
  bikes <- spread(world$bikes)
  docks <- spread(world$docks)
  renting <- spread(world$renting) == 1
  returning <- spread(world$returning) == 1
  hit_rent <- matrix(FALSE, R, S)
  hit_ret <- matrix(FALSE, R, S)
  p_rent <- matrix(NA_real_, S, length(horizons))
  p_ret <- p_rent
  for (k in 0:(h_max - 1)) {
    if (!is.null(arrivals) && nrow(arrivals) > 0) {
      for (a in which(arrivals$step == k)) {
        i <- arrivals$station[a]
        add <- pmin(arrivals$qty[a], docks[, i])        # leftover bikes stay on the van
        bikes[, i] <- bikes[, i] + add
        docks[, i] <- docks[, i] - add
      }
    }
    lr <- lambda[k + 1, , 1]
    lt <- lambda[k + 1, , 2]
    total <- lr + lt
    n_events <- matrix(stats::rpois(R * S, rep(total, each = R)), R, S)
    share_rent <- matrix(rep(ifelse(total > 0, lr / total, 0), each = R), R, S)
    for (j in seq_len(max(n_events))) {
      u <- matrix(stats::runif(R * S), R, S)
      active <- n_events >= j
      rent_ok <- active & u < share_rent & bikes > 0 & renting
      ret_ok <- active & u >= share_rent & docks > 0 & returning
      bikes <- bikes - rent_ok + ret_ok
      docks <- docks + rent_ok - ret_ok
    }
    hit_rent <- hit_rent | bikes == 0 | !renting
    hit_ret <- hit_ret | docks == 0 | !returning
    col <- match(k + 1, horizons)
    if (!is.na(col)) {
      p_rent[, col] <- colMeans(hit_rent)
      p_ret[, col] <- colMeans(hit_ret)
    }
  }
  se <- function(p) sqrt(p * (1 - p) / R)
  list(p_rent = p_rent, p_return = p_ret, se_rent = se(p_rent), se_return = se(p_ret), R = R, seed = seed)
}

# ---------------------------------------------------------------- 2. vans already on the way

#' Tasks in transit at t0, using NO information after t0.
#' In transit = status not "planned"/"cancelled", assigned_at <= t0, and not completed by t0
#'   (completed_at missing or after t0). The logged arrived_at / completed_at are never used as the
#'   arrival time, because they may lie after t0.
#' Demo assumption: the van arrives at assigned_at + haversine km x detour / speed (source to
#'   destination), the pickup has already happened (its effect is in the source's snapshot), and
#'   planned_quantity bikes are added to the destination then (capped by its free docks).
#' Output: data.frame(task_id, source, destination, planned, assigned_at, eta_min (minutes after t0,
#'   may be negative = should already have arrived), known_destination).
forecast_in_transit <- function(tasks, stations, t0, params = sim_params()) {
  empty <- data.frame(task_id = character(0), source = character(0), destination = character(0),
                      planned = numeric(0), assigned_at = as.POSIXct(character(0), tz = SIM_TZ),
                      eta_min = numeric(0), known_destination = logical(0), stringsAsFactors = FALSE)
  if (is.null(tasks) || nrow(tasks) == 0) return(empty)
  t0s <- as.numeric(t0)
  asg <- as.numeric(tasks$assigned_at)
  comp <- as.numeric(tasks$completed_at)
  live <- !is.na(asg) & asg <= t0s & (is.na(comp) | comp > t0s) &
    !tasks$status %in% c("planned", "cancelled")
  tk <- tasks[live, ]
  if (nrow(tk) == 0) return(empty)
  a <- match(tk$source_station_id, stations$station_id)
  b <- match(tk$destination_station_id, stations$station_id)
  km <- haversine_km(stations$latitude[a], stations$longitude[a],
                     stations$latitude[b], stations$longitude[b]) * params$detour
  eta <- (as.numeric(tk$assigned_at) - t0s) / 60 + km / params$speed_kmh * 60
  data.frame(task_id = tk$task_id, source = tk$source_station_id, destination = tk$destination_station_id,
             planned = tk$planned_quantity, assigned_at = tk$assigned_at, eta_min = eta,
             known_destination = !is.na(b), stringsAsFactors = FALSE)
}

# ---------------------------------------------------------------- 3. rates (no look-ahead)

#' Poisson bin rates for a forecast on `date`: sim.R estimate_demand over the weekdays STRICTLY
#' BEFORE `date` that have a grid. Output: the estimate_demand list, or NULL with no earlier weekday.
forecast_rates <- function(attempts, grids, date, dates, station_ids, tz = SIM_TZ) {
  source_days <- sort(intersect(dates[dates < date], names(grids)))
  if (length(source_days) == 0) return(NULL)
  estimate_demand(attempts, grids, source_days, station_ids, tz)
}

# ---------------------------------------------------------------- 4. the forecast for every station

#' Step 5a forecast at t0 = `date` 07:00 + `minute`.
#' Input : sc = list(stations, attempts, tasks) from qc.R load_scenario;
#'         grids = minute grids named by date (prep.R build_day_grids at the chosen stale_limit, so the
#'           age rule is already applied); date; dates = every weekday of the scenario;
#'         minute = minutes after 07:00 (0..179); R (paths, default 2000); seed (default 1);
#'         params (sim_params: speed and detour for the van ETA); horizons.
#' Rules : the start inventory is the grid state at t0 (latest valid snapshot at or before t0 that
#'         passes the age rule). Unknown / stale -> all probabilities NA with the reason.
#'         No earlier weekday, or a station without any known minute earlier -> NA with the reason.
#'         A closed station (flag off) or one already unusable at t0 is still simulated and its state
#'         is stated in `flags` ("already rent-unusable at t0"); with a flag off the probability is 1
#'         by construction (the flag is held), with 0 bikes it is the chance of being unusable in the
#'         next minutes (a return can fix it first).
#' Output: list(ok, reason, table (one row per station), horizons, t0, minute, R, seed, source_days,
#'         rates ([station, type, bin] of the stations used), in_transit, past_10 (per horizon),
#'         uncertainty (the three sources, text), n_attempts).
forecast_now <- function(sc, grids, date, dates, minute, R = 2000, seed = 1,
                         params = sim_params(), horizons = FORECAST_HORIZONS, tz = SIM_TZ) {
  if (!is.numeric(minute) || length(minute) != 1 || is.na(minute) || minute < 0 || minute > SIM_N_MIN - 1) {
    stop("minute must be a number from 0 to 179.", call. = FALSE)
  }
  if (!date %in% names(grids)) stop("no minute grid for ", date, ".", call. = FALSE)
  t0 <- as.POSIXct(paste(date, "07:00"), tz = tz, format = "%Y-%m-%d %H:%M") + 60 * minute
  all_ids <- sort(sc$stations$station_id, method = "radix")
  st <- state_at(grids[[date]], minute)
  st <- st[match(all_ids, st$station_id), ]
  known <- !is.na(st$known) & st$known
  demand <- forecast_rates(sc$attempts, grids, date, dates, all_ids, tz)
  past_10 <- minute + horizons > SIM_N_MIN

  reason <- rep("", length(all_ids))
  reason[!known] <- "no valid recent snapshot at t0 (stale or missing): no forecast"
  if (is.null(demand)) {
    reason[known] <- "no earlier weekday to estimate demand: no forecast"
  } else {
    reason[known & !demand$has_rate] <- "no known minute on earlier weekdays to estimate demand: no forecast"
  }
  use <- reason == ""

  nh <- length(horizons)
  P <- function() matrix(NA_real_, length(all_ids), nh)
  p_rent <- P(); p_ret <- P(); se_rent <- P(); se_ret <- P()
  in_transit <- forecast_in_transit(sc$tasks, sc$stations, t0, params)
  rates <- NULL
  if (any(use)) {
    ids <- all_ids[use]
    world <- sim_world(st[use, c("station_id", "bikes_available", "docks_available", "is_renting", "is_returning")],
                       sc$stations)
    rates <- demand$rates[use, , , drop = FALSE]
    per_min <- demand_lambda(rates)                                   # [180, S, 2]
    h_max <- max(horizons)
    idx <- pmin(minute + seq_len(h_max) - 1, SIM_N_MIN - 1) + 1       # past 10:00: last bin's rate
    lambda <- per_min[idx, , , drop = FALSE]
    arrivals <- NULL
    if (nrow(in_transit) > 0) {
      keep <- in_transit$known_destination & in_transit$destination %in% ids
      if (any(keep)) {
        arrivals <- data.frame(step = floor(pmax(in_transit$eta_min[keep], 0)),
                               station = match(in_transit$destination[keep], ids),
                               qty = in_transit$planned[keep])
        arrivals <- arrivals[arrivals$step < h_max, , drop = FALSE]
      }
    }
    sim <- forecast_simulate(world, lambda, arrivals, horizons, R, seed)
    row <- match(ids, all_ids)
    p_rent[row, ] <- sim$p_rent; p_ret[row, ] <- sim$p_return
    se_rent[row, ] <- sim$se_rent; se_ret[row, ] <- sim$se_return
  }

  flags <- vapply(seq_along(all_ids), function(i) {
    if (!known[i]) return("")
    f <- character(0)
    if (!isTRUE(as.logical(st$is_renting[i]))) f <- c(f, "renting off at t0 (rent risk = 1 by construction)")
    else if (st$bikes_available[i] == 0) f <- c(f, "already rent-unusable at t0 (0 bikes)")
    if (!isTRUE(as.logical(st$is_returning[i]))) f <- c(f, "returning off at t0 (return risk = 1 by construction)")
    else if (st$docks_available[i] == 0) f <- c(f, "already return-unusable at t0 (0 docks)")
    if (use[i] && sum(demand$rates[i, , ], na.rm = TRUE) == 0) {
      f <- c(f, "no attempts observed on earlier weekdays; this does not show the risk is zero")
    }
    paste(f, collapse = "; ")
  }, character(1))

  tab <- data.frame(station_id = all_ids, known = known, age = st$age,
                    bikes = st$bikes_available, docks = st$docks_available,
                    is_renting = st$is_renting, is_returning = st$is_returning,
                    stringsAsFactors = FALSE)
  for (j in seq_len(nh)) {
    h <- horizons[j]
    tab[[paste0("p_rent_", h)]] <- p_rent[, j]
    tab[[paste0("se_rent_", h)]] <- se_rent[, j]
  }
  for (j in seq_len(nh)) {
    h <- horizons[j]
    tab[[paste0("p_return_", h)]] <- p_ret[, j]
    tab[[paste0("se_return_", h)]] <- se_ret[, j]
  }
  tab$flags <- flags
  tab$reason <- reason
  last <- paste0("p_rent_", max(horizons))
  worst <- pmax(tab[[last]], tab[[paste0("p_return_", max(horizons))]], na.rm = TRUE)
  worst[is.infinite(worst)] <- NA
  tab <- tab[order(-ifelse(is.na(worst), -1, worst), tab$station_id, method = "radix"), ]
  rownames(tab) <- NULL

  list(ok = any(use), reason = if (any(use)) "" else
         (if (is.null(demand)) "no earlier weekday to estimate demand: no forecast" else
            "no station has a valid recent snapshot at t0 and a demand rate: no forecast"),
       table = tab, horizons = horizons, t0 = t0, minute = minute, R = round(R), seed = seed,
       source_days = if (is.null(demand)) character(0) else demand$source_days,
       rates = rates, in_transit = in_transit, past_10 = setNames(past_10, horizons),
       uncertainty = FORECAST_UNCERTAINTY,
       n_attempts = if (is.null(demand)) 0 else demand$n_attempts,
       params = params)
}
