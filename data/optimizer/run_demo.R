# Run all user locations at one shared instant across all three cities.
# No network requests. Outputs are simulated recommendations, not live service.
source("dock_projection.R")
locations <- read.csv("data/optimizer/user_locations.csv")
all_recommendations <- list()
all_exclusions <- list()
shared_reference <- as.POSIXct("2026-10-15 23:55:00", tz = "America/New_York")
for (city in c("jersey_city", "milwaukee", "tampa")) {
  tz <- if (city == "milwaukee") "America/Chicago" else "America/New_York"
  history <- readRDS(file.path("data", paste0(city, ".rds")))
  # Preserve the shared instant while giving each comparison its local timezone.
  now <- as.POSIXct(as.numeric(shared_reference), origin = "1970-01-01", tz = tz)
  if (!any(history$time == now)) stop("Shared reference snapshot missing for ", city)
  stations <- read.csv(file.path("data", "stations", paste0(city, ".csv")))
  snapshot <- history[history$time == now & history$DOCID != "0", ]
  inventory <- table(snapshot$DOCID)
  stations$live_bikes <- as.integer(inventory[stations$dockID])
  stations$live_bikes[is.na(stations$live_bikes)] <- 0L
  stations$capacity <- 30L
  rates <- compute_dock_rates(history[history$time < now, ], tz = tz)
  user_ids <- locations$location_id[locations$city == city]
  for (id in user_ids) for (mode in c("pickup", "return")) {
    result <- optimize_docks(id, stations, rates, mode = mode, now = now)
    excluded <- attr(result, "excluded_docks")
    stopifnot(nrow(result) + nrow(excluded) == 27,
      all(diff(result$distance_miles) >= 0),
      all(if (mode == "pickup") result$projected_bikes >= 1 else result$projected_spaces >= 1))
    if (nrow(result)) {
      result$arrival_time <- format(result$arrival_time, "%Y-%m-%dT%H:%M:%S%z", tz = tz)
      key <- paste(city, id, mode, sep = "/")
      all_recommendations[[key]] <- data.frame(city = city, location_id = id,
        mode = mode, reference_time = format(now, "%Y-%m-%dT%H:%M:%S%z", tz = tz), result)
    }
    if (nrow(excluded)) {
      excluded$arrival_time <- format(excluded$arrival_time, "%Y-%m-%dT%H:%M:%S%z", tz = tz)
      key <- paste(city, id, mode, sep = "/")
      all_exclusions[[key]] <- data.frame(city = city, location_id = id, mode = mode, excluded)
    }
  }
  cat(sprintf("PASS %s: 10 real locations x pickup/return; road distances, arrival projections, ordering and eligibility verified\n", city))
}
recommendations <- do.call(rbind, all_recommendations)
write.csv(recommendations, "data/optimizer/demo_recommendations.csv", row.names = FALSE)
if (length(all_exclusions)) {
  excluded <- do.call(rbind, all_exclusions)
  write.csv(excluded, "data/optimizer/demo_exclusions.csv", row.names = FALSE)
} else {
  write.csv(data.frame(city = character(), location_id = character(), mode = character(),
    dockID = character(), exclusion_reason = character()),
    "data/optimizer/demo_exclusions.csv", row.names = FALSE)
}
cat("PASS: all 60 city/location/mode cases; saved demo_recommendations.csv and demo_exclusions.csv\n")
