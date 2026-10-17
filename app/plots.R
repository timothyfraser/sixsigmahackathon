# app/plots.R - ggplot drawing helpers (team 2027win)
#
# Drawing only: every number plotted here was computed in app/qc.R or counted in app/prep.R.
# Needs ggplot2.

STATE_COLOURS <- c(
  "rent-unusable" = "#d73027",
  "return-unusable" = "#fc8d59",
  "rent- and return-unusable" = "#7b3294",
  "early warning" = "#fee08b",
  "usable" = "#1a9850",
  "unknown / stale data" = "#9e9e9e"
)

# Bikes and docks over the window for ONE station. Unknown minutes are NA, so the lines
# break there; grey ticks along the bottom mark each unknown minute.
plot_trend <- function(g, title) {
  long <- rbind(
    data.frame(minute = g$minute, value = g$bikes_available, what = "bikes available"),
    data.frame(minute = g$minute, value = g$docks_available, what = "docks available"))
  p <- ggplot2::ggplot(long, ggplot2::aes(minute, value, colour = what)) +
    ggplot2::geom_line(na.rm = TRUE) +
    ggplot2::geom_point(size = 0.8, na.rm = TRUE) +
    ggplot2::labs(title = title, x = "time (New York)", y = "count", colour = NULL,
                  caption = "Line breaks and grey ticks = unknown/stale minutes (no value is shown)") +
    ggplot2::theme_minimal() + ggplot2::theme(legend.position = "bottom")
  unknown <- g[!g$known, ]
  if (nrow(unknown) > 0) {
    p <- p + ggplot2::geom_rug(data = unknown, ggplot2::aes(x = minute), inherit.aes = FALSE,
                               sides = "b", colour = "grey50")
  }
  p
}

# Heatmap: either-unusable minutes per station and hour.
# Hours with known minutes use a light-to-dark red scale; 0 is a visible light tint with a
# thin border, so it never looks like an empty cell. Hours with no known minute are drawn
# separately in dark grey and get their own legend entry, so "0 unusable
# minutes" and "unknown" can always be told apart.
plot_heatmap <- function(m) {
  m$hour_f <- factor(m$hour)
  known <- m[m$known_min > 0, ]
  unknown <- m[!(m$known_min > 0), ]
  top <- max(1, known$either_unusable_min, na.rm = TRUE)
  p <- ggplot2::ggplot(m, ggplot2::aes(hour_f, station_id)) +
    ggplot2::geom_blank() +
    ggplot2::geom_tile(data = known, ggplot2::aes(fill = either_unusable_min),
                       colour = "grey55", linewidth = 0.3) +
    ggplot2::scale_fill_gradient(low = "#fde5d8", high = "#b2182b", limits = c(0, top),
                                 name = "unusable minutes\n(known data)") +
    ggplot2::labs(x = "hour of day (New York)", y = "station",
                  caption = paste("Light tint = 0 unusable minutes.",
                                  "Dark grey = no known minute in that hour.", sep = "\n")) +
    ggplot2::theme_minimal() +
    ggplot2::theme(plot.caption = ggplot2::element_text(hjust = 0))
  if (nrow(unknown) > 0) {
    p <- p +
      ggplot2::geom_tile(data = unknown, ggplot2::aes(colour = "no known minute (unknown)"),
                         fill = "grey45", linewidth = 0.3) +
      ggplot2::scale_colour_manual(values = c("no known minute (unknown)" = "grey20"), name = NULL,
                                   guide = ggplot2::guide_legend(override.aes = list(fill = "grey45")))
  }
  p
}

# Pareto: bars = either-unusable minutes (largest first), line = cumulative share.
plot_pareto <- function(p) {
  p$station_id <- factor(p$station_id, levels = p$station_id)
  top <- max(p$either_unusable_min, 1)
  g <- ggplot2::ggplot(p, ggplot2::aes(station_id, either_unusable_min)) +
    ggplot2::geom_col(fill = "#4575b4") +
    ggplot2::labs(x = "station", y = "either-unusable minutes") +
    ggplot2::theme_minimal() +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 60, hjust = 1))
  if (!all(is.na(p$cum_share))) {
    g <- g + ggplot2::geom_line(ggplot2::aes(y = cum_share * top, group = 1), colour = "#d73027") +
      ggplot2::geom_point(ggplot2::aes(y = cum_share * top), colour = "#d73027") +
      ggplot2::scale_y_continuous(sec.axis = ggplot2::sec_axis(~ . / top, name = "cumulative share",
                                                                labels = function(x) paste0(round(100 * x), "%")))
  }
  g
}

# One control chart panel. d needs x (position), y, center and (optional) ucl, lcl, ooc;
# limits are drawn only when they are not NA (qc.R returns NA when they cannot be estimated).
# ooc_label / ok_label name the two signal states in the legend (p charts reword them when the
# dispersion check warns).
plot_control <- function(d, labels, ylab, title, y_limit_floor = NULL,
                         ooc_label = "out of control", ok_label = "in control") {
  d$ooc <- ifelse(is.na(d$ooc), "not assessed", ifelse(d$ooc, ooc_label, ok_label))
  colours <- c("#2166ac", "#d73027", "grey40")
  names(colours) <- c(ok_label, ooc_label, "not assessed")
  g <- ggplot2::ggplot(d, ggplot2::aes(x, y)) +
    ggplot2::geom_line(colour = "grey40", na.rm = TRUE) +
    ggplot2::geom_point(ggplot2::aes(colour = ooc), size = 3, na.rm = TRUE) +
    ggplot2::scale_colour_manual(values = colours, name = NULL) +
    ggplot2::scale_x_continuous(breaks = d$x, labels = labels) +
    ggplot2::labs(title = title, x = "rush window (date)", y = ylab) +
    ggplot2::theme_minimal() +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1),
                   legend.position = "bottom")
  if (any(!is.na(d$center))) {
    g <- g + ggplot2::geom_step(ggplot2::aes(y = center), colour = "darkgreen", na.rm = TRUE)
  }
  if (any(!is.na(d$ucl))) {
    g <- g + ggplot2::geom_step(ggplot2::aes(y = ucl), colour = "red", linetype = "dashed", na.rm = TRUE)
  }
  if (any(!is.na(d$lcl))) {
    g <- g + ggplot2::geom_step(ggplot2::aes(y = lcl), colour = "red", linetype = "dashed", na.rm = TRUE)
  }
  g
}

# p chart (qc.R p_chart result) -> plot
plot_p <- function(res, dates, ylab, title, ooc_label = "out of control", ok_label = "in control") {
  d <- res$data
  plot_control(data.frame(x = d$subgroup, y = 100 * d$p, center = 100 * d$center,
                          ucl = 100 * d$ucl, lcl = 100 * d$lcl, ooc = d$out_of_control),
               dates, ylab, title, ooc_label = ooc_label, ok_label = ok_label)
}

# I chart (qc.R imr_chart result) -> plot
plot_i <- function(res, dates, ylab, title) {
  d <- res$data
  plot_control(data.frame(x = d$subgroup, y = d$x, center = d$center, ucl = d$ucl,
                          lcl = d$lcl, ooc = d$out_of_control), dates, ylab, title)
}

# Moving-range chart (qc.R imr_chart result) -> plot
plot_mr <- function(res, dates, title) {
  d <- res$data
  mr_ooc <- ifelse(is.na(d$mr_signal), NA, d$mr_signal)
  plot_control(data.frame(x = d$subgroup, y = d$mr, center = res$mr_bar, ucl = d$mr_ucl,
                          lcl = NA_real_, ooc = mr_ooc),
               dates, "moving range (percentage points)", title)
}

# c chart (qc.R c_chart result) -> plot
plot_c <- function(res, dates, ylab, title, ooc_label = "out of control", ok_label = "in control") {
  d <- res$data
  plot_control(data.frame(x = d$subgroup, y = d$count, center = d$center, ucl = d$ucl,
                          lcl = d$lcl, ooc = d$out_of_control),
               dates, ylab, title, ooc_label = ooc_label, ok_label = ok_label)
}

# X-bar chart (qc.R xbar_r_chart result) -> plot. A subgroup is red when it has a rule 1 or 4 signal.
plot_xbar <- function(res, dates, ylab, title) {
  d <- res$data
  plot_control(data.frame(x = d$subgroup, y = d$xbar, center = d$x_center, ucl = d$x_ucl,
                          lcl = d$x_lcl, ooc = d$rule1_x | d$rule4_x),
               dates, ylab, title)
}

# R chart (qc.R xbar_r_chart result) -> plot. Rule 1 only.
plot_r <- function(res, dates, ylab, title) {
  d <- res$data
  plot_control(data.frame(x = d$subgroup, y = d$range, center = d$r_center, ucl = d$r_ucl,
                          lcl = d$r_lcl, ooc = d$rule1_r),
               dates, ylab, title)
}

# Histogram of the individual response times used, with the centre and any spec limit the
# operator typed (dashed red, labelled as the operator's input).
plot_response_hist <- function(x, xbarbar = NA_real_, usl = NA_real_, lsl = NA_real_) {
  g <- ggplot2::ggplot(data.frame(x = x), ggplot2::aes(x)) +
    ggplot2::geom_histogram(bins = max(5, min(20, length(unique(x)))), fill = "#4575b4",
                            colour = "white") +
    ggplot2::labs(title = "Response times in the subgroups", x = "response time (minutes)",
                  y = "tasks",
                  caption = "Green = X-double-bar. Dashed red = USL / LSL typed by the operator (an input, not a measured spec).") +
    ggplot2::theme_minimal()
  if (!is.na(xbarbar)) g <- g + ggplot2::geom_vline(xintercept = xbarbar, colour = "darkgreen")
  specs <- c(usl, lsl)
  specs <- specs[!is.na(specs)]
  if (length(specs) > 0) g <- g + ggplot2::geom_vline(xintercept = specs, colour = "red", linetype = "dashed")
  g
}

# Kaplan-Meier step curve S(t) with its 95% interval band and censoring ticks (+).
# d = prep.R km_plot_data(): d$curve (t, surv, lo, hi on whole minutes), d$ticks (t, surv).
# Whole-minute steps: each value holds on [m, m+1), so the curve and band are drawn as exact steps.
plot_km <- function(d, title, caption) {
  cv <- d$curve
  steps <- data.frame(t = c(rbind(cv$t, cv$t + 1)), surv = rep(cv$surv, each = 2),
                      lo = rep(cv$lo, each = 2), hi = rep(cv$hi, each = 2))
  g <- ggplot2::ggplot(steps, ggplot2::aes(t, surv)) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = lo, ymax = hi), fill = "#4575b4", alpha = 0.2, na.rm = TRUE) +
    ggplot2::geom_line(colour = "#08519c", linewidth = 0.8, na.rm = TRUE) +
    ggplot2::scale_y_continuous(limits = c(0, 1)) +
    ggplot2::labs(title = title, x = "minutes after 07:00 (station usable at 07:00)",
                  y = "S(t): share of station-days with no failure yet", caption = caption) +
    ggplot2::theme_minimal()
  if (nrow(d$ticks) > 0) {
    g <- g + ggplot2::geom_point(data = d$ticks, ggplot2::aes(t, surv), shape = 3, size = 2.5,
                                 colour = "black", inherit.aes = FALSE)
  }
  g
}

# Per-seed paired differences for the primary metric: one point per seed, the mean (green) and its
# confidence interval (dashed blue band edges; NA = not drawn), zero = no difference.
# d = metric(none) - metric(reactive), so points above 0 favour the reactive policy.
# ci_low / ci_high / mean_d come from sim.R paired_table; this function only draws.
plot_paired_diff <- function(d, seeds, mean_d, ci_low, ci_high, ci_text, ylab, title) {
  df <- data.frame(seed = seeds, d = d)
  g <- ggplot2::ggplot(df, ggplot2::aes(seed, d)) +
    ggplot2::geom_hline(yintercept = 0, colour = "grey40") +
    ggplot2::geom_point(size = 2.5, colour = "#2166ac", na.rm = TRUE) +
    ggplot2::labs(title = title, x = "seed", y = ylab, caption = ci_text) +
    ggplot2::theme_minimal()
  if (!is.na(mean_d)) g <- g + ggplot2::geom_hline(yintercept = mean_d, colour = "darkgreen")
  if (!is.na(ci_low) && !is.na(ci_high)) {
    g <- g + ggplot2::geom_hline(yintercept = c(ci_low, ci_high), colour = "#2166ac", linetype = "dashed")
  }
  g
}

# The three pairwise primary differences side by side (H-15): one panel per pair, one point per seed,
# the mean (green) and the Bonferroni interval (dashed blue; NA = not drawn), zero = no difference.
# d = metric(first policy) - metric(second policy), so points above 0 favour the SECOND policy.
# diffs = list named by pair of per-seed differences; rows = the primary rows of sim.R paired_tables
# (columns pair, mean_d, ci_low, ci_high). This function only draws.
plot_paired_diffs <- function(diffs, seeds, rows, ylab, title, caption) {
  pairs <- names(diffs)
  df <- data.frame(seed = rep(seeds, length(pairs)), d = unlist(diffs, use.names = FALSE),
                   pair = factor(rep(pairs, each = length(seeds)), levels = pairs))
  rows <- rows[match(pairs, rows$pair), ]
  rows$pair <- factor(rows$pair, levels = pairs)
  g <- ggplot2::ggplot(df, ggplot2::aes(seed, d)) +
    ggplot2::geom_hline(yintercept = 0, colour = "grey40") +
    ggplot2::geom_point(size = 2, colour = "#2166ac", na.rm = TRUE) +
    ggplot2::facet_wrap(~pair, nrow = 1) +
    ggplot2::labs(title = title, x = "seed", y = ylab, caption = caption) +
    ggplot2::theme_minimal()
  has_mean <- !is.na(rows$mean_d)
  if (any(has_mean)) {
    g <- g + ggplot2::geom_hline(ggplot2::aes(yintercept = mean_d), data = rows[has_mean, ], colour = "darkgreen")
  }
  has_ci <- !is.na(rows$ci_low) & !is.na(rows$ci_high)
  if (any(has_ci)) {
    g <- g + ggplot2::geom_hline(ggplot2::aes(yintercept = ci_low), data = rows[has_ci, ], colour = "#2166ac", linetype = "dashed") +
      ggplot2::geom_hline(ggplot2::aes(yintercept = ci_high), data = rows[has_ci, ], colour = "#2166ac", linetype = "dashed")
  }
  g
}

# Risk of the top stations: P(at least one unusable minute within the horizon), rent and return side
# by side, with +/- 1 simulation SE as a thin bar. d = prep.R forecast_plot_data().
# When the day bootstrap was run (lo / hi not NA) the 2.5-97.5% parameter range (iii) is added as a wide
# orange bracket, distinct from the thin black SE whisker (ii); the caption says which is which.
plot_forecast_risk <- function(d, title, caption) {
  d$station <- factor(d$station, levels = rev(unique(d$station)))
  g <- ggplot2::ggplot(d, ggplot2::aes(station, p, fill = type)) +
    ggplot2::geom_col(position = ggplot2::position_dodge(width = 0.8), width = 0.7) +
    ggplot2::geom_errorbar(ggplot2::aes(ymin = pmax(0, p - se), ymax = pmin(1, p + se)),
                           position = ggplot2::position_dodge(width = 0.8), width = 0.25)
  if ("lo" %in% names(d) && any(!is.na(d$lo))) {
    g <- g + ggplot2::geom_errorbar(ggplot2::aes(ymin = lo, ymax = hi), data = d[!is.na(d$lo), ],
                                    position = ggplot2::position_dodge(width = 0.8), width = 0.6,
                                    colour = "#ff7f00", linewidth = 0.9)
  }
  g +
    ggplot2::coord_flip() +
    ggplot2::scale_y_continuous(limits = c(0, 1)) +
    ggplot2::scale_fill_manual(values = c("rent-unusable" = "#d73027", "return-unusable" = "#4575b4"), name = NULL) +
    ggplot2::labs(title = title, x = "station", y = "probability of at least one unusable minute", caption = caption) +
    ggplot2::theme_minimal() + ggplot2::theme(legend.position = "bottom")
}
