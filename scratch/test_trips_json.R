library(shiny)
library(jsonlite)

test_trips <- list(
  b_id = c(0L, 1L, 2L),
  start_step = c(10L, 20L, 30L),
  end_step = c(15L, 25L, 35L),
  r_idx = c(100L, 101L, 102L),
  n = 3L
)

cat("Direct toJSON:\n", toJSON(test_trips, auto_unbox = TRUE), "\n\n")
cat("shiny:::toJSON:\n", as.character(shiny:::toJSON(list(trips = test_trips))), "\n")

