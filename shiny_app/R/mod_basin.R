# Basin tab: basin-wide flow statistics and a simple water-year accounting of
# outflow at the outlet gage(s) against transbasin exports and imports.
# Volumes are in thousand acre-feet (KAF). Water years run Oct to Sep.

library(dplyr)
library(plotly)

# Structure basins are finer than the basin polygons
basin_alias <- c(Gunnison = "Colorado", Yampa = "Yampa/White")
to_basin <- function(x) coalesce(unname(basin_alias[x]), x)

kaf <- function(af) af / 1000
fmt_kaf <- function(af) {
  if (length(af) == 0 || is.na(af)) "n/a" else sprintf("%s KAF", format(round(kaf(af), 1), big.mark = ","))
}

#' Annual transbasin volumes by structure and water year, with polygon basins.
#'
#' Approved records lag about a year, so months without a record are filled
#' from provisional daily telemetry (cfs-days to acre-feet) and the year is
#' flagged provisional. CDSS records are sparse before ~2013 (about 30
#' structures report, versus about 45 after), so early totals undercount.
transfers_by_wy <- function(history, telemetry, structures) {
  records <- history |>
    filter(!is.na(diversion_af)) |>
    transmute(wdid, month_start, af = diversion_af, provisional = FALSE)

  tele <- telemetry |>
    mutate(month_start = as.Date(format(date, "%Y-%m-01"))) |>
    group_by(wdid, month_start) |>
    summarize(af = sum(discharge_cfs, na.rm = TRUE) * af_per_cfs_day,
              .groups = "drop") |>
    anti_join(records, by = c("wdid", "month_start")) |>
    mutate(provisional = TRUE)

  bind_rows(records, tele) |>
    mutate(wy = water_year(month_start)) |>
    group_by(wdid, wy) |>
    summarize(af = sum(af), provisional = any(provisional), .groups = "drop") |>
    inner_join(structures |>
                 transmute(wdid, name,
                           from = to_basin(source_basin),
                           to = to_basin(destination_basin)),
               by = "wdid") |>
    filter(from != to)
}

#' Water-year outflow (AF) summed across a basin's outlet gages. A year counts
#' only when every outlet gage has at least 330 days of data.
outflow_by_wy <- function(outlet_ids) {
  read_ds("streamflow_daily") |>
    filter(id %in% outlet_ids) |>
    select(id, date, flow_cfs) |>
    collect() |>
    mutate(wy = water_year(date)) |>
    group_by(id, wy) |>
    summarize(af = sum(flow_cfs, na.rm = TRUE) * af_per_cfs_day,
              days = sum(!is.na(flow_cfs)), .groups = "drop") |>
    group_by(wy) |>
    summarize(outflow_af = if (n() == length(outlet_ids) && all(days >= 330))
                sum(af) else NA_real_,
              .groups = "drop")
}

#' Date in each water year when half of the year's outflow has passed.
runoff_timing <- function(outlet_ids) {
  read_ds("streamflow_daily") |>
    filter(id %in% outlet_ids) |>
    select(id, date, flow_cfs) |>
    collect() |>
    group_by(date) |>
    summarize(q = sum(flow_cfs), n = n(), .groups = "drop") |>
    filter(n == length(outlet_ids), !is.na(q)) |>
    mutate(wy = water_year(date)) |>
    group_by(wy) |>
    filter(n() >= 330) |>
    arrange(date, .by_group = TRUE) |>
    summarize(day = which(cumsum(q) >= sum(q) / 2)[1], .groups = "drop") |>
    mutate(label = format(as.Date("2000-09-30") + day, "%b %d"))
}

basin_ui <- function(id, basin_names) {
  ns <- NS(id)
  bslib::layout_sidebar(
    sidebar = bslib::sidebar(
      width = 280,
      selectInput(ns("basin"), "Basin", choices = basin_names),
      selectInput(ns("wy"), "Water year", choices = NULL),
      uiOutput(ns("outlets")),
      helpText("Accounting is approximate: outflow is measured at the outlet",
               "gage(s), transfers come from CDSS diversion records, and",
               "consumptive use, storage changes, and ungaged tributaries are",
               "not included.")
    ),
    tags$style(".basin-vb .value-box-value { font-size: 1.4rem; }"),
    bslib::layout_column_wrap(
      width = 1 / 4, fill = FALSE, class = "basin-vb",
      vb("Outflow", ns("vb_out"), "water"),
      vb("Transbasin exports", ns("vb_exp"), "box-arrow-right"),
      vb("Transbasin imports", ns("vb_imp"), "box-arrow-in-left"),
      vb("Share of yield exported", ns("vb_share"), "pie-chart")
    ),
    bslib::layout_columns(
      col_widths = c(7, 5),
      bslib::card(bslib::card_header("Water-year accounting"),
                  plotlyOutput(ns("accounting"), height = "320px")),
      bslib::card(bslib::card_header("Transbasin flows, selected year"),
                  plotlyOutput(ns("sankey"), height = "320px"))
    ),
    bslib::layout_columns(
      col_widths = c(5, 7),
      bslib::card(bslib::card_header("Runoff timing at the outlet"),
                  plotlyOutput(ns("timing"), height = "300px")),
      bslib::card(bslib::card_header("Gages in this basin today"),
                  uiOutput(ns("gage_table")))
    )
  )
}

#' @param gage_status gage points with latest flow, flow class, and basin.
basin_server <- function(id, outlets, transfers, gage_status, dark) {
  moduleServer(id, function(input, output, session) {
    outlet_ids <- reactive(filter(outlets, basin == input$basin)$gage_id)

    outflow <- reactive(outflow_by_wy(outlet_ids()))

    accounts <- reactive({
      exp <- transfers |> filter(from == input$basin) |>
        group_by(wy) |> summarize(export_af = sum(af), p_exp = any(provisional),
                                  n_exp = n_distinct(wdid))
      imp <- transfers |> filter(to == input$basin) |>
        group_by(wy) |> summarize(import_af = sum(af), p_imp = any(provisional),
                                  n_imp = n_distinct(wdid))
      out <- outflow()
      first_wy <- min(out$wy[!is.na(out$outflow_af)], Inf)
      out |>
        full_join(exp, by = "wy") |>
        full_join(imp, by = "wy") |>
        filter(wy >= first_wy, wy < water_year(Sys.Date())) |>
        mutate(across(c(export_af, import_af), \(x) coalesce(x, 0)),
               provisional = coalesce(p_exp, FALSE) | coalesce(p_imp, FALSE),
               share = export_af / (outflow_af + export_af)) |>
        arrange(wy)
    })

    # Water-year choices: complete years with outflow, newest first
    observeEvent(accounts(), {
      yrs <- rev(accounts()$wy[!is.na(accounts()$outflow_af)])
      updateSelectInput(session, "wy", choices = yrs, selected = yrs[1])
    })

    sel <- reactive({
      req(input$wy)
      filter(accounts(), wy == as.integer(input$wy))
    })

    # Medians use only years with data; many transfer records start ~2010
    pct_of_median <- function(x, col) {
      v <- accounts()[[col]]
      med <- median(v[!is.na(v) & v > 0])
      if (is.na(x) || is.na(med) || med == 0) "" else
        sprintf("%.0f%% of median (%s)", 100 * x / med, fmt_kaf(med))
    }

    output$outlets <- renderUI({
      o <- filter(outlets, basin == input$basin)
      tagList(tags$label("Outlet gage(s)"),
              tags$ul(class = "small", lapply(o$note, tags$li)))
    })

    output$vb_out <- renderText(fmt_kaf(sel()$outflow_af))
    output$vb_out_note <- renderText(pct_of_median(sel()$outflow_af, "outflow_af"))
    output$vb_exp <- renderText(fmt_kaf(sel()$export_af))
    output$vb_exp_note <- renderText(pct_of_median(sel()$export_af, "export_af"))
    output$vb_imp <- renderText(fmt_kaf(sel()$import_af))
    output$vb_imp_note <- renderText(pct_of_median(sel()$import_af, "import_af"))
    output$vb_share <- renderText({
      if (is.na(sel()$share)) "n/a" else sprintf("%.1f%%", 100 * sel()$share)
    })
    output$vb_share_note <- renderText({
      paste0("Exports / (outflow + exports)",
             if (isTRUE(sel()$provisional)) ". Transfers partly provisional." else "")
    })

    output$accounting <- renderPlotly({
      a <- accounts()
      validate(need(nrow(a) > 0, "No accounting data for this basin."))
      p <- plot_ly(a, x = ~wy) |>
        add_bars(y = ~kaf(outflow_af), name = "Outflow at outlet",
                 marker = list(color = "#31688e"),
                 hovertemplate = "WY %{x} outflow: %{y:,.1f} KAF<extra></extra>") |>
        add_bars(y = ~kaf(export_af), name = "Transbasin exports",
                 marker = list(color = "#f28e2b",
                               pattern = list(shape = ifelse(a$provisional, "/", ""))),
                 customdata = ~coalesce(n_exp, 0L),
                 hovertemplate = "WY %{x} exports: %{y:,.1f} KAF (%{customdata} structures reporting)<extra></extra>")
      if (any(a$import_af > 0)) {
        p <- p |>
          add_bars(y = ~-kaf(import_af), name = "Transbasin imports (shown below zero)",
                   marker = list(color = "#35b779"),
                   hovertemplate = "WY %{x} imports: %{customdata[0]:,.1f} KAF (%{customdata[1]} structures reporting)<extra></extra>",
                   customdata = ~mapply(c, kaf(import_af), coalesce(n_imp, 0L), SIMPLIFY = FALSE))
      }
      p |>
        add_lines(y = ~100 * share, yaxis = "y2", name = "Share exported",
                  line = list(color = "#b35806", width = 1.5),
                  hovertemplate = "WY %{x} exported: %{y:.1f}%<extra></extra>") |>
        layout(barmode = "relative",
               xaxis = list(title = if (any(a$provisional))
                 "Water year (hatched: transfers partly from provisional telemetry)"
                 else "Water year"),
               yaxis = list(title = "Thousand acre-feet"),
               yaxis2 = list(title = "% exported", overlaying = "y", side = "right",
                             rangemode = "tozero", showgrid = FALSE),
               hovermode = "x unified",
               legend = list(orientation = "h", y = -0.4),
               margin = list(b = 90)) |>
        style_plotly(dark())
    })

    # Basin-to-basin Sankey for the selected water year, structures on hover
    output$sankey <- renderPlotly({
      t <- transfers |>
        filter(wy == as.integer(input$wy),
               from == input$basin | to == input$basin, af > 0)
      validate(need(nrow(t) > 0, "No transbasin diversions into or out of this basin this year."))
      links <- t |>
        arrange(desc(af)) |>
        group_by(from, to) |>
        summarize(
          detail = paste(sprintf("%s: %s", name, fmt_vec(af)), collapse = "<br>"),
          af = sum(af), .groups = "drop"
        )
      nodes <- unique(c(links$from, links$to))
      plot_ly(
        type = "sankey", arrangement = "snap",
        node = list(label = paste(nodes, "basin"), pad = 15, thickness = 16,
                    color = ifelse(nodes == input$basin, "#31688e", "#9e9e9e")),
        link = list(source = match(links$from, nodes) - 1,
                    target = match(links$to, nodes) - 1,
                    value = kaf(links$af), customdata = links$detail,
                    color = ifelse(links$from == input$basin,
                                   "rgba(242,142,43,0.45)", "rgba(53,183,121,0.45)"),
                    hovertemplate = paste0("%{source.label} to %{target.label}: ",
                                           "%{value:,.1f} KAF<br>%{customdata}<extra></extra>"))
      ) |>
        layout(title = list(text = sprintf("WY %s, thousand acre-feet. Hover for structures.", input$wy),
                            font = list(size = 11), x = 0),
               margin = list(t = 30, l = 5, r = 5, b = 5)) |>
        style_plotly(dark())
    })

    output$timing <- renderPlotly({
      tm <- runoff_timing(outlet_ids())
      validate(need(nrow(tm) >= 5, "Not enough complete years at the outlet."))
      fit <- lm(day ~ wy, data = tm)
      slope <- coef(fit)[["wy"]] * 10
      tm$fit <- fitted(fit)
      plot_ly(tm, x = ~wy) |>
        add_markers(y = ~day, name = "Half of annual flow passed",
                    marker = list(color = "#31688e", size = 7),
                    text = ~sprintf("WY %d: %s", wy, label), hoverinfo = "text") |>
        add_lines(y = ~fit, name = sprintf("Trend: %+.1f days per decade", slope),
                  line = list(color = "#f28e2b", dash = "dash"), hoverinfo = "skip") |>
        layout(xaxis = list(title = "Water year"),
               yaxis = list(title = "", tickvals = c(1, 32, 62, 93, 124, 152, 183, 213, 244, 274, 305, 336),
                            ticktext = month.abb[c(10:12, 1:9)]),
               legend = list(orientation = "h", y = -0.35),
               margin = list(b = 80)) |>
        style_plotly(dark())
    })

    output$gage_table <- renderUI({
      g <- gage_status |> filter(basin == input$basin) |>
        arrange(desc(id %in% outlet_ids()), name)
      if (nrow(g) == 0) return(p(class = "text-muted", "No gages."))
      tags$div(
        class = "table-responsive", style = "max-height: 300px; overflow-y: auto;",
        tags$table(
          class = "table table-sm small align-middle",
          tags$thead(tags$tr(tags$th(""), tags$th("Gage"), tags$th("Latest"),
                             tags$th("% of median"), tags$th("Status"))),
          tags$tbody(lapply(seq_len(nrow(g)), function(i) {
            x <- g[i, ]
            tags$tr(
              tags$td(tags$span(style = sprintf(
                "display:inline-block;width:11px;height:11px;border-radius:50%%;background:%s;border:1px solid #333;",
                x$color))),
              tags$td(x$name, if (x$id %in% outlet_ids()) tags$span(class = "badge bg-secondary ms-1", "outlet")),
              tags$td(if (is.na(x$flow_cfs)) "n/a" else sprintf("%s cfs", format(round(x$flow_cfs), big.mark = ","))),
              tags$td(if (is.na(x$p50_cfs) || x$p50_cfs == 0 || is.na(x$flow_cfs)) "" else
                sprintf("%.0f%%", 100 * x$flow_cfs / x$p50_cfs)),
              tags$td(x$label)
            )
          }))
        )
      )
    })
  })
}
