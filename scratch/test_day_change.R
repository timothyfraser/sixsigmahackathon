library(dplyr)
library(jsonlite)

DATA_DIR <- "data"
STATION_CSV <- file.path(DATA_DIR, "stations", "tampa.csv")
ZONE_CSV <- file.path(DATA_DIR, "zoning", "tampa.csv")
MOVEMENT_RDS <- file.path(DATA_DIR, "tampa.rds")

stations <- read.csv(STATION_CSV, colClasses = "character")
stations$lat <- as.numeric(stations$lat)
stations$lon <- as.numeric(stations$lon)
zones <- read.csv(ZONE_CSV, colClasses = "character")
stations <- merge(stations, zones, by = "dockID", all.x = TRUE)

movement <- readRDS(MOVEMENT_RDS)
movement$date <- as.Date(movement$time, tz = "America/New_York")
all_dates <- sort(unique(movement$date))

# Let's inspect what happens in app.R:
# Day 1 initial:
# init_trips_json <- toJSON(initial_payload$trips, auto_unbox = TRUE)
#
# But in observeEvent(cur_day_date()):
# session$sendCustomMessage("load_day_data", list(
#   trips = payload$trips,
#   dock_mat = payload$dock_mat
# ))
p1 <- toJSON(list(trips = data.frame(a = 1:2, b = 3:4)))
cat("list(trips = df) json structure:\n", p1, "\n")

