# Shared daily hydrograph for a gage or diversion: observed daily flow over
# day-of-year percentile bands, with gaps shown explicitly. Diversions use
# official daily records, then provisional telemetry after the records end,
# and monthly means before daily records begin.

library(dplyr)
library(plotly)

hydro_periods <- c("Past year" = 365, "5 years" = 5 * 365,
                   "10 years" = 10 * 365, "All" = Inf)

#' Observed series for one site as list(daily, telemetry, monthly).
site_series <- function(type, id) {
  if (type == "gage") {
    daily <- read_ds("streamflow_daily") |>
      filter(id == !!id) |>
      transmute(x = date, y = flow_cfs) |>
      collect() |>
      arrange(x)
    return(list(daily = daily, telemetry = NULL, monthly = NULL))
  }

  records <- if (dir.exists(file.path(DATA_ROOT, "diversions_daily_records"))) {
    read_ds("diversions_daily_records") |>
      filter(wdid == !!id) |>
      transmute(x = date, y = discharge_cfs) |>
      collect() |>
      arrange(x)
  } else {
    tibble(x = as.Date(character()), y = numeric())
  }
  records_end <- if (nrow(records) > 0) max(records$x) else as.Date("1900-01-01")

  telemetry <- read_ds("diversions_daily") |>
    filter(wdid == !!id, date > !!records_end) |>
    transmute(x = date, y = discharge_cfs) |>
    collect() |>
    arrange(x)

  daily_start <- min(c(records$x, telemetry$x, Sys.Date()))
  monthly <- history |>
    filter(wdid == !!id, month_start < daily_start) |>
    transmute(x = month_start + 14, y = mean_cfs) |>
    arrange(x)

  list(daily = records, telemetry = telemetry, monthly = monthly)
}

#' Percentile bands for every day between two dates from day-of-year stats.
site_normals <- function(stats, start, end) {
  if (is.null(stats) || nrow(stats) == 0) return(NULL)
  days <- tibble(x = seq(start, end, by = "day")) |>
    mutate(mmdd = format(x, "%m-%d"))
  if (!"02-29" %in% stats$mmdd) {
    days <- mutate(days, mmdd = if_else(mmdd == "02-29", "02-28", mmdd))
  }
  left_join(days, stats, by = "mmdd")
}

#' Fill missing days with NA so lines break, keep rows inside the window.
in_window <- function(df, start, step = "day") {
  if (is.null(df) || nrow(df) == 0) return(df)
  df <- filter(df, x >= start)
  if (nrow(df) == 0 || step != "day") return(df)
  complete_series(df, "day")
}

#' Plotly hydrograph for one site over the last `days` days.
plot_site_hydrograph <- function(series, stats, title, days = 365,
                                 dark = FALSE) {
  all_x <- c(series$daily$x, series$telemetry$x, series$monthly$x)
  validate(need(length(all_x) > 0, "No data for this site."))
  end   <- max(all_x)
  start <- if (is.finite(days)) end - days else min(all_x)

  daily     <- in_window(series$daily, start)
  telemetry <- in_window(series$telemetry, start)
  monthly   <- if (!is.null(series$monthly)) filter(series$monthly, x >= start)
  bands     <- site_normals(stats, start, end)

  blue   <- if (dark) "#6ab0de" else "#31688e"
  green  <- "#35b779"
  outer  <- if (dark) "rgba(255,255,255,0.08)" else "rgba(0,0,0,0.06)"
  inner  <- if (dark) "rgba(255,255,255,0.16)" else "rgba(0,0,0,0.12)"
  has    <- function(d) !is.null(d) && nrow(d) > 0

  p <- plot_ly()
  if (has(bands)) {
    p <- p |>
      add_ribbons(data = bands, x = ~x, ymin = ~p10_cfs, ymax = ~p90_cfs,
                  name = "10th to 90th percentile", fillcolor = outer,
                  line = list(width = 0), hoverinfo = "skip") |>
      add_ribbons(data = bands, x = ~x, ymin = ~p25_cfs, ymax = ~p75_cfs,
                  name = "25th to 75th percentile", fillcolor = inner,
                  line = list(width = 0), hoverinfo = "skip") |>
      add_lines(data = bands, x = ~x, y = ~p50_cfs, name = "Median for the day",
                line = list(color = "grey", dash = "dash", width = 1),
                hovertemplate = "Median: %{y:,.1f} cfs<extra></extra>")
  }
  if (has(monthly)) {
    p <- p |>
      add_lines(data = monthly, x = ~x, y = ~y, name = "Monthly mean (records)",
                line = list(color = blue, width = 1.5, dash = "dashdot"),
                hovertemplate = "Monthly mean: %{y:,.1f} cfs<extra></extra>")
  }
  if (has(daily)) {
    p <- p |>
      add_lines(data = daily, x = ~x, y = ~y, connectgaps = FALSE,
                name = if (has(telemetry)) "Daily (approved records)" else "Daily",
                line = list(color = blue, width = 1.3),
                hovertemplate = "Daily: %{y:,.1f} cfs<extra></extra>") |>
      add_lines(data = gap_bridges(daily), x = ~x, y = ~y,
                name = "No record (gap)", legendgroup = "gap",
                line = list(color = blue, width = 1, dash = "dot"),
                opacity = 0.5, hoverinfo = "skip")
  }
  if (has(telemetry)) {
    p <- p |>
      add_lines(data = telemetry, x = ~x, y = ~y, connectgaps = FALSE,
                name = "Daily (provisional telemetry)",
                line = list(color = green, width = 1.3),
                hovertemplate = "Telemetry: %{y:,.1f} cfs<extra></extra>") |>
      add_lines(data = gap_bridges(telemetry), x = ~x, y = ~y,
                legendgroup = "gap", showlegend = !has(daily),
                name = "No record (gap)",
                line = list(color = green, width = 1, dash = "dot"),
                opacity = 0.5, hoverinfo = "skip")
  }

  p |>
    layout(title = list(text = title, x = 0),
           xaxis = list(title = "", hoverformat = "%b %d, %Y"),
           yaxis = list(title = "Discharge (cfs)", rangemode = "tozero"),
           hovermode = "x unified",
           margin = list(t = if (is.null(title)) 10 else 40)) |>
    style_plotly(dark)
}
