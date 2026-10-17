DATA_DIR <- "data"
CAPACITY <- 30L

CITIES <- list(
  tampa = list(name = "Tampa", lat = 27.9486, lon = -82.4572, zoom = 15, tz = "America/New_York"),
  jersey_city = list(name = "Jersey City", lat = 40.7194, lon = -74.0446, zoom = 14, tz = "America/New_York"),
  milwaukee = list(name = "Milwaukee", lat = 43.0389, lon = -87.9065, zoom = 14, tz = "America/Chicago")
)

source("scratch/test_city_switch.R") # defines build_city_network

library(dplyr)
for (c_name in names(CITIES)) {
  meta <- CITIES[[c_name]]
  mov <- readRDS(file.path("data", paste0(c_name, ".rds")))
  mov$date <- as.Date(mov$time, tz = meta$tz)
  u_dates <- sort(unique(mov$date))
  cat(c_name, "unique dates:", length(u_dates), "range:", as.character(range(u_dates)), "\n")
}
cat("All cities data validated successfully!\n")

