# Rush Hour Autopilot - Shiny dashboard (team 2027win)
#
# app.R does the screen and the wiring ONLY:
#   app/qc.R    every statistic (loader, grid, p and I-MR charts, rebalancing plan)
#   app/prep.R  data shaping (dates, counts of attempts, ranking, baseline choice)
#   app/plots.R ggplot drawing
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

DEFAULT_PATH <- default_scenario_path(".")   # NA when no default file ships with the app

help_text <- function(...) tags$p(class = "text-muted small", ...)
# A card that keeps its natural height (the page scrolls instead of squeezing cards).
panel_card <- function(...) card(..., fill = FALSE)
alert_box <- function(text, type = "warning") tags$div(class = paste0("alert alert-", type), text)

# ------------------------------------------------------------------ UI
ui <- page_navbar(
  title = "Rush Hour Autopilot",
  fillable = FALSE,
  sidebar = sidebar(
    width = 320,
    tags$b("Data (simulated)"),
    fileInput("upload", "Upload a scenario CSV (long form, with a `table` column)",
              accept = c(".csv", "text/csv")),
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
    help_text("How to read this: the map shows each station's state at the chosen date and minute,",
              " from the minute grid (most recent snapshot at or before that minute, no older than",
              " stale_limit). Grey = unknown/stale data; it is never shown as normal."),
    uiOutput("kpis"),
    layout_columns(
      fill = FALSE,
      col_widths = c(7, 5),
      panel_card(card_header("Station map at the chosen minute"), leafletOutput("map", height = 450)),
      panel_card(card_header("Station ranking (whole 07:00-10:00 window of the chosen date)"),
           help_text("Rank 1 = worst: either-unusable minutes + early-warning minutes; ties by station_id."),
           tableOutput("ranking"))
    ),
    panel_card(card_header("Data issues (rows rejected or flagged when the file was loaded)"),
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
                   " red points signal; dashed lines are the 3-sigma limits from the baseline."),
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
  )
)

# ------------------------------------------------------------------ server
server <- function(input, output, session) {

  # ---- data source: upload, else default file, else an upload panel
  scn <- reactive({
    path <- if (!is.null(input$upload)) input$upload$datapath else DEFAULT_PATH
    label <- if (!is.null(input$upload)) input$upload$name else if (is.na(path)) NA else basename(path)
    if (is.na(path)) {
      return(list(ok = FALSE, label = NA, message = paste(
        "No scenario file found. Upload a long-form scenario CSV with a `table` column",
        "(record types: stations, status, attempts, tasks; schema in docs/methods.md section 7).")))
    }
    tryCatch(list(ok = TRUE, label = label, data = load_scenario(path)),
             error = function(e) list(ok = FALSE, label = label, message = conditionMessage(e)))
  })

  # the loaded data, or a message shown in place of every output
  sc <- reactive({
    s <- scn()
    validate(need(isTRUE(s$ok), if (isTRUE(s$ok)) "" else s$message))
    s$data
  })

  dates <- reactive({
    d <- scenario_dates(sc()$status, sc()$attempts)
    validate(need(length(d) > 0, "The scenario has no weekday status or attempt rows."))
    d
  })

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
    build_day_grids(sc()$status, sc()$stations, dates(), stale_limit())
  })
  grid <- reactive({           # the chosen day, with the chosen early-warning threshold
    req(input$date, input$date %in% names(grids()), input$warn_k)
    set_warning_threshold(grids()[[input$date]], input$warn_k)
  })
  summ <- reactive(rank_stations(unusable_summary(grid())))
  att_all <- reactive(attempts_by_day(sc()$attempts, dates()))
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
      if (!is.na(DEFAULT_PATH) && is.null(input$upload) && grepl("fixtures", DEFAULT_PATH)) {
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
    counts <- grid_window_counts(grid(), NULL, input$date)
    att <- att_all()[att_all()$date == input$date, ]
    k <- kpi_summary(counts, att)
    pct <- function(x) if (is.na(x)) "n/a" else sprintf("%.1f%%", x)
    box <- function(title, value, detail) value_box(title, value, tags$small(detail))
    layout_column_wrap(
      width = 1 / 3, fill = FALSE,
      box("Either-unusable share", pct(k$either_share_pct),
          paste0(counts$either_min, " of ", k$known, " known station-minutes")),
      box("Rent failure", pct(k$rent_fail_pct), paste0(k$rent_fail, "/", k$rent_n, " rent attempts")),
      box("Return failure", pct(k$return_fail_pct), paste0(k$return_fail, "/", k$return_n, " return attempts")),
      box("Known minutes", format(k$known), "station-minutes with a valid recent snapshot"),
      box("Unknown minutes", format(k$unknown), "left out of every rate; never counted as usable"),
      box("Coverage", pct(100 * k$coverage), "known / (known + unknown)")
    )
  })

  output$map <- renderLeaflet({
    st <- state()
    stn <- sc()$stations
    m <- stn[match(st$station_id, stn$station_id), ]
    m$state <- factor(st$state, levels = STATE_LEVELS)
    pal <- colorFactor(unname(STATE_COLOURS[STATE_LEVELS]), domain = factor(STATE_LEVELS, levels = STATE_LEVELS))
    popup <- paste0("<b>", m$station_name, "</b> (", m$station_id, ")<br>state: ", m$state,
                    "<br>bikes: ", st$bikes_available, ", docks: ", st$docks_available)
    leaflet(m) |>
      addTiles() |>
      addCircleMarkers(lng = ~longitude, lat = ~latitude, radius = 9, color = "black", weight = 1,
                       fillColor = ~pal(state), fillOpacity = 0.9, popup = popup) |>
      addLegend("bottomright", colors = unname(STATE_COLOURS[STATE_LEVELS]), labels = STATE_LEVELS,
                title = "Station state", opacity = 1)
  })

  output$ranking <- renderTable({
    r <- station_table(summ(), sc()$stations)
    r$rank <- seq_len(nrow(r))
    r[, c("rank", "station_id", "station", "either_unusable_min", "warning_min", "known_min", "coverage_pct")]
  }, digits = 1)

  output$issues <- renderTable({
    iss <- sc()$issues
    if (nrow(iss) == 0) data.frame(note = "No data issues found.") else iss
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
    w <- windows()
    inc <- w$included
    k_p <- baseline_count(sum(att_all()$rent_n > 0), input$baseline_share)
    k_i <- baseline_count(sum(inc), input$baseline_share)
    tagList(
      alert_box(paste0("Baseline (limits are estimated from these only): the first ", input$baseline_share * 100,
                       "% of weekdays, at least 1. p charts: first ", k_p, " of ", sum(att_all()$rent_n > 0),
                       " weekdays with attempts. I-MR: first ", k_i, " of ", sum(inc),
                       " included windows. ", length(d), " weekdays in the scenario."), "info"))
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
      if (nzchar(r$note)) alert_box(paste("Control limits not drawn or limited:", r$note), "warning")
    })
    out$plot <- renderPlot({
      validate(need(any(!is.na(res()$data$p)), paste("No", kind, "attempts in the weekday windows: nothing to plot.")))
      plot_p(res(), att_all()$date, paste0(kind, " failure (%)"), paste("p chart:", kind, "failures"))
    })
    out$tbl <- renderTable({
      d <- res()$data
      data.frame(date = att_all()$date, failures_over_n = paste0(d$failures, "/", d$n),
                 percent = round(100 * d$p, 2), center_pct = round(100 * d$center, 2),
                 UCL_pct = round(100 * d$ucl, 2), LCL_pct = round(100 * d$lcl, 2),
                 signal = ifelse(is.na(d$out_of_control), "not assessed",
                                 ifelse(d$out_of_control, "OUT OF CONTROL", "in control")))
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
    data.frame(from = mv$from_station, to = mv$to_station, bikes = mv$quantity,
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
    if (nrow(u) == 0) data.frame(note = "None.") else u
  })
}

shinyApp(ui = ui, server = server)
