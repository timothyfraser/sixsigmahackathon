# Shared inputs for baseline reports and service-log recalculation.
maintenance_inputs <- function(city, bike_ids, service_interval_h = 60) {
  start_path <- file.path("data", paste0("start_hours_", city, "2.csv"))
  log_path <- file.path("data", paste0("service_log_", city, ".csv"))
  start <- if (file.exists(start_path)) read.csv(start_path, stringsAsFactors = FALSE) else
    simulate_start_hours(bike_ids, service_interval_h, seed = 42)
  log <- if (file.exists(log_path)) read.csv(log_path, stringsAsFactors = FALSE) else
    data.frame(BIKEID = character(), service_time = character())
  stopifnot(setequal(start$BIKEID, bike_ids), all(log$BIKEID %in% bike_ids),
    !anyDuplicated(start$BIKEID), !anyDuplicated(log$BIKEID))
  list(start_hours = start, service_log = log, assume_service_h = 70,
    description = paste(if (file.exists(start_path)) "Team-supplied simulated starting hours." else
      "Simulated staggered offsets, uniform 0 to 60 hours, seed 42.",
      if (nrow(log)) paste(nrow(log), "team-supplied simulated service records.") else "No recorded service log supplied.",
      "Package assumes service every 70 ride hours; due threshold is 60 ride hours."))
}
