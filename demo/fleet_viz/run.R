# demo/fleet_viz/run.R
# One-command launcher for the standalone maintenance fleet demo.

if (!requireNamespace("shiny", quietly = TRUE)) {
  stop("Package 'shiny' is required. Run install.packages('shiny')")
}
if (!requireNamespace("leaflet", quietly = TRUE)) {
  stop("Package 'leaflet' is required. Run install.packages('leaflet')")
}
if (!requireNamespace("dplyr", quietly = TRUE)) {
  stop("Package 'dplyr' is required. Run install.packages('dplyr')")
}

# Determine path to app.R
app_dir <- if (file.exists("demo/fleet_viz/app.R")) {
  "demo/fleet_viz"
} else if (file.exists("app.R")) {
  "."
} else {
  stop("Could not locate app.R")
}

cat("Launching BikeSmart Fleet Monitor Demo...\n")
shiny::runApp(app_dir, launch.browser = TRUE)

