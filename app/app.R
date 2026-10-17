# Rush Hour Autopilot - Shiny dashboard (team 2027win)
#
# app.R does the screen and the wiring ONLY:
#   app/qc.R    every statistic (loader, grid, p and I-MR charts, rebalancing plan)
#   app/prep.R  data shaping (dates, counts of attempts, ranking, baseline choice)
#   app/plots.R ggplot drawing
#   app/sim.R   the seeded policy simulation (Improvement tab)
# Started from the demo in demos/shinyapp (one app.R with ui + server + shinyApp()).
#
# Run from the repo root:  Rscript app/testme.R

library(shiny)
library(bslib)
library(ggplot2)
library(leaflet)

source("qc.R", local = TRUE)      # the working directory is the app folder when the app runs
source("prep.R", local = TRUE)
source("plots.R", local = TRUE)
source("sim.R", local = TRUE)     # the policy simulation (H-10); the page only shows its results

# Built-in scenarios (H-02 data): app/data/*.csv.gz in the deployed bundle, ../data/*.csv in a
# clone. With none, fall back to the tiny test fixture, else ask for an upload.
BUILTIN <- builtin_scenarios(".")
DEFAULT_PATH <- if (length(BUILTIN) > 0) unname(BUILTIN[1]) else default_scenario_path(".")
options(shiny.maxRequestSize = 100 * 1024^2)  # 100 MiB uploads (planted_shift.csv is about 47 MB)

# Shared by every session of this R process: a built-in scenario is loaded (and its minute
# grids built) once, not once per visitor. Uploads are never cached.
CACHE <- new.env(parent = emptyenv())
cached <- function(key, value) {
  if (!exists(key, envir = CACHE, inherits = FALSE)) assign(key, value, envir = CACHE)
  get(key, envir = CACHE, inherits = FALSE)
}

# What pauses when a record type cannot be used (see table_block_message in prep.R).
NEEDS_STATUS <- "the map, the minute grid, the station views, the I-MR chart and rebalancing"
NEEDS_ATTEMPTS <- "the failure rates and the p charts"

help_text <- function(...) tags$p(class = "text-muted small", ...)
# A card that keeps its natural height (the page scrolls instead of squeezing cards).
panel_card <- function(...) card(..., fill = FALSE)
alert_box <- function(text, type = "warning") tags$div(class = paste0("alert alert-", type), text)
# The p chart's overdispersion check (computed in qc.R p_dispersion; shown here only).
dispersion_box <- function(d) {
  if (is.na(d$ratio)) return(alert_box(paste("Dispersion check:", d$note), "secondary"))
  p_text <- format_p(d$p_value)
  note <- paste0(toupper(substr(d$note, 1, 1)), substring(d$note, 2))
  alert_box(paste0("Dispersion check on the baseline: X2 = ", sprintf("%.1f", d$chi_sq), " on ", d$df,
                   " df, ratio X2/df = ", sprintf("%.2f", d$ratio), ", chi-square p ",
                   if (startsWith(p_text, "<")) p_text else paste("=", p_text), ". ", note, "."),
            if (isTRUE(d$warning)) "warning" else "info")
}

# ------------------------------------------------------------------ UI
ui <- page_navbar(
  id = "tabs",
  title = "Rush Hour Autopilot",
  fillable = FALSE,
  sidebar = sidebar(
    width = 320,
    tags$b("Data (simulated)"),
    if (length(BUILTIN) > 0) {
      selectInput("scenario", "Built-in scenario (simulated test data)", choices = names(BUILTIN))
    },
    fileInput("upload", "Or upload a scenario CSV (long form, with a `table` column)",
              accept = c(".csv", "text/csv", ".gz")),
    uiOutput("data_info"),
    tags$hr(),
    tags$b("Rush window"),
    selectInput("date", "Date (weekdays in the scenario)", choices = character(0)),
    sliderInput("minute", "Observation minute (minutes after 07:00)", min = 0, max = 179,
                value = 5, step = 1),
    textOutput("clock"),
    tags$hr(),
    tags$b("Parameters"),
    numericInput("stale_limit", "stale_limit, minutes (demo assumption)", 2, min = 0, step = 1),
    numericInput("warn_k", "Early-warning threshold, bikes or docks (ranking only)", 2, min = 1, step = 1),
    sliderInput("target_fill", "Target fill (demo heuristic)", 0.1, 0.9, 0.5, step = 0.05),
    numericInput("van_capacity", "Van capacity, bikes (demo assumption)", 12, min = 1, step = 1),
    numericInput("detour", "Detour factor (demo assumption)", 1.3, min = 1, max = 3, step = 0.1),
    sliderInput("min_coverage", "Minimum coverage for SPC (demo assumption)", 0.5, 1, 0.95, step = 0.01),
    sliderInput("baseline_share", "Baseline share (first part of the weekdays)", 0.1, 1, 0.5, step = 0.05)
  ),

  nav_panel("Overview",
    uiOutput("upload_help"),
    uiOutput("health_banner"),
    help_text("How to read this: the map shows each station's state at the chosen date and minute,",
              " from the minute grid (most recent snapshot at or before that minute, no older than",
              " stale_limit). Grey = unknown/stale data; it is never shown as normal."),
    uiOutput("kpis"),
    layout_columns(
      fill = FALSE,
      col_widths = c(7, 5),
      panel_card(card_header("Station map at the chosen minute"), uiOutput("map_note"),
                 leafletOutput("map", height = 450)),
      panel_card(card_header("Station ranking (whole 07:00-10:00 window of the chosen date)"),
           help_text("Rank 1 = worst: either-unusable minutes + early-warning minutes; ties by station_id."),
           tableOutput("ranking"))
    ),
    panel_card(card_header("Data issues (rows rejected or flagged when the file was loaded)"),
         help_text("Rows per record type: in the file, valid after loading, rejected, and identical copies kept once."),
         tableOutput("health_tbl"),
         help_text("Issues counted by record type and rule:"),
         tableOutput("issue_summary_tbl"),
         textOutput("issue_detail_caption"),
         tableOutput("issues"))
  ),

  nav_panel("Stations",
    selectInput("station", "Station", choices = character(0)),
    panel_card(card_header("Inventory trend"),
         help_text("How to read this: bikes and docks minute by minute; gaps = unknown/stale minutes."),
         plotOutput("trend", height = 350)),
    panel_card(card_header("Unusable and warning minutes per station"),
         help_text("Minutes are counted over KNOWN minutes only; compare stations by coverage-aware",
                   " numbers, not raw totals. Early warning is for ranking and is not a failure."),
         tableOutput("station_tbl")),
    layout_columns(
      fill = FALSE,
      col_widths = c(6, 6),
      panel_card(card_header("Heatmap: either-unusable minutes by hour and station"),
           help_text("How to read this: darker = more unusable minutes in that hour."),
           plotOutput("heatmap", height = 400)),
      panel_card(card_header("Pareto of either-unusable minutes"),
           help_text("How to read this: bars = minutes per station, largest first; red line = cumulative share."),
           plotOutput("pareto", height = 400))
    )
  ),

  nav_panel("Quality",
    uiOutput("baseline_info"),
    panel_card(card_header("p chart: rent failure proportion"),
         help_text("How to read this: each point is one weekday rush window (% of rent attempts that failed);",
                   " red points are beyond the 3-sigma limits from the baseline (dashed) or in a run of 8.",
                   " The box below checks whether the binomial model behind the limits fits the baseline."),
         uiOutput("p_rent_note"), plotOutput("p_rent_plot", height = 350), tableOutput("p_rent_tbl")),
    panel_card(card_header("p chart: return failure proportion"),
         help_text("How to read this: same as above for return attempts."),
         uiOutput("p_return_note"), plotOutput("p_return_plot", height = 350), tableOutput("p_return_tbl")),
    panel_card(card_header("I-MR chart: either-unusable share of known station-minutes (fixed station set)"),
         help_text("How to read this: one point per included weekday window; top = the share, bottom = the",
                   " change from the previous window. Windows below the minimum coverage are left out."),
         uiOutput("imr_note"), plotOutput("imr_i_plot", height = 350), plotOutput("imr_mr_plot", height = 300),
         tableOutput("imr_tbl")),
    panel_card(card_header("Windows excluded from the I-MR chart"), tableOutput("excluded_tbl"))
  ),

  nav_panel("Rebalancing",
    help_text("Greedy heuristic, not an optimum: the worst-ranked deficit station gets one move from the",
              " nearest station with a surplus. Distances are estimated (straight line x detour factor),",
              " not a road route. State = the chosen date and minute."),
    textOutput("plan_title"),
    panel_card(card_header("Recommended moves"), tableOutput("moves_tbl")),
    layout_columns(
      fill = FALSE,
      col_widths = c(6, 6),
      panel_card(card_header("Stations left out of moves (closed or no valid data)"), tableOutput("excluded_plan_tbl")),
      panel_card(card_header("Unmet deficits after the moves"), tableOutput("unmet_tbl"))
    )
  ),

  nav_panel("Improvement",
    panel_card(card_header("What this tab does, and what it assumes"),
      help_text("Question: with the SAME simulated riders, are fewer station-minutes unusable when vans",
                " rebalance (reactive policy) than when they do not (no rebalancing)? The tool does not",
                " assume the reactive policy wins. Everything below is simulated, not a forecast of a real day."),
      tags$ul(class = "text-muted small",
        tags$li("Demand (from the data): Poisson arrivals per station and 15-minute bin, rate = attempts",
                " (successful + failed) / known station-minutes over the weekdays STRICTLY BEFORE the chosen",
                " date (no look-ahead). A rate of 0 is valid. A bin with no known minute uses the station's",
                " pooled rate (demo assumption); riders who gave up without trying are not observed."),
        tags$li("Paired seeds: each seed makes ONE stream of rider events; both policies get exactly that",
                " stream, so the policy never changes demand, only whether a rent or return succeeds."),
        tags$li("Start: the chosen date's 07:00 state (from the minute grid, so stale_limit applies). Stations",
                " with an unknown 07:00 state are left out and listed below. Station open/closed flags stay as",
                " at 07:00 (demo assumption); a closed station is maintenance, never a move."),
        tags$li("Bikes are conserved: stations + vans + bikes on rides is the same at every event. Bikes on rides",
                " start as the number of returns in the stream; a failed return leaves the bike on the ride."),
        tags$li("Vans (demo assumptions): the number of distinct van_id in the file's tasks (else 2), starting at",
                " the network centroid; travel = straight line x detour factor / speed; handling = stop time +",
                " time per bike at each pickup and drop-off. At pickup a van takes min(planned, bikes there",
                " then, free room); at drop-off it leaves min(load, free docks then); the rest stays on the van."),
        tags$li("Reactive policy: at the start of each minute an idle van gets the first move of the greedy",
                " rebalancing plan (the plan from the Rebalancing tab, on the simulated state) that touches a",
                " rent-unusable, return-unusable or early-warning station. One task per van; stations of an",
                " active task are reserved. Target fill, van capacity and detour come from the sidebar."),
        tags$li("Difference d = metric(no rebalancing) - metric(reactive), per seed. Primary metric: either-unusable",
                " station-minutes in 07:00-10:00, paired t interval with a Bonferroni family of 3 (98.333%, this",
                " anticipates the three-policy comparison). The other metrics are exploratory, unadjusted 95%,",
                " not adjusted for multiple comparisons; there is no overall 95% confidence across metrics."),
        tags$li("Recovery time: only failure onsets that recover before 10:00 are averaged, and only seeds with at",
                " least one are counted; the table shows how many.")
      )),
    panel_card(card_header("Run"),
      layout_columns(
        fill = FALSE, col_widths = c(3, 3, 3, 3),
        numericInput("sim_seeds", "Seeds R (paired)", 30, min = 1, max = 200, step = 1),
        numericInput("sim_base_seed", "Base seed (seed s = base + s - 1)", 1, step = 1),
        numericInput("sim_vans", "Number of vans (demo assumption)", 2, min = 1, max = 20, step = 1),
        numericInput("sim_speed", "Van speed, km/h (demo assumption)", 20, min = 1, step = 1)),
      layout_columns(
        fill = FALSE, col_widths = c(3, 3, 6),
        numericInput("sim_stop", "Stop time per pickup / drop-off, min (demo assumption)", 2, min = 0, step = 0.5),
        numericInput("sim_perbike", "Handling time per bike, min (demo assumption)", 0.1, min = 0, step = 0.05),
        tags$div(
          help_text("Also used from the sidebar: date, stale_limit, target fill, van capacity, detour factor."),
          actionButton("run_sim", "Run comparison", class = "btn-primary"))),
      help_text("The simulation runs only when you click. 30 seeds take several seconds.")),
    uiOutput("sim_head"),
    panel_card(card_header("Per-policy means over the seeds"), tableOutput("sim_summary_tbl")),
    panel_card(card_header("Paired differences (no rebalancing minus reactive)"),
      help_text("How to read this: positive = the reactive policy is better (fewer minutes, fewer failures, faster",
                " recovery). Van distance is negative because only the reactive policy drives. An interval that",
                " contains 0 does not show a difference. CI_level shows the level of each row."),
      tableOutput("sim_paired_tbl")),
    panel_card(card_header("Primary metric: per-seed differences"),
      plotOutput("sim_plot", height = 350)),
    layout_columns(
      fill = FALSE, col_widths = c(6, 6),
      panel_card(card_header("Stations left out of the simulation"), tableOutput("sim_excluded_tbl")),
      panel_card(card_header("Demand-rate source days (weekdays before the chosen date)"), textOutput("sim_days")))
  )
)

# ------------------------------------------------------------------ server
server <- function(input, output, session) {

  # ---- data source: the latest choice wins (an upload, or a built-in scenario picked after it);
  # with neither, the default file; with no default file, an upload panel.
  use_upload <- reactiveVal(FALSE)
  observeEvent(input$upload, use_upload(TRUE))
  observeEvent(input$scenario, use_upload(FALSE), ignoreInit = TRUE)
  scn <- reactive({
    upload <- use_upload() && !is.null(input$upload)
    path <- if (upload) input$upload$datapath else if (!is.null(input$scenario) &&
                                                       input$scenario %in% names(BUILTIN)) {
      unname(BUILTIN[input$scenario])
    } else DEFAULT_PATH
    label <- if (upload) input$upload$name else if (is.na(path)) NA else basename(path)
    if (is.na(path)) {
      return(list(ok = FALSE, label = NA, message = paste(
        "No scenario file found. Upload a long-form scenario CSV with a `table` column",
        "(record types: stations, status, attempts, tasks; schema in docs/methods.md section 7).")))
    }
    key <- if (upload) NULL else normalizePath(path, winslash = "/")
    tryCatch(list(ok = TRUE, label = label, key = key, fixture = !upload && grepl("fixtures", path),
                  data = if (is.null(key)) load_scenario(path) else cached(paste("scenario", key), load_scenario(path))),
             error = function(e) list(ok = FALSE, label = label, message = conditionMessage(e)))
  })

  # the loaded data, or a message shown in place of every output
  sc <- reactive({
    s <- scn()
    validate(need(isTRUE(s$ok), if (isTRUE(s$ok)) "" else s$message))
    s$data
  })
  # Rows per record type. Stations are required for everything; status and attempts each
  # pause only the features that need them; tasks are not used yet.
  health <- reactive(table_health(sc()))
  stations_ok <- reactive({
    msg <- table_block_message(health(), sc()$issues, "stations", "no part of the scenario")
    validate(need(is.null(msg), msg))
    TRUE
  })
  status_msg <- reactive(table_block_message(health(), sc()$issues, "status", NEEDS_STATUS))
  attempts_msg <- reactive(table_block_message(health(), sc()$issues, "attempts", NEEDS_ATTEMPTS))

  dates <- reactive({
    stations_ok()
    d <- scenario_dates(sc()$status, sc()$attempts)
    validate(need(length(d) > 0, paste(c("The scenario has no weekday status or attempt rows.",
                                         status_msg(), attempts_msg()), collapse = " ")))
    d
  })

  # A new file first clears the date list, so dates of the previous file never linger.
  observeEvent(sc(), updateSelectInput(session, "date", choices = character(0)), priority = 10)

  observeEvent(dates(), {
    updateSelectInput(session, "date", choices = dates(), selected = dates()[1])
  })
  observeEvent(sc(), {
    ids <- sc()$stations$station_id
    names(ids) <- paste(ids, "-", sc()$stations$station_name)
    updateSelectInput(session, "station", choices = ids)
  })

  stale_limit <- reactive({ req(input$stale_limit >= 0); input$stale_limit })
  grids <- reactive({
    validate(need(is.null(status_msg()), status_msg()))
    key <- scn()$key
    if (is.null(key)) return(build_day_grids(sc()$status, sc()$stations, dates(), stale_limit()))
    cached(paste("grids", key, stale_limit()), build_day_grids(sc()$status, sc()$stations, dates(), stale_limit()))
  })
  grid <- reactive({           # the chosen day, with the chosen early-warning threshold
    req(input$date, input$date %in% names(grids()), input$warn_k)
    set_warning_threshold(grids()[[input$date]], input$warn_k)
  })
  summ <- reactive(rank_stations(unusable_summary(grid())))
  att_all <- reactive({
    validate(need(is.null(attempts_msg()), attempts_msg()))
    attempts_by_day(sc()$attempts, dates())
  })
  state <- reactive({
    req(input$minute)
    state_at(grid(), input$minute)
  })
  fixed_ids <- reactive(fixed_station_set(sc()$status, sc()$stations, dates()))
  windows <- reactive({
    window_table(grids(), fixed_ids(), dates(), input$min_coverage)
  })

  # ---- sidebar
  output$data_info <- renderUI({
    s <- scn()
    if (isTRUE(s$ok)) {
      n <- sc()
      tagList(help_text("Source: ", s$label, ". All data in this version are simulated."),
              help_text(nrow(n$stations), " stations, ", nrow(n$status), " status rows, ",
                        nrow(n$attempts), " attempts, ", nrow(n$tasks), " tasks after validation."))
    } else if (!is.na(s$label)) {
      alert_box(s$message, "danger")
    }
  })
  output$clock <- renderText({
    m <- input$minute
    if (is.null(m)) return("")
    sprintf("Observation time: %02d:%02d (New York). Window 07:00-10:00.", 7 + m %/% 60, m %% 60)
  })

  # ---- Overview
  output$upload_help <- renderUI({
    s <- scn()
    if (isTRUE(s$ok)) {
      if (isTRUE(s$fixture)) {
        alert_box(paste("Showing the tiny test fixture (edge_small.csv) because data/baseline.csv was not",
                        "found. Most minutes are unknown there on purpose. Simulated data."), "info")
      }
    } else {
      panel_card(card_header("Provide a scenario file"),
           tags$p(s$message),
           tags$p("Use the upload box in the sidebar. The file must be UTF-8 CSV with a header row and a",
                  tags$code("table"), "column whose values are", tags$code("stations"), ",",
                  tags$code("status"), ",", tags$code("attempts"), ",", tags$code("tasks"),
                  ". Example: data/baseline.csv in the project repository (simulated)."))
    }
  })

  output$kpis <- renderUI({
    req(input$date)
    # Each half pauses on its own: status feeds the minute boxes, attempts the failure boxes.
    s_ok <- is.null(status_msg())
    a_ok <- is.null(attempts_msg())
    counts <- if (s_ok) grid_window_counts(grid(), NULL, input$date) else
      data.frame(known = 0, unknown = 0, either_min = 0)
    att <- if (a_ok) att_all()[att_all()$date == input$date, ] else
      data.frame(rent_n = 0, rent_fail = 0, return_n = 0, return_fail = 0)
    k <- kpi_summary(counts, att)
    pct <- function(x) if (is.na(x)) "n/a" else sprintf("%.1f%%", x)
    box <- function(title, value, detail) value_box(title, value, tags$small(detail))
    paused <- function(title, what) box(title, "paused", paste("no valid", what, "records"))
    layout_column_wrap(
      width = 1 / 3, fill = FALSE,
      if (s_ok) box("Either-unusable share", pct(k$either_share_pct),
                    paste0(counts$either_min, " of ", k$known, " known station-minutes"))
      else paused("Either-unusable share", "status"),
      if (a_ok) box("Rent failure", pct(k$rent_fail_pct), paste0(k$rent_fail, "/", k$rent_n, " rent attempts"))
      else paused("Rent failure", "attempts"),
      if (a_ok) box("Return failure", pct(k$return_fail_pct), paste0(k$return_fail, "/", k$return_n, " return attempts"))
      else paused("Return failure", "attempts"),
      if (s_ok) box("Known minutes", format(k$known), "station-minutes with a valid recent snapshot")
      else paused("Known minutes", "status"),
      if (s_ok) box("Unknown minutes", format(k$unknown), "left out of every rate; never counted as usable")
      else paused("Unknown minutes", "status"),
      if (s_ok) box("Coverage", pct(100 * k$coverage), "known / (known + unknown)")
      else paused("Coverage", "status")
    )
  })

  output$health_banner <- renderUI({
    req(isTRUE(scn()$ok))
    h <- health()
    msgs <- c(table_block_message(h, sc()$issues, "stations", "no part of the scenario"),
              status_msg(), attempts_msg())
    partial <- h[h$state == "some rejected", ]
    tagList(
      lapply(msgs, function(m) alert_box(m, "danger")),
      if (nrow(partial) > 0) {
        alert_box(paste0("Some rows were rejected and left out: ",
                         paste0(partial$rejected, " of ", partial$in_file, " ", partial$table, collapse = "; "),
                         ". The rest of the file is used. See Data issues."), "warning")
      }
    )
  })

  # The map widget is built ONCE (tiles + legend) and never rebuilt; markers and the view are
  # updated through leafletProxy. Rebuilding the whole widget on every minute/date/file change
  # while the Overview tab was hidden left a stale resize handler on a removed map
  # ("Cannot read properties of undefined (reading '_leaflet_pos')").
  output$map <- renderLeaflet({
    leaflet() |>
      addTiles() |>
      setView(lng = -76.5, lat = 42.44, zoom = 13) |>
      addLegend("bottomright", colors = unname(STATE_COLOURS[STATE_LEVELS]), labels = STATE_LEVELS,
                title = "Station state", opacity = 1)
  })
  map_ready <- reactiveVal(FALSE)          # TRUE once the browser has drawn the map
  observeEvent(input$map_zoom, map_ready(TRUE), once = TRUE)

  # Fit the view to the stations of each new file, once, and only while the Overview tab is
  # shown: a hidden map has zero size, so fitting it then would zoom out to the whole world.
  # Not on every minute or tab change, so a user's own zoom stays.
  fit_pending <- reactiveVal(FALSE)
  observeEvent(sc(), fit_pending(TRUE))
  observeEvent(list(fit_pending(), map_ready(), input$tabs), {
    req(fit_pending(), map_ready(), identical(input$tabs, "Overview"))
    stn <- sc()$stations
    req(nrow(stn) > 0)
    pad <- 0.005
    leafletProxy("map") |>
      fitBounds(min(stn$longitude) - pad, min(stn$latitude) - pad,
                max(stn$longitude) + pad, max(stn$latitude) + pad)
    fit_pending(FALSE)
  })

  # Station markers for the chosen date and minute. Old markers are cleared first, so a file
  # without valid status rows never keeps the previous file's stations on the map.
  observe({
    req(map_ready())
    proxy <- leafletProxy("map") |> clearMarkers()
    req(isTRUE(scn()$ok), is.null(status_msg()))
    st <- state()
    stn <- sc()$stations
    m <- stn[match(st$station_id, stn$station_id), ]
    m$state <- factor(st$state, levels = STATE_LEVELS)
    pal <- colorFactor(unname(STATE_COLOURS[STATE_LEVELS]), domain = factor(STATE_LEVELS, levels = STATE_LEVELS))
    popup <- station_popup(m$station_name, m$station_id, as.character(m$state),
                           st$bikes_available, st$docks_available)
    proxy |>
      addCircleMarkers(data = m, lng = ~longitude, lat = ~latitude, radius = 9, color = "black", weight = 1,
                       fillColor = ~pal(state), fillOpacity = 0.9, popup = popup)
  })
  output$map_note <- renderUI({
    req(isTRUE(scn()$ok))
    if (!is.null(status_msg())) alert_box(status_msg(), "danger")
  })

  output$ranking <- renderTable({
    r <- station_table(summ(), sc()$stations)
    r$rank <- seq_len(nrow(r))
    r[, c("rank", "station_id", "station", "either_unusable_min", "warning_min", "known_min", "coverage_pct")]
  }, digits = 1)

  output$health_tbl <- renderTable(health())
  output$issue_summary_tbl <- renderTable({
    s <- issue_summary(sc()$issues)
    if (nrow(s) == 0) data.frame(note = "No data issues found.") else s
  })
  output$issue_detail_caption <- renderText({
    n <- nrow(sc()$issues)
    if (n == 0) "" else sprintf("Issue rows: showing the first %d of %d.", min(n, 200), n)
  })
  output$issues <- renderTable({
    iss <- sc()$issues
    if (nrow(iss) == 0) NULL else issue_detail(iss, 200)
  })

  # ---- Stations
  output$trend <- renderPlot({
    req(input$station)
    g <- grid()[grid()$station_id == input$station, ]
    nm <- sc()$stations$station_name[sc()$stations$station_id == input$station]
    plot_trend(g, paste0(input$station, " ", nm, ", ", input$date,
                         " (", sum(g$known), " known, ", sum(!g$known), " unknown minutes)"))
  })
  output$station_tbl <- renderTable(station_table(summ(), sc()$stations), digits = 1)
  output$heatmap <- renderPlot(plot_heatmap(hour_station_matrix(grid())))
  output$pareto <- renderPlot({
    p <- pareto_order(summ())
    validate(need(nrow(p) > 0, "No stations."),
             need(sum(p$either_unusable_min) > 0, "No unusable minutes in the known data for this date."))
    plot_pareto(p)
  })

  # ---- Quality
  output$baseline_info <- renderUI({
    d <- dates()
    p_part <- if (is.null(attempts_msg())) {
      n_p <- sum(att_all()$rent_n > 0)
      paste0("p charts: first ", baseline_count(n_p, input$baseline_share), " of ", n_p, " weekdays with attempts. ")
    } else "p charts: paused (no valid attempts records). "
    i_part <- if (is.null(status_msg())) {
      inc <- windows()$included
      paste0("I-MR: first ", baseline_count(sum(inc), input$baseline_share), " of ", sum(inc), " included windows. ")
    } else "I-MR: paused (no valid status records). "
    alert_box(paste0("Baseline (limits are estimated from these only): the first ", input$baseline_share * 100,
                     "% of weekdays, at least 1. ", p_part, i_part, length(d), " weekdays in the scenario."), "info")
  })

  p_panel <- function(kind) {
    n_col <- paste0(kind, "_n")
    fail_col <- paste0(kind, "_fail")
    res <- reactive({
      a <- att_all()
      p_chart(a[[fail_col]], a[[n_col]], baseline = baseline_flags(a[[n_col]] > 0, input$baseline_share))
    })
    out <- list()
    out$note <- renderUI({
      r <- res()
      tagList(
        if (nzchar(r$note)) alert_box(paste("Control limits not drawn or limited:", r$note), "warning"),
        dispersion_box(r$dispersion)
      )
    })
    out$plot <- renderPlot({
      validate(need(any(!is.na(res()$data$p)), paste("No", kind, "attempts in the weekday windows: nothing to plot.")))
      plot_p(res(), att_all()$date, paste0(kind, " failure (%)"), paste("p chart:", kind, "failures"),
             ooc_label = signal_label(TRUE, res()$dispersion$warning),
             ok_label = signal_label(FALSE, res()$dispersion$warning))
    })
    out$tbl <- renderTable({
      d <- res()$data
      data.frame(date = att_all()$date, failures_over_n = paste0(d$failures, "/", d$n),
                 percent = round(100 * d$p, 2), center_pct = round(100 * d$center, 2),
                 UCL_pct = round(100 * d$ucl, 2), LCL_pct = round(100 * d$lcl, 2),
                 signal = signal_label(d$out_of_control, res()$dispersion$warning))
    }, na = "n/a")
    out
  }
  rent <- p_panel("rent")
  ret <- p_panel("return")
  output$p_rent_note <- rent$note;   output$p_rent_plot <- rent$plot;   output$p_rent_tbl <- rent$tbl
  output$p_return_note <- ret$note;  output$p_return_plot <- ret$plot;  output$p_return_tbl <- ret$tbl

  imr <- reactive({
    w <- windows()
    inc <- w[w$included, ]
    validate(need(nrow(inc) > 0, "No window has enough coverage for the I-MR chart (see the excluded list below)."))
    list(windows = inc,
         res = imr_chart(inc$either_share_pct, baseline = baseline_flags(rep(TRUE, nrow(inc)), input$baseline_share)))
  })
  output$imr_note <- renderUI({
    if (!any(windows()$included)) return(NULL)   # the plots below say why nothing is drawn
    r <- imr()$res
    if (nzchar(r$note)) alert_box(paste("Control limits not drawn:", r$note), "warning")
  })
  output$imr_i_plot <- renderPlot({
    plot_i(imr()$res, imr()$windows$window, "either-unusable share (% of known station-minutes)", "Individuals (I) chart")
  })
  output$imr_mr_plot <- renderPlot(plot_mr(imr()$res, imr()$windows$window, "Moving range (MR) chart"))
  output$imr_tbl <- renderTable({
    i <- imr()
    d <- i$res$data
    data.frame(date = i$windows$window, share_pct = round(d$x, 2), either_min = i$windows$either_min,
               known_min = i$windows$known, coverage_pct = round(100 * i$windows$coverage, 1),
               center = round(d$center, 2), UCL = round(d$ucl, 2), LCL = round(d$lcl, 2),
               moving_range = round(d$mr, 2),
               signal = ifelse(is.na(d$out_of_control), "not assessed",
                               ifelse(d$out_of_control, "OUT OF CONTROL", "in control")))
  }, na = "n/a")
  output$excluded_tbl <- renderTable({
    w <- windows()
    ex <- w[!w$included, ]
    if (nrow(ex) == 0) return(data.frame(note = "No window is excluded."))
    data.frame(date = ex$window, known_min = ex$known, unknown_min = ex$unknown,
               coverage_pct = round(100 * ex$coverage, 1), reason = ex$reason)
  }, na = "n/a")

  # ---- Rebalancing
  plan <- reactive({
    r <- summ()[, c("station_id", "rank")]
    rebalance_plan(state(), sc()$stations, rank = r, target_fill = input$target_fill,
                   van_capacity = input$van_capacity, detour = input$detour)
  })
  output$plan_title <- renderText({
    m <- input$minute
    sprintf("Plan for %s at %02d:%02d (greedy heuristic, not an optimum). Stations with stale data are left out.",
            input$date, 7 + m %/% 60, m %% 60)
  })
  output$moves_tbl <- renderTable({
    mv <- plan()$moves
    if (nrow(mv) == 0) return(data.frame(note = "No move is recommended at this minute."))
    data.frame(from = mv$from_station, to = mv$to_station, bikes = as.integer(round(mv$quantity)),
               `estimated_distance_km (estimated, not a road route)` = mv$est_distance_km,
               check.names = FALSE)
  })
  output$excluded_plan_tbl <- renderTable({
    ex <- plan()$excluded
    if (nrow(ex) == 0) return(data.frame(note = "None."))
    ex <- explain_exclusion(ex, sc()$status, state()$minute[1], input$stale_limit, sc()$issues)
    data.frame(station_id = ex$station_id, reason = ex$detail,
               recommendation = ex$recommendation)
  })
  output$unmet_tbl <- renderTable({
    u <- plan()$unmet
    if (nrow(u) == 0) data.frame(note = "None.") else as_whole_numbers(u, "remaining_deficit")
  })

  # ---- Improvement (the simulation is in sim.R; this only wires inputs and shows results)
  # A new file resets the number of vans to the distinct van_id in its tasks (else 2).
  observeEvent(sc(), updateNumericInput(session, "sim_vans", value = default_van_count(sc()$tasks)))

  # Runs only on the button. A paused data type shows its message instead of running.
  sim_res <- eventReactive(input$run_sim, {
    validate(need(is.null(status_msg()), status_msg()), need(is.null(attempts_msg()), attempts_msg()))
    req(input$date, input$date %in% names(grids()))
    params <- tryCatch(
      sim_params(vans = input$sim_vans, van_capacity = input$van_capacity, target_fill = input$target_fill,
                 detour = input$detour, speed_kmh = input$sim_speed, stop_min = input$sim_stop,
                 per_bike_min = input$sim_perbike),
      error = function(e) conditionMessage(e))
    validate(need(is.list(params), params),
             need(isTRUE(input$sim_seeds >= 1), "Seeds R must be at least 1."),
             need(!is.na(input$sim_base_seed), "Base seed must be a number."))
    withProgress(message = "Running the paired simulation", value = 0, {
      compare_policies(sc(), grids(), input$date, dates(), n_seeds = input$sim_seeds,
                       base_seed = input$sim_base_seed, params = params,
                       on_progress = function(i, n) incProgress(1 / n, detail = paste("seed", i, "of", n)))
    })
  })

  output$sim_head <- renderUI({
    r <- sim_res()
    if (!r$ok) return(alert_box(paste0("No comparison: ", r$reason, "."), "warning"))
    p <- r$params
    alert_box(paste0("Result for ", r$date, ": ", length(r$seeds), " paired seeds (", min(r$seeds), " to ",
                     max(r$seeds), "), ", length(r$stations), " stations, ", p$vans, " van(s), demand from ",
                     length(r$demand_days), " earlier weekday(s) (", r$demand_attempts, " attempts). Simulated; ",
                     "inputs changed since the click are not reflected until you run again."), "info")
  })
  output$sim_summary_tbl <- renderTable({
    r <- sim_res()
    validate(need(r$ok, r$reason))
    policy_summary_display(r$summary)
  }, na = "n/a")
  output$sim_paired_tbl <- renderTable({
    r <- sim_res()
    paired_table_display(r$paired)
  }, na = "n/a")
  output$sim_plot <- renderPlot({
    r <- sim_res()
    validate(need(r$ok, r$reason))
    row <- r$paired[r$paired$metric == "either_min", ]
    ci_text <- if (is.na(row$ci_low)) paste("No interval:", row$note) else
      sprintf("green line = mean difference; dashed = %.3f%% CI (Bonferroni family of 3); n = %d seeds",
              row$ci_level_pct, row$n)
    plot_paired_diff(r$diffs$either_min, r$seeds, row$mean_d, row$ci_low, row$ci_high, ci_text,
                     "unusable station-minutes saved (none - reactive)",
                     "Per-seed difference in either-unusable station-minutes")
  })
  output$sim_excluded_tbl <- renderTable({
    r <- sim_res()
    if (is.null(r$excluded) || nrow(r$excluded) == 0) return(data.frame(note = "None."))
    r$excluded
  })
  output$sim_days <- renderText({
    r <- sim_res()
    if (length(r$demand_days) == 0) return("none: no earlier weekday")
    paste0(length(r$demand_days), " weekday(s): ", paste(r$demand_days, collapse = ", "))
  })
}

shinyApp(ui = ui, server = server)
