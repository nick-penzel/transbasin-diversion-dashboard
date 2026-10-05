# Colorado water dashboard. Map tab: rivers, diversions, and gages linked to
# an info card and a diversion hydrograph. Gage tab: yearly hydrograph ridges.
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

basin_transfers <- transfers_by_wy(
  history, collect(read_ds("diversions_daily")), structures
)

# Site picker values are "d:<wdid>" for diversions and "g:<id>" for gages
site_choices <- list(
  Diversions = setNames(paste0("d:", structures$wdid), structures$name),
  `Stream gages` = setNames(paste0("g:", gages$id), gages$name)
)

# ---- UI ----
ui <- page_navbar(
  id = "nav",
  title = "Colorado Water",
  theme = bs_theme(version = 5, preset = "flatly"),
  nav_panel(
    "Map",
    layout_columns(
      col_widths = c(8, 4),
      card(full_screen = TRUE, leafletOutput("map", height = "520px")),
      card(
        card_header("Details"),
        card_body(fillable = FALSE,
                  uiOutput("info"),
                  plotlyOutput("reach_monthly", height = "180px"))
      )
    ),
    card(
      layout_columns(
        col_widths = c(6, 6),
        selectInput("site", "Site (or click the map)", choices = site_choices),
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
    list(type = if (startsWith(input$site, "g:")) "gage" else "diversion",
         id = sub("^[dg]:", "", input$site))
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
                     color = "#2c7fb8", opacity = 0.8,
                     weight = ~pmax(0.6, (streamorde - 2) * 0.8),
                     label = ~ifelse(is.na(gnis_name), "Unnamed", gnis_name),
                     highlightOptions = highlightOptions(color = "#f28e2b",
                                                         weight = 4),
                     group = "Rivers")
    }
    # Basins go above rivers but stay non-interactive so river clicks pass through
    m |>
      addPolygons(data = basins, fillColor = "#9ecae1", fillOpacity = 0.08,
                  color = "#08306b", weight = 2.5, opacity = 0.8,
                  dashArray = "6 4", group = "Basins",
                  options = pathOptions(interactive = FALSE)) |>
      addLabelOnlyMarkers(data = basin_labels, label = ~basin, group = "Basins",
                          labelOptions = labelOptions(
                            noHide = TRUE, direction = "center", textOnly = TRUE,
                            style = list("font-weight" = "600",
                                         "font-size" = "13px",
                                         "color" = "#08306b",
                                         "text-shadow" = "0 0 3px #fff, 0 0 3px #fff"))) |>
      addCircleMarkers(
        data = diversion_points, layerId = ~wdid, group = "Diversions",
        radius = ~pmax(4, sqrt(discharge_cfs), na.rm = TRUE),
        color = ~ifelse(is_transbasin == "yes", "#440154", "#8c8c8c"),
        fillOpacity = 0.7, weight = 1, label = ~name
      ) |>
      addCircleMarkers(
        data = gage_points, layerId = ~id, group = "Gages",
        radius = 7, fillColor = ~color, fillOpacity = 0.95,
        color = "#333333", weight = 1, label = ~name
      ) |>
      addLayersControl(baseGroups = c("Esri light gray", "Esri dark gray", "OpenStreetMap"),
                       overlayGroups = c("Rivers", "Basins", "Diversions", "Gages"),
                       options = layersControlOptions(collapsed = TRUE)) |>
      addLegend("bottomleft",
                colors = c("#440154", "#8c8c8c"),
                labels = c("Transbasin diversion", "Other diversion"),
                opacity = 0.9, group = "Diversions") |>
      addLegend("bottomright", colors = flow_classes$color,
                labels = flow_classes$label, opacity = 0.95,
                title = "Gage flow vs. this day in history",
                group = "Gages")
  })

  # Highlight the selected structure, or the whole river for a clicked reach
  observeEvent(list(site(), clicked()), {
    proxy <- leafletProxy("map") |> clearGroup("highlight")
    cl <- clicked()
    if (!is.null(cl) && cl$type == "river") {
      reach <- flowlines[flowlines$comid == cl$id, ]
      river <- flowlines[flowlines$levelpathi == reach$levelpathi, ]
      proxy |> addPolylines(data = river, color = "#f28e2b", weight = 4,
                            opacity = 0.9, group = "highlight")
    }
    sel <- if (site()$type == "gage") filter(gage_points, id == site()$id)
           else filter(structures, wdid == site()$id)
    proxy |> addCircleMarkers(data = sel, lng = ~longitude, lat = ~latitude,
                              group = "highlight", radius = 12,
                              color = "#f28e2b", fillOpacity = 0, weight = 3)
  })

  # ---- Info card ----
  output$info <- renderUI({
    cl <- clicked()
    if (is.null(cl)) {
      return(p(class = "text-muted",
               "Click a river, diversion, or gage on the map."))
    }
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

  output$reach_monthly <- renderPlotly({
    cl <- clicked()
    req(cl, cl$type == "river")
    plot_reach_monthly(flowlines[flowlines$comid == cl$id, ], dark = dark())
  })

  # ---- Site hydrograph: daily flow vs. day-of-year percentiles ----
  series <- reactive(site_series(site()$type, site()$id))

  output$hydrograph <- renderPlotly({
    sv <- site()
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
  basin_server("basin", basin_outlets, basin_transfers, gage_points, dark)
  diversion_server("div", structures, history, diversion_classes,
                   diversions_recent, normals, water_rights,
                   diversion_profiles, selected, dark)
}

shinyApp(ui, server)
