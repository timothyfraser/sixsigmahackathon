library(dplyr)
library(ggplot2)

CITY_TZ <- "America/Chicago"
BIN_MINUTES <- 5

milwaukee <- readRDS("data/milwaukee.rds")

# ------------------------------------------------------------------
# Timestamp handling
# ------------------------------------------------------------------

parse_city_time <- function(x, tz) {
  if (inherits(x, "POSIXt")) {
    # Preserve the actual instant; do not strip and reinterpret its clock.
    return(as.POSIXct(x))
  }

  x <- as.character(x)

  # Supports our exported CSV timestamps with explicit UTC offsets.
  if (all(grepl(
    "T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{4}$",
    x
  ))) {
    return(as.POSIXct(
      x,
      format = "%Y-%m-%dT%H:%M:%S%z",
      tz = tz
    ))
  }

  # Timezone-free strings are interpreted as local city time.
  as.POSIXct(
    x,
    format = "%Y-%m-%d %H:%M:%S",
    tz = tz
  )
}


# ------------------------------------------------------------------
# Historical net docking rates
# Positive = net arrivals; negative = net departures.
# ------------------------------------------------------------------

compute_dock_rates <- function(
    df,
    bin_minutes = 5,
    tz = "America/Chicago"
) {
  stopifnot(
    all(c("BIKEID", "DOCID", "time") %in% names(df)),
    length(bin_minutes) == 1,
    is.finite(bin_minutes),
    bin_minutes > 0,
    1440 %% bin_minutes == 0
  )

  bin_sec <- bin_minutes * 60
  slots_per_day <- 1440 / bin_minutes
  slots_per_week <- 7 * slots_per_day

  df <- df %>%
    mutate(
      BIKEID = as.character(BIKEID),
      DOCID = as.character(DOCID),
      time = parse_city_time(time, tz)
    )

  if (anyNA(df[c("BIKEID", "DOCID", "time")])) {
    stop("Missing bike IDs, dock IDs, or invalid timestamps.")
  }

  if (anyDuplicated(df[c("BIKEID", "time")])) {
    stop("Duplicate BIKEID/full-timestamp pairs found.")
  }

  df <- df %>%
    mutate(
      bin = as.POSIXct(
        floor(as.numeric(time) / bin_sec) * bin_sec,
        origin = "1970-01-01",
        tz = tz
      )
    )

  counts <- df %>%
    filter(DOCID != "0") %>%
    group_by(DOCID, bin) %>%
    summarise(
      n_docked = n_distinct(BIKEID),
      .groups = "drop"
    )

  if (nrow(counts) == 0) {
    stop("No docked-bike observations found.")
  }

  all_bins <- seq(
    min(df$bin),
    max(df$bin),
    by = bin_sec
  )

  grid <- expand.grid(
    DOCID = unique(counts$DOCID),
    bin = all_bins,
    stringsAsFactors = FALSE
  )

  per_bin <- grid %>%
    left_join(counts, by = c("DOCID", "bin")) %>%
    mutate(
      n_docked = coalesce(n_docked, 0L),

      # Explicit local timezone is essential here.
      weekday = as.integer(format(bin, "%u", tz = tz)),
      minute =
        as.integer(format(bin, "%H", tz = tz)) * 60 +
        as.integer(format(bin, "%M", tz = tz)),

      slot =
        (weekday - 1) * slots_per_day +
        minute / bin_minutes
    )

  weekly <- per_bin %>%
    group_by(DOCID, weekday, slot, minute) %>%
    summarise(
      avg_docked = mean(n_docked),
      n_days = n(),
      .groups = "drop"
    )

  coverage <- weekly %>%
    count(DOCID, name = "n_slots")

  if (any(coverage$n_slots != slots_per_week)) {
    stop(
      "History must cover every local weekday/time slot ",
      "to construct a complete typical week."
    )
  }

  previous <- weekly %>%
    transmute(
      DOCID,
      slot = (slot + 1) %% slots_per_week,
      prev_docked = avg_docked
    )

  result <- weekly %>%
    left_join(previous, by = c("DOCID", "slot")) %>%
    mutate(
      day = c(
        "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"
      )[weekday],
      tod = sprintf(
        "%02d:%02d",
        minute %/% 60,
        minute %% 60
      ),
      rate = (avg_docked - prev_docked) / bin_minutes
    ) %>%
    select(
      DOCID, weekday, day, tod, slot, n_days,
      avg_docked, prev_docked, rate
    ) %>%
    arrange(DOCID, slot)

  attr(result, "city_timezone") <- tz
  attr(result, "bin_minutes") <- bin_minutes

  result
}


mke_rates <- compute_dock_rates(
  milwaukee,
  bin_minutes = BIN_MINUTES,
  tz = CITY_TZ
)

mke_rates %>%
  filter(
    DOCID == "Discovery World",
    day %in% c("Tue", "Sat")
  ) %>%
  mutate(
    hour = (slot %% (1440 / BIN_MINUTES)) *
      BIN_MINUTES / 60
  ) %>%
  ggplot(aes(x = hour, y = rate, color = day)) +
  geom_hline(yintercept = 0, color = "grey60") +
  geom_line(linewidth = 0.6) +
  scale_color_manual(values = c(Tue = "blue", Sat = "red")) +
  scale_x_continuous(
    breaks = seq(0, 24, 3),
    labels = sprintf("%02d:00", seq(0, 24, 3)),
    limits = c(0, 24)
  ) +
  labs(
    x = "Milwaukee local time",
    y = "Net docking rate (bikes/min)",
    color = NULL
  ) +
  theme_bw()

# ------------------------------------------------------------------
# Typical-week inventory-change projection
# This is a historical baseline, not a calibrated probability model.
# ------------------------------------------------------------------

predict_dock <- function(
    rates,
    dock,
    live_bikes,
    capacity,
    walk_min,
    now = Sys.time(),
    smooth_min = 30,
    bin_minutes = 5,
    tz = "America/Chicago"
) {
  stopifnot(
    length(live_bikes) == 1,
    length(capacity) == 1,
    length(walk_min) == 1,
    is.finite(live_bikes),
    is.finite(capacity),
    is.finite(walk_min),
    capacity > 0,
    live_bikes >= 0,
    live_bikes <= capacity,
    walk_min >= 0,
    bin_minutes > 0,
    smooth_min >= 0
  )

  stored_tz <- attr(rates, "city_timezone")
  stored_bin <- attr(rates, "bin_minutes")

  if (!is.null(stored_tz) && stored_tz != tz) {
    stop("Prediction timezone must match historical rates.")
  }

  if (!is.null(stored_bin) && stored_bin != bin_minutes) {
    stop("Prediction bin size must match historical rates.")
  }

  week_min <- 7 * 1440
  slots_per_week <- week_min / bin_minutes

  d <- rates %>%
    filter(DOCID == dock) %>%
    arrange(slot)

  if (nrow(d) == 0) {
    stop("Unknown dock: ", dock)
  }

  if (
    nrow(d) != slots_per_week ||
    anyDuplicated(d$slot) ||
    !all(d$slot == seq.int(0, slots_per_week - 1))
  ) {
    stop("Dock history must contain a complete typical week.")
  }

  avg <- d$avg_docked
  k <- max(1L, as.integer(round(smooth_min / bin_minutes)))

  if (k > length(avg)) {
    stop("Smoothing window exceeds the available weekly history.")
  }

  if (k > 1) {
    avg <- as.numeric(stats::filter(
      avg,
      rep(1 / k, k),
      sides = 2,
      circular = TRUE
    ))
  }

  # These datasets are snapshots at the recorded timestamp.
  anchors <- d$slot * bin_minutes

  typical <- approxfun(
    c(
      anchors - week_min,
      anchors,
      anchors + week_min
    ),
    rep(avg, 3),
    rule = 2
  )

  now <- parse_city_time(now, tz)

  if (length(now) != 1 || is.na(now)) {
    stop("Provide one valid prediction timestamp.")
  }

  local_now <- as.POSIXlt(now, tz = tz)

  now_min <-
    (as.integer(format(now, "%u", tz = tz)) - 1) * 1440 +
    local_now$hour * 60 +
    local_now$min +
    local_now$sec / 60

  arrive_min <- (now_min + walk_min) %% week_min

  change <- typical(arrive_min) - typical(now_min)
  bikes <- min(max(live_bikes + change, 0), capacity)

  c(
    expected_bikes = unname(bikes),
    expected_spaces = unname(capacity - bikes),
    change = unname(change)
  )
}

# Timezone-free example strings are interpreted as Milwaukee local time.
# Capacity 30 matches the synthetic demo.

predict_dock(
  mke_rates,
  dock = "411 East Wisconsin ",
  now = "2026-10-15 11:35:00",
  live_bikes = 4,
  capacity = 30,
  walk_min = 25,
  tz = CITY_TZ
)

predict_dock(
  mke_rates,
  dock = "Discovery World",
  now = "2026-10-20 23:30:00",
  live_bikes = 4,
  capacity = 30,
  walk_min = 25,
  tz = CITY_TZ
)

# ------------------------------------------------------------------
# Zone trends: net arrivals/departures in local time
# ------------------------------------------------------------------

zoning <- read.csv(
  "data/zoning/milwaukee.csv",
  colClasses = "character"
) %>%
  select(dockID, zone) %>%
  mutate(zone = tolower(trimws(zone)))

if (anyDuplicated(zoning$dockID)) {
  stop("Duplicate dock IDs in zoning lookup.")
}

unmatched <- mke_rates %>%
  distinct(DOCID) %>%
  anti_join(zoning, by = c("DOCID" = "dockID"))

if (nrow(unmatched) > 0) {
  stop("Some docks have no zoning assignment.")
}

zone_trends <- mke_rates %>%
  inner_join(zoning, by = c("DOCID" = "dockID")) %>%
  group_by(zone, weekday, day, slot) %>%
  summarise(
    rate_hr = mean(rate) * 60,
    docks = n(),
    .groups = "drop"
  ) %>%
  group_by(zone) %>%
  arrange(slot, .by_group = TRUE) %>%
  mutate(
    # Centered one-hour smoothing across the typical week.
    rate_smooth = as.numeric(stats::filter(
      rate_hr,
      rep(1 / 12, 12),
      sides = 2,
      circular = TRUE
    )),
    hour = (slot %% (1440 / BIN_MINUTES)) *
      BIN_MINUTES / 60,
    day = factor(
      day,
      levels = c(
        "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"
      )
    )
  ) %>%
  ungroup()

ggplot(
  zone_trends,
  aes(x = hour, y = rate_smooth, color = zone)
) +
  geom_hline(yintercept = 0, color = "grey40") +
  geom_line(linewidth = 0.7) +
  facet_wrap(~ day, nrow = 1) +
  scale_color_manual(values = c(
    office = "#2a78d6",
    residential = "#eb6834",
    retail = "#1baf7a"
  )) +
  scale_x_continuous(
    breaks = c(0, 6, 12, 18, 24),
    labels = c("0", "6a", "12p", "6p", "")
  ) +
  labs(
    x = "Milwaukee local time",
    y = "Net bikes per dock per hour\n(+ arriving, − leaving)",
    color = NULL,
    title = "When bikes arrive at and leave each zone"
  ) +
  theme_bw() +
  theme(legend.position = "top")