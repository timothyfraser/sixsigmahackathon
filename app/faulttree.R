# Qualitative fault trees for rent failure and return failure (tier 3, docs/methods.md 4.2 item 3).
# Every number of the Diagnosis tab lives here; app.R and prep.R only call and display.
#
# The idea, in words. A failed attempt carries a logged reason (failure_reason). Each reason points to
# one action (docs/methods.md section 7, "Cause mapping"):
#   no_bike, no_dock                          -> rebalancing
#   bike_fault, dock_fault, station_closed    -> maintenance
#   app_error                                 -> data check
# The cause share of an action = (failed attempts pointing to it) / (all failed attempts in the scope).
# It is a count of LOGGED failures only. It is qualitative: no component probabilities exist, so the
# tree gives no probability of the top event.
#
# Status/attempt contradiction rule (KA-10). A failed rent logged no_bike, in a minute whose VALID, KNOWN
# grid state shows bikes_available > 0, cannot be a real "no bike": it is reclassified as a data check.
# EXTENSION OF THE METHODS (not in the methods text): the same rule for returns, a failed return logged
# no_dock while the known state shows docks_available > 0 is reclassified as a data check.
# The minute is the interval [m, m+1) that contains the attempt time (docs/methods.md 4.1). If that
# minute is unknown or stale in the grid (or outside the grid), the attempt is NOT reclassified, the
# logged reason is kept, and it is counted as "could not be checked".

FAULT_ACTIONS <- c("rebalancing", "maintenance", "data check")

# The cause mapping, one row per failure_reason code.
CAUSE_MAP <- c(no_bike = "rebalancing", no_dock = "rebalancing",
               bike_fault = "maintenance", dock_fault = "maintenance", station_closed = "maintenance",
               app_error = "data check")

NO_FAILURES_REASON <- paste("no failed attempts: shares are not defined;",
                            "no failures observed does not mean zero risk")
NO_ATTEMPTS_REASON <- "no attempts of this type in the scope: the failed share is not defined"

#' Map failure_reason codes to actions. An unknown code stops with a clear message (it is never guessed).
cause_action <- function(reason) {
  reason <- as.character(reason)
  bad <- setdiff(unique(reason), names(CAUSE_MAP))
  if (length(bad) > 0) {
    stop("unknown failure_reason code(s): ", paste(ifelse(is.na(bad), "<missing>", bad), collapse = ", "),
         ". Known codes: ", paste(names(CAUSE_MAP), collapse = ", "), ".", call. = FALSE)
  }
  unname(CAUSE_MAP[reason])
}

# The seconds (since 1970) of the start of the minute that contains each timestamp: [m, m+1).
minute_start_secs <- function(ts) floor(as.numeric(ts) / 60) * 60

#' Classify every FAILED attempt of one type.
#' Input : attempts = table with attempt_type, success, failure_reason, station_id, timestamp;
#'         type = "rent" or "return"; grid = qc.R build_grid output (several days may be stacked with
#'         rbind), or NULL when no usable status exists (then nothing can be checked).
#' Output: a data frame with one row per failed attempt: station_id, timestamp, reason (logged),
#'         logged_action, action (after the rule), reclassified (TRUE/FALSE), checkable (TRUE when the
#'         rule could be applied to this attempt; NA when the rule does not concern it).
classify_failures <- function(attempts, type = c("rent", "return"), grid = NULL) {
  type <- match.arg(type)
  need <- c("attempt_type", "success", "failure_reason", "station_id", "timestamp")
  if (!all(need %in% names(attempts))) stop("attempts needs the columns: ", paste(need, collapse = ", "), ".", call. = FALSE)
  f <- attempts[attempts$attempt_type == type & !is.na(attempts$success) & !attempts$success, , drop = FALSE]
  out <- data.frame(station_id = as.character(f$station_id), timestamp = f$timestamp,
                    reason = as.character(f$failure_reason), stringsAsFactors = FALSE)
  out$logged_action <- if (nrow(out) > 0) cause_action(out$reason) else character(0)
  out$action <- out$logged_action
  out$reclassified <- rep(FALSE, nrow(out))
  out$checkable <- rep(NA, nrow(out))
  if (nrow(out) == 0) return(out)

  # the rule concerns only the "state says empty/full" reason of this type
  rule_reason <- if (type == "rent") "no_bike" else "no_dock"
  state_col <- if (type == "rent") "bikes_available" else "docks_available"
  concerned <- out$reason == rule_reason
  out$checkable[concerned] <- FALSE
  if (is.null(grid) || nrow(grid) == 0 || !any(concerned)) return(out)

  key_grid <- paste(grid$station_id, as.numeric(grid$minute))
  key_att <- paste(out$station_id, minute_start_secs(out$timestamp))
  row <- match(key_att, key_grid)
  known <- !is.na(row) & grid$known[pmax(row, 1)] %in% TRUE
  count <- ifelse(known, grid[[state_col]][pmax(row, 1)], NA)
  checkable <- concerned & known & !is.na(count)
  out$checkable[checkable] <- TRUE
  contradiction <- checkable & count > 0
  out$reclassified <- contradiction
  out$action[contradiction] <- "data check"
  out
}

# counts and shares of a vector over fixed levels; shares NA when the total is 0
count_share <- function(x, levels) {
  counts <- as.integer(table(factor(x, levels = levels)))
  total <- sum(counts)
  data.frame(item = levels, count = counts, share = if (total > 0) counts / total else rep(NA_real_, length(levels)),
             stringsAsFactors = FALSE)
}

#' The fault tree numbers for one failure type.
#' Input : as classify_failures; also grid_available (FALSE when status is unusable: documented in the output).
#' Output: list(type, n, n_failed, failed_share, failed_share_reason, by_reason (reason, action, count, share),
#'         by_action (action, count, share; after the rule), logged_by_action (before the rule),
#'         reclassified, not_checked, checked, rule_applied (TRUE when a grid was given), shares_reason,
#'         tree (action, leaf, count, share: the leaves of the drawn tree)).
fault_tree <- function(attempts, type = c("rent", "return"), grid = NULL) {
  type <- match.arg(type)
  of_type <- attempts[attempts$attempt_type == type & !is.na(attempts$success), , drop = FALSE]
  n <- nrow(of_type)
  cls <- classify_failures(attempts, type, grid)
  n_failed <- nrow(cls)
  reasons <- if (type == "rent") c("no_bike", "bike_fault", "dock_fault", "station_closed", "app_error")
             else c("no_dock", "dock_fault", "station_closed", "app_error")
  by_reason <- count_share(cls$reason, reasons)
  names(by_reason)[1] <- "reason"
  by_reason$action <- unname(CAUSE_MAP[by_reason$reason])
  by_action <- count_share(cls$action, FAULT_ACTIONS)
  names(by_action)[1] <- "action"
  logged <- count_share(cls$logged_action, FAULT_ACTIONS)
  names(logged)[1] <- "action"

  # the leaves of the tree: each logged reason under the action it ends up in (after the rule);
  # reclassified attempts form their own leaf under "data check"
  leaf_name <- ifelse(cls$reclassified,
                      paste0(cls$reason, " (status shows ", if (type == "rent") "bikes" else "docks",
                             " available: reclassified)"),
                      cls$reason)
  leaf_action <- cls$action
  leaves <- unique(data.frame(action = leaf_action, leaf = leaf_name, stringsAsFactors = FALSE))
  if (nrow(leaves) > 0) {
    leaves$count <- mapply(function(a, l) sum(leaf_action == a & leaf_name == l), leaves$action, leaves$leaf)
    leaves$share <- leaves$count / n_failed
    leaves <- leaves[order(match(leaves$action, FAULT_ACTIONS), -leaves$count, leaves$leaf), ]
  } else {
    leaves <- data.frame(action = character(0), leaf = character(0), count = integer(0), share = numeric(0),
                         stringsAsFactors = FALSE)
  }
  rownames(leaves) <- NULL

  list(type = type, n = n, n_failed = n_failed,
       failed_share = if (n > 0) n_failed / n else NA_real_,
       failed_share_reason = if (n > 0) "" else NO_ATTEMPTS_REASON,
       by_reason = by_reason[, c("reason", "action", "count", "share")],
       by_action = by_action, logged_by_action = logged,
       reclassified = sum(cls$reclassified),
       not_checked = sum(cls$checkable %in% FALSE),
       checked = sum(cls$checkable %in% TRUE),
       rule_applied = !is.null(grid) && nrow(grid) > 0,
       shares_reason = if (n == 0) NO_ATTEMPTS_REASON else if (n_failed == 0) NO_FAILURES_REASON else "",
       tree = leaves)
}

#' Per-station causes: for each station with at least one failure, the failed counts by action (after the
#' rule), the number of failed attempts, and the top cause (the action with the most failures; a tie is
#' written "tie: a / b"). Output: station_id, n_failed, rebalancing, maintenance, data check, top_cause.
#' Sorted by n_failed (largest first), then station_id.
fault_tree_by_station <- function(attempts, type = c("rent", "return"), grid = NULL) {
  type <- match.arg(type)
  cls <- classify_failures(attempts, type, grid)
  empty <- data.frame(station_id = character(0), n_failed = integer(0), rebalancing = integer(0),
                      maintenance = integer(0), `data check` = integer(0), top_cause = character(0),
                      check.names = FALSE, stringsAsFactors = FALSE)
  if (nrow(cls) == 0) return(empty)
  ids <- sort(unique(cls$station_id))
  rows <- lapply(ids, function(id) {
    a <- cls$action[cls$station_id == id]
    cnt <- vapply(FAULT_ACTIONS, function(x) sum(a == x), numeric(1))
    top <- FAULT_ACTIONS[cnt == max(cnt)]
    data.frame(station_id = id, n_failed = length(a), rebalancing = cnt[[1]], maintenance = cnt[[2]],
               `data check` = cnt[[3]],
               top_cause = if (length(top) == 1) top else paste0("tie: ", paste(top, collapse = " / ")),
               check.names = FALSE, stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows)
  out <- out[order(-out$n_failed, out$station_id), ]
  rownames(out) <- NULL
  out
}
