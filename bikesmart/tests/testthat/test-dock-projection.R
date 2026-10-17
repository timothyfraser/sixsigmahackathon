# test-dock-projection.R
# Tests for dock projection, arrival forecasting, return discounts, and station optimization

rates_for <- function(values) {
  result <- do.call(rbind, lapply(names(values), function(dock) {
    data.frame(
      DOCID = dock,
      weekday = 1L,
      day = "Mon",
      tod = "00:00",
      slot = 0:2015,
      n_days = 5L,
      avg_docked = values[[dock]],
      prev_docked = values[[dock]],
      rate = 0,
      stringsAsFactors = FALSE
    )
  }))
  attr(result, "city_timezone") <- "America/Chicago"
  attr(result, "bin_minutes") <- 5
  result
}

test_rates <- rates_for(c(A = 2, B = 0, C = 30))
test_stations <- data.frame(
  dockID = c("A", "B", "C"),
  live_bikes = c(2, 0, 30),
  capacity = c(30, 30, 30),
  stringsAsFactors = FALSE
)
test_routes <- expand.grid(
  location_id = "TEST",
  mode = c("pickup", "return"),
  dockID = c("A", "B", "C"),
  stringsAsFactors = FALSE
)
test_routes$distance <- c(A = 1.5, B = 0.5, C = 2.0)[test_routes$dockID]
ref_time <- "2026-10-19 08:00:00"

# 1. Pickup test (known answer: 1.5 miles at 3 mph = 30 min, arrival 08:30)
pickup <- optimize_docks(
  "TEST", test_stations, test_rates,
  mode = "pickup", now = ref_time, user_distances = test_routes, smooth_min = 0
)
stopifnot(
  identical(pickup$dockID, c("A", "C")),
  identical(pickup$rank, 1:2),
  all(pickup$discount_percent == 0),
  pickup$travel_minutes[1] == 30,
  format(pickup$arrival_time[1], "%H:%M", tz = "America/Chicago") == "08:30",
  pickup$projected_bikes[1] == 2
)

# 2. Return test (known answer: 0.5 miles at 10 mph = 3 min; full dock excluded)
returns <- optimize_docks(
  "TEST", test_stations, test_rates,
  mode = "return", now = ref_time, user_distances = test_routes, smooth_min = 0
)
stopifnot(
  identical(returns$dockID, c("B", "A")),
  identical(returns$discount_percent, c(20L, 20L)),
  returns$travel_minutes[1] == 3,
  identical(attr(returns, "excluded_docks")$dockID, "C")
)

# 3. Return discount incentive thresholds
stopifnot(
  identical(return_discount(c(0, 7.49, 7.5, 14.99, 15, 30), 30),
            c(20L, 20L, 10L, 10L, 0L, 0L))
)

# 4. Nearest rank takes precedence over discount
test_stations$live_bikes <- c(10, 2, 30)
test_routes$distance <- c(A = 0.1, B = 0.2, C = 0.3)[test_routes$dockID]
ordered <- optimize_docks(
  "TEST", test_stations, test_rates,
  mode = "return", now = ref_time, user_distances = test_routes, smooth_min = 0
)
stopifnot(
  identical(ordered$dockID, c("A", "B")),
  identical(ordered$discount_percent, c(10L, 20L))
)

# 5. Degenerate and error edge cases
expect_error <- function(expr) stopifnot(inherits(try(expr, silent = TRUE), "try-error"))
expect_error(optimize_docks("TEST", test_stations, test_rates, travel_speed_mph = 0))
expect_error(optimize_docks("UNKNOWN", test_stations, test_rates, user_distances = test_routes))
expect_error(return_discount(31, 30))
expect_error(return_discount(-1, 30))

cat("PASS test-dock-projection: known answers, return incentives, and degenerate cases verified.\n")

