# Tests for app/faulttree.R (qualitative fault trees, tier 3). Known answer: docs/methods.md KA-10.
source(testthat::test_path("..", "app", "faulttree.R"), local = TRUE)

t0 <- as.POSIXct("2026-10-05 07:00:00", tz = "America/New_York")

# n failed attempts of one type, one per minute (07:00, 07:01, ...), at station S1
fails <- function(reasons, type = "rent", station = "S1") {
  data.frame(attempt_type = type, success = FALSE, failure_reason = reasons, station_id = station,
             timestamp = t0 + 60 * (seq_along(reasons) - 1) + 30, stringsAsFactors = FALSE)
}
ok_rows <- function(n, type = "rent") {
  d <- data.frame(attempt_type = type, success = TRUE, failure_reason = NA_character_, station_id = "S1",
                  timestamp = t0 + 600, stringsAsFactors = FALSE)
  d <- d[rep(1, n), ]                            # n copies (n = 0 gives an empty table)
  d$timestamp <- t0 + 600 + 60 * seq_len(n)
  d
}
# a grid for S1, 07:00 .. 07:19; bikes/docks given per minute, known flags optional
grid_of <- function(bikes, docks = 10 - bikes, known = rep(TRUE, length(bikes))) {
  data.frame(station_id = "S1", minute = t0 + 60 * (seq_along(bikes) - 1), known = known,
             bikes_available = ifelse(known, bikes, NA), docks_available = ifelse(known, docks, NA),
             stringsAsFactors = FALSE)
}
ka10 <- fails(c(rep("no_bike", 6), rep("dock_fault", 3), "app_error"))

test_that("KA-10: 6 no_bike, 3 dock_fault, 1 app_error -> 60% / 30% / 10%, no contradiction", {
  g <- grid_of(rep(0, 20))                       # every minute really has 0 bikes
  r <- fault_tree(ka10, "rent", g)
  expect_equal(r$n_failed, 10)
  expect_equal(r$by_action$count, c(6, 3, 1))
  expect_equal(r$by_action$share, c(0.6, 0.3, 0.1))
  expect_equal(r$by_action$action, c("rebalancing", "maintenance", "data check"))
  expect_equal(r$reclassified, 0)
  expect_equal(r$not_checked, 0)
  expect_equal(r$checked, 6)
})

test_that("KA-10 variant: one no_bike falls in a minute with bikes > 0 -> 50% / 30% / 20%", {
  b <- rep(0, 20); b[3] <- 4                     # minute 07:02 shows 4 bikes; ka10 row 3 is a no_bike at 07:02:30
  r <- fault_tree(ka10, "rent", grid_of(b))
  expect_equal(r$by_action$count, c(5, 3, 2))
  expect_equal(r$by_action$share, c(0.5, 0.3, 0.2))
  expect_equal(r$reclassified, 1)
  expect_equal(r$logged_by_action$count, c(6, 3, 1))   # the logged view is kept for comparison
  expect_true(any(grepl("reclassified", r$tree$leaf)))
})

test_that("the return side uses the symmetric rule (no_dock with docks > 0 -> data check)", {
  x <- fails(c("no_dock", "no_dock", "dock_fault", "app_error"), "return")
  g <- grid_of(bikes = rep(5, 20), docks = c(0, 3, 0, 0, rep(0, 16)))   # minute 1 (07:01) has 3 docks
  r <- fault_tree(x, "return", g)
  expect_equal(r$by_action$count, c(1, 1, 2))
  expect_equal(r$reclassified, 1)
  # a rent-side no_dock-like check must not touch return: bikes > 0 does not matter for returns
  g2 <- grid_of(bikes = rep(5, 20), docks = rep(0, 20))
  expect_equal(fault_tree(x, "return", g2)$reclassified, 0)
})

test_that("an unknown minute is NOT reclassified and is counted as could not be checked", {
  x <- fails(c("no_bike", "no_bike", "no_bike"))
  b <- c(5, 5, 5, rep(0, 17))
  known <- c(TRUE, FALSE, TRUE, rep(TRUE, 17))   # minute 07:01 is unknown / stale
  r <- fault_tree(x, "rent", grid_of(b, known = known))
  expect_equal(r$reclassified, 2)                # 07:00 and 07:02 contradict
  expect_equal(r$not_checked, 1)
  expect_equal(r$by_action$count, c(1, 0, 2))    # the unchecked one keeps its logged reason: rebalancing
})

test_that("an attempt outside the grid cannot be checked; no grid means no reclassification", {
  late <- fails("no_bike"); late$timestamp <- t0 + 3 * 3600
  r <- fault_tree(late, "rent", grid_of(rep(5, 20)))
  expect_equal(r$not_checked, 1); expect_equal(r$reclassified, 0)
  r2 <- fault_tree(ka10, "rent", NULL)
  expect_false(r2$rule_applied)
  expect_equal(r2$by_action$share, c(0.6, 0.3, 0.1))
  expect_equal(r2$reclassified, 0)
})

test_that("zero failures: counts 0, shares NA with a reason, failed share 0 with n shown", {
  r <- fault_tree(ok_rows(5), "rent", grid_of(rep(0, 20)))
  expect_equal(r$n, 5); expect_equal(r$n_failed, 0); expect_equal(r$failed_share, 0)
  expect_equal(r$by_action$count, c(0, 0, 0))
  expect_true(all(is.na(r$by_action$share)))
  expect_true(all(is.na(r$by_reason$share)))
  expect_match(r$shares_reason, "no failures observed does not mean zero risk")
  expect_equal(nrow(r$tree), 0)
})

test_that("n = 0 attempts: the failed share is NA with a reason", {
  r <- fault_tree(ok_rows(0), "rent", NULL)
  expect_equal(r$n, 0)
  expect_true(is.na(r$failed_share))
  expect_match(r$failed_share_reason, "no attempts")
  expect_true(all(is.na(r$by_action$share)))
})

test_that("every code maps to the right action", {
  expect_equal(cause_action(c("no_bike", "no_dock", "bike_fault", "dock_fault", "station_closed", "app_error")),
               c("rebalancing", "rebalancing", "maintenance", "maintenance", "maintenance", "data check"))
  expect_error(cause_action("flat_tyre"), "unknown failure_reason")
  r <- fault_tree(fails(c("bike_fault", "station_closed", "dock_fault")), "rent", NULL)
  expect_equal(r$by_action$count, c(0, 3, 0))
  rr <- fault_tree(fails(c("no_dock", "station_closed"), "return"), "return", NULL)
  expect_equal(rr$by_action$count, c(1, 1, 0))
})

test_that("failed share is failed / n and only the chosen type is used", {
  a <- rbind(ka10, ok_rows(10), fails("no_dock", "return"))
  r <- fault_tree(a, "rent", NULL)
  expect_equal(r$n, 20); expect_equal(r$n_failed, 10); expect_equal(r$failed_share, 0.5)
})

test_that("per-station causes: counts by action and the top cause", {
  x <- rbind(fails(c("no_bike", "no_bike", "dock_fault"), station = "S1"),
             fails(c("dock_fault", "no_bike"), station = "S2"),
             fails("app_error", station = "S3"))
  s <- fault_tree_by_station(x, "rent", NULL)
  expect_equal(s$station_id, c("S1", "S2", "S3"))
  expect_equal(s$top_cause, c("rebalancing", "tie: rebalancing / maintenance", "data check"))
  expect_equal(nrow(fault_tree_by_station(ok_rows(2), "rent", NULL)), 0)
})

# ---- prep.R helpers (scope and wording only)
local({
  source(testthat::test_path("..", "app", "prep.R"), local = TRUE)
  source(testthat::test_path("..", "app", "plots.R"), local = TRUE)
  test_that("scope_attempts keeps only the 07:00-10:00 window of the chosen dates", {
    a <- fails(c("no_bike", "no_bike"))
    a$timestamp <- as.POSIXct(c("2026-10-05 07:30:00", "2026-10-05 10:00:00"), tz = "America/New_York")
    expect_equal(nrow(scope_attempts(a, "2026-10-05")), 1)     # 10:00 is outside [07:00, 10:00)
    expect_equal(nrow(scope_attempts(a, "2026-10-06")), 0)
    expect_equal(nrow(scope_attempts(a, character(0))), 0)
  })
  test_that("display helpers show n/a for undefined shares and the plot builds", {
    r <- fault_tree(ok_rows(3), "rent", NULL)
    expect_equal(fault_action_display(r)[[3]], rep("n/a (0)", 3))
    expect_match(fault_summary_text(r), "0 of 3 attempts failed [(]0.0%[)]")
    expect_s3_class(plot_fault_tree(r, "x"), "ggplot")
    r2 <- fault_tree(ka10, "rent", grid_of(rep(0, 20)))
    expect_equal(fault_action_display(r2)[[3]], c("60.0% (6)", "30.0% (3)", "10.0% (1)"))
    expect_s3_class(plot_fault_tree(r2, "x"), "ggplot")
  })
})

test_that("fault_station_display prints the per-station counts as whole numbers", {
  source(testthat::test_path("..", "app", "prep.R"), local = TRUE)
  st <- data.frame(station_id = c("S1", "S2"), n_failed = c(334, 2), rebalancing = c(334, 0),
                   maintenance = c(0, 2), `data check` = c(0, 0), top_cause = c("rebalancing", "maintenance"),
                   check.names = FALSE, stringsAsFactors = FALSE)
  d <- fault_station_display(st)
  expect_identical(d[["failed attempts"]], c(334L, 2L))
  expect_identical(d$rebalancing, c(334L, 0L))
  expect_identical(d[["data check"]], c(0L, 0L))
})
