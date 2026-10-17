# Tests for app/tasks.R (H-18): status moves with the docs/methods.md section 7 rules.
source(testthat::test_path("..", "app", "tasks.R"), local = TRUE)

t0 <- as.POSIXct("2026-10-05 07:00:00", tz = "America/New_York")
mins <- function(m) t0 + 60 * m

moves <- data.frame(from_station = c("S1", "S3"), to_station = c("S2", "S4"), quantity = c(4, 6),
                    stringsAsFactors = FALSE)
fresh <- function() new_tasks_from_plan(moves, t0)

# a table with one task (SIM-001, planned 4 bikes) moved to the wanted status by valid moves
task_at <- function(status) {
  tk <- fresh()
  if (status == "planned") return(tk)
  if (status == "cancelled") return(task_transition(tk, "SIM-001", "cancelled")$tasks)
  tk <- task_transition(tk, "SIM-001", "assigned", van_id = "V1", at = mins(1))$tasks
  if (status == "assigned") return(tk)
  tk <- task_transition(tk, "SIM-001", "in_progress", at = mins(10))$tasks
  if (status == "in_progress") return(tk)
  task_transition(tk, "SIM-001", "completed", at = mins(20), actual_quantity = 4)$tasks
}

test_that("new_tasks_from_plan builds planned tasks from the moves", {
  tk <- fresh()
  expect_equal(nrow(tk), 2)
  expect_equal(tk$task_id, c("SIM-001", "SIM-002"))
  expect_equal(tk$source_station_id, c("S1", "S3"))
  expect_equal(tk$destination_station_id, c("S2", "S4"))
  expect_equal(tk$planned_quantity, c(4L, 6L))
  expect_true(all(tk$status == "planned"))
  expect_true(all(is.na(tk$van_id)) && all(is.na(tk$assigned_at)) && all(is.na(tk$actual_quantity)))
  expect_equal(names(tk), TASK_COLUMNS)
  expect_equal(nrow(new_tasks_from_plan(moves[0, ], t0)), 0)     # no moves, no tasks
})

test_that("task ids stay unique over repeated creation", {
  tk <- fresh()
  tk <- rbind(tk, new_tasks_from_plan(moves, t0, existing = tk))
  tk <- rbind(tk, new_tasks_from_plan(moves, t0, existing = tk))
  expect_equal(nrow(tk), 6)
  expect_equal(anyDuplicated(tk$task_id), 0)
  expect_equal(tk$task_id[5:6], c("SIM-005", "SIM-006"))
})

test_that("every allowed transition is accepted", {
  for (path in list(c("planned", "assigned"), c("assigned", "in_progress"),
                    c("in_progress", "completed"), c("planned", "cancelled"),
                    c("assigned", "cancelled"), c("in_progress", "cancelled"))) {
    tk <- task_at(path[1])
    r <- task_transition(tk, "SIM-001", path[2], van_id = "V1", at = mins(30), actual_quantity = 3)
    expect_true(r$ok, info = paste(path, collapse = " -> "))
    expect_equal(r$tasks$status[1], path[2])
    expect_match(r$message, "^Accepted")
  }
})

test_that("a full valid life cycle fills the right fields", {
  tk <- task_at("completed")
  expect_equal(tk$status[1], "completed")
  expect_equal(tk$van_id[1], "V1")
  expect_equal(tk$actual_quantity[1], 4L)
  expect_true(tk$assigned_at[1] <= tk$arrived_at[1] && tk$arrived_at[1] <= tk$completed_at[1])
  expect_equal(validate_task_row(tk[1, ]), character(0))
  expect_equal(tk$status[2], "planned")                           # the other task is untouched
})

test_that("every disallowed transition is rejected with the transition reason", {
  for (from in TASK_STATUS_ORDER) {
    for (to in TASK_STATUS_ORDER) {
      if (to %in% TASK_NEXT[[from]]) next
      tk <- task_at(from)
      r <- task_transition(tk, "SIM-001", to, van_id = "V2", at = mins(40), actual_quantity = 2)
      expect_false(r$ok, info = paste(from, "->", to))
      expect_match(r$message, paste0("invalid transition: ", from, " -> ", to, "; allowed from ", from, ": "),
                   fixed = TRUE)
      expect_identical(r$tasks, tk)
    }
  }
  r <- task_transition(task_at("completed"), "SIM-001", "assigned", van_id = "V1", at = mins(40))
  expect_match(r$message, "none (final status)", fixed = TRUE)
  r <- task_transition(fresh(), "SIM-001", "in_progress", at = mins(5))     # skipping a step
  expect_match(r$message, "invalid transition: planned -> in_progress; allowed from planned: assigned, cancelled",
               fixed = TRUE)
})

test_that("unknown task or status is rejected", {
  tk <- fresh()
  expect_false(task_transition(tk, "NOPE", "assigned", van_id = "V1", at = mins(1))$ok)
  expect_false(task_transition(tk, NULL, "assigned", van_id = "V1", at = mins(1))$ok)
  expect_false(task_transition(tk, "SIM-001", "flying", van_id = "V1", at = mins(1))$ok)
})

test_that("assigned needs a van and a time", {
  tk <- fresh()
  for (bad in list(NULL, NA, "", "  ")) {
    r <- task_transition(tk, "SIM-001", "assigned", van_id = bad, at = mins(1))
    expect_false(r$ok)
    expect_match(r$message, "van_id is required")
    expect_identical(r$tasks, tk)
  }
  r <- task_transition(tk, "SIM-001", "assigned", van_id = "V1", at = NULL)
  expect_false(r$ok)
  expect_match(r$message, "time is required")
  expect_false(task_transition(tk, "SIM-001", "assigned", van_id = "V1", at = as.POSIXct(NA))$ok)
})

test_that("times must be in order", {
  tk <- task_at("assigned")                                       # assigned_at = 07:01
  r <- task_transition(tk, "SIM-001", "in_progress", at = mins(0))
  expect_false(r$ok)
  expect_match(r$message, "arrived_at must not be before assigned_at")
  expect_identical(r$tasks, tk)
  expect_true(task_transition(tk, "SIM-001", "in_progress", at = mins(1))$ok)   # equal times are allowed
  tk2 <- task_at("in_progress")                                   # arrived_at = 07:10
  r <- task_transition(tk2, "SIM-001", "completed", at = mins(9), actual_quantity = 2)
  expect_false(r$ok)
  expect_match(r$message, "completed_at must not be before arrived_at")
  expect_identical(r$tasks, tk2)
  expect_true(task_transition(tk2, "SIM-001", "completed", at = mins(10), actual_quantity = 2)$ok)
})

test_that("actual_quantity: required, whole, 0..planned", {
  tk <- task_at("in_progress")                                    # planned_quantity = 4
  r <- task_transition(tk, "SIM-001", "completed", at = mins(20))
  expect_false(r$ok); expect_match(r$message, "actual_quantity is required")
  for (bad in list(5, -1, 2.5, NA, "x")) {
    r <- task_transition(tk, "SIM-001", "completed", at = mins(20), actual_quantity = bad)
    expect_false(r$ok, info = as.character(bad))
    expect_identical(r$tasks, tk)
  }
  expect_match(task_transition(tk, "SIM-001", "completed", at = mins(20), actual_quantity = 5)$message,
               "whole number from 0 to planned_quantity")
  expect_true(task_transition(tk, "SIM-001", "completed", at = mins(20), actual_quantity = 0)$ok)
  expect_true(task_transition(tk, "SIM-001", "completed", at = mins(20), actual_quantity = 4)$ok)
  expect_match(task_transition(tk, "SIM-001", "completed", at = NULL, actual_quantity = 4)$message,
               "time is required")
})

test_that("a van holds one active task at a time", {
  tk <- task_at("assigned")                                       # SIM-001 active on V1
  r <- task_transition(tk, "SIM-002", "assigned", van_id = "V1", at = mins(2))
  expect_false(r$ok)
  expect_match(r$message, "van V1 already holds the active task SIM-001")
  expect_identical(r$tasks, tk)
  expect_true(task_transition(tk, "SIM-002", "assigned", van_id = "V2", at = mins(2))$ok)
  # once the first task is in progress it is still active; once completed or cancelled the van is free
  tk <- task_transition(tk, "SIM-001", "in_progress", at = mins(5))$tasks
  expect_false(task_transition(tk, "SIM-002", "assigned", van_id = "V1", at = mins(6))$ok)
  done <- task_transition(tk, "SIM-001", "completed", at = mins(9), actual_quantity = 4)$tasks
  expect_true(task_transition(done, "SIM-002", "assigned", van_id = "V1", at = mins(10))$ok)
  gone <- task_transition(tk, "SIM-001", "cancelled")$tasks
  expect_true(task_transition(gone, "SIM-002", "assigned", van_id = "V1", at = mins(10))$ok)
})

test_that("validate_task_row mirrors the section 7 rules", {
  ok <- task_at("completed")[1, ]
  expect_equal(validate_task_row(ok), character(0))
  bad <- function(...) { r <- ok; args <- list(...); for (n in names(args)) r[[n]] <- args[[n]]; validate_task_row(r) }
  expect_match(bad(destination_station_id = "S1"), "must differ")
  expect_match(bad(van_id = NA_character_), "van_id is required")
  expect_match(bad(assigned_at = as.POSIXct(NA)), "assigned_at is required")
  expect_match(bad(arrived_at = as.POSIXct(NA)), "arrived_at is required")
  expect_match(bad(completed_at = as.POSIXct(NA)), "completed_at is required")
  expect_match(bad(actual_quantity = NA_integer_), "actual_quantity is required")
  expect_match(bad(actual_quantity = 9L), "actual_quantity must be")
  expect_equal(validate_task_row(task_at("cancelled")[1, ]), character(0))   # cancelled from planned: no van
  cancelled_assigned <- ok; cancelled_assigned$status <- "cancelled"; cancelled_assigned$van_id <- NA_character_
  expect_match(validate_task_row(cancelled_assigned), "van_id is required")  # but an assigned one needs its van
  expect_match(bad(arrived_at = mins(0), assigned_at = mins(5))[1], "times out of order")
  expect_match(bad(status = "flying"), "invalid status")
  expect_equal(validate_task_row(fresh()[1, ]), character(0))     # planned: no van or times needed
})

test_that("a rejected move leaves the table identical", {
  tk <- task_at("assigned")
  tries <- list(
    task_transition(tk, "SIM-001", "completed", at = mins(9), actual_quantity = 1),
    task_transition(tk, "SIM-001", "planned"),
    task_transition(tk, "SIM-002", "assigned", van_id = "V1", at = mins(3)),
    task_transition(tk, "SIM-001", "in_progress", at = mins(0)))
  for (r in tries) { expect_false(r$ok); expect_identical(r$tasks, tk) }
})

test_that("task_van_choices uses the scenario vans, else V1 and V2", {
  expect_equal(task_van_choices(NULL), c("V1", "V2"))
  expect_equal(task_van_choices(data.frame(van_id = c("B", "A", NA, "B"))), c("A", "B"))
  expect_equal(task_van_choices(data.frame(van_id = NA_character_)), c("V1", "V2"))
})

# ---- formatting helpers in prep.R (no rules here)
source(testthat::test_path("..", "app", "prep.R"), local = TRUE)

test_that("tasks_display shows New York clock times and empty cells", {
  tk <- task_at("in_progress")
  d <- tasks_display(tk)
  expect_equal(d$assigned[1], "07:01")
  expect_equal(d$arrived[1], "07:10")
  expect_equal(d$completed, c("", ""))
  expect_equal(d$van_id, c("V1", ""))
  expect_equal(d$status, c("in_progress", "planned"))
  expect_equal(names(tasks_display(empty_tasks())), "note")
})

test_that("the default time is the sidebar minute and the time text is checked", {
  expect_equal(task_time_default("2026-10-05", 5), "07:05")
  expect_equal(task_time_default("2026-10-05", 125), "09:05")
  at <- task_time_parse("2026-10-05", "07:35")
  expect_equal(format(at, "%H:%M", tz = "America/New_York"), "07:35")
  for (bad in c("", "7:35", "25:00", "07:61", "abc", NA)) expect_true(is.na(task_time_parse("2026-10-05", bad)), info = bad)
})

# ---- the page wiring: create, a valid move, an invalid move (built-in baseline scenario)
test_that("the Rebalancing tab accepts a valid move and rejects an invalid one", {
  skip_if_not_installed("shiny")
  app_dir <- normalizePath(testthat::test_path("..", "app"))
  old <- setwd(app_dir)
  old_warn <- options(warn = -1)                 # package built-under-newer-R warnings only
  on.exit({ setwd(old); options(old_warn) }, add = TRUE)
  app <- shiny::shinyAppFile("app.R")
  suppressWarnings(suppressPackageStartupMessages(shiny::testServer(app, {   # R-version warnings from packages only
    session$setInputs(scenario = "baseline", tabs = "Rebalancing", stale_limit = 2, warn_k = 2,
                      target_fill = 0.5, van_capacity = 12, detour = 1.3, min_coverage = 0.95,
                      baseline_share = 0.5)
    session$setInputs(date = dates()[1], minute = 5)
    session$setInputs(tk_create = 1)
    expect_match(tk_message()$text, "^Created [0-9]+ planned task")
    n1 <- nrow(tasks_rv())
    expect_gt(n1, 0)
    session$setInputs(tk_create = 2)                                  # a second click adds new ids
    expect_equal(nrow(tasks_rv()), 2 * n1)
    expect_equal(anyDuplicated(tasks_rv()$task_id), 0)
    session$setInputs(tk_select = "SIM-001", tk_status = "assigned", tk_van = "V1", tk_time = "07:05",
                      tk_qty = NA)
    session$setInputs(tk_apply = 1)                                   # planned -> assigned: accepted
    expect_true(tk_message()$ok)
    expect_match(tk_message()$text, "Accepted: SIM-001 planned -> assigned")
    expect_equal(tasks_rv()$status[1], "assigned")
    before <- tasks_rv()
    session$setInputs(tk_status = "completed", tk_qty = 2)
    session$setInputs(tk_apply = 2)                                   # assigned -> completed: skips a step
    expect_false(tk_message()$ok)
    expect_match(tk_message()$text, "invalid transition: assigned -> completed; allowed from assigned: in_progress, cancelled",
                 fixed = TRUE)
    expect_identical(tasks_rv(), before)
  })))
})
