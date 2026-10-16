test_that("KA-2: p-bar 0.050, UCL 0.115, LCL 0, no signals", {
  p <- p_chart(failures = c(4, 6, 5, 3, 7), n = rep(100, 5))
  expect_near(p$p_bar, 0.05)
  expect_near(p$data$ucl[1], 0.115383)
  expect_equal(p$data$lcl[1], 0)
  expect_false(any(p$data$out_of_control))
})

test_that("KA-2b: UCL is capped at 1 and LCL floored at 0", {
  p <- p_chart(failures = c(50, 50, 2), n = c(100, 100, 4), baseline = c(TRUE, TRUE, FALSE))
  expect_near(p$p_bar, 0.5)
  expect_equal(p$data$ucl[3], 1)
  expect_equal(p$data$lcl[3], 0)
})

test_that("KA-2c: zero failures keeps counts and p, limits NA with a reason", {
  p <- p_chart(failures = c(0, 0, 0), n = c(100, 100, 100))
  expect_equal(p$totals[["failures"]], 0)
  expect_equal(p$totals[["n"]], 300)
  expect_equal(p$data$p, c(0, 0, 0))
  expect_true(all(is.na(p$data$ucl)) && all(is.na(p$data$lcl)))
  expect_match(p$note, "p-bar = 0: limits cannot be estimated; no failures observed does not mean zero risk",
               fixed = TRUE)
})

test_that("changing the baseline changes the limits", {
  all5 <- p_chart(c(4, 6, 5, 3, 7), rep(100, 5))
  two <- p_chart(c(4, 6, 5, 3, 7), rep(100, 5), baseline = c(2, 5))
  expect_near(two$p_bar, 0.065)
  expect_true(abs(two$data$ucl[1] - all5$data$ucl[1]) > 0.001)
})

test_that("p chart flags rule 1 (point above UCL) and rule 4 (8 in a row)", {
  p <- p_chart(failures = c(5, 5, 5, 5, 5, 30), n = rep(100, 6), baseline = 1:5)
  expect_true(p$data$rule1[6])
  expect_false(any(p$data$rule1[1:5]))
  # points 3 to 10 sit above the centre line (0.05), so the run reaches 8 at point 10
  q <- p_chart(failures = c(5, 4, 6, 6, 6, 6, 6, 6, 6, 6), n = rep(100, 10), baseline = 1:3)
  expect_near(q$p_bar, 0.05)
  expect_false(any(q$data$rule4[1:9]))
  expect_true(q$data$rule4[10])
})

test_that("n_i = 0 gives p NA with a note; one baseline subgroup gives NA limits", {
  p <- p_chart(failures = c(2, 0, 3), n = c(100, 0, 100))
  expect_true(is.na(p$data$p[2]))
  expect_match(p$note, "n = 0")
  one <- p_chart(failures = c(2, 3), n = c(100, 100), baseline = 1)
  expect_true(all(is.na(one$data$ucl)))
  expect_match(one$note, "fewer than 2")
  expect_equal(one$data$p, c(0.02, 0.03))
})

test_that("p chart rejects impossible input", {
  expect_error(p_chart(failures = 5, n = 3), "failures")
  expect_error(p_chart(failures = c(1, 2), n = 10), "same length")
})

test_that("KA-3: I-MR centre 32, MR-bar 5.5, sigma 4.8759, limits 17.372 / 46.628, MR UCL 17.969", {
  r <- imr_chart(c(30, 34, 28, 36, 32))
  expect_near(r$center, 32)
  expect_equal(r$data$mr[-1], c(4, 6, 8, 4))
  expect_near(r$mr_bar, 5.5)
  expect_near(r$sigma_hat, 4.875887)
  expect_near(r$ucl, 46.628)
  expect_near(r$lcl, 17.372)
  expect_near(r$mr_ucl, 17.9685, 1e-6)  # 3.267 * 5.5 = 17.9685 exactly; methods.md rounds to 17.969
  expect_equal(r$mr_lcl, 0)
  expect_false(any(r$data$out_of_control))
})

test_that("I-MR constant data: limits NA, zero variation, data still shown", {
  r <- imr_chart(rep(30, 5))
  expect_true(is.na(r$ucl) && is.na(r$lcl) && is.na(r$sigma_hat))
  expect_match(r$note, "zero variation")
  expect_equal(r$center, 30)
  expect_equal(r$data$x, rep(30, 5))
  expect_equal(r$data$mr[-1], rep(0, 4))
})

test_that("I-MR with fewer than 2 baseline points: limits NA with a note", {
  r <- imr_chart(c(30, 34, 28), baseline = 1)
  expect_true(is.na(r$ucl))
  expect_match(r$note, "fewer than 2")
  expect_equal(r$center, 30)
})

test_that("I-MR flags a planted shift with rule 1 and rule 4", {
  x <- c(30, 34, 28, 36, 32, 30, 33, 31, 60)
  r <- imr_chart(x, baseline = 1:5)
  expect_true(r$data$rule1[9])
  y <- c(30, 34, 28, 36, 32, rep(35, 8))
  r2 <- imr_chart(y, baseline = 1:5)
  expect_true(r2$data$rule4[13])
  expect_false(r2$data$rule4[11])
})
