stn <- function(id, cap, lat = 42.44, lon = -76.50) {
  data.frame(station_id = id, latitude = lat, longitude = lon, capacity = cap,
             stringsAsFactors = FALSE)
}
st <- function(id, bikes, cap, renting = TRUE, returning = TRUE) {
  data.frame(station_id = id, bikes_available = bikes, docks_available = cap - bikes,
             is_renting = renting, is_returning = returning, stringsAsFactors = FALSE)
}

test_that("KA-4: move 8 bikes from A to B", {
  stations <- rbind(stn("A", 20, 42.44, -76.50), stn("B", 20, 42.45, -76.50))
  state <- rbind(st("A", 18, 20), st("B", 1, 20))
  plan <- rebalance_plan(state, stations)
  expect_equal(nrow(plan$moves), 1)
  expect_equal(plan$moves$from_station, "A")
  expect_equal(plan$moves$to_station, "B")
  expect_equal(plan$moves$quantity, 8)
  expect_true(plan$moves$est_distance_km > 1)       # about 1.11 km x 1.3
  expect_match(plan$moves$distance_basis, "estimated")
})

test_that("a closed station is excluded and gets a recommendation", {
  stations <- rbind(stn("A", 20), stn("B", 20), stn("C", 20))
  state <- rbind(st("A", 18, 20), st("B", 1, 20, renting = FALSE), st("C", 2, 20))
  plan <- rebalance_plan(state, stations)
  expect_equal(plan$excluded$station_id, "B")
  expect_match(plan$excluded$recommendation, "maintenance")
  expect_false("B" %in% c(plan$moves$from_station, plan$moves$to_station))
  expect_equal(plan$moves$to_station, "C")
})

test_that("van capacity limits the quantity", {
  stations <- rbind(stn("A", 40), stn("B", 40))
  state <- rbind(st("A", 38, 40), st("B", 1, 40))
  plan <- rebalance_plan(state, stations, van_capacity = 12)
  expect_equal(plan$moves$quantity, 12)
})

test_that("destination free docks limit the quantity", {
  stations <- rbind(stn("A", 40), stn("B", 20))
  state <- rbind(st("A", 38, 40),
                 data.frame(station_id = "B", bikes_available = 1, docks_available = 3,
                            is_renting = TRUE, is_returning = TRUE))
  plan <- rebalance_plan(state, stations)
  expect_equal(plan$moves$quantity, 3)
})

test_that("two deficits competing for one surplus are not double-planned", {
  stations <- rbind(stn("A", 20), stn("B", 20), stn("C", 20))
  state <- rbind(st("A", 18, 20), st("B", 1, 20), st("C", 1, 20))
  rank <- data.frame(station_id = c("B", "C"), rank = c(2, 1))   # C is worse (1 = worst)
  plan <- rebalance_plan(state, stations, rank = rank)
  expect_equal(sum(plan$moves$quantity[plan$moves$from_station == "A"]), 8)
  expect_equal(plan$moves$to_station, "C")            # worst first takes it all
  expect_true("B" %in% plan$unmet$station_id)
})

test_that("a distance tie is broken by station_id ascending", {
  stations <- rbind(stn("A", 20), stn("S2", 20), stn("S1", 20))   # same coordinates
  state <- rbind(st("A", 1, 20), st("S2", 18, 20), st("S1", 18, 20))
  plan <- rebalance_plan(state, stations)
  expect_equal(plan$moves$from_station[1], "S1")
})

test_that("a rank tie is broken by station_id ascending", {
  stations <- rbind(stn("A", 20), stn("B", 20), stn("C", 20))
  state <- rbind(st("A", 18, 20), st("C", 1, 20), st("B", 1, 20))
  plan <- rebalance_plan(state, stations)
  expect_equal(plan$moves$to_station[1], "B")
})

test_that("no deficits gives an empty moves table", {
  stations <- rbind(stn("A", 20), stn("B", 20))
  state <- rbind(st("A", 10, 20), st("B", 10, 20))
  plan <- rebalance_plan(state, stations)
  expect_equal(nrow(plan$moves), 0)
})
