# app/survival.R - historical Kaplan-Meier time to first service failure (team 2027win)
#
# Plain base-R functions (no packages). Method: docs/methods.md 4.2 tier 2 item 4 and KA-8.
# This is DESCRIPTIVE about past days. It is not a forecast (the forecast is a later task).
#
# Contents
#   1. station_day_obs   one day's grid -> one (time, event) per usable-at-07:00 station
#   2. km_fit            Kaplan-Meier product-limit estimate + Greenwood log-log interval
#   3. km_at, km_rmst    the curve at a time, and the area under it
#   4. km_summary        counts, F(10/20/30), RMST, MTTF, notes for one set of (time, event)
#   5. km_history        grids of many days -> observations -> summary
#
# Conventions (stated, not hidden):
#   * Time is minutes from 07:00 to the START of the first unusable minute: a failure in
#     the interval [07:05, 07:06) has time 5.
#   * Origin: a station-day is observed only if its 07:00 interval is known AND usable
#     (either-unusable FALSE). Otherwise it gives no observation and is counted by reason.
#   * Censoring: at 180 (10:00) if never unusable, or at the start of the first unknown
#     minute if that comes before any unusable minute (the gap is not guessed).
#   * Ties: events are counted before censorings at the same time, so a station-day
#     censored at t is still at risk at t (the standard convention).
#   * S(t) = product over event times t_j <= t of (1 - d_j / n_j), right-continuous.
#   * Greenwood: Var(S) = S^2 * sum d_j / (n_j (n_j - d_j)). Interval: 95% pointwise,
#     log-log transform, S^exp(+-z * se), always inside [0, 1]. It is undefined when
#     d_j = n_j (S = 0), and before the first failure (S = 1, no variance): then the
#     interval is NA with a reason, never Inf.
#   * Assumptions: censoring is non-informative; Greenwood treats station-days as
#     independent, but nearby stations (and the same station on different days) may be
#     correlated, so the intervals may be too narrow.

SURVIVAL_HORIZONS <- c(10, 20, 30)
SURVIVAL_TAU <- 180
KM_MTTF_REASON <- paste("the curve does not reach 0 (largest time is censored): MTTF is not estimable;",
                        "use the RMST to 180 min instead (shown when it is estimable)")
KM_NO_START_REASON <- "no station-day is usable at 07:00: no observation to estimate from"
KM_FAILURE_COLUMN <- c(either = "either_unusable", rent = "rent_unusable", `return` = "return_unusable")

# ---------------------------------------------------------------- 1. observations

#' Station-day observations from ONE day's grid (qc.R build_grid output).
#' Input : grid with station_id, minute, known, rent_unusable, return_unusable, either_unusable;
#'         failure = "either" (default), "rent" or "return" (which unusable minute is the event).
#' Output: list(obs, excluded)
#'   obs      station_id, time (minutes from 07:00), event (1 failure, 0 censored),
#'            end ("failure", "end of window" or "unknown gap")
#'   excluded station_id, reason ("unknown at 07:00" or "unusable at 07:00")
station_day_obs <- function(grid, failure = "either") {
  if (!(length(failure) == 1 && failure %in% names(KM_FAILURE_COLUMN))) {
    stop("failure must be one of: either, rent, return.", call. = FALSE)
  }
  fail_col <- KM_FAILURE_COLUMN[[failure]]
  obs <- list()
  excluded <- list()
  for (id in unique(grid$station_id)) {
    g <- grid[grid$station_id == id, ]
    g <- g[order(g$minute), ]
    k <- nrow(g)                                   # 180 intervals for 07:00-10:00
    if (!isTRUE(g$known[1])) {
      excluded[[length(excluded) + 1]] <- data.frame(station_id = id, reason = "unknown at 07:00")
      next
    }
    if (isTRUE(g$either_unusable[1])) {
      excluded[[length(excluded) + 1]] <- data.frame(station_id = id, reason = "unusable at 07:00")
      next
    }
    later <- seq_len(k)[-1]                        # minutes 1 .. k-1 (minute m is row m + 1)
    failed <- g$known[later] & g[[fail_col]][later] %in% TRUE
    stops <- !g$known[later] | failed              # the first of these ends the follow-up
    first <- which(stops)[1]
    if (is.na(first)) {
      o <- data.frame(station_id = id, time = k, event = 0, end = "end of window")
    } else if (failed[first]) {
      o <- data.frame(station_id = id, time = first, event = 1, end = "failure")
    } else {
      o <- data.frame(station_id = id, time = first, event = 0, end = "unknown gap")
    }
    obs[[length(obs) + 1]] <- o
  }
  bind <- function(l, empty) if (length(l) == 0) empty else do.call(rbind, l)
  list(obs = bind(obs, data.frame(station_id = character(0), time = numeric(0),
                                  event = numeric(0), end = character(0))),
       excluded = bind(excluded, data.frame(station_id = character(0), reason = character(0))))
}

# ---------------------------------------------------------------- 2. Kaplan-Meier

#' Kaplan-Meier estimate with Greenwood variance.
#' Input : time (>= 0, finite), event (1 = failure, 0 = censored), conf = 0.95.
#' Output: list(fit = data.frame(time, n_risk, n_event, surv, greenwood, ci_low, ci_high,
#'         ci_note), ...) with one row per distinct EVENT time; plus n, max_time, conf.
#'         `greenwood` = sum d_j / (n_j (n_j - d_j)) (NA once everyone at risk failed).
km_fit <- function(time, event, conf = 0.95) {
  if (length(time) != length(event)) stop("time and event must have the same length.", call. = FALSE)
  if (anyNA(time) || anyNA(event)) stop("time and event must not have missing values.", call. = FALSE)
  event <- as.numeric(event)
  if (!all(event %in% c(0, 1))) stop("event must be 0 or 1 (or TRUE/FALSE).", call. = FALSE)
  if (!is.numeric(time) || any(!is.finite(time)) || any(time < 0)) {
    stop("time must be finite and not negative.", call. = FALSE)
  }
  if (!(conf > 0 && conf < 1)) stop("conf must be between 0 and 1.", call. = FALSE)
  z <- qnorm(1 - (1 - conf) / 2)

  t_j <- sort(unique(time[event == 1]))
  d <- vapply(t_j, function(t) sum(time == t & event == 1), numeric(1))
  n_at_risk <- vapply(t_j, function(t) sum(time >= t), numeric(1))   # censored at t still at risk
  surv <- cumprod(1 - d / n_at_risk)
  term <- ifelse(n_at_risk > d, d / (n_at_risk * (n_at_risk - d)), NA_real_)
  greenwood <- cumsum(term)                                          # NA once d_j = n_j

  defined <- !is.na(greenwood) & surv > 0 & surv < 1
  se_ll <- rep(NA_real_, length(t_j))
  se_ll[defined] <- sqrt(greenwood[defined]) / abs(log(surv[defined]))
  cll <- rep(NA_real_, length(t_j))
  cll[defined] <- log(-log(surv[defined]))
  ci_low <- exp(-exp(cll + z * se_ll))
  ci_high <- exp(-exp(cll - z * se_ll))
  ci_note <- ifelse(defined, "",
                    "Greenwood interval undefined: every station-day still at risk failed (S = 0)")
  out <- data.frame(time = t_j, n_risk = n_at_risk, n_event = d, surv = surv, greenwood = greenwood,
                    ci_low = ci_low, ci_high = ci_high, ci_note = ci_note, stringsAsFactors = FALSE)
  attr(out, "n") <- length(time)
  attr(out, "max_time") <- if (length(time) > 0) max(time) else NA_real_
  attr(out, "conf") <- conf
  out
}

# ---------------------------------------------------------------- 3. the curve and its area

#' The curve at times t (a right-continuous step function: events at t are included).
#' Output: data.frame(t, surv, ci_low, ci_high, note). Before the first failure S = 1 and the
#' interval is NA (no variance yet). Beyond the largest observed time, while S > 0, nothing was
#' observed: all NA with a reason. S = 0 has no Greenwood interval (NA, with a reason).
km_at <- function(fit, t) {
  idx <- findInterval(t, fit$time)                 # 0 = before the first failure
  surv <- ifelse(idx == 0, 1, fit$surv[pmax(idx, 1)])
  lo <- ifelse(idx == 0, NA_real_, fit$ci_low[pmax(idx, 1)])
  hi <- ifelse(idx == 0, NA_real_, fit$ci_high[pmax(idx, 1)])
  note <- ifelse(idx == 0, "no failure has occurred by this time: the interval is not defined",
                 fit$ci_note[pmax(idx, 1)])
  beyond <- t > attr(fit, "max_time") & surv > 0
  surv[beyond] <- NA_real_
  lo[beyond] <- NA_real_
  hi[beyond] <- NA_real_
  note[beyond] <- "beyond the largest observed time: not observed"
  data.frame(t = t, surv = surv, ci_low = lo, ci_high = hi, note = note, stringsAsFactors = FALSE)
}

#' Restricted mean survival time: the area under S from 0 to tau (minutes).
#' Output: list(value, note). NA (with a reason) when tau is beyond the largest observed
#' time and the curve has not reached 0, because the area there was not observed.
km_rmst <- function(fit, tau = SURVIVAL_TAU) {
  if (length(tau) != 1 || !is.finite(tau) || tau <= 0) stop("tau must be one positive number.", call. = FALSE)
  if (is.na(attr(fit, "max_time"))) return(list(value = NA_real_, note = "no observations"))
  inside <- fit$time < tau
  edges <- c(0, fit$time[inside], tau)
  levels <- c(1, fit$surv[inside])
  if (tau > attr(fit, "max_time") && tail(levels, 1) > 0) {
    return(list(value = NA_real_, note = paste0("tau = ", tau, " min is beyond the largest observed time (",
                                                attr(fit, "max_time"), " min) and the curve has not reached 0")))
  }
  list(value = sum(levels * diff(edges)), note = "")
}

# ---------------------------------------------------------------- 4. summary

#' Everything the History panel shows for one set of (time, event).
#' Output: list(n, events, censored, fit, horizons, rmst, rmst_tau, rmst_note, mttf, mttf_note,
#'         notes, reason, max_time)
#'   horizons = data.frame(t, surv, F, F_low, F_high, note), F = 1 - S, F interval from the S interval.
#'   mttf = the full area under S, ONLY when the curve reaches 0 (the last failure leaves nobody at risk).
#'   reason = "" or why nothing can be estimated (n = 0).
km_summary <- function(time, event, horizons = SURVIVAL_HORIZONS, tau = SURVIVAL_TAU, conf = 0.95) {
  fit <- km_fit(time, event, conf)
  n <- length(time)
  events <- sum(event == 1)
  empty_h <- data.frame(t = horizons, surv = NA_real_, F = NA_real_, F_low = NA_real_, F_high = NA_real_,
                        note = KM_NO_START_REASON, stringsAsFactors = FALSE)
  if (n == 0) {
    return(list(n = 0, events = 0, censored = 0, fit = fit, horizons = empty_h,
                rmst = NA_real_, rmst_tau = tau, rmst_note = KM_NO_START_REASON,
                mttf = NA_real_, mttf_note = KM_NO_START_REASON, notes = KM_NO_START_REASON,
                reason = KM_NO_START_REASON, max_time = NA_real_))
  }
  at <- km_at(fit, horizons)
  h <- data.frame(t = horizons, surv = at$surv, F = 1 - at$surv, F_low = 1 - at$ci_high,
                  F_high = 1 - at$ci_low, note = at$note, stringsAsFactors = FALSE)
  notes <- character(0)
  if (events == 0) {
    notes <- sprintf(paste("no failures observed in these %d station-days; this does not show the risk",
                           "is zero"), n)
    h$note <- ifelse(is.na(h$F), h$note, "no failure observed: the interval is not defined")
  }
  rm <- km_rmst(fit, tau)
  reaches_zero <- nrow(fit) > 0 && tail(fit$surv, 1) == 0
  mttf <- if (reaches_zero) km_rmst(fit, tail(fit$time, 1))$value else NA_real_
  list(n = n, events = events, censored = n - events, fit = fit, horizons = h,
       rmst = rm$value, rmst_tau = tau, rmst_note = rm$note,
       mttf = mttf, mttf_note = if (reaches_zero) "" else KM_MTTF_REASON,
       notes = notes, reason = "", max_time = attr(fit, "max_time"))
}

# ---------------------------------------------------------------- 5. many days

#' History from the per-day grids.
#' Input : grids = list of build_grid outputs named by date, dates = the dates to use (in order),
#'         failure = "either" / "rent" / "return".
#' Output: list(obs, excluded, counts, summary, failure, dates)
#'   obs      date, station_id, time, event, end
#'   excluded date, station_id, reason
#'   counts   one-row data.frame: days, stations_days (all station-days seen), n (observed),
#'            events, cens_end (censored at 10:00), cens_gap (censored at an unknown gap),
#'            excl_unknown, excl_unusable
#'   summary  km_summary() of obs
km_history <- function(grids, dates, failure = "either", horizons = SURVIVAL_HORIZONS,
                       tau = SURVIVAL_TAU, conf = 0.95) {
  dates <- intersect(dates, names(grids))
  obs <- list()
  excl <- list()
  for (d in dates) {
    r <- station_day_obs(grids[[d]], failure)
    if (nrow(r$obs) > 0) obs[[length(obs) + 1]] <- cbind(date = d, r$obs, stringsAsFactors = FALSE)
    if (nrow(r$excluded) > 0) excl[[length(excl) + 1]] <- cbind(date = d, r$excluded, stringsAsFactors = FALSE)
  }
  obs <- if (length(obs) == 0) data.frame(date = character(0), station_id = character(0), time = numeric(0),
                                          event = numeric(0), end = character(0)) else do.call(rbind, obs)
  excl <- if (length(excl) == 0) data.frame(date = character(0), station_id = character(0),
                                            reason = character(0)) else do.call(rbind, excl)
  counts <- data.frame(
    days = length(dates), station_days = nrow(obs) + nrow(excl), n = nrow(obs),
    events = sum(obs$event == 1), cens_end = sum(obs$end == "end of window"),
    cens_gap = sum(obs$end == "unknown gap"),
    excl_unknown = sum(excl$reason == "unknown at 07:00"),
    excl_unusable = sum(excl$reason == "unusable at 07:00"))
  list(obs = obs, excluded = excl, counts = counts, failure = failure, dates = dates,
       summary = km_summary(obs$time, obs$event, horizons, tau, conf))
}

