DATA_DIR <- "data"
STATION_CSV <- file.path(DATA_DIR, "stations", "tampa.csv")
ZONE_CSV <- file.path(DATA_DIR, "zoning", "tampa.csv")
MOVEMENT_RDS <- file.path(DATA_DIR, "tampa.rds")

library(dplyr)
library(jsonlite)

stations <- read.csv(STATION_CSV, colClasses = "character")
stations$lat <- as.numeric(stations$lat)
stations$lon <- as.numeric(stations$lon)
zones <- read.csv(ZONE_CSV, colClasses = "character")
stations <- merge(stations, zones, by = "dockID", all.x = TRUE)
stations$zone[is.na(stations$zone)] <- "unassigned"

movement <- readRDS(MOVEMENT_RDS)
movement$date <- as.Date(movement$time, tz = "America/New_York")
all_dates <- sort(unique(movement$date))
all_bike_ids <- sort(unique(movement$BIKEID))

dock_map <- setNames(seq_len(nrow(stations)) - 1L, stations$dockID)
bike_map <- setNames(seq_len(length(all_bike_ids)) - 1L, all_bike_ids)

day_mov <- movement %>% filter(date == all_dates[1]) %>% arrange(time)
t_start <- as.POSIXct(paste(all_dates[1], "00:00:00"), tz = "America/New_York")
day_mov$step <- as.integer(difftime(day_mov$time, t_start, units = "mins") / 5) + 1L

day_trips <- day_mov %>%
  filter(DOCID != "0") %>%
  arrange(BIKEID, time) %>%
  group_by(BIKEID) %>%
  mutate(
    prev_dock = lag(DOCID),
    start_step = lag(step),
    end_step = step
  ) %>%
  filter(!is.na(prev_dock) & DOCID != prev_dock) %>%
  ungroup()

cat("Total day 1 trips calculated this way:", nrow(day_trips), "\n")
print(head(day_mov %>% filter(BIKEID == all_bike_ids[1]), 10))

