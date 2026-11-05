# One compact legend for the map: status colors shared by rivers, gages, and
# reservoirs, then the marker symbols. Styled by .map-legend in app.R.

library(htmltools)

#' SVG markup as a data URI for leaflet icons or legend images.
svg_uri <- function(svg) {
  paste0("data:image/svg+xml;utf8,", gsub("#", "%23", svg, fixed = TRUE))
}

#' Gauge symbol: a status-colored disc with a white ring and dark halo.
gauge_svg <- function(fill, size = 18) {
  c <- size / 2
  sprintf(paste0("<svg xmlns='http://www.w3.org/2000/svg' width='%s' height='%s'>",
                 "<circle cx='%s' cy='%s' r='%s' fill='%s' stroke='white' stroke-width='2'/>",
                 "<circle cx='%s' cy='%s' r='%s' fill='none' stroke='#1f2d50' stroke-width='1'/>",
                 "</svg>"),
          size, size, c, c, c - 2, fill, c, c, c - 0.6)
}

#' Reservoir symbol: a tank filled to its percent full in the status color.
reservoir_svg <- function(fill, pct_full, size = 22) {
  pct <- pmin(pmax(coalesce(pct_full, 0), 0), 100) / 100
  inner <- size - 6
  level <- inner * pct
  sprintf(paste0("<svg xmlns='http://www.w3.org/2000/svg' width='%s' height='%s'>",
                 "<rect x='2' y='2' width='%s' height='%s' rx='3' fill='white' ",
                 "stroke='#1f2d50' stroke-width='2'/>",
                 "<rect x='3' y='%s' width='%s' height='%s' fill='%s'/>",
                 "</svg>"),
          size, size, size - 4, size - 4,
          3 + inner - level, size - 6, level, fill)
}

#' Diversion symbol: a diamond, purple for transbasin and gray otherwise.
diversion_svg <- function(transbasin, size = ifelse(transbasin, 16, 12)) {
  c <- size / 2
  fill <- ifelse(transbasin, "#6a3d9a", "#8a8a8a")
  sprintf(paste0("<svg xmlns='http://www.w3.org/2000/svg' width='%s' height='%s'>",
                 "<rect x='%s' y='%s' width='%s' height='%s' transform='rotate(45 %s %s)' ",
                 "fill='%s' stroke='white' stroke-width='1.5'/></svg>"),
          size, size, c * 0.35, c * 0.35, c * 1.3, c * 1.3, c, c, fill)
}

#' Leaflet icons for the Map tab, one per row of points.
gauge_icons <- function(pts) {
  icons(iconUrl = svg_uri(gauge_svg(pts$color)), iconWidth = 18, iconHeight = 18)
}

reservoir_icons <- function(pts) {
  size <- round(pmin(16 + sqrt(pts$capacity) / 70, 36))
  icons(iconUrl = svg_uri(reservoir_svg(pts$color, pts$pct_full, size)),
        iconWidth = size, iconHeight = size)
}

diversion_icons <- function(pts) {
  tb <- pts$is_transbasin == "yes"
  size <- ifelse(tb, 16, 12)
  icons(iconUrl = svg_uri(diversion_svg(tb, size)), iconWidth = size, iconHeight = size)
}

#' Legend HTML for leaflet::addControl().
map_legend_html <- function(classes = flow_classes) {
  swatch <- function(style) tags$span(class = "sw", style = style)
  sym <- function(svg) tags$img(src = svg_uri(svg), class = "sym", alt = "")
  row <- function(sym, label) tags$div(class = "row-item", sym, tags$span(label))

  tags$div(
    class = "map-legend",
    tags$div(class = "lg-title", "Compared with this day in history"),
    tags$div(class = "lg-grid", lapply(seq_len(nrow(classes)), function(i) {
      row(swatch(sprintf("background:%s;", classes$color[i])), classes$short[i])
    })),
    tags$div(class = "lg-title mt", "Symbols"),
    tags$div(class = "lg-grid",
      row(sym(gauge_svg("#5fbf6a", 14)), "Gauge"),
      row(sym(reservoir_svg("#5fbf6a", 60, 16)), "Reservoir"),
      row(sym(diversion_svg(TRUE, 14)), "Transbasin div."),
      row(sym(diversion_svg(FALSE, 12)), "Other diversion")),
    tags$div(class = "lg-note", "Reservoirs sized by capacity and filled to percent full. River colors are estimated from nearby gauges.")
  )
}

#' Details card shown before anything is clicked: a statewide snapshot.
statewide_ui <- function(gages, reservoirs) {
  ranked <- filter(gages, class != "unranked")
  counts <- flow_classes |>
    filter(class != "unranked") |>
    left_join(count(ranked, class), by = "class") |>
    mutate(n = coalesce(n, 0L), pct = 100 * n / max(sum(n), 1))
  res <- filter(reservoirs, !is.na(storage_af))
  res_med <- filter(res, !is.na(p50_af))

  tagList(
    h5("Colorado today"),
    p(class = "small text-muted mb-2",
      sprintf("%d of %d gauges report a ranked flow.", nrow(ranked), nrow(gages))),
    div(class = "d-flex rounded overflow-hidden mb-1", style = "height: 14px;",
        lapply(seq_len(nrow(counts)), function(i) {
          if (counts$n[i] == 0) return(NULL)
          div(style = sprintf("width:%.1f%%;background:%s;", counts$pct[i], counts$color[i]),
              title = sprintf("%s: %d gauges", counts$short[i], counts$n[i]))
        })),
    p(class = "small text-muted mb-3",
      sprintf("%d below normal, %d normal, %d above normal.",
              sum(counts$n[counts$class %in% c("below", "much_below", "low")]),
              sum(counts$n[counts$class == "normal"]),
              sum(counts$n[counts$class %in% c("above", "much_above", "high")]))),
    div(class = "d-flex gap-4 mb-3",
        div(div(class = "fs-4 fw-semibold",
                sprintf("%.0f%%", 100 * sum(res$storage_af) / sum(res$capacity))),
            div(class = "small text-muted", "major reservoirs full")),
        div(div(class = "fs-4 fw-semibold",
                sprintf("%.0f%%", 100 * sum(res_med$storage_af) / sum(res_med$p50_af))),
            div(class = "small text-muted", "of median for the date"))),
    p(class = "small text-muted",
      sprintf("%s KAF stored in %d reservoirs.",
              format(round(sum(res$storage_af) / 1000), big.mark = ","), nrow(res))),
    hr(),
    p(class = "small text-muted mb-0",
      "Click a river, gauge, reservoir, or diversion for details.")
  )
}
