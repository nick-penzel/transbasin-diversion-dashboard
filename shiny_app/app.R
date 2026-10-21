# Colorado water dashboard. Map tab: rivers, diversions, gages, and
# reservoirs linked to an info card and a shared hydrograph. Gage tab: yearly hydrograph ridges.
# Files in R/ are loaded automatically by shiny::runApp().

library(shiny)
library(bslib)
library(arrow)
library(dplyr)
library(plotly)
library(leaflet)
library(sf)

diversion_points <- structures |>
  left_join(select(latest_diversions, wdid, date, discharge_cfs), by = "wdid")

gage_points <- gages |>
  left_join(select(latest_flows, id, date, flow_cfs), by = "id")
gage_points <- if (is.null(flow_doy_stats)) {
  mutate(gage_points, class = "unranked") |> left_join(flow_classes, by = "class")
} else {
  add_flow_status(gage_points, flow_doy_stats)
}

basins <- st_read("data/basins.geojson", quiet = TRUE) |>
  st_transform(crs = 4326)

basin_labels <- suppressWarnings(st_point_on_surface(basins))

# Assign each gage to its nearest basin polygon (outlets can sit just
# across the state line)
gage_points$basin <- basins$basin[suppressMessages(st_nearest_feature(
  st_as_sf(gage_points, coords = c("longitude", "latitude"), crs = 4326),
  basins
))]

# Reservoirs: same nearest-basin assignment, then today's storage status
reservoirs$basin <- basins$basin[suppressMessages(st_nearest_feature(
  st_as_sf(reservoirs, coords = c("longitude", "latitude"), crs = 4326),
  basins
))]
reservoir_points <- reservoir_status(reservoirs, reservoir_storage,
                                     reservoir_doy_stats)
basin_storage <- storage_by_wy(reservoir_storage, reservoirs)
basin_climate_wy <- climate_by_wy(basin_climate, climate_zones)

gage_points <- gage_points |>
  mutate(pctile = if (is.null(flow_doy_stats)) NA_real_
                  else flow_percentile(flow_cfs, min_cfs, p10_cfs, p25_cfs,
                                       p50_cfs, p75_cfs, p90_cfs, max_cfs))
if (!is.null(flowlines)) {
  flowlines <- if (is.null(reach_gage_distance)) {
    mutate(flowlines, pctile = NA_real_, n_gages = 0L, class = "unranked") |>
      left_join(flow_classes, by = "class")
  } else {
    idw_flowlines(flowlines, gage_points, reach_gage_distance)
  }
}

basin_transfers <- transfers_by_wy(
  history, collect(read_ds("diversions_daily")), structures
)

# Public story view: simplified rivers (scripts/build_story_assets.R) and
# the numbers behind each chapter. Transfer records are sparse before 2013.
major_rivers <- st_read("data/major_rivers.geojson", quiet = TRUE)
story <- build_story(basin_outlets, basin_climate_wy, climate_zones,
                     basin_transfers, basins, reservoir_points, gage_points)
story_years <- story$budget$wy[story$budget$wy >= 2013]
# Larger reaches with today's estimated condition, for the story's live map
story_reaches <- if (!is.null(flowlines)) {
  flowlines[flowlines$streamorde >= 5, ] |>
    select(comid, gnis_name, streamorde, class, color) |>
    left_join(plain_status, by = "class") |>
    st_simplify(dTolerance = 0.0005)
}
pro_tabs <- c("Map", "Gage hydrographs", "Diversions", "Basins")

# Site picker values are "d:<wdid>" for diversions, "g:<id>" for gages, and
# "r:<wdid>" for reservoirs
site_types <- c(d = "diversion", g = "gage", r = "reservoir")
site_choices <- list(
  Diversions = setNames(paste0("d:", structures$wdid), structures$name),
  `Stream gages` = setNames(paste0("g:", gages$id), gages$name),
  Reservoirs = setNames(paste0("r:", reservoirs$wdid), reservoirs$name)
)

# ---- UI ----
ui <- page_navbar(
  id = "nav",
  title = "Colorado Water",
  theme = bs_theme(version = 5, preset = "flatly"),
  fillable = pro_tabs,
  header = tagList(
  tags$link(rel = "stylesheet", href = "https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,400;9..144,500;9..144,600&display=swap"),
  tags$link(rel = "stylesheet", href = "story.css"),
  tags$script(src = "story.js"),
  tags$style(HTML("
    .flow-anim { animation: flow-downstream 0.8s linear infinite; }
    @keyframes flow-downstream { to { stroke-dashoffset: -16; } }
    @media (prefers-reduced-motion: reduce) { .flow-anim { animation: none; } }
    .leaflet-control-layers, .map-legend {
      font-size: 11.5px; line-height: 1.35; border-radius: 6px;
      box-shadow: 0 1px 4px rgba(0,0,0,0.25); border: none;
    }
    .leaflet-control-layers-expanded { padding: 6px 10px; }
    .leaflet-control-layers-separator { margin: 4px -10px; }
    .map-legend { background: rgba(255,255,255,0.92); padding: 8px 10px; }
    .map-legend .lg-title { font-weight: 600; margin-bottom: 3px; }
    .map-legend .lg-title.mt { margin-top: 6px; }
    .map-legend .row-item { display: flex; align-items: center; gap: 6px; }
    .map-legend .lg-grid { display: grid; grid-template-columns: auto auto; column-gap: 12px; }
    .map-legend .sw { display: inline-block; width: 12px; height: 12px;
                      border-radius: 50%; flex: none; }
    .map-legend .lg-note { margin-top: 6px; color: #6c757d; max-width: 220px; }
    [data-bs-theme=dark] .map-legend { background: rgba(33,37,41,0.92); color: #e9ecef; }
    [data-bs-theme=dark] .map-legend .sw { box-shadow: 0 0 0 1px rgba(255,255,255,0.35); }
    [data-bs-theme=dark] .leaflet-control-layers { background: #212529; color: #e9ecef; }
    .leaflet-tooltip { font-size: 12px; }
  "))),
  nav_panel("Colorado's water", value = "story", story_ui("story", story_years)),
  nav_panel(
    "Map",
    layout_columns(
      col_widths = c(8, 4),
      card(full_screen = TRUE, height = "620px",
           card_body(padding = 0, leafletOutput("map", height = "100%"))),
      card(
        height = "620px",
        card_header("Details"),
        card_body(fillable = FALSE,
                  uiOutput("info"),
                  plotlyOutput("reach_monthly", height = "180px"))
      )
    ),
    card(
      layout_columns(
        col_widths = c(6, 6),
        selectInput("site", "Site (or click the map)", choices = site_choices,
                    selected = "g:USGS-09163500"),
        radioButtons("period", "Period", inline = TRUE,
                     choices = names(hydro_periods), selected = "Past year")
      ),
      plotlyOutput("hydrograph", height = "380px")
    )
  ),
  nav_panel("Gage hydrographs", joyplot_ui("joy", gages)),
  nav_panel("Diversions", diversion_ui("div", structures)),
  nav_panel("Basins", basin_ui("basin", sort(basins$basin))),
  nav_spacer(),
  nav_item(input_switch("pro_view", "Professional view", width = "auto")),
  nav_item(input_dark_mode(id = "dark_mode", mode = "light"))
)


# ---- Server ----
server <- function(input, output, session) {

  # Whatever was last clicked on the map: list(type, id)
  clicked <- reactiveVal(NULL)
  selected <- reactiveVal(structures$wdid[1])
  selected_gage <- reactiveVal(NULL)

  site <- reactive({
    req(input$site)
    list(type = site_types[[substr(input$site, 1, 1)]],
         id = substring(input$site, 3))
  })
  observeEvent(site(), {
    if (site()$type == "diversion") selected(site()$id)
  })

  observeEvent(input$map_marker_click, {
    click <- input$map_marker_click
    if (identical(click$group, "Diversions")) {
      selected(click$id)
      updateSelectInput(session, "site", selected = paste0("d:", click$id))
      clicked(list(type = "diversion", id = click$id))
    } else if (identical(click$group, "Gages")) {
      selected_gage(click$id)
      updateSelectInput(session, "site", selected = paste0("g:", click$id))
      clicked(list(type = "gage", id = click$id))
    } else if (identical(click$group, "Reservoirs")) {
      updateSelectInput(session, "site", selected = paste0("r:", click$id))
      clicked(list(type = "reservoir", id = click$id))
    }
  })

  observeEvent(input$map_shape_click, {
    click <- input$map_shape_click
    if (identical(click$group, "Rivers")) {
      clicked(list(type = "river", id = click$id))
    }
  })

  observeEvent(input$open_gage, nav_select("nav", "Gage hydrographs"))
  observeEvent(input$open_diversion, nav_select("nav", "Diversions"))

  # ---- Map ----
  output$map <- renderLeaflet({
    # Canvas keeps ~18k reaches fast; tolerance makes thin lines clickable
    m <- leaflet(options = leafletOptions(
      preferCanvas = TRUE, renderer = JS("L.canvas({tolerance: 6})")
    )) |>
      addProviderTiles(providers$Esri.WorldGrayCanvas, group = "Esri light gray") |>
      addTiles(
        urlTemplate = "https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}",
        attribution = "Tiles &copy; Esri", group = "Esri dark gray",
        options = tileOptions(maxZoom = 16)
      ) |>
      addTiles(group = "OpenStreetMap")
    if (!is.null(flowlines)) {
      m <- m |>
        addPolylines(data = flowlines, layerId = ~comid,
                     color = ~color, opacity = ~ifelse(streamorde <= 3, 0.45, 0.8),
                     weight = ~pmax(0.5, (streamorde - 2) * 0.6),
                     label = ~sprintf("%s: %s (est.)",
                                      ifelse(is.na(gnis_name), "Unnamed", gnis_name),
                                      label),
                     highlightOptions = highlightOptions(color = "#222222",
                                                         weight = 4, opacity = 1),
                     group = "Rivers")
    }
    # Basins go above rivers but stay non-interactive so river clicks pass through
    m |>
      # Pad the right edge so the state sits clear of the legend
      fitBounds(-109.06, 36.99, -102.04, 41.0,
                options = list(paddingBottomRight = c(210, 0))) |>
      addPolygons(data = basins, fill = FALSE,
                  color = "#4a5a70", weight = 1.2, opacity = 0.7,
                  dashArray = "4 3", group = "Basins",
                  options = pathOptions(interactive = FALSE)) |>
      addLabelOnlyMarkers(data = basin_labels, label = ~basin, group = "Basins",
                          labelOptions = labelOptions(
                            noHide = TRUE, direction = "center", textOnly = TRUE,
                            style = list("font-weight" = "600",
                                         "font-size" = "11px",
                                         "letter-spacing" = "0.04em",
                                         "text-transform" = "uppercase",
                                         "color" = "#4a5a70",
                                         "text-shadow" = "0 0 3px rgba(255,255,255,0.9)"))) |>
      addCircleMarkers(
        data = diversion_points, layerId = ~wdid, group = "Diversions",
        radius = ~ifelse(is_transbasin == "yes", 4, 3),
        fillColor = ~ifelse(is_transbasin == "yes", "#6a3d9a", "#9e9e9e"),
        fillOpacity = 0.9, color = "#ffffff", weight = 1, label = ~name
      ) |>
      addCircleMarkers(
        data = reservoir_points, layerId = ~wdid, group = "Reservoirs",
        radius = ~4 + sqrt(capacity) / 90, fillColor = ~color, fillOpacity = 0.85,
        color = "#1f2d50", weight = 2,
        label = ~sprintf("%s: %s%% full (%s)", name, round(pct_full),
                         format(date, "%b %d, %Y"))
      ) |>
      addCircleMarkers(
        data = gage_points, layerId = ~id, group = "Gages",
        radius = 5.5, fillColor = ~color, fillOpacity = 1,
        color = "#ffffff", weight = 1.5, label = ~name
      ) |>
      addLayersControl(baseGroups = c("Esri light gray", "Esri dark gray", "OpenStreetMap"),
                       overlayGroups = c("Rivers", "Basins", "Gages", "Reservoirs",
                                         "Diversions"),
                       options = layersControlOptions(collapsed = FALSE)) |>
      addControl(map_legend_html(), position = "bottomright", className = "")
  })

  # Basemap follows the dark mode toggle
  observeEvent(dark(), {
    leafletProxy("map") |>
      hideGroup(c("Esri light gray", "Esri dark gray", "OpenStreetMap")) |>
      showGroup(if (dark()) "Esri dark gray" else "Esri light gray")
  }, ignoreInit = TRUE)

  # Highlight the selected structure, or the whole river for a clicked reach
  observeEvent(list(site(), clicked()), {
    proxy <- leafletProxy("map") |> clearGroup("highlight")
    cl <- clicked()
    if (!is.null(cl) && cl$type == "river") {
      reach <- flowlines[flowlines$comid == cl$id, ]
      river <- flowlines[flowlines$levelpathi == reach$levelpathi, ]
      # SVG (not canvas) so CSS can animate dashes; lines run upstream to
      # downstream, so the dashes move with the current
      svg <- pathOptions(interactive = FALSE, renderer = JS("L.svg()"))
      proxy |>
        addPolylines(data = river, color = "#08306b", weight = 6,
                     opacity = 0.9, group = "highlight", options = svg) |>
        addPolylines(data = river, color = "#ffffff", weight = 2.5,
                     opacity = 1, dashArray = "6 10", group = "highlight",
                     options = modifyList(svg, list(className = "flow-anim")))
    }
    sel <- switch(site()$type,
                  gage = filter(gage_points, id == site()$id),
                  reservoir = filter(reservoir_points, wdid == site()$id),
                  filter(structures, wdid == site()$id))
    proxy |> addCircleMarkers(data = sel, lng = ~longitude, lat = ~latitude,
                              group = "highlight", radius = 12,
                              color = "#f28e2b", fillOpacity = 0, weight = 3)
  })

  # ---- Info card ----
  output$info <- renderUI({
    cl <- clicked()
    if (is.null(cl)) return(statewide_ui(gage_points, reservoir_points))
    switch(
      cl$type,
      river = river_info_ui(flowlines[flowlines$comid == cl$id, ], flowlines),
      diversion = {
        d <- filter(diversion_points, wdid == cl$id)
        tagList(
          h4(d$name),
          p(class = "small text-muted", "WDID ", d$wdid),
          p(sprintf("%s to %s basin", d$source_basin, d$destination_basin)),
          p(strong(if (is.na(d$discharge_cfs)) "No recent telemetry"
                   else sprintf("%s cfs on %s", d$discharge_cfs, d$date))),
          actionLink("open_diversion", "View diversion details")
        )
      },
      reservoir = reservoir_info_ui(filter(reservoir_points, wdid == cl$id)),
      gage = {
        g <- filter(gage_points, id == cl$id)
        tagList(
          h4(g$name),
          p(class = "small text-muted", g$id, " (", g$type, ")"),
          p(strong(if (is.na(g$flow_cfs)) "No recent data"
                   else sprintf("%s cfs on %s", round(g$flow_cfs), g$date))),
          p(tags$span(style = sprintf(
              "display:inline-block;width:12px;height:12px;border-radius:50%%;background:%s;border:1px solid #333;margin-right:6px;vertical-align:middle;",
              g$color)),
            g$label),
          if (!is.na(g$p50_cfs %||% NA)) {
            p(class = "small text-muted", sprintf(
              "Typical for %s: %s cfs median, %s to %s cfs normal range (%d years since %d).",
              format(g$date, "%b %d"), format(round(g$p50_cfs), big.mark = ","),
              format(round(g$p25_cfs), big.mark = ","),
              format(round(g$p75_cfs), big.mark = ","), g$n_years, g$first_yr))
          },
          actionLink("open_gage", "View yearly hydrographs")
        )
      }
    )
  })

  dark <- reactive(identical(input$dark_mode, "dark"))

  # ---- Public / professional view ----
  # ?view=pro opens the professional tabs; the public story is the default
  observe({
    view <- parseQueryString(session$clientData$url_search)$view
    if (identical(view, "pro")) update_switch("pro_view", value = TRUE)
  }) |> bindEvent(session$clientData$url_search, once = TRUE)

  observeEvent(input$pro_view, {
    pro <- isTRUE(input$pro_view)
    for (tab in pro_tabs) {
      if (pro) nav_show("nav", tab) else nav_hide("nav", tab)
    }
    if (pro) nav_hide("nav", "story") else nav_show("nav", "story")
    nav_select("nav", if (pro) "Map" else "story")
  }, ignoreNULL = FALSE)

  story_server("story", story, major_rivers, story_reaches, basins, structures,
               basin_outlets, gages, flow_doy_stats, diversion_profiles, dark,
               go_pro = \() update_switch("pro_view", value = TRUE))

  output$reach_monthly <- renderPlotly({
    cl <- clicked()
    req(cl, cl$type == "river")
    plot_reach_monthly(flowlines[flowlines$comid == cl$id, ], dark = dark())
  })

  # ---- Site hydrograph: daily flow vs. day-of-year percentiles ----
  series <- reactive(site_series(site()$type, site()$id))

  output$hydrograph <- renderPlotly({
    sv <- site()
    if (sv$type == "reservoir") {
      r <- filter(reservoir_points, wdid == sv$id)
      stats <- reservoir_doy_stats |>
        filter(wdid == sv$id) |>
        rename_with(\(x) sub("_af$", "_cfs", x))
      return(plot_site_hydrograph(series(), stats, r$name,
                                  days = hydro_periods[[input$period]],
                                  dark = dark(), units = "AF",
                                  y_title = "Storage (acre-feet)",
                                  capacity = r$capacity))
    }
    if (sv$type == "gage") {
      stats <- if (!is.null(flow_doy_stats)) filter(flow_doy_stats, id == sv$id)
      title <- gages$name[gages$id == sv$id]
    } else {
      stats <- if (!is.null(diversion_doy_stats)) filter(diversion_doy_stats, wdid == sv$id)
      title <- structures$name[structures$wdid == sv$id]
    }
    plot_site_hydrograph(series(), stats, title,
                         days = hydro_periods[[input$period]], dark = dark())
  })

  joyplot_server("joy", gages, selected_gage, dark)
  basin_server("basin", basin_outlets, basin_transfers, gage_points,
               reservoir_points, basin_storage, basin_climate_wy, basin_climate,
               basin_climate_stats, dark)
  diversion_server("div", structures, history, diversion_classes,
                   diversions_recent, normals, water_rights,
                   diversion_profiles, selected, dark)
}

shinyApp(ui, server)
