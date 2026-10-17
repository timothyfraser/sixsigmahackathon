# Export the fleet_viz demo's own route/trip helpers for the authenticated React monitor.
# Each city runs in a fresh process, keeping the full movement data out of the web server.
args <- commandArgs(trailingOnly = TRUE)
city_arg <- sub("^--city=", "", args[grepl("^--city=", args)])
if (!length(city_arg)) {
  for (city in c("jersey_city", "milwaukee", "tampa")) {
    result <- system2(file.path(R.home("bin"), "Rscript"),
      c("--vanilla", "tools/export_fleet_viz.R", paste0("--city=", city)))
    if (result != 0) stop("Fleet replay export failed for ", city)
  }
  cat("PASS: fleet_viz replay exported and validated for all cities and available dates\n")
  quit(status = 0)
}
stopifnot(length(city_arg) == 1, city_arg %in% c("jersey_city", "milwaukee", "tampa"))
suppressPackageStartupMessages(library(dplyr))
stopifnot(requireNamespace("jsonlite", quietly = TRUE))
# Evaluate only reusable demo declarations: never load the Shiny UI or launch a server.
allowed <- c("CAPACITY", "FLEET", "CITIES", "city_data_cache", "format_stations_payload",
  "load_city_bundle", "format_trips_payload", "get_day_payload")
for (expression in parse("demo/fleet_viz/app.R", encoding = "UTF-8")) {
  if (is.call(expression) && identical(expression[[1]], as.name("<-")) &&
      is.symbol(expression[[2]]) && as.character(expression[[2]]) %in% allowed) eval(expression)
}
DATA_DIR <- normalizePath("data", winslash = "/")
bundle <- load_city_bundle(city_arg)
stopifnot(nrow(bundle$stations) == 27, length(bundle$all_bike_ids) == FLEET)
streets <- jsonlite::read_json(file.path("bike-wise-ui/server/data/fleet", city_arg, "streets.json"), simplifyVector = TRUE)
street_names <- read.csv(file.path("data/stations", paste0(city_arg, ".csv")), stringsAsFactors = FALSE)$dockID
for (pair in names(bundle$pair_to_route_idx)) {
  index <- bundle$pair_to_route_idx[[pair]]
  if (index < 0) next
  endpoints <- as.integer(strsplit(pair, "_")[[1]]) + 1L
  original_indexes <- match(bundle$stations$dockID[endpoints], street_names) - 1L
  route <- streets$routes[[paste(original_indexes, collapse = "_")]]
  stopifnot(abs(route$lats[[1]] - bundle$stations$lat[endpoints[[1]]]) < 1e-8,
    abs(tail(route$lons, 1) - bundle$stations$lon[endpoints[[2]]]) < 1e-8)
  stopifnot(!is.null(route), route$n >= 2, length(route$cumulative) == route$n,
    all(diff(route$cumulative) >= 0), route$cumulative[[1]] == 0, tail(route$cumulative, 1) == 1)
  route$street_node_ids <- NULL
  bundle$route_list[[index + 1L]] <- route
}
output_dir <- file.path("bike-wise-ui/server/data/fleet", city_arg)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
write_gzip <- function(value, name) {
  connection <- gzfile(file.path(output_dir, paste0(name, ".json.gz")), "wb")
  on.exit(close(connection))
  writeLines(jsonlite::toJSON(value, auto_unbox = TRUE, dataframe = "rows",
    matrix = "rowmajor", digits = 12, na = "null", null = "null"), connection, useBytes = TRUE)
}
days <- list()
for (date_value in as.character(bundle$all_dates)) {
  date <- as.Date(date_value)
  payload <- get_day_payload(bundle, date)
  day <- bundle$movement[bundle$movement$date == date, ]
  midnight <- as.POSIXct(paste(date, "00:00:00"), tz = bundle$meta$tz)
  steps <- as.integer(difftime(day$time, midnight, units = "mins") / 5) + 1L
  bike_indexes <- match(day$BIKEID, bundle$all_bike_ids)
  dock_indexes <- as.integer(bundle$dock_map[as.character(day$DOCID)])
  dock_indexes[as.character(day$DOCID) == "0"] <- -1L
  stopifnot(!anyNA(dock_indexes), !anyNA(bike_indexes))
  bike_docks <- matrix(-2L, nrow = 288, ncol = FLEET)
  bike_docks[cbind(steps, bike_indexes)] <- dock_indexes
  observed <- sort(unique(steps))
  stopifnot(!anyDuplicated(data.frame(step = steps, bike = bike_indexes)))
  for (step in observed) {
    state <- bike_docks[step, ]
    stopifnot(all(state >= -1L), sum(payload$dock_mat[step, ]) + sum(state == -1L) == FLEET,
      identical(as.integer(payload$dock_mat[step, ]), tabulate(state[state >= 0] + 1L, nbins = 27)),
      all(payload$dock_mat[step, ] >= 0), all(payload$dock_mat[step, ] <= CAPACITY))
  }
  if (payload$trips$n) stopifnot(all(payload$trips$r_idx >= 0),
    all(payload$trips$r_idx < length(bundle$route_list)),
    all(payload$trips$start_step < payload$trips$end_step))
  times <- seq(midnight, by = "5 mins", length.out = 288)
  write_gzip(list(date = date_value, time_zone = bundle$meta$tz,
    timestamps = format(times, "%Y-%m-%dT%H:%M:%S%z", tz = bundle$meta$tz),
    observed_steps = as.integer(observed), dock_mat = payload$dock_mat,
    bike_docks = bike_docks, trips = payload$trips), date_value)
  days[[date_value]] <- list(date = date_value, first_step = min(observed),
    last_step = max(observed), n_steps = length(observed))
}
full_days <- names(days)[vapply(days, function(day) day$n_steps == 288, logical(1))]
meta <- bundle$meta[c("id", "name", "state", "lat", "lon", "zoom", "tz")]
write_gzip(list(city = city_arg, meta = meta, capacity = CAPACITY, fleet_size = FLEET,
  dates = unname(days), default_date = if (length(full_days)) full_days[[1]] else names(days)[[1]],
  bike_ids = as.character(bundle$all_bike_ids), stations = bundle$stations_payload,
  routes = bundle$route_list, source = "demo/fleet_viz/app.R",
  route_source = streets$source, osm_timestamp = streets$osm_timestamp,
  max_matrix_difference_miles = streets$max_matrix_difference_miles,
  route_note = "Shortest bicycle street routes inferred from dock observations, not recorded GPS tracks."), "network")
cat(sprintf("PASS fleet_viz %s: %d dates, 27 stations, 405 bikes; every observed snapshot reconciles; routes valid\n",
  city_arg, length(days)))
