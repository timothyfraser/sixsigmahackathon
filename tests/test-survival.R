# Tests for app/survival.R (historical Kaplan-Meier time to first service failure).
# Known answer: docs/methods.md KA-8. The 'survival' package is used here ONLY as an
# independent cross-check; the app code does not use it.
source(testthat::test_path("..", "app", "survival.R"), local = TRUE)

# A hand-made one-station grid in the shape of qc.R build_grid output (180 minutes).
# `states` is a string, one letter per minute from 07:00; missing minutes at the end are usable.
#   u = known and usable, x = unknown, R = rent-unusable, T = return-unusable, B = both
hand_grid <- function(states, id = "S1") {
  s <- strsplit(states, "")[[1]]
  s <- c(s, rep("u", 180 - length(s)))
  data.frame(station_id = id, minute = .POSIXct(1.7e9 + 60 * (0:179), tz = "America/New_York"),
             known = s != "x",
             rent_unusable = ifelse(s == "x", NA, s %in% c("R", "B")),
             return_unusable = ifelse(s == "x", NA, s %in% c("T", "B")),
             either_unusable = ifelse(s == "x", NA, s != "u"),
             stringsAsFactors = FALSE)
}

# KA-8 data: 5, 8 (censored), 12, 15 (censored), 20
ka8_time <- c(5, 8, 12, 15, 20)
ka8_event <- c(1, 0, 1, 0, 1)

test_that("KA-8: S, F, RMST to 30 and MTTF match the hand answer", {
  fit <- km_fit(ka8_time, ka8_event)
  expect_equal(fit$time, c(5, 12, 20))
  expect_near(fit$surv[1], 0.8)
  expect_near(fit$surv[2], 0.5333333)
  expect_equal(fit$surv[3], 0)
  s <- km_summary(ka8_time, ka8_event, horizons = c(10, 20, 30), tau = 30)
  expect_near(s$horizons$F[s$horizons$t == 10], 0.2)
  expect_near(s$horizons$F[s$horizons$t == 20], 1)   # S(20) = 0 (event at 20 is included)
  expect_near(s$horizons$F[s$horizons$t == 30], 1.0)
  expect_near(s$rmst, 14.867, tol = 5e-4)
  expect_near(s$mttf, 14.867, tol = 5e-4)            # the curve reaches 0, so MTTF = full area
  expect_equal(c(s$n, s$events, s$censored), c(5, 3, 2))
})

test_that("MTTF is NA with the stated reason when the largest time is censored", {
  s <- km_summary(c(5, 8, 12, 15), c(1, 0, 1, 0), tau = 15)
  expect_true(is.na(s$mttf))
  expect_match(s$mttf_note, "the curve does not reach 0 (largest time is censored): MTTF is not estimable; use the RMST to 180 min instead (shown when it is estimable)",
               fixed = TRUE)
  expect_false(is.na(s$rmst))
})

test_that("RMST is NA (with a reason) when tau is beyond the data and the curve has not reached 0", {
  s <- km_summary(c(5, 8, 12, 15), c(1, 0, 1, 0), tau = 180)
  expect_true(is.na(s$rmst))
  expect_match(s$rmst_note, "beyond the largest observed time")
})

test_that("ties: events come before censorings at the same time", {
  # at t = 5: 4 at risk (the censored one at 5 still counts), 2 events -> S = 0.5
  fit <- km_fit(c(5, 5, 5, 10), c(1, 0, 1, 1))
  expect_equal(fit$n_risk, c(4, 1))
  expect_equal(fit$n_event, c(2, 1))
  expect_near(fit$surv[1], 0.5)
  expect_equal(fit$surv[2], 0)
})

test_that("the first unusable interval [07:05, 07:06) has time 5 and is an event", {
  o <- station_day_obs(hand_grid("uuuuuR"))$obs
  expect_equal(o$time, 5)
  expect_equal(o$event, 1)
})

test_that("an unknown minute before the first failure censors at the START of the gap", {
  # usable 07:00-07:03, unknown 07:04, unusable 07:05 -> censored at 4, not an event at 5
  o <- station_day_obs(hand_grid("uuuuxR"))$obs
  expect_equal(o$time, 4)
  expect_equal(o$event, 0)
  expect_equal(o$end, "unknown gap")
})

test_that("never failing is censored at 180 (10:00)", {
  o <- station_day_obs(hand_grid("uuu"))$obs
  expect_equal(c(o$time, o$event), c(180, 0))
  expect_equal(o$end, "end of window")
})

test_that("stations unknown or unusable at 07:00 give no observation and are counted by reason", {
  grid <- rbind(hand_grid("xuuu", "A"), hand_grid("Ruuu", "B"), hand_grid("uuRu", "C"))
  r <- station_day_obs(grid)
  expect_equal(r$obs$station_id, "C")
  expect_equal(r$obs$time, 2)
  expect_equal(r$excluded$station_id, c("A", "B"))
  expect_equal(r$excluded$reason, c("unknown at 07:00", "unusable at 07:00"))
})

test_that("failure type selects which unusable minute is the event", {
  g <- hand_grid("uuTuuR")             # return-unusable at 2, rent-unusable at 5
  expect_equal(station_day_obs(g, "either")$obs$time, 2)
  expect_equal(station_day_obs(g, "return")$obs$time, 2)
  r <- station_day_obs(g, "rent")$obs
  expect_equal(c(r$time, r$event), c(5, 1))
  expect_error(station_day_obs(g, "banana"), "failure")
})

test_that("no usable 07:00 start gives NA estimates with a reason", {
  grid <- rbind(hand_grid("xuu", "A"), hand_grid("Ruu", "B"))
  h <- km_history(list("2026-10-05" = grid), "2026-10-05")
  expect_equal(h$summary$n, 0)
  expect_true(is.na(h$summary$rmst))
  expect_true(is.na(h$summary$mttf))
  expect_true(all(is.na(h$summary$horizons$F)))
  expect_match(h$summary$reason, "no station-day is usable at 07:00: no observation to estimate from", fixed = TRUE)
  expect_equal(c(h$counts$excl_unknown, h$counts$excl_unusable), c(1, 1))
  s0 <- km_summary(numeric(0), numeric(0))
  expect_true(is.na(s0$rmst))
})

test_that("all censored: S = 1, F = 0 shown, a note, MTTF NA, RMST = tau", {
  s <- km_summary(c(180, 180, 180), c(0, 0, 0), tau = 180)
  expect_equal(nrow(s$fit), 0)
  expect_equal(s$horizons$F, c(0, 0, 0))
  expect_true(all(is.na(s$horizons$F_low)))
  expect_match(s$notes[1], "no failures observed in these 3 station-days; this does not show the risk is zero",
               fixed = TRUE)
  expect_true(is.na(s$mttf))
  expect_equal(s$rmst, 180)
})

test_that("n = 1: the estimate is shown, the interval where undefined is NA", {
  s <- km_summary(7, 1, tau = 30)
  expect_equal(s$horizons$F[s$horizons$t == 10], 1)
  expect_true(is.na(s$horizons$F_low[1]))
  expect_equal(s$mttf, 7)
  s2 <- km_summary(7, 0, tau = 7)
  expect_true(is.na(s2$horizons$F[1]))                # t = 10 is beyond the only observed time (7)
  expect_match(s2$horizons$note[1], "beyond the largest observed time")
  expect_equal(s2$rmst, 7)
})

test_that("Greenwood log-log interval agrees with survival::survfit", {
  skip_if_not_installed("survival")
  time <- c(3, 5, 5, 8, 9, 12, 12, 14, 20, 25)
  event <- c(1, 1, 0, 1, 0, 1, 1, 0, 1, 0)
  fit <- km_fit(time, event, conf = 0.95)
  sf <- survival::survfit(survival::Surv(time, event) ~ 1, conf.type = "log-log")
  ss <- summary(sf, times = fit$time)
  expect_equal(fit$surv, ss$surv, tolerance = 1e-9)
  expect_equal(fit$ci_low, ss$lower, tolerance = 1e-6)
  expect_equal(fit$ci_high, ss$upper, tolerance = 1e-6)
  expect_equal(fit$n_risk, ss$n.risk)
})

test_that("when everyone still at risk fails, the interval is NA with a reason, never Inf", {
  fit <- km_fit(ka8_time, ka8_event)
  expect_equal(fit$surv[3], 0)
  expect_true(is.na(fit$ci_low[3]) && is.na(fit$ci_high[3]))
  expect_match(fit$ci_note[3], "Greenwood")
  expect_false(any(is.infinite(unlist(fit[sapply(fit, is.numeric)]))))
  s <- km_summary(ka8_time, ka8_event, tau = 30)
  expect_true(is.na(s$horizons$F_low[s$horizons$t == 30]))
  expect_true(nzchar(s$horizons$note[s$horizons$t == 30]))
})

test_that("RMST agrees with survival's restricted mean on a random example", {
  skip_if_not_installed("survival")
  set.seed(42)
  time <- sample(1:60, 40, replace = TRUE)
  event <- rbinom(40, 1, 0.6)
  tau <- 40
  s <- km_summary(time, event, tau = tau)
  sf <- survival::survfit(survival::Surv(time, event) ~ 1)
  rm <- summary(sf, rmean = tau)$table[["rmean"]]
  expect_equal(s$rmst, rm, tolerance = 1e-9)
})

test_that("bad input stops with a clear error", {
  expect_error(km_fit(c(1, 2), c(1)), "same length")
  expect_error(km_fit(c(1, NA), c(1, 0)), "missing")
  expect_error(km_fit(c(1, 2), c(1, 2)), "0 or 1")
})

# ---- display helpers (app/prep.R): wording and day picking only
source(testthat::test_path("..", "app", "prep.R"), local = TRUE)

test_that("km_days picks all weekdays, or those up to and including the chosen date", {
  d <- c("2026-10-05", "2026-10-06", "2026-10-07")
  expect_equal(km_days(d, "all", "2026-10-06"), d)
  expect_equal(km_days(d, "upto", "2026-10-06"), d[1:2])
})

test_that("the display tables carry the counts, the reasons and n/a instead of numbers", {
  grids <- list("2026-10-05" = rbind(hand_grid("uuuuuR", "A"), hand_grid("xuu", "B"), hand_grid("uuxR", "C"), hand_grid("uuu", "D")))
  h <- km_history(grids, "2026-10-05")
  ct <- km_counts_table(h)
  expect_equal(ct$count, c(1, 3, 1, 1, 1, 1, 0))     # days, n, events, end, gap, unknown, unusable
  mt <- km_mean_table(h$summary)
  expect_equal(mt$value[2], "n/a")
  expect_match(mt$reason_if_not_reported[2], "does not reach 0")
  ht <- km_horizon_table(h$summary)
  expect_equal(nrow(ht), 3)
  pd <- km_plot_data(h)
  expect_equal(nrow(pd$curve), 181)
  expect_equal(pd$ticks$t, c(2, 180))
})
