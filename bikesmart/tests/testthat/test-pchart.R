# test-pchart.R
# Tests for P-chart calculations, 3-sigma limits, and daily service counts

# KNOWN ANSWER:
# Three days, 100 bikes each, 5 / 10 / 15 due.
# p-bar = 30 / 300 = 0.10; sigma = sqrt(0.10 * 0.90 / 100) = 0.03
# UCL = 0.10 + 0.09 = 0.19; LCL = 0.10 - 0.09 = 0.01; no day out of control.
ch <- p_chart(d = c(5, 10, 15), n = c(100, 100, 100))
stopifnot(all(abs(ch$p - c(0.05, 0.10, 0.15)) < 1e-9))
stopifnot(abs(unique(ch$p_bar) - 0.10) < 1e-9)
stopifnot(all(abs(ch$ucl - rep(0.19, 3)) < 1e-9))
stopifnot(all(abs(ch$lcl - rep(0.01, 3)) < 1e-9))
stopifnot(!any(ch$out_of_control))

# Spike day out of control
ch_spike <- p_chart(d = c(5, 5, 10, 30), n = rep(100, 4))
stopifnot(abs(unique(ch_spike$p_bar) - 0.125) < 1e-9)
stopifnot(identical(ch_spike$out_of_control, c(FALSE, FALSE, FALSE, TRUE)))

# Limits widen for smaller subgroups
ch_var <- p_chart(d = c(10, 10), n = c(100, 25))
stopifnot(ch_var$ucl[2] > ch_var$ucl[1])

# Degenerate cases
ch_zero <- p_chart(d = c(0, 0, 0), n = c(50, 50, 50))
stopifnot(unique(ch_zero$p_bar) == 0)
stopifnot(all(ch_zero$ucl == 0))
stopifnot(!any(ch_zero$out_of_control))

ch_all <- p_chart(d = c(20, 20), n = c(20, 20))
stopifnot(all(ch_all$ucl == 1))

ch_one <- p_chart(d = 1, n = 1)
stopifnot(ch_one$p == 1)

# Error handling
expect_error <- function(expr) stopifnot(inherits(try(expr, silent = TRUE), "try-error"))
expect_error(p_chart(numeric(0), numeric(0)))
expect_error(p_chart(c(1, 2), c(10)))
expect_error(p_chart(c(1), c(0)))
expect_error(p_chart(c(11), c(10)))
expect_error(p_chart(c(NA), c(10)))

# daily_service_counts known answer
mk <- function(day) seq(as.POSIXct(paste(day, "14:00:00"), tz = "UTC"), by = "5 min", length.out = 6)
t1 <- mk("2026-09-16")
t2 <- mk("2026-09-17")
log_df <- rbind(
  data.frame(BIKEID = "A", DOCID = c(rep("0", 6), rep("X", 6)), time = c(t1, t2), stringsAsFactors = FALSE),
  data.frame(BIKEID = "B", DOCID = c("0", "0", rep("X", 4), "0", "0", rep("X", 4)), time = c(t1, t2), stringsAsFactors = FALSE)
)
out <- daily_service_counts(log_df, service_interval_h = 0.25)
stopifnot(
  identical(out$day, as.Date(c("2026-09-16", "2026-09-17"))),
  identical(out$n, c(2L, 2L)),
  identical(out$d, c(1L, 1L))
)

# Start hours offset
out_sh <- daily_service_counts(log_df, service_interval_h = 0.25,
                               start_hours = data.frame(BIKEID = "B", start_hours = 0.1, stringsAsFactors = FALSE))
stopifnot(identical(out_sh$d, c(2L, 0L)))

cat("PASS test-pchart: hand calculation (p-bar 0.10, limits 0.01/0.19), spike detection, and daily service counts verified.\n")

