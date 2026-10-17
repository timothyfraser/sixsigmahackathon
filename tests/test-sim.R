# Tests for app/sim.R (H-10): the seeded policy simulation.
# Known answers: KA-4b (van meets a station that filled up), KA-5 and KA-5b (paired intervals).
# Also: bike conservation at every event, same seed -> identical output, "none" never moves a
# bike, both policies see the same rider stream, demand rates never look ahead, and the
# degenerate cases (no earlier weekday, one seed).
# helper-qc.R has already loaded app/qc.R.
source(testthat::test_path("..", "app", "sim.R"), local = TRUE)

# ---------------------------------------------------------------- small builders

mini_stations <- function(ids, cap, lat, lon) {
  data.frame(station_id = ids, latitude = lat, longitude = lon, capacity = cap,
             stringsAsFactors = FALSE)
}
# A world (the 07:00 state) from a stations table and a bikes vector; every station open.
mini_world <- function(stations, bikes, renting = TRUE, returning = TRUE) {
  sim_world(data.frame(station_id = stations$station_id, bikes_available = bikes,
                       docks_available = stations$capacity - bikes,
                       is_renting = renting, is_returning = returning,
                       stringsAsFactors = FALSE), stations)
}
# The same rate for every station, type and 15-minute bin.
flat_rate <- function(n_stations, rent, ret) {
  r <- array(0, c(n_stations, 2, 12))
  r[, 1, ] <- rent
  r[, 2, ] <- ret
  r
}

# ---------------------------------------------------------------- KA-4b

test_that("KA-4 plan then KA-4b: the van meets a station that filled up, bikes are conserved", {
  st <- mini_stations(c("A", "B"), c(20, 20), c(42.440, 42.445), c(-76.50, -76.50))
  world <- mini_world(st, c(18, 1))
  # KA-4: surplus 8 at A, deficit 9 at B -> move min(8, 9, 19, 12) = 8 from A to B
  plan <- rebalance_plan(data.frame(station_id = c("A", "B"), bikes_available = c(18, 1),
                                    docks_available = c(2, 19), is_renting = TRUE,
                                    is_returning = TRUE), st, target_fill = 0.5, van_capacity = 12)
  expect_equal(plan$moves$from_station, "A")
  expect_equal(plan$moves$to_station, "B")
  expect_equal(plan$moves$quantity, 8)

  # KA-4b: riders return 15 bikes to B in minute 0 (B = 16, 4 free docks); the van is sent at minute 1
  stream <- data.frame(minute = rep(0L, 15), station_id = "B", type = "return",
                       stringsAsFactors = FALSE)
  script <- data.frame(minute = 1, from = "A", to = "B", quantity = 8, stringsAsFactors = FALSE)
  p <- sim_params(vans = 1, van_capacity = 12)
  res <- run_policy(world, stream, "scripted", p, script = script, keep_log = TRUE)

  expect_equal(nrow(res$tasks), 1)
  expect_equal(res$tasks$planned, 8)
  expect_equal(res$tasks$picked, 8)             # A: 18 -> 10 at the pickup event
  expect_equal(res$tasks$actual_quantity, 4)    # B: 16 -> 20 at the drop-off event
  expect_equal(res$tasks$left_on_van, 4)        # the van keeps 4
  expect_equal(res$final$bikes, c(A = 10, B = 20))
  expect_equal(res$final$van_load, 4)
  expect_equal(res$final$rides, 0)
  # bikes in stations + on vans + on rides: 18 + 1 + 15 = 34 before and 10 + 20 + 4 + 0 = 34 after
  expect_equal(res$total0, 34)
  expect_equal(res$final$bikes[["A"]] + res$final$bikes[["B"]] + res$final$van_load + res$final$rides, 34)
  expect_true(all(res$log$total == 34))
  # the log shows the pickup at A (10 left) and the drop-off at B before the totals are checked
  expect_equal(res$log$event[res$log$event %in% c("pickup", "dropoff")], c("pickup", "dropoff"))
})

test_that("pickup and drop-off amounts follow methods 4.4", {
  expect_equal(van_pickup_amount(planned = 8, bikes_at_source = 18, van_free = 12), 8)
  expect_equal(van_pickup_amount(planned = 8, bikes_at_source = 5, van_free = 12), 5)
  expect_equal(van_pickup_amount(planned = 8, bikes_at_source = 18, van_free = 3), 3)
  expect_equal(van_dropoff_amount(van_load = 8, free_docks = 4), 4)
  expect_equal(van_dropoff_amount(van_load = 2, free_docks = 4), 2)
})

# ---------------------------------------------------------------- conservation, seeds, policies

six <- mini_stations(paste0("S", 1:6), rep(10, 6), 42.44 + 0.004 * (1:6), -76.50 + 0.002 * (1:6))
six_world <- mini_world(six, c(0, 10, 5, 1, 9, 5))     # empty, full, balanced, near-empty, near-full
six_rate <- flat_rate(6, rent = 0.25, ret = 0.25)
six_lambda <- demand_lambda(six_rate)

test_that("the same seed gives the same stream, a different seed a different one", {
  a <- make_demand_stream(six_lambda, six_world$ids, seed = 7)
  b <- make_demand_stream(six_lambda, six_world$ids, seed = 7)
  c2 <- make_demand_stream(six_lambda, six_world$ids, seed = 8)
  expect_identical(a, b)
  expect_false(identical(a, c2))
  expect_true(all(a$minute >= 0 & a$minute < 180))
  expect_false(is.unsorted(a$minute))
})

test_that("bikes are conserved at every event, for both policies and several seeds", {
  p <- sim_params(vans = 2, van_capacity = 6)
  moved_somewhere <- FALSE
  for (seed in 1:3) {
    stream <- make_demand_stream(six_lambda, six_world$ids, seed)
    for (policy in c("none", "reactive")) {
      r <- run_policy(six_world, stream, policy, p, keep_log = TRUE)
      expect_true(r$conserved)
      expect_true(all(r$log$total == r$total0))
      expect_equal(nrow(r$log), r$n_events)
      expect_true(r$n_events >= nrow(stream))     # every rider event is logged
      if (policy == "reactive" && nrow(r$tasks) > 0) moved_somewhere <- TRUE
    }
  }
  expect_true(moved_somewhere)     # the test really exercises pickups and drop-offs
})

test_that("keep_log on or off gives the same results, and a van takes more than one task", {
  # Regression: sim_pickup/sim_dropoff read t = S$v_time[v] lazily; with keep_log = FALSE it was read
  # after S$v_time[v] <- Inf, so a van never became free again (stats-reviewer, H-10).
  p <- sim_params(vans = 1, van_capacity = 6)
  for (seed in 1:3) {
    stream <- make_demand_stream(six_lambda, six_world$ids, seed)
    on <- run_policy(six_world, stream, "reactive", p, keep_log = TRUE)
    off <- run_policy(six_world, stream, "reactive", p, keep_log = FALSE)
    expect_equal(off$either_min, on$either_min)
    expect_equal(off$van_km, on$van_km)
    expect_equal(off$n_failed, on$n_failed)
    expect_equal(nrow(off$tasks), nrow(on$tasks))
    expect_equal(off$final, on$final)
  }
  r <- run_policy(six_world, make_demand_stream(six_lambda, six_world$ids, 1), "reactive", p)
  expect_gt(nrow(r$tasks), 1)                       # the single van was re-dispatched
  expect_true(all(is.finite(r$tasks$dispatch_min)))
})

test_that("same seed and policy give identical output", {
  p <- sim_params(vans = 2, van_capacity = 6)
  stream <- make_demand_stream(six_lambda, six_world$ids, 11)
  one <- run_policy(six_world, stream, "reactive", p, keep_log = TRUE)
  two <- run_policy(six_world, stream, "reactive", p, keep_log = TRUE)
  expect_identical(one, two)
})

test_that("policy none never moves a bike and the vans never leave", {
  stream <- make_demand_stream(six_lambda, six_world$ids, 5)
  r <- run_policy(six_world, stream, "none", sim_params(vans = 2), keep_log = TRUE)
  expect_equal(nrow(r$tasks), 0)
  expect_equal(r$van_km, 0)
  expect_false(any(r$log$event %in% c("pickup", "dropoff")))
  expect_equal(r$final$van_load, c(0, 0))
})

test_that("both policies see the identical rider events for one seed (paired streams)", {
  p <- sim_params(vans = 2, van_capacity = 6)
  stream <- make_demand_stream(six_lambda, six_world$ids, 3)
  a <- run_policy(six_world, stream, "none", p, keep_log = TRUE)$log
  b <- run_policy(six_world, stream, "reactive", p, keep_log = TRUE)$log
  rider <- function(l) {
    r <- l[grepl("^rider", l$event), c("time", "event", "station_id")]
    rownames(r) <- NULL
    r
  }
  expect_identical(rider(a), rider(b))
  expect_equal(nrow(rider(a)), nrow(stream))
})

test_that("a closed station is never a move source or destination", {
  w <- mini_world(six, c(0, 10, 5, 1, 9, 5), renting = c(TRUE, FALSE, rep(TRUE, 4)))   # S2 not renting
  stream <- make_demand_stream(six_lambda, w$ids, 2)
  r <- run_policy(w, stream, "reactive", sim_params(vans = 2, van_capacity = 6), keep_log = TRUE)
  expect_true(r$conserved)
  expect_false("S2" %in% c(r$tasks$from, r$tasks$to))
})

# ---------------------------------------------------------------- episodes (recovery time)

test_that("recovery episodes: onset to first usable minute, unrecovered ones are censored", {
  u <- rbind(c(FALSE, TRUE, TRUE, FALSE, FALSE, TRUE, TRUE),   # onset at 2 recovers at 4 (2 min); onset at 6 never
             c(TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE))      # unusable from the start: no onset
  e <- recovery_episodes(u)
  expect_equal(e$durations, 2)
  expect_equal(e$n_censored, 1)
})

# ---------------------------------------------------------------- demand rates (no look-ahead)

day_start <- function(date) as.POSIXct(paste(date, "07:00"), tz = "America/New_York",
                                       format = "%Y-%m-%d %H:%M")
fake_grid <- function(date, ids, bikes, cap, known = TRUE) {
  do.call(rbind, lapply(seq_along(ids), function(i) {
    k <- rep_len(known[[min(i, length(known))]], 180)
    data.frame(station_id = ids[i], minute = day_start(date) + 60 * (0:179), known = k,
               bikes_available = ifelse(k, bikes[i], NA), docks_available = ifelse(k, cap[i] - bikes[i], NA),
               is_renting = ifelse(k, TRUE, NA), is_returning = ifelse(k, TRUE, NA),
               stringsAsFactors = FALSE)
  }))
}
fake_attempts <- function(date, clock, station, type, n, success = TRUE) {
  data.frame(timestamp = rep(day_start(date) + 60 * clock, n), station_id = station,
             attempt_type = type, success = success, stringsAsFactors = FALSE)
}

ids4 <- paste0("T", 1:4)
cap4 <- rep(10, 4)
days3 <- c("2026-10-05", "2026-10-06", "2026-10-07")      # Monday to Wednesday
grids3 <- setNames(lapply(days3, function(d) fake_grid(d, ids4, c(0, 10, 5, 3), cap4)), days3)
att3 <- rbind(
  fake_attempts(days3[1], 5, "T1", "rent", 3),                       # 3 rents in bin 1 on day 1
  fake_attempts(days3[2], 6, "T1", "rent", 2),                       # 2 successful + ...
  fake_attempts(days3[2], 7, "T1", "rent", 1, success = FALSE),      # ... 1 failed rent: all count
  fake_attempts(days3[1], 20, "T3", "return", 15),                   # bin 2: 15 returns on day 1
  fake_attempts(days3[3], 8, "T2", "rent", 100)                      # the CHOSEN day: must be ignored
)

test_that("demand rates = attempts / known station-minutes over earlier weekdays only", {
  d <- estimate_demand(att3, grids3, source_days = days3[1:2], station_ids = ids4)
  # T1 rent, bin 1: (3 + 3) attempts / (15 + 15) known minutes = 0.2
  expect_equal(d$rates["T1", "rent", 1], 6 / 30)
  # T3 return, bin 2: 15 attempts / 30 known minutes = 0.5
  expect_equal(d$rates["T3", "return", 2], 0.5)
  # a rate of 0 is valid
  expect_equal(d$rates["T4", "rent", 1], 0)
  # the chosen day (10-07) has 100 rents at T2 in bin 1: they must not be used
  expect_equal(d$rates["T2", "rent", 1], 0)
  expect_equal(d$source_days, days3[1:2])
  expect_true(all(d$has_rate))
})

test_that("a bin with no known minute falls back to the station's pooled rate; no known minute at all -> no rate", {
  g <- grids3
  for (k in 1:2) {   # T1 has no known minute in 07:00-07:14 on the two earlier days
    first15 <- g[[k]]$station_id == "T1" & g[[k]]$minute < day_start(days3[k]) + 15 * 60
    g[[k]]$known[first15] <- FALSE
  }
  d <- estimate_demand(att3, g, source_days = days3[1:2], station_ids = ids4)
  expect_false(anyNA(d$rates))
  # pooled T1 rent rate = 6 rent attempts / (2 days x 165 known minutes) = 6/330
  expect_equal(d$rates["T1", "rent", 1], 6 / 330)
  expect_equal(d$n_fallback_cells, 2)   # T1 rent and T1 return in bin 1
  none_known <- setNames(lapply(days3, function(dd) fake_grid(dd, ids4, c(0, 10, 5, 3), cap4,
                                                                known = c(TRUE, TRUE, TRUE, FALSE))), days3)
  d2 <- estimate_demand(att3, none_known, source_days = days3[1:2], station_ids = ids4)
  expect_equal(d2$has_rate, c(TRUE, TRUE, TRUE, FALSE))
})

# ---------------------------------------------------------------- the comparison

sc3 <- list(
  stations = mini_stations(ids4, cap4, 42.44 + 0.004 * (1:4), -76.50 + 0.002 * (1:4)),
  attempts = att3[att3$station_id != "T2" | att3$timestamp < day_start(days3[3]), ],
  tasks = data.frame(van_id = c("V1", "V2", "V1"), stringsAsFactors = FALSE)
)
# make demand big enough for something to happen: lots of earlier-day attempts at T1/T3
busy <- rbind(
  fake_attempts(days3[1], 30, "T1", "rent", 200),
  fake_attempts(days3[2], 30, "T1", "rent", 200),
  fake_attempts(days3[1], 30, "T3", "return", 200),
  fake_attempts(days3[2], 30, "T3", "return", 200)
)
sc3$attempts <- rbind(sc3$attempts, busy)

test_that("default van count = distinct van_id in the tasks, else 2", {
  expect_equal(default_van_count(sc3$tasks), 2)
  expect_equal(default_van_count(sc3$tasks[0, , drop = FALSE]), 2)
})

test_that("no earlier weekday -> NA results with the reason (degenerate case)", {
  r <- compare_policies(sc3, grids3, date = days3[1], dates = days3, n_seeds = 3)
  expect_false(r$ok)
  expect_equal(r$reason, "no earlier weekdays to estimate demand")
  expect_true(all(is.na(r$paired$mean_d)))
  expect_true(all(is.na(r$paired$ci_low)))
  expect_true(all(r$paired$note == "no earlier weekdays to estimate demand"))
  expect_null(r$per_seed)
})

test_that("a station with an unknown 07:00 state is excluded and listed with its reason", {
  g <- grids3
  g[[3]] <- fake_grid(days3[3], ids4, c(0, 10, 5, 3), cap4, known = c(TRUE, TRUE, TRUE, FALSE))
  r <- compare_policies(sc3, g, date = days3[3], dates = days3, n_seeds = 2)
  expect_true(r$ok)
  expect_equal(r$excluded$station_id, "T4")
  expect_match(r$excluded$reason, "unknown")
  expect_equal(r$stations, c("T1", "T2", "T3"))
  expect_equal(r$demand_days, days3[1:2])
})

test_that("a full comparison conserves bikes, is repeatable and pairs the seeds", {
  r1 <- compare_policies(sc3, grids3, date = days3[3], dates = days3, n_seeds = 4, base_seed = 100,
                         params = sim_params(vans = 2, van_capacity = 6))
  r2 <- compare_policies(sc3, grids3, date = days3[3], dates = days3, n_seeds = 4, base_seed = 100,
                         params = sim_params(vans = 2, van_capacity = 6))
  expect_true(r1$ok)
  expect_identical(r1, r2)
  expect_equal(nrow(r1$per_seed), 8)                          # 4 seeds x 2 policies
  expect_equal(r1$seeds, 100:103)                             # seed s = base + s - 1
  expect_true(all(r1$per_seed$conserved))
  expect_equal(r1$paired$n[r1$paired$metric == "either_min"], 4)
  # d = none - reactive, per seed, for the primary metric
  none <- r1$per_seed$either_min[r1$per_seed$policy == "none"]
  reac <- r1$per_seed$either_min[r1$per_seed$policy == "reactive"]
  expect_equal(r1$diffs$either_min, none - reac)
  expect_equal(r1$paired$mean_d[r1$paired$metric == "either_min"], mean(none - reac))
  expect_equal(r1$paired$ci_level_pct[r1$paired$metric == "either_min"], 100 * (1 - 0.05 / 3))
  expect_equal(r1$paired$ci_level_pct[r1$paired$metric == "fail_prop"], 95)
  expect_equal(r1$summary$van_km[r1$summary$policy == "none"], 0)
})

test_that("KA-5b through the comparison: one seed keeps the mean, intervals NA with the message", {
  r <- compare_policies(sc3, grids3, date = days3[3], dates = days3, n_seeds = 1, base_seed = 1)
  p <- r$paired[r$paired$metric == "either_min", ]
  expect_equal(p$n, 1)
  expect_false(is.na(p$mean_d))
  expect_true(is.na(p$ci_low) && is.na(p$ci_high))
  expect_match(p$note, "n < 2: no interval can be estimated", fixed = TRUE)
})

# ---------------------------------------------------------------- KA-5 through paired_table

test_that("KA-5: paired_table gives mean 10, Bonferroni 98.333% CI [7.199, 12.801], 95% CI [8.037, 11.963]", {
  t <- paired_table(list(either_min = c(10, 12, 8, 11, 9), fail_prop = c(10, 12, 8, 11, 9)))
  prim <- t[t$metric == "either_min", ]
  expect_near(prim$mean_d, 10)
  expect_near(prim$ci_low, 7.199)
  expect_near(prim$ci_high, 12.801)
  expect_near(prim$ci_level_pct, 98.3333, tol = 1e-3)
  expect_match(prim$label, "Bonferroni")
  sec <- t[t$metric == "fail_prop", ]
  expect_near(sec$ci_low, 8.037)
  expect_near(sec$ci_high, 11.963)
  expect_equal(sec$ci_level_pct, 95)
  expect_match(sec$label, "exploratory, not adjusted for multiple comparisons", fixed = TRUE)
})

test_that("policy_summary_display keeps 2 decimals, so the shown means differ by the shown mean difference", {
  source(testthat::test_path("..", "app", "prep.R"), local = TRUE)
  s <- data.frame(policy = c("none", "reactive"), seeds = 30, either_min = c(1936.633333, 1935.966667),
                  fail_prop = 0.2865, van_km = c(0, 3.230857), recovery_min = 4.45, recovery_seeds = 30,
                  tasks = c(0, 2), stringsAsFactors = FALSE)
  d <- policy_summary_display(s)
  expect_equal(d$mean_either_unusable_min, c(1936.63, 1935.97))
  expect_equal(round(diff(rev(d$mean_either_unusable_min)), 2), 0.66)   # within rounding of 0.67
  expect_equal(d$policy, c("none (no rebalancing)", "reactive"))
})

test_that("paired_table_display shows small differences (failed share in percentage points), NA stays NA", {
  source(testthat::test_path("..", "app", "prep.R"), local = TRUE)
  tbl <- data.frame(metric = c("either_min", "fail_prop", "van_km"), role = c("primary", "exploratory", "exploratory"),
                    n = 30, mean_d = c(3.933333, 1.317578e-4, -14.07434), ci_low = c(-2.614733, 9.129296e-6, NA),
                    ci_high = c(10.4814, 2.543864e-4, NA), ci_level_pct = c(98.33333, 95, 95),
                    label = "x", note = "", stringsAsFactors = FALSE)
  d <- paired_table_display(tbl)
  expect_equal(d$mean_difference, c("3.933", "0.01318", "-14.07"))
  expect_equal(d$CI_low[1:2], c("-2.615", "0.0009129"))
  expect_true(is.na(d$CI_low[3]))
  expect_match(d$metric[2], "percentage points", fixed = TRUE)
})
