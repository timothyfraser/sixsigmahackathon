write_tmp_csv <- function(df) {
  path <- tempfile(fileext = ".csv")
  write.csv(df, path, row.names = FALSE, na = "")
  path
}

test_that("a missing file stops with a clear message", {
  expect_error(read_scenario("no/such/file.csv"), "not found")
})

test_that("no table column stops", {
  path <- write_tmp_csv(data.frame(a = 1, b = 2))
  expect_error(read_scenario(path), "table")
})

test_that("a required column missing for a record type that is present stops", {
  sc <- ka1_scenario()
  sc$bikes_available <- NULL
  expect_error(validate_scenario(sc), "bikes_available")
})

test_that("an unknown table value stops", {
  sc <- ka1_scenario()
  sc$table[2] <- "weather"
  expect_error(validate_scenario(sc), "weather")
})

test_that("no stations rows stops", {
  sc <- ka1_scenario()
  sc <- sc[sc$table != "stations", ]
  expect_error(validate_scenario(sc), "stations")
})

test_that("a duplicated station_id in stations stops", {
  sc <- rbind(make_station_rows(c("S1", "S1"), 10), make_status_rows("07:00:00", 2))
  expect_error(validate_scenario(sc), "duplicated")
})

test_that("a clean scenario has an empty issues table with the right columns", {
  v <- validate_scenario(ka1_scenario())
  expect_equal(nrow(v$issues), 0)
  expect_equal(names(v$issues), c("table", "row", "id", "rule", "action"))
})

test_that("invalid status rows are rejected and listed, never turned into 0", {
  bad <- rbind(
    make_status_rows("07:10:00", -1, docks = 5),     # negative count
    make_status_rows("07:11:00", 8, docks = 8),      # 16 > capacity 10
    make_status_rows("07:12:00", 2, station = "S9")  # unknown station
  )
  v <- validate_scenario(ka1_scenario(extra = bad))
  expect_equal(nrow(v$status), 10)
  expect_setequal(v$issues$rule,
                  c("negative or missing count", "bikes + docks > capacity", "unknown station_id"))
  expect_true(all(v$issues$action == "rejected"))
  expect_true(all(v$issues$table == "status"))
})

test_that("identical duplicate status rows are kept once and flagged", {
  v <- validate_scenario(ka1_scenario(extra = make_status_rows("07:02:00", 0)))
  expect_equal(nrow(v$status), 10)
  expect_equal(v$issues$rule, "identical duplicate")
  expect_equal(v$issues$action, "kept once")
})

test_that("edge-case fixture loads without stopping and lists its issues", {
  v <- load_scenario(testthat::test_path("fixtures", "edge_small.csv"))
  expect_equal(nrow(v$stations), 2)
  expect_equal(nrow(v$status), 2)       # S1 07:00 and S2 07:01 (kept once)
  expect_equal(nrow(v$attempts), 2)     # A1, A2
  expect_equal(nrow(v$tasks), 1)        # T1
  rules <- table(v$issues$rule)
  expect_equal(unname(rules["unparseable timestamp"]), 1)
  expect_equal(unname(rules["conflicting duplicate"]), 2 + 2)  # 2 status + 2 attempts
  expect_equal(unname(rules["identical duplicate"]), 1)
  expect_equal(unname(rules["success inconsistent with failure_reason"]), 2)
  expect_equal(unname(rules["task times out of order"]), 1)
  expect_equal(unname(rules["source equals destination"]), 1)
  expect_true(all(c("table", "row", "id", "rule", "action") %in% names(v$issues)))
})
