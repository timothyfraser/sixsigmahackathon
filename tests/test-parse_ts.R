test_that("parse_ts converts EDT (-04:00) to UTC", {
  x <- parse_ts("2026-10-05T07:03:30-04:00")
  expect_equal(format(x, "%Y-%m-%d %H:%M:%S", tz = "UTC"), "2026-10-05 11:03:30")
  expect_equal(format(x, "%H:%M:%S", tz = "America/New_York"), "07:03:30")
})

test_that("parse_ts converts EST (-05:00) to UTC", {
  x <- parse_ts("2026-11-09T07:00:00-05:00")
  expect_equal(format(x, "%Y-%m-%d %H:%M:%S", tz = "UTC"), "2026-11-09 12:00:00")
  expect_equal(format(x, "%H:%M:%S", tz = "America/New_York"), "07:00:00")
})

test_that("parse_ts gives NA (not a wrong time) for garbage, and works on vectors", {
  x <- parse_ts(c("2026-10-05T07:00:00-04:00", "garbage", "", NA, "2026-13-45T07:00:00-04:00"))
  expect_false(is.na(x[1]))
  expect_true(all(is.na(x[2:5])))
})
