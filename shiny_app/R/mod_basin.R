# Basin tab: basin-wide flow statistics and a simple water-year accounting of
# outflow at the outlet gage(s), transbasin exports and imports, change in
# major reservoir storage, and basin climate (gridMET).
# Volumes are in thousand acre-feet (KAF). Water years run Oct to Sep.

library(dplyr)
library(plotly)

# Structure basins are finer than the basin polygons
basin_alias <- c(Gunnison = "Colorado", Yampa = "Yampa/White")
to_basin <- function(x) coalesce(unname(basin_alias[x]), x)

kaf <- function(af) af / 1000
fmt_ratio <- function(r) if (r >= 10) sprintf("%.0fx", r) else sprintf("%.0f%%", 100 * r)
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

af_per_mm_km2 <- 0.8107
inches <- function(mm) mm / 25.4
to_f <- function(c) c * 9 / 5 + 32

#' Water-year climate per basin from the basin-mean daily series:
#' precipitation and reference ET depth (mm), precipitation volume (AF), mean
#' temperature, and mean vapor pressure deficit. Only complete water years.
climate_by_wy <- function(climate, zones) {
  if (is.null(climate) || is.null(zones)) {
    return(tibble::tibble(basin = character(), wy = integer(), prcp_mm = numeric(),
                          prcp_af = numeric(), eto_mm = numeric(),
                          tmean_c = numeric(), vpd_kpa = numeric()))
  }
  climate |>
    mutate(wy = water_year(date)) |>
    group_by(basin, wy) |>
    summarize(prcp_mm = sum(prcp_mm), eto_mm = sum(eto_mm),
              tmean_c = mean((tmax_c + tmin_c) / 2), vpd_kpa = mean(vpd_kpa),
              days = n(), .groups = "drop") |>
    filter(days >= 360) |>
    left_join(select(zones, basin = zone_id, area_km2), by = "basin") |>
    mutate(prcp_af = prcp_mm * area_km2 * af_per_mm_km2) |>
    select(-days, -area_km2)
}

#' Position of a date within a generic water year (Oct 1999 to Sep 2000), so
#' different years share one axis. Accepts dates or "mm-dd" strings.
wy_axis_date <- function(mmdd) {
  if (inherits(mmdd, "Date")) mmdd <- format(mmdd, "%m-%d")
  as.Date(paste0(if_else(substr(mmdd, 1, 2) >= "10", "1999-", "2000-"), mmdd))
}

basin_ui <- function(id, basin_names) {
  ns <- NS(id)
  bslib::layout_sidebar(
    fillable = FALSE,
    sidebar = bslib::sidebar(
      width = 280,
      selectInput(ns("basin"), "Basin", choices = basin_names),
      selectInput(ns("wy"), "Water year", choices = NULL),
      uiOutput(ns("outlets")),
      helpText("Accounting is approximate: outflow is measured at the outlet",
               "gage(s), transfers come from CDSS diversion records, storage",
               "change covers only the major reservoirs on the map, and",
               "consumptive use and ungaged tributaries are not included.")
    ),
    tags$style(".basin-vb .value-box-value { font-size: 1.25rem; }
                .basin-vb .value-box-title { font-size: 0.85rem; }"),
    bslib::layout_column_wrap(
      width = 1 / 6, fill = FALSE, class = "basin-vb",
      vb("Precipitation", ns("vb_pcp"), "cloud-rain"),
      vb("Outflow", ns("vb_out"), "water"),
      vb("Transbasin exports", ns("vb_exp"), "box-arrow-right"),
      vb("Transbasin imports", ns("vb_imp"), "box-arrow-in-left"),
      vb("Share of yield exported", ns("vb_share"), "pie-chart"),
      vb("Reservoir storage today", ns("vb_sto"), "droplet-half")
    ),
    bslib::card(
      bslib::card_header("Water-year accounting"),
      plotlyOutput(ns("accounting"), height = "380px"),
      bslib::card_footer(class = "small text-muted",
                         "Outflow, exports, and storage gain stack to roughly the basin's",
                         "yield; imports sit below zero. Hatched exports use provisional telemetry.")
    ),
    bslib::card(
      bslib::card_header("Precipitation and runoff"),
      plotlyOutput(ns("precip"), height = "320px"),
      bslib::card_footer(class = "small text-muted",
                         "Basin-mean water-year totals from gridMET (4 km grid). Reference ET is",
                         "what a well-watered grass surface would use, a measure of atmospheric",
                         "demand, not actual water use. Runoff ratio is outflow plus exports minus",
                         "imports, divided by precipitation volume; it is approximate where an",
                         "outlet gage also carries out-of-state inflow or misses part of the basin,",
                         "and is left blank where imports exceed outflow.")
    ),
    bslib::layout_columns(
      col_widths = c(6, 6),
      bslib::card(
        bslib::card_header(
          class = "d-flex justify-content-between align-items-center",
          "Water year to date",
          radioButtons(ns("cum_var"), NULL, inline = TRUE,
                       choices = c("Precipitation" = "prcp", "Reference ET" = "eto"))
        ),
        plotlyOutput(ns("cumulative"), height = "340px"),
        bslib::card_footer(class = "small text-muted",
                           "Running total since October 1 against the range of past water years.",
                           "The last two months or so of gridMET are provisional.")
      ),
      bslib::card(
        bslib::card_header("Temperature and vapor pressure deficit"),
        plotlyOutput(ns("temperature"), height = "340px"),
        bslib::card_footer(class = "small text-muted",
                           "Water-year means. Vapor pressure deficit is how much more moisture the",
                           "air could hold; higher values dry out soils and snowpack faster.")
      )
    ),
    bslib::layout_columns(
      col_widths = c(6, 6),
      bslib::card(bslib::card_header("Transbasin structures, selected year"),
                  plotlyOutput(ns("sankey"), height = "340px")),
      bslib::card(bslib::card_header("Runoff timing at the outlet"),
                  plotlyOutput(ns("timing"), height = "340px"))
    ),
    bslib::layout_columns(
      col_widths = c(6, 6),
      bslib::card(bslib::card_header("Gages in this basin today"),
                  uiOutput(ns("gage_table"))),
      bslib::card(bslib::card_header("Reservoirs in this basin today"),
                  uiOutput(ns("res_table")))
    )
  )
}

#' Colored status dot used in the gage and reservoir tables.
status_dot <- function(color) {
  tags$span(style = sprintf(
    "display:inline-block;width:10px;height:10px;border-radius:50%%;background:%s;margin-right:6px;",
    color))
}

#' @param gage_status gage points with latest flow, flow class, and basin.
#' @param res_status reservoir points from reservoir_status() with basin.
#' @param storage water-year storage change per basin from storage_by_wy().
#' @param climate_wy water-year climate per basin from climate_by_wy().
#' @param climate daily basin-mean climate (basin, date, prcp_mm, eto_mm, ...).
#' @param climate_stats running water-year total percentiles by basin and mmdd.
basin_server <- function(id, outlets, transfers, gage_status, res_status,
                         storage, climate_wy, climate, climate_stats, dark) {
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
      sto <- storage |> filter(basin == input$basin) |> select(-basin)
      pcp <- climate_wy |> filter(basin == input$basin) |> select(-basin)
      out <- outflow()
      first_wy <- min(out$wy[!is.na(out$outflow_af)], Inf)
      out |>
        full_join(exp, by = "wy") |>
        full_join(imp, by = "wy") |>
        left_join(sto, by = "wy") |>
        left_join(pcp, by = "wy") |>
        filter(wy >= first_wy, wy < water_year(Sys.Date())) |>
        mutate(across(c(export_af, import_af), \(x) coalesce(x, 0)),
               provisional = coalesce(p_exp, FALSE) | coalesce(p_imp, FALSE),
               # No transfer records at all that year: share is unknown, not 0
               share = if_else(export_af == 0 & import_af == 0, NA_real_,
                               export_af / (outflow_af + export_af)),
               # Negative where imports exceed outflow (South Platte): not a
               # runoff ratio, so leave it blank
               yield_af = outflow_af + export_af - import_af,
               runoff_ratio = if_else(yield_af > 0, yield_af / prcp_af, NA_real_)) |>
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
        sprintf("%s of median (%s)", fmt_ratio(x / med), fmt_kaf(med))
    }

    output$outlets <- renderUI({
      o <- filter(outlets, basin == input$basin)
      tagList(tags$label("Outlet gage(s)"),
              tags$ul(class = "small", lapply(o$note, tags$li)))
    })

    output$vb_pcp <- renderText({
      if (is.na(sel()$prcp_mm)) "n/a" else sprintf("%.1f in", inches(sel()$prcp_mm))
    })
    output$vb_pcp_note <- renderText({
      if (is.na(sel()$prcp_mm)) return("")
      med <- median(accounts()$prcp_mm, na.rm = TRUE)
      sprintf("%.0f%% of median (%.1f in)", 100 * sel()$prcp_mm / med, inches(med))
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
      paste0("of outflow plus exports",
             if (isTRUE(sel()$provisional)) " (partly provisional)" else "")
    })

    res_now <- reactive(filter(res_status, basin == input$basin, !is.na(storage_af)))

    output$vb_sto <- renderText({
      r <- res_now()
      if (nrow(r) == 0) return("n/a")
      sprintf("%.0f%% full", 100 * sum(r$storage_af) / sum(r$capacity))
    })
    output$vb_sto_note <- renderText({
      r <- res_now()
      if (nrow(r) == 0) return("No mapped reservoirs")
      m <- filter(r, !is.na(p50_af))
      paste0(fmt_kaf(sum(r$storage_af)), " in ", nrow(r), " reservoirs",
             if (nrow(m) > 0) sprintf(", %.0f%% of median", 100 * sum(m$storage_af) / sum(m$p50_af)))
    })

    output$accounting <- renderPlotly({
      a <- accounts()
      validate(need(nrow(a) > 0, "No accounting data for this basin."))
      p <- plot_ly(a, x = ~wy) |>
        add_bars(y = ~kaf(outflow_af), name = "Outflow",
                 marker = list(color = "#31688e"),
                 hovertemplate = "WY %{x} outflow: %{y:,.1f} KAF<extra></extra>") |>
        add_bars(y = ~kaf(export_af), name = "Exports",
                 marker = list(color = "#f28e2b",
                               pattern = list(shape = ifelse(a$provisional, "/", ""))),
                 customdata = ~coalesce(n_exp, 0L),
                 hovertemplate = "WY %{x} exports: %{y:,.1f} KAF (%{customdata} structures reporting)<extra></extra>")
      if (any(a$import_af > 0)) {
        p <- p |>
          add_bars(y = ~-kaf(import_af), name = "Imports",
                   marker = list(color = "#35b779"),
                   hovertemplate = "WY %{x} imports: %{customdata[0]:,.1f} KAF (%{customdata[1]} structures reporting)<extra></extra>",
                   customdata = ~mapply(c, kaf(import_af), coalesce(n_imp, 0L), SIMPLIFY = FALSE))
      }
      if (any(!is.na(a$storage_change_af))) {
        p <- p |>
          add_bars(y = ~kaf(storage_change_af), name = "Storage change",
                   marker = list(color = "rgba(140,107,177,0.75)"),
                   customdata = ~coalesce(n_res, 0L),
                   hovertemplate = "WY %{x} storage change: %{y:+,.1f} KAF (%{customdata} reservoirs)<extra></extra>")
      }
      p |>
        add_lines(y = ~100 * share, yaxis = "y2", name = "Share exported", connectgaps = FALSE,
                  line = list(color = "#b35806", width = 1.5),
                  hovertemplate = "WY %{x} exported: %{y:.1f}%<extra></extra>") |>
        layout(barmode = "relative", bargap = 0.15,
               xaxis = list(title = ""),
               yaxis = list(title = "Thousand acre-feet", zeroline = TRUE),
               yaxis2 = list(title = "% exported", overlaying = "y", side = "right",
                             rangemode = "tozero", showgrid = FALSE, ticksuffix = "%"),
               hovermode = "x unified",
               margin = list(t = 30, r = 50, b = 30)) |>
        style_plotly(dark(), legend = legend_top)
    })

    output$precip <- renderPlotly({
      a <- filter(accounts(), !is.na(prcp_mm))
      validate(need(nrow(a) > 0, "No precipitation data for this basin."))
      med <- inches(median(a$prcp_mm))
      picked <- a$wy == as.integer(input$wy)
      plot_ly(a, x = ~wy) |>
        add_bars(y = ~inches(prcp_mm), name = "Precipitation",
                 marker = list(color = ifelse(picked, "#440154", "#21908c")),
                 customdata = ~kaf(prcp_af),
                 hovertemplate = "WY %{x} precipitation: %{y:.1f} in (%{customdata:,.0f} KAF)<extra></extra>") |>
        add_lines(y = rep(med, nrow(a)), name = sprintf("Median, %.1f in", med),
                  line = list(color = "#888", dash = "dash", width = 1.5),
                  hoverinfo = "skip") |>
        add_lines(y = ~inches(eto_mm), name = "Reference ET",
                  line = list(color = "#fde725", width = 2),
                  hovertemplate = "WY %{x} reference ET: %{y:.1f} in<extra></extra>") |>
        add_lines(y = ~100 * runoff_ratio, yaxis = "y2", name = "Runoff ratio",
                  connectgaps = FALSE, line = list(color = "#f28e2b", width = 1.5),
                  hovertemplate = "WY %{x} runoff ratio: %{y:.0f}%<extra></extra>") |>
        layout(bargap = 0.15,
               xaxis = list(title = ""),
               yaxis = list(title = "Inches", rangemode = "tozero"),
               yaxis2 = list(title = "Runoff ratio", overlaying = "y", side = "right",
                             rangemode = "tozero", showgrid = FALSE, ticksuffix = "%"),
               hovermode = "x unified",
               margin = list(t = 30, r = 50, b = 30)) |>
        style_plotly(dark(), legend = legend_top)
    })

    # Running total for the selected and current water years over the
    # percentile range of past years
    output$cumulative <- renderPlotly({
      validate(need(!is.null(climate) && !is.null(climate_stats),
                    "No climate data. Run the gridMET backfill and build_flow_stats."))
      col <- paste0(input$cum_var, "_mm")
      label <- if (input$cum_var == "prcp") "precipitation" else "reference ET"
      st <- climate_stats |>
        filter(basin == input$basin, variable == paste0(input$cum_var, "_wy_mm"),
               mmdd != "02-29") |>
        mutate(x = wy_axis_date(mmdd)) |>
        arrange(x)
      validate(need(nrow(st) > 0, "No climate statistics for this basin."))

      now_wy <- water_year(Sys.Date())
      years <- unique(c(as.integer(input$wy), now_wy))
      d <- climate |>
        filter(basin == input$basin) |>
        mutate(wy = water_year(date)) |>
        filter(wy %in% years, format(date, "%m-%d") != "02-29") |>
        arrange(date) |>
        mutate(total = cumsum(.data[[col]]), x = wy_axis_date(date), .by = wy)

      p <- plot_ly() |>
        add_ribbons(data = st, x = ~x, ymin = ~inches(p10), ymax = ~inches(p90),
                    name = "10th to 90th percentile", line = list(width = 0),
                    fillcolor = "rgba(33,144,140,0.18)", hoverinfo = "skip") |>
        add_ribbons(data = st, x = ~x, ymin = ~inches(p25), ymax = ~inches(p75),
                    name = "25th to 75th", line = list(width = 0),
                    fillcolor = "rgba(33,144,140,0.32)", hoverinfo = "skip") |>
        add_lines(data = st, x = ~x, y = ~inches(p50), name = "Median",
                  line = list(color = "#21908c", dash = "dash", width = 1.5),
                  hovertemplate = "%{x|%b %d} median: %{y:.1f} in<extra></extra>")
      colors <- c("#440154", "#f28e2b")
      for (i in seq_along(years)) {
        di <- filter(d, wy == years[i])
        if (nrow(di) == 0) next
        nm <- sprintf("WY %d%s", years[i], if (years[i] == now_wy) " to date" else "")
        p <- p |>
          add_lines(data = di, x = ~x, y = ~inches(total), name = nm,
                    line = list(color = colors[i], width = 2.5),
                    hovertemplate = paste0("%{x|%b %d} ", nm, ": %{y:.1f} in<extra></extra>"))
      }
      p |>
        layout(xaxis = list(title = "", tickformat = "%b", dtick = "M1",
                            range = as.character(as.Date(c("1999-10-01", "2000-09-30")))),
               yaxis = list(title = paste("Inches of", label), rangemode = "tozero"),
               hovermode = "x unified",
               margin = list(t = 30, b = 30)) |>
        style_plotly(dark(), legend = legend_top)
    })

    output$temperature <- renderPlotly({
      a <- filter(accounts(), !is.na(tmean_c))
      validate(need(nrow(a) > 0, "No climate data for this basin."))
      picked <- a$wy == as.integer(input$wy)
      fit <- lm(to_f(tmean_c) ~ wy, data = a)
      plot_ly(a, x = ~wy) |>
        add_trace(y = ~to_f(tmean_c), name = "Mean temperature",
                  type = "scatter", mode = "lines+markers",
                  line = list(color = "#31688e", width = 1.5),
                  marker = list(color = ifelse(picked, "#440154", "#31688e"),
                                size = ifelse(picked, 11, 6)),
                  hovertemplate = "WY %{x} mean temperature: %{y:.1f} \u00b0F<extra></extra>") |>
        add_lines(y = fitted(fit),
                  name = sprintf("Trend: %+.1f \u00b0F per decade", coef(fit)[["wy"]] * 10),
                  line = list(color = "#31688e", dash = "dash", width = 1),
                  hoverinfo = "skip") |>
        add_lines(y = ~vpd_kpa, yaxis = "y2", name = "Vapor pressure deficit",
                  line = list(color = "#f28e2b", width = 1.5),
                  hovertemplate = "WY %{x} VPD: %{y:.2f} kPa<extra></extra>") |>
        layout(xaxis = list(title = ""),
               yaxis = list(title = "\u00b0F"),
               yaxis2 = list(title = "kPa", overlaying = "y", side = "right",
                             showgrid = FALSE),
               hovermode = "x unified",
               margin = list(t = 30, r = 50, b = 30)) |>
        style_plotly(dark(), legend = legend_top)
    })

    # Each transbasin structure into or out of the basin, largest first
    output$sankey <- renderPlotly({
      t <- transfers |>
        filter(wy == as.integer(input$wy),
               from == input$basin | to == input$basin, af > 0) |>
        mutate(dir = if_else(from == input$basin, "Export", "Import"),
               other = if_else(dir == "Export", to, from),
               label = sprintf("%s  <span style='color:#888'>%s %s</span>", name,
                               if_else(dir == "Export", "to", "from"), other)) |>
        arrange(af)
      validate(need(nrow(t) > 0, "No transbasin diversions into or out of this basin this year."))
      plot_ly(t, x = ~kaf(af), y = ~factor(label, levels = label), type = "bar",
              orientation = "h", color = ~dir,
              colors = c(Export = "#f28e2b", Import = "#35b779"),
              text = ~sprintf("%s: %s", name, fmt_vec(af)), hoverinfo = "text",
              textposition = "none") |>
        layout(xaxis = list(title = "Thousand acre-feet"),
               yaxis = list(title = "", automargin = TRUE, tickfont = list(size = 11)),
               margin = list(t = 30, l = 10, r = 10, b = 40)) |>
        style_plotly(dark(), legend = legend_top)
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
        layout(xaxis = list(title = ""),
               yaxis = list(title = "Date half of the year's flow passed",
                            tickvals = c(1, 32, 62, 93, 124, 152, 183, 213, 244, 274, 305, 336),
                            ticktext = paste(month.abb[c(10:12, 1:9)], "1"),
                            range = range(tm$day) + c(-12, 12)),
               margin = list(t = 30, b = 30)) |>
        style_plotly(dark(), legend = legend_top)
    })

    output$gage_table <- renderUI({
      g <- gage_status |> filter(basin == input$basin) |>
        arrange(desc(id %in% outlet_ids()), name)
      if (nrow(g) == 0) return(p(class = "text-muted", "No gages."))
      status_table(
        c("Gage", "Latest", "% of median", "Status"),
        lapply(seq_len(nrow(g)), function(i) {
          x <- g[i, ]
          list(
            tagList(x$name, if (x$id %in% outlet_ids())
              tags$span(class = "badge text-bg-light border ms-1", "outlet")),
            if (is.na(x$flow_cfs)) "n/a" else sprintf("%s cfs", fmt_num(x$flow_cfs)),
            if (is.na(x$p50_cfs) || x$p50_cfs == 0 || is.na(x$flow_cfs)) "" else
              fmt_ratio(x$flow_cfs / x$p50_cfs),
            tagList(status_dot(x$color), x$short)
          )
        })
      )
    })

    output$res_table <- renderUI({
      r <- res_status |> filter(basin == input$basin) |> arrange(desc(capacity))
      if (nrow(r) == 0) return(p(class = "text-muted", "No mapped reservoirs."))
      status_table(
        c("Reservoir", "Storage", "Full", "% of median", "Status"),
        lapply(seq_len(nrow(r)), function(i) {
          x <- r[i, ]
          stale <- !is.na(x$date) && x$date < Sys.Date() - 30
          list(
            tagList(x$name, if (stale) tags$div(class = "text-muted", style = "font-size: 0.75rem;",
                                                 "as of ", format(x$date, "%b %Y"))),
            if (is.na(x$storage_af)) "n/a" else sprintf("%s KAF", format(round(kaf(x$storage_af), 1), nsmall = 1, big.mark = ",")),
            if (is.na(x$pct_full)) "" else fill_bar(x$pct_full),
            if (is.na(x$pct_median)) "" else sprintf("%.0f%%", x$pct_median),
            tagList(status_dot(x$color), x$short)
          )
        })
      )
    })
  })
}

#' Compact scrolling table; numeric columns and status stay on one line.
status_table <- function(header, rows) {
  tags$div(
    class = "table-responsive", style = "max-height: 320px; overflow-y: auto;",
    tags$table(
      class = "table table-sm table-hover small align-middle mb-0",
      tags$thead(class = "sticky-top", tags$tr(lapply(header, tags$th))),
      tags$tbody(lapply(rows, function(r) {
        tags$tr(tags$td(r[[1]]),
                lapply(r[-1], \(v) tags$td(class = "text-nowrap", v)))
      }))
    )
  )
}

#' Small horizontal bar for percent full.
fill_bar <- function(pct) {
  tags$div(class = "d-flex align-items-center gap-1",
           tags$div(class = "progress", style = "width: 48px; height: 6px;",
                    tags$div(class = "progress-bar",
                             style = sprintf("width:%.0f%%;background:#31688e;", min(pct, 100)))),
           sprintf("%.0f%%", pct))
}
