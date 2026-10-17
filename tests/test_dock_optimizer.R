source("dock_projection.R")

rates_for <- function(values) {
  result <- do.call(rbind, lapply(names(values), function(dock)
    data.frame(DOCID = dock, slot = 0:2015, avg_docked = values[[dock]])))
  attr(result, "city_timezone") <- "America/Chicago"
  attr(result, "bin_minutes") <- 5
  result
}
rates <- rates_for(c(A = 2, B = 0, C = 30))
stations <- data.frame(dockID = c("A", "B", "C"),
  live_bikes = c(2, 0, 30), capacity = c(30, 30, 30))
routes <- expand.grid(location_id = "TEST", mode = c("pickup", "return"),
  dockID = c("A", "B", "C"), stringsAsFactors = FALSE)
routes$distance <- c(A = 1.5, B = 0.5, C = 2)[routes$dockID]
reference <- "2026-10-19 08:00:00"
run <- function(mode = "pickup", ...) optimize_docks("TEST", stations, rates,
  mode = mode, now = reference, user_distances = routes, smooth_min = 0, ...)

pickup <- run()
stopifnot(identical(pickup$dockID, c("A", "C")),
  identical(pickup$rank, 1:2), all(pickup$discount_percent == 0),
  pickup$travel_minutes[1] == 30,
  format(pickup$arrival_time[1], "%H:%M", tz = "America/Chicago") == "08:30",
  pickup$projected_bikes[1] == 2)
cat("PASS known answer: 1.5 miles / 3 mph = 30 minutes; arrival 08:30; 2 projected bikes; empty pickup removed\n")

returns <- run("return")
stopifnot(identical(returns$dockID, c("B", "A")),
  identical(returns$discount_percent, c(20L, 20L)),
  returns$travel_minutes[1] == 3,
  identical(attr(returns, "excluded_docks")$dockID, "C"))
cat("PASS return: 0.5 miles / 10 mph = 3 minutes; full return dock removed; nearest first\n")

stopifnot(identical(return_discount(c(0, 7.49, 7.5, 14.99, 15, 30), 30),
  c(20L, 20L, 10L, 10L, 0L, 0L)))
cat("PASS incentive boundaries: <25% =>20%; 25%-<50% =>10%; >=50% =>0%\n")

# Distance, not the incentive, determines ordering.
stations$live_bikes <- c(10, 2, 30)
routes$distance <- c(A = 0.1, B = 0.2, C = 0.3)[routes$dockID]
ordered <- run("return")
stopifnot(identical(ordered$dockID, c("A", "B")),
  identical(ordered$discount_percent, c(10L, 20L)))
cat("PASS: a farther 20% discount does not outrank a nearer 10% discount\n")

# Arrival-time inventory, not current inventory, controls eligibility.
changing <- rates_for(c(A = 10, B = 0, C = 30))
changing$avg_docked[changing$DOCID == "A" & changing$slot == 1] <- 9.2
one <- data.frame(dockID = "A", live_bikes = 1, capacity = 30)
five_minutes <- data.frame(location_id = "TEST", mode = "pickup", dockID = "A", distance = 0.25)
fractional <- optimize_docks("TEST", one, changing, now = "2026-10-19 00:00:00",
  user_distances = five_minutes, smooth_min = 0)
stopifnot(nrow(fractional) == 0,
  abs(attr(fractional, "excluded_docks")$projected_bikes - 0.2) < 1e-8)
cat("PASS arrival projection: 1 current bike minus 0.8 projected change = 0.2; excluded\n")
changing$avg_docked[changing$DOCID == "A" & changing$slot == 1] <- 10.8
one$live_bikes <- 29
five_minutes$mode <- "return"
five_minutes$distance <- 10 * 5 / 60
fractional_return <- optimize_docks("TEST", one, changing, mode = "return",
  now = "2026-10-19 00:00:00", user_distances = five_minutes, smooth_min = 0)
stopifnot(nrow(fractional_return) == 0,
  abs(attr(fractional_return, "excluded_docks")$projected_spaces - 0.2) < 1e-8)
cat("PASS arrival projection: 29 current bikes plus 0.8 change leaves 0.2 spaces; return excluded\n")

stations$live_bikes <- c(1, 29, 30)
stopifnot("A" %in% run()$dockID, "B" %in% run("return")$dockID)
stations$live_bikes <- stations$capacity
stopifnot(nrow(run("return")) == 0)
stations$live_bikes[] <- 0
stopifnot(nrow(run()) == 0)
routes$distance[routes$dockID == "A"] <- NA_real_
stations$live_bikes[] <- 2
missing_route <- run()
stopifnot(!"A" %in% missing_route$dockID,
  "no_route" %in% attr(missing_route, "excluded_docks")$exclusion_reason)
expect_error <- function(expression) stopifnot(inherits(try(expression, silent = TRUE), "try-error"))
expect_error(run(travel_speed_mph = 0))
expect_error(optimize_docks("UNKNOWN", stations, rates, user_distances = routes))
expect_error(return_discount(31, 30))
cat("PASS edge cases: exactly one bike/space qualifies; all docks excluded; missing route; invalid speed, location, and occupancy\n")

locations <- read.csv("data/optimizer/user_locations.csv")
distances <- read.csv("data/optimizer/user_dock_distances.csv")
stopifnot(nrow(locations) == 30, !anyDuplicated(locations$location_id),
  all(table(locations$city) == 10), nrow(distances) == 1620,
  all(is.finite(distances$distance)), all(distances$distance > 0),
  !anyDuplicated(distances[c("location_id", "mode", "dockID")]),
  all(table(distances$location_id, distances$mode) == 27),
  setequal(locations$location_id, distances$location_id))
cat("PASS saved inputs: 10 real sourced locations per city; 1620 walking/cycling road distances\n")
