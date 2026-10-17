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
all_bike_ids <- sort(unique(movement$BIKEID))

dock_map <- setNames(seq_len(nrow(stations)) - 1L, stations$dockID)
bike_map <- setNames(seq_len(length(all_bike_ids)) - 1L, all_bike_ids)

ew_names <- c("East Washington Street", "East Jackson Street", "East Kennedy Boulevard",
              "East Madison Street", "East Twiggs Street", "East Zack Street", "Polk Street")

clean_dock <- function(dockID) {
  parts <- strsplit(dockID, " & ")[[1]]
  if (parts[1] %in% ew_names) {
    c(ew = parts[1], ns = parts[2])
  } else {
    c(ew = parts[2], ns = parts[1])
  }
}

p <- t(sapply(stations$dockID, clean_dock))
stations$ew <- p[, 1]
stations$ns <- p[, 2]
stations$id <- seq_len(nrow(stations)) - 1L

grid_coords <- list()
for (i in seq_len(nrow(stations))) {
  key <- paste(stations$ew[i], stations$ns[i], sep = " | ")
  grid_coords[[key]] <- c(lat = stations$lat[i], lon = stations$lon[i])
}

route_list <- list()
pair_to_route_idx <- list()
route_counter <- 0L

for (i in seq_len(nrow(stations))) {
  for (j in seq_len(nrow(stations))) {
    pair_key <- paste(i - 1L, j - 1L, sep = "_")
    if (i == j) {
      pair_to_route_idx[[pair_key]] <- -1L
      next
    }
    st1 <- stations[i, ]
    st2 <- stations[j, ]
    if (st1$ew == st2$ew || st1$ns == st2$ns) {
      route_list[[length(route_list) + 1L]] <- list(
        lats = c(st1$lat, st2$lat),
        lons = c(st1$lon, st2$lon),
        n = 2L,
        w1 = 1.0
      )
    } else {
      key1 <- paste(st1$ew, st2$ns, sep = " | ")
      key2 <- paste(st2$ew, st1$ns, sep = " | ")
      corner <- if (!is.null(grid_coords[[key1]])) grid_coords[[key1]] else grid_coords[[key2]]
      d1_dist <- sqrt((corner["lat"] - st1$lat)^2 + (corner["lon"] - st1$lon)^2)
      d2_dist <- sqrt((st2$lat - corner["lat"])^2 + (st2$lon - corner["lon"])^2)
      w1 <- as.numeric(d1_dist / (d1_dist + d2_dist))
      route_list[[length(route_list) + 1L]] <- list(
        lats = c(st1$lat, as.numeric(corner["lat"]), st2$lat),
        lons = c(st1$lon, as.numeric(corner["lon"]), st2$lon),
        n = 3L,
        w1 = w1
      )
    }
    pair_to_route_idx[[pair_key]] <- route_counter
    route_counter <- route_counter + 1L
  }
}

get_day_payload <- function(target_date) {
  day_mov <- movement %>% filter(date == target_date) %>% arrange(time)
  t_start <- as.POSIXct(paste(target_date, "00:00:00"), tz = "America/New_York")
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
    ungroup() %>%
    mutate(
      b_id = bike_map[BIKEID],
      d1 = dock_map[prev_dock],
      d2 = dock_map[DOCID],
      pair_k = paste(d1, d2, sep = "_"),
      r_idx = unlist(pair_to_route_idx[pair_k])
    ) %>%
    select(b_id, d1, d2, start_step, end_step, r_idx)
  
  day_dock_counts <- day_mov %>%
    filter(DOCID != "0") %>%
    count(DOCID, step, name = "bikes")
  
  dock_mat <- matrix(0L, nrow = 288, ncol = nrow(stations))
  for (k in seq_len(nrow(day_dock_counts))) {
    s_idx <- dock_map[day_dock_counts$DOCID[k]] + 1L
    st_idx <- day_dock_counts$step[k]
    if (!is.na(s_idx) && st_idx >= 1L && st_idx <= 288L) {
      dock_mat[st_idx, s_idx] <- day_dock_counts$bikes[k]
    }
  }
  
  list(
    trips = as.data.frame(day_trips),
    dock_mat = dock_mat
  )
}

p1 <- get_day_payload(all_dates[1])
p2 <- get_day_payload(all_dates[2])

cat("Day 1 trips:", nrow(p1$trips), "\n")
cat("Day 2 trips:", nrow(p2$trips), "\n")
cat("Summary of Day 2 start_step and end_step:\n")
print(summary(p2$trips$start_step))
print(summary(p2$trips$end_step))
print(head(p2$trips))

