# One compact legend for the map: status colors shared by rivers, gages, and
# reservoirs, then the marker symbols. Styled by .map-legend in app.R.

library(htmltools)

#' Legend HTML for leaflet::addControl().
map_legend_html <- function(classes = flow_classes) {
  swatch <- function(style) tags$span(class = "sw", style = style)
  row <- function(sym, label) tags$div(class = "row-item", sym, tags$span(label))

  tags$div(
    class = "map-legend",
    tags$div(class = "lg-title", "Compared with this day in history"),
    tags$div(class = "lg-grid", lapply(seq_len(nrow(classes)), function(i) {
      row(swatch(sprintf("background:%s;", classes$color[i])), classes$short[i])
    })),
    tags$div(class = "lg-title mt", "Symbols"),
    tags$div(class = "lg-grid",
      row(swatch("background:#5fbf6a;border:1.5px solid #fff;box-shadow:0 0 0 1px #555;"),
          "Gauge"),
      row(swatch("background:#5fbf6a;border:2px solid #1f2d50;width:14px;height:14px;"),
          "Reservoir"),
      row(swatch("background:#6a3d9a;width:8px;height:8px;margin:0 3px;"),
          "Transbasin div."),
      row(swatch("background:#9e9e9e;width:8px;height:8px;margin:0 3px;"),
          "Other diversion")),
    tags$div(class = "lg-note", "Reservoirs sized by capacity. River colors are estimated from nearby gauges.")
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
