DATA_DIR <- "data"

build_network <- function(city_key) {
  st_file <- file.path(DATA_DIR, "stations", paste0(city_key, ".csv"))
  zn_file <- file.path(DATA_DIR, "zoning", paste0(city_key, ".csv"))
  dist_file <- file.path(DATA_DIR, "distances", paste0(city_key, ".csv"))
  
  stations <- read.csv(st_file, colClasses = "character")
  stations$lat <- as.numeric(stations$lat)
  stations$lon <- as.numeric(stations$lon)
  zones <- read.csv(zn_file, colClasses = "character")
  stations <- merge(stations, zones, by = "dockID", all.x = TRUE)
  stations$zone[is.na(stations$zone)] <- "unassigned"
  stations$id <- seq_len(nrow(stations)) - 1L
  
  N <- nrow(stations)
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
    for (i in seq_len(N)) {
      key <- paste(stations$ew[i], stations$ns[i], sep = " | ")
      grid_coords[[key]] <- c(lat = stations$lat[i], lon = stations$lon[i])
    }
    for (i in seq_len(N)) {
      for (j in seq_len(N)) {
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
    # Distance matrix based intermediate corner turns on street network
    dist_df <- read.csv(dist_file, colClasses = c("character", "character", "numeric"))
    dmat <- matrix(Inf, N, N)
    diag(dmat) <- 0
    for (k in 1:nrow(dist_df)) {
      idx1 <- which(stations$dockID == dist_df$dockID1[k])
      idx2 <- which(stations$dockID == dist_df$dockID2[k])
      if (length(idx1) == 1 && length(idx2) == 1) {
        dmat[idx1, idx2] <- dist_df$distance[k]
      }
    }
    
    for (i in seq_len(N)) {
      for (j in seq_len(N)) {
        pair_key <- paste(i - 1L, j - 1L, sep = "_")
        if (i == j) { pair_to_route_idx[[pair_key]] <- -1L; next }
        st1 <- stations[i, ]
        st2 <- stations[j, ]
        d_direct <- dmat[i, j]
        
        # Check if there is an intermediate station along the street route
        best_diff <- Inf
        best_k <- -1
        for (k in seq_len(N)) {
          if (k != i && k != j) {
            diff <- (dmat[i, k] + dmat[k, j]) - d_direct
            if (diff < best_diff) {
              best_diff <- diff
              best_k <- k
            }
          }
        }
        
        if (best_diff < 0.05 && best_k > 0) {
          # Passes through station best_k (turn corner on street network)
          st_corner <- stations[best_k, ]
          w1 <- as.numeric(dmat[i, best_k] / (dmat[i, best_k] + dmat[best_k, j]))
          route_list[[length(route_list) + 1L]] <- list(
            lats = c(st1$lat, st_corner$lat, st2$lat),
            lons = c(st1$lon, st_corner$lon, st2$lon),
            n = 3L,
            w1 = w1
          )
        } else {
          # Direct adjacent street connection
          route_list[[length(route_list) + 1L]] <- list(
            lats = c(st1$lat, st2$lat),
            lons = c(st1$lon, st2$lon),
            n = 2L,
            w1 = 1.0
          )
        }
        pair_to_route_idx[[pair_key]] <- route_counter
        route_counter <- route_counter + 1L
      }
    }
  }
  
  cat("City:", city_key, "Routes:", length(route_list), "Pairs:", length(pair_to_route_idx), "\n")
  return(list(stations = stations, route_list = route_list, pair_to_route_idx = pair_to_route_idx))
}

for (c_name in c("tampa", "jersey_city", "milwaukee")) {
  net <- build_network(c_name)
}
cat("All routing built successfully!\n")

