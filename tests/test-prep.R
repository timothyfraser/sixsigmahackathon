# Tests for app/prep.R (data shaping only; the statistics are tested in the other files).
# The fixture tests/fixtures/edge_small.csv, after validation, leaves:
#   S1 (capacity 10): one status row at 07:00 with 2 bikes -> known 07:00-07:02 (3 minutes)
#   S2 (capacity 20): one status row at 07:01 with 5 bikes -> known 07:01-07:03 (3 minutes)
#   attempts: A1 rent ok, A2 rent failed (the other attempt rows are rejected)
source(testthat::test_path("..", "app", "prep.R"), local = TRUE)

fx <- load_scenario(testthat::test_path("fixtures", "edge_small.csv"))
day <- "2026-10-05"   # a Monday

test_that("scenario_dates lists weekdays only, sorted", {
  expect_equal(scenario_dates(fx$status, fx$attempts), day)
  # 2026-10-10 is a Saturday: it must be dropped
  sat <- fx$status[1, ]
  sat$timestamp <- parse_ts("2026-10-10T07:00:00-04:00")
  both <- rbind(fx$status, sat)
  expect_equal(scenario_dates(both, fx$attempts), day)
  expect_equal(scenario_dates(fx$status[0, ], fx$attempts[0, ]), character(0))
})

test_that("attempts_by_day counts rows of the attempt log", {
  a <- attempts_by_day(fx$attempts, day)
  expect_equal(a$rent_n, 2)
  expect_equal(a$rent_fail, 1)
  expect_equal(a$return_n, 0)
  expect_equal(a$return_fail, 0)
})

test_that("attempts_by_day gives zeros (not NA) when there are no attempts", {
  a <- attempts_by_day(fx$attempts[0, ], c(day, "2026-10-06"))
  expect_equal(a$date, c(day, "2026-10-06"))
  expect_true(all(a$rent_n == 0 & a$rent_fail == 0 & a$return_n == 0 & a$return_fail == 0))
  expect_equal(nrow(attempts_by_day(fx$attempts, character(0))), 0)
})

test_that("attempts outside 07:00-10:00 are not counted", {
  late <- fx$attempts
  late$timestamp <- parse_ts("2026-10-05T10:00:00-04:00")   # 10:00 is outside [07:00, 10:00)
  expect_equal(attempts_by_day(late, day)$rent_n, 0)
})

test_that("fixed_station_set keeps stations with status rows on every date", {
  expect_equal(fixed_station_set(fx$status, fx$stations, day), c("S1", "S2"))
  expect_equal(fixed_station_set(fx$status, fx$stations, c(day, "2026-10-06")), character(0))
  expect_equal(fixed_station_set(fx$status, fx$stations, character(0)), character(0))
  only_s1 <- fx$status[fx$status$station_id == "S1", ]
  expect_equal(fixed_station_set(only_s1, fx$stations, day), "S1")
})

test_that("build_day_grids: known minutes on a day with data, all unknown on a day without", {
  g <- build_day_grids(fx$status, fx$stations, c(day, "2026-10-06"))
  expect_named(g, c(day, "2026-10-06"))
  expect_equal(sum(g[[day]]$known), 6)                 # 3 minutes per station
  expect_equal(nrow(g[[day]]), 2 * 180)
  expect_false(any(g[["2026-10-06"]]$known))           # no status rows that day
  expect_true(all(is.na(g[["2026-10-06"]]$either_unusable)))   # never 0/FALSE
})

test_that("window_table reports coverage and excludes low-coverage windows with a reason", {
  g <- build_day_grids(fx$status, fx$stations, c(day, "2026-10-06"))
  w <- window_table(g, c("S1", "S2"), c(day, "2026-10-06"))
  expect_equal(w$known, c(6, 0))
  expect_equal(w$unknown, c(354, 360))
  expect_equal(w$included, c(FALSE, FALSE))
  expect_match(w$reason[1], "below")
  expect_equal(nrow(window_table(g, character(0), character(0))), 0)
  # a lower minimum coverage does not change the fact that 1.7% is far below it
  expect_false(window_table(g, c("S1", "S2"), day, min_coverage = 0.5)$included)
})

test_that("set_warning_threshold recomputes early warning and keeps unknown as NA", {
  g <- build_day_grids(fx$status, fx$stations, day)[[day]]
  g1 <- set_warning_threshold(g, 1)       # S1 has 2 bikes: no longer a warning at k = 1
  expect_equal(sum(g$warn_bike, na.rm = TRUE), 3)
  expect_equal(sum(g1$warn_bike, na.rm = TRUE), 0)
  expect_true(all(is.na(g1$warn_bike[!g1$known])))
})

test_that("state_at: early warning, usable and unknown are told apart", {
  g <- build_day_grids(fx$status, fx$stations, day)[[day]]
  s1 <- state_at(g, 1)                    # 07:01
  expect_equal(s1$state[s1$station_id == "S1"], "early warning")   # 2 bikes
  expect_equal(s1$state[s1$station_id == "S2"], "usable")          # 5 bikes
  s10 <- state_at(g, 10)                  # 07:10: both stale
  expect_true(all(s10$state == "unknown / stale data"))
  expect_false(any(s10$state == "usable"))
  expect_true(all(s10$state %in% STATE_LEVELS))
})

test_that("state_at: unusable states from the flags and counts", {
  g <- build_day_grids(fx$status, fx$stations, day)[[day]]
  g$bikes_available[g$station_id == "S1" & g$known] <- 0
  g$rent_unusable <- g$bikes_available == 0
  g$docks_available[g$station_id == "S2" & g$known] <- 0
  g$return_unusable[g$station_id == "S2"] <- g$docks_available[g$station_id == "S2"] == 0
  s <- state_at(g, 1)
  expect_equal(s$state[s$station_id == "S1"], "rent-unusable")
  expect_equal(s$state[s$station_id == "S2"], "return-unusable")
  expect_equal(nrow(state_at(g[0, ], 1)), 0)
})

test_that("rank_stations: worst first, ties by station_id", {
  s <- data.frame(station_id = c("B", "A", "C"),
                  either_unusable_min = c(5, 5, 1), warn_bike_min = c(0, 0, 4),
                  warn_dock_min = c(0, 0, 0))
  r <- rank_stations(s)
  expect_equal(r$station_id, c("A", "B", "C"))   # A, B tie at 5; C = 1 + 4 = 5 too -> A, B, C by id
  expect_equal(r$rank, 1:3)
  s$warn_bike_min[3] <- 5                          # C now scores 6 and moves first
  expect_equal(rank_stations(s)$station_id, c("C", "A", "B"))
  expect_equal(nrow(rank_stations(s[0, ])), 0)
})

test_that("rank and station_table on the fixture", {
  g <- build_day_grids(fx$status, fx$stations, day)[[day]]
  r <- rank_stations(unusable_summary(g))
  expect_equal(r$station_id, c("S1", "S2"))        # S1 has 3 warning minutes, S2 none
  expect_equal(r$priority_min, c(3, 0))
  tab <- station_table(r, fx$stations)
  expect_equal(tab$known_min, c(3, 3))
  expect_equal(tab$coverage_pct, c(1.7, 1.7))
  expect_equal(tab$station, c("One", "Two"))
})

test_that("kpi_summary: counts, shares per known minute, NA when nothing to divide", {
  g <- build_day_grids(fx$status, fx$stations, day)[[day]]
  k <- kpi_summary(grid_window_counts(g), attempts_by_day(fx$attempts, day))
  expect_equal(k$known, 6)
  expect_equal(k$unknown, 354)
  expect_near(k$coverage, 6 / 360)
  expect_equal(k$either_share_pct, 0)
  expect_equal(k$rent_fail, 1)
  expect_equal(k$rent_n, 2)
  expect_equal(k$rent_fail_pct, 50)
  expect_true(is.na(k$return_fail_pct))             # 0 return attempts: no percentage
  none <- kpi_summary(grid_window_counts(g[!g$known, ]), attempts_by_day(fx$attempts[0, ], day))
  expect_true(is.na(none$either_share_pct))
  expect_true(is.na(none$rent_fail_pct))
})

test_that("hour_station_matrix sums by station and hour; empty grid is empty", {
  g <- build_day_grids(fx$status, fx$stations, day)[[day]]
  g$either_unusable[g$known] <- TRUE               # pretend every known minute is unusable
  m <- hour_station_matrix(g)
  expect_equal(nrow(m), 6)                         # 2 stations x hours 7, 8, 9
  expect_equal(m$either_unusable_min[m$station_id == "S1" & m$hour == 7], 3)
  expect_equal(m$known_min[m$station_id == "S1" & m$hour == 8], 0)
  expect_equal(nrow(hour_station_matrix(g[0, ])), 0)
})

test_that("pareto_order sorts descending with a cumulative share", {
  s <- data.frame(station_id = c("A", "B", "C"), either_unusable_min = c(2, 6, 2))
  p <- pareto_order(s)
  expect_equal(p$station_id, c("B", "A", "C"))
  expect_near(p$cum_share[1], 0.6)
  expect_near(p$cum_share[3], 1)
  zero <- pareto_order(data.frame(station_id = c("A", "B"), either_unusable_min = c(0, 0)))
  expect_true(all(is.na(zero$cum_share)))          # total 0: no share, not 0/0
})

test_that("baseline_count and baseline_flags: first half, at least 1", {
  expect_equal(baseline_count(10), 5)
  expect_equal(baseline_count(1), 1)
  expect_equal(baseline_count(3), 1)
  expect_equal(baseline_count(0), 0)
  expect_equal(baseline_count(4, share = 1), 4)
  expect_equal(baseline_flags(c(TRUE, TRUE, TRUE, TRUE)), c(TRUE, TRUE, FALSE, FALSE))
  expect_equal(baseline_flags(c(FALSE, TRUE, TRUE, TRUE)), c(FALSE, TRUE, FALSE, FALSE))
  expect_equal(baseline_flags(c(FALSE, FALSE)), c(FALSE, FALSE))
})

test_that("default_scenario_path finds the first existing file, else NA", {
  d <- tempfile("appdir")
  dir.create(file.path(d, "app"), recursive = TRUE)
  dir.create(file.path(d, "tests", "fixtures"), recursive = TRUE)
  app <- file.path(d, "app")
  expect_true(is.na(default_scenario_path(app)))
  file.create(file.path(d, "tests", "fixtures", "edge_small.csv"))
  expect_match(default_scenario_path(app), "edge_small.csv$")
  dir.create(file.path(d, "data"))
  file.create(file.path(d, "data", "baseline.csv"))
  expect_match(default_scenario_path(app), "baseline.csv$")
})

test_that("pipeline on the fixture: the rebalancing plan at 07:01 and at a stale minute", {
  g <- build_day_grids(fx$status, fx$stations, day)[[day]]
  r <- rank_stations(unusable_summary(g))
  at1 <- rebalance_plan(state_at(g, 1), fx$stations, rank = r[, c("station_id", "rank")])
  expect_equal(nrow(at1$moves), 0)                 # no station holds a surplus
  expect_equal(nrow(at1$unmet), 2)
  at10 <- rebalance_plan(state_at(g, 10), fx$stations, rank = r[, c("station_id", "rank")])
  expect_equal(sort(at10$excluded$station_id), c("S1", "S2"))   # stale data: data check
  expect_match(at10$excluded$recommendation[1], "data check")
})

test_that("explain_exclusion tells stale, missing and invalid apart (qc.R unchanged)", {
  g <- build_day_grids(fx$status, fx$stations, day)[[day]]
  st <- state_at(g, 5)                                   # 07:05: S1 age 5, S2 age 4 > 2
  ex <- rebalance_plan(st, fx$stations)$excluded
  out <- explain_exclusion(ex, fx$status, st$minute[1], 2, fx$issues)
  s1 <- out$detail[out$station_id == "S1"]
  s2 <- out$detail[out$station_id == "S2"]
  expect_true(startsWith(s1, "stale station data: last valid snapshot is 5 min old (stale_limit 2 min)"))
  expect_match(s2, "^stale station data: last valid snapshot is 4 min old")
  expect_match(s1, "invalid status row(s) rejected", fixed = TRUE)          # fixture rejects S1 rows
  expect_equal(out$reason, ex$reason)                              # qc.R reason kept as is

  # missing: no valid snapshot at or before the minute
  early <- st$minute[1] - 60 * 30
  ex2 <- data.frame(station_id = "S1", reason = "missing station data",
                    recommendation = "data check", stringsAsFactors = FALSE)
  out2 <- explain_exclusion(ex2, fx$status, early, 2, NULL)
  expect_equal(out2$detail, "missing station data: no valid snapshot at or before this minute")

  # other reasons pass through unchanged; empty input stays empty
  ex3 <- data.frame(station_id = "S2", reason = "renting or returning is switched off",
                    recommendation = "maintenance", stringsAsFactors = FALSE)
  expect_equal(explain_exclusion(ex3, fx$status, st$minute[1], 2, fx$issues)$detail, ex3$reason)
  expect_equal(nrow(explain_exclusion(ex3[0, ], fx$status, st$minute[1], 2)), 0)
})

test_that("heatmap keeps 0 and unknown apart (distinct layers and a legend entry)", {
  source(testthat::test_path("..", "app", "plots.R"), local = TRUE)
  m <- data.frame(station_id = c("S1", "S1", "S2"), hour = c(7L, 8L, 7L),
                  either_unusable_min = c(0, 0, 4), known_min = c(60, 0, 60),
                  stringsAsFactors = FALSE)
  p <- plot_heatmap(m)
  b <- ggplot2::ggplot_build(p)
  fills <- unlist(lapply(b$data, function(d) d$fill))
  expect_false(any(fills %in% c("white", "#FFFFFF")))              # 0 is a visible tint
  expect_true("grey45" %in% fills)                                  # unknown hour drawn
  expect_true(any(vapply(b$plot$scales$scales,
                         function(s) "colour" %in% s$aesthetics, logical(1))))  # legend entry
})
