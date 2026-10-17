# Empirical availability and empirical reliability R(tau) (tier 3, docs/methods.md 4.2 items 1-2).
# Every statistic of this tab's lower panel lives here; app.R and prep.R only call and display.
#
# The idea, in words. The station grid gives, for every station and minute, "known" and "usable"
# at the SAME minutes. We look at those joint observations directly, so stations are NOT assumed
# independent. Three service structures:
#   series   (a trip)   origin rent-usable at minute m AND destination return-usable at minute m + d
#   parallel            at least one of the chosen stations is usable at minute m
#   kofn                at least k of the n chosen stations are usable at minute m
# Availability = (minutes in which the condition holds) / (minutes in which it can be judged).
# Reliability R(tau) = (start minutes m whose condition holds in EVERY minute m, ..., m+tau-1) /
#                      (start minutes whose tau minutes can all be judged).
# The "independence formula" value is a CONTRAST only (series: product, parallel: 1 - product of
# (1 - A_i), k-out-of-n: Poisson-binomial tail), computed from each station's own availability.
#
# Convention: a matrix M has one row per minute (in time order) and one column per station (or per
# role in a series). Values are 1/TRUE usable, 0/FALSE unusable, NA unknown (or out of range).
# NA is never treated as usable or unusable: a minute with an NA in any needed column is left out
# of BOTH the numerator and the denominator.

NO_KNOWN_REASON <- "no minute where all stations involved are known"

#' Series (trip) alignment. Input : origin_usable, dest_usable = vectors over minutes 0..n-1
#'   (the origin's rent-usable flag, the destination's return-usable flag), d = trip time in minutes.
#' Output: an n x 2 matrix. Row m holds (origin at m, destination at m + d); for m + d > n - 1 the
#'   destination is outside the window and is NA, so those start minutes drop out.
align_series <- function(origin_usable, dest_usable, d = 15) {
  if (length(origin_usable) != length(dest_usable)) stop("origin and destination must have the same length.", call. = FALSE)
  if (length(d) != 1 || is.na(d) || d < 0 || d != round(d)) stop("d must be a whole number of minutes, 0 or more.", call. = FALSE)
  n <- length(origin_usable)
  later <- seq_len(n) + d
  dest_shifted <- ifelse(later <= n, as.numeric(dest_usable)[pmin(later, n)], NA_real_)
  cbind(origin = as.numeric(origin_usable), destination = dest_shifted)
}

#' Stack several days (matrices with the same columns) into one, with `gap` NA rows between days,
#' so that a reliability window can never run from one day into the next.
pool_days <- function(mats, gap = 30) {
  if (length(mats) == 0) stop("no days to pool.", call. = FALSE)
  pad <- matrix(NA_real_, nrow = gap, ncol = ncol(mats[[1]]))
  out <- mats[[1]]
  for (m in mats[-1]) out <- rbind(out, pad, m)
  out
}

# The condition at each minute: TRUE / FALSE, or NA when any needed column is NA.
condition_vector <- function(M, structure, k = NULL) {
  M <- as.matrix(M)
  known <- rowSums(is.na(M)) == 0
  hits <- rowSums(M, na.rm = TRUE)
  holds <- switch(structure, series = hits == ncol(M), parallel = hits >= 1, kofn = hits >= k)
  ifelse(known, holds, NA)
}

# P(at least k successes) for independent successes with probabilities p (Poisson-binomial, by recursion).
poisson_binomial_tail <- function(p, k) {
  dist <- 1                                   # dist[j + 1] = P(j successes so far)
  for (pi in p) dist <- c(dist * (1 - pi), 0) + c(0, dist * pi)
  sum(dist[(k + 1):length(dist)])
}

# The independence-formula value from each column's own availability over the eligible minutes.
# A contrast only: it assumes the stations are independent, which the data need not satisfy.
independence_value <- function(M, eligible, structure, k = NULL) {
  p <- colMeans(as.matrix(M)[eligible, , drop = FALSE])
  switch(structure,
         series = prod(p),
         parallel = 1 - prod(1 - p),
         kofn = poisson_binomial_tail(p, k))
}

#' Empirical availability and reliability of one structure.
#' Input : M = minutes x stations matrix (see the convention above); structure = "series",
#'         "parallel" or "kofn"; k (kofn only, 1 <= k <= n); tau = reliability horizon in minutes.
#' Output: a list: availability, avail_hold, avail_n (eligible minutes), independence (contrast),
#'         reliability, rel_hold, rel_n (eligible start minutes), tau, and a reason for every NA.
reliability_summary <- function(M, structure = c("series", "parallel", "kofn"), k = NULL, tau = 30) {
  structure <- match.arg(structure)
  M <- as.matrix(M)
  n_st <- ncol(M)
  if (length(tau) != 1 || is.na(tau) || tau < 1 || tau != round(tau)) stop("tau must be a whole number of minutes, 1 or more.", call. = FALSE)
  if (structure == "series" && n_st != 2) stop("a series needs exactly 2 columns (origin, destination).", call. = FALSE)
  if (structure == "kofn" && (is.null(k) || length(k) != 1 || is.na(k) || k < 1 || k > n_st || k != round(k))) {
    stop("k must be a whole number from 1 to n (n = ", n_st, " stations).", call. = FALSE)
  }
  cond <- condition_vector(M, structure, k)
  eligible <- !is.na(cond)
  n_el <- sum(eligible)
  out <- list(structure = structure, k = if (structure == "kofn") k else NA_integer_, n_stations = n_st, tau = tau,
              availability = NA_real_, avail_hold = NA_integer_, avail_n = n_el, independence = NA_real_,
              reliability = NA_real_, rel_hold = NA_integer_, rel_n = 0L, avail_reason = "", rel_reason = "")
  if (n_el == 0) {
    out$avail_reason <- NO_KNOWN_REASON
    out$rel_reason <- NO_KNOWN_REASON
    return(out)
  }
  out$avail_hold <- sum(cond[eligible])
  out$availability <- out$avail_hold / n_el
  out$independence <- independence_value(M, eligible, structure, k)

  # Reliability: for every start row s, the tau rows s..s+tau-1 must all be judgeable (non-NA),
  # and the condition must hold in all of them. Counted with running sums.
  N <- length(cond)
  if (N < tau) {
    out$rel_reason <- paste0("fewer than ", tau, " consecutive minutes where all stations involved are known")
    return(out)
  }
  cs <- function(x) c(0, cumsum(x))
  ok_cs <- cs(eligible)
  true_cs <- cs(cond %in% TRUE)
  starts <- seq_len(N - tau + 1)
  ends <- starts + tau - 1
  all_known <- (ok_cs[ends + 1] - ok_cs[starts]) == tau
  all_true <- (true_cs[ends + 1] - true_cs[starts]) == tau
  out$rel_n <- sum(all_known)
  if (out$rel_n == 0) {
    out$rel_reason <- paste0("fewer than ", tau, " consecutive minutes where all stations involved are known")
    return(out)
  }
  out$rel_hold <- sum(all_true & all_known)
  out$reliability <- out$rel_hold / out$rel_n
  out
}

# Build the minutes x stations matrix of one usable role from a grid (qc.R build_grid columns).
# usable = "rent" (not rent_unusable), "return" (not return_unusable) or "either" (neither unusable).
# Unknown minutes stay NA. Rows are put in minute order, whatever the order of the grid rows.
grid_usable_matrix <- function(grid, station_ids, usable = c("either", "rent", "return")) {
  usable <- match.arg(usable)
  missing_ids <- setdiff(station_ids, grid$station_id)
  if (length(missing_ids) > 0) stop("station(s) not in the grid: ", paste(missing_ids, collapse = ", "), ".", call. = FALSE)
  col <- switch(usable, rent = "rent_unusable", `return` = "return_unusable", either = "either_unusable")
  cols <- lapply(station_ids, function(id) {
    g <- grid[grid$station_id == id, ]
    g <- g[order(g$minute), ]
    ifelse(g$known, as.numeric(!g[[col]]), NA_real_)
  })
  if (length(unique(lengths(cols))) != 1) stop("the stations do not have the same minutes in the grid.", call. = FALSE)
  M <- do.call(cbind, cols)
  colnames(M) <- station_ids
  M
}

#' The wrapper from the grid of ONE day.
#' series  : origin (rent-usable) and destination (return-usable) station ids, trip time d.
#' parallel / kofn : stations = ids, usable = "rent", "return" or "either" (default "either").
#' Returns reliability_summary(...).
reliability_from_grid <- function(grid, structure = c("series", "parallel", "kofn"), origin = NULL,
                                  destination = NULL, d = 15, stations = NULL, k = NULL,
                                  usable = "either", tau = 30) {
  structure <- match.arg(structure)
  M <- if (structure == "series") {
    if (is.null(origin) || is.null(destination)) stop("a series needs an origin and a destination.", call. = FALSE)
    o <- grid_usable_matrix(grid, origin, "rent")
    de <- grid_usable_matrix(grid, destination, "return")
    align_series(o[, 1], de[, 1], d)
  } else {
    if (length(stations) < 1) stop("choose at least one station.", call. = FALSE)
    grid_usable_matrix(grid, stations, usable)
  }
  reliability_summary(M, structure, k = k, tau = tau)
}

#' The same over several days (pooled). `grids` = list of day grids. Day matrices are stacked with a
#' gap of NA rows (see pool_days), so availability pools minutes and R(tau) pools start minutes.
reliability_from_grids <- function(grids, structure = c("series", "parallel", "kofn"), origin = NULL,
                                   destination = NULL, d = 15, stations = NULL, k = NULL,
                                   usable = "either", tau = 30) {
  structure <- match.arg(structure)
  mats <- lapply(grids, function(g) {
    if (structure == "series") {
      align_series(grid_usable_matrix(g, origin, "rent")[, 1], grid_usable_matrix(g, destination, "return")[, 1], d)
    } else grid_usable_matrix(g, stations, usable)
  })
  reliability_summary(pool_days(mats, gap = max(tau, 30)), structure, k = k, tau = tau)
}
