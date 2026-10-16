test_that("KA-1: rent 3, return 2, either 5, warn_bike 4, warn_dock 1, 10 known", {
  s <- ka1_summary(ka1_scenario())
  expect_equal(s$known_min, 10)
  expect_equal(s$unknown_min, 0)
  expect_equal(s$rent_unusable_min, 3)
  expect_equal(s$return_unusable_min, 2)
  expect_equal(s$either_unusable_min, 5)
  expect_equal(s$warn_bike_min, 4)
  expect_equal(s$warn_dock_min, 1)
  expect_equal(s$coverage, 1)
})

test_that("KA-1b(a): removing 07:04 leaves the totals unchanged", {
  s <- ka1_summary(ka1_scenario(drop = 4))
  expect_equal(c(s$rent_unusable_min, s$return_unusable_min, s$either_unusable_min), c(3, 2, 5))
  expect_equal(s$known_min, 10)
})

test_that("KA-1b(b): removing 07:03-07:05 gives 1 unknown minute, rent 3 of 9 known", {
  s <- ka1_summary(ka1_scenario(drop = 3:5))
  expect_equal(s$known_min, 9)
  expect_equal(s$unknown_min, 1)
  expect_near(s$coverage, 0.9)
  expect_equal(s$rent_unusable_min, 3)
})

test_that("KA-1b(c): conflicting 07:02 rows are both rejected and listed", {
  extra <- make_status_rows("07:02:00", 3)
  v <- validate_scenario(ka1_scenario(extra = extra))
  conflicts <- v$issues[v$issues$rule == "conflicting duplicate", ]
  expect_equal(nrow(conflicts), 2)
  expect_true(all(conflicts$action == "rejected"))
  expect_equal(nrow(v$status), 9)             # 10 original + 1 extra - 2 rejected
  s <- ka1_summary(ka1_scenario(extra = extra))
  expect_equal(s$known_min, 10)
  expect_equal(s$rent_unusable_min, 2)        # 07:03 and 07:04; 07:02 uses 07:01
})

test_that("KA-1b(d): a snapshot at 07:05:30 never fills minute 07:05", {
  extra <- make_status_rows("07:05:30", 0)
  s <- ka1_summary(ka1_scenario(extra = extra))
  expect_equal(c(s$rent_unusable_min, s$return_unusable_min, s$either_unusable_min), c(3, 2, 5))
  expect_equal(s$known_min, 10)
})

test_that("unknown minutes are NA in the grid, never 0 or FALSE", {
  v <- validate_scenario(ka1_scenario(drop = 3:5))
  g <- build_grid(v$status, v$stations, "2026-10-05", "07:00", "07:10")
  unk <- g[!g$known, ]
  expect_equal(nrow(unk), 1)
  expect_true(is.na(unk$bikes_available) && is.na(unk$rent_unusable) && is.na(unk$either_unusable))
  expect_true(is.na(unk$warn_bike))
})

test_that("a station with no snapshots is entirely unknown, coverage 0", {
  sc <- rbind(ka1_scenario(), make_station_rows("S2", 10))
  v <- validate_scenario(sc)
  g <- build_grid(v$status, v$stations, "2026-10-05", "07:00", "07:10")
  s <- unusable_summary(g)
  expect_equal(s$known_min[s$station_id == "S2"], 0)
  expect_equal(s$coverage[s$station_id == "S2"], 0)
  expect_true(is.na(s$either_share[s$station_id == "S2"]))
})

test_that("KA-11: window X included, window Y excluded with a reason", {
  w <- window_summary(known = c(4500, 4200), unknown = c(0, 300),
                      either_min = c(450, 441), window = c("X", "Y"))
  expect_near(w$coverage[1], 1)
  expect_near(w$either_share_pct[1], 10.0)
  expect_true(w$included[1])
  expect_near(w$coverage[2], 0.9333)
  expect_near(w$either_share_pct[2], 10.5)
  expect_false(w$included[2])
  expect_true(nzchar(w$reason[2]))
  expect_equal(w$reason[1], "")
})

test_that("grid_window_counts adds up known, unknown and either minutes", {
  v <- validate_scenario(ka1_scenario(drop = 3:5))
  g <- build_grid(v$status, v$stations, "2026-10-05", "07:00", "07:10")
  w <- grid_window_counts(g, "S1")
  expect_equal(c(w$known, w$unknown, w$either_min), c(9, 1, 5))
})
