# Tests for app/forecast.R (H-13): current-state risk forecast, step 5a (fixed Poisson rates).
# Known answers: KA-8b (2 bikes, rent rate 0.1/min, no returns: 0.264, 0.594, 0.801) and
# KA-8c (no look-ahead). Also: stale inventory gives NA with a reason, rate 0 gives probability 0,
# vans in transit, same seed -> same output, no earlier weekday.
# helper-qc.R has already loaded app/qc.R.
source(testthat::test_path("..", "app", "sim.R"), local = TRUE)
source(testthat::test_path("..", "app", "prep.R"), local = TRUE)
source(testthat::test_path("..", "app", "forecast.R"), local = TRUE)

# ---------------------------------------------------------------- small builders

TZ <- "America/New_York"
at <- function(date, hm) as.POSIXct(paste(date, hm), tz = TZ, format = "%Y-%m-%d %H:%M")

# Cleaned status rows: one snapshot per minute 07:00..09:59 for one station, constant state.
status_day <- function(date, id, bikes, capacity = 10, renting = TRUE, returning = TRUE, until = 180) {
  ts <- at(date, "07:00") + 60 * (0:(until - 1))
  data.frame(station_id = id, timestamp = ts, bikes_available = bikes, docks_available = capacity - bikes,
             is_renting = renting, is_returning = returning, stringsAsFactors = FALSE)
}
# Rent attempts of one station on one day: `per_bin` in each 15-minute bin (at the bin's first minute).
attempts_day <- function(date, id, per_bin, type = "rent") {
  ts <- rep(at(date, "07:00") + 60 * 15 * (0:11), each = per_bin) + 10
  data.frame(timestamp = ts, station_id = id, attempt_type = type, success = TRUE, stringsAsFactors = FALSE)
}
no_tasks <- function() {
  data.frame(task_id = character(0), van_id = character(0), source_station_id = character(0),
             destination_station_id = character(0), planned_quantity = numeric(0),
             assigned_at = as.POSIXct(character(0), tz = TZ), arrived_at = as.POSIXct(character(0), tz = TZ),
             completed_at = as.POSIXct(character(0), tz = TZ), status = character(0), stringsAsFactors = FALSE)
}
stations2 <- data.frame(station_id = c("A", "B"), latitude = c(42.440, 42.450), longitude = -76.50,
                        capacity = 10, stringsAsFactors = FALSE)

# Three weekdays. A: 3 rent attempts per bin over the two source days (2 + 1) = 3 / 30 known minutes
# = 0.1 per minute. B: no attempts at all (rate 0). On the forecast day (10-07) A has 2 bikes, B has 5.
hand_scenario <- function(extra_attempts = NULL, bikes_a = 2, a_until = 180) {
  days <- c("2026-10-05", "2026-10-06", "2026-10-07")
  status <- rbind(
    do.call(rbind, lapply(days[1:2], function(d) rbind(status_day(d, "A", 5), status_day(d, "B", 5)))),
    status_day(days[3], "A", bikes_a, until = a_until), status_day(days[3], "B", 5))
  attempts <- rbind(attempts_day(days[1], "A", 2), attempts_day(days[2], "A", 1), extra_attempts)
  sc <- list(stations = stations2, attempts = attempts, tasks = no_tasks())
  grids <- build_day_grids(status, stations2, days, stale_limit = 2)
  list(sc = sc, grids = grids, dates = days)
}

# ---------------------------------------------------------------- KA-8b

test_that("KA-8b: 2 bikes, rent rate 0.1, no returns: 0.264, 0.594, 0.801 within 4 simulation SE (core)", {
  world <- list(bikes = 2, docks = 8, renting = TRUE, returning = TRUE)
  lambda <- array(0, c(30, 1, 2))
  lambda[, 1, 1] <- 0.1
  sim <- forecast_simulate(world, lambda, horizons = c(10, 20, 30), R = 20000, seed = 1)
  exact <- c(1 - 2 * exp(-1), 1 - 3 * exp(-2), 1 - 4 * exp(-3))
  expect_equal(round(exact, 3), c(0.264, 0.594, 0.801))
  expect_true(all(abs(sim$p_rent[1, ] - exact) < 4 * sim$se_rent[1, ]),
              info = paste("p =", paste(sim$p_rent[1, ], collapse = ", ")))
  expect_true(all(sim$p_return == 0))      # 8 free docks and no returns: never full
})

test_that("KA-8b through forecast_now: rates estimated from earlier days, same three values", {
  h <- hand_scenario()
  f <- forecast_now(h$sc, h$grids, "2026-10-07", h$dates, minute = 30, R = 20000, seed = 1)
  expect_true(f$ok)
  a <- f$table[f$table$station_id == "A", ]
  expect_equal(unname(f$rates["A", "rent", ]), rep(0.1, 12))
  exact <- c(1 - 2 * exp(-1), 1 - 3 * exp(-2), 1 - 4 * exp(-3))
  got <- c(a$p_rent_10, a$p_rent_20, a$p_rent_30)
  se <- c(a$se_rent_10, a$se_rent_20, a$se_rent_30)
  expect_true(all(abs(got - exact) < 4 * se), info = paste(got, collapse = ", "))
  expect_equal(f$source_days, c("2026-10-05", "2026-10-06"))
})

# ---------------------------------------------------------------- KA-8c

test_that("KA-8c: rates and forecast are identical whether or not later days' attempts exist", {
  later <- rbind(attempts_day("2026-10-07", "A", 20), attempts_day("2026-10-07", "B", 20, "return"))
  with_later <- hand_scenario(extra_attempts = later)
  without <- hand_scenario()
  # forecast on 10-07 at 07:30: the attempts of 10-07 itself (even before 07:30) must not be used
  f1 <- forecast_now(with_later$sc, with_later$grids, "2026-10-07", with_later$dates, 30, R = 500, seed = 3)
  f2 <- forecast_now(without$sc, without$grids, "2026-10-07", without$dates, 30, R = 500, seed = 3)
  expect_identical(f1$rates, f2$rates)
  expect_identical(f1$table, f2$table)
  # forecast on 10-06: remove 10-07 attempts and the 10-07 date altogether
  g <- forecast_now(with_later$sc, with_later$grids, "2026-10-06", with_later$dates, 30, R = 500, seed = 3)
  keep <- as.Date(format(with_later$sc$attempts$timestamp, "%Y-%m-%d", tz = TZ)) < as.Date("2026-10-06")
  sc_early <- with_later$sc
  sc_early$attempts <- sc_early$attempts[keep, ]
  g2 <- forecast_now(sc_early, with_later$grids, "2026-10-06", with_later$dates[1:2], 30, R = 500, seed = 3)
  expect_identical(g$rates, g2$rates)
  expect_equal(g$source_days, "2026-10-05")
})

# ---------------------------------------------------------------- degenerate and rule cases

test_that("stale inventory gives NA with a reason, never a probability", {
  h <- hand_scenario(a_until = 20)           # A's last snapshot is 07:19; at 07:30 it is 11 min old
  f <- forecast_now(h$sc, h$grids, "2026-10-07", h$dates, 30, R = 200, seed = 1)
  a <- f$table[f$table$station_id == "A", ]
  expect_false(a$known)
  expect_true(is.na(a$p_rent_10) && is.na(a$p_return_30) && is.na(a$se_rent_20))
  expect_match(a$reason, "no valid recent snapshot at t0 (stale or missing): no forecast", fixed = TRUE)
  b <- f$table[f$table$station_id == "B", ]       # B is fine and is still forecast
  expect_false(is.na(b$p_rent_10))
  # a larger stale_limit makes the same snapshot usable at 07:30 (age 11)
  g <- build_day_grids(rbind(status_day("2026-10-07", "A", 2, until = 20)), stations2, "2026-10-07", stale_limit = 15)
  expect_true(state_at(g[["2026-10-07"]], 30)$known[1])
})

test_that("rate 0 everywhere gives probability 0 with a note, not a claim of safety", {
  h <- hand_scenario()
  f <- forecast_now(h$sc, h$grids, "2026-10-07", h$dates, 30, R = 300, seed = 1)
  b <- f$table[f$table$station_id == "B", ]
  expect_equal(c(b$p_rent_10, b$p_rent_30, b$p_return_10, b$p_return_30), rep(0, 4))
  expect_match(b$flags, "does not show the risk is zero")
})

test_that("a closed or empty station states its state; closed means probability 1 by construction", {
  h <- hand_scenario(bikes_a = 0)
  f <- forecast_now(h$sc, h$grids, "2026-10-07", h$dates, 30, R = 300, seed = 1)
  expect_match(f$table$flags[f$table$station_id == "A"], "already rent-unusable at t0")
  closed <- list(bikes = 3, docks = 7, renting = FALSE, returning = TRUE)
  sim <- forecast_simulate(closed, array(0, c(30, 1, 2)), horizons = 10, R = 50, seed = 1)
  expect_equal(c(sim$p_rent, sim$se_rent), c(1, 0))
})

test_that("no earlier weekday: no forecast, with the reason", {
  h <- hand_scenario()
  f <- forecast_now(h$sc, h$grids, "2026-10-05", h$dates, 30, R = 100, seed = 1)
  expect_false(f$ok)
  expect_match(f$reason, "no earlier weekday")
  expect_true(all(is.na(f$table$p_rent_30)))
  expect_length(f$source_days, 0)
})

test_that("same seed gives identical output, another seed differs, bad inputs stop", {
  h <- hand_scenario()
  f1 <- forecast_now(h$sc, h$grids, "2026-10-07", h$dates, 30, R = 400, seed = 7)
  f2 <- forecast_now(h$sc, h$grids, "2026-10-07", h$dates, 30, R = 400, seed = 7)
  f3 <- forecast_now(h$sc, h$grids, "2026-10-07", h$dates, 30, R = 400, seed = 8)
  expect_identical(f1$table, f2$table)
  expect_false(identical(f1$table, f3$table))
  expect_error(forecast_now(h$sc, h$grids, "2026-10-07", h$dates, 30, R = 0), "R must be")
  expect_error(forecast_now(h$sc, h$grids, "2026-10-07", h$dates, 200), "minute must be")
})

test_that("a horizon that passes 10:00 is labelled", {
  h <- hand_scenario()
  f <- forecast_now(h$sc, h$grids, "2026-10-07", h$dates, 165, R = 100, seed = 1)
  expect_equal(unname(f$past_10), c(FALSE, TRUE, TRUE))
})

# ---------------------------------------------------------------- vans in transit

test_that("in transit = assigned by t0 and not completed by t0; ETA = assigned + km x detour / speed", {
  t0 <- at("2026-10-07", "07:30")
  mk <- function(id, asg, comp, status, arrived = NA) {
    data.frame(task_id = id, van_id = "V1", source_station_id = "B", destination_station_id = "A",
               planned_quantity = 5, assigned_at = asg, arrived_at = arrived, completed_at = comp,
               status = status, stringsAsFactors = FALSE)
  }
  na_t <- as.POSIXct(NA, tz = TZ)
  tasks <- rbind(
    mk("in", at("2026-10-07", "07:20"), at("2026-10-07", "07:50"), "completed", arrived = at("2026-10-07", "07:21")),
    mk("open", at("2026-10-07", "07:25"), na_t, "in_progress"),
    mk("done", at("2026-10-07", "07:00"), at("2026-10-07", "07:10"), "completed"),
    mk("later", at("2026-10-07", "07:40"), na_t, "assigned"),
    mk("cancelled", at("2026-10-07", "07:20"), na_t, "cancelled"),
    mk("planned", na_t, na_t, "planned"))
  p <- sim_params()
  it <- forecast_in_transit(tasks, stations2, t0, p)
  expect_equal(sort(it$task_id), c("in", "open"))
  km <- haversine_km(42.450, -76.50, 42.440, -76.50) * p$detour
  travel <- km / p$speed_kmh * 60
  # "in": assigned 10 min before t0; the logged arrived_at (07:21) is NOT used
  expect_equal(it$eta_min[it$task_id == "in"], -10 + travel, tolerance = 1e-9)
  expect_equal(it$eta_min[it$task_id == "open"], -5 + travel, tolerance = 1e-9)
  expect_equal(nrow(forecast_in_transit(no_tasks(), stations2, t0, p)), 0)
})

test_that("a van arriving adds bikes to the destination (capped by free docks) and removes the risk", {
  world <- list(bikes = 0, docks = 10, renting = TRUE, returning = TRUE)
  lambda <- array(0, c(30, 1, 2))
  none <- forecast_simulate(world, lambda, NULL, horizons = c(10, 20, 30), R = 20, seed = 1)
  expect_equal(none$p_rent[1, ], c(1, 1, 1))                       # empty and nobody comes
  van_now <- forecast_simulate(world, lambda, data.frame(step = 0, station = 1, qty = 5),
                               horizons = c(10, 20, 30), R = 20, seed = 1)
  expect_equal(van_now$p_rent[1, ], c(0, 0, 0))                    # in place before the first checked minute
  van_late <- forecast_simulate(world, lambda, data.frame(step = 15, station = 1, qty = 5),
                                horizons = c(10, 20, 30), R = 20, seed = 1)
  expect_equal(van_late$p_rent[1, ], c(1, 1, 1))                   # empty during 10 min, so the hit stays
  full <- list(bikes = 9, docks = 1, renting = TRUE, returning = TRUE)
  van_cap <- forecast_simulate(full, lambda, data.frame(step = 0, station = 1, qty = 5),
                               horizons = 10, R = 20, seed = 1)
  expect_equal(van_cap$p_return[1, 1], 1)                          # only 1 of 5 bikes fits: now 0 docks
})

# ---------------------------------------------------------------- step 5b: day bootstrap (H-14)

# Same scenario as hand_scenario(), but A's attempts per bin on the two source days are given.
# 3 attempts per 15-minute bin = rate 0.2 per minute, 6 = 0.4.
boot_scenario <- function(per_bin_day1, per_bin_day2) {
  h <- hand_scenario()
  h$sc$attempts <- rbind(attempts_day("2026-10-05", "A", per_bin_day1), attempts_day("2026-10-06", "A", per_bin_day2))
  h
}

test_that("counts per day add up to exactly the rates of sim.R estimate_demand", {
  h <- hand_scenario()
  ids <- c("A", "B")
  days <- c("2026-10-05", "2026-10-06")
  counts <- forecast_day_counts(h$sc$attempts, h$grids, days, ids)
  r <- forecast_rates_from_counts(apply(counts$known_min, c(2, 3), sum), apply(counts$att, c(2, 3, 4), sum))
  expect_equal(r, unname(estimate_demand(h$sc$attempts, h$grids, days, ids)$rates), ignore_attr = TRUE)
})

test_that("KA-8d: identical days give identical rate sets and a range that is exactly a point", {
  h <- boot_scenario(3, 3)
  f <- forecast_now(h$sc, h$grids, "2026-10-07", h$dates, 30, R = 2000, seed = 1,
                    bootstrap = TRUE, B = 60, R_b = 300)
  b <- f$bootstrap
  expect_true(b$ok)
  expect_true(b$sets_identical)                                   # every rate set is exactly the same
  expect_equal(unname(b$rate_sets[1, 1, 1, ]), rep(0.2, 12))
  a <- f$table[f$table$station_id == "A", ]
  expect_identical(a$boot_lo_rent_30, a$boot_hi_rent_30)          # common random numbers: a point
  expect_identical(a$boot_lo_rent_10, a$boot_hi_rent_10)
  expect_identical(a$boot_lo_return_20, a$boot_hi_return_20)
  # the 5a point estimate (R = 2000) agrees with that point within simulation error of the two runs
  expect_lt(abs(a$p_rent_30 - a$boot_lo_rent_30), 4 * sqrt(a$se_rent_30^2 + a$boot_mean_se_rent_30^2))
  # separate fields: the simulation SE and the bootstrap mean SE are different columns
  expect_true(all(c("se_rent_30", "boot_mean_se_rent_30", "boot_lo_rent_30", "boot_hi_rent_30") %in% names(f$table)))
})

test_that("days with different rates (0.2 and 0.4): rate sets take only 0.2, 0.3, 0.4 with weights 1/4, 1/2, 1/4", {
  h <- boot_scenario(3, 6)
  f <- forecast_now(h$sc, h$grids, "2026-10-07", h$dates, 30, R = 200, seed = 5,
                    bootstrap = TRUE, B = 400, R_b = 20)
  b <- f$bootstrap
  rate <- b$rate_sets[, 1, 1, 1]                                   # station A (first used), rent, bin 1
  expect_true(all(abs(rate - 0.2) < 1e-12 | abs(rate - 0.3) < 1e-12 | abs(rate - 0.4) < 1e-12))
  prop <- c(mean(abs(rate - 0.2) < 1e-12), mean(abs(rate - 0.3) < 1e-12), mean(abs(rate - 0.4) < 1e-12))
  expect_equal(prop, c(0.25, 0.5, 0.25), tolerance = 0.08, scale = 1)
  # the weights are draws of 2 days with replacement: (2,0), (1,1), (0,2)
  expect_true(all(rowSums(b$weights) == 2))
  # the range is a real range now: wider than a point, and ordered
  a <- f$table[f$table$station_id == "A", ]
  expect_gt(a$boot_hi_rent_10, a$boot_lo_rent_10)     # 30 min is saturated near 1 at these rates
})

test_that("a day drawn twice counts twice in numerator and denominator (rate of the pair, not an average of rates)", {
  # day 1: A has 3 per bin; day 2: A has 6 per bin; known minutes are equal, so weights (2,0) -> 0.2
  h <- boot_scenario(3, 6)
  counts <- forecast_day_counts(h$sc$attempts, h$grids, c("2026-10-05", "2026-10-06"), c("A", "B"))
  km <- c(2, 0) %*% matrix(counts$known_min, 2, 2 * 12)
  at <- c(2, 0) %*% matrix(counts$att, 2, 2 * 2 * 12)
  r <- forecast_rates_from_counts(array(km, c(2, 12)), array(at, c(2, 2, 12)))
  expect_equal(r[1, 1, 1], 0.2)
  expect_equal(r[2, 1, 1], 0)
})

test_that("same seed gives an identical bootstrap, another seed differs", {
  h <- boot_scenario(3, 6)
  go <- function(seed) forecast_now(h$sc, h$grids, "2026-10-07", h$dates, 30, R = 200, seed = seed,
                                    bootstrap = TRUE, B = 30, R_b = 50)
  expect_identical(go(2)$table, go(2)$table)
  expect_false(identical(go(2)$bootstrap$weights, go(3)$bootstrap$weights))
})

test_that("fewer than 2 earlier weekdays: range NA with the reason, the 5a estimate is still shown", {
  h <- hand_scenario()
  f <- forecast_now(h$sc, h$grids, "2026-10-06", h$dates, 30, R = 300, seed = 1,
                    bootstrap = TRUE, B = 20, R_b = 20)
  expect_false(f$bootstrap$ok)
  a <- f$table[f$table$station_id == "A", ]
  expect_false(is.na(a$p_rent_30))
  expect_true(is.na(a$boot_lo_rent_30) && is.na(a$boot_hi_rent_30))
  expect_equal(a$boot_reason, "fewer than 2 earlier weekdays: the day bootstrap cannot vary the rates")
  expect_match(f$uncertainty[3], "fewer than 2 earlier weekdays")
})

test_that("a stale station is NA in the bootstrap columns too", {
  h <- hand_scenario(a_until = 20)
  f <- forecast_now(h$sc, h$grids, "2026-10-07", h$dates, 30, R = 100, seed = 1, bootstrap = TRUE, B = 10, R_b = 10)
  a <- f$table[f$table$station_id == "A", ]
  expect_true(is.na(a$boot_lo_rent_30) && is.na(a$boot_hi_return_30))
  expect_false(is.na(f$table$boot_lo_rent_30[f$table$station_id == "B"]))
})

test_that("bootstrap off: the table is exactly the 5a table, and the 5a columns do not change when it is on", {
  h <- boot_scenario(3, 6)
  off <- forecast_now(h$sc, h$grids, "2026-10-07", h$dates, 30, R = 500, seed = 4)
  on <- forecast_now(h$sc, h$grids, "2026-10-07", h$dates, 30, R = 500, seed = 4, bootstrap = TRUE, B = 10, R_b = 10)
  expect_null(off$bootstrap)
  expect_false(any(grepl("^boot_", names(off$table))))
  expect_match(off$uncertainty[3], "not computed: tick the day bootstrap")
  keep <- names(off$table)
  expect_identical(on$table[keep], off$table)
  expect_identical(on$rates, off$rates)
  expect_error(forecast_now(h$sc, h$grids, "2026-10-07", h$dates, 30, bootstrap = TRUE, B = 1), "B must be")
  expect_error(forecast_now(h$sc, h$grids, "2026-10-07", h$dates, 30, bootstrap = TRUE, R_b = 0), "R_b must be")
})
