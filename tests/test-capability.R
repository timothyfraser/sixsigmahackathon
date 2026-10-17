# Tests for task H-11: anomaly onsets, c chart (KA-6), X-bar and R chart (KA-7), Cpu/Cp/Cpk,
# the Poisson dispersion check and the Shapiro-Wilk check. Hand-worked answers are in
# docs/methods.md section 4.2. Run from the repo root.
source(testthat::test_path("..", "app", "prep.R"), local = TRUE)

# ---------------------------------------------------------------- anomaly onsets
# Hand-made grid: S = still usable, X = unusable, ? = unknown (known FALSE, state NA).
# Rows are one minute each; the function must look only at consecutive KNOWN minutes.
make_state_grid <- function(id, states, first = "2026-10-05 07:00") {
  t0 <- as.POSIXct(first, tz = "America/New_York")
  data.frame(station_id = rep(id, length(states)), minute = t0 + 60 * (seq_along(states) - 1),
             known = states != "?",
             either_unusable = ifelse(states == "?", NA, states == "X"),
             stringsAsFactors = FALSE)
}

test_that("an onset is a known usable minute followed by a known unusable minute", {
  # A: S X S X ? X S ?  -> onsets at minute 2 and 4 (index 4 follows S). The ? X switch is NOT counted.
  a <- make_state_grid("A", strsplit("S X S X ? X S ?", " ")[[1]])
  # B: X X S X X S X S -> onsets at index 4 and 7; the leading X is not an onset (nothing before it).
  b <- make_state_grid("B", strsplit("X X S X X S X S", " ")[[1]])
  g <- rbind(a, b)
  expect_equal(count_onsets(g, "A"), 2)
  expect_equal(count_onsets(g, "B"), 2)
  expect_equal(count_onsets(g), 4)
  expect_equal(count_onsets(g, c("A", "B")), 4)
})

test_that("a switch across an unknown gap is not an onset", {
  g <- make_state_grid("A", strsplit("S ? X S", " ")[[1]])
  expect_equal(count_onsets(g), 0)
  g2 <- make_state_grid("A", strsplit("S X", " ")[[1]])
  expect_equal(count_onsets(g2), 1)
})

test_that("onset counting does not depend on the row order", {
  g <- rbind(make_state_grid("A", strsplit("S X S X ? X S ?", " ")[[1]]),
             make_state_grid("B", strsplit("X X S X X S X S", " ")[[1]]))
  expect_equal(count_onsets(g[sample(nrow(g)), ]), 4)
})

test_that("an empty grid has 0 onsets", {
  expect_equal(count_onsets(make_state_grid("A", character(0))), 0)
})

# ---------------------------------------------------------------- c chart (KA-6)
test_that("KA-6: counts 3,5,2,4,6 give c-bar 4, UCL 10, LCL 0 and no signal", {
  r <- c_chart(c(3, 5, 2, 4, 6))
  expect_equal(r$c_bar, 4)
  expect_equal(unique(r$data$ucl), 10)
  expect_equal(unique(r$data$lcl), 0)
  expect_equal(r$data$count, c(3, 5, 2, 4, 6))
  expect_false(any(r$data$out_of_control))
  expect_equal(r$note, "")
})

test_that("c chart: rule 1 flags a count beyond the UCL and the baseline decides the limits", {
  # baseline = the first 5 windows only; the 6th (count 12) is beyond UCL 10
  r <- c_chart(c(3, 5, 2, 4, 6, 12), baseline = c(TRUE, TRUE, TRUE, TRUE, TRUE, FALSE))
  expect_equal(r$c_bar, 4)
  expect_equal(r$data$rule1, c(FALSE, FALSE, FALSE, FALSE, FALSE, TRUE))
  expect_equal(r$data$out_of_control[6], TRUE)
})

test_that("c chart: rule 4 flags the 8th point in a row above the centre", {
  r <- c_chart(c(4, 4, 4, 4, 5, 5, 5, 5, 5, 5, 5, 5), baseline = c(rep(TRUE, 4), rep(FALSE, 8)))
  expect_equal(r$c_bar, 4)
  # 8 in a row above 4: the 8th of them is index 12
  expect_equal(which(r$data$rule4), 12)
})

test_that("c chart: c-bar = 0 gives NA limits with a reason, observed counts kept", {
  r <- c_chart(c(0, 0, 0, 0))
  expect_equal(r$c_bar, 0)
  expect_true(all(is.na(r$data$ucl)))
  expect_true(all(is.na(r$data$lcl)))
  expect_true(all(is.na(r$data$out_of_control)))
  expect_equal(r$data$count, c(0, 0, 0, 0))
  expect_match(r$note, "no anomaly events in the baseline: limits cannot be estimated")
  expect_match(r$note, "zero observed does not mean zero risk")
})

test_that("c chart: fewer than 2 baseline windows gives NA limits with a reason", {
  r <- c_chart(c(3, 5, 2), baseline = c(TRUE, FALSE, FALSE))
  expect_equal(r$c_bar, 3)
  expect_true(all(is.na(r$data$ucl)))
  expect_match(r$note, "fewer than 2 baseline windows")
})

test_that("c chart: dispersion ratio variance/mean on hand numbers", {
  d <- c_chart(c(3, 5, 2, 4, 6))$dispersion
  expect_equal(d$variance, 2.5)
  expect_equal(d$mean, 4)
  expect_equal(d$ratio, 0.625)
  expect_false(d$warning)
  # overdispersed: 0,10,0,10,5 -> mean 5, variance 25, ratio 5
  o <- c_chart(c(0, 10, 0, 10, 5))$dispersion
  expect_equal(o$variance, 25)
  expect_equal(o$mean, 5)
  expect_equal(o$ratio, 5)
  expect_true(o$warning)
  expect_match(o$note, "not a confirmed special cause")
})

test_that("c chart: dispersion is NA with a reason for mean 0 or fewer than 2 windows", {
  z <- c_dispersion(c(0, 0, 0))
  expect_true(is.na(z$ratio))
  expect_true(is.na(z$warning))
  expect_match(z$note, "mean is 0")
  one <- c_dispersion(5)
  expect_true(is.na(one$ratio))
  expect_match(one$note, "fewer than 2")
})

# ---------------------------------------------------------------- X-bar and R (KA-7)
ka7 <- rbind(c(10, 12, 14), c(11, 13, 15), c(9, 12, 15))

test_that("KA-7: X-bar and R limits and sigma-hat", {
  r <- xbar_r_chart(ka7)
  expect_near(r$xbarbar, 12.333)
  expect_near(r$rbar, 4.667)
  expect_near(r$x_ucl, 17.107)
  expect_near(r$x_lcl, 7.559)
  expect_near(r$r_ucl, 12.012)
  expect_equal(r$r_lcl, 0)
  expect_near(r$sigma_hat, 2.756)
  expect_equal(r$data$xbar, c(12, 13, 12))
  expect_equal(r$data$range, c(4, 4, 6))
  expect_false(any(r$data$out_of_control))
  expect_true(r$in_control)
  expect_equal(r$note, "")
})

test_that("KA-7: Cpu = 0.927 with a USL of 20", {
  cap <- capability_indices(xbar_r_chart(ka7), usl = 20)
  expect_near(cap$sigma_hat, 2.756)
  expect_near(cap$cpu, 0.927)
  expect_true(is.na(cap$cp))                       # no LSL entered
  expect_match(cap$cp_note, "no LSL")
})

test_that("Cp, Cpl and Cpk with USL = 20 and LSL = 5 (hand worked)", {
  # sigma-hat = (14/3)/1.693 = 2.756405; 3 sigma = 8.269215
  # Cpu = (20 - 12.3333)/8.269215 = 0.927; Cpl = (12.3333 - 5)/8.269215 = 0.887
  # Cp = 15/(6 * 2.756405) = 0.907; Cpk = min(Cpu, Cpl) = 0.887
  cap <- capability_indices(xbar_r_chart(ka7), usl = 20, lsl = 5)
  expect_near(cap$cpu, 0.927)
  expect_near(cap$cpl, 0.887)
  expect_near(cap$cp, 0.907)
  expect_near(cap$cpk, 0.887)
})

test_that("a USL below the LSL is refused with a reason", {
  cap <- capability_indices(xbar_r_chart(ka7), usl = 5, lsl = 20)
  expect_true(is.na(cap$cp))
  expect_true(is.na(cap$cpk))
  expect_match(cap$cp_note, "USL must be larger than the LSL")
})

test_that("no USL: Cpu is NA with a reason (a spec is never invented)", {
  cap <- capability_indices(xbar_r_chart(ka7))
  expect_true(is.na(cap$cpu))
  expect_equal(cap$cpu_note, "no USL entered: capability is not computed")
  cap2 <- capability_indices(xbar_r_chart(ka7), usl = NA)
  expect_true(is.na(cap2$cpu))
  # sigma-hat is still reported
  expect_near(cap2$sigma_hat, 2.756)
})

test_that("R-bar = 0: limits, sigma-hat and capability are NA with a reason", {
  flat <- rbind(c(10, 10, 10), c(11, 11, 11), c(12, 12, 12))
  r <- xbar_r_chart(flat)
  expect_equal(r$rbar, 0)
  expect_near(r$xbarbar, 11)
  expect_true(is.na(r$x_ucl) && is.na(r$x_lcl) && is.na(r$r_ucl) && is.na(r$sigma_hat))
  expect_true(all(is.na(r$data$out_of_control)))
  expect_equal(r$data$xbar, c(10, 11, 12))
  expect_match(r$note, "R-bar = 0: no within-subgroup variation, limits and capability cannot be estimated")
  cap <- capability_indices(r, usl = 20)
  expect_true(is.na(cap$cpu))
  expect_match(cap$cpu_note, "R-bar = 0")
})

test_that("fewer than 2 baseline subgroups: NA with a reason", {
  r <- xbar_r_chart(ka7, baseline = c(TRUE, FALSE, FALSE))
  expect_true(is.na(r$x_ucl))
  expect_match(r$note, "fewer than 2 baseline subgroups")
  expect_true(is.na(capability_indices(r, usl = 20)$cpu))
})

test_that("an out-of-control X-bar chart: Cpu is NA with a reason", {
  # 6 baseline subgroups (KA-7 twice), then a subgroup with mean 31 far beyond UCL 17.107
  vals <- rbind(ka7, ka7, c(30, 31, 32))
  r <- xbar_r_chart(vals, baseline = c(rep(TRUE, 6), FALSE))
  expect_near(r$x_ucl, 17.107)
  expect_true(r$data$rule1_x[7])
  expect_false(r$in_control)
  cap <- capability_indices(r, usl = 40)
  expect_true(is.na(cap$cpu))
  expect_equal(cap$cpu_note, "the X-bar/R chart is not in control: capability is not meaningful")
  # sigma-hat is an estimate from the baseline and stays visible
  expect_near(cap$sigma_hat, 2.756)
})

test_that("an out-of-control R chart (rule 1 on R) also blocks capability", {
  vals <- rbind(ka7, ka7, c(10, 12, 40))      # range 30 > R UCL 12.012
  r <- xbar_r_chart(vals, baseline = c(rep(TRUE, 6), FALSE))
  expect_true(r$data$rule1_r[7])
  expect_false(r$in_control)
})

test_that("xbar_r_chart insists on subgroups of 3", {
  expect_error(xbar_r_chart(matrix(1:8, ncol = 4)), "3")
})

# ---------------------------------------------------------------- response subgroups
tk <- function(id, assigned, arrived, status = "completed") {
  data.frame(task_id = id, status = status,
             assigned_at = parse_ts(paste0("2026-10-05T", assigned, "-04:00")),
             arrived_at = parse_ts(paste0("2026-10-05T", arrived, "-04:00")),
             completed_at = parse_ts(paste0("2026-10-05T", arrived, "-04:00")),
             stringsAsFactors = FALSE)
}

test_that("subgroups use the FIRST 3 completed tasks by assigned_at (ties by task_id)", {
  tasks <- rbind(tk("T5", "07:50:00", "08:10:00"),       # 20 min, the 4th: not used
                 tk("T2", "07:10:00", "07:22:00"),       # 12
                 tk("T1", "07:10:00", "07:20:00"),       # 10 (ties with T2 by time, T1 first)
                 tk("T3", "07:30:00", "07:44:00"),       # 14
                 tk("T9", "07:15:00", "07:30:00", "cancelled"))
  s <- response_subgroups(tasks, "2026-10-05")
  expect_equal(s$windows, "2026-10-05")
  expect_equal(as.numeric(s$values[1, ]), c(10, 12, 14))
  expect_equal(as.character(s$task_ids[1, ]), c("T1", "T2", "T3"))
  expect_equal(nrow(s$dropped), 0)
})

test_that("a window with fewer than 3 tasks is dropped and reported with a reason", {
  tasks <- rbind(tk("T1", "07:10:00", "07:20:00"), tk("T2", "07:30:00", "07:40:00"))
  s <- response_subgroups(tasks, c("2026-10-05", "2026-10-06"))
  expect_equal(nrow(s$values), 0)
  expect_equal(s$dropped$window, c("2026-10-05", "2026-10-06"))
  expect_equal(s$dropped$tasks, c(2, 0))
  expect_match(s$dropped$reason[1], "only 2 completed task")
})

test_that("tasks outside 07:00-10:00 or without both times are not counted", {
  tasks <- rbind(tk("T1", "06:59:00", "07:10:00"),      # assigned before the window
                 tk("T2", "10:00:00", "10:10:00"),      # at 10:00 = outside [07:00, 10:00)
                 tk("T3", "07:10:00", "07:20:00"))
  tasks$arrived_at[3] <- as.POSIXct(NA, tz = "UTC")
  s <- response_subgroups(tasks, "2026-10-05")
  expect_equal(nrow(s$values), 0)
  expect_equal(s$dropped$tasks, 0)
})

test_that("no tasks at all: every window is dropped, nothing errors", {
  s <- response_subgroups(tk("T1", "07:10:00", "07:20:00")[0, ], c("2026-10-05"))
  expect_equal(nrow(s$values), 0)
  expect_equal(nrow(s$dropped), 1)
})

# ---------------------------------------------------------------- Shapiro-Wilk
test_that("Shapiro-Wilk: NA with a reason for n < 3, a constant sample, or n > 5000", {
  expect_true(is.na(normality_check(c(1, 2))$p_value))
  expect_match(normality_check(c(1, 2))$note, "at least 3")
  const <- normality_check(c(5, 5, 5, 5))
  expect_true(is.na(const$w))
  expect_match(const$note, "identical")
  big <- normality_check(rnorm(6000))
  expect_true(is.na(big$w))
  expect_match(big$note, "5000")
})

test_that("Shapiro-Wilk agrees with stats::shapiro.test", {
  x <- c(10, 12, 14, 11, 13, 15, 9, 12, 15)
  n <- normality_check(x)
  ref <- stats::shapiro.test(x)
  expect_equal(n$w, unname(ref$statistic))
  expect_equal(n$p_value, ref$p.value)
  expect_equal(n$n, 9)
  expect_match(n$note, "not a proof")
})

# ---------------------------------------------------------------- prep helpers
test_that("onset_window_table counts onsets per date on the fixed station set", {
  g1 <- rbind(make_state_grid("A", strsplit("S X S X", " ")[[1]]),
              make_state_grid("Z", strsplit("S X S X", " ")[[1]]))    # Z is not in the fixed set
  g2 <- make_state_grid("A", strsplit("S S S S", " ")[[1]], first = "2026-10-06 07:00")
  tbl <- onset_window_table(list("2026-10-05" = g1, "2026-10-06" = g2), "A", c("2026-10-05", "2026-10-06"))
  expect_equal(tbl$window, c("2026-10-05", "2026-10-06"))
  expect_equal(tbl$onsets, c(2, 0))
})
