# Gage hydrograph joyplot: one ridge per year of daily discharge, with the
# current year drawn in front for comparison. Filters zoom to a year range
# and a window of months.

library(dplyr)
library(plotly)

# Month order for each year type (water years start in October)
month_order <- function(water_year) if (water_year) c(10:12, 1:9) else 1:12

#' Daily flow for one gage with year, day-in-year, and month columns.
#'
#' Water years start Oct 1 and are named for the calendar year they end in.
prep_ridges <- function(flows, water_year = FALSE, smooth_days = 1) {
  flows <- flows |>
    arrange(date) |>
    mutate(
      flow = if (smooth_days > 1) {
        as.numeric(stats::filter(flow_cfs, rep(1 / smooth_days, smooth_days),
                                 sides = 2))
      } else {
        flow_cfs
      },
      month = as.integer(format(date, "%m"))
    )

  if (water_year) {
    flows |>
      mutate(
        year = as.integer(format(date, "%Y")) + (month >= 10),
        day  = as.integer(date - as.Date(sprintf("%d-10-01", year - 1))) + 1
      )
  } else {
    flows |>
      mutate(year = as.integer(format(date, "%Y")),
             day  = as.integer(format(date, "%j")))
  }
}

#' Keep a year range and a contiguous window of months (in year-type order).
filter_ridges <- function(ridges, years, months, water_year = FALSE) {
  ord    <- month_order(water_year)
  window <- ord[seq(match(months[1], ord), match(months[2], ord))]
  ridges |>
    filter(year >= years[1], year <= years[2], month %in% window)
}

#' Plotly ridgeline of daily flow by year. Ridges are scaled to the largest
#' flow in the filtered window so zoomed views stay readable.
plot_ridges <- function(ridges, gage_name, water_year = FALSE, overlap = 2.5,
                        dark = FALSE) {
  years   <- sort(unique(ridges$year))
  current <- max(years)
  peak    <- max(ridges$flow, na.rm = TRUE)
  pal     <- viridisLite::mako(length(years), begin = 0.15, end = 0.85)

  ridges <- ridges |>
    mutate(base = match(year, rev(years)),
           top  = base + overlap * flow / peak)

  # Oldest first so newer ridges are drawn in front
  p <- plot_ly()
  for (i in seq_along(years)) {
    yr <- years[i]
    d  <- filter(ridges, year == yr)
    is_now <- yr == current
    fill   <- if (is_now) "#f28e2b" else pal[i]
    p <- p |>
      add_trace(data = d, x = ~day, y = ~base, type = "scatter",
                mode = "lines", line = list(width = 0), hoverinfo = "skip",
                showlegend = FALSE) |>
      add_trace(data = d, x = ~day, y = ~top, type = "scatter",
                mode = "lines", fill = "tonexty", fillcolor = fill,
                line = list(color = if (is_now) "#b35806" else "white",
                            width = if (is_now) 1.5 else 0.4),
                text = ~sprintf("%s<br>%s cfs", format(date, "%b %d, %Y"),
                                format(round(flow), big.mark = ",")),
                hoverinfo = "text", name = as.character(yr),
                showlegend = FALSE)
  }

  # Day-in-year of each month start, using a non-leap reference year
  ord     <- month_order(water_year)
  starts  <- as.Date(sprintf("%d-%02d-01", ifelse(water_year & ord >= 10, 2000, 2001), ord))
  origin  <- as.Date(if (water_year) "2000-10-01" else "2001-01-01")
  tick_at <- as.integer(starts - origin) + 1

  p |>
    layout(
      title = list(
        text = sprintf("%s<br><sup>Daily discharge by %s. %d in orange. Peak in view %s cfs.</sup>",
                       gage_name,
                       if (water_year) "water year" else "calendar year",
                       current, format(round(peak), big.mark = ",")),
        x = 0, xanchor = "left"
      ),
      xaxis = list(title = "", tickvals = tick_at, ticktext = month.abb[ord],
                   range = range(ridges$day)),
      yaxis = list(title = "", tickvals = seq_along(years),
                   ticktext = rev(years), tickfont = list(size = 10),
                   range = c(0.5, length(years) + overlap)),
      hovermode = "closest",
      margin = list(t = 70)
    ) |>
    style_plotly(dark)
}

joyplot_ui <- function(id, gages) {
  ns <- NS(id)
  bslib::layout_sidebar(
    sidebar = bslib::sidebar(
      selectInput(ns("gage"), "Gauge", choices = setNames(gages$id, gages$name)),
      radioButtons(ns("year_type"), "Year type", inline = TRUE,
                   choices = c("Calendar" = "cal", "Water year" = "wy")),
      sliderInput(ns("years"), "Years", min = 1990, max = 2026,
                  value = c(1990, 2026), step = 1, sep = ""),
      selectInput(ns("month_from"), "From month", choices = NULL),
      selectInput(ns("month_to"), "To month", choices = NULL),
      sliderInput(ns("smooth"), "Smoothing (days)", min = 1, max = 15,
                  value = 7, step = 2),
      helpText("Each ridge is one year of daily mean discharge, scaled to",
               "the largest daily flow in view. Water years run Oct 1 to",
               "Sep 30 and are named for the year they end in.")
    ),
    # Fixed to the viewport so fewer years means taller ridges
    plotlyOutput(ns("ridges"), height = "calc(100vh - 110px)")
  )
}

#' @param selected_gage reactive giving a gage id chosen elsewhere (the map).
#' @param dark reactive, TRUE when the app is in dark mode.
joyplot_server <- function(id, gages, selected_gage, dark) {
  moduleServer(id, function(input, output, session) {
    observeEvent(selected_gage(), {
      updateSelectInput(session, "gage", selected = selected_gage())
    }, ignoreNULL = TRUE)

    water_year <- reactive(input$year_type == "wy")

    # Month choices follow the year type, keeping a full-year default
    observeEvent(water_year(), {
      ord <- month_order(water_year())
      choices <- setNames(ord, month.name[ord])
      updateSelectInput(session, "month_from", choices = choices,
                        selected = ord[1])
      updateSelectInput(session, "month_to", choices = choices,
                        selected = ord[12])
    })

    flows <- reactive({
      req(input$gage)
      read_ds("streamflow_daily") |>
        filter(id == !!input$gage) |>
        select(date, flow_cfs) |>
        collect()
    })

    ridges_all <- reactive({
      prep_ridges(flows(), water_year = water_year(),
                  smooth_days = input$smooth)
    })

    # Year slider tracks the gage's record
    observeEvent(list(flows(), water_year()), {
      yrs <- range(ridges_all()$year)
      updateSliderInput(session, "years", min = yrs[1], max = yrs[2],
                        value = yrs)
    })

    ridges <- reactive({
      req(input$month_from, input$month_to)
      months <- as.integer(c(input$month_from, input$month_to))
      ord <- month_order(water_year())
      req(match(months[1], ord) <= match(months[2], ord))
      filter_ridges(ridges_all(), input$years, months, water_year())
    })

    output$ridges <- renderPlotly({
      validate(need(nrow(ridges()) > 0, "No data for this selection."))
      name <- gages$name[gages$id == input$gage]
      plot_ridges(ridges(), name, water_year = water_year(), dark = dark())
    })
  })
}
