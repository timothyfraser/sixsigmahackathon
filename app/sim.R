# app/sim.R - seeded policy simulation for the weekday 07:00-10:00 rush (task H-10, team 2027win)
#
# Plain base-R functions (base, stats only, plus app/qc.R). No Shiny, no plotting.
# The rules are written out in docs/methods.md sections 4.2 (item 5, D-2), 4.3, 4.4 and 4.2 KA-4b/KA-5.
# Everything marked "demo assumption" is adjustable and is NOT a measured property of a real system.
#
# What it answers: with the SAME simulated riders, are fewer station-minutes unusable when vans
# rebalance (policy "reactive" or "predictive") than when they do not (policy "none")? The tool never
# assumes the answer; the paired differences and their intervals say. Three policies, three pairs (H-15).
#
# Contents
#   1. parameters and the world         sim_params, default_van_count, sim_world
#   2. demand (no look-ahead)           estimate_demand, demand_lambda, make_demand_stream
#   3. van rules                        van_pickup_amount, van_dropoff_amount
#   3b. predictive risk (H-15)          predictive_risk_table, predictive_risk
#   4. one run of one policy            run_policy (+ its helpers), recovery_episodes
#   5. the comparison                   paired_table, paired_tables, compare_policies
#
# Time: minutes after 07:00 (0 ... 180). A rider event of minute m happens at time m + 0.5.
# The state of minute [m, m+1) is read at time m, after every event before m (methods 4.1).

SIM_N_MIN <- 180                 # 07:00-10:00
SIM_BIN_MIN <- 15                # demand rates are constant inside a 15-minute bin
SIM_TZ <- "America/New_York"
SIM_PRIMARY <- "either_min"      # the primary metric; the others are exploratory
SIM_PRIMARY_FAMILY <- 3          # Bonferroni family: 3 pairwise policy comparisons (H-15), alpha = 0.05/3
SIM_POLICIES <- c("none", "reactive", "predictive")
# The 3 pairwise comparisons. d = metric(first) - metric(second): positive = the SECOND policy is better
# (fewer minutes / failures / minutes to recover; for van_km it says the second drives less).
SIM_PAIRS <- list(c("none", "reactive"), c("none", "predictive"), c("reactive", "predictive"))
SIM_RISK_HORIZON <- 30           # minutes the predictive policy looks ahead (same as the Now forecast's longest horizon)
SIM_METRICS <- c("either_min", "fail_prop", "van_km", "recovery_min")

# ---------------------------------------------------------------- 1. parameters and the world

#' Simulation parameters (all demo assumptions, adjustable).
#' vans         number of vans (default 2; the app uses the number of distinct van_id in the tasks)
#' van_capacity bikes a van holds
#' target_fill  target share of capacity per station (for the rebalancing plan)
#' detour       road distance = straight line x detour
#' speed_kmh    van speed; travel minutes = km / speed_kmh x 60
#' stop_min     minutes lost at each pickup and each drop-off
#' per_bike_min minutes per bike loaded or unloaded
#' early_k      early warning = 0 < bikes <= k or 0 < docks <= k (used only to trigger "reactive")
#' risk_threshold  the "predictive" policy dispatches for a station whose risk of at least one
#'              unusable minute in the next 30 minutes is at or above this (default 0.5; an adjustable
#'              demo heuristic, not a tuned or optimal value; above 1 it never triggers)
sim_params <- function(vans = 2, van_capacity = 12, target_fill = 0.5, detour = 1.3,
                       speed_kmh = 20, stop_min = 2, per_bike_min = 0.1, early_k = 2, risk_threshold = 0.5) {
  ok <- function(x, lower, name) {
    if (!is.numeric(x) || length(x) != 1 || is.na(x) || x < lower) {
      stop(name, " must be a single number of at least ", lower, ".", call. = FALSE)
    }
  }
  ok(vans, 1, "vans"); ok(van_capacity, 1, "van_capacity"); ok(detour, 1, "detour")
  ok(speed_kmh, 1e-6, "speed_kmh"); ok(stop_min, 0, "stop_min"); ok(per_bike_min, 0, "per_bike_min")
  ok(early_k, 1, "early_k"); ok(risk_threshold, 0, "risk_threshold")
  if (!is.numeric(target_fill) || length(target_fill) != 1 || is.na(target_fill) ||
      target_fill <= 0 || target_fill >= 1) {
    stop("target_fill must be between 0 and 1.", call. = FALSE)
  }
  list(vans = round(vans), van_capacity = van_capacity, target_fill = target_fill, detour = detour,
       speed_kmh = speed_kmh, stop_min = stop_min, per_bike_min = per_bike_min, early_k = early_k,
       risk_threshold = risk_threshold)
}

# Number of vans the scenario's task log used (distinct van_id); 2 when there are none.
default_van_count <- function(tasks) {
  if (is.null(tasks) || !"van_id" %in% names(tasks)) return(2)
  n <- length(unique(tasks$van_id[!is.na(tasks$van_id)]))
  if (n == 0) 2 else n
}

#' The starting world: stations, their capacity and position, the 07:00 inventory and flags.
#' Input : state0 = station_id, bikes_available, docks_available, is_renting, is_returning (07:00);
#'         stations = station_id, latitude, longitude, capacity.
#' Station flags stay at their 07:00 values for the whole run (demo assumption).
sim_world <- function(state0, stations) {
  state0 <- state0[order(state0$station_id, method = "radix"), ]
  pos <- match(state0$station_id, stations$station_id)
  if (anyNA(pos)) stop("state0 has a station_id that is not in stations.", call. = FALSE)
  list(ids = state0$station_id, lat = stations$latitude[pos], lon = stations$longitude[pos],
       cap = stations$capacity[pos], bikes = state0$bikes_available, docks = state0$docks_available,
       renting = as.logical(state0$is_renting), returning = as.logical(state0$is_returning))
}

# ---------------------------------------------------------------- 2. demand (no look-ahead)

#' Poisson demand rates per station x type x 15-minute bin (methods 4.2 item 5, D-2).
#' Method: rate = attempts (successful + failed) / known station-minutes in that bin, summed over
#'         `source_days`. The caller passes only weekdays STRICTLY BEFORE the chosen date, so the
#'         chosen day is never used. A rate of 0 is valid (known minutes, no attempts).
#' Input : attempts (timestamp, station_id, attempt_type, success), grids = list of minute grids
#'         named by date (qc.R build_grid), source_days, station_ids.
#' Output: list(rates = array [station, "rent"/"return", bin 1..12] in attempts per station-minute,
#'         has_rate = TRUE where the station has any known minute on the source days,
#'         source_days, n_attempts, n_fallback_cells).
#' Demo assumption: a bin with no known station-minute uses the station's pooled rate over all bins
#'         (counted in n_fallback_cells). A station with no known minute at all has no rate (NA) and
#'         is left out of the simulation by compare_policies.
estimate_demand <- function(attempts, grids, source_days, station_ids, tz = SIM_TZ) {
  ns <- length(station_ids)
  n_bins <- SIM_N_MIN %/% SIM_BIN_MIN
  known_min <- matrix(0, ns, n_bins)
  att <- array(0, c(ns, 2, n_bins))
  secs <- as.numeric(attempts$timestamp)
  for (d in source_days) {
    start <- as.numeric(as.POSIXct(paste(d, "07:00"), tz = tz, format = "%Y-%m-%d %H:%M"))
    g <- grids[[d]]
    g <- g[g$known & g$station_id %in% station_ids, ]
    bin <- floor((as.numeric(g$minute) - start) / 60 / SIM_BIN_MIN) + 1
    tab <- table(factor(match(g$station_id, station_ids), seq_len(ns)), factor(bin, seq_len(n_bins)))
    known_min <- known_min + matrix(as.vector(tab), ns, n_bins)

    in_day <- !is.na(secs) & secs >= start & secs < start + 60 * SIM_N_MIN &
      attempts$station_id %in% station_ids
    a <- attempts[in_day, ]
    abin <- floor((secs[in_day] - start) / 60 / SIM_BIN_MIN) + 1
    atype <- ifelse(a$attempt_type == "rent", 1, 2)
    tab <- table(factor(match(a$station_id, station_ids), seq_len(ns)), factor(atype, 1:2),
                 factor(abin, seq_len(n_bins)))
    att <- att + array(as.vector(tab), c(ns, 2, n_bins))
  }
  rates <- array(NA_real_, c(ns, 2, n_bins),
                 dimnames = list(station_ids, c("rent", "return"), seq_len(n_bins)))
  pooled_known <- rowSums(known_min)
  n_fallback <- 0
  for (ty in 1:2) {
    pooled <- ifelse(pooled_known > 0, rowSums(att[, ty, , drop = FALSE]) / pooled_known, NA_real_)
    for (b in seq_len(n_bins)) {
      own <- ifelse(known_min[, b] > 0, att[, ty, b] / known_min[, b], NA_real_)
      fallback <- is.na(own) & !is.na(pooled)
      n_fallback <- n_fallback + sum(fallback)
      rates[, ty, b] <- ifelse(is.na(own), pooled, own)
    }
  }
  list(rates = rates, has_rate = pooled_known > 0, source_days = source_days,
       n_attempts = sum(att), n_fallback_cells = n_fallback)
}

# Expand rates [station, type, bin] to a per-minute array [minute, station, type].
demand_lambda <- function(rates) {
  lambda <- array(0, c(SIM_N_MIN, dim(rates)[1], 2))
  for (m in seq_len(SIM_N_MIN)) lambda[m, , ] <- rates[, , (m - 1) %/% SIM_BIN_MIN + 1]
  lambda
}

#' ONE stream of rider events for one seed (the same stream is used by every policy).
#' Method: the number of events per station-minute and type is Poisson(rate); events inside a
#'         minute are ordered by a pre-drawn random key, then station_id.
#' Output: data.frame(minute 0..179, station_id, type "rent"/"return"), sorted in time order.
#' Side effect: set.seed(seed) (so the same seed always gives the same stream).
make_demand_stream <- function(lambda, station_ids, seed) {
  set.seed(seed)
  counts <- stats::rpois(length(lambda), as.vector(lambda))
  hit <- which(counts > 0)
  cell <- rep(hit, counts[hit])
  n_min <- dim(lambda)[1]
  ns <- dim(lambda)[2]
  minute <- (cell - 1) %% n_min
  station <- ((cell - 1) %/% n_min) %% ns + 1
  type <- (cell - 1) %/% (n_min * ns) + 1
  key <- stats::runif(length(cell))
  o <- order(minute, key, station_ids[station], method = "radix")
  data.frame(minute = as.integer(minute[o]), station_id = station_ids[station][o],
             type = c("rent", "return")[type][o], stringsAsFactors = FALSE)
}

# ---------------------------------------------------------------- 3. van rules (methods 4.4)

# At pickup the van takes min(planned, bikes at the source then, free capacity on the van).
van_pickup_amount <- function(planned, bikes_at_source, van_free) max(0, min(planned, bikes_at_source, van_free))
# At drop-off the van leaves min(van load, free docks at the destination then).
van_dropoff_amount <- function(van_load, free_docks) max(0, min(van_load, free_docks))

# ---------------------------------------------------------------- 3b. predictive risk (H-15)

#' Risk table for the "predictive" policy: for every station, every start minute m (0..179) and every
#' bike count b, the probability of AT LEAST ONE rent-unusable (and, separately, return-unusable)
#' minute in [m, m + 30) when the station holds b bikes at the start of minute m.
#' Model (the same as the Now forecast, docs/methods.md 4.2 item 5): independent Poisson rent and
#'   return attempts per station, rate constant inside each 15-minute bin. In a minute with N ~
#'   Poisson(rent rate + return rate) attempts, each is a rent with probability rent / (rent + return);
#'   a rent needs a bike, a return needs a free dock, a failed attempt changes nothing. The state is
#'   checked after the events of each minute. The current minute counts: an empty station has risk 1.
#' Method: EXACT, not simulated. For each station the bike count (0 ... bikes + docks, constant in a
#'   run) is a Markov chain; one minute is the matrix sum over n of Poisson(n) x M^n (M = one attempt);
#'   the "unusable" state is made absorbing, and the 30 minute matrices are applied back to front.
#' DEMO ASSUMPTION ("oracle rates"): the policy is given the TRUE demand rates of the simulator
#'   (`lambda`), which a real dispatcher would only estimate. This favours the predictive policy
#'   over a real one, and the comparison says so.
#' Uses no random numbers, so it cannot change the rider streams or the global seed.
#' Input : world (sim_world), lambda (demand_lambda: [minute, station, type]).
#' Output: list(rent = list of matrices, ret = same, n_bikes_max, horizon); each matrix is
#'         [bike count + 1, start minute + 1].
predictive_risk_table <- function(world, lambda, horizon = SIM_RISK_HORIZON) {
  ns <- length(world$ids)
  n_bins <- SIM_N_MIN %/% SIM_BIN_MIN
  n_max <- round(world$bikes + world$docks)           # bikes + docks never changes in a run
  starts <- 0:(SIM_N_MIN - 1)
  rent <- vector("list", ns)
  ret <- vector("list", ns)
  for (i in seq_len(ns)) {
    N <- n_max[i]
    P_rent <- vector("list", n_bins)
    P_ret <- vector("list", n_bins)
    for (b in seq_len(n_bins)) {
      first_minute <- (b - 1) * SIM_BIN_MIN + 1        # the rate is constant inside the bin
      P <- risk_minute_matrix(N, lambda[first_minute, i, 1], lambda[first_minute, i, 2])
      P_rent[[b]] <- risk_absorb(P, 0)                 # absorbing state: 0 bikes (rent-unusable)
      P_ret[[b]] <- risk_absorb(P, N)                  # absorbing state: 0 free docks (return-unusable)
    }
    rent[[i]] <- risk_window(P_rent, 0, N, horizon, starts)
    ret[[i]] <- risk_window(P_ret, N, N, horizon, starts)
  }
  list(rent = rent, ret = ret, n_bikes_max = n_max, horizon = horizon)
}

# One minute of one station: matrix [bikes now + 1, bikes after the minute + 1].
risk_minute_matrix <- function(N, rent_rate, return_rate) {
  total <- rent_rate + return_rate
  if (total <= 0) return(diag(N + 1))
  share <- rent_rate / total
  M <- matrix(0, N + 1, N + 1)                         # M = one attempt
  for (b in 0:N) {
    if (b > 0) M[b + 1, b] <- share else M[b + 1, b + 1] <- share      # a rent needs a bike
    if (b < N) M[b + 1, b + 2] <- 1 - share else M[b + 1, b + 1] <- M[b + 1, b + 1] + 1 - share   # a return needs a dock
  }
  n_top <- stats::qpois(1 - 1e-12, total)              # more attempts than this have probability < 1e-12
  w <- stats::dpois(0:n_top, total)
  w[n_top + 1] <- w[n_top + 1] + (1 - sum(w))          # the (tiny) tail goes on the last term
  P <- w[1] * diag(N + 1)
  Mn <- diag(N + 1)
  for (n in seq_len(n_top)) {
    Mn <- Mn %*% M
    P <- P + w[n + 1] * Mn
  }
  P
}

# Make state `hit` absorbing (once there, it stays) in a minute matrix.
risk_absorb <- function(P, hit) {
  P[hit + 1, ] <- 0
  P[hit + 1, hit + 1] <- 1
  P
}

# Probability of being in the absorbing state `hit` after `horizon` minutes, for every start minute
# (column) and every starting bike count (row). P_bins = one absorbing minute matrix per 15-minute bin.
# Past 10:00 the last bin's rate is reused (demo assumption, same as the Now forecast).
risk_window <- function(P_bins, hit, N, horizon, starts) {
  V <- matrix(0, N + 1, length(starts))
  V[hit + 1, ] <- 1
  for (k in (horizon - 1):0) {                         # innermost minute first: P_m (P_m+1 (... P_m+29 e))
    bins <- pmin((starts + k) %/% SIM_BIN_MIN, length(P_bins) - 1) + 1
    for (b in unique(bins)) {
      cols <- which(bins == b)
      V[, cols] <- P_bins[[b]] %*% V[, cols, drop = FALSE]
    }
  }
  V
}

#' Look up the risks at the start of minute `minute` for the given bike counts (one per station).
#' Output: list(rent, ret) numeric vectors, probability of at least one unusable minute in the next 30.
predictive_risk <- function(tab, minute, bikes) {
  idx <- minute + 1
  at <- function(mats) vapply(seq_along(bikes), function(i) mats[[i]][bikes[i] + 1, idx], numeric(1))
  list(rent = at(tab$rent), ret = at(tab$ret))
}

# ---------------------------------------------------------------- 4. one run of one policy

# The mutable state of one run lives in an environment S (so the helpers below can change it).
sim_state <- function(world, params, stream, keep_log, script, risk = NULL) {
  S <- new.env(parent = emptyenv())
  S$ids <- world$ids; S$lat <- world$lat; S$lon <- world$lon; S$cap <- world$cap
  S$renting <- world$renting; S$returning <- world$returning
  S$bikes <- world$bikes; S$docks <- world$docks
  S$n <- length(world$ids)
  S$stations_df <- data.frame(station_id = world$ids, latitude = world$lat, longitude = world$lon,
                              capacity = world$cap, stringsAsFactors = FALSE)
  S$params <- params
  # bikes on rides start at the number of return events in the stream, so returns never run out
  S$rides <- sum(stream$type == "return")
  S$total0 <- sum(world$bikes) + S$rides
  nv <- params$vans
  S$n_vans <- nv
  S$v_lat <- rep(mean(world$lat), nv)      # vans start at the network centroid
  S$v_lon <- rep(mean(world$lon), nv)
  S$v_load <- rep(0, nv)
  S$v_phase <- rep("idle", nv)             # "idle", "to_source" or "to_dest"
  S$v_time <- rep(Inf, nv)                 # time of the van's next event
  S$v_free_at <- rep(0, nv)                # an idle van can take a new task from this time on
  S$v_task <- rep(0L, nv)
  S$tasks <- list()
  S$van_km <- 0
  S$conserved <- TRUE
  S$n_events <- 0
  S$n_att <- 0
  S$n_fail <- 0
  S$unusable <- matrix(FALSE, S$n, SIM_N_MIN)
  S$keep_log <- keep_log
  S$log_time <- numeric(0); S$log_event <- character(0); S$log_station <- character(0)
  S$log_qty <- numeric(0); S$log_ok <- logical(0); S$log_total <- numeric(0)
  S$risk <- risk
  S$script <- script
  S$script_used <- if (is.null(script)) logical(0) else rep(FALSE, nrow(script))
  S
}

# Record one event and check the invariant: bikes in stations + on vans + on rides never changes.
sim_log <- function(S, time, event, station, qty, ok) {
  total <- sum(S$bikes) + sum(S$v_load) + S$rides
  if (total != S$total0) S$conserved <- FALSE
  S$n_events <- S$n_events + 1
  if (S$keep_log) {
    k <- S$n_events
    S$log_time[k] <- time; S$log_event[k] <- event; S$log_station[k] <- station
    S$log_qty[k] <- qty; S$log_ok[k] <- ok; S$log_total[k] <- total
  }
}

# A rider tries to rent or return. Success changes the station and the rides; failure changes nothing
# (a failed return leaves the bike on the ride).
sim_rider <- function(S, time, i, type) {
  S$n_att <- S$n_att + 1
  if (type == "rent") {
    ok <- S$bikes[i] > 0 && S$renting[i]
    if (ok) { S$bikes[i] <- S$bikes[i] - 1; S$docks[i] <- S$docks[i] + 1; S$rides <- S$rides + 1 }
  } else {
    ok <- S$docks[i] > 0 && S$returning[i]
    if (ok) { S$bikes[i] <- S$bikes[i] + 1; S$docks[i] <- S$docks[i] - 1; S$rides <- S$rides - 1 }
  }
  if (!ok) S$n_fail <- S$n_fail + 1
  sim_log(S, time, paste0("rider_", type), S$ids[i], 1, ok)
}

# Estimated road km between a van position and a station (haversine x detour).
sim_km <- function(S, lat1, lon1, i) haversine_km(lat1, lon1, S$lat[i], S$lon[i]) * S$params$detour

sim_reserved <- function(S) {      # stations that are the source or destination of an active task
  r <- rep(FALSE, S$n)
  for (v in which(S$v_phase != "idle")) {
    t <- S$tasks[[S$v_task[v]]]
    r[c(t$from_idx, t$to_idx)] <- TRUE
  }
  r
}

sim_start_task <- function(S, v, m, task) {
  k <- length(S$tasks) + 1
  km <- sim_km(S, S$v_lat[v], S$v_lon[v], task$from)
  S$van_km <- S$van_km + km
  S$tasks[[k]] <- list(task_id = k, van = v, from = S$ids[task$from], to = S$ids[task$to],
                       planned = task$planned, dispatch_min = m, picked = NA_real_,
                       actual_quantity = NA_real_, left_on_van = NA_real_, status = "dispatched",
                       from_idx = task$from, to_idx = task$to)
  S$v_task[v] <- k
  S$v_phase[v] <- "to_source"
  S$v_time[v] <- m + km / S$params$speed_kmh * 60
}

# The van has reached the source: take min(planned, bikes there now, free capacity).
sim_pickup <- function(S, v, t) {
  force(t)   # t is often S$v_time[v]; S is an environment, so read it before S$v_time changes
  k <- S$v_task[v]
  task <- S$tasks[[k]]
  src <- task$from_idx
  take <- van_pickup_amount(task$planned, S$bikes[src], S$params$van_capacity - S$v_load[v])
  S$bikes[src] <- S$bikes[src] - take
  S$docks[src] <- S$docks[src] + take
  S$v_load[v] <- S$v_load[v] + take
  S$tasks[[k]]$picked <- take
  S$v_lat[v] <- S$lat[src]; S$v_lon[v] <- S$lon[src]
  sim_log(S, t, "pickup", S$ids[src], take, TRUE)
  handling <- S$params$stop_min + S$params$per_bike_min * take
  if (S$v_load[v] <= 0) {            # nothing to carry: the task ends here
    S$tasks[[k]]$status <- "nothing_to_pick_up"
    S$v_phase[v] <- "idle"; S$v_time[v] <- Inf; S$v_free_at[v] <- t + handling
  } else {
    km <- sim_km(S, S$lat[src], S$lon[src], task$to_idx)
    S$van_km <- S$van_km + km
    S$tasks[[k]]$status <- "picked_up"
    S$v_phase[v] <- "to_dest"
    S$v_time[v] <- t + handling + km / S$params$speed_kmh * 60
  }
}

# The van has reached the destination: leave min(load, free docks there now); the rest stays on the van.
sim_dropoff <- function(S, v, t) {
  force(t)   # as in sim_pickup: without this, t would be read after S$v_time[v] <- Inf
  k <- S$v_task[v]
  dst <- S$tasks[[k]]$to_idx
  drop <- van_dropoff_amount(S$v_load[v], S$docks[dst])
  S$bikes[dst] <- S$bikes[dst] + drop
  S$docks[dst] <- S$docks[dst] - drop
  S$v_load[v] <- S$v_load[v] - drop
  S$tasks[[k]]$actual_quantity <- drop
  S$tasks[[k]]$left_on_van <- S$v_load[v]
  S$tasks[[k]]$status <- "completed"
  S$v_lat[v] <- S$lat[dst]; S$v_lon[v] <- S$lon[dst]
  sim_log(S, t, "dropoff", S$ids[dst], drop, TRUE)
  S$v_phase[v] <- "idle"; S$v_time[v] <- Inf
  S$v_free_at[v] <- t + S$params$stop_min + S$params$per_bike_min * drop
}

# Run every van event with time < limit, earliest first (ties: lower van number).
sim_run_vans <- function(S, limit) {
  repeat {
    active <- which(S$v_phase != "idle" & S$v_time < limit)
    if (length(active) == 0) break
    v <- active[which.min(S$v_time[active])]
    if (S$v_phase[v] == "to_source") sim_pickup(S, v, S$v_time[v]) else sim_dropoff(S, v, S$v_time[v])
  }
}

# The plan both dynamic policies use: qc.R rebalance_plan on the current simulated state, stations of
# active tasks left out, stations ranked by `severity` (largest first, ties by station_id).
# Returns the data.frame of planned moves (from_station, to_station, quantity).
sim_plan_moves <- function(S, v, reserved, severity) {
  free_cap <- S$params$van_capacity - S$v_load[v]
  keep <- which(!reserved)
  keep <- keep[order(-severity[keep], S$ids[keep], method = "radix")]
  state <- data.frame(station_id = S$ids[keep], bikes_available = S$bikes[keep],
                      docks_available = S$docks[keep], is_renting = S$renting[keep],
                      is_returning = S$returning[keep], stringsAsFactors = FALSE)
  rank <- data.frame(station_id = S$ids[keep], rank = seq_along(keep), stringsAsFactors = FALSE)
  rebalance_plan(state, S$stations_df, rank = rank, target_fill = S$params$target_fill,
                 van_capacity = free_cap, detour = S$params$detour)$moves
}

# Reactive policy (methods 4.4): at the start of a minute an idle van gets the FIRST move of
# qc.R rebalance_plan (on the current simulated state) whose source or destination is a triggered
# station. Triggered = an OPEN station (renting and returning) that is rent-unusable (0 bikes),
# return-unusable (0 docks) or in early warning (0 < bikes <= k or 0 < docks <= k).
# Closed stations are maintenance, never a move. Stations of an active task are reserved.
# Rank for the plan: worst first = both unusable, then one unusable, then early warning, then the rest
# (ties: station_id). Returns list(from, to, planned) as station numbers, or NULL.
sim_reactive_choice <- function(S, v) {
  free_cap <- S$params$van_capacity - S$v_load[v]
  if (free_cap <= 0) return(NULL)
  reserved <- sim_reserved(S)
  k <- S$params$early_k
  open <- S$renting & S$returning
  warn <- (S$bikes > 0 & S$bikes <= k) | (S$docks > 0 & S$docks <= k)
  triggered <- open & !reserved & (S$bikes == 0 | S$docks == 0 | warn)
  if (!any(triggered)) return(NULL)
  rent_u <- S$bikes == 0 | !S$renting
  ret_u <- S$docks == 0 | !S$returning
  severity <- ifelse(rent_u | ret_u, rent_u + ret_u, ifelse(warn, 0.5, 0))
  mv <- sim_plan_moves(S, v, reserved, severity)
  hit <- which(mv$from_station %in% S$ids[triggered] | mv$to_station %in% S$ids[triggered])
  if (length(hit) == 0) return(NULL)
  list(from = match(mv$from_station[hit[1]], S$ids), to = match(mv$to_station[hit[1]], S$ids),
       planned = mv$quantity[hit[1]])
}

# Predictive policy (H-15, tier 2): at the start of minute m an idle van gets the FIRST move of the same
# rebalance_plan whose destination is a station with rent risk >= the threshold (deficit side) or whose
# source is a station with return risk >= the threshold (surplus side). Risk = probability of at least
# one rent-unusable (return-unusable) minute in the next 30 minutes from the CURRENT simulated state
# (predictive_risk_table; exact Poisson model with the simulator's TRUE rates = "oracle rates").
# Same rules as reactive: only open stations, stations of an active task are reserved, one task per van.
# Rank for the plan: the larger of the two risks first (ties: station_id). Decided every minute a van
# is idle. Returns list(from, to, planned) as station numbers, or NULL.
sim_predictive_choice <- function(S, v, m) {
  free_cap <- S$params$van_capacity - S$v_load[v]
  if (free_cap <= 0) return(NULL)
  reserved <- sim_reserved(S)
  open <- S$renting & S$returning
  risk <- predictive_risk(S$risk, m, S$bikes)
  thr <- S$params$risk_threshold
  need_bikes <- open & !reserved & risk$rent >= thr
  need_docks <- open & !reserved & risk$ret >= thr
  if (!any(need_bikes | need_docks)) return(NULL)
  severity <- ifelse(open, pmax(risk$rent, risk$ret), 0)
  mv <- sim_plan_moves(S, v, reserved, severity)
  hit <- which(mv$to_station %in% S$ids[need_bikes] | mv$from_station %in% S$ids[need_docks])
  if (length(hit) == 0) return(NULL)
  list(from = match(mv$from_station[hit[1]], S$ids), to = match(mv$to_station[hit[1]], S$ids),
       planned = mv$quantity[hit[1]])
}

# Test-only policy "scripted": the rows of `script` (minute, from, to, quantity) are handed out in order.
sim_scripted_choice <- function(S, m) {
  due <- which(!S$script_used & S$script$minute <= m)
  if (length(due) == 0) return(NULL)
  r <- due[1]
  S$script_used[r] <- TRUE
  list(from = match(S$script$from[r], S$ids), to = match(S$script$to[r], S$ids),
       planned = S$script$quantity[r])
}

sim_dispatch <- function(S, m, policy) {
  tried_free <- numeric(0)       # a van with the same free capacity would get the same answer
  for (v in seq_len(S$n_vans)) {
    if (S$v_phase[v] != "idle" || S$v_free_at[v] > m + 1e-9) next
    free_cap <- S$params$van_capacity - S$v_load[v]
    if (policy %in% c("reactive", "predictive") && free_cap %in% tried_free) next
    task <- switch(policy, scripted = sim_scripted_choice(S, m), reactive = sim_reactive_choice(S, v),
                   predictive = sim_predictive_choice(S, v, m))
    if (is.null(task)) tried_free <- c(tried_free, free_cap) else sim_start_task(S, v, m, task)
  }
}

#' Failure episodes of a station x minute table of "either unusable" flags.
#' An onset is a usable minute followed by an unusable one. Recovery time = minutes from the onset
#' minute to the first usable minute again. A station already unusable at 07:00 has no onset; an
#' episode still open at 10:00 is censored (counted, not averaged).
#' Output: list(durations, n_onsets, n_censored).
recovery_episodes <- function(unusable) {
  durations <- numeric(0)
  censored <- 0
  for (i in seq_len(nrow(unusable))) {
    u <- unusable[i, ]
    onset <- which(u[-1] & !u[-length(u)]) + 1
    for (o in onset) {
      back <- which(!u[o:length(u)])
      if (length(back) == 0) censored <- censored + 1 else durations <- c(durations, back[1] - 1)
    }
  }
  list(durations = durations, n_onsets = length(durations) + censored, n_censored = censored)
}

#' Run ONE policy on ONE rider stream.
#' policy: "none" (no vans dispatched), "reactive" (see sim_reactive_choice), "predictive" (see
#'         sim_predictive_choice; needs `risk`) or "scripted" (tests).
#' Input : world (sim_world), stream (make_demand_stream), params (sim_params),
#'         risk = predictive_risk_table(world, lambda), only for the "predictive" policy.
#' Order inside minute m: record the state of [m, m+1); dispatch idle vans; van events before m+0.5;
#'         the minute's rider events (in stream order); van events before m+1.
#' Metrics: either_min = station-minutes with a rent- or return-unusable state (4.1) summed over the
#'         180 minutes (PRIMARY); fail_prop = failed attempts / attempts; van_km; recovery (above).
#' Output: list with those metrics, tasks (one row per van task, with actual_quantity), final state,
#'         conserved (the invariant held at every event), total0, n_events, log (if keep_log).
run_policy <- function(world, stream, policy = c("none", "reactive", "predictive", "scripted"), params = sim_params(),
                       script = NULL, keep_log = FALSE, risk = NULL) {
  policy <- match.arg(policy)
  if (policy == "scripted" && is.null(script)) stop("policy 'scripted' needs a script.", call. = FALSE)
  if (policy == "predictive" && is.null(risk)) {
    stop("policy 'predictive' needs a risk table (predictive_risk_table).", call. = FALSE)
  }
  S <- sim_state(world, params, stream, keep_log, script, risk)
  st_idx <- match(stream$station_id, S$ids)
  if (anyNA(st_idx)) stop("the stream has a station that is not in the world.", call. = FALSE)
  first_row <- cumsum(c(1, tabulate(stream$minute + 1, SIM_N_MIN)))     # rows of minute m: first_row[m+1] ...
  for (m in 0:(SIM_N_MIN - 1)) {
    S$unusable[, m + 1] <- S$bikes == 0 | !S$renting | S$docks == 0 | !S$returning
    if (policy != "none") sim_dispatch(S, m, policy)
    sim_run_vans(S, m + 0.5)
    if (first_row[m + 2] > first_row[m + 1]) {
      for (j in first_row[m + 1]:(first_row[m + 2] - 1)) sim_rider(S, m + 0.5, st_idx[j], stream$type[j])
    }
    sim_run_vans(S, m + 1)
  }
  tasks <- if (length(S$tasks) == 0) {
    data.frame(task_id = integer(0), van = integer(0), from = character(0), to = character(0),
               planned = numeric(0), dispatch_min = numeric(0), picked = numeric(0),
               actual_quantity = numeric(0), left_on_van = numeric(0), status = character(0),
               stringsAsFactors = FALSE)
  } else {
    t <- do.call(rbind, lapply(S$tasks, function(x) as.data.frame(x[setdiff(names(x), c("from_idx", "to_idx"))],
                                                                  stringsAsFactors = FALSE)))
    t$status[!t$status %in% c("completed", "nothing_to_pick_up")] <- "unfinished at 10:00"
    t
  }
  log <- if (keep_log) {
    data.frame(time = S$log_time, event = S$log_event, station_id = S$log_station, quantity = S$log_qty,
               ok = S$log_ok, total = S$log_total, stringsAsFactors = FALSE)
  }
  rec <- recovery_episodes(S$unusable)
  list(policy = policy, either_min = sum(S$unusable), n_attempts = S$n_att, n_failed = S$n_fail,
       fail_prop = if (S$n_att > 0) S$n_fail / S$n_att else NA_real_,
       van_km = S$van_km,
       recovery_min = if (length(rec$durations) > 0) mean(rec$durations) else NA_real_,
       n_onsets = rec$n_onsets, n_censored = rec$n_censored,
       tasks = tasks, final = list(bikes = setNames(S$bikes, S$ids), van_load = S$v_load, rides = S$rides),
       conserved = S$conserved, total0 = S$total0, n_events = S$n_events, log = log)
}

# ---------------------------------------------------------------- 5. the comparison

#' Paired-difference table for ONE pair of policies. d_s = metric(first) - metric(second) for each
#' seed s, so a POSITIVE difference means the second policy has fewer minutes / failures / minutes to
#' recover (for van_km it means the second drives less; "none" never drives, so any pair with "none"
#' first gives a negative van_km difference).
#' Input : diffs = named list of numeric vectors, one per metric (see SIM_METRICS).
#' Method: qc.R paired_diff_ci. The primary metric (either_min) uses the Bonferroni family of 3,
#'         alpha = 0.05/3, i.e. a 98.333% t interval (D-4: 3 pairwise comparisons of 3 policies). Every
#'         other metric is exploratory: unadjusted 95%, labelled as such. No claim of overall 95%
#'         confidence across metrics. n < 2 -> interval NA with the message (KA-5b).
#' Output: data.frame(metric, role, n, n_missing, mean_d, ci_low, ci_high, ci_level_pct, label, note).
paired_table <- function(diffs) {
  rows <- lapply(names(diffs), function(metric) {
    primary <- metric == SIM_PRIMARY
    ci <- paired_diff_ci(diffs[[metric]], conf = 0.95, family_size = if (primary) SIM_PRIMARY_FAMILY else 1)
    data.frame(metric = metric, role = if (primary) "primary" else "exploratory",
               n = ci$n, n_missing = ci$n_missing, mean_d = ci$mean, ci_low = ci$lower,
               ci_high = ci$upper, ci_level_pct = 100 * ci$conf_level,
               label = if (primary) "primary; Bonferroni family of 3 (alpha = 0.05/3)" else
                 "exploratory, not adjusted for multiple comparisons",
               note = ci$note, stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

#' The paired table for every pair: diffs_by_pair = list named "first - second" of paired_table inputs.
#' Output: paired_table rows with a `pair` column first; the primary rows (one per pair) come first.
paired_tables <- function(diffs_by_pair) {
  rows <- lapply(names(diffs_by_pair), function(pair) {
    t <- paired_table(diffs_by_pair[[pair]])
    cbind(data.frame(pair = pair, stringsAsFactors = FALSE), t)
  })
  all <- do.call(rbind, rows)
  all <- all[order(all$role != "primary"), ]           # stable: the pair order is kept inside each group
  rownames(all) <- NULL
  all
}

# A comparison that cannot be run: NA results that carry the reason.
sim_not_ok <- function(reason, excluded = NULL, demand_days = character(0)) {
  empty <- setNames(lapply(SIM_METRICS, function(x) numeric(0)), SIM_METRICS)
  paired <- paired_tables(setNames(rep(list(empty), length(SIM_PAIRS)),
                                   vapply(SIM_PAIRS, function(p) paste(p, collapse = " - "), "")))
  paired$note <- reason
  list(ok = FALSE, reason = reason, per_seed = NULL, summary = NULL, paired = paired, diffs = NULL,
       excluded = excluded, stations = character(0), demand_days = demand_days, seeds = integer(0),
       params = NULL, date = NA_character_)
}

#' Compare the policies "none", "reactive" and "predictive" on paired seeds for one rush window.
#' Input : sc = list(stations, attempts, tasks) from qc.R load_scenario;
#'         grids = minute grids named by date (prep.R build_day_grids, at the chosen stale_limit);
#'         date = the chosen "YYYY-MM-DD"; dates = every weekday of the scenario;
#'         n_seeds R (default 30), base_seed (seed s = base_seed + s - 1);
#'         params (sim_params, including the predictive threshold); on_progress(i, n) is called after each seed.
#' Method: demand = estimate_demand() over the weekdays STRICTLY BEFORE `date` (no look-ahead);
#'         the start state is the 07:00 state of `date` from its grid; stations whose 07:00 state is
#'         unknown, or with no known minute on earlier days, are left out and listed.
#'         Every policy gets the same start inventory, the same vans and, per seed, the SAME rider
#'         stream (made once, before any policy runs). The predictive policy is given those same rates
#'         as its forecast ("oracle rates", see predictive_risk_table).
#' Output: list(ok, reason, per_seed (one row per seed x policy), summary (per policy means, 3 rows),
#'         paired (paired_tables: 3 pairs x 4 metrics), diffs (per pair, then per metric: per-seed
#'         differences), excluded, stations, demand_days,
#'         seeds, params, date). With no earlier weekday: ok = FALSE and NA results with the reason.
compare_policies <- function(sc, grids, date, dates, n_seeds = 30, base_seed = 1,
                             params = sim_params(vans = default_van_count(sc$tasks)),
                             tz = SIM_TZ, on_progress = NULL) {
  if (!is.numeric(n_seeds) || length(n_seeds) != 1 || is.na(n_seeds) || n_seeds < 1) {
    stop("n_seeds must be a whole number of at least 1.", call. = FALSE)
  }
  n_seeds <- round(n_seeds)
  source_days <- sort(intersect(dates[dates < date], names(grids)))
  if (length(source_days) == 0) return(sim_not_ok("no earlier weekdays to estimate demand"))
  if (!date %in% names(grids)) return(sim_not_ok(paste("no minute grid for", date), demand_days = source_days))

  g0 <- grids[[date]]
  g0 <- g0[as.numeric(g0$minute) == min(as.numeric(g0$minute)), ]
  known0 <- g0$station_id[g0$known]
  all_ids <- sort(sc$stations$station_id, method = "radix")
  demand <- estimate_demand(sc$attempts, grids, source_days, all_ids, tz)
  unknown_start <- !all_ids %in% known0
  no_rate <- !unknown_start & !demand$has_rate
  excluded <- data.frame(
    station_id = c(all_ids[unknown_start], all_ids[no_rate]),
    reason = c(rep("07:00 state unknown (no valid snapshot within stale_limit)", sum(unknown_start)),
               rep("no known minute on earlier weekdays to estimate demand", sum(no_rate))),
    stringsAsFactors = FALSE)
  excluded <- excluded[order(excluded$station_id, method = "radix"), ]
  rownames(excluded) <- NULL
  use <- !unknown_start & !no_rate
  if (sum(use) < 2) return(sim_not_ok("fewer than 2 stations with a known 07:00 state and a demand rate",
                                      excluded, source_days))

  state0 <- g0[match(all_ids[use], g0$station_id), c("station_id", "bikes_available", "docks_available",
                                                     "is_renting", "is_returning")]
  world <- sim_world(state0, sc$stations)
  lambda <- demand_lambda(demand$rates[use, , , drop = FALSE])
  risk <- predictive_risk_table(world, lambda)         # once: it depends on the world and the rates, not on the seed

  seeds <- base_seed + seq_len(n_seeds) - 1
  policies <- SIM_POLICIES
  rows <- list()
  for (i in seq_along(seeds)) {
    stream <- make_demand_stream(lambda, world$ids, seeds[i])      # ONE stream, used by all policies
    for (policy in policies) {
      r <- run_policy(world, stream, policy, params, risk = risk)
      if (!r$conserved) stop("internal error: bikes were not conserved (seed ", seeds[i], ", ", policy, ").", call. = FALSE)
      rows[[length(rows) + 1]] <- data.frame(
        seed = seeds[i], policy = policy, either_min = r$either_min, fail_prop = r$fail_prop,
        van_km = r$van_km, recovery_min = r$recovery_min, n_onsets = r$n_onsets, n_censored = r$n_censored,
        n_attempts = r$n_attempts, n_tasks = nrow(r$tasks), conserved = r$conserved,
        stringsAsFactors = FALSE)
    }
    if (!is.null(on_progress)) on_progress(i, n_seeds)
  }
  per_seed <- do.call(rbind, rows)

  one <- function(p) per_seed[per_seed$policy == p, ]
  diffs <- setNames(lapply(SIM_PAIRS, function(pr) {
    setNames(lapply(SIM_METRICS, function(m) one(pr[1])[[m]] - one(pr[2])[[m]]), SIM_METRICS)
  }), vapply(SIM_PAIRS, function(pr) paste(pr, collapse = " - "), ""))
  summary <- do.call(rbind, lapply(policies, function(p) {
    x <- one(p)
    data.frame(policy = p, seeds = nrow(x), either_min = mean(x$either_min),
               fail_prop = mean(x$fail_prop, na.rm = TRUE), van_km = mean(x$van_km),
               recovery_min = if (any(!is.na(x$recovery_min))) mean(x$recovery_min, na.rm = TRUE) else NA_real_,
               recovery_seeds = sum(!is.na(x$recovery_min)), tasks = mean(x$n_tasks),
               stringsAsFactors = FALSE)
  }))
  list(ok = TRUE, reason = "", per_seed = per_seed, summary = summary, paired = paired_tables(diffs),
       diffs = diffs, excluded = excluded, stations = world$ids, demand_days = source_days,
       seeds = seeds, params = params, date = date, demand_attempts = demand$n_attempts,
       fallback_cells = demand$n_fallback_cells)
}
