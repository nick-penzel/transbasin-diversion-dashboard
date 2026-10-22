# Graphics for the public story view. Colors come from the viridis family:
# mako for water, inferno orange for water moved across the Divide.

library(dplyr)
library(plotly)
library(leaflet)

story_col <- list(
  river  = "#3487A6", deep = "#3D5296", light = "#6CD3AD",
  divide = "#F78311", sky = "#B9C6D0", sky_dark = "#3B4754"
)

basin_exit <- c(
  Colorado = "Colorado River into Utah", `Yampa/White` = "Yampa and White into Utah",
  Dolores = "Dolores and San Miguel into Utah", `San Juan` = "San Juan into New Mexico",
  `Rio Grande` = "Rio Grande into New Mexico", Arkansas = "Arkansas River into Kansas",
  `South Platte` = "South Platte into Nebraska", `North Platte` = "North Platte into Wyoming"
)

#' "4.8 million acre-feet" or "540,000 acre-feet".
fmt_af_words <- function(af) {
  if (length(af) != 1) return(vapply(af, fmt_af_words, character(1)))
  if (is.na(af)) return("n/a")
  if (af >= 1e7) sprintf("%.0f million acre-feet", af / 1e6)
  else if (af >= 1e6) sprintf("%.1f million acre-feet", af / 1e6)
  else sprintf("%s acre-feet", format(signif(af, 2), big.mark = ",", scientific = FALSE))
}

#' Short volume label for map and chart annotations.
fmt_af_short <- function(af) {
  if (length(af) != 1) return(vapply(af, fmt_af_short, character(1)))
  if (af >= 1e6) sprintf("%.1fM AF", af / 1e6)
  else if (af >= 1e4) sprintf("%sK AF", format(round(af / 1e3), big.mark = ","))
  else sprintf("%s AF", format(signif(af, 2), big.mark = ","))
}

#' USGS names capitalize only the first word after a hyphen: "Colorado-Utah".
nice_name <- function(x) gsub("(?<=[-/])([a-z])", "\\U\\1", x, perl = TRUE)

#' Day of water year (1 = Oct 1) as "May 28".
wy_day_label <- function(day) format(as.Date("1999-09-30") + round(day), "%b %d")

#' 100 droplets: river outflow, moved across the Divide, and everything else.
droplet_waffle <- function(b, labels = c("left Colorado in its rivers",
                                          "was tunneled east across the Divide",
                                          "returned to the sky or stayed in the ground")) {
  n <- hundredths(c(b$outflow_af, b$divide_af, b$other_af))
  share <- 100 * c(b$outflow_af, b$divide_af) / b$prcp_af
  sliver <- function(x) if (x < 1) sprintf("%.1f of 100", x)
  kind <- rep(c("river", "divide", "sky"), n)
  drops <- lapply(seq_along(kind), function(i) {
    tags$span(class = paste("drop", kind[i]), style = sprintf("animation-delay:%dms", i * 9),
              bsicons::bs_icon("droplet-fill"))
  })
  tagList(
    tags$div(class = "waffle", drops),
    tags$div(
      class = "waffle-key",
      waffle_key("river", n[1], labels[1], b$outflow_af, count = sliver(share[1])),
      if (b$divide_af > 0)
        waffle_key("divide", n[2], labels[2], b$divide_af,
                   count = sliver(share[2])),
      waffle_key("sky", n[3], labels[3], b$other_af)
    )
  )
}

waffle_key <- function(kind, n, text, af, count = NULL) {
  tags$div(class = "key-row",
           tags$span(class = paste("drop", kind), bsicons::bs_icon("droplet-fill")),
           tags$div(tags$strong(count %||% sprintf("%d of 100", n)), " ", text,
                    tags$div(class = "key-af", fmt_af_words(af))))
}

#' Base leaflet map for the story: quiet basemap, no scroll zoom.
story_basemap <- function(dark = FALSE) {
  tone <- if (dark) "Dark_Gray" else "Light_Gray"
  leaflet(options = leafletOptions(scrollWheelZoom = FALSE, zoomSnap = 0.25)) |>
    addTiles(urlTemplate = sprintf(
      "https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_%s_Base/MapServer/tile/{z}/{y}/{x}",
      tone), attribution = "Tiles &copy; Esri") |>
    fitBounds(-109.6, 36.75, -101.6, 41.25)
}

#' Rivers drawn wider and deeper blue downstream.
add_story_rivers <- function(m, rivers, opacity = 0.85, width = 1.1) {
  pal <- colorNumeric(c(story_col$light, story_col$river, story_col$deep),
                      domain = range(rivers$order))
  m |>
    addPolylines(data = rivers, color = ~pal(order), weight = ~(order - 4) * width,
                 opacity = opacity, label = ~name,
                 options = pathOptions(interactive = TRUE))
}

#' Where the rivers leave: outlet circles sized by water-year outflow.
outflow_map <- function(rivers, basins, outflow, gages, outlets, year, dark = FALSE) {
  pts <- outlets |>
    distinct(basin, .keep_all = TRUE) |>
    left_join(select(gages, gage_id = id, longitude, latitude), by = "gage_id") |>
    left_join(filter(outflow, wy == year), by = "basin") |>
    filter(!is.na(outflow_af)) |>
    mutate(label = sprintf("<b>%s</b><br>%s in water year %d",
                           basin_exit[basin], fmt_af_words(outflow_af), year))
  story_basemap(dark) |>
    addPolygons(data = basins, fill = FALSE, color = if (dark) "#8796a8" else "#6b7b8f",
                weight = 1, dashArray = "3 4", opacity = 0.6,
                options = pathOptions(interactive = FALSE)) |>
    add_story_rivers(rivers) |>
    addCircleMarkers(data = pts, lng = ~longitude, lat = ~latitude,
                     radius = ~sqrt(outflow_af) / 55 + 4,
                     fillColor = story_col$river, fillOpacity = 0.35,
                     color = story_col$deep, weight = 2,
                     label = ~lapply(label, HTML)) |>
    addLabelOnlyMarkers(lng = c(-109.75, -106.9, -103.3, -101.55, -105.9),
                        lat = c(39.2, 41.25, 41.17, 38.6, 36.75),
                        label = c("UTAH", "WYOMING", "NEBRASKA", "KANSAS", "NEW MEXICO"),
                        labelOptions = labelOptions(noHide = TRUE, textOnly = TRUE,
                                                    direction = "center",
                                                    className = "state-label")) |>
    addLabelOnlyMarkers(data = pts, lng = ~longitude, lat = ~latitude,
                        label = ~fmt_af_short(outflow_af),
                        labelOptions = labelOptions(noHide = TRUE, direction = "top",
                                                    offset = c(0, -8),
                                                    className = "outflow-label"))
}

#' Quadratic curve from a to b bowed to the left of travel.
arc_coords <- function(a, b, bend = 0.25, n = 30) {
  mid <- (a + b) / 2
  d <- b - a
  ctrl <- mid + bend * c(-d[2], d[1])
  t <- seq(0, 1, length.out = n)
  cbind((1 - t)^2 * a[1] + 2 * (1 - t) * t * ctrl[1] + t^2 * b[1],
        (1 - t)^2 * a[2] + 2 * (1 - t) * t * ctrl[2] + t^2 * b[2])
}

#' Transfers across the Divide as animated arcs into the destination basin.
divide_map <- function(rivers, basins, divide, flows, dark = FALSE) {
  west <- basins$basin %in% west_slope
  map <- story_basemap(dark) |>
    addPolygons(data = basins, stroke = FALSE, fillOpacity = if (dark) 0.22 else 0.14,
                fillColor = ifelse(west, story_col$river, story_col$divide),
                options = pathOptions(interactive = FALSE)) |>
    add_story_rivers(rivers, opacity = 0.55) |>
    addPolylines(data = divide, color = if (dark) "#e9ecef" else "#1d2b3a",
                 weight = 2.5, dashArray = "1 6", opacity = 0.9,
                 options = pathOptions(interactive = FALSE, lineCap = "round"))
  svg <- pathOptions(interactive = FALSE, renderer = JS("L.svg()"))
  for (i in seq_len(nrow(flows))) {
    f <- flows[i, ]
    xy <- arc_coords(c(f$longitude, f$latitude), c(f$to_lon, f$to_lat))
    w <- 1.5 + sqrt(f$af) / 70
    map <- map |>
      addPolylines(lng = xy[, 1], lat = xy[, 2], color = story_col$divide,
                   weight = w, opacity = 0.5, options = svg) |>
      addPolylines(lng = xy[, 1], lat = xy[, 2], color = "#fff3d6",
                   weight = max(1, w / 3), opacity = 0.95, dashArray = "4 12",
                   options = modifyList(svg, list(className = "flow-anim")))
  }
  map |>
    addCircleMarkers(data = flows, lng = ~longitude, lat = ~latitude,
                     radius = ~2 + sqrt(af) / 70, color = "#ffffff", weight = 1.5,
                     fillColor = story_col$divide, fillOpacity = 1,
                     label = ~lapply(sprintf("<b>%s</b><br>%s to the %s basin",
                                             name, fmt_vec(af), to), HTML)) |>
    addLabelOnlyMarkers(lng = c(-107.9, -104.4), lat = c(39.75, 39.75),
                        label = c("WEST SLOPE", "EAST SLOPE"),
                        labelOptions = labelOptions(noHide = TRUE, textOnly = TRUE,
                                                    direction = "center",
                                                    className = "slope-label"))
}

#' Destination points for each cross-Divide structure: the destination
#' basin's interior within about 80 km of the structure.
divide_flows <- function(transfers, structures, basins, year) {
  f <- transfers |>
    filter(wy == year, from %in% west_slope, !to %in% west_slope, af > 0) |>
    left_join(select(structures, wdid, longitude, latitude), by = "wdid") |>
    filter(!is.na(longitude))
  if (nrow(f) == 0) return(f)
  b <- st_transform(basins, 26913)
  pts <- st_as_sf(f, coords = c("longitude", "latitude"), crs = 4326, remove = FALSE) |>
    st_transform(26913)
  ends <- lapply(seq_len(nrow(pts)), function(i) {
    dest <- b[b$basin == f$to[i], ]
    zone <- suppressWarnings(st_intersection(st_geometry(dest), st_buffer(st_geometry(pts)[i], 80000)))
    st_coordinates(st_transform(st_point_on_surface(zone), 4326))[1, ]
  })
  f$to_lon <- vapply(ends, `[`, numeric(1), 1)
  f$to_lat <- vapply(ends, `[`, numeric(1), 2)
  arrange(f, af)
}

#' Two stacked bars: where the river water is and where people live.
divide_split <- function(west_share, people_west = 0.1) {
  row <- function(label, west) {
    tags$div(class = "split-row",
             tags$div(class = "split-label", label),
             tags$div(class = "split-bar",
                      tags$div(class = "split-west", style = sprintf("flex:%.3f", west),
                               if (west >= 0.15) sprintf("%.0f%% west", 100 * west)),
                      tags$div(class = "split-east", style = sprintf("flex:%.3f", 1 - west),
                               if (west <= 0.85) sprintf("%.0f%% east", 100 * (1 - west)))),
             tags$div(class = "split-note",
                      if (west < 0.15) sprintf("%.0f%% west", 100 * west)
                      else if (west > 0.85) sprintf("%.0f%% east", 100 * (1 - west))))
  }
  tags$div(class = "split",
           row("River water leaving Colorado", west_share),
           row("Coloradans", people_west))
}

#' Every year's daily flow at one gage as faint lines, one year in color.
snowmelt_plot <- function(flow, year, dark = FALSE) {
  d <- flow |>
    mutate(wy = water_year(date), x = wy_axis_date(date)) |>
    filter(format(date, "%m-%d") != "02-29") |>
    arrange(date)
  med <- d |> filter(wy < year) |> summarize(q = median(flow_cfs, na.rm = TRUE), .by = x) |>
    arrange(x) |> mutate(q = stats::filter(q, rep(1 / 7, 7), sides = 2))
  ghost <- if (dark) "rgba(173,227,192,0.10)" else "rgba(61,82,150,0.09)"
  past <- d |> filter(wy < year) |> group_by(wy) |>
    group_modify(\(g, k) bind_rows(g, tibble::tibble(x = NA))) |> ungroup()
  this <- filter(d, wy == year)
  peak <- this |>
    filter(as.integer(format(date, "%m")) %in% 4:7) |>
    slice_max(flow_cfs, n = 1, with_ties = FALSE)
  plot_ly() |>
    add_lines(data = past, x = ~x, y = ~flow_cfs, line = list(color = ghost, width = 1),
              hoverinfo = "skip", name = "Earlier years", connectgaps = FALSE) |>
    add_lines(data = med, x = ~x, y = ~q, name = "Typical year",
              line = list(color = if (dark) "#ADE3C0" else story_col$deep, width = 2, dash = "dot"),
              hovertemplate = "%{x|%b %d}, typical: %{y:,.0f} cfs<extra></extra>") |>
    add_lines(data = this, x = ~x, y = ~flow_cfs, name = sprintf("Water year %d", year),
              line = list(color = story_col$divide, width = 2.5),
              hovertemplate = "%{x|%b %d}: %{y:,.0f} cfs<extra></extra>") |>
    layout(
      xaxis = list(title = "", tickformat = "%b", dtick = "M1",
                   range = as.character(as.Date(c("1999-10-01", "2000-09-30")))),
      yaxis = list(title = "Cubic feet per second", rangemode = "tozero"),
      hovermode = "x", showlegend = TRUE,
      annotations = list(
        list(x = as.character(peak$x), y = peak$flow_cfs,
             text = sprintf("%d spring peak: %s cfs on %s", year,
                            format(round(peak$flow_cfs), big.mark = ","),
                            format(peak$date, "%b %d")),
             showarrow = TRUE, arrowcolor = story_col$divide, font = list(size = 12),
             ax = 90, ay = -60, xanchor = "left"),
        list(x = "2000-01-15", y = 0.9, yref = "paper", showarrow = FALSE,
             text = "Winter: snow piles up,<br>rivers run low", font = list(size = 12),
             opacity = 0.7),
        list(x = "2000-06-01", y = 1.02, yref = "paper", showarrow = FALSE,
             text = "Spring: the snowpack melts", font = list(size = 12), opacity = 0.7)
      ),
      margin = list(t = 30, r = 10, b = 30)
    ) |>
    style_plotly(dark, legend = legend_top)
}

#' Dumbbells: date half of each basin's annual flow had passed, then and now.
runoff_shift_plot <- function(shift, dark = FALSE) {
  s <- shift |> arrange(shift) |> mutate(basin = factor(basin, levels = rev(basin)))
  seg <- s |> rowwise() |>
    reframe(basin = basin, x = c(early_day, recent_day, NA))
  plot_ly(s, y = ~basin) |>
    add_trace(data = seg, x = ~x, y = ~basin, type = "scatter", mode = "lines",
              line = list(color = if (dark) "rgba(255,255,255,0.3)" else "rgba(0,0,0,0.2)",
                          width = 4),
              hoverinfo = "skip", showlegend = FALSE) |>
    add_markers(data = s, x = ~early_day, name = "1991 to 2000",
                marker = list(color = story_col$deep, size = 13),
                text = ~sprintf("%s, 1990s: %s", basin, wy_day_label(early_day)),
                hoverinfo = "text") |>
    add_markers(data = s, x = ~recent_day, name = sprintf("%d to %d", min(s$recent_from), max(s$recent_to)),
                marker = list(color = story_col$divide, size = 13),
                text = ~sprintf("%s, recent: %s (%+.0f days)", basin,
                                wy_day_label(recent_day), shift),
                hoverinfo = "text") |>
    layout(annotations = list(list(x = 1, xref = "paper", y = 1.02, yref = "paper",
                                   xanchor = "right", yanchor = "bottom", showarrow = FALSE,
                                   text = "\u2190 earlier in the year",
                                   font = list(size = 12), opacity = 0.7)),
           xaxis = list(title = "", tickvals = c(152, 167, 183, 198, 213, 228, 244),
                        ticktext = c("Mar 1", "Mar 15", "Apr 1", "Apr 15", "May 1",
                                     "May 15", "Jun 1"),
                        range = c(min(s$recent_day, s$early_day) - 6,
                                  max(s$recent_day, s$early_day) + 6)),
           yaxis = list(title = ""),
           margin = list(t = 30, l = 10, r = 10, b = 30)) |>
    style_plotly(dark, legend = legend_top)
}

#' Warming stripes: one bar per water year colored by statewide mean temperature.
warming_stripes <- function(temp, dark = FALSE) {
  base <- mean(temp$tmean_f[temp$wy <= 2000])
  temp <- mutate(temp, anom = tmean_f - base)
  lim <- max(abs(temp$anom))
  plot_ly(temp, x = ~wy, y = 1, type = "bar", width = 1,
          marker = list(color = ~anom, cmin = -lim, cmax = lim,
                        colorscale = list(c(0, "#2166ac"), c(0.25, "#67a9cf"),
                                          c(0.5, "#f7f7f7"), c(0.75, "#ef8a62"),
                                          c(1, "#b2182b")),
                        line = list(width = 0)),
          hovertext = ~sprintf("Water year %d: %.1f \u00b0F (%+.1f vs 1980 to 2000)", wy, tmean_f, anom),
          hoverinfo = "text", textposition = "none") |>
    layout(bargap = 0, xaxis = list(title = "", showgrid = FALSE, dtick = 10,
                                    ticks = "", tickfont = list(size = 11)),
           yaxis = list(visible = FALSE),
           margin = list(t = 0, l = 0, r = 0, b = 24)) |>
    style_plotly(dark) |>
    config(displayModeBar = FALSE)
}

#' Reservoirs as tanks: water level, a line at the usual level for the
#' date, and height scaled by capacity (square root, so area reads as volume).
reservoir_tanks <- function(res, n = 12) {
  r <- res |>
    filter(!is.na(storage_af), !is.na(capacity)) |>
    slice_max(capacity, n = n) |>
    mutate(name = sub(" Reservoir$", "", name),
           pct = pmin(100 * storage_af / capacity, 100),
           usual = pmin(100 * p50_af / capacity, 100),
           level = case_when(is.na(pct_median) ~ "ok", pct_median < 60 ~ "very-low",
                             pct_median < 90 ~ "low", TRUE ~ "ok"))
  w_max <- sqrt(max(r$capacity))
  tags$div(class = "tanks", lapply(seq_len(nrow(r)), function(i) {
    x <- r[i, ]
    tags$div(
      class = "tank-wrap",
      style = sprintf("--h:%.0fpx", 60 + 170 * sqrt(x$capacity) / w_max),
      title = sprintf("%s: %s of %s acre-feet. Usually %.0f%% full on this date.",
                      x$name, format(round(x$storage_af), big.mark = ","),
                      format(round(x$capacity), big.mark = ","), x$usual),
      tags$div(class = "tank-pct", sprintf("%.0f%%", x$pct)),
      tags$div(class = "tank",
               tags$div(class = paste("water", x$level), style = sprintf("height:%.1f%%", x$pct)),
               if (!is.na(x$usual))
                 tags$div(class = "usual", style = sprintf("bottom:%.1f%%", x$usual))),
      tags$div(class = "tank-name", x$name),
      tags$div(class = "tank-cap", sprintf("holds %s", fmt_af_words(x$capacity)))
    )
  }))
}

plain_status <- tibble::tribble(
  ~class,       ~plain,
  "high",       "Highest ever for the date",
  "much_above", "Much higher than usual",
  "above",      "Higher than usual",
  "normal",     "About normal",
  "below",      "Lower than usual",
  "much_below", "Much lower than usual",
  "low",        "Lowest ever for the date",
  "unranked",   "Not enough history"
)

#' Today's river conditions: larger reaches colored by the condition
#' estimated from nearby gages, gages on top.
now_map <- function(reaches, gages, dark = FALSE) {
  g <- left_join(gages, plain_status, by = "class")
  m <- story_basemap(dark)
  if (!is.null(reaches)) {
    m <- m |>
      addPolylines(data = reaches, color = ~color, weight = ~(streamorde - 4) * 1.3,
                   opacity = 0.9, label = ~sprintf("%s: %s (estimated)",
                                                  coalesce(gnis_name, "Unnamed stream"),
                                                  coalesce(plain, "")),
                   options = pathOptions(interactive = TRUE))
  }
  m |>
    addCircleMarkers(data = g, lng = ~longitude, lat = ~latitude, layerId = ~id,
                     radius = 7, fillColor = ~color, fillOpacity = 1,
                     color = if (dark) "#161b22" else "#ffffff", weight = 2,
                     label = ~sprintf("%s: %s", nice_name(name), plain))
}

#' One gage's past year against its normal range, in plain terms.
public_hydrograph <- function(daily, stats, dark = FALSE, units = "cfs",
                              y_title = "Cubic feet per second") {
  validate(need(nrow(daily) > 0, "No recent data for this site."))
  end <- max(daily$x)
  start <- end - 365
  d <- in_window(daily, start)
  bands <- site_normals(stats, start, end)
  band_fill <- if (dark) "rgba(108,211,173,0.18)" else "rgba(52,135,166,0.16)"
  p <- plot_ly()
  if (!is.null(bands)) {
    p <- p |>
      add_ribbons(data = bands, x = ~x, ymin = ~p25_cfs, ymax = ~p75_cfs,
                  name = "Normal range", fillcolor = band_fill, line = list(width = 0),
                  hoverinfo = "skip") |>
      add_lines(data = bands, x = ~x, y = ~p50_cfs, name = "Typical",
                line = list(color = if (dark) "#ADE3C0" else story_col$deep,
                            dash = "dot", width = 1.5),
                hovertemplate = paste0("Typical: %{y:,.0f} ", units, "<extra></extra>"))
  }
  p |>
    add_lines(data = d, x = ~x, y = ~y, name = "This past year", connectgaps = FALSE,
              line = list(color = story_col$divide, width = 2.2),
              hovertemplate = paste0("%{x|%b %d}: %{y:,.0f} ", units, "<extra></extra>")) |>
    layout(xaxis = list(title = "", tickformat = "%b"),
           yaxis = list(title = y_title, rangemode = "tozero"),
           hovermode = "x unified", margin = list(t = 30, b = 30)) |>
    style_plotly(dark, legend = legend_top)
}

#' Plain-language card for one gage.
gage_card <- function(g) {
  plain <- plain_status$plain[plain_status$class == g$class]
  tagList(
    tags$div(class = "card-kicker", g$basin, " basin"),
    tags$h3(class = "card-title", nice_name(g$name)),
    tags$div(class = "card-status",
             tags$span(class = "tile", style = sprintf("background:%s", g$color)), plain),
    if (!is.na(g$flow_cfs)) {
      tags$p(sprintf("%s cubic feet per second on %s.",
                     format(round(g$flow_cfs), big.mark = ","), format(g$date, "%B %d")),
             if (!is.na(g$p50_cfs %||% NA))
               sprintf("On this date the river usually runs between %s and %s, based on %d years of records.",
                       fmt_cfs(g$p25_cfs), fmt_cfs(g$p75_cfs), g$n_years))
    } else tags$p("No recent reading.")
  )
}

#' Cards for the largest cross-Divide structures, with curated history.
tunnel_cards <- function(flows, profiles, n = 4) {
  top <- slice_max(flows, af, n = n)
  tags$div(class = "tunnels", lapply(seq_len(nrow(top)), function(i) {
    x <- top[i, ]
    pr <- profiles[[x$wdid]]
    summary <- if (!is.null(pr$summary)) sub("^(.*?\\.)\\s.*$", "\\1", pr$summary)
    tags$div(class = "tunnel",
             tags$div(class = "tunnel-af", fmt_af_short(x$af)),
             tags$div(class = "tunnel-to", sprintf("to the %s basin", x$to)),
             tags$h4(x$name),
             if (!is.null(pr$built)) tags$div(class = "tunnel-meta",
                                               paste0("Built ", pr$built,
                                                      if (!is.null(pr$operator)) paste0(" \u00b7 ", pr$operator))),
             if (!is.null(summary)) tags$p(summary))
  }))
}

# ---- River basins page ----

basin_blurb <- c(
  Colorado = "The Colorado River rises in Rocky Mountain National Park and gathers the Eagle, Roaring Fork, and Gunnison before it crosses into Utah. It is the state's largest river and a lifeline for the Southwest.",
  `Yampa/White` = "The Yampa and White drain Colorado's quiet northwest corner, sagebrush and high plateaus, and flow west into Utah. The Yampa is one of the least dammed rivers in the Colorado River system.",
  Dolores = "The Dolores and San Miguel drain the western San Juan Mountains. McPhee Reservoir holds back much of the Dolores and sends it south to farms around Cortez.",
  `San Juan` = "The Animas, Piedra, Los Pinos, and other rivers of the southern San Juan Mountains join the San Juan, which crosses into New Mexico near Four Corners.",
  `Rio Grande` = "The Rio Grande rises in the San Juan Mountains and crosses the San Luis Valley, where potato and barley farms depend on it and on the groundwater below, before it enters New Mexico.",
  Arkansas = "The Arkansas falls from near Leadville through the Royal Gorge to the plains, watering farms and towns from Pueblo to the Kansas line.",
  `South Platte` = "The South Platte runs through Denver and the Front Range, home to most Coloradans. It is the state's most heavily used river, and much of the water piped across the Divide ends up here.",
  `North Platte` = "The North Platte drains North Park, a high mountain valley of hay meadows, and flows north into Wyoming."
)

transfer_col <- c(export = story_col$divide, import = "#8E5BB5", local = "#7B8794")
transfer_word <- c(export = "Sends water out of the basin",
                   import = "Brings water into the basin",
                   local = "Diversion within the basin")

#' Diamond map icons for diversions, one color per direction.
diamond_icons <- function(dir) {
  url <- sprintf(paste0("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='18' height='18'>",
                        "<rect x='4' y='4' width='10' height='10' transform='rotate(45 9 9)' ",
                        "fill='%s' stroke='white' stroke-width='1.6'/></svg>"),
                 sub("#", "%23", transfer_col[dir]))
  icons(iconUrl = url, iconWidth = 18, iconHeight = 18)
}

#' One basin in the spotlight: other basins veiled and clickable, its rivers,
#' gages, reservoirs, and the diversions into or out of it.
basin_map <- function(b, basins, rivers, gages, reservoirs, divs, dark = FALSE) {
  sel <- basins[basins$basin == b, ]
  bb <- unname(sf::st_bbox(sel))
  veil <- if (dark) "#161b22" else "#fbfaf7"
  g <- left_join(gages, plain_status, by = "class")
  r <- left_join(reservoirs, plain_status, by = "class")
  story_basemap(dark) |>
    fitBounds(bb[1], bb[2], bb[3], bb[4]) |>
    addPolygons(data = sel, fillColor = story_col$river, fillOpacity = 0.06, stroke = FALSE,
                options = pathOptions(interactive = FALSE)) |>
    add_story_rivers(rivers, opacity = 0.95, width = 1.5) |>
    addPolygons(data = basins[basins$basin != b, ], layerId = ~basin, group = "basin",
                fillColor = veil, fillOpacity = 0.7, color = if (dark) "#55606e" else "#9aa6b2",
                weight = 1, label = ~paste("Explore the", basin, "basin"),
                highlightOptions = highlightOptions(fillOpacity = 0.45)) |>
    addPolygons(data = sel, fill = FALSE, color = story_col$deep, weight = 2.5, opacity = 0.9,
                options = pathOptions(interactive = FALSE)) |>
    addCircleMarkers(data = r, lng = ~longitude, lat = ~latitude, layerId = ~paste0("r:", wdid),
                     radius = ~5 + sqrt(capacity) / 80, fillColor = ~color, fillOpacity = 0.75,
                     color = if (dark) "#ADE3C0" else story_col$deep, weight = 2.5,
                     label = ~sprintf("%s: %.0f%% full, %s", name, pct_full,
                                      tolower(coalesce(plain, "no recent data")))) |>
    addCircleMarkers(data = g, lng = ~longitude, lat = ~latitude, layerId = ~paste0("g:", id),
                     radius = 6.5, fillColor = ~color, fillOpacity = 1,
                     color = if (dark) "#161b22" else "#ffffff", weight = 2,
                     label = ~sprintf("%s: %s", nice_name(name), plain)) |>
    addMarkers(data = divs, lng = ~longitude, lat = ~latitude, layerId = ~paste0("d:", wdid),
               icon = diamond_icons(divs$dir),
               label = ~sprintf("%s: %s", name, tolower(transfer_word[dir])))
}

#' Map key for the basin page.
basin_map_key <- function() {
  sw <- function(style, text) tags$span(tags$span(class = "key-mark", style = style), text)
  tags$div(class = "tile-legend",
           sw("border-radius:50%;background:#5fbf6a;border:2px solid #fff;box-shadow:0 0 0 1px #9aa6b2",
              "River gage, colored by today's flow"),
           sw("border-radius:50%;width:18px;height:18px;background:#5fbf6a;border:2.5px solid var(--deep)",
              "Reservoir, sized by capacity"),
           sw(sprintf("transform:rotate(45deg) scale(0.75);background:%s", transfer_col[["export"]]),
              "Sends water out"),
           sw(sprintf("transform:rotate(45deg) scale(0.75);background:%s", transfer_col[["import"]]),
              "Brings water in"),
           sw(sprintf("transform:rotate(45deg) scale(0.75);background:%s", transfer_col[["local"]]),
              "Other diversion"))
}

#' Water leaving the basin each year: river outflow with transfers out on top.
basin_years_plot <- function(years, dark = FALSE) {
  latest <- max(years$wy[!is.na(years$prcp_af)])
  med <- median(years$outflow_af)
  op <- ifelse(years$wy == latest, 1, 0.55)
  p <- plot_ly(years, x = ~wy) |>
    add_bars(y = ~outflow_af / 1e3, name = "Left the state in rivers",
             marker = list(color = story_col$river, opacity = op),
             hovertemplate = "%{x}: %{y:,.0f} thousand acre-feet in rivers<extra></extra>")
  if (any(years$export_af > 0, na.rm = TRUE)) {
    p <- p |>
      add_bars(y = ~export_af / 1e3, name = "Sent to other basins",
               marker = list(color = story_col$divide, opacity = op),
               hovertemplate = "%{x}: %{y:,.0f} thousand acre-feet sent away<extra></extra>")
  }
  p |>
    add_lines(y = med / 1e3, name = "Typical river outflow", hoverinfo = "skip",
              line = list(color = if (dark) "#dee2e6" else story_col$deep, dash = "dot", width = 1.5)) |>
    layout(barmode = "stack", bargap = 0.2,
           xaxis = list(title = "", dtick = 5),
           yaxis = list(title = "Thousand acre-feet"),
           margin = list(t = 30, b = 30)) |>
    style_plotly(dark, legend = c(legend_top, traceorder = "normal"))
}

#' Plain-language card for one reservoir.
reservoir_card <- function(r) {
  plain <- plain_status$plain[plain_status$class == r$class]
  tagList(
    tags$div(class = "card-kicker", "Reservoir · ", r$basin, " basin"),
    tags$h3(class = "card-title", r$name),
    tags$div(class = "card-status",
             tags$span(class = "tile", style = sprintf("background:%s", r$color)), plain),
    if (!is.na(r$storage_af)) {
      tags$p(sprintf("Holding %s on %s, %.0f%% of the %s it can store.",
                     fmt_af_words(r$storage_af), format(r$date, "%B %d"), r$pct_full,
                     fmt_af_words(r$capacity)),
             if (!is.na(r$p50_af))
               sprintf("On this date it is usually %.0f%% full.", 100 * r$p50_af / r$capacity))
    } else tags$p("No recent reading."),
    if (!is.na(r$water_source))
      tags$p(class = "card-note", paste0("Fed by the ", tools::toTitleCase(tolower(r$water_source)), "."))
  )
}

#' Plain-language card for one diversion, with its researched history.
diversion_card <- function(d, profile, vol) {
  meta <- list(Built = profile$built, Operator = profile$operator, Serves = profile$serves)
  meta <- meta[!vapply(meta, is.null, logical(1))]
  found <- isTRUE(profile$found)
  tagList(
    tags$div(class = "card-kicker",
             if (d$dir == "local") sprintf("Diversion · %s basin", d$from)
             else sprintf("Across basins · %s to %s", d$from, d$to)),
    tags$h3(class = "card-title", d$name),
    tags$div(class = "card-status",
             tags$span(class = "tile diamond", style = sprintf("background:%s", transfer_col[[d$dir]])),
             transfer_word[[d$dir]]),
    if (nrow(vol) > 0)
      tags$p(class = "card-vol",
             tags$strong(fmt_af_words(vol$af[nrow(vol)])),
             sprintf(" in water year %d", vol$wy[nrow(vol)]),
             if (nrow(vol) >= 5)
               sprintf(" (typically %s)", fmt_af_words(median(vol$af)))),
    if (found) tags$p(profile$summary)
    else tags$p(class = "card-note", "No published history found for this structure."),
    if (found && length(meta) > 0)
      tags$dl(class = "card-meta", lapply(names(meta), \(k) tagList(tags$dt(k), tags$dd(meta[[k]])))),
    if (found && length(profile$facts) > 0)
      tags$ul(class = "card-facts", lapply(profile$facts, tags$li)),
    if (found && length(profile$sources) > 0)
      tags$p(class = "card-note", "Sources: ",
             lapply(seq_along(profile$sources), \(i)
               tagList(if (i > 1) ", ",
                       tags$a(href = profile$sources[[i]], target = "_blank", .noWS = "outside",
                              sprintf("[%d]", i)))))
  )
}
