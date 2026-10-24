# Irrigation tab: Roaring Fork (HUC8 14010004) trial of irrigation consumptive
# use from OpenET, with the ditches, rights, and landowners behind it. Data
# come from the docs/Irrigation notebooks via scripts/publish_irrigation.R.
# Depths are shown in inches and volumes in acre-feet.

library(shiny)
library(dplyr)
library(plotly)
library(leaflet)

irr_years <- c("2025 (complete)" = "2025", "2026 (through September)" = "2026")
irr_periods <- c("Irrigation year, Nov to Oct" = "irrigation_year",
                 "Growing season, May to Sep" = "may_sep")
irr_src_colors <- c(Precipitation = "#3487A6", Irrigation = "#F78311", `Other sources` = "#9AA5B1")
irr_status_colors <- c(irrigated = "#3D5296", shorted = "#F2B134", fallow = "#C9BFAE")
#' Ordinal colors for senior, middle, junior; lighter steps in dark mode.
irr_tercile_colors <- function(dark = FALSE) {
  setNames(viridisLite::viridis(3, begin = if (dark) 0.35 else 0, end = if (dark) 0.95 else 0.85),
           c("Senior", "Middle", "Junior"))
}
irr_color_by <- c("Water consumed (AF per acre)" = "cu", "Irrigation status" = "status",
                  "Share of crop need met" = "adequacy", "Crop" = "crop")
irr_levels <- c(Owners = "Owner", `Farm blocks` = "Field block", Ditches = "Ditch")

fmt_n <- function(x, d = 0) format(round(x, d), big.mark = ",", nsmall = max(d, 0), trim = TRUE)
irr_af_label <- function(af) paste(fmt_n(signif(af, 3)), "AF")
mm_in <- function(mm) mm / 25.4
title_name <- function(x) tools::toTitleCase(tolower(x))
irr_year <- function(d) as.integer(format(d, "%Y")) + (as.integer(format(d, "%m")) >= 11)

#' Link that opens a chapter (and optionally a section) of the Methods tab.
methods_link <- function(label, chapter, anchor = NULL) {
  tags$a(href = "#", class = "methods-link", `data-chapter` = chapter,
         `data-anchor` = anchor, label)
}

#' Small info icon with a plain-language definition and a methods link.
irr_term <- function(text, chapter, anchor) {
  popover(bsicons::bs_icon("info-circle", class = "irr-info", title = "What is this?"),
          tags$p(text), methods_link("More in Methods", chapter, anchor),
          options = list(trigger = "focus click"))
}

irrigation_ui <- function(id) {
  ns <- NS(id)
  card_title <- function(title, ...) card_header(class = "irr-card-head", title, ...)
  tags$div(
    class = "irr-page",
    tags$div(
      class = "irr-head",
      tags$div(
        tags$div(class = "irr-kicker", "Roaring Fork River basin · trial model"),
        tags$h2("Where irrigation water goes"),
        tags$p(class = "irr-lede",
               "Ditches spread snowmelt over about 670 hay meadows, pastures, and golf courses",
               "from Aspen to Glenwood Springs. Satellites show how much of it the plants use up.",
               "The rest flows back to the river, where it is diverted again downstream.")
      ),
      tags$div(class = "irr-controls",
               radioButtons(ns("iy"), "Irrigation year", irr_years, inline = TRUE),
               radioButtons(ns("period"), "Months", irr_periods, inline = TRUE))
    ),
    uiOutput(ns("boxes")),
    layout_columns(
      col_widths = c(7, 5),
      card(full_screen = TRUE,
           card_title(tags$span("Irrigated fields"),
                      tags$div(class = "irr-head-input d-flex flex-wrap gap-2",
                               selectizeInput(ns("ditch"), NULL, choices = NULL, width = "220px",
                                              options = list(placeholder = "Find a ditch")),
                               selectInput(ns("color_by"), NULL, irr_color_by, width = "260px"))),
           card_body(padding = 0, leafletOutput(ns("map"), height = "540px")),
           card_footer(class = "irr-note",
                       "Fields from the CDSS 2023 irrigated lands map. Click a field for its water budget.")),
      card(card_title(uiOutput(ns("detail_title"), inline = TRUE),
                      uiOutput(ns("clear"), inline = TRUE)),
           card_body(uiOutput(ns("detail")),
                     plotlyOutput(ns("budget"), height = "300px"),
                     uiOutput(ns("budget_note"))))
    ),
    layout_columns(
      col_widths = c(6, 6),
      card(card_title(tags$span("Diverted and consumed, by month",
                                irr_term("Consumptive use is the water plants evaporate and transpire. It leaves the basin as vapor. Diversion is what a ditch takes from the stream; most of it seeps or runs back.",
                                         "irrigation-cu", "what-consumptive-use-means"))),
           plotlyOutput(ns("div_month"), height = "320px"),
           uiOutput(ns("div_note"))),
      card(card_title(tags$span("Largest ditches")),
           plotlyOutput(ns("ditches"), height = "320px"),
           tags$div(class = "irr-note", "Click a ditch to outline its fields on the map.",
                    "Diversion is split among fields by acres, so a ditch that also waters land",
                    "outside the map is counted only for its mapped share."))
    ),
    tags$h3(class = "irr-section", "Who holds the land and the water"),
    layout_columns(
      col_widths = c(7, 5),
      card(card_title(tags$span("How evenly it is shared",
                                irr_term("A Lorenz curve lines holders up from smallest to largest and adds up their share. If everyone held the same amount it would follow the diagonal. The Gini coefficient is the gap: 0 is perfectly even, 1 is one holder with everything.",
                                         "irrigation-rights", "measuring-concentration")),
                      tags$div(class = "irr-head-input",
                               radioButtons(ns("level"), NULL, irr_levels, inline = TRUE))),
           layout_columns(col_widths = c(8, 4),
                          plotlyOutput(ns("lorenz"), height = "330px"),
                          uiOutput(ns("conc_stats")))),
      card(card_title("Who owns the irrigated land"),
           plotlyOutput(ns("owner_class"), height = "200px"),
           tags$div(class = "irr-note",
                    "Agricultural fields with a known owner, from county assessor parcels.",
                    "Owners are not named. Eagle County withholds owner names, so its",
                    "2,000 field acres are left out.",
                    methods_link("How owners were counted", "irrigation-rights", "landowners")))
    ),
    tags$h3(class = "irr-section", "Seniority decides who gets water in a dry year"),
    layout_columns(
      col_widths = c(7, 5),
      card(card_title(tags$span("Days the oldest right on a ditch was cut off",
                                irr_term("Under Colorado's prior appropriation system, older (senior) rights are filled first. When a stream runs short, a senior downstream user can place a call, and newer (junior) rights upstream must stop diverting. Ditches here are split into thirds of the irrigated acres by the age of their rights.",
                                         "irrigation-rights", "priority-and-calls"))),
           plotlyOutput(ns("calls"), height = "380px"),
           tags$div(class = "irr-note", "Top: April 1 snowpack at seven Roaring Fork SNOTEL sites; orange bars are",
                    "the three driest years and blue the three wettest. Bottom: acre-weighted average days the",
                    "oldest right on each ditch was out of priority, by seniority group. 2026 runs through October 22.")),
      card(card_title("Dry years compared with wet years"),
           plotlyOutput(ns("tercile"), height = "300px"),
           uiOutput(ns("tercile_note")))
    ),
    tags$h3(class = "irr-section", "How sure are these numbers?"),
    layout_columns(
      col_widths = c(6, 6),
      card(card_title(tags$span("Estimates by method and satellite model",
                                irr_term("Two questions give two answers. Accounting use removes the rain and snowmelt that soaked into each field. Use beyond native land compares fields with nearby unirrigated shrubland. Each is shown for three of OpenET's satellite models.",
                                         "irrigation-cu", "two-ways-to-remove-precipitation"))),
           plotlyOutput(ns("methods_plot"), height = "330px"),
           tags$div(class = "irr-note", "Highlighted: the headline estimate (eeMETRIC, accounting use).")),
      card(card_title("What moves the headline estimate"),
           plotlyOutput(ns("sensitivity"), height = "330px"),
           tags$div(class = "irr-note", "May to September consumptive use under one change at a time,",
                    "as a percent change from the headline.",
                    methods_link("All sensitivity runs", "irrigation-cu", "sensitivity")))
    ),
    tags$div(class = "irr-foot",
             tags$p("Data: OpenET v2.1 satellite evapotranspiration (provisional), gridMET weather,",
                    "CDSS irrigated lands, diversion records, water rights, and call analysis,",
                    "Colorado OIT parcels, NRCS SSURGO soils, and SNOTEL. Irrigation years run",
                    "November to October, as in DWR diversion records. This is a trial of the method",
                    "for one basin, not an official consumptive use determination."),
             tags$p(methods_link("Read the full methods", "irrigation-cu"), " · ",
                    methods_link("Diversions, rights, and owners", "irrigation-rights")))
  )
}

#' @param irr list of irrigation tables from shiny_data_source.R, or NULL.
irrigation_server <- function(id, irr, dark) {
  moduleServer(id, function(input, output, session) {
    if (is.null(irr)) {
      output$boxes <- renderUI(tags$div(class = "alert alert-secondary",
                                        "Irrigation data have not been published yet (scripts/publish_irrigation.R)."))
      return(invisible())
    }

    ditch_names <- irr$ditches |> transmute(wdid, ditch = title_name(name))
    field_ditches <- irr$field_ditch |>
      inner_join(ditch_names, by = "wdid") |>
      group_by(field_id) |>
      summarise(ditches = paste(ditch, collapse = ", "), .groups = "drop")
    fields <- irr$fields |> left_join(field_ditches, by = "field_id")

    ditch_choices <- irr$ditches |>
      filter(wdid %in% irr$field_ditch$wdid) |>
      arrange(name)
    updateSelectizeInput(session, "ditch", server = TRUE,
                         choices = c(setNames(ditch_choices$wdid, title_name(ditch_choices$name))),
                         selected = character(0))

    iy <- reactive(as.integer(req(input$iy)))
    period <- reactive(req(input$period))
    months_in <- reactive(if (period() == "may_sep") 5:9 else c(11:12, 1:10))

    field_iy <- reactive({
      irr$cu_field_iy |>
        filter(iy == iy(), period == period()) |>
        mutate(adequacy = if_else(status == "irrigated" & niwr_mm > 0, cu_mm / niwr_mm, NA_real_))
    })
    counted <- reactive(filter(field_iy(), status != "fallow"))

    # ---- Value boxes ----
    output$boxes <- renderUI({
      f <- field_iy()
      cu <- sum(f$cu_af)
      acres <- sum(irr$fields$acres[irr$fields$field_id %in% counted()$field_id])
      rng <- irr$cu_summary |>
        filter(period == period(), iy == as.character(iy()), startsWith(method, "A: daily balance, CU"),
               eta != "eemetric") |>
        pull(cu_af)
      div_af <- irr$diversion_month |>
        filter(iy == iy(), as.integer(format(month_start, "%m")) %in% months_in()) |>
        pull(irr_af) |>
        sum()
      shorted <- f |> filter(status == "shorted")
      n_irr <- sum(f$status != "fallow")
      dep <- sum(f$depletion_af)
      layout_column_wrap(
        width = "240px", fill = FALSE, class = "irr-boxes",
        value_box("Used up by irrigated fields", irr_af_label(cu),
                  sprintf("%.2f AF per acre. Other satellite models: %s to %s AF.",
                          cu / acres, fmt_n(signif(min(rng), 2)), fmt_n(signif(max(rng), 2))),
                  showcase = bsicons::bs_icon("droplet-half"), theme = value_box_theme(bg = "#FDF0E2", fg = "#7A3E00")),
        value_box("Diverted by the ditches", irr_af_label(div_af),
                  if (iy() == 2026) "Records for 2026 are still being entered."
                  else sprintf("About %.0f times the water used up. Most returns to the river.", div_af / cu),
                  showcase = bsicons::bs_icon("signpost-split"), theme = value_box_theme(bg = "#E6F1F5", fg = "#1D4E61")),
        value_box("Irrigated land", paste(fmt_n(signif(acres, 3)), "acres"),
                  sprintf("%d fields, %s acres of them golf courses and other turf. %d fields dried up mid-season.",
                          n_irr, fmt_n(sum(irr$fields$acres[irr$fields$field_id %in% counted()$field_id &
                                                              irr$fields$land_class == "turf"]), -2),
                          nrow(shorted)),
                  showcase = bsicons::bs_icon("grid-3x3-gap"), theme = value_box_theme(bg = "#E9ECF5", fg = "#2B3A6B")),
        value_box(tags$span("Use beyond native land",
                            irr_term("How much more water the fields use than nearby unirrigated grass and sagebrush at the same elevation. This is the water a basin would get back if the fields went dry.",
                                     "irrigation-cu", "method-b-depletion-above-the-native-baseline")),
                  irr_af_label(dep),
                  sprintf("%.0f%% of the use at left. Smaller because native land also uses stored soil water and groundwater.",
                          100 * dep / cu),
                  showcase = bsicons::bs_icon("tree"), theme = value_box_theme(bg = "#EEF3EA", fg = "#3B5232"))
      )
    })

    # ---- Map ----
    selected_field <- reactiveVal(NULL)
    selected_ditch <- reactiveVal(NULL)

    map_data <- reactive({
      d <- fields |>
        left_join(field_iy(), by = "field_id") |>
        mutate(cu_ac = cu_af / acres)
      by <- input$color_by
      value_cu <- pmin(d$cu_ac, quantile(d$cu_ac, 0.98, na.rm = TRUE))
      pal <- switch(
        by,
        cu = colorNumeric(viridisLite::viridis(256), range(value_cu, na.rm = TRUE),
                          na.color = "#BDBDBD"),
        status = colorFactor(unname(irr_status_colors), levels = names(irr_status_colors)),
        adequacy = colorBin(rev(viridisLite::cividis(5)), bins = c(0, 0.5, 0.75, 1, 1.25, Inf),
                            na.color = "#BDBDBD"),
        crop = colorFactor(c("#5DC863", "#21908C", "#FDE725"), levels = c("alfalfa", "grass_pasture", "turf"))
      )
      value <- switch(by, cu = value_cu, status = d$status,
                      adequacy = d$adequacy,
                      crop = if_else(d$land_class == "turf", "turf", d$crop))
      d$fill <- pal(value)
      d$label <- sprintf(
        "<b>%s</b><br>%s, %s irrigated, %s ac<br>%s<br>Used up: %s AF (%.1f AF/ac)",
        coalesce(d$ditches, "No ditch on record"),
        if_else(d$land_class == "turf", paste("Turf:", d$turf_type), gsub("_", " ", d$crop)),
        d$irrig_type, fmt_n(d$acres, 1), d$status, fmt_n(d$cu_af), d$cu_ac
      ) |> lapply(HTML)
      list(d = d, pal = pal, value = value)
    })

    huc <- irr$huc
    output$map <- renderLeaflet({
      bb <- unname(sf::st_bbox(fields))
      m <- leaflet(options = leafletOptions(preferCanvas = TRUE)) |>
        addProviderTiles(providers$Esri.WorldGrayCanvas, group = "Light gray") |>
        addTiles(
          urlTemplate = "https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}",
          attribution = "Tiles &copy; Esri", group = "Dark gray", options = tileOptions(maxZoom = 16)
        ) |>
        addProviderTiles(providers$Esri.WorldImagery, group = "Satellite") |>
        fitBounds(bb[1], bb[2], bb[3], bb[4]) |>
        addLayersControl(baseGroups = c("Light gray", "Dark gray", "Satellite"),
                         options = layersControlOptions(collapsed = TRUE))
      if (!is.null(huc)) {
        m <- addPolygons(m, data = huc, fill = FALSE, color = "#4a5a70", weight = 1.5,
                         dashArray = "4 3", options = pathOptions(interactive = FALSE))
      }
      m
    })

    # The map exists only once its tab has been shown; map_zoom arrives then
    map_shown <- reactiveVal(FALSE)
    observeEvent(input$map_zoom, map_shown(TRUE), once = TRUE)

    observeEvent(list(dark(), map_shown()), {
      req(map_shown())
      leafletProxy(session$ns("map")) |>
        hideGroup(c("Light gray", "Dark gray", "Satellite")) |>
        showGroup(if (dark()) "Dark gray" else "Light gray")
    })

    observe({
      req(map_shown())
      md <- map_data()
      title <- names(irr_color_by)[irr_color_by == input$color_by]
      proxy <- leafletProxy(session$ns("map")) |>
        clearGroup("fields") |>
        removeControl("legend") |>
        addPolygons(data = md$d, layerId = ~field_id, group = "fields",
                    fillColor = ~fill, fillOpacity = 0.85, color = "#ffffff", weight = 0.6,
                    label = ~label,
                    highlightOptions = highlightOptions(weight = 2.5, color = "#F78311", bringToFront = TRUE))
      if (input$color_by == "cu") {
        # Reversed palette and labels put high values at the top of the legend
        rev_pal <- colorNumeric(rev(viridisLite::viridis(256)), range(md$value, na.rm = TRUE))
        addLegend(proxy, pal = rev_pal, values = md$value, title = title, layerId = "legend",
                  position = "bottomright", opacity = 0.9,
                  labFormat = labelFormat(transform = \(x) sort(x, decreasing = TRUE)))
      } else {
        addLegend(proxy, pal = md$pal, values = md$value[!is.na(md$value)], title = title,
                  layerId = "legend", position = "bottomright", opacity = 0.9,
                  na.label = "Not irrigated")
      }
    })

    observeEvent(input$map_shape_click, {
      if (identical(input$map_shape_click$group, "fields")) {
        selected_field(input$map_shape_click$id)
        selected_ditch(NULL)
      }
    })
    observeEvent(input$ditch, {
      if (nzchar(input$ditch)) {
        selected_ditch(input$ditch)
        selected_field(NULL)
      }
    })
    observeEvent(input$clear_field, {
      selected_field(NULL)
      selected_ditch(NULL)
      updateSelectizeInput(session, "ditch", selected = character(0))
    })

    # Outline of the selected field or ditch
    observe({
      req(map_shown())
      proxy <- leafletProxy(session$ns("map")) |> clearGroup("highlight")
      ids <- if (!is.null(selected_ditch())) {
        irr$field_ditch$field_id[irr$field_ditch$wdid == selected_ditch()]
      } else selected_field()
      if (length(ids) == 0) return()
      sel <- fields[fields$field_id %in% ids, ]
      proxy <- addPolygons(proxy, data = sel, group = "highlight", fill = FALSE, color = "#F78311",
                           weight = 3, opacity = 1, options = pathOptions(interactive = FALSE))
      if (!is.null(selected_ditch())) {
        bb <- unname(sf::st_bbox(sel))
        flyToBounds(proxy, bb[1], bb[2], bb[3], bb[4], options = list(maxZoom = 14))
      }
    })

    # ---- Field or basin water budget ----
    budget_rows <- reactive({
      ids <- if (!is.null(selected_ditch())) {
        on_ditch <- irr$field_ditch$field_id[irr$field_ditch$wdid == selected_ditch()]
        if (any(on_ditch %in% counted()$field_id)) intersect(on_ditch, counted()$field_id) else on_ditch
      } else selected_field() %||% counted()$field_id
      irr$cu_field_month |>
        filter(field_id %in% ids, irr_year(month) == iy()) |>
        inner_join(st_drop_geometry_fields(), by = "field_id") |>
        group_by(month) |>
        summarise(across(c(et_p_mm, cu_mm, other_mm, ref_mm, prcp_mm, eto_mm),
                         \(x) weighted.mean(x, acres, na.rm = TRUE)), .groups = "drop")
    })
    st_drop_geometry_fields <- function() sf::st_drop_geometry(irr$fields)[, c("field_id", "acres")]

    output$detail_title <- renderUI({
      if (!is.null(selected_ditch())) {
        title_name(irr$ditches$name[irr$ditches$wdid == selected_ditch()])
      } else if (is.null(selected_field())) "All irrigated fields" else {
        f <- fields[fields$field_id == selected_field(), ]
        coalesce(f$ditches, "Field")
      }
    })
    output$clear <- renderUI({
      if (!is.null(selected_field()) || !is.null(selected_ditch()))
        actionLink(session$ns("clear_field"), "Show all fields", class = "small")
    })

    output$detail <- renderUI({
      if (!is.null(selected_ditch())) return(ditch_detail(selected_ditch()))
      if (is.null(selected_field())) {
        f <- counted()
        return(tags$p(class = "irr-detail",
                      sprintf("Average water budget per acre across the %d irrigated fields.", nrow(f)),
                      "Bars split the water plants used each month by where it came from.",
                      "The dashed line is what nearby native land used at the same elevation."))
      }
      f <- fields[fields$field_id == selected_field(), ]
      y <- field_iy() |> filter(field_id == selected_field())
      crop <- if (f$land_class == "turf") paste("Turf,", f$turf_type) else gsub("_", " ", f$crop)
      tags$div(
        class = "irr-detail",
        tags$div(class = "irr-facts",
                 tags$span(paste0(tools::toTitleCase(crop), ", ", f$irrig_type, " irrigated")),
                 tags$span(paste(fmt_n(f$acres, 1), "acres")),
                 tags$span(paste(fmt_n(f$elev_m * 3.28084, -1), "ft elevation")),
                 tags$span(paste("Status:", y$status))),
        tags$p(sprintf("Used up %s AF of irrigation water (%.1f AF per acre)%s.",
                       fmt_n(y$cu_af), y$cu_af / f$acres,
                       if (!is.na(y$adequacy)) sprintf(", %.0f%% of what the crop needs with a full supply", 100 * y$adequacy) else ""))
      )
    })

    ditch_detail <- function(wdid) {
      d <- irr$ditches[irr$ditches$wdid == wdid, ]
      div <- d[[paste0("irr_af_", iy())]]
      cu <- d[[paste0("cu_", iy())]]
      tags$div(
        class = "irr-detail",
        tags$div(class = "irr-facts",
                 tags$span(paste("From", title_name(d$water_source))),
                 tags$span(paste(fmt_n(d$acres), "mapped acres")),
                 if (!is.na(d$cfs_abs)) tags$span(paste(fmt_n(d$cfs_abs, 1), "cfs decreed")),
                 if (!is.na(d$tercile)) tags$span(paste(d$tercile, "rights"))),
        tags$p(if (is.na(div)) sprintf("No %d diversion record. Its fields used up %s AF in irrigation year %d.",
                                       iy(), fmt_n(cu), iy())
               else sprintf("Diverted %s AF to its mapped fields in irrigation year %d; they used up %s AF (%.0f%%).",
                            fmt_n(div), iy(), fmt_n(cu), 100 * cu / div),
               if (!is.na(d$irr_af_mean)) sprintf("Its 2015 to 2024 average was %s AF.", fmt_n(d$irr_af_mean)))
      )
    }

    output$budget <- renderPlotly({
      b <- budget_rows()
      validate(need(nrow(b) > 0, "No data for this field."))
      b <- filter(b, as.integer(format(month, "%m")) %in% months_in())
      hover <- "%{x|%b %Y}: %{y:.1f} in<extra>%{fullData.name}</extra>"
      plot_ly(b, x = ~month) |>
        add_bars(y = ~mm_in(et_p_mm), name = "Precipitation", marker = list(color = irr_src_colors[["Precipitation"]]),
                 hovertemplate = hover) |>
        add_bars(y = ~mm_in(cu_mm), name = "Irrigation", marker = list(color = irr_src_colors[["Irrigation"]]),
                 hovertemplate = hover) |>
        add_bars(y = ~mm_in(other_mm), name = "Other sources", marker = list(color = irr_src_colors[["Other sources"]]),
                 hovertemplate = hover) |>
        add_lines(y = ~mm_in(ref_mm), name = "Native land", line = list(color = if (dark()) "#dee2e6" else "#343a40",
                                                                         dash = "dash", width = 2),
                  hovertemplate = hover) |>
        layout(barmode = "stack", bargap = 0.25, hovermode = "x unified",
               xaxis = list(title = "", tickformat = "%b"),
               yaxis = list(title = "Water used (inches)", rangemode = "tozero"),
               margin = list(t = 10, r = 10, b = 30, l = 50)) |>
        style_plotly(dark(), legend = legend_top)
    })

    output$budget_note <- renderUI({
      b <- budget_rows() |> filter(as.integer(format(month, "%m")) %in% months_in())
      tot <- colSums(select(b, et_p_mm, cu_mm, other_mm, ref_mm))
      tags$p(class = "irr-note", sprintf(
        "Total use %.1f in: %.0f%% from irrigation, %.0f%% from rain and snowmelt. Native land used %.1f in.",
        mm_in(sum(tot[1:3])), 100 * tot[["cu_mm"]] / sum(tot[1:3]), 100 * tot[["et_p_mm"]] / sum(tot[1:3]),
        mm_in(tot[["ref_mm"]])),
        " ", methods_link("How the split works", "irrigation-cu", "method-a-accounting-consumptive-use"))
    })

    # ---- Diversion vs consumption ----
    cu_month <- reactive({
      irr$cu_field_month |>
        filter(irr_year(month) == iy()) |>
        inner_join(st_drop_geometry_fields(), by = "field_id") |>
        group_by(month) |>
        summarise(cu_af = sum(cu_mm / 304.8 * acres), .groups = "drop")
    })

    output$div_month <- renderPlotly({
      d <- irr$diversion_month |>
        filter(iy == iy()) |>
        transmute(month = month_start, irr_af, ditches) |>
        full_join(cu_month(), by = "month") |>
        filter(as.integer(format(month, "%m")) %in% months_in()) |>
        arrange(month)
      plot_ly(d, x = ~month) |>
        add_bars(y = ~irr_af, name = "Diverted for irrigation", marker = list(color = "#3487A6"),
                 customdata = ~ditches,
                 hovertemplate = "%{x|%b %Y}: %{y:,.0f} AF diverted (%{customdata} ditches reporting)<extra></extra>") |>
        add_bars(y = ~cu_af, name = "Used up by plants", marker = list(color = "#F78311"),
                 hovertemplate = "%{x|%b %Y}: %{y:,.0f} AF used up<extra></extra>") |>
        layout(barmode = "group", bargap = 0.2, hovermode = "x unified",
               xaxis = list(title = "", tickformat = "%b"),
               yaxis = list(title = "Acre-feet", tickformat = ",.0f"),
               margin = list(t = 10, r = 10, b = 30)) |>
        style_plotly(dark(), legend = legend_top)
    })

    output$div_note <- renderUI({
      s <- irr$cu_vs_diversion_summary |> filter(iy == as.character(iy()))
      tags$div(class = "irr-note",
               sprintf("On the %d ditches with complete %d records, fields used up %.0f%% of the water diverted to them",
                       s$ditches, iy(), 100 * s$ratio),
               sprintf("(%.0f%% counting ditch losses).", 100 * s$net_ratio),
               "The rest returns to streams as runoff and groundwater and supports flows downstream.",
               if (iy() == 2026) "2026 diversion records are partial.")
    })

    output$ditches <- renderPlotly({
      dv <- paste0("irr_af_", iy())
      cv <- paste0("cu_", iy())
      d <- irr$ditches |>
        filter(!is.na(.data[[dv]])) |>
        transmute(wdid, ditch = title_name(name), div = .data[[dv]], cu = .data[[cv]], acres) |>
        slice_max(div, n = 12) |>
        arrange(div) |>
        mutate(ditch = factor(ditch, ditch))
      plot_ly(d, y = ~ditch, key = ~wdid, source = "irr_ditches") |>
        add_bars(x = ~div, name = "Diverted", orientation = "h", marker = list(color = "#3487A6"),
                 customdata = ~acres,
                 hovertemplate = "%{y}: %{x:,.0f} AF diverted to %{customdata:,.0f} mapped acres<extra></extra>") |>
        add_bars(x = ~cu, name = "Used up", orientation = "h", marker = list(color = "#F78311"),
                 hovertemplate = "%{y}: %{x:,.0f} AF used up<extra></extra>") |>
        layout(barmode = "group", bargap = 0.25,
               xaxis = list(title = sprintf("Acre-feet, full irrigation year %d", iy()), tickformat = ",.0f"),
               yaxis = list(title = ""),
               margin = list(t = 10, r = 10, b = 40, l = 10)) |>
        style_plotly(dark(), legend = legend_top) |>
        event_register("plotly_click")
    })

    observeEvent(event_data("plotly_click", source = "irr_ditches"), {
      k <- event_data("plotly_click", source = "irr_ditches")$key
      if (length(k)) updateSelectizeInput(session, "ditch", selected = k[[1]])
    })

    # ---- Concentration ----
    quantities <- reactive(c(acres = "Irrigated acres", setNames("Water used up", paste0("cu_", iy())),
                             irr_af_mean = "Water diverted (2015 to 2024 average)"))

    output$lorenz <- renderPlotly({
      q <- quantities()
      d <- irr$lorenz |> filter(level == input$level, quantity %in% names(q))
      cols <- setNames(viridisLite::viridis(3, begin = if (dark()) 0.35 else 0, end = if (dark()) 0.95 else 0.8), names(q))
      p <- plot_ly() |>
        add_lines(x = c(0, 100), y = c(0, 100), name = "Perfectly even",
                  line = list(color = "#9AA5B1", dash = "dot", width = 1.5), hoverinfo = "skip")
      for (v in names(q)) {
        dv <- filter(d, quantity == v)
        p <- add_lines(p, data = dv, x = ~100 * holders, y = ~100 * amount, name = q[[v]],
                       line = list(color = cols[[v]], width = 2),
                       hovertemplate = paste0("Smallest %{x:.0f}% of holders: %{y:.0f}% of ", tolower(q[[v]]),
                                              "<extra></extra>"))
      }
      p |>
        layout(xaxis = list(title = "Holders, smallest to largest (%)", range = c(0, 100), ticksuffix = "%"),
               yaxis = list(title = "Share of the total (%)", range = c(0, 100), ticksuffix = "%"),
               margin = list(t = 10, r = 10, b = 40)) |>
        style_plotly(dark(), legend = legend_top)
    })

    output$conc_stats <- renderUI({
      c <- irr$concentration |> filter(level == input$level)
      a <- filter(c, quantity == "acres")
      u <- filter(c, quantity == paste0("cu_", iy()))
      noun <- c(Owner = "owners", `Field block` = "farm blocks", Ditch = "ditches")[[input$level]]
      stat <- function(num, label) tags$div(class = "irr-stat", tags$div(class = "irr-stat-num", num),
                                            tags$div(class = "irr-stat-label", label))
      tags$div(class = "irr-stats",
               stat(sprintf("%.2f", u$gini), sprintf("Gini of water used up across %s %s", fmt_n(u$n), noun)),
               stat(fmt_n(a$holders_for_half), sprintf("%s hold half the irrigated acres", noun)),
               stat(sprintf("%.0f%%", 100 * u$top10pct_share), sprintf("of the water used up goes to the largest 10%% of %s", noun)))
    })

    output$owner_class <- renderPlotly({
      d <- irr$owner_class |>
        mutate(cls = recode(owner_class, `private business` = "Ranches, LLCs, and trusts",
                            individual = "Individuals", `public entity` = "Towns, counties, and agencies"),
               acres_pct = 100 * acres / sum(acres), cu_pct = 100 * cu_2025 / sum(cu_2025)) |>
        arrange(acres_pct) |>
        mutate(cls = factor(cls, cls))
      plot_ly(d, y = ~cls) |>
        add_bars(x = ~acres_pct, name = "Share of acres", orientation = "h", marker = list(color = "#3D5296"),
                 customdata = ~owners,
                 hovertemplate = "%{y}: %{x:.0f}% of acres (%{customdata} owners)<extra></extra>") |>
        add_bars(x = ~cu_pct, name = "Share of water used up (2025)", orientation = "h",
                 marker = list(color = "#F78311"),
                 hovertemplate = "%{y}: %{x:.0f}% of water used up<extra></extra>") |>
        layout(barmode = "group", xaxis = list(title = "", ticksuffix = "%", range = c(0, 100)),
               yaxis = list(title = ""), margin = list(t = 10, r = 10, b = 20, l = 10)) |>
        style_plotly(dark(), legend = legend_top)
    })

    # ---- Priority and calls ----
    output$calls <- renderPlotly({
      sw <- irr$snow_years |> filter(year >= 2010) |> arrange(year)
      sw_col <- c(dry = "#B35806", wet = "#3487A6", other = "#9AA5B1")
      top <- plot_ly(sw, x = ~year, y = ~mm_in(swe_mm), type = "bar", name = "April 1 snowpack",
                     marker = list(color = unname(sw_col[sw$kind])),
                     customdata = ~kind,
                     hovertemplate = "%{x}: %{y:.1f} in of snow water (%{customdata} year)<extra></extra>",
                     showlegend = FALSE) |>
        layout(yaxis = list(title = "April 1 snow<br>water (in)"))
      cy <- irr$calls_year
      tc <- irr_tercile_colors(dark())
      bottom <- plot_ly()
      for (t in names(tc)) {
        bottom <- add_trace(bottom, data = filter(cy, tercile == t), x = ~year, y = ~senior_days,
                            type = "scatter", mode = "lines+markers", name = paste(t, "rights"),
                            line = list(color = tc[[t]], width = 2),
                            marker = list(color = tc[[t]], size = 7),
                            hovertemplate = paste0(t, " ditches, %{x}: %{y:.0f} days<extra></extra>"))
      }
      bottom <- layout(bottom, yaxis = list(title = "Days cut off<br>(Apr to Oct)", rangemode = "tozero"))
      subplot(top, bottom, nrows = 2, shareX = TRUE, heights = c(0.32, 0.68), titleY = TRUE, margin = 0.04) |>
        layout(xaxis = list(title = "", dtick = 2), hovermode = "x unified", margin = list(t = 10, r = 10, b = 30)) |>
        style_plotly(dark(), legend = legend_top)
    })

    output$tercile <- renderPlotly({
      d <- irr$priority_tercile |>
        mutate(tercile = factor(tercile, c("Senior", "Middle", "Junior")))
      plot_ly(d, x = ~tercile) |>
        add_bars(y = ~100 * cfs_out_wet, name = "Wet years", marker = list(color = "#9FC5D6"),
                 hovertemplate = "%{x} ditches, wet years: %{y:.0f}% of rights cut off on an average day<extra></extra>") |>
        add_bars(y = ~100 * cfs_out_dry, name = "Dry years", marker = list(color = "#B35806"),
                 hovertemplate = "%{x} ditches, dry years: %{y:.0f}% of rights cut off on an average day<extra></extra>") |>
        layout(barmode = "group", xaxis = list(title = ""),
               yaxis = list(title = "Share of decreed flow cut off<br>on an average day", ticksuffix = "%"),
               margin = list(t = 10, r = 10, b = 30)) |>
        style_plotly(dark(), legend = legend_top)
    })

    output$tercile_note <- renderUI({
      d <- irr$priority_tercile
      j <- filter(d, tercile == "Junior")
      s <- filter(d, tercile == "Senior")
      dry <- paste(irr$snow_years$year[irr$snow_years$kind == "dry"], collapse = ", ")
      tags$div(class = "irr-note",
               sprintf("Dry years (%s) are the three lowest April 1 snowpacks since 2010.", dry),
               sprintf("Junior ditches still diverted about as much per acre: %.0f%% of their dry-year water came under augmentation plans, which replace what they take with stored water (%.0f%% for seniors).",
                       100 * j$aug_share_dry, 100 * s$aug_share_dry),
               methods_link("More on calls", "irrigation-rights", "priority-and-calls"))
    })

    # ---- Uncertainty ----
    output$methods_plot <- renderPlotly({
      lab <- c("A: daily balance, CU&L convention" = "Accounting use (headline)",
               "A: daily balance, mixed" = "Accounting use, pools mixed",
               "A: daily balance, precipitation first" = "Accounting use, rain used first",
               "A: monthly, Reclamation style" = "Monthly accounting, Reclamation style",
               "B: depletion above native baseline" = "Use beyond native land",
               "Cross-check: NIWR (Kc x ETo minus Pe)" = "Crop need with a full supply")
      eta_lab <- c(eemetric = "eeMETRIC", ssebop = "SSEBop", geesebal = "geeSEBAL", `Kc x ETo` = "Crop coefficient")
      d <- irr$cu_summary |>
        filter(period == period(), iy == as.character(iy())) |>
        mutate(m = factor(lab[method], rev(unname(lab))), e = eta_lab[eta],
               head = method == names(lab)[1] & eta == "eemetric")
      cols <- c(eeMETRIC = "#F78311", SSEBop = "#3D5296", geeSEBAL = "#21908C", `Crop coefficient` = "#9AA5B1")
      p <- plot_ly()
      for (e in names(cols)) {
        de <- filter(d, e == !!e)
        p <- add_markers(p, data = de, x = ~cu_af, y = ~m, name = e,
                         marker = list(color = cols[[e]], size = ifelse(de$head, 16, 11),
                                       line = list(color = if (dark()) "#161b22" else "#ffffff", width = 2)),
                         hovertemplate = paste0("%{y}, ", e, ": %{x:,.0f} AF<extra></extra>"))
      }
      p |>
        layout(xaxis = list(title = "Acre-feet", tickformat = ",.0f", rangemode = "tozero"),
               yaxis = list(title = ""), margin = list(t = 10, r = 10, b = 40, l = 10)) |>
        style_plotly(dark(), legend = legend_top)
    })

    output$sensitivity <- renderPlotly({
      col <- paste0("IY", iy())
      d <- irr$cu_sensitivity |>
        mutate(pct = 100 * (.data[[col]] / .data[[col]][run == "Base"] - 1)) |>
        filter(run != "Base") |>
        arrange(abs(pct)) |>
        mutate(run = factor(run, run))
      plot_ly(d, x = ~pct, y = ~run, type = "bar", orientation = "h",
              marker = list(color = ifelse(d$pct > 0, "#F78311", "#3487A6")),
              hovertemplate = "%{y}: %{x:+.1f}%<extra></extra>") |>
        layout(xaxis = list(title = "Change from headline", ticksuffix = "%", zeroline = TRUE,
                            zerolinecolor = "#9AA5B1"),
               yaxis = list(title = ""), margin = list(t = 10, r = 10, b = 40, l = 10)) |>
        style_plotly(dark())
    })
  })
}
