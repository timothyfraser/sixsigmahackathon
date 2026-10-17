# Test building routing for all 3 cities
library(dplyr)
library(jsonlite)

build_city_network <- function(city_key) {
  st_file <- file.path("data", "stations", paste0(city_key, ".csv"))
  zn_file <- file.path("data", "zoning", paste0(city_key, ".csv"))
  
  stations <- read.csv(st_file, colClasses = "character")
  stations$lat <- as.numeric(stations$lat)
  stations$lon <- as.numeric(stations$lon)
  zones <- read.csv(zn_file, colClasses = "character")
  stations <- merge(stations, zones, by = "dockID", all.x = TRUE)
  stations$zone[is.na(stations$zone)] <- "unassigned"
  stations$id <- seq_len(nrow(stations)) - 1L
  
  # For Tampa, parse orthogonal street names if available; otherwise use Manhattan corner turn
  route_list <- list()
  pair_to_route_idx <- list()
  route_counter <- 0L
  
  if (city_key == "tampa") {
    ew_names <- c("East Washington Street", "East Jackson Street", "East Kennedy Boulevard",
                  "East Madison Street", "East Twiggs Street", "East Zack Street", "Polk Street")
    clean_dock <- function(dockID) {
      parts <- strsplit(dockID, " & ")[[1]]
      if (parts[1] %in% ew_names) c(ew = parts[1], ns = parts[2]) else c(ew = parts[2], ns = parts[1])
    }
    p <- t(sapply(stations$dockID, clean_dock))
    stations$ew <- p[, 1]
    stations$ns <- p[, 2]
    grid_coords <- list()
    for (i in seq_len(nrow(stations))) {
      key <- paste(stations$ew[i], stations$ns[i], sep = " | ")
      grid_coords[[key]] <- c(lat = stations$lat[i], lon = stations$lon[i])
    }
    
    for (i in seq_len(nrow(stations))) {
      for (j in seq_len(nrow(stations))) {
        pair_key <- paste(i - 1L, j - 1L, sep = "_")
        if (i == j) { pair_to_route_idx[[pair_key]] <- -1L; next }
        st1 <- stations[i, ]
        st2 <- stations[j, ]
        if (st1$ew == st2$ew || st1$ns == st2$ns) {
          route_list[[length(route_list) + 1L]] <- list(lats = c(st1$lat, st2$lat), lons = c(st1$lon, st2$lon), n = 2L, w1 = 1.0)
        } else {
          key1 <- paste(st1$ew, st2$ns, sep = " | ")
          key2 <- paste(st2$ew, st1$ns, sep = " | ")
          corner <- if (!is.null(grid_coords[[key1]])) grid_coords[[key1]] else grid_coords[[key2]]
          d1_dist <- sqrt((corner["lat"] - st1$lat)^2 + (corner["lon"] - st1$lon)^2)
          d2_dist <- sqrt((st2$lat - corner["lat"])^2 + (st2$lon - corner["lon"])^2)
          w1 <- as.numeric(d1_dist / (d1_dist + d2_dist))
          route_list[[length(route_list) + 1L]] <- list(lats = c(st1$lat, as.numeric(corner["lat"]), st2$lat), lons = c(st1$lon, as.numeric(corner["lon"]), st2$lon), n = 3L, w1 = w1)
        }
        pair_to_route_idx[[pair_key]] <- route_counter
        route_counter <- route_counter + 1L
      }
    }
  } else {
    # Orthogonal Manhattan corner turn along street grid for Jersey City and Milwaukee
    for (i in seq_len(nrow(stations))) {
      for (j in seq_len(nrow(stations))) {
        pair_key <- paste(i - 1L, j - 1L, sep = "_")
        if (i == j) { pair_to_route_idx[[pair_key]] <- -1L; next }
        st1 <- stations[i, ]
        st2 <- stations[j, ]
        
        # Lat/Lon differences
        dlat <- abs(st1$lat - st2$lat)
        dlon <- abs(st1$lon - st2$lon)
        
        if (dlat < 0.0005 || dlon < 0.0005) {
          route_list[[length(route_list) + 1L]] <- list(lats = c(st1$lat, st2$lat), lons = c(st1$lon, st2$lon), n = 2L, w1 = 1.0)
        } else {
          # Corner turn at st1$lat, st2$lon (travel along E-W street first, then N-S avenue)
          corner_lat <- st1$lat
          corner_lon <- st2$lon
          d1_dist <- dlon
          d2_dist <- dlat
          w1 <- as.numeric(d1_dist / (d1_dist + d2_dist))
          route_list[[length(route_list) + 1L]] <- list(lats = c(st1$lat, corner_lat, st2$lat), lons = c(st1$lon, corner_lon, st2$lon), n = 3L, w1 = w1)
        }
        pair_to_route_idx[[pair_key]] <- route_counter
        route_counter <- route_counter + 1L
      }
    }
  }
  
  list(stations = stations, route_list = route_list, pair_to_route_idx = pair_to_route_idx)
}

for (c_name in c("tampa", "jersey_city", "milwaukee")) {
  net <- build_city_network(c_name)
  cat(c_name, ": stations =", nrow(net$stations), ", routes =", length(net$route_list), "\n")
}

