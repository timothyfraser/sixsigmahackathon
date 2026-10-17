# availability.R
# -------------------------------------------------------------------------
# PURPOSE: Compute the probability that a rider finds a bike (or an open
# docking slot) at a given dock at a given time.
#
# This is the statistical core of the package (corresponds to CONTRACT task
# H-03). The approach uses Poisson-based flow rates:
#   - lam_out: average departures (pickups) per snapshot at a dock
#   - lam_in:  average arrivals (drop-offs) per snapshot at a dock
#
# Given the current bike count (b0) and the expected flow over the time the
# rider needs, we compute:
#   P(at least one bike present) for pickup   → get_bike_availability()
#   P(at least one open slot)    for drop-off → get_slot_availability()
#
# This file contains two exported functions:
#   get_bike_availability()
#   get_slot_availability()
#
# NOTE for teammates: these functions are intentionally pure -- they take
# plain numbers and return plain numbers. No data frames, no plotting.
# The recommend_dock() function in recommend.R calls these.
# -------------------------------------------------------------------------

#' @name get_bike_availability
#' @title Probability a Bike Is Available at a Dock
#' @description
#' Given the current number of bikes at a dock (`b0`) and the expected
#' Poisson departure rate (`lam_out`) and arrival rate (`lam_in`) over
#' the rider's walking time to the dock, returns the probability that at
#' least one bike will be there when the rider arrives.
#'
#' **Method:** With departures `Out ~ Poisson(lam_out)` and arrivals
#' `In ~ Poisson(lam_in)` modeled as independent, the net change is
#' `Delta = In - Out`. We want `P(b0 + Delta >= 1)`, i.e.
#' `P(Out - In <= b0 - 1)`. This is evaluated numerically by summing
#' the joint Poisson probability mass over a grid up to the 99.99th
#' quantile of each marginal distribution.
#'
#' @param b0 Non-negative integer. Current bike count at the dock.
#' @param lam_out Non-negative numeric. Expected number of departures
#'   (pickups) from this dock over the rider's travel window.
#' @param lam_in Non-negative numeric. Expected number of arrivals
#'   (drop-offs) to this dock over the rider's travel window.
#'
#' @return A single numeric in [0, 1]: the probability that at least one
#'   bike is present when the rider arrives.
#'
#' @author Big Red Crew
#' @export
#'
#' @examples
#' # With 1 bike, equal departure and arrival rates of 1: ~60.6% chance
#' get_bike_availability(b0 = 1, lam_out = 1, lam_in = 1)
#' # With 5 bikes and no flow, certainty
#' get_bike_availability(b0 = 5, lam_out = 0, lam_in = 0)
#' # With 0 bikes and no flow, impossible
#' get_bike_availability(b0 = 0, lam_out = 0, lam_in = 0)
# ------------------------------------------------------------------------------
# get_bike_availability
# ------------------------------------------------------------------------------
# Short description: Calculates the Poisson probability that at least one bike
# will be available at a dock upon rider arrival given current inventory and expected flows.

get_bike_availability <- function(b0, lam_out, lam_in) {
  # --- input validation ----------------------------------------------------
  stopifnot(
    is.numeric(b0),   length(b0)    == 1L, b0    >= 0,
    is.numeric(lam_out), length(lam_out) == 1L, lam_out >= 0,
    is.numeric(lam_in),  length(lam_in)  == 1L, lam_in  >= 0
  )

  # Edge case: no bikes and nothing arriving → definitely no bike available.
  if (b0 == 0 && lam_in == 0) return(0)
  # Edge case: bikes present and nothing leaving → definitely available.
  if (b0 >= 1 && lam_out == 0) return(1)

  # --- numerical summation over the joint Poisson grid --------------------
  # Truncate each marginal at its 99.99th percentile to keep computation fast.
  max_out <- qpois(0.9999, lam_out)
  max_in  <- qpois(0.9999, lam_in)

  out_vals <- 0:max_out
  in_vals  <- 0:max_in

  p_out <- dpois(out_vals, lam_out)
  p_in  <- dpois(in_vals,  lam_in)

  # P(b0 + in - out >= 1) for each (out, in) pair
  prob <- 0
  for (o in seq_along(out_vals)) {
    net_bikes <- b0 + in_vals - out_vals[o]
    # Contribution: P(Out = out_vals[o]) * sum_in[ P(In = in) * I(net >= 1) ]
    prob <- prob + p_out[o] * sum(p_in[net_bikes >= 1])
  }
  prob
}


#' @name get_slot_availability
#' @title Probability an Open Docking Slot Is Available
#' @description
#' Given the current number of bikes at a dock (`b0`), the dock's total
#' capacity, and the expected Poisson flow rates, returns the probability
#' that at least one open slot will be available when a rider arrives to
#' return their bike.
#'
#' **Method:** Open slots = `capacity - b0`. We need `P(open_slots +
#' Out - In >= 1)`, where more departures and fewer arrivals both help.
#' Evaluated with the same numerical grid as [get_bike_availability()],
#' with the roles of `lam_out` and `lam_in` swapped.
#'
#' @param b0 Non-negative integer. Current bike count at the dock.
#' @param capacity Positive integer. Total docking slots at this dock.
#' @param lam_out Non-negative numeric. Expected departures (pickups) over
#'   the rider's travel window to this dock.
#' @param lam_in Non-negative numeric. Expected arrivals (drop-offs) over
#'   the rider's travel window to this dock.
#'
#' @return A single numeric in [0, 1]: the probability that at least one
#'   open slot is present when the rider arrives.
#'
#' @author Big Red Crew
#' @export
#'
#' @examples
#' # Dock has 5 bikes, capacity 10, so 5 open slots; moderate flow
#' get_slot_availability(b0 = 5, capacity = 10, lam_out = 1, lam_in = 1)
#' # Full dock (b0 == capacity), nothing leaving → no slot available
#' get_slot_availability(b0 = 10, capacity = 10, lam_out = 0, lam_in = 0)
# ------------------------------------------------------------------------------
# get_slot_availability
# ------------------------------------------------------------------------------
# Short description: Calculates the Poisson probability that at least one open
# docking slot will be available at a dock upon rider arrival.

get_slot_availability <- function(b0, capacity, lam_out, lam_in) {
  # --- input validation ----------------------------------------------------
  stopifnot(
    is.numeric(b0),       length(b0)       == 1L, b0       >= 0,
    is.numeric(capacity), length(capacity) == 1L, capacity >= 1,
    b0 <= capacity,
    is.numeric(lam_out),  length(lam_out)  == 1L, lam_out  >= 0,
    is.numeric(lam_in),   length(lam_in)   == 1L, lam_in   >= 0
  )

  open_slots <- capacity - b0

  # Edge case: full dock and nothing leaving → definitely no slot.
  if (open_slots == 0 && lam_out == 0) return(0)
  # Edge case: slots exist and nothing arriving → definitely a slot available.
  if (open_slots >= 1 && lam_in == 0) return(1)

  # Swap perspective: we now need P(open_slots + Out - In >= 1).
  # Re-use the same Poisson grid logic with roles exchanged.
  max_in  <- qpois(0.9999, lam_in)
  max_out <- qpois(0.9999, lam_out)

  in_vals  <- 0:max_in
  out_vals <- 0:max_out

  p_in  <- dpois(in_vals,  lam_in)
  p_out <- dpois(out_vals, lam_out)

  prob <- 0
  for (i in seq_along(in_vals)) {
    net_open <- open_slots + out_vals - in_vals[i]
    prob <- prob + p_in[i] * sum(p_out[net_open >= 1])
  }
  prob
}

