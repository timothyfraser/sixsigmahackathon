# ==============================================================================
# failure_factor.R
# BikeSmart R Package - Usable Fleet Reliability & Failure Factor Modeling
# ------------------------------------------------------------------------------
# PURPOSE:
# Models the probability and share of bikes expected to be mechanically usable,
# accounting for multiple independent defect types (flat tires, batteries, etc.).
# Analogous to Rolled Throughput Yield (RTY) in Six Sigma quality engineering.
#
# Core functions:
#   - check_rates(): Validates numeric defect share rates
#   - failure_factor(): Computes overall fleet usable share factor
#   - failure_breakdown(): Breakdown table of per-defect impact
#   - apply_failure_factor(): Scales inventory predictions by usable share
# ==============================================================================

# ------------------------------------------------------------------------------
# check_rates
# ------------------------------------------------------------------------------
# Short description: Validates that the supplied defect rates are named numeric
# shares between 0 and 1 without missing values.

#' Validate Defect Rate Inputs
#'
#' @description
#' Confirms that a vector of defect rates is numeric, properly named, contains
#' no missing values (`NA`), and each rate is a proportion between 0 and 1.
#'
#' @param rates Named numeric vector of defect shares (e.g. `c(flat_tire = 0.02, battery = 0.05)`).
#' @return Invisibly returns the validated rates vector.
#' @export
check_rates <- function(rates) {
  if (!is.numeric(rates)) {
    stop("rates must be numeric, e.g. c(flat_tire = 0.02, battery = 0.05)")
  }
  if (length(rates) > 0 && (is.null(names(rates)) || any(names(rates) == ""))) {
    stop("every rate needs a name, e.g. c(flat_tire = 0.02)")
  }
  if (anyNA(rates)) {
    stop("rates must not contain NA")
  }
  if (any(rates < 0 | rates > 1)) {
    stop("every rate must be between 0 and 1 (a share, not a percent)")
  }
  invisible(rates)
}


# ------------------------------------------------------------------------------
# failure_factor
# ------------------------------------------------------------------------------
# Short description: Multiplies survival shares across independent defect types
# to compute the overall fraction of bikes expected to be usable (0 to 1).

#' Calculate Usable Fleet Share (Rolled Throughput Survival)
#'
#' @description
#' Computes the overall usable proportion of bikes under the assumption of independent
#' defect probabilities:
#' \deqn{\text{factor} = \prod_{i=1}^k (1 - r_i)}
#' where \eqn{r_i} is the defect rate for fault category \eqn{i}.
#'
#' @param rates Named numeric vector of defect shares, each between 0 and 1.
#' @return Single numeric value between 0 and 1 representing usable proportion.
#' @export
#' @examples
#' failure_factor(c(flat_tire = 0.02, battery = 0.05)) # Returns 0.931
failure_factor <- function(rates) {
  check_rates(rates)
  prod(1 - rates)
}


# ------------------------------------------------------------------------------
# failure_breakdown
# ------------------------------------------------------------------------------
# Short description: Returns a Pareto-style table showing each defect's isolated
# survival rate and cumulative usable factor, sorted from highest to lowest impact.

#' Defect Contribution and Cumulative Usability Breakdown
#'
#' @description
#' Generates an ordered summary table of defect impact, showing individual failure
#' rates, isolated survival rates, and cumulative survival factor ordered worst-first.
#'
#' @param rates Named numeric vector of defect shares.
#' @return Data frame with columns `defect`, `rate`, `survive`, and `cumulative_factor`.
#' @export
#' @examples
#' failure_breakdown(c(flat_tire = 0.02, battery = 0.05, crash = 0.01))
failure_breakdown <- function(rates) {
  check_rates(rates)
  if (length(rates) == 0) {
    return(data.frame(
      defect = character(),
      rate = numeric(),
      survive = numeric(),
      cumulative_factor = numeric()
    ))
  }
  rates <- sort(rates, decreasing = TRUE)
  data.frame(
    defect = names(rates),
    rate = unname(rates),
    survive = unname(1 - rates),
    cumulative_factor = unname(cumprod(1 - rates)),
    stringsAsFactors = FALSE
  )
}


# ------------------------------------------------------------------------------
# apply_failure_factor
# ------------------------------------------------------------------------------
# Short description: Scales projected dock bike inventory by the failure factor
# to estimate the actual number of mechanically sound, rentable bikes.

#' Scale Inventory Predictions by Failure Factor
#'
#' @description
#' Multiplies a predicted bike count or vector of station bike counts by the
#' fleet usable factor to give the expected count of functional, rentable bikes.
#'
#' @param predicted Numeric vector of predicted bike counts.
#' @param rates Named numeric vector of defect shares.
#' @return Numeric vector of the same length as `predicted`, scaled by the factor.
#' @export
#' @examples
#' apply_failure_factor(c(10, 20, 30), c(flat_tire = 0.02, battery = 0.05))
apply_failure_factor <- function(predicted, rates) {
  if (!is.numeric(predicted)) {
    stop("predicted must be numeric")
  }
  if (any(predicted < 0, na.rm = TRUE)) {
    stop("predicted must not be negative")
  }
  predicted * failure_factor(rates)
}

