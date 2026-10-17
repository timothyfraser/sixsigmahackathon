# test-failure-factor.R
# Tests for failure factor, defect breakdown, and prediction scaling

rates2 <- c(flat_tire = 0.02, battery = 0.05)
rates3 <- c(flat_tire = 0.02, battery = 0.05, crash = 0.01)

# KNOWN ANSWER (hand calculation):
# 0.98 * 0.95 = 0.931
# 0.931 * 0.99 = 0.92169
# 20 * 0.931 = 18.62
stopifnot(abs(failure_factor(rates2) - 0.931) < 1e-9)
stopifnot(abs(failure_factor(rates3) - 0.92169) < 1e-9)
stopifnot(abs(apply_failure_factor(20, rates2) - 18.62) < 1e-9)
stopifnot(all(abs(apply_failure_factor(c(0, 10, 20), rates2) - c(0, 9.31, 18.62)) < 1e-9))

# Breakdown ordering (worst first)
b <- failure_breakdown(rates3)
stopifnot(
  identical(b$defect, c("battery", "flat_tire", "crash")),
  all(abs(b$cumulative_factor - c(0.95, 0.931, 0.92169)) < 1e-9),
  abs(tail(b$cumulative_factor, 1) - failure_factor(rates3)) < 1e-9
)

# Order invariance
stopifnot(abs(failure_factor(rev(rates3)) - failure_factor(rates3)) < 1e-9)

# Degenerate cases
none <- stats::setNames(numeric(0), character(0))
stopifnot(failure_factor(none) == 1)
stopifnot(nrow(failure_breakdown(none)) == 0)
stopifnot(failure_factor(c(a = 0, b = 0)) == 1)
stopifnot(failure_factor(c(a = 1, b = 0.3)) == 0)
stopifnot(abs(failure_factor(c(flat_tire = 0.1)) - 0.9) < 1e-9)

# Error validation
expect_error <- function(expr) stopifnot(inherits(try(expr, silent = TRUE), "try-error"))
expect_error(failure_factor(c(flat_tire = 5)))
expect_error(failure_factor(c(flat_tire = -0.1)))
expect_error(failure_factor(c(0.02, 0.05)))
expect_error(failure_factor(c(a = NA)))
expect_error(failure_factor("0.02"))
expect_error(apply_failure_factor(-1, rates2))

cat("PASS test-failure-factor: hand calculation (0.931, 0.92169), breakdown, and edge cases verified.\n")

