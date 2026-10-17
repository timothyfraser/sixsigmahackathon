# Build the site's recorded analyses by calling the completed bikesmart package.
# No statistical formulas are reimplemented in JavaScript.
args <- commandArgs(trailingOnly = TRUE)
city_arg <- sub("^--city=", "", args[grepl("^--city=", args)])
if (!length(city_arg)) {
  stopifnot(requireNamespace("jsonlite", quietly = TRUE))
  outputs <- list()
  for (name in c("jersey_city", "milwaukee", "tampa")) {
    output <- tempfile(pattern = paste0("bikesmart-", name), fileext = ".json")
    status <- system2(file.path(R.home("bin"), "Rscript"),
      c("--vanilla", "tools/export_bikesmart_ui.R", paste0("--city=", name),
        paste0("--output=", output), if ("--rider-only" %in% args) "--rider-only"))
    if (status != 0) stop("BikeSmart city export failed: ", name)
    outputs[[name]] <- jsonlite::read_json(output, simplifyVector = FALSE)
    unlink(output)
  }
  combined <- list(
    locations = unname(do.call(c, lapply(outputs, function(x) x$optimizer$locations))),
    stations = unname(do.call(c, lapply(outputs, function(x) x$optimizer$stations))),
    records = unname(do.call(c, lapply(outputs, function(x) x$optimizer$records))),
    metadata = outputs[[1]]$optimizer$metadata)
  stopifnot(length(combined$locations) == 30, length(combined$stations) == 81,
            length(combined$records) == 1620)
  jsonlite::write_json(combined, "bike-wise-ui/src/data/optimizer.json", auto_unbox = TRUE,
    na = "null", null = "null", digits = 15)
  if (!"--rider-only" %in% args) {
    reports <- lapply(outputs, function(x) x$maintenance[[1]])
    jsonlite::write_json(reports, "bike-wise-ui/server/data/maintenance.json", auto_unbox = TRUE,
      na = "null", null = "null", digits = 15)
  }
  cat(if ("--rider-only" %in% args) "PASS: 1620 rider projections generated from bikesmart\n" else "PASS: site data generated from bikesmart; 1620 rider projections and city-isolated maintenance reports\n")
  quit(status = 0)
}
stopifnot(city_arg %in% c("jersey_city", "milwaukee", "tampa"))
suppressPackageStartupMessages(library(dplyr))
stopifnot(requireNamespace("jsonlite", quietly = TRUE))
for (file in list.files("bikesmart/R", pattern = "\\.R$", full.names = TRUE)) source(file)
source("tools/bikesmart_maintenance_inputs.R")
args <- commandArgs(trailingOnly = TRUE)
rider_only <- "--rider-only" %in% args
locations <- read.csv("data/optimizer/user_locations.csv", stringsAsFactors = FALSE)
distances <- read.csv("data/optimizer/user_dock_distances.csv", stringsAsFactors = FALSE)
reference <- as.POSIXct("2026-10-15 23:55:00", tz = "America/New_York")
records <- list(); station_metadata <- list(); reports <- list()
stamp <- function(value, tz) format(value, "%Y-%m-%dT%H:%M:%S%z", tz = tz)
for (city in city_arg) {
  tz <- if (city == "milwaukee") "America/Chicago" else "America/New_York"
  history <- readRDS(file.path("data", paste0(city, ".rds")))
  history <- history[history$time <= reference, ]
  stopifnot(max(history$time) == reference)
  stations <- read.csv(file.path("data/stations", paste0(city, ".csv")), stringsAsFactors = FALSE)
  zones <- read.csv(file.path("data/zoning", paste0(city, ".csv")), stringsAsFactors = FALSE)
  station_metadata[[city]] <- data.frame(city = city, dockID = stations$dockID,
    lat = stations$lat, lon = stations$lon, zone = zones$zone[match(stations$dockID, zones$dockID)])
  snapshot <- history[history$time == reference & history$DOCID != "0", ]
  inventory <- table(snapshot$DOCID)
  stations$live_bikes <- as.integer(inventory[stations$dockID])
  stations$live_bikes[is.na(stations$live_bikes)] <- 0L
  stations$capacity <- 30L
  rates <- compute_dock_rates(history[history$time < reference, ], tz = tz)
  for (location in locations$location_id[locations$city == city]) for (mode in c("pickup", "return")) {
    eligible <- optimize_docks(location, stations, rates, mode = mode, now = reference,
      user_distances = distances[distances$city == city, ], tz = tz)
    excluded <- attr(eligible, "excluded_docks")
    stopifnot(nrow(eligible) + nrow(excluded) == nrow(stations))
    for (kind in c("eligible", "excluded")) {
      rows <- if (kind == "eligible") eligible else excluded
      if (!nrow(rows)) next
      rows$arrival_time <- stamp(rows$arrival_time, tz)
      rows$city <- city; rows$location_id <- location; rows$mode <- mode
      rows$reference_time <- stamp(reference, tz)
      rows$eligible <- kind == "eligible"
      records[[paste(city, location, mode, kind)]] <- rows
    }
  }
  cat(sprintf("PASS package projections %s: 20 saved inputs, 27 stations each\n", city))
  if (!rider_only) {
    inputs <- maintenance_inputs(city, unique(history$BIKEID))
    start_hours <- inputs$start_hours
    service_log <- if (nrow(inputs$service_log)) inputs$service_log else NULL
    dispatch <- dispatch_recommendation(history, service_interval_h = 60,
      threshold_min = 90, start_hours = start_hours, service_log = service_log, assume_service_h = inputs$assume_service_h)
    daily <- daily_service_counts(history, service_interval_h = 60, tz = tz, start_hours = start_hours)
    chart <- p_chart(daily$d, daily$n, label = as.character(daily$day))
    status_all <- if (nrow(dispatch$service_due) == length(unique(history$BIKEID))) dispatch$service_due else
      service_status(history, service_interval_h = 60, start_hours = start_hours, service_log = service_log, assume_service_h = inputs$assume_service_h)
    status_all$due_at <- stamp(status_all$due_at, tz)
    dispatch$service_due$due_at <- stamp(dispatch$service_due$due_at, tz)
    dispatch$stations$lat <- stations$lat[match(dispatch$stations$DOCID, stations$dockID)]
    dispatch$stations$lon <- stations$lon[match(dispatch$stations$DOCID, stations$dockID)]
    reports[[city]] <- list(city = city, time_zone = tz, reference_time = stamp(reference, tz),
      history_start = stamp(min(history$time), tz), source = "bikesmart 0.1.0",
      service_interval_h = 60, alert_threshold_min = 90,
      starting_hours = inputs$description, assume_service_h = inputs$assume_service_h,
      service_log = inputs$service_log,
      fleet_size = length(unique(history$BIKEID)),
      service_status = status_all, service_due = dispatch$service_due,
      transit = dispatch$stuck_alerts,
      stuck_alerts = dispatch$stuck_alerts[dispatch$stuck_alerts$flagged, ],
      stations = dispatch$stations, chart = chart)
    stopifnot(all(chart$d <= chart$n), all(dispatch$service_due$due),
      all(diff(dispatch$stations$n_due) <= 0))
    cat(sprintf("PASS package maintenance %s: %d fleet, %d service due, %d flagged trips, %d daily subgroups\n",
      city, reports[[city]]$fleet_size, nrow(dispatch$service_due), nrow(reports[[city]]$stuck_alerts), nrow(chart)))
  }
  rm(history); gc(verbose = FALSE)
}
record_frame <- dplyr::bind_rows(records)
stopifnot(nrow(record_frame) == 540, !anyDuplicated(record_frame[c("city", "location_id", "mode", "dockID")]))
payload <- list(locations = locations[locations$city == city_arg, ], stations = dplyr::bind_rows(station_metadata), records = record_frame,
  metadata = list(package = "bikesmart", version = "0.1.0", source = "bikesmart/R/dock_projection.R",
    reference_time = stamp(reference, "America/New_York"), simulated = TRUE))
output <- sub("^--output=", "", args[grepl("^--output=", args)])
stopifnot(length(output) == 1)
jsonlite::write_json(list(optimizer = payload, maintenance = reports), output,
  auto_unbox = TRUE, dataframe = "rows", na = "null", null = "null", digits = 15)
