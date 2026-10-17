library(shiny)
library(leaflet)
library(htmlwidgets)
library(jsonlite)

stations_json <- toJSON(data.frame(id=0:26, dockID=paste0("Station ", 0:26), lat=27.95, lon=-82.45, zone="office"), auto_unbox = TRUE)
routes_json   <- toJSON(replicate(702, list(lats=c(27.95, 27.96), lons=c(-82.45, -82.46), n=2, w1=1), simplify=FALSE), auto_unbox = TRUE)

static_data_js <- paste0(
  "window.stationsData = ", stations_json, ";\n",
  "window.routesData = ", routes_json, ";\n"
)

cat("static_data_js nchar:", nchar(static_data_js), "\n")

m <- leaflet() %>%
  addTiles() %>%
  onRender("
    function(el, x) {
      console.log('Leaflet ready');
    }
  ")

cat("Leaflet onRender created OK!\n")

