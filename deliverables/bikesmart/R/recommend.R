# recommend.R
# -------------------------------------------------------------------------
# PURPOSE: Pick the best dock for a rider's pickup or drop-off.
#
# This is the user-facing decision layer. It takes a table of candidate
# docks (each with an availability probability and a distance/time) and
# applies a simple decision rule:
#   1. Among docks that meet the probability threshold, pick the closest.
#   2. If no dock meets the threshold, pick the one with the highest
#      probability (the "best available" fallback).
#
# recommend_dock() is intentionally lightweight: it does not compute
# probabilities itself. The calling code (or a teammate's API handler)
# is responsible for running get_bike_availability() or
# get_slot_availability() on each candidate first, then passing the
# results here.
#
# This file contains one exported function: recommend_dock()
# -------------------------------------------------------------------------

#' @name recommend_dock
#' @title Recommend the Best Dock for Pickup or Drop-Off
#' @description
#' Given a data frame of candidate docks with their availability
#' probabilities and distances (or walk times), applies a threshold rule
#' to select the best one for the rider.
#'
#' **Decision rule:**
#' 1. Drop any candidate whose probability is `NA`.
#' 2. Among candidates with `p >= threshold`, choose the one with the
#'    smallest `minutes` (ties broken by higher `p`).
#' 3. If no candidate meets the threshold, choose the one with the highest
#'    `p` (ties broken by smallest `minutes`). A warning is attached to
#'    the output.
#'
#' @param candidates A data frame with at least the following columns:
#'   \describe{
#'     \item{`dock_id`}{Character. Dock identifier.}
#'     \item{`minutes`}{Numeric. Estimated walk (or ride) time to this dock
#'       in minutes.}
#'     \item{`p`}{Numeric in [0,1]. Availability probability from
#'       [get_bike_availability()] or [get_slot_availability()].}
#'   }
#'   Any additional columns (e.g. `name`, `lat`, `lon`) are passed through
#'   to the output unchanged.
#' @param threshold Numeric in (0, 1]. The minimum acceptable probability.
#'   Defaults to `0.90` (90% confidence a bike/slot will be there).
#'
#' @return A named list with:
#'   \describe{
#'     \item{`choice`}{A one-row data frame: the recommended dock with all
#'       columns from `candidates`.}
#'     \item{`alternatives`}{A data frame of up to two runner-up docks
#'       (the next-closest that also meet the threshold, if any).}
#'     \item{`reason`}{Character. One of `"threshold met"` or
#'       `"no dock met threshold – best available returned"`.}
#'   }
#'
#' @author Big Red Crew
#' @import dplyr
#' @export
#'
#' @examples
#' candidates <- data.frame(
#'   dock_id = c("DockA", "DockB", "DockC"),
#'   minutes = c(10, 20, 5),
#'   p       = c(0.61, 0.95, 0.39)
#' )
#' # DockB wins: only one that meets the 0.90 threshold
#' recommend_dock(candidates, threshold = 0.90)
#'
#' # Lower threshold: DockA (10 min, p=0.61) beats DockB (20 min, p=0.95)
#' recommend_dock(candidates, threshold = 0.60)
recommend_dock <- function(candidates, threshold = 0.90) {
  # --- input checks --------------------------------------------------------
  stopifnot(
    is.data.frame(candidates),
    all(c("dock_id", "minutes", "p") %in% names(candidates)),
    nrow(candidates) >= 1L,
    is.numeric(threshold), length(threshold) == 1L,
    threshold > 0, threshold <= 1
  )

  # Drop rows with missing probability (dock data unavailable)
  valid <- filter(candidates, !is.na(p))

  if (nrow(valid) == 0L)
    stop("All candidates have missing probability (p = NA). ",
         "Run get_bike_availability() / get_slot_availability() first.")

  # --- apply decision rule -------------------------------------------------
  above_threshold <- filter(valid, p >= threshold)

  if (nrow(above_threshold) >= 1L) {
    # Sort by minutes ascending, then p descending for ties
    ranked  <- arrange(above_threshold, minutes, desc(p))
    reason  <- "threshold met"
  } else {
    # Fall back: highest p, ties broken by fewest minutes
    ranked  <- arrange(valid, desc(p), minutes)
    reason  <- "no dock met threshold - best available returned"
    warning("No candidate dock reached p >= ", threshold,
            ". Returning best available (p = ", round(ranked$p[1], 4), ").")
  }

  choice       <- ranked[1, , drop = FALSE]
  alternatives <- if (nrow(ranked) > 1L) ranked[2:min(3, nrow(ranked)), , drop = FALSE] else
                  data.frame()

  list(
    choice       = choice,
    alternatives = alternatives,
    reason       = reason
  )
}

