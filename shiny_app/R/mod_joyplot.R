# Gage hydrograph joyplot: one ridge per year of daily discharge, with the
# current year drawn on top for comparison.

library(ggplot2)
library(dplyr)

#' Daily flow for one gage with year and day-of-year columns.
#'
#' Water years start Oct 1 and are named for the calendar year they end in.
prep_ridges <- function(flows, water_year = FALSE, smooth_days = 1) {
  flows <- flows |>
    arrange(date) |>
    mutate(flow = if (smooth_days > 1) {
      as.numeric(stats::filter(flow_cfs, rep(1 / smooth_days, smooth_days), sides = 2))
    } else {
      flow_cfs
    })

  if (water_year) {
    flows |>
      mutate(
        year  = as.integer(format(date, "%Y")) + (as.integer(format(date, "%m")) >= 10),
        start = as.Date(sprintf("%d-10-01", year - 1)),
        day   = as.integer(date - start) + 1
      )
  } else {
    flows |>
      mutate(year = as.integer(format(date, "%Y")),
             day  = as.integer(format(date, "%j")))
  }
}

#' Ridgeline plot of daily flow by year.
plot_ridges <- function(ridges, gage_name, water_year = FALSE, overlap = 2.5) {
  current <- max(ridges$year)
  peak    <- max(ridges$flow, na.rm = TRUE)
  years   <- sort(unique(ridges$year), decreasing = TRUE)

  ridges <- ridges |>
    mutate(base = match(year, years),
           top  = base + overlap * flow / peak)

  month_starts <- if (water_year) {
    c(1, 32, 62, 93, 124, 152, 183, 213, 244, 274, 305, 336)
  } else {
    c(1, 32, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335)
  }
  month_labels <- if (water_year) month.abb[c(10:12, 1:9)] else month.abb

  past <- filter(ridges, year != current)
  now  <- filter(ridges, year == current)

  ggplot(mapping = aes(x = day, group = year)) +
    geom_ribbon(data = past,
                aes(ymin = base, ymax = top, fill = year),
                colour = "white", linewidth = 0.2, na.rm = TRUE) +
    geom_ribbon(data = now,
                aes(ymin = base, ymax = top),
                fill = "#f28e2b", colour = "#b35806", linewidth = 0.5,
                alpha = 0.9, na.rm = TRUE) +
    scale_fill_viridis_c(option = "mako", begin = 0.15, end = 0.85,
                         guide = "none") +
    scale_x_continuous(breaks = month_starts, labels = month_labels,
                       expand = c(0, 0)) +
    scale_y_continuous(breaks = seq_along(years), labels = years,
                       expand = expansion(add = c(0.3, overlap))) +
    labs(
      x = NULL, y = NULL, title = gage_name,
      subtitle = sprintf(
        "Daily discharge by %s, %d to %d. %d highlighted. Peak %s cfs.",
        if (water_year) "water year" else "calendar year",
        min(years), current, current, format(round(peak), big.mark = ",")
      )
    ) +
    theme_minimal(base_size = 12) +
    theme(panel.grid.major.y = element_blank(),
          panel.grid.minor = element_blank(),
          axis.text.y = element_text(size = 8))
}

joyplot_ui <- function(id, gages) {
  ns <- NS(id)
  bslib::layout_sidebar(
    sidebar = bslib::sidebar(
      selectInput(ns("gage"), "Gage", choices = setNames(gages$id, gages$name)),
      radioButtons(ns("year_type"), "Year", inline = TRUE,
                   choices = c("Calendar" = "cal", "Water year" = "wy")),
      sliderInput(ns("smooth"), "Smoothing (days)", min = 1, max = 15,
                  value = 7, step = 2),
      helpText("Each ridge is one year of daily mean discharge, scaled to the",
               "largest daily flow in the record. Water years run Oct 1 to",
               "Sep 30.")
    ),
    plotOutput(ns("ridges"), height = "auto")
  )
}

#' @param selected_gage reactive giving a gage id chosen elsewhere (the map).
joyplot_server <- function(id, gages, selected_gage) {
  moduleServer(id, function(input, output, session) {
    observeEvent(selected_gage(), {
      updateSelectInput(session, "gage", selected = selected_gage())
    }, ignoreNULL = TRUE)

    flows <- reactive({
      req(input$gage)
      read_ds("streamflow_daily") |>
        filter(id == !!input$gage) |>
        select(date, flow_cfs) |>
        collect()
    })

    ridges <- reactive({
      prep_ridges(flows(), water_year = input$year_type == "wy",
                  smooth_days = input$smooth)
    })

    output$ridges <- renderPlot({
      req(nrow(flows()) > 0)
      name <- gages$name[gages$id == input$gage]
      plot_ridges(ridges(), name, water_year = input$year_type == "wy")
    }, height = function() {
      max(400, 22 * length(unique(ridges()$year)) + 120)
    })
  })
}
