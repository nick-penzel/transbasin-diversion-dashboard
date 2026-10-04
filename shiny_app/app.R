# Colorado water dashboard. Map tab: rivers, diversions, and gages linked to
# an info card and a diversion hydrograph. Gage tab: yearly hydrograph ridges.
# Files in R/ are loaded automatically by shiny::runApp().

library(shiny)
library(bslib)
library(arrow)
library(dplyr)
library(ggplot2)
library(leaflet)
library(sf)

diversion_points <- structures |>
  left_join(select(latest_diversions, wdid, date, discharge_cfs), by = "wdid")

gage_points <- gages |>
  left_join(select(latest_flows, id, date, flow_cfs), by = "id")

basins <- st_read("data/basins.geojson", quiet = TRUE) |>
  st_transform(crs = 4326)

year_max <- max(history$year)

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
                  plotOutput("reach_monthly", height = "160px"))
      )
    ),
    card(
      layout_columns(
        col_widths = c(6, 6),
        selectInput("wdid", "Diversion structure",
                    choices = setNames(structures$wdid, structures$name)),
        sliderInput("years", "Years shown",
                    min = min(history$year), max = year_max,
                    value = c(year_max - 9, year_max), step = 1, sep = "")
      ),
      plotOutput("hydrograph", height = "340px")
    )
  ),
  nav_panel("Gage hydrographs", joyplot_ui("joy", gages))
)


# ---- Server ----
server <- function(input, output, session) {

  # Whatever was last clicked on the map: list(type, id)
  clicked <- reactiveVal(NULL)
  selected <- reactiveVal(structures$wdid[1])
  selected_gage <- reactiveVal(NULL)

  observeEvent(input$wdid, selected(input$wdid))

  observeEvent(input$map_marker_click, {
    click <- input$map_marker_click
    if (identical(click$group, "Diversions")) {
      selected(click$id)
      updateSelectInput(session, "wdid", selected = click$id)
      clicked(list(type = "diversion", id = click$id))
    } else if (identical(click$group, "Gages")) {
      selected_gage(click$id)
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

  # ---- Map ----
  output$map <- renderLeaflet({
    # Canvas keeps ~18k reaches fast; tolerance makes thin lines clickable
    m <- leaflet(options = leafletOptions(
      preferCanvas = TRUE, renderer = JS("L.canvas({tolerance: 6})")
    )) |>
      addProviderTiles(providers$Esri.WorldGrayCanvas) |>
      addPolygons(data = basins, fillColor = "#9ecae1", fillOpacity = 0.15,
                  color = "#3182bd", weight = 1, group = "Basins",
                  options = pathOptions(interactive = FALSE))
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
    m |>
      addCircleMarkers(
        data = diversion_points, layerId = ~wdid, group = "Diversions",
        radius = ~pmax(4, sqrt(discharge_cfs), na.rm = TRUE),
        color = ~ifelse(is_transbasin == "yes", "#440154", "#8c8c8c"),
        fillOpacity = 0.7, weight = 1, label = ~name
      ) |>
      addCircleMarkers(
        data = gage_points, layerId = ~id, group = "Gages",
        radius = 6, color = "#21918c", fillOpacity = 0.9, weight = 2,
        label = ~name
      ) |>
      addLayersControl(overlayGroups = c("Rivers", "Diversions", "Gages", "Basins"),
                       options = layersControlOptions(collapsed = TRUE)) |>
      addLegend("bottomleft",
                colors = c("#440154", "#8c8c8c", "#21918c"),
                labels = c("Transbasin diversion", "Other diversion", "Stream gage"),
                opacity = 0.9)
  })

  # Highlight the selected structure, or the whole river for a clicked reach
  observeEvent(list(selected(), clicked()), {
    proxy <- leafletProxy("map") |> clearGroup("highlight")
    cl <- clicked()
    if (!is.null(cl) && cl$type == "river") {
      reach <- flowlines[flowlines$comid == cl$id, ]
      river <- flowlines[flowlines$levelpathi == reach$levelpathi, ]
      proxy |> addPolylines(data = river, color = "#f28e2b", weight = 4,
                            opacity = 0.9, group = "highlight")
    }
    sel <- structures |> filter(wdid == selected())
    proxy |> addCircleMarkers(data = sel, group = "highlight", radius = 12,
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
                   else sprintf("%s cfs on %s", d$discharge_cfs, d$date)))
        )
      },
      gage = {
        g <- filter(gage_points, id == cl$id)
        tagList(
          h4(g$name),
          p(class = "small text-muted", g$id, " (", g$type, ")"),
          p(strong(if (is.na(g$flow_cfs)) "No recent data"
                   else sprintf("%s cfs on %s", round(g$flow_cfs), g$date))),
          actionLink("open_gage", "View yearly hydrographs")
        )
      }
    )
  })

  output$reach_monthly <- renderPlot({
    cl <- clicked()
    req(cl, cl$type == "river")
    plot_reach_monthly(flowlines[flowlines$comid == cl$id, ])
  })

  # ---- Diversion hydrograph: monthly history + last 365 days daily ----
  daily <- reactive({
    filter(diversions_recent, wdid == selected())
  })

  monthly <- reactive({
    daily_start <- if (nrow(daily()) > 0) min(daily()$date) else Sys.Date()
    history |>
      filter(wdid == selected(),
             year >= input$years[1], year <= input$years[2],
             month_start < daily_start)
  })

  norm <- reactive({
    n <- normals |> filter(wdid == selected())
    expand.grid(year = seq(input$years[1], input$years[2]), month = 1:12) |>
      left_join(n, by = "month") |>
      mutate(month_start = as.Date(sprintf("%04d-%02d-15", year, month))) |>
      arrange(month_start)
  })

  output$hydrograph <- renderPlot({
    nm <- structures |> filter(wdid == selected()) |> pull(name)
    ggplot() +
      geom_ribbon(data = norm(),
                  aes(month_start, ymin = p25_cfs, ymax = p75_cfs),
                  fill = "grey85", na.rm = TRUE) +
      geom_line(data = norm(), aes(month_start, p50_cfs),
                colour = "grey55", linetype = "dashed", na.rm = TRUE) +
      geom_line(data = monthly(), aes(month_start + 14, mean_cfs),
                colour = "#31688e", linewidth = 0.7, na.rm = TRUE) +
      geom_line(data = daily(), aes(date, discharge_cfs),
                colour = "#35b779", linewidth = 0.4, na.rm = TRUE) +
      labs(x = NULL, y = "Discharge (cfs)", title = nm,
           subtitle = paste("Blue: monthly mean (diversion records).",
                            "Green: daily telemetry, last 365 days.",
                            "Grey: monthly median and 25th to 75th percentile.")) +
      theme_minimal(base_size = 13)
  })

  joyplot_server("joy", gages, selected_gage)
}

shinyApp(ui, server)
