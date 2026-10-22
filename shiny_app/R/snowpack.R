# SNOTEL snowpack this water year against the 1991 to 2020 median, for a
# basin or the whole state. Used by the Basins tab and the story.

min_median_mm <- 25   # below about an inch, % of median is too noisy to show

#' "April 5" (no zero padding).
fmt_day <- function(d) sprintf("%s %d", format(d, "%B"), as.integer(format(d, "%d")))

#' Mean SWE across sites, today's water year and the median curve.
#'
#' The median curve averages each site's 1991 to 2020 median for the date.
#' Daily values average only sites that report and have a median that day,
#' so `pct` (sum of SWE over sum of medians, as NRCS computes basin indexes)
#' compares like with like.
#' @param daily SNOTEL daily values (site_id, date, swe_mm).
#' @param normals SWE day-of-year stats (site_id, mmdd, med_9120).
#' @param site_ids sites to include.
snowpack_series <- function(daily, normals, site_ids) {
  if (is.null(daily) || is.null(normals)) return(NULL)
  med <- filter(normals, site_id %in% site_ids, !is.na(med_9120), mmdd != "02-29")
  if (nrow(med) == 0) return(NULL)

  normal <- med |>
    summarize(median_mm = mean(med_9120), n_sites = n(), .by = mmdd) |>
    mutate(x = wy_axis_date(mmdd)) |>
    arrange(x)

  current <- daily |>
    filter(site_id %in% site_ids, !is.na(swe_mm), format(date, "%m-%d") != "02-29") |>
    mutate(mmdd = format(date, "%m-%d")) |>
    inner_join(med, by = c("site_id", "mmdd")) |>
    summarize(pct = 100 * sum(swe_mm) / sum(med_9120), swe_mm = mean(swe_mm),
              median_mm = mean(med_9120), n_sites = n(), .by = date) |>
    mutate(x = wy_axis_date(date)) |>
    arrange(date)

  list(normal = normal, current = current,
       peak = slice_max(normal, median_mm, n = 1, with_ties = FALSE),
       n_sites = n_distinct(med$site_id))
}

#' Snowpack status today: latest value, % of median, and season stage.
snowpack_today <- function(s) {
  last <- slice_max(s$current, date, n = 1, with_ties = FALSE)
  if (nrow(last) == 0) return(NULL)
  after_peak <- last$x > s$peak$x
  stage <- if (last$median_mm >= min_median_mm) "season"
           else if (after_peak) "melted" else "early"
  this_peak <- slice_max(s$current, swe_mm, n = 1, with_ties = FALSE)
  list(date = last$date, swe_mm = last$swe_mm, median_mm = last$median_mm,
       pct = if (stage == "season") last$pct else NA_real_, stage = stage,
       n_sites = last$n_sites, this_peak = this_peak)
}

#' Current water year SWE over the 1991 to 2020 median curve, in inches.
snowpack_plot <- function(s, dark = FALSE, median_color = "#21908c",
                          current_color = NULL) {
  current_color <- current_color %||% if (dark) "#fde725" else "#440154"
  now_wy <- water_year(Sys.Date())
  peak <- s$peak
  p <- plot_ly() |>
    add_lines(data = s$normal, x = ~x, y = ~median_mm / 25.4,
              name = "1991 to 2020 median",
              line = list(color = median_color, dash = "dash", width = 1.5),
              hovertemplate = "%{x|%b %d} median: %{y:.1f} in<extra></extra>")
  if (nrow(s$current) > 0) {
    p <- p |>
      add_lines(data = s$current, x = ~x, y = ~swe_mm / 25.4,
                name = sprintf("WY %d to date", now_wy),
                line = list(color = current_color, width = 2.5),
                customdata = ~ifelse(median_mm >= min_median_mm, sprintf(" (%.0f%% of median)", pct), ""),
                hovertemplate = "%{x|%b %d}: %{y:.1f} in%{customdata}<extra></extra>")
  }
  p |>
    layout(
      xaxis = list(title = "", tickformat = "%b", dtick = "M1",
                   range = as.character(as.Date(c("1999-10-01", "2000-09-30")))),
      yaxis = list(title = "Snow water equivalent (in)", rangemode = "tozero"),
      hovermode = "x unified",
      annotations = list(list(
        x = as.character(peak$x), y = peak$median_mm / 25.4,
        text = sprintf("Typical peak: %.1f in, %s", peak$median_mm / 25.4,
                       format(peak$x, "%b %d")),
        showarrow = TRUE, arrowcolor = median_color, ax = -50, ay = -25,
        xanchor = "right", font = list(size = 11)
      )),
      margin = list(t = 30, b = 30)
    ) |>
    style_plotly(dark, legend = legend_top)
}
