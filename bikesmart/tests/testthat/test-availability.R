# test-availability.R
# Tests for Poisson availability probabilities and dock recommendation rule

# 1. get_bike_availability known answers
# With 1 bike, lam_out = 1, lam_in = 1 -> P(In >= Out) ~ 0.6542
p_bike <- get_bike_availability(b0 = 1, lam_out = 1, lam_in = 1)
stopifnot(abs(p_bike - 0.65417) < 0.001)

# Certainty & impossibility edge cases
stopifnot(get_bike_availability(b0 = 5, lam_out = 0, lam_in = 0) == 1)
stopifnot(get_bike_availability(b0 = 0, lam_out = 0, lam_in = 0) == 0)

# 2. get_slot_availability
p_slot <- get_slot_availability(b0 = 9, capacity = 10, lam_out = 1, lam_in = 1)
stopifnot(p_slot > 0 && p_slot < 1)
stopifnot(get_slot_availability(b0 = 10, capacity = 10, lam_out = 0, lam_in = 0) == 0)
stopifnot(get_slot_availability(b0 = 5, capacity = 10, lam_out = 0, lam_in = 0) == 1)

# 3. recommend_dock
candidates <- data.frame(
  dock_id = c("DockA", "DockB"),
  minutes = c(10, 20),
  p       = c(0.61, 0.95),
  stringsAsFactors = FALSE
)
rec_90 <- recommend_dock(candidates, threshold = 0.90)
stopifnot(
  rec_90$choice$dock_id == "DockB",
  rec_90$reason == "threshold met"
)

rec_60 <- recommend_dock(candidates, threshold = 0.60)
stopifnot(
  rec_60$choice$dock_id == "DockA",
  rec_60$reason == "threshold met"
)

cat("PASS test-availability: Poisson availability, slot availability, and threshold recommendation verified.\n")
