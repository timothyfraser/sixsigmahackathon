# aggregate.R
# -------------------------------------------------------------------------
# PURPOSE: Convert the raw three-column bike snapshot data into a
# dock-level summary that the rest of the package uses.
#
# The raw simulation data (produced by simulate_data.R) has one row per
# bike per five-minute snapshot:
#   BIKEID  - unique bike identifier (e.g. "JC-B0001")
#   DOCID   - station name the bike is at, or "0" if the bike is in transit
#   time    - POSIXct timestamp of the snapshot (5-minute intervals)
#
# aggregate_snapshots() collapses those rows into one row per dock per
# snapshot, counting how many bikes are currently docked. From that
# dock-level time series the availability and recommendation functions
# can compute flow rates, fill levels, and probabilities.
#
# This file contains one exported function: aggregate_snapshots()
# -------------------------------------------------------------------------

#' @name aggregate_snapshots
#' @title Aggregate Raw Bike Snapshots to Dock Level
#' @description
#' Takes the raw three-column movement data (one row per bike per timestamp)
#' and collapses it to one row per dock per timestamp, counting the number
#' of bikes currently at each dock. Rows where `DOCID == "0"` (bikes in
#' transit) are excluded from dock counts. The resulting data frame is the
#' input expected by [get_bike_availability()] and [get_slot_availability()].
#'
#' @param snapshots A data frame with columns `BIKEID` (character),
#'   `DOCID` (character), and `time` (POSIXct or character). Produced by
#'   `simulate_data.R` or loaded with `readRDS()` / `read.csv()`.
#' @param stations A data frame with at least a `dockID` column (character)
#'   and optionally `capacity` (integer, docking slots available), `name`,
#'   `lat`, `lon`. Loaded from `data/stations/<city>.csv`. If `capacity` is
#'   not present, a default value is assumed (see `default_capacity`).
#' @param default_capacity Integer. Capacity to assume for any dock not
#'   present in `stations` or missing a `capacity` value. Defaults to 30,
#'   which matches the simulation setup in `simulate_data.R`.
#'
#' @return A data frame with columns:
#'   \describe{
#'     \item{`DOCID`}{Character. Dock identifier (matches `stations$dockID`).}
#'     \item{`time`}{POSIXct. Snapshot timestamp.}
#'     \item{`bikes`}{Integer. Number of bikes at this dock at this timestamp.}
#'     \item{`capacity`}{Integer. Total docking slots at this dock.}
#'   }
#'
#' @author Big Red Crew
#' @import dplyr
#' @export
#'
#' @examples
#' \dontrun{
#' movement  <- readRDS("data/jersey_city.rds")
#' stations  <- read.csv("data/stations/jersey_city.csv",
#'                        colClasses = "character")
#' dock_data <- aggregate_snapshots(movement, stations)
#' head(dock_data)
#' }
# ------------------------------------------------------------------------------
# aggregate_snapshots
# ------------------------------------------------------------------------------
# Short description: Collapses raw bike-level snapshot logs into dock-level
# counts of docked bikes at each time step.

aggregate_snapshots <- function(snapshots, stations,
                                default_capacity = 30L) {
  # --- input checks --------------------------------------------------------
  stopifnot(
    is.data.frame(snapshots),
    all(c("BIKEID", "DOCID", "time") %in% names(snapshots)),
    is.data.frame(stations),
    "dockID" %in% names(stations)
  )

  # Ensure time is POSIXct (handles the case where snapshots come from a CSV
  # and time was read as character).
  if (!inherits(snapshots$time, "POSIXct")) {
    snapshots$time <- as.POSIXct(snapshots$time,
                                  format = "%Y-%m-%dT%H:%M:%S%z")
  }

  # --- attach capacity from stations lookup --------------------------------
  cap_lookup <- stations %>%
    select(dockID, any_of("capacity")) %>%
    rename(DOCID = dockID)

  if (!"capacity" %in% names(cap_lookup)) {
    cap_lookup <- cap_lookup %>% mutate(capacity = default_capacity)
  }

  # --- count bikes per dock per snapshot -----------------------------------
  # Exclude transit rows (DOCID == "0"); those bikes are not at any dock.
  snapshots %>%
    filter(DOCID != "0") %>%
    count(DOCID, time, name = "bikes") %>%
    left_join(cap_lookup, by = "DOCID") %>%
    mutate(
      bikes    = as.integer(bikes),
      capacity = as.integer(replace(capacity,
                                    is.na(capacity),
                                    default_capacity))
    )
}

