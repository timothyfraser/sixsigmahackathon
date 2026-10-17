for (city in c("tampa", "jersey_city", "milwaukee")) {
  st_file <- file.path("data", "stations", paste0(city, ".csv"))
  zn_file <- file.path("data", "zoning", paste0(city, ".csv"))
  rds_file <- file.path("data", paste0(city, ".rds"))
  
  st <- read.csv(st_file, colClasses = "character")
  zn <- read.csv(zn_file, colClasses = "character")
  m <- merge(st, zn, by = "dockID", all.x = TRUE)
  
  cat("=== City:", city, "===\n")
  cat("Stations count:", nrow(st), "\n")
  cat("Lat range:", range(as.numeric(st$lat)), "\n")
  cat("Lon range:", range(as.numeric(st$lon)), "\n")
  cat("Zones:", table(m$zone, useNA = "always"), "\n")
  
  # Check RDS
  mov <- readRDS(rds_file)
  cat("Bikes count:", length(unique(mov$BIKEID)), "\n")
  cat("Dates range:", range(as.Date(mov$time, tz = "America/New_York")), "\n")
  cat("Sample dockID:\n")
  print(head(st$dockID, 3))
  cat("\n")
}

