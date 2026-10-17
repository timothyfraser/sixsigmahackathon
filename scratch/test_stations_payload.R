library(shiny)

format_stations_payload <- function(st_df) {
  lapply(seq_len(nrow(st_df)), function(i) {
    list(
      id     = as.integer(st_df$id[i]),
      dockID = as.character(st_df$dockID[i]),
      lat    = as.numeric(st_df$lat[i]),
      lon    = as.numeric(st_df$lon[i]),
      zone   = as.character(st_df$zone[i])
    )
  })
}

st_df <- data.frame(id = 0:2, dockID = c("A", "B", "C"), lat = c(40.1, 40.2, 40.3), lon = c(-74.1, -74.2, -74.3), zone = c("office", "residential", "retail"))
payload <- format_stations_payload(st_df)
json_out <- as.character(shiny:::toJSON(list(stations = payload)))
cat("Serialized stations format:\n")
cat(substr(json_out, 1, 150), "\n")

