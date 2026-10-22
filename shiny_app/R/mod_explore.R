# Public river basins page: one basin at a time, a map of its rivers, gages,
# reservoirs, and diversions with the key numbers beside it. Clicking a map
# feature opens its card and chart below the map.

library(shiny)

basin_order <- c("Colorado", "Yampa/White", "Dolores", "San Juan", "Rio Grande",
                 "Arkansas", "South Platte", "North Platte")

#' Drop count for prose: "3", or "less than 1" for a sliver.
drops_count <- function(af, total, n) {
  if (100 * af / total < 1) "less than 1" else as.character(n)
}

explore_ui <- function(id) {
  ns <- NS(id)
  tags$div(
    class = "story explore",
    tags$header(
      class = "explore-head",
      tags$div(class = "explore-inner",
               tags$div(class = "kicker", "Explore a river basin"),
               tags$div(class = "basin-chips",
                        radioButtons(ns("basin"), NULL, choices = basin_order,
                                     selected = "Colorado", inline = TRUE)),
               uiOutput(ns("head")))
    ),
    tags$section(
      class = "explore-main",
      tags$div(class = "explore-grid",
               tags$div(class = "figure map-figure",
                        leafletOutput(ns("map"), height = "640px"),
                        basin_map_key(),
                        tags$p(class = "caption",
                               "Click a gage, reservoir, or diversion for its story.",
                               "Click a shaded basin to go there.")),
               tags$aside(class = "basin-stats", uiOutput(ns("stats"))))
    ),
    tags$section(class = "chapter explore-detail", id = "basin-detail",
                 tags$div(class = "gage-detail",
                          tags$div(class = "gage-card", uiOutput(ns("card"))),
                          tags$div(plotlyOutput(ns("detail_plot"), height = "340px"),
                                   uiOutput(ns("detail_caption"))))),
    tags$section(class = "chapter",
                 tags$h2(class = "chapter-title", "Where the water went"),
                 tags$div(class = "chapter-grid",
                          tags$div(class = "prose", uiOutput(ns("drops_text"))),
                          tags$div(class = "figure", uiOutput(ns("waffle"))))),
    tags$section(class = "chapter",
                 tags$h2(class = "chapter-title", "Year by year"),
                 tags$div(class = "prose wide", uiOutput(ns("years_text"))),
                 tags$div(class = "figure", plotlyOutput(ns("years"), height = "360px"),
                          uiOutput(ns("years_caption")))),
    tags$section(class = "chapter",
                 tags$h2(class = "chapter-title", "Reservoirs"),
                 tags$div(class = "prose wide", uiOutput(ns("res_text"))),
                 tags$div(class = "figure", uiOutput(ns("tanks")),
                          tags$p(class = "caption",
                                 "The basin's largest reservoirs, drawn taller the more they hold.",
                                 "The dashed line shows how full each one usually is on this date."))),
    tags$footer(class = "story-foot",
                tags$p("Data: Colorado Division of Water Resources (CDSS), U.S. Geological",
                       "Survey, U.S. Bureau of Reclamation, and gridMET. Outflow is measured",
                       "at the main gage(s) where the basin's rivers leave the state.",
                       "Transfers between basins are counted from 2013, when records fill in;",
                       "recent months are provisional."))
  )
}

#' @param story list from build_story().
#' @param res_stats reservoir day-of-year storage percentiles.
#' @param div_stats diversion day-of-year flow percentiles.
explore_server <- function(id, story, climate_wy, rivers, basins, structures, outlets,
                           flow_stats, res_stats, div_stats, history, profiles, dark) {
  moduleServer(id, function(input, output, session) {
    divs_all <- structures |>
      mutate(from = to_basin(source_basin), to = to_basin(destination_basin))

    b <- reactive(req(input$basin))
    years <- reactive(basin_years(b(), story$outflow, climate_wy, story$transfers))
    gages <- reactive(filter(story$gages, basin == b()))
    res <- reactive(filter(story$reservoirs, basin == b()))
    divs <- reactive({
      divs_all |>
        mutate(dir = case_when(from != to & from == b() ~ "export",
                               from != to & to == b() ~ "import",
                               from == b() ~ "local")) |>
        filter(!is.na(dir))
    })
    snap <- reactive(basin_snapshot(years(), gages(), res()))

    # Clicking a veiled basin moves there
    observeEvent(input$map_shape_click, {
      if (identical(input$map_shape_click$group, "basin"))
        updateRadioButtons(session, "basin", selected = input$map_shape_click$id)
    })

    # Selected feature as "g:<id>", "r:<wdid>", or "d:<wdid>"; starts on the outlet
    picked <- reactiveVal(NULL)
    observeEvent(b(), picked(paste0("g:", outlets$gage_id[outlets$basin == b()][1])))
    observeEvent(input$map_marker_click, {
      picked(input$map_marker_click$id)
      session$sendCustomMessage("scroll_into_view", "basin-detail")
    })
    pick <- reactive(list(type = substr(req(picked()), 1, 1), id = substring(picked(), 3)))

    output$head <- renderUI({
      tagList(tags$h1(sprintf("The %s basin", b())),
              tags$p(class = "lede", basin_blurb[[b()]]))
    })

    output$stats <- renderUI({
      s <- snap()
      y <- s$year
      stat <- function(kind, label, num, note) {
        tags$div(class = paste("bstat", kind),
                 tags$div(class = "bstat-label", label),
                 tags$div(class = "bstat-num", num),
                 tags$div(class = "bstat-note", note))
      }
      vs <- function(x, med) if (is.na(x) || is.na(med) || med == 0) "" else
        sprintf("%.0f%% of a typical year", 100 * x / med)
      tagList(
        tags$div(class = "bstat-year", sprintf("Water year %d", y$wy)),
        stat("sky", "Rain and snow", sprintf("%.1f in", inches(y$prcp_mm)),
             paste0(fmt_af_words(y$prcp_af), ", ", vs(y$prcp_mm, s$prcp_med))),
        stat("river", "Left the state in rivers", fmt_af_short(y$outflow_af),
             vs(y$outflow_af, s$outflow_med)),
        if (isTRUE(y$export_af > 0))
          stat("divide", "Sent to other basins", fmt_af_short(y$export_af),
               vs(y$export_af, s$export_med)),
        if (isTRUE(y$import_af > 0))
          stat("import", "Brought in from other basins", fmt_af_short(y$import_af),
               vs(y$import_af, s$import_med)),
        tags$div(class = "bstat-year today", "Today"),
        if (!is.null(s$storage))
          stat("river", "Reservoirs", sprintf("%.0f%% full", s$storage$pct),
               if (is.finite(s$storage$usual_pct))
                 sprintf("usually %.0f%% on this date", s$storage$usual_pct) else ""),
        if (s$gages$n > 0)
          stat("river", "River gages running low", sprintf("%d of %d", s$gages$low, s$gages$n),
               sprintf("%d running higher than usual", s$gages$high))
      )
    })

    output$map <- renderLeaflet({
      basin_map(b(), basins, rivers, gages(), filter(res(), !is.na(storage_af)),
                divs(), dark())
    })

    # Ring around the selected feature
    observe({
      p <- pick()
      pt <- switch(p$type,
                   g = filter(story$gages, id == p$id),
                   r = filter(story$reservoirs, wdid == p$id),
                   d = filter(structures, wdid == p$id))
      leafletProxy("map") |>
        clearGroup("picked") |>
        addCircleMarkers(data = pt, lng = ~longitude, lat = ~latitude, group = "picked",
                         radius = 15, color = story_col$divide, weight = 3, fillOpacity = 0,
                         options = pathOptions(interactive = FALSE))
    })

    div_volumes <- function(wdid) {
      v <- filter(story$transfers, wdid == !!wdid) |> select(wy, af)
      if (nrow(v) == 0) v <- select(annual_volumes(history, wdid), wy, af)
      filter(v, wy < water_year(Sys.Date())) |> arrange(wy)
    }

    output$card <- renderUI({
      p <- pick()
      switch(p$type,
             g = {
               g <- filter(story$gages, id == p$id)
               tagList(gage_card(g),
                       if (g$id %in% outlets$gage_id)
                         tags$p(class = "card-note", "This is where the basin's water is measured as it leaves the state."))
             },
             r = reservoir_card(filter(story$reservoirs, wdid == p$id)),
             d = diversion_card(filter(divs(), wdid == p$id), profiles[[p$id]],
                                div_volumes(p$id)))
    })

    # Daily series for the selected site; diversions with no recent daily
    # records fall back to yearly volumes
    detail <- reactive({
      p <- pick()
      if (p$type == "g") {
        return(list(daily = site_series("gage", p$id)$daily,
                    stats = if (!is.null(flow_stats)) filter(flow_stats, id == p$id)))
      }
      if (p$type == "r") {
        s <- site_series("reservoir", p$id)
        st <- if (!is.null(res_stats)) filter(res_stats, wdid == p$id) |>
          rename_with(\(x) sub("_af$", "_cfs", x))
        return(list(daily = bind_rows(s$daily, s$telemetry) |> arrange(x), stats = st,
                    units = "acre-feet", y_title = "Acre-feet stored"))
      }
      s <- site_series("diversion", p$id)
      daily <- bind_rows(s$daily, s$telemetry) |> arrange(x)
      recent <- nrow(daily) > 0 && max(daily$x) > Sys.Date() - 730
      list(daily = if (recent) daily,
           stats = if (!is.null(div_stats)) filter(div_stats, wdid == p$id),
           volumes = if (!recent) div_volumes(p$id))
    })

    output$detail_plot <- renderPlotly({
      d <- detail()
      if (!is.null(d$volumes)) {
        validate(need(nrow(d$volumes) > 0, "No records for this diversion."))
        return(plot_ly(d$volumes, x = ~wy, y = ~af, type = "bar",
                       marker = list(color = story_col$divide),
                       hovertemplate = "%{x}: %{y:,.0f} acre-feet<extra></extra>") |>
                 layout(xaxis = list(title = ""), yaxis = list(title = "Acre-feet per year"),
                        margin = list(t = 30, b = 30)) |>
                 style_plotly(dark()))
      }
      public_hydrograph(d$daily, d$stats, dark(), units = d$units %||% "cfs",
                        y_title = d$y_title %||% "Cubic feet per second")
    })

    output$detail_caption <- renderUI({
      d <- detail()
      tags$p(class = "caption",
             if (!is.null(d$volumes)) "Water moved each water year, from approved records."
             else "The past year against the normal range for each day (middle half of past years).")
    })

    output$drops_text <- renderUI({
      y <- snap()$year
      imp <- coalesce(y$import_af, 0)
      exp <- coalesce(y$export_af, 0)
      total <- y$prcp_af + imp
      n <- hundredths(c(y$outflow_af, exp, max(total - y$outflow_af - exp, 0)))
      tagList(
        tags$p(class = "big",
               sprintf("In water year %d, %s of rain and snow fell on the %s basin.",
                       y$wy, fmt_af_words(y$prcp_af), b())),
        tags$p(if (imp > 0) sprintf("Tunnels and ditches brought in another %s from other basins.",
                                    fmt_af_words(imp)),
               sprintf("Of every 100 drops, %s left Colorado in the basin's rivers%s",
                       drops_count(y$outflow_af, total, n[1]),
                       if (exp > 0) sprintf(" and %s %s sent to other basins.",
                                            drops_count(exp, total, n[2]),
                                            if (n[2] == 1) "was" else "were") else "."),
               "The rest watered forests, fields, and towns, evaporated, or soaked into the ground.")
      )
    })

    output$waffle <- renderUI({
      y <- snap()$year
      imp <- coalesce(y$import_af, 0)
      exp <- coalesce(y$export_af, 0)
      droplet_waffle(list(outflow_af = y$outflow_af, divide_af = exp,
                          other_af = max(y$prcp_af + imp - y$outflow_af - exp, 0),
                          prcp_af = y$prcp_af + imp),
                     labels = c("left Colorado in the basin's rivers",
                                "were sent to other basins",
                                "were used, evaporated, or soaked in"))
    })

    output$years_text <- renderUI({
      yr <- years()
      wet <- slice_max(yr, outflow_af, n = 1)
      dry <- slice_min(yr, outflow_af, n = 1)
      tags$p(class = "big",
             sprintf("Since %d, the most water to leave in a year was %s in %d; the least was %s in %d.",
                     min(yr$wy), fmt_af_words(wet$outflow_af), wet$wy,
                     fmt_af_words(dry$outflow_af), dry$wy))
    })

    output$years <- renderPlotly(basin_years_plot(years(), dark()))

    output$years_caption <- renderUI({
      tags$p(class = "caption",
             "Each bar is one water year (October to September), measured at",
             paste0(paste(outlets$note[outlets$basin == b()], collapse = "; "), "."),
             if (any(years()$export_af > 0, na.rm = TRUE))
               "Transfers to other basins are shown from 2013.")
    })

    output$res_text <- renderUI({
      st <- snap()$storage
      if (is.null(st)) return(tags$p("No major reservoirs with current data in this basin."))
      tags$p(class = "big",
             sprintf("The basin's major reservoirs are %.0f%% full, %s.", st$pct,
                     if (!is.finite(st$vs_usual)) "with no history to compare against"
                     else if (st$vs_usual < 0.9) sprintf("below the usual %.0f%% for this date", st$usual_pct)
                     else if (st$vs_usual > 1.1) sprintf("above the usual %.0f%% for this date", st$usual_pct)
                     else "about normal for this date"))
    })

    output$tanks <- renderUI(reservoir_tanks(res(), n = 6))
  })
}
