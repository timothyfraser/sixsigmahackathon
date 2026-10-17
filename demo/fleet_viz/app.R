# demo/fleet_viz/app.R ──────────────────────────────────────────────────────
# BikeSmart Fleet Monitor — Multi-City Maintenance Demo
# Cities: Tampa (FL), Jersey City (NJ), Milwaukee (WI)
# 405 Bikes · 27 Stations per city · 5-Minute Scrubbing "Bike Paths" Animation
# Street-Grid Accurate Routing · Zero-Flicker Canvas Rendering Engine
#
# Run from repository root:
#   shiny::runApp("demo/fleet_viz")
# Or run with Rscript:
#   Rscript demo/fleet_viz/run.R
# ────────────────────────────────────────────────────────────────────────────

suppressPackageStartupMessages({
  library(shiny)
  library(leaflet)
  library(htmlwidgets)
  library(dplyr)
  library(jsonlite)
})

# ── 1. Robust path resolution ────────────────────────────────────────────────
find_data_dir <- function() {
  candidates <- c(
    "../../data",
    "data",
    file.path("..", "data"),
    file.path(".", "data")
  )
  for (cand in candidates) {
    p <- file.path(cand, "stations", "tampa.csv")
    if (file.exists(p)) return(normalizePath(cand, winslash = "/"))
  }
  stop("Could not locate 'data' directory. Please run from repo root or demo/fleet_viz/.")
}

DATA_DIR <- find_data_dir()
CAPACITY <- 30L     # dock capacity
FLEET    <- 405L    # total fleet size per city

# ── 2. City Definitions & Metadata ───────────────────────────────────────────
CITIES <- list(
  tampa = list(
    id    = "tampa",
    name  = "Tampa",
    state = "FL",
    label = "🌴 Tampa, FL",
    lat   = 27.9486,
    lon   = -82.4572,
    zoom  = 15,
    tz    = "America/New_York",
    sub   = "Tampa Network · 405 Bikes · 27 Docks"
  ),
  jersey_city = list(
    id    = "jersey_city",
    name  = "Jersey City",
    state = "NJ",
    label = "🏙️ Jersey City, NJ",
    lat   = 40.7194,
    lon   = -74.0446,
    zoom  = 14,
    tz    = "America/New_York",
    sub   = "Jersey City Network · 405 Bikes · 27 Docks"
  ),
  milwaukee = list(
    id    = "milwaukee",
    name  = "Milwaukee",
    state = "WI",
    label = "🍺 Milwaukee, WI",
    lat   = 43.0389,
    lon   = -87.9065,
    zoom  = 14,
    tz    = "America/Chicago",
    sub   = "Milwaukee Network · 405 Bikes · 27 Docks"
  )
)

# ── Helper: Format stations array for client ─────────────────────────────────
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

# ── 3. City Data Loader with Memory Cache ─────────────────────────────────────
city_data_cache <- list()

load_city_bundle <- function(city_key) {
  if (!is.null(city_data_cache[[city_key]])) {
    return(city_data_cache[[city_key]])
  }

  meta      <- CITIES[[city_key]]
  st_file   <- file.path(DATA_DIR, "stations", paste0(city_key, ".csv"))
  zn_file   <- file.path(DATA_DIR, "zoning", paste0(city_key, ".csv"))
  dist_file <- file.path(DATA_DIR, "distances", paste0(city_key, ".csv"))
  mov_file  <- file.path(DATA_DIR, paste0(city_key, ".rds"))

  message(sprintf("[fleet_viz] Loading & caching data bundle for %s (%s)…", meta$name, meta$state))
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
    for (k in seq_len(nrow(dist_df))) {
      idx1 <- which(stations$dockID == dist_df$dockID1[k])
      idx2 <- which(stations$dockID == dist_df$dockID2[k])
      if (length(idx1) == 1L && length(idx2) == 1L) {
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

        # Find best intermediate corner station along street network
        best_diff <- Inf
        best_k <- -1L
        for (k in seq_len(N)) {
          if (k != i && k != j) {
            diff <- (dmat[i, k] + dmat[k, j]) - d_direct
            if (diff < best_diff) {
              best_diff <- diff
              best_k <- k
            }
          }
        }

        if (best_diff < 0.05 && best_k > 0L) {
          # Route turns at intermediate station along the street
          st_corner <- stations[best_k, ]
          w1 <- as.numeric(dmat[i, best_k] / (dmat[i, best_k] + dmat[best_k, j]))
          route_list[[length(route_list) + 1L]] <- list(
            lats = c(st1$lat, st_corner$lat, st2$lat),
            lons = c(st1$lon, st_corner$lon, st2$lon),
            n    = 3L,
            w1   = w1
          )
        } else {
          # Direct adjacent street corridor
          route_list[[length(route_list) + 1L]] <- list(
            lats = c(st1$lat, st2$lat),
            lons = c(st1$lon, st2$lon),
            n    = 2L,
            w1   = 1.0
          )
        }
        pair_to_route_idx[[pair_key]] <- route_counter
        route_counter <- route_counter + 1L
      }
    }
  }

  movement <- readRDS(mov_file)
  movement$date <- as.Date(movement$time, tz = meta$tz)
  all_dates <- sort(unique(movement$date))
  all_bike_ids <- sort(unique(movement$BIKEID))

  dock_map <- setNames(seq_len(nrow(stations)) - 1L, stations$dockID)
  bike_map <- setNames(seq_len(length(all_bike_ids)) - 1L, all_bike_ids)

  dock_ts <- movement %>%
    filter(DOCID != "0") %>%
    count(DOCID, time, date, name = "bikes") %>%
    mutate(
      bikes    = as.integer(bikes),
      fill_pct = bikes / CAPACITY
    )

  daily_dock <- dock_ts %>%
    group_by(date, DOCID) %>%
    summarise(
      mean_bikes = mean(bikes),
      mean_fill  = mean(fill_pct),
      min_bikes  = min(bikes),
      max_bikes  = max(bikes),
      n_empty    = sum(bikes == 0L),
      n_full     = sum(bikes == CAPACITY),
      .groups    = "drop"
    ) %>%
    left_join(stations[, c("dockID", "zone")], by = c("DOCID" = "dockID"))

  bundle <- list(
    city_key          = city_key,
    meta              = meta,
    stations          = stations,
    stations_payload  = format_stations_payload(stations),
    route_list        = route_list,
    pair_to_route_idx = pair_to_route_idx,
    movement          = movement,
    all_dates         = all_dates,
    all_bike_ids      = all_bike_ids,
    dock_map          = dock_map,
    bike_map          = bike_map,
    dock_ts           = dock_ts,
    daily_dock        = daily_dock
  )

  city_data_cache[[city_key]] <<- bundle
  bundle
}

# Pre-load Tampa as the initial city
init_bundle <- load_city_bundle("tampa")
stations_json_init <- toJSON(init_bundle$stations_payload, auto_unbox = TRUE)
routes_json_init   <- toJSON(init_bundle$route_list, auto_unbox = TRUE)

# ── Helper: Format trips payload for WebSocket streaming ─────────────────────
format_trips_payload <- function(trips_df) {
  list(
    b_id       = as.integer(unname(trips_df$b_id)),
    d1         = as.integer(unname(trips_df$d1)),
    d2         = as.integer(unname(trips_df$d2)),
    start_step = as.integer(unname(trips_df$start_step)),
    end_step   = as.integer(unname(trips_df$end_step)),
    r_idx      = as.integer(unname(trips_df$r_idx)),
    n          = as.integer(nrow(trips_df))
  )
}

get_day_payload <- function(bundle, target_date) {
  day_mov <- bundle$movement %>% filter(date == target_date) %>% arrange(time)
  t_start <- as.POSIXct(paste(target_date, "00:00:00"), tz = bundle$meta$tz)
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
      b_id = as.integer(unname(bundle$bike_map[BIKEID])),
      d1 = as.integer(unname(bundle$dock_map[prev_dock])),
      d2 = as.integer(unname(bundle$dock_map[DOCID])),
      pair_k = paste(d1, d2, sep = "_"),
      r_idx = as.integer(unname(unlist(bundle$pair_to_route_idx[pair_k])))
    ) %>%
    select(b_id, d1, d2, start_step, end_step, r_idx)

  # Build 288 x 27 dock bikes matrix
  day_dock_counts <- day_mov %>%
    filter(DOCID != "0") %>%
    count(DOCID, step, name = "bikes")

  dock_mat <- matrix(0L, nrow = 288, ncol = nrow(bundle$stations))
  for (k in seq_len(nrow(day_dock_counts))) {
    s_idx <- bundle$dock_map[day_dock_counts$DOCID[k]] + 1L
    st_idx <- day_dock_counts$step[k]
    if (!is.na(s_idx) && st_idx >= 1L && st_idx <= 288L) {
      dock_mat[st_idx, s_idx] <- day_dock_counts$bikes[k]
    }
  }

  day_trips_df <- as.data.frame(day_trips)
  list(
    trips = format_trips_payload(day_trips_df),
    trips_df = day_trips_df,
    dock_mat = dock_mat
  )
}

# ── Helper: Time period description ──────────────────────────────────────────
time_desc <- function(t_posix) {
  h <- as.integer(format(t_posix, "%H"))
  m <- as.integer(format(t_posix, "%M"))
  mins <- h * 60 + m
  if (mins >= 420 && mins <= 570)  return("Morning Commute (Peak Inflow)")
  if (mins >= 690 && mins <= 810)  return("Lunchtime Activity")
  if (mins >= 990 && mins <= 1170) return("Evening Commute (Peak Return)")
  if (mins >= 1260 || mins <= 270) return("Night / Off-Peak Period")
  "Regular Daytime Operation"
}

# ════════════════════════════════════════════════════════════════════════════
#  UI
# ════════════════════════════════════════════════════════════════════════════
ui <- fluidPage(
  title = "BikeSmart · Fleet Monitor",

  tags$head(
    tags$style(HTML("
      *, *::before, *::after { box-sizing: border-box; }
      html, body {
        margin: 0; padding: 0; height: 100%; overflow: hidden;
        background: #0d1117; color: #e6edf3;
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
      }

      /* ── Sidebar ── */
      .sidebar {
        background: #161b22;
        border-right: 1px solid #30363d;
        padding: 16px 14px;
        height: 100vh;
        overflow-y: auto;
      }
      .app-title {
        color: #58a6ff; font-size: 1.22em; font-weight: 700; margin: 0 0 2px;
        display: flex; align-items: center; justify-content: space-between;
      }
      .badge-maint {
        background: #238636; color: #ffffff; font-size: 0.58em;
        padding: 3px 7px; border-radius: 10px; text-transform: uppercase;
        font-weight: 700; letter-spacing: 0.05em;
      }
      .app-sub { color: #8b949e; font-size: 0.74em; margin: 0 0 10px; }
      hr.div   { border: none; border-top: 1px solid #30363d; margin: 10px 0; }
      .sec-lbl {
        font-size: 0.70em; font-weight: 700; color: #8b949e;
        text-transform: uppercase; letter-spacing: .08em; margin: 6px 0 4px;
      }

      /* ── Clock Banner ── */
      .clock-banner {
        text-align: center; background: #0d1117; border: 1px solid #30363d;
        border-radius: 8px; padding: 8px 10px; margin: 6px 0 10px;
      }
      .clock-time { font-size: 1.45em; font-weight: 800; color: #58a6ff; font-family: monospace; }
      .clock-desc { font-size: 0.72em; color: #8b949e; margin-top: 2px; }

      /* ── Clickable KPI cards (Perfect 100% Hit Area) ── */
      .kpi-row { display: flex; gap: 6px; margin: 6px 0; align-items: stretch; }
      .kpi-box {
        flex: 1; background: #0d1117; border: 1px solid #30363d;
        border-radius: 8px; padding: 7px 4px; text-align: center;
        display: flex; flex-direction: column; justify-content: center;
        user-select: none;
      }
      .kpi-clickable {
        cursor: pointer; transition: all 0.15s ease;
      }
      .kpi-clickable:hover {
        border-color: #58a6ff !important;
        background: #1c2128 !important;
        transform: translateY(-1px);
      }
      .kpi-clickable:active {
        transform: translateY(0);
      }
      .kpi-val { font-size: 1.25em; font-weight: 700; color: #58a6ff; }
      .kpi-lbl { font-size: 0.62em; color: #8b949e; line-height: 1.2; margin-top: 2px; }
      .kpi-hint { font-size: 0.58em; color: #8b949e; margin-top: 1px; }
      .kpi-badge {
        font-size: 0.58em; font-weight: 700; padding: 1px 5px;
        border-radius: 4px; display: inline-block; margin: 1px auto 0;
      }

      /* ── Day Selector Buttons ── */
      .day-btn-group { display: flex; gap: 4px; margin-bottom: 8px; }
      .day-btn-group .btn {
        background: #21262d; color: #c9d1d9; border: 1px solid #30363d;
        font-size: 0.75em; padding: 4px 8px; font-weight: 600;
      }
      .day-btn-group .btn:hover { background: #30363d; color: #58a6ff; }

      /* ── Legend ── */
      .lg-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 4px; font-size: 0.72em; }
      .lg-item { display: flex; align-items: center; gap: 6px; color: #c9d1d9; }
      .lg-dot  { width: 11px; height: 11px; border-radius: 50%; flex-shrink: 0; }

      /* ── Dark Tabs & Inputs ── */
      .nav-tabs { border-bottom: 1px solid #30363d; margin-bottom: 10px; }
      .nav-tabs > li > a {
        color: #8b949e; border: none; font-size: 0.76em; font-weight: 600;
        padding: 5px 8px; background: transparent;
      }
      .nav-tabs > li.active > a, .nav-tabs > li.active > a:focus, .nav-tabs > li.active > a:hover {
        color: #58a6ff; background: #21262d; border: 1px solid #30363d;
        border-bottom-color: transparent; border-radius: 6px 6px 0 0;
      }
      .form-control, .selectize-input {
        background: #0d1117 !important; color: #e6edf3 !important;
        border: 1px solid #30363d !important; border-radius: 6px;
        font-size: 0.80em;
      }
      .selectize-dropdown {
        background: #161b22 !important; color: #e6edf3 !important;
        border: 1px solid #30363d !important;
      }
      .selectize-dropdown-content .option { color: #c9d1d9; }
      .selectize-dropdown-content .option.active { background: #21262d; color: #58a6ff; }

      /* ── Map ── */
      #map { height: 100vh !important; }
      .row { margin: 0 !important; }
      .col-sm-4, .col-sm-8 { padding: 0 !important; }

      .footer { font-size: 0.64em; color: #484f58; margin-top: 12px; line-height: 1.45; }
    ")),
    tags$script(HTML(paste0(
      "window.stationsData = ", stations_json_init, ";\n",
      "window.routesData = ", routes_json_init, ";\n"
    )))
  ),

  fluidRow(
    # ── Left sidebar ──────────────────────────────────────────────────────────
    column(4,
      div(class = "sidebar",
        div(class = "app-title",
          span("🚲 Fleet Monitor"),
          span(class = "badge-maint", "Live 5-Min")
        ),
        p(class = "app-sub", textOutput("app_sub_text")),

        # ── 1. City / Fleet Network Selector ──────────────────────────────────
        div(class = "sec-lbl", "Select City / Fleet Network"),
        selectInput("sel_city", label = NULL,
          choices = c(
            "🌴 Tampa, FL" = "tampa",
            "🏙️ Jersey City, NJ" = "jersey_city",
            "🍺 Milwaukee, WI" = "milwaukee"
          ),
          selected = "tampa"
        ),

        # ── 2. Date Selector ─────────────────────────────────────────────────
        div(class = "sec-lbl", "Calendar Date"),
        div(class = "day-btn-group",
          actionButton("btn_prev_day", "◀ Prev Day", class = "btn btn-sm"),
          actionButton("btn_next_day", "Next Day ▶", class = "btn btn-sm")
        ),
        selectInput("sel_date", label = NULL,
          choices  = setNames(as.character(init_bundle$all_dates), format(init_bundle$all_dates, "%a · %B %d, %Y")),
          selected = as.character(init_bundle$all_dates[1])
        ),

        # ── 3. Clock Banner & 5-Minute Slider ─────────────────────────────────
        uiOutput("clock_banner_ui"),

        sliderInput("time_idx", label = "Time of Day (Auto-Play / Scrub 5-Min)",
          min     = 1, max = 288, value = 100, step = 1,
          animate = animationOptions(interval = 500, loop = TRUE),
          width   = "100%"
        ),

        # ── 4. Real-Time Fleet KPIs (Clickable Toggles with 100% Hit Area) ────
        div(class = "kpi-row",
          div(class = "kpi-box",
            div(class = "kpi-val", textOutput("kpi_in_transit")),
            div(class = "kpi-lbl", "Bikes in Transit")
          ),
          div(class = "kpi-box kpi-clickable", id = "kpi_box_empty",
            onclick = "Shiny.setInputValue('btn_toggle_empty', Math.random(), {priority: 'event'});",
            div(class = "kpi-val", style = "color:#ff7b72", textOutput("kpi_empty_now")),
            div(class = "kpi-lbl", "Stations Empty (0)"),
            uiOutput("badge_empty_filter")
          ),
          div(class = "kpi-box kpi-clickable", id = "kpi_box_full",
            onclick = "Shiny.setInputValue('btn_toggle_full', Math.random(), {priority: 'event'});",
            div(class = "kpi-val", style = "color:#ffa657", textOutput("kpi_full_now")),
            div(class = "kpi-lbl", "Stations Full (30)"),
            uiOutput("badge_full_filter")
          )
        ),

        hr(class = "div"),

        # ── 5. Navigation Tabs ────────────────────────────────────────────────
        tabsetPanel(id = "side_tabs", type = "tabs",
          # ── Tab 1: Bike Paths ──
          tabPanel("🚲 Bike Paths",
            div(class = "sec-lbl", style = "margin-top:8px;", "Ride Trails Mode"),
            radioButtons("trail_mode", label = NULL,
              choices = c(
                "All 405 Bikes (Active Paths)" = "all",
                "Single Bike Journey (Inspect Bike)" = "single"
              ),
              selected = "all"
            ),

            conditionalPanel(
              condition = "input.trail_mode == 'single'",
              selectInput("sel_bike", "Select Bike to Track:",
                choices  = init_bundle$all_bike_ids,
                selected = init_bundle$all_bike_ids[1]
              ),
              uiOutput("single_bike_status_ui"),
              checkboxInput("show_past_trails", "Display Path History", value = TRUE)
            ),

            hr(class = "div"),
            div(class = "sec-lbl", "Legend - Click to Inspect"),
            div(class = "lg-grid",
              div(class = "lg-item", span(class = "lg-dot", style = "background:#2563eb; border:1px solid #ffffff;"), "Office Station"),
              div(class = "lg-item", span(class = "lg-dot", style = "background:#10b981; border:1px solid #ffffff;"), "Residential Station"),
              div(class = "lg-item", span(class = "lg-dot", style = "background:#f59e0b; border:1px solid #ffffff;"), "Retail Station"),
              div(class = "lg-item", span(class = "lg-dot", style = "background:#023e8a; border:1px solid #ffffff;"), "Moving Bike Head")
            ),
            tags$p(style = "font-size:.70em; color:#8b949e; margin-top:8px;",
              "Station circles are color-coded by zoning type. Click KPI cards above to show empty/full docks on the map. Click any station to inspect its 24-hr inventory. Rides turn corners smoothly along the downtown street grid."
            )
          ),

          # ── Tab 2: Station Deep-Dive ──
          tabPanel("🔍 Station Inspector",
            div(class = "sec-lbl", style = "margin-top:8px;", "Selected Station"),
            selectInput("sel_station", label = NULL,
              choices  = init_bundle$stations$dockID,
              selected = init_bundle$stations$dockID[1]
            ),
            uiOutput("station_metrics_ui"),
            div(class = "sec-lbl", "24-Hour Time-Series (Yellow line = Current time)"),
            plotOutput("station_ts_plot", height = "180px")
          )
        ),

        hr(class = "div"),
        div(class = "footer",
          "Cornell Six Sigma Hackathon · Big Red Crew", br(),
          "Tampa · Jersey City · Milwaukee Networks", br(),
          "Turn-by-turn street routing · Synchronized Canvas"
        )
      )
    ),

    # ── Right Map Panel ───────────────────────────────────────────────────────
    column(8,
      leafletOutput("map", height = "100vh")
    )
  )
)

# ════════════════════════════════════════════════════════════════════════════
#  SERVER
# ════════════════════════════════════════════════════════════════════════════
server <- function(input, output, session) {

  # Active City Bundle Reactive
  cur_city_key <- reactive({ req(input$sel_city); input$sel_city })
  cur_bundle   <- reactive({ load_city_bundle(cur_city_key()) })

  output$app_sub_text <- renderText({
    cur_bundle()$meta$sub
  })

  # ── City Switching Observer (Instant Cut, No FlyTo Delay) ────────────────
  observeEvent(cur_city_key(), {
    bundle <- cur_bundle()
    meta   <- bundle$meta

    # 1. Update station and bike select dropdowns
    updateSelectInput(session, "sel_station", choices = bundle$stations$dockID, selected = bundle$stations$dockID[1])
    updateSelectInput(session, "sel_bike", choices = bundle$all_bike_ids, selected = bundle$all_bike_ids[1])

    # 2. Instant snap cut to new city center (no slow flyTo zoom out/in)
    leafletProxy("map") %>%
      setView(lng = meta$lon, lat = meta$lat, zoom = meta$zoom)

    # 3. Stream new network topology as clean array of station objects
    session$sendCustomMessage("load_city_network", list(
      stations = bundle$stations_payload,
      routes   = bundle$route_list,
      center   = list(lat = meta$lat, lon = meta$lon, zoom = meta$zoom)
    ))

    # 4. Stream active day trips for the new city
    target_d <- cur_day_date()
    p_load   <- get_day_payload(bundle, target_d)
    session$sendCustomMessage("load_day_data", list(
      trips    = p_load$trips,
      dock_mat = p_load$dock_mat
    ))
  }, ignoreInit = TRUE)

  # ── Highlight Filter Toggle State ('none', 'empty', or 'full') ───────────
  highlight_filter <- reactiveVal("none")

  observeEvent(input$btn_toggle_empty, {
    if (highlight_filter() == "empty") {
      highlight_filter("none")
    } else {
      highlight_filter("empty")
    }
  })

  observeEvent(input$btn_toggle_full, {
    if (highlight_filter() == "full") {
      highlight_filter("none")
    } else {
      highlight_filter("full")
    }
  })

  output$badge_empty_filter <- renderUI({
    if (highlight_filter() == "empty") {
      span(class = "kpi-badge", style = "background:#ff7b72; color:#0d1117;", "● Showing")
    } else {
      span(class = "kpi-hint", "(Click to show)")
    }
  })

  output$badge_full_filter <- renderUI({
    if (highlight_filter() == "full") {
      span(class = "kpi-badge", style = "background:#ffa657; color:#0d1117;", "● Showing")
    } else {
      span(class = "kpi-hint", "(Click to show)")
    }
  })

  # ── Date navigation buttons ──────────────────────────────────────────────
  observeEvent(input$btn_prev_day, {
    bundle <- cur_bundle()
    cur_idx <- match(input$sel_date, as.character(bundle$all_dates))
    if (!is.na(cur_idx) && cur_idx > 1L) {
      updateSelectInput(session, "sel_date", selected = as.character(bundle$all_dates[cur_idx - 1L]))
    }
  })

  observeEvent(input$btn_next_day, {
    bundle <- cur_bundle()
    cur_idx <- match(input$sel_date, as.character(bundle$all_dates))
    if (!is.na(cur_idx) && cur_idx < length(bundle$all_dates)) {
      updateSelectInput(session, "sel_date", selected = as.character(bundle$all_dates[cur_idx + 1L]))
    }
  })

  # Active Day & Timestamps
  cur_day_date <- reactive({
    req(input$sel_date)
    as.Date(input$sel_date)
  })

  day_timestamps <- reactive({
    d <- cur_day_date()
    bundle <- cur_bundle()
    seq(from = as.POSIXct(paste(d, "00:00:00"), tz = bundle$meta$tz),
        by = "5 mins", length.out = 288L)
  })

  cur_time_posix <- reactive({
    ts <- day_timestamps()
    idx <- max(1L, min(288L, input$time_idx))
    ts[idx]
  })

  # Reactive day payload (trips + trips_df + dock_mat)
  day_data <- reactive({
    d <- cur_day_date()
    bundle <- cur_bundle()
    get_day_payload(bundle, d)
  })

  # When date changes, update client canvas data
  observeEvent(cur_day_date(), {
    payload <- day_data()
    session$sendCustomMessage("load_day_data", list(
      trips    = payload$trips,
      dock_mat = payload$dock_mat
    ))
  })

  # ── Real-Time Metrics & Clock UI ─────────────────────────────────────────
  output$clock_banner_ui <- renderUI({
    t_now <- cur_time_posix()
    div(class = "clock-banner",
      div(class = "clock-time", format(t_now, "%I:%M %p")),
      div(class = "clock-desc", time_desc(t_now))
    )
  })

  output$kpi_in_transit <- renderText({
    payload <- day_data()
    step_idx <- max(1L, min(288L, input$time_idx))
    docked <- sum(payload$dock_mat[step_idx, ])
    in_trans <- max(0L, FLEET - docked)
    sprintf("%d (%.1f%%)", in_trans, in_trans / FLEET * 100)
  })

  output$kpi_empty_now <- renderText({
    payload <- day_data()
    step_idx <- max(1L, min(288L, input$time_idx))
    as.character(sum(payload$dock_mat[step_idx, ] == 0L))
  })

  output$kpi_full_now <- renderText({
    payload <- day_data()
    step_idx <- max(1L, min(288L, input$time_idx))
    as.character(sum(payload$dock_mat[step_idx, ] == CAPACITY))
  })

  # ── Single Bike Status UI ────────────────────────────────────────────────
  output$single_bike_status_ui <- renderUI({
    req(input$trail_mode == "single", input$sel_bike)
    bundle <- cur_bundle()
    b_idx  <- as.integer(unname(bundle$bike_map[[input$sel_bike]]))
    if (is.na(b_idx)) return(NULL)

    payload  <- day_data()
    step_idx <- max(1L, min(288L, input$time_idx))

    b_trips <- payload$trips_df %>% filter(b_id == b_idx)
    active_trip <- b_trips %>% filter(start_step < step_idx & end_step > step_idx)
    completed   <- b_trips %>% filter(end_step <= step_idx)

    if (nrow(active_trip) > 0L) {
      d1_name <- bundle$stations$dockID[active_trip$d1[[1L]] + 1L]
      d2_name <- bundle$stations$dockID[active_trip$d2[[1L]] + 1L]
      status_txt <- sprintf("Riding: %s ➔ %s", substr(d1_name, 1, 18), substr(d2_name, 1, 18))
      status_col <- "#00b4d8"
    } else if (nrow(completed) > 0L) {
      last_d <- bundle$stations$dockID[tail(completed$d2, 1) + 1L]
      status_txt <- sprintf("Docked at: %s", substr(last_d, 1, 26))
      status_col <- "#10b981"
    } else {
      first_t <- b_trips %>% head(1)
      first_d <- if (nrow(first_t) > 0L) bundle$stations$dockID[first_t$d1[[1L]] + 1L] else "Station"
      status_txt <- sprintf("Docked at: %s (Morning)", substr(first_d, 1, 22))
      status_col <- "#8b949e"
    }

    div(style = "background:#0d1117; border:1px solid #30363d; border-radius:6px; padding:6px 8px; margin:6px 0; font-size:0.75em;",
      div("Bike ID: ", strong(input$sel_bike, style = "color:#58a6ff")),
      div("Status: ", strong(status_txt, style = paste0("color:", status_col))),
      div("Trips Completed Today: ", strong(nrow(completed), style = "color:#58a6ff")),
      div("Total Trips Scheduled Today: ", strong(nrow(b_trips)))
    )
  })

  # ── Leaflet Map with Synchronized HTML5 Canvas Overlay ────────────────────
  output$map <- renderLeaflet({
    leaflet(options = leafletOptions(zoomControl = TRUE)) %>%
      addTiles(
        urlTemplate = "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
        attribution = "&copy; OpenStreetMap contributors"
      ) %>%
      setView(lng = init_bundle$meta$lon, lat = init_bundle$meta$lat, zoom = init_bundle$meta$zoom) %>%
      onRender("
        function(el, x) {
          var map = this;
          window.fleetMap = map;
          window.currentStep = 100.0;
          window.targetStep = 100.0;
          window.showPastHistory = true;
          window.singleBikeId = -1;
          window.singleDockedStation = -1;
          window.highlightFilter = 'none';

          // Mount canvas inside map container with pointer-events: none for rock-solid map pan/drag
          var container = map.getContainer();
          var canvas = document.createElement('canvas');
          canvas.id = 'fleet_anim_canvas';
          canvas.style.position = 'absolute';
          canvas.style.top = '0';
          canvas.style.left = '0';
          canvas.style.width = '100%';
          canvas.style.height = '100%';
          canvas.style.pointerEvents = 'none';
          canvas.style.zIndex = '450';
          container.appendChild(canvas);
          window.fleetCanvas = canvas;

          function resizeCanvas() {
            var size = map.getSize();
            canvas.width = size.x;
            canvas.height = size.y;
            drawFrame();
          }

          map.on('move', drawFrame);
          map.on('zoom', drawFrame);
          map.on('viewreset', drawFrame);
          map.on('resize', resizeCanvas);

          // Station zone color mapping function
          function getZoneColor(zone) {
            if (!zone) return '#6b7280';
            var z = zone.toLowerCase();
            if (z === 'office') return '#2563eb';      // Blue
            if (z === 'residential') return '#10b981'; // Green
            if (z === 'retail') return '#f59e0b';      // Amber
            return '#6b7280';
          }

          // Safe accessor for station data (supports both array of objects and columnar lists)
          function getStationCount(stations) {
            if (!stations) return 0;
            if (Array.isArray(stations)) return stations.length;
            if (stations.lat && Array.isArray(stations.lat)) return stations.lat.length;
            return 0;
          }

          function getStation(stations, s) {
            if (Array.isArray(stations)) return stations[s];
            return {
              id: stations.id ? stations.id[s] : s,
              dockID: stations.dockID ? stations.dockID[s] : '',
              lat: stations.lat[s],
              lon: stations.lon[s],
              zone: stations.zone ? stations.zone[s] : 'unassigned'
            };
          }

          // Main 60-FPS Canvas draw function (Direct container coordinates)
          function drawFrame() {
            if (!canvas || !window.routesData || !window.tripsData || !window.stationsData) return;
            var ctx = canvas.getContext('2d');
            ctx.clearRect(0, 0, canvas.width, canvas.height);

            var step = window.currentStep;
            var trips = window.tripsData;
            var routes = window.routesData;
            var stations = window.stationsData;
            var dockMat = window.dockMatData;

            var isSingle = (window.singleBikeId !== null && window.singleBikeId !== undefined && window.singleBikeId >= 0);
            var singleB = isSingle ? window.singleBikeId : null;

            var nTrips = trips.n !== undefined ? trips.n : (trips.b_id ? trips.b_id.length : (Array.isArray(trips) ? trips.length : 0));

            // 1. Draw Past Completed Path History (Single Bike Mode ONLY)
            if (isSingle && window.showPastHistory) {
              ctx.strokeStyle = 'rgba(0, 180, 216, 0.75)';
              ctx.lineWidth = 3.0;
              ctx.beginPath();
              for (var i = 0; i < nTrips; i++) {
                var endStep = trips.end_step ? trips.end_step[i] : trips[i].end_step;
                if (endStep <= step) {
                  var bId = trips.b_id ? trips.b_id[i] : trips[i].b_id;
                  if (bId !== singleB) continue;
                  var rIdx = trips.r_idx ? trips.r_idx[i] : trips[i].r_idx;
                  var r = routes[rIdx];
                  if (!r) continue;
                  var p0 = map.latLngToContainerPoint([r.lats[0], r.lons[0]]);
                  ctx.moveTo(p0.x, p0.y);
                  for (var j = 1; j < r.lats.length; j++) {
                    var pj = map.latLngToContainerPoint([r.lats[j], r.lons[j]]);
                    ctx.lineTo(pj.x, pj.y);
                  }
                }
              }
              ctx.stroke();
            }

            // 2. Draw Active Extending Rides along street grid (Turning Corners!)
            ctx.strokeStyle = isSingle ? '#00f0ff' : '#00b4d8';
            ctx.lineWidth = isSingle ? 4.0 : 2.4;
            ctx.beginPath();
            var activeHeads = [];

            for (var i = 0; i < nTrips; i++) {
              var startStep = trips.start_step ? trips.start_step[i] : trips[i].start_step;
              var endStep = trips.end_step ? trips.end_step[i] : trips[i].end_step;
              if (startStep < step && endStep > step) {
                var bId = trips.b_id ? trips.b_id[i] : trips[i].b_id;
                if (singleB !== null && bId !== singleB) continue;
                var rIdx = trips.r_idx ? trips.r_idx[i] : trips[i].r_idx;
                var r = routes[rIdx];
                if (!r) continue;

                var prog = (step - startStep) / (endStep - startStep);
                var p0 = map.latLngToContainerPoint([r.lats[0], r.lons[0]]);
                ctx.moveTo(p0.x, p0.y);

                var headX, headY;
                if (r.n === 2) {
                  var p1 = map.latLngToContainerPoint([r.lats[1], r.lons[1]]);
                  headX = p0.x + prog * (p1.x - p0.x);
                  headY = p0.y + prog * (p1.y - p0.y);
                  ctx.lineTo(headX, headY);
                } else {
                  var corner = map.latLngToContainerPoint([r.lats[1], r.lons[1]]);
                  var pEnd = map.latLngToContainerPoint([r.lats[2], r.lons[2]]);
                  if (prog <= r.w1) {
                    var p1 = prog / r.w1;
                    headX = p0.x + p1 * (corner.x - p0.x);
                    headY = p0.y + p1 * (corner.y - p0.y);
                    ctx.lineTo(headX, headY);
                  } else {
                    ctx.lineTo(corner.x, corner.y);
                    var p2 = (prog - r.w1) / (1.0 - r.w1);
                    headX = corner.x + p2 * (pEnd.x - corner.x);
                    headY = corner.y + p2 * (pEnd.y - corner.y);
                    ctx.lineTo(headX, headY);
                  }
                }
                activeHeads.push({x: headX, y: headY});
              }
            }
            ctx.stroke();

            // 3. Draw Moving Bike Heads (Dark navy blue circle #023e8a with white rim)
            for (var k = 0; k < activeHeads.length; k++) {
              var h = activeHeads[k];
              ctx.beginPath();
              ctx.arc(h.x, h.y, isSingle ? 6.0 : 4.5, 0, 2 * Math.PI);
              ctx.fillStyle = '#023e8a';
              ctx.fill();
              ctx.lineWidth = isSingle ? 2.0 : 1.5;
              ctx.strokeStyle = '#ffffff';
              ctx.stroke();
            }

            // 4. Draw 27 Stations (Fixed uniform radius = 10, colored strictly by zoning)
            var stepIdx = Math.max(0, Math.min(287, Math.round(step) - 1));
            var stepRow = (dockMat && dockMat[stepIdx]) ? dockMat[stepIdx] : [];
            var nStations = getStationCount(stations);

            for (var s = 0; s < nStations; s++) {
              var st = getStation(stations, s);
              var pt = map.latLngToContainerPoint([st.lat, st.lon]);
              var col = getZoneColor(st.zone);
              var bikes = stepRow[s] !== undefined ? stepRow[s] : 15;

              ctx.beginPath();
              ctx.arc(pt.x, pt.y, 10, 0, 2 * Math.PI);
              ctx.fillStyle = col;
              ctx.fill();
              ctx.lineWidth = 2.0;
              ctx.strokeStyle = '#ffffff';
              ctx.stroke();

              // Single bike docked halo
              if (window.singleDockedStation !== null && window.singleDockedStation === s) {
                ctx.beginPath();
                ctx.arc(pt.x, pt.y, 16, 0, 2 * Math.PI);
                ctx.lineWidth = 3.0;
                ctx.strokeStyle = '#00f0ff';
                ctx.stroke();
              }

              // Highlight Empty / Full stations if toggled from KPI cards
              if (window.highlightFilter === 'empty' && bikes === 0) {
                ctx.beginPath();
                ctx.arc(pt.x, pt.y, 17, 0, 2 * Math.PI);
                ctx.lineWidth = 3.5;
                ctx.strokeStyle = '#ff4d4f';
                ctx.stroke();

                ctx.font = 'bold 10px monospace';
                ctx.fillStyle = '#ff4d4f';
                ctx.textAlign = 'center';
                ctx.fillText('EMPTY (0)', pt.x, pt.y - 14);
              } else if (window.highlightFilter === 'full' && bikes === 30) {
                ctx.beginPath();
                ctx.arc(pt.x, pt.y, 17, 0, 2 * Math.PI);
                ctx.lineWidth = 3.5;
                ctx.strokeStyle = '#ffa657';
                ctx.stroke();

                ctx.font = 'bold 10px monospace';
                ctx.fillStyle = '#ffa657';
                ctx.textAlign = 'center';
                ctx.fillText('FULL (30)', pt.x, pt.y - 14);
              }
            }
          }
          window.drawFleetFrame = drawFrame;

          // Continuous smooth 60-FPS animation interpolation loop (No teleporting!)
          function animLoop() {
            var diff = window.targetStep - window.currentStep;
            if (Math.abs(diff) > 0.005) {
              if (Math.abs(diff) > 3.0) {
                window.currentStep = window.targetStep;
              } else {
                window.currentStep += diff * 0.16;
              }
              drawFrame();
            }
            requestAnimationFrame(animLoop);
          }
          requestAnimationFrame(animLoop);

          // Click detection on stations to trigger inspector
          map.on('click', function(e) {
            var cp = e.containerPoint;
            var stations = window.stationsData;
            var nStations = getStationCount(stations);
            for (var i = 0; i < nStations; i++) {
              var st = getStation(stations, i);
              var pt = map.latLngToContainerPoint([st.lat, st.lon]);
              var dist = Math.sqrt((cp.x - pt.x)*(cp.x - pt.x) + (cp.y - pt.y)*(cp.y - pt.y));
              if (dist <= 15) {
                Shiny.setInputValue('sel_station', st.dockID, {priority: 'event'});
                var tabLink = document.querySelector('a[data-value=\"🔍 Station Inspector\"]');
                if (tabLink) tabLink.click();
                break;
              }
            }
          });

          // Pointer cursor on station hover
          map.on('mousemove', function(e) {
            var cp = e.containerPoint;
            var stations = window.stationsData;
            var nStations = getStationCount(stations);
            var isOver = false;
            for (var i = 0; i < nStations; i++) {
              var st = getStation(stations, i);
              var pt = map.latLngToContainerPoint([st.lat, st.lon]);
              var dist = Math.sqrt((cp.x - pt.x)*(cp.x - pt.x) + (cp.y - pt.y)*(cp.y - pt.y));
              if (dist <= 15) { isOver = true; break; }
            }
            map.getContainer().style.cursor = isOver ? 'pointer' : '';
          });

          setTimeout(resizeCanvas, 150);
        }
      ")
  })

  # ── Push frame updates to client canvas (Synchronous & instant) ───────────
  observe({
    step_val <- max(1L, min(288L, input$time_idx))
    show_past <- isTRUE(input$show_past_trails)
    bundle <- cur_bundle()

    sel_b <- -1L
    docked_s <- -1L

    if (identical(input$trail_mode, "single") && !is.null(input$sel_bike) && nzchar(input$sel_bike)) {
      b_idx <- as.integer(unname(bundle$bike_map[[input$sel_bike]]))
      if (!is.na(b_idx)) {
        sel_b <- b_idx
        payload <- day_data()
        b_trips <- payload$trips_df %>% filter(b_id == b_idx)
        active_trip <- b_trips %>% filter(start_step < step_val & end_step > step_val)
        if (nrow(active_trip) == 0L) {
          completed <- b_trips %>% filter(end_step <= step_val)
          if (nrow(completed) > 0L) {
            docked_s <- as.integer(tail(completed$d2, 1))
          } else if (nrow(b_trips) > 0L) {
            docked_s <- as.integer(b_trips$d1[[1L]])
          }
        }
      }
    }

    session$sendCustomMessage("update_anim_frame", list(
      step             = step_val,
      show_past        = show_past,
      single_bike      = sel_b,
      single_docked    = docked_s,
      highlight_filter = highlight_filter()
    ))
  })

  # ── Station Metrics in Inspector UI ──────────────────────────────────────
  output$station_metrics_ui <- renderUI({
    req(input$sel_station)
    d <- cur_day_date()
    bundle <- cur_bundle()
    st_day <- bundle$daily_dock %>% filter(date == d, DOCID == input$sel_station)
    payload <- day_data()
    s_idx <- bundle$dock_map[input$sel_station] + 1L
    step_idx <- max(1L, min(288L, input$time_idx))
    live_bikes <- payload$dock_mat[step_idx, s_idx]

    if (nrow(st_day) == 0L) return(NULL)

    zone_col <- switch(tolower(st_day$zone[[1L]]),
      "office"      = "#2563eb",
      "residential" = "#10b981",
      "retail"      = "#f59e0b",
      "#8b949e"
    )

    div(style = "background:#0d1117; border:1px solid #30363d; border-radius:6px; padding:7px 10px; margin-bottom:8px; font-size:0.75em;",
      div("Zoning: ", strong(toupper(st_day$zone[[1L]]), style = paste0("color:", zone_col))),
      div("Live Inventory Right Now: ",
          strong(sprintf("%d / 30 bikes (%.0f%%)", live_bikes, live_bikes / CAPACITY * 100),
                 style = if (live_bikes == 0L || live_bikes == 30L) "color:#ff7b72" else "color:#2ecc71")),
      div("Today's Range: ",
          span(sprintf("%d to %d bikes (mean: %.1f)", st_day$min_bikes[[1L]], st_day$max_bikes[[1L]], st_day$mean_bikes[[1L]]))),
      div("Outages Today: ",
          span(sprintf("%d min empty · %d min full", st_day$n_empty[[1L]] * 5, st_day$n_full[[1L]] * 5),
               style = if (st_day$n_empty[[1L]] > 0L || st_day$n_full[[1L]] > 0L) "color:#ff7b72" else "color:#2ecc71"))
    )
  })

  # ── Station 24-Hour Time-Series Plot ─────────────────────────────────────
  output$station_ts_plot <- renderPlot({
    req(input$sel_station)
    d <- cur_day_date()
    t_now <- cur_time_posix()
    bundle <- cur_bundle()

    sub_ts <- bundle$dock_ts %>%
      filter(date == d, DOCID == input$sel_station) %>%
      arrange(time)

    if (nrow(sub_ts) == 0L) {
      plot.new()
      text(0.5, 0.5, "No data for this date", col = "#8b949e")
      return()
    }

    # Left margin 3.8 so 'Number of Bikes' is never clipped
    par(bg = "#0d1117", fg = "#c9d1d9", col.axis = "#8b949e", col.lab = "#c9d1d9", mar = c(2.8, 3.8, 1, 0.8))
    plot(sub_ts$time, sub_ts$bikes, type = "n", ylim = c(0, 32),
         xlab = "", ylab = "Number of Bikes", xaxt = "n", yaxt = "n", cex.lab = 0.82)

    grid(col = "#21262d", lty = "dotted")

    axis.POSIXct(1, at = seq(min(sub_ts$time), max(sub_ts$time), by = "4 hours"),
                 format = "%H:%M", col = "#30363d", col.axis = "#8b949e", cex.axis = 0.78)
    axis(2, at = c(0, 10, 20, 30),
         labels = c("0 (Empty)", "10", "20", "30 (Full)"),
         col = "#30363d", col.axis = "#8b949e", cex.axis = 0.78, las = 1)

    # Safe operating band (6 to 24 bikes)
    rect(min(sub_ts$time), 6, max(sub_ts$time), 24, col = "#2ecc7115", border = NA)

    # Risk limits
    abline(h = c(0, 30), col = "#e74c3c", lty = "dashed", lwd = 1.2)

    # Inventory line
    lines(sub_ts$time, sub_ts$bikes, col = "#00b4d8", lwd = 2.2)

    # Vertical cursor at current time of day
    abline(v = t_now, col = "#ffe600", lwd = 2, lty = "solid")
  })
}

# ── 6. Client-Side Message Handler Script (Injected into HTML) ───────────────
shinyApp(
  ui = tagList(
    ui,
    tags$script(HTML("
      Shiny.addCustomMessageHandler('load_city_network', function(msg) {
        window.stationsData = msg.stations;
        window.routesData = msg.routes;
        if (window.fleetMap && msg.center) {
          window.fleetMap.setView([msg.center.lat, msg.center.lon], msg.center.zoom, {animate: false});
        }
        if (window.drawFleetFrame) window.drawFleetFrame();
      });

      Shiny.addCustomMessageHandler('load_day_data', function(msg) {
        window.tripsData = msg.trips;
        window.dockMatData = msg.dock_mat;
        if (window.drawFleetFrame) window.drawFleetFrame();
      });

      Shiny.addCustomMessageHandler('update_anim_frame', function(msg) {
        window.targetStep = msg.step;
        window.showPastHistory = msg.show_past;
        window.singleBikeId = msg.single_bike;
        window.singleDockedStation = msg.single_docked;
        window.highlightFilter = msg.highlight_filter;
        if (Math.abs(window.targetStep - window.currentStep) > 3.0) {
          window.currentStep = window.targetStep;
        }
        if (window.drawFleetFrame) window.drawFleetFrame();
      });
    "))
  ),
  server = server
)
