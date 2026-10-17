# distances.R
# -------------------------------------------------------------------------
# PURPOSE: Expose dock distance information to package users.
#
# The simulation pipeline (prepare_networks.py) pre-computes pairwise
# shortest-path distances between every dock pair in a city and stores
# them in data/distances/<city>.csv (long format, 729 rows for 27 docks).
# Those files are the ground truth for how far apart docks are.
#
# dock_distances() loads and filters that distance grid, making it easy
# for a package user (or a calling function like recommend_dock()) to
# find how far a given starting location is from each candidate dock.
#
# This file contains one exported function: dock_distances()
# -------------------------------------------------------------------------

#' @name dock_distances
#' @title Look Up Distances Between Docks
#' @description
#' Filters the pre-computed pairwise distance matrix for a city to return
#' the distances from one or more origin docks to all (or a subset of)
#' destination docks. The distance matrix is the long-form CSV produced by
#' `data/prepare_networks.py` (columns: `dockID1`, `dockID2`, `distance`
#' in miles).
#'
#' When planning a trip you typically want "how far is each candidate pickup
#' dock from where I am standing?". If your starting point is a known dock,
#' pass its name as `from`. Otherwise, use the `lat`/`lon` variant (not yet
#' implemented in v0.1; see the `Note` section below).
#'
#' @param distance_grid A data frame with columns `dockID1` (character),
#'   `dockID2` (character), and `distance` (numeric, miles). Load with
#'   `read.csv("data/distances/<city>.csv")`.
#' @param from Character vector. One or more `dockID` values to use as
#'   origins. If `NULL` (default), all origins in the grid are returned.
#' @param to Character vector. One or more `dockID` values to use as
#'   destinations. If `NULL` (default), all destinations are returned.
#' @param max_miles Numeric. If supplied, only rows with `distance <=
#'   max_miles` are returned. Useful for filtering to "nearby" docks.
#'   Defaults to `Inf` (no filter).
#'
#' @return A data frame with columns `dockID1` (origin), `dockID2`
#'   (destination), and `distance` (miles), filtered to the requested
#'   origins, destinations, and distance ceiling, sorted by distance.
#'
#' @note
#' **v0.1 limitation:** this function only works when the origin is a known
#' dock in the grid. A future version will accept arbitrary `(lat, lon)`
#' coordinates and compute a haversine approximation to the nearest dock.
#'
#' @author Big Red Crew
#' @import dplyr
#' @export
#'
#' @examples
#' \dontrun{
#' grid <- read.csv("data/distances/jersey_city.csv",
#'                   colClasses = c("character", "character", "numeric"))
#'
#' # All docks reachable from one starting dock within 1 mile
#' dock_distances(grid, from = "Hamilton Park", max_miles = 1)
#'
#' # Distance between two specific docks (one pair)
#' dock_distances(grid, from = "Hamilton Park", to = "Grove St PATH")
#' }
# ------------------------------------------------------------------------------
# dock_distances
# ------------------------------------------------------------------------------
# Short description: Filters and looks up road network distances between dock pairs.

dock_distances <- function(distance_grid,
                            from      = NULL,
                            to        = NULL,
                            max_miles = Inf) {
  # --- input checks --------------------------------------------------------
  stopifnot(
    is.data.frame(distance_grid),
    all(c("dockID1", "dockID2", "distance") %in% names(distance_grid)),
    is.numeric(distance_grid$distance),
    is.numeric(max_miles), length(max_miles) == 1L, max_miles > 0
  )

  result <- distance_grid

  if (!is.null(from)) {
    stopifnot(is.character(from))
    result <- filter(result, dockID1 %in% from)
    if (nrow(result) == 0L)
      warning("No rows matched the 'from' dock(s): ",
              paste(from, collapse = ", "))
  }

  if (!is.null(to)) {
    stopifnot(is.character(to))
    result <- filter(result, dockID2 %in% to)
  }

  if (is.finite(max_miles)) {
    result <- filter(result, distance <= max_miles)
  }

  arrange(result, distance)
}

