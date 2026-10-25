# Public story view: one long page in chapters, each a short plain-language
# passage with numbers filled in from the data and one graphic.

library(shiny)

#' A chapter: number, title, prose, and its graphic(s).
chapter <- function(id, num, title, ..., class = NULL) {
  tags$section(class = paste("chapter", class), id = id,
               tags$div(class = "chapter-num", num),
               tags$h2(class = "chapter-title", title),
               ...)
}

story_ui <- function(id, years) {
  ns <- NS(id)
  toc <- c(`ch-drops` = "A hundred drops", `ch-leaving` = "Out of state",
           `ch-divide` = "Across the Divide", `ch-snow` = "Snow becomes river",
           `ch-storage` = "Saving for a dry year", `ch-now` = "Right now")
  tags$div(
    class = "story",
    tags$nav(class = "story-toc", lapply(names(toc), function(id) {
      tags$a(href = paste0("#", id), `data-target` = id, tags$span(class = "dot"),
             tags$span(class = "lbl", toc[[id]]))
    })),
    tags$header(
      class = "story-hero",
      tags$div(class = "hero-inner",
               tags$div(class = "kicker", "Colorado's water, told with live data"),
               tags$h1("Where Colorado's water goes"),
               tags$p(class = "lede",
                      "Colorado is the headwaters state. Rivers born in its mountains",
                      "supply 18 states and Mexico, and almost no water flows in from",
                      "anywhere else. Every drop that falls here has somewhere to go."),
               tags$a(class = "scroll-cue", href = "#ch-drops", "Follow the water",
                      bsicons::bs_icon("arrow-down")))
    ),
    tags$div(class = "today-strip", uiOutput(ns("today"))),

    chapter(
      "ch-drops", "01", "A hundred drops",
      tags$div(class = "chapter-grid",
               tags$div(class = "prose", uiOutput(ns("drops_text")),
                        tags$div(class = "year-picker",
                                 sliderInput(ns("year"), "Water year", min = min(years),
                                             max = max(years), value = max(years),
                                             step = 1, sep = "", ticks = FALSE,
                                             width = "100%")),
                        tags$p(class = "aside",
                               tags$strong("A water year"), " runs from October 1 to",
                               "September 30, so one winter's snow and the spring melt",
                               "that follows land in the same year. ",
                               tags$strong("An acre-foot"), " is enough water to cover",
                               "a football field a foot deep, about 326,000 gallons.")),
               tags$div(class = "figure", uiOutput(ns("waffle"))))
    ),

    chapter(
      "ch-leaving", "02", "Downhill and out of state",
      tags$div(class = "prose wide", uiOutput(ns("leaving_text"))),
      tags$div(class = "figure map-figure",
               leafletOutput(ns("outflow_map"), height = "560px"),
               tags$p(class = "caption",
                      "Circles mark where each river system crosses the state line, sized",
                      "by how much water passed that year. Lines are the larger rivers,",
                      "wider and darker downstream."))
    ),

    chapter(
      "ch-divide", "03", "Across the Divide",
      tags$div(class = "prose wide", uiOutput(ns("divide_text"))),
      tags$div(class = "figure",
               uiOutput(ns("divide_split")),
               tags$p(class = "caption",
                      "Population share is approximate, from 2020 Census county totals.")),
      tags$div(class = "figure", uiOutput(ns("tunnels"))),
      tags$div(class = "figure map-figure",
               leafletOutput(ns("divide_map"), height = "600px"),
               tags$p(class = "caption",
                      "The dotted line is the Continental Divide. Orange arcs are tunnels",
                      "and ditches carrying West Slope water east, sized by volume that",
                      "year. Hover a point for its name."))
    ),

    chapter(
      "ch-snow", "04", "Snow becomes river",
      tags$div(class = "prose wide", uiOutput(ns("snow_text"))),
      tags$div(class = "figure", plotlyOutput(ns("snowmelt"), height = "430px"),
               tags$p(class = "caption",
                      "Daily flow of the Colorado River at the Utah line. Each faint",
                      "line is one year since 1990.")),
      tags$div(class = "prose wide", uiOutput(ns("snowpack_text"))),
      tags$div(class = "figure", plotlyOutput(ns("snowpack"), height = "380px"),
               uiOutput(ns("snowpack_caption"))),
      tags$div(class = "prose wide", uiOutput(ns("shift_text"))),
      tags$div(class = "figure", plotlyOutput(ns("shift"), height = "380px"),
               uiOutput(ns("shift_caption"))),
      tags$div(class = "prose wide", uiOutput(ns("warming_text"))),
      tags$div(class = "figure", plotlyOutput(ns("stripes"), height = "170px"),
               tags$p(class = "caption",
                      "Each stripe is one water year, colored by Colorado's average",
                      "temperature compared with 1980 to 2000. Data: gridMET."))
    ),

    chapter(
      "ch-storage", "05", "Saving for a dry year",
      tags$div(class = "prose wide", uiOutput(ns("storage_text"))),
      tags$div(class = "figure", uiOutput(ns("tanks")),
               tags$p(class = "caption",
                      "Colorado's 12 largest reservoirs, largest first and drawn taller",
                      "the more they hold. The dashed line shows how full each one usually",
                      "is on this date. Yellow water is below that, orange well below."))
    ),

    chapter(
      "ch-now", "06", "The rivers right now",
      tags$div(class = "prose wide", uiOutput(ns("now_text"))),
      tags$div(class = "figure map-figure",
               leafletOutput(ns("now_map"), height = "620px"),
               tags$div(class = "tile-legend",
                        lapply(c("low", "much_below", "below", "normal", "above",
                                 "much_above", "high"), function(k) {
                          tags$span(tags$span(class = "tile",
                                              style = sprintf("background:%s",
                                                              flow_classes$color[flow_classes$class == k])),
                                    plain_status$plain[plain_status$class == k])
                        })),
               tags$p(class = "caption",
                      "Dots are river gauges, compared with the same day in every year",
                      "since 1990. River colors between gauges are estimated from the",
                      "nearest gauges up and downstream.")),
      tags$div(class = "gage-detail",
               tags$div(class = "gage-card", uiOutput(ns("gage_card"))),
               tags$div(plotlyOutput(ns("gage_plot"), height = "320px"))),
      tags$div(class = "cta",
               actionButton(ns("go_pro"), "Open the professional view",
                            class = "btn-outline-secondary", icon = icon("chart-line")),
               tags$span(class = "cta-note",
                         "Every diversion, reservoir, and basin account, in full detail."))
    ),

    tags$footer(class = "story-foot",
                tags$p("Data: Colorado Division of Water Resources (CDSS), U.S. Geological",
                       "Survey, U.S. Bureau of Reclamation, and gridMET (University of",
                       "California Merced). River lines from NHDPlus. Numbers update daily;",
                       "recent months use provisional data that can change."),
                tags$p("Totals are approximate. Outflow is measured at the main gauge",
                       "where each river leaves the state, and precipitation covers the",
                       "eight major river basins."))
  )
}

#' @param story list from build_story().
#' @param reaches larger river reaches colored by estimated condition.
#' @param go_pro callback run when the professional view button is pressed.
story_server <- function(id, story, rivers, reaches, basins, structures, outlets,
                         gages, flow_stats, profiles, snowpack, dark, go_pro) {
  moduleServer(id, function(input, output, session) {
    observeEvent(input$go_pro, go_pro())

    output$today <- renderUI({
      g <- gage_summary(story$gages)
      st <- storage_summary(story$reservoirs)
      wy <- water_year(Sys.Date())
      day <- as.integer(Sys.Date() - as.Date(sprintf("%d-09-30", wy - 1)))
      stat <- function(num, text) tags$div(class = "today-stat", tags$div(class = "num", num),
                                          tags$div(class = "txt", text))
      tags$div(class = "today-inner",
               tags$div(class = "today-label", "Today", tags$br(), format(Sys.Date(), "%b %d")),
               stat(sprintf("%d of %d", g$low, g$n), "river gauges running lower than usual"),
               stat(sprintf("%.0f%%", st$pct),
                    sprintf("full, major reservoirs (usually %.0f%% now)", st$usual_pct)),
               stat(sprintf("Day %d", day), sprintf("of water year %d", wy)))
    })

    yr <- reactive(as.integer(input$year))
    b <- reactive(filter(story$budget, wy == yr()))

    output$drops_text <- renderUI({
      x <- b()
      n <- hundredths(c(x$outflow_af, x$divide_af, x$other_af))
      tagList(
        tags$p(class = "big",
               sprintf("In water year %d, about %s of rain and snow fell on Colorado.",
                       yr(), fmt_af_words(x$prcp_af))),
        tags$p(sprintf("Picture it as 100 drops. Only %d left the state in its rivers.", n[1]),
               "Fewer than one in a hundred was pumped through tunnels to the other side",
               "of the mountains. The rest, by far the largest share, never reached a",
               "river at all: it evaporated from snow and soil, was drawn up by forests,",
               "grasslands, and crops, or soaked into the ground."),
        tags$p(class = "muted",
               "Move the slider to compare years. Wet years send more water downstream;",
               "in dry years, thirsty soils and plants keep almost all of it.")
      )
    })

    output$waffle <- renderUI(droplet_waffle(b()))

    output$leaving_text <- renderUI({
      o <- filter(story$outflow, wy == yr(), !is.na(outflow_af)) |> arrange(desc(outflow_af))
      west <- b()$west_outflow_af / b()$outflow_af
      tagList(
        tags$p(class = "big",
               sprintf("Colorado's rivers carried %s across the state line in %d.",
                       fmt_af_words(b()$outflow_af), yr())),
        tags$p(sprintf("The %s alone took %s, %.0f%% of the total.",
                       basin_exit[[o$basin[1]]], fmt_af_words(o$outflow_af[1]),
                       100 * o$outflow_af[1] / sum(o$outflow_af)),
               sprintf("Rivers flowing west to the Pacific carried %.0f%% of it;", 100 * west),
               "the Platte, Arkansas, and Rio Grande, which drain the plains and the San",
               "Luis Valley toward the Gulf of Mexico, carried the rest. Much of their",
               "water is used along the way by farms and cities before it reaches Kansas,",
               "Nebraska, or New Mexico.")
      )
    })

    output$outflow_map <- renderLeaflet({
      outflow_map(rivers, basins, story$outflow, gages, outlets, yr(), dark())
    })

    flows <- reactive(divide_flows(story$transfers, structures, basins, yr()))

    output$divide_text <- renderUI({
      f <- flows()
      top <- slice_max(f, af, n = 2)
      west <- b()$west_outflow_af / b()$outflow_af
      tagList(
        tags$p(class = "big",
               sprintf("%.0f%% of the river water leaving Colorado comes from west of the Continental Divide. About 9 in 10 Coloradans live east of it.",
                       100 * west)),
        tags$p("For more than a century, Coloradans have closed that gap by moving water",
               "under and over the mountains.",
               sprintf("In %d, %d tunnels, ditches, and pipelines carried %s east.",
                       yr(), nrow(f), fmt_af_words(sum(f$af))),
               sprintf("The largest, the %s, moved %s on its own, followed by the %s with %s.",
                       top$name[1], fmt_af_words(top$af[1]), top$name[2],
                       fmt_af_words(top$af[2])))
      )
    })

    output$divide_split <- renderUI(divide_split(b()$west_outflow_af / b()$outflow_af))

    output$tunnels <- renderUI(tunnel_cards(flows(), profiles))

    output$divide_map <- renderLeaflet({
      divide_map(rivers, basins, story$divide, flows(), dark())
    })

    cameo <- read_ds("streamflow_daily") |>
      filter(id == "USGS-09163500") |>
      select(date, flow_cfs) |>
      collect()
    flow_wy <- max(water_year(cameo$date[cameo$date < Sys.Date() - 300]))

    output$snow_text <- renderUI({
      s <- snow_stats(cameo, flow_wy)
      tagList(
        tags$p(class = "big",
               "Most of Colorado's river water starts as mountain snow."),
        tags$p("Through the winter, snow piles up and rivers run low and clear. Then",
               sprintf("the snowpack melts. In a typical year the Colorado River leaving the state climbs from about %s cubic feet per second in January to %s in early June, %.0f times its winter flow.",
                       fmt_cfs(s$winter), fmt_cfs(s$typ_peak), s$typ_peak / s$winter),
               "Reservoirs, ditches, and water rights are all built around catching",
               "that one short pulse."),
        tags$p(sprintf("Water year %d barely had one. The river peaked at %s cubic feet per second, %.0f%% of a typical spring peak.",
                       flow_wy, fmt_cfs(s$this_peak), 100 * s$this_peak / s$typ_peak))
      )
    })

    output$snowmelt <- renderPlotly(snowmelt_plot(cameo, flow_wy, dark()))

    state_snow <- if (!is.null(snowpack$sites)) {
      snowpack_series(snowpack$daily, snowpack$normals,
                      filter(snowpack$sites, active)$site_id)
    }

    output$snowpack_text <- renderUI({
      req(state_snow)
      t <- snowpack_today(state_snow)
      req(t)
      peak <- state_snow$peak
      typical <- sprintf("In a typical year the snowpack peaks around %s, when the average snow site holds about %.0f inches of water.",
                         fmt_day(peak$x), peak$median_mm / 25.4)
      now <- switch(t$stage,
        early = sprintf("Water year %d's snow season is just getting started: the average site holds %.1f inches of water so far.",
                        water_year(t$date), t$swe_mm / 25.4),
        season = sprintf("Right now Colorado's snowpack is %s normal for the date, at %.0f%% of the 1991 to 2020 median.",
                         if (t$pct >= 110) "above" else if (t$pct <= 90) "below" else "close to",
                         t$pct),
        melted = sprintf("This winter the average site peaked at %.0f inches on %s, %.0f%% of a typical peak.",
                         t$this_peak$swe_mm / 25.4, fmt_day(t$this_peak$date),
                         100 * t$this_peak$swe_mm / peak$median_mm))
      tagList(
        tags$p(class = "big", "Snow is the state's first reservoir."),
        tags$p("More than a hundred automated SNOTEL stations, mostly above 9,000",
               "feet, weigh the snow every day. The water locked in that snow tells",
               "water managers how much river is coming in spring.", typical, now)
      )
    })

    output$snowpack <- renderPlotly({
      req(state_snow)
      snowpack_plot(state_snow, dark(),
                    median_color = if (dark()) "#ADE3C0" else story_col$deep,
                    current_color = story_col$divide)
    })

    output$snowpack_caption <- renderUI({
      req(state_snow)
      tags$p(class = "caption",
             sprintf("Average snow water equivalent (the depth of water if the snow melted) across %d SNOTEL stations,",
                     state_snow$n_sites),
             "this water year against the 1991 to 2020 median for each date. Data: NRCS.")
    })

    output$shift_text <- renderUI({
      s <- story$shift
      earlier <- filter(s, shift <= -5)
      tagList(
        tags$p(class = "big", "The pulse is coming earlier."),
        tags$p(sprintf("In %d of %d river basins, half the year's water now leaves Colorado",
                       nrow(earlier), nrow(s)),
               sprintf("one to three weeks sooner than it did in the 1990s. The Rio Grande's has moved up by %.0f days.",
                       -s$shift[s$basin == "Rio Grande"]),
               "Earlier melt means less water left in the rivers in late summer, when",
               "farms, fish, and cities need it most.")
      )
    })

    output$shift <- renderPlotly(runoff_shift_plot(story$shift, dark()))

    output$shift_caption <- renderUI({
      late <- filter(story$shift, early_from > 1991)
      tags$p(class = "caption",
             "Date by which half of each basin's yearly river flow has left the state,",
             "averaged over each period at the main gauge where the river leaves.",
             if (nrow(late) > 0)
               sprintf("The %s record starts in %d.", paste(late$basin, collapse = " and "),
                       min(late$early_from)))
    })

    output$warming_text <- renderUI({
      t <- story$temperature
      fit <- lm(tmean_f ~ wy, data = t)
      warmest <- slice_max(t, tmean_f, n = 1)
      tagList(
        tags$p(class = "big", "The state is warming."),
        tags$p(sprintf("Colorado's average temperature has risen about %.1f \u00b0F per decade since %d,",
                       coef(fit)[["wy"]] * 10, min(t$wy)),
               sprintf("and water year %d was the warmest in the record at %.1f \u00b0F.",
                       warmest$wy, warmest$tmean_f),
               "Warmer air melts snow sooner and pulls more water back out of soils,",
               "plants, and reservoirs, so the same snowfall makes less river.")
      )
    })

    output$stripes <- renderPlotly(warming_stripes(story$temperature, dark()))

    output$storage_text <- renderUI({
      st <- storage_summary(story$reservoirs)
      tagList(
        tags$p(class = "big",
               sprintf("Colorado's major reservoirs are %.0f%% full today, %s.", st$pct,
                       if (st$vs_usual < 0.9) sprintf("well below the usual %.0f%% for this date", st$usual_pct)
                       else if (st$vs_usual > 1.1) "above normal for this date"
                       else "close to normal for this date")),
        tags$p("Reservoirs are the state's savings account: they catch the spring melt",
               "and pay it out through the dry months and dry years.",
               sprintf("%s, the largest, holds %.0f%% of what it can.",
                       st$largest$name, st$largest$pct_full),
               if (st$vs_usual < 0.9) "After a dry, hot year, many are drawn down well below where they usually sit this time of year.")
      )
    })

    output$tanks <- renderUI(reservoir_tanks(story$reservoirs))

    output$now_text <- renderUI({
      g <- gage_summary(story$gages)
      tagList(
        tags$p(class = "big",
               sprintf("Of %d river gauges across the state, %d are running lower than usual for the date and %d higher.",
                       g$n, g$low, g$high)),
        tags$p("Click any dot on the map to see how that river has run over the past",
               "year compared with normal.")
      )
    })

    output$now_map <- renderLeaflet(now_map(reaches, story$gages, dark()))

    # Start on the Colorado River at the state line; map clicks change it
    gage_id <- reactiveVal("USGS-09163500")
    observeEvent(input$now_map_marker_click, gage_id(input$now_map_marker_click$id))

    output$gage_card <- renderUI(gage_card(filter(story$gages, id == gage_id())))

    output$gage_plot <- renderPlotly({
      daily <- site_series("gage", gage_id())$daily
      stats <- if (!is.null(flow_stats)) filter(flow_stats, id == gage_id())
      public_hydrograph(daily, stats, dark())
    })
  })
}
