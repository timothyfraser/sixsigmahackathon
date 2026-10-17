# Tests for app/reliability.R (empirical availability and reliability, tier 3).
# Known answer: docs/methods.md KA-9.
source(testthat::test_path("..", "app", "reliability.R"), local = TRUE)

# KA-9: usable flags over 5 minutes
A <- c(1, 1, 0, 0, 1)
B <- c(1, 0, 0, 1, 1)
C <- c(1, 1, 1, 0, 0)

test_that("KA-9 series, same minute (d = 0): 2/5 = 0.4, independence 0.36", {
  r <- reliability_summary(align_series(A, B, 0), "series", tau = 2)
  expect_equal(r$availability, 0.4)
  expect_equal(r$avail_hold, 2)
  expect_equal(r$avail_n, 5)
  expect_equal(r$independence, 0.36)
})

test_that("KA-9 series with d = 1: 0/4 = 0 (the destination is read one minute later)", {
  r <- reliability_summary(align_series(A, B, 1), "series", tau = 2)
  expect_equal(r$availability, 0)
  expect_equal(r$avail_n, 4)
  expect_equal(r$independence, 0.5 * 0.5)   # A over m = 1..4 is 2/4; B over m+1 = 2..5 is 2/4
})

test_that("KA-9 parallel A or B: availability 4/5, independence 0.84, tau = 2 reliability 2/4", {
  r <- reliability_summary(cbind(A, B), "parallel", tau = 2)
  expect_equal(r$availability, 0.8)
  expect_equal(r$independence, 0.84)
  expect_equal(r$tau, 2)
  expect_equal(r$reliability, 0.5)
  expect_equal(r$rel_hold, 2)
  expect_equal(r$rel_n, 4)
})

test_that("KA-9 2-of-3: availability 3/5, tau = 2 reliability 1/4", {
  r <- reliability_summary(cbind(A, B, C), "kofn", k = 2, tau = 2)
  expect_equal(r$availability, 0.6)
  expect_equal(r$reliability, 0.25)
  expect_equal(r$rel_n, 4)
  # independence: own availabilities A = B = C = 3/5; P(at least 2) by listing the cases
  p <- c(0.6, 0.6, 0.6)
  by_hand <- p[1] * p[2] * p[3] + p[1] * p[2] * (1 - p[3]) + p[1] * (1 - p[2]) * p[3] + (1 - p[1]) * p[2] * p[3]
  expect_equal(r$independence, by_hand)
})

test_that("unknown minutes (NA) are excluded from numerator AND denominator", {
  A2 <- c(1, NA, 0, 1, 1, 1)
  B2 <- c(1, 1, 1, NA, 0, 1)
  r <- reliability_summary(cbind(A2, B2), "series", tau = 2)
  # minutes where both known: 1, 3, 5, 6 -> both usable at 1, 6 -> 2/4
  expect_equal(r$avail_n, 4)
  expect_equal(r$availability, 0.5)
  # windows of 2 consecutive minutes with all known: only (5, 6); both TRUE? minute 5 B=0 -> FALSE
  expect_equal(r$rel_n, 1)
  expect_equal(r$reliability, 0)
})

test_that("a window needs every minute known: a gap is not bridged", {
  M <- cbind(c(1, 1, NA, 1, 1, 1))
  r <- reliability_summary(M, "parallel", tau = 2)
  expect_equal(r$rel_n, 3)       # windows (1,2), (4,5), (5,6)
  expect_equal(r$reliability, 1)
})

test_that("series with a trip time d: start minutes stop d minutes before the end", {
  o <- rep(1, 10)
  de <- rep(1, 10)
  al <- align_series(o, de, 3)
  expect_equal(nrow(al), 10)
  expect_true(all(is.na(al[8:10, 2])))
  r <- reliability_summary(al, "series", tau = 4)
  expect_equal(r$avail_n, 7)         # m = 1..7 have m + 3 <= 10
  expect_equal(r$rel_n, 4)           # windows of 4 within the 7 usable start minutes
  expect_equal(r$reliability, 1)
})

test_that("zero eligible minutes gives NA with the reason, never 0", {
  M <- cbind(rep(NA, 5), c(1, 0, 1, 1, 1))
  r <- reliability_summary(M, "parallel", tau = 2)
  expect_true(is.na(r$availability))
  expect_true(is.na(r$independence))
  expect_true(is.na(r$reliability))
  expect_match(r$avail_reason, "no minute where all stations involved are known")
  expect_match(r$rel_reason, "no minute where all stations involved are known")
})

test_that("fewer than tau eligible consecutive minutes: reliability NA with reason, availability kept", {
  r <- reliability_summary(cbind(c(1, 1, NA, 1, 1, NA, 1)), "parallel", tau = 3)
  expect_equal(r$availability, 1)
  expect_true(is.na(r$reliability))
  expect_match(r$rel_reason, "fewer than 3 consecutive")
})

test_that("k greater than n, or bad inputs, stop with a clear error", {
  expect_error(reliability_summary(cbind(A, B), "kofn", k = 3, tau = 2), "k must be")
  expect_error(reliability_summary(cbind(A, B), "kofn", k = 0, tau = 2), "k must be")
  expect_error(reliability_summary(cbind(A, B), "kofn", tau = 2), "k must be")
  expect_error(reliability_summary(cbind(A, B), "parallel", tau = 0), "tau")
  expect_error(align_series(A, B[1:3], 0), "same length")
  expect_error(align_series(A, B, -1), "d must be")
})

test_that("pooling days puts a gap between them so a window never spans two days", {
  M <- pool_days(list(cbind(c(1, 1, 1)), cbind(c(1, 1, 1))), gap = 2)
  expect_equal(nrow(M), 8)
  r <- reliability_summary(M, "parallel", tau = 3)
  expect_equal(r$rel_n, 2)       # one window per day
  expect_equal(r$avail_n, 6)
})

# A tiny hand grid in the shape of qc.R build_grid output (5 minutes, 3 stations).
hand <- function(id, rent_ok, ret_ok, known = rep(TRUE, length(rent_ok))) {
  data.frame(station_id = id, minute = .POSIXct(1.7e9 + 60 * (seq_along(rent_ok) - 1), tz = "America/New_York"),
             known = known,
             rent_unusable = ifelse(known, !rent_ok, NA),
             return_unusable = ifelse(known, !ret_ok, NA),
             either_unusable = ifelse(known, !(rent_ok & ret_ok), NA),
             stringsAsFactors = FALSE)
}

test_that("wrapper from a grid: roles (rent for the origin, return for the destination), rows in any order", {
  g <- rbind(hand("A", as.logical(A), rep(TRUE, 5)),
             hand("B", rep(TRUE, 5), as.logical(B)))
  g <- g[sample(nrow(g)), ]                       # row order must not matter
  r <- reliability_from_grid(g, "series", origin = "A", destination = "B", d = 0, tau = 2)
  expect_equal(r$availability, 0.4)
  expect_equal(r$independence, 0.36)
})

test_that("wrapper from a grid: unknown minutes of one station remove the minute for the whole structure", {
  g <- rbind(hand("A", as.logical(A), rep(TRUE, 5)),
             hand("B", c(TRUE, FALSE, TRUE, FALSE, TRUE), rep(TRUE, 5), known = c(TRUE, TRUE, FALSE, TRUE, TRUE)))
  r <- reliability_from_grid(g, "parallel", stations = c("A", "B"), usable = "rent", tau = 2)
  expect_equal(r$avail_n, 4)                      # minute 3 (B unknown) is dropped
  # A = 1,1,0,0,1 and B = 1,0,?,0,1 -> minutes 1, 2, 5 hold, minute 4 does not: 3/4
  expect_equal(r$availability, 3 / 4)
})

test_that("wrapper from a grid: kofn with usable = either, unknown station id is an error", {
  g <- rbind(hand("A", as.logical(A), rep(TRUE, 5)), hand("B", as.logical(B), rep(TRUE, 5)),
             hand("C", as.logical(C), rep(TRUE, 5)))
  r <- reliability_from_grid(g, "kofn", stations = c("A", "B", "C"), k = 2, usable = "either", tau = 2)
  expect_equal(r$availability, 0.6)
  expect_equal(r$reliability, 0.25)
  expect_error(reliability_from_grid(g, "parallel", stations = c("A", "Z"), tau = 2), "not in the grid")
})
