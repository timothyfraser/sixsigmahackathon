# Simulated van tasks and their status moves (H-18, tier 3, Rebalancing tab).
# Plain functions, no Shiny. The page keeps the table in memory for one session only.
#
# Rules come from docs/methods.md section 7 (task-status rules), mirrored from clean_tasks()
# in qc.R, plus these demo assumptions (decisions of the H-18 charter):
#   * Moves go forward only: planned -> assigned -> in_progress -> completed.
#     planned, assigned or in_progress can also go to cancelled. completed and cancelled are final.
#   * A van holds only one active (assigned or in_progress) task at a time (methods 4.3).
#   * Times are POSIXct; the page chooses them (default: sidebar date + observation minute).
# A rejected move never changes the table: task_transition() returns the table it was given.

TASK_STATUS_ORDER <- c("planned", "assigned", "in_progress", "completed", "cancelled")
TASK_ACTIVE <- c("assigned", "in_progress")

# Allowed next statuses from each status (forward only).
TASK_NEXT <- list(
  planned = c("assigned", "cancelled"),
  assigned = c("in_progress", "cancelled"),
  in_progress = c("completed", "cancelled"),
  completed = character(0),
  cancelled = character(0)
)

TASK_COLUMNS <- c("task_id", "van_id", "source_station_id", "destination_station_id",
                  "planned_quantity", "actual_quantity", "created_at", "assigned_at",
                  "arrived_at", "completed_at", "status")

TASK_NOT_SAVED_NOTE <- paste("Simulated, session only: tasks are not saved and do not change the data,",
                             "the charts or the simulation.")

#' An empty task table with the right column types.
empty_tasks <- function() {
  na_time <- as.POSIXct(character(0), tz = "UTC")
  data.frame(task_id = character(0), van_id = character(0), source_station_id = character(0),
             destination_station_id = character(0), planned_quantity = integer(0),
             actual_quantity = integer(0), created_at = na_time, assigned_at = na_time,
             arrived_at = na_time, completed_at = na_time, status = character(0),
             stringsAsFactors = FALSE)
}

#' New planned tasks from the rebalancing plan's moves.
#' Input : moves = data.frame(from_station, to_station, quantity) (rebalance_plan()$moves);
#'         created_at = one POSIXct (when the button was clicked / the plan minute);
#'         existing = the session's tasks so far (to keep task ids unique), or NULL.
#' Output: data.frame in TASK_COLUMNS, status "planned", van and times empty; ids SIM-001, SIM-002,
#'         ... continuing after the largest number already used. Zero moves give zero rows.
new_tasks_from_plan <- function(moves, created_at, existing = NULL) {
  out <- empty_tasks()
  if (is.null(moves) || nrow(moves) == 0) return(out)
  used <- if (is.null(existing)) character(0) else existing$task_id
  nums <- suppressWarnings(as.integer(sub("^SIM-", "", used[grepl("^SIM-[0-9]+$", used)])))
  start <- if (length(nums) == 0) 0L else max(nums)
  n <- nrow(moves)
  data.frame(task_id = sprintf("SIM-%03d", start + seq_len(n)), van_id = NA_character_,
             source_station_id = as.character(moves$from_station),
             destination_station_id = as.character(moves$to_station),
             planned_quantity = as.integer(round(moves$quantity)), actual_quantity = NA_integer_,
             created_at = rep(as.POSIXct(created_at, tz = "UTC"), n),
             assigned_at = as.POSIXct(rep(NA, n), tz = "UTC"),
             arrived_at = as.POSIXct(rep(NA, n), tz = "UTC"),
             completed_at = as.POSIXct(rep(NA, n), tz = "UTC"),
             status = "planned", stringsAsFactors = FALSE)
}

# TRUE when a van id is present (not NULL, NA or blank).
has_value <- function(x) length(x) == 1 && !is.na(x) && nzchar(trimws(as.character(x)))

# TRUE when x is one whole number between lo and hi.
is_whole_in <- function(x, lo, hi) {
  length(x) == 1 && is.numeric(x) && !is.na(x) && x == round(x) && x >= lo && x <= hi
}

#' Check one task row against the methods section 7 task-status rules.
#' Input : row = a one-row data.frame with the TASK_COLUMNS (created_at not needed).
#' Output: character vector of problems; character(0) means the row is valid.
validate_task_row <- function(row) {
  if (!is.data.frame(row) || nrow(row) != 1) return("row must be one task")
  p <- character(0)
  st <- row$status
  if (!(st %in% TASK_STATUS_ORDER)) return("invalid status")
  src <- row$source_station_id
  dst <- row$destination_station_id
  if (is.na(src) || is.na(dst) || src == dst) p <- c(p, "source and destination must differ")
  pq <- row$planned_quantity
  if (!is_whole_in(pq, 1, Inf)) p <- c(p, "planned_quantity must be a whole number above 0")
  # Section 7: van_id is required unless planned. One documented exception (H-18 decision): a task
  # cancelled straight from planned never had a van, so a cancelled row needs a van only if it was assigned.
  never_assigned <- st == "cancelled" && is.na(row$assigned_at)
  if (st != "planned" && !never_assigned && !has_value(row$van_id)) {
    p <- c(p, "van_id is required unless the status is planned")
  }
  from_assigned <- st %in% c("assigned", "in_progress", "completed")
  from_in_progress <- st %in% c("in_progress", "completed")
  if (from_assigned && is.na(row$assigned_at)) p <- c(p, "assigned_at is required from assigned on")
  if (from_in_progress && is.na(row$arrived_at)) p <- c(p, "arrived_at is required from in_progress on")
  if (st == "completed" && is.na(row$completed_at)) p <- c(p, "completed_at is required for completed")
  if (!is.na(row$assigned_at) && !is.na(row$arrived_at) && as.numeric(row$assigned_at) > as.numeric(row$arrived_at)) {
    p <- c(p, "times out of order: assigned_at must not be after arrived_at")
  }
  if (!is.na(row$arrived_at) && !is.na(row$completed_at) && as.numeric(row$arrived_at) > as.numeric(row$completed_at)) {
    p <- c(p, "times out of order: arrived_at must not be after completed_at")
  }
  if (!is.na(row$assigned_at) && !is.na(row$completed_at) && as.numeric(row$assigned_at) > as.numeric(row$completed_at)) {
    p <- c(p, "times out of order: assigned_at must not be after completed_at")
  }
  aq <- row$actual_quantity
  if (st == "completed" && is.na(aq)) {
    p <- c(p, "actual_quantity is required for completed")
  } else if (!is.na(aq) && !is_whole_in(aq, 0, if (is_whole_in(pq, 1, Inf)) pq else 0)) {
    p <- c(p, "actual_quantity must be a whole number from 0 to planned_quantity")
  }
  p
}

# The result of a move: ok, the (possibly changed) table and a message.
task_result <- function(ok, tasks, message) list(ok = ok, tasks = tasks, message = message)

#' Move one task to a new status, or say why not.
#' Input : tasks = the session table (TASK_COLUMNS); task_id; to = the new status;
#'         van_id (needed for assigned); at = POSIXct time of the move (assigned_at for assigned,
#'         arrived_at for in_progress, completed_at for completed); actual_quantity (completed).
#' Output: list(ok, tasks, message). On failure tasks is the table you gave, unchanged.
task_transition <- function(tasks, task_id, to, van_id = NULL, at = NULL, actual_quantity = NULL) {
  reject <- function(why) task_result(FALSE, tasks, paste("Rejected:", why))
  if (!has_value(task_id) || !(task_id %in% tasks$task_id)) {
    return(reject(paste0("unknown task_id ", if (has_value(task_id)) task_id else "(none selected)")))
  }
  if (!has_value(to) || !(to %in% TASK_STATUS_ORDER)) {
    return(reject(paste0("unknown status ", if (has_value(to)) to else "(none chosen)")))
  }
  i <- which(tasks$task_id == task_id)
  from <- tasks$status[i]
  allowed <- TASK_NEXT[[from]]
  if (!(to %in% allowed)) {
    return(reject(paste0("invalid transition: ", from, " -> ", to, "; allowed from ", from, ": ",
                         if (length(allowed) == 0) "none (final status)" else paste(allowed, collapse = ", "))))
  }
  row <- tasks[i, , drop = FALSE]
  needs_time <- to %in% c("assigned", "in_progress", "completed")
  if (needs_time && (is.null(at) || length(at) != 1 || is.na(at))) {
    return(reject(paste0("a time is required to move to ", to)))
  }
  if (to == "assigned") {
    if (!has_value(van_id)) return(reject("van_id is required to move to assigned"))
    busy <- tasks$task_id != task_id & tasks$van_id %in% van_id & tasks$status %in% TASK_ACTIVE
    if (any(busy)) {
      return(reject(paste0("van ", van_id, " already holds the active task ", tasks$task_id[busy][1],
                           " (", tasks$status[busy][1], "); a van holds one active task at a time")))
    }
    row$van_id <- as.character(van_id)
    row$assigned_at <- as.POSIXct(at, tz = "UTC")
  } else if (to == "in_progress") {
    row$arrived_at <- as.POSIXct(at, tz = "UTC")
  } else if (to == "completed") {
    if (is.null(actual_quantity) || length(actual_quantity) != 1 || is.na(actual_quantity)) {
      return(reject("actual_quantity is required to move to completed"))
    }
    row$completed_at <- as.POSIXct(at, tz = "UTC")
    row$actual_quantity <- actual_quantity
  }
  # Time order, checked before the general rules so the reason names the time that is wrong.
  if (to == "in_progress" && as.numeric(row$arrived_at) < as.numeric(row$assigned_at)) {
    return(reject("arrived_at must not be before assigned_at"))
  }
  if (to == "completed" && as.numeric(row$completed_at) < as.numeric(row$arrived_at)) {
    return(reject("completed_at must not be before arrived_at"))
  }
  problems <- validate_task_row(transform(row, status = to))
  if (length(problems) > 0) return(reject(paste(problems, collapse = "; ")))
  row$status <- to
  row$actual_quantity <- as.integer(row$actual_quantity)   # whole by now (validated above)
  tasks[i, ] <- row
  task_result(TRUE, tasks, paste0("Accepted: ", task_id, " ", from, " -> ", to, "."))
}

#' Van ids to offer: the distinct van_id of the scenario's task log, else V1 and V2.
task_van_choices <- function(tasks) {
  v <- if (is.null(tasks) || !"van_id" %in% names(tasks)) character(0) else
    sort(unique(tasks$van_id[!is.na(tasks$van_id)]))
  if (length(v) == 0) c("V1", "V2") else v
}
