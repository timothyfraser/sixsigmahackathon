# Recompute maintenance statuses with the package's service_log implementation.
suppressPackageStartupMessages({library(dplyr);library(jsonlite)})
source("bikesmart/R/maintenance_qc.R")
source("tools/bikesmart_maintenance_inputs.R")
request <- fromJSON(file("stdin"))
stopifnot(request$city %in% c("jersey_city", "milwaukee", "tampa"))
base <- fromJSON("bike-wise-ui/server/data/maintenance.json")[[request$city]]
status <- base$service_status
if (is.null(status)) status <- base$service_due
stopifnot(nrow(status) == base$fleet_size, !anyDuplicated(status$BIKEID))
log <- request$records[c("BIKEID", "service_time")]
stopifnot(nrow(log) > 0, all(log$BIKEID %in% status$BIKEID))
history <- readRDS(file.path("data", paste0(request$city, ".rds")))
reference <- parse_time(base$reference_time)
# Preserve original ID order: seeded starting hours depend on it.
all_ids <- unique(history$BIKEID)
history <- history[history$BIKEID %in% log$BIKEID & as.numeric(history$time) <= as.numeric(reference), ]
inputs <- maintenance_inputs(request$city, all_ids, base$service_interval_h)
start <- inputs$start_hours
# The package errors if service removes every history row. At the reference
# instant, no post-service interval exists: hours are exactly zero. Apply that
# boundary directly and let the package calculate all earlier service events.
effective <- log[as.numeric(parse_time(log$service_time)) <= as.numeric(reference), ]
reset_ids <- unique(effective$BIKEID[as.numeric(parse_time(effective$service_time)) == as.numeric(reference)])
calculate_ids <- setdiff(unique(log$BIKEID), reset_ids)
if (length(calculate_ids)) {
  fresh <- service_status(history[history$BIKEID %in% calculate_ids, ],
    service_interval_h = base$service_interval_h, service_log = log, start_hours = start, assume_service_h = base$assume_service_h)
  fresh$due_at <- format(fresh$due_at, "%Y-%m-%dT%H:%M:%S%z", tz = base$time_zone)
  status[match(fresh$BIKEID, status$BIKEID), names(fresh)] <- as.data.frame(fresh)
}
reset_rows <- status$BIKEID %in% reset_ids
status$ride_hours[reset_rows] <- 0
status$due[reset_rows] <- FALSE
status$due_at[reset_rows] <- NA_character_
status <- status[order(status$ride_hours, decreasing = TRUE), ]
ranked <- rank_stations(status, base$service_interval_h)
ranked$lat <- base$stations$lat[match(ranked$DOCID, base$stations$DOCID)]
ranked$lon <- base$stations$lon[match(ranked$DOCID, base$stations$DOCID)]
result <- list(service_status = status, service_due = status[status$due, ], stations = ranked)
cat(toJSON(result, auto_unbox = TRUE, dataframe = "rows", na = "null", null = "null", digits = 15))
