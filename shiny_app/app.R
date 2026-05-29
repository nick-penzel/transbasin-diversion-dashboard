# Transbasin diversion dashboard — map + hydrograph linked.
# Click a structure on the map to update the hydrograph below.

library(shiny)
library(arrow)
library(dplyr)
library(ggplot2)
library(leaflet)
library(piggyback)

REPO <- "nick-penzel/transbasin-diversion-dashboard"
TAG  <- "historical-data"

# Load data at startup

source("R/shiny_data_source.R")

daily <- load_daily_data()

structure_meta <- read_csv("data/structure_meta.csv")

daily_diversion <- daily$diversions %>% 
  left_join(structure_meta %>% select(-abbrev, parameter), by = "wdid") %>% 
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326)

gages_names<- read_csv("data/stream_gages.csv")

daily_flow <- daily$flows %>% 
  left_join(gages_names, by = "id") %>% 
  st_as_sf(coords = c("X", "Y"), crs = 4326)

basins <- sf::st_read("data/basins.geojson") %>% 
  st_transform(crs = 4326)

# ---- UI ----
ui <- fluidPage(
  titlePanel("Colorado Transbasin Diversions"),
  fluidRow(
    column(7, leafletOutput("map", height = "450px")),
    column(5,
           selectInput("wdid", "Structure",
                       choices = setNames(structures$wdid, structures$name)),
           sliderInput("years", "Year range",
                       min = min(history$year), max = max(history$year),
                       value = c(max(history$year) - 5, max(history$year)),
                       step = 1, sep = "")
    )
  ),
  fluidRow(
    column(12, plotOutput("hydrograph", height = "350px"))
  )
)


# ---- Server ----
server <- function(input, output, session) {
  
  # The selected WDID lives in a reactiveVal so both the map and the dropdown
  # can write to it, and everything downstream reads from it.
  selected <- reactiveVal(structures$wdid[1])
  
  # Dropdown changes -> update selection
  observeEvent(input$wdid, selected(input$wdid))
  
  # Map marker click -> update selection AND sync the dropdown
  observeEvent(input$map_marker_click, {
    click <- input$map_marker_click
    if (!is.null(click$id)) {
      selected(click$id)
      updateSelectInput(session, "wdid", selected = click$id)
    }
  })
  
  # ---- Map: initial render ----
  output$map <- renderLeaflet({
    leaflet() %>% 
      addTiles() %>%
      addPolygons(
        data        = basins,                    
        fillColor   = "#9ecae1",
        fillOpacity = 0.2,
        color       = "#3182bd",               
        weight      = 1,
        label       = ~ basin,               
        group       = "Basins",
        highlightOptions = highlightOptions(
          weight = 3, color = "#666", fillOpacity = 0.4,
          bringToFront = FALSE
        )) %>% 
      addCircleMarkers(
        data = daily_diversion,
        layerId = ~wdid,                       
        radius = ~pmax(4, sqrt(discharge_cfs)),  
        color = ~ifelse(is_transbasin == "yes", "#1f77b4", "#888888"),
        fillOpacity = 0.7, stroke = TRUE, weight = 1,
        popup = ~paste0("<b>", name, "</b><br>",
                        "Source: ",source_basin, "<br>",
                        "Destination: ", destination_basin, "<br>",
                        discharge_cfs, "cfs")) %>% 
      addCircleMarkers(
        data = daily_flow,
        layerId = ~id,                       
        radius = ~pmax(4, sqrt(flow_cfs)/2),  
        color = "darkblue",
        fillOpacity = 0.7, stroke = TRUE, weight = 1,
        popup = ~paste0("<b>", name, "</b><br>",
                        flow_cfs, "cfs")) 
  })
  
  # ---- Map: highlight the selected marker without full redraw ----
  observeEvent(selected(), {
    sel <- structures |> filter(wdid == selected())
    leafletProxy("map") |>
      clearGroup("highlight") |>
      addCircleMarkers(
        data = sel,
        lng = ~longitude, lat = ~latitude,
        group = "highlight",
        radius = ~pmax(4, sqrt(mean_cfs) / 8) + 4,
        color = "red", fillOpacity = 0, stroke = TRUE, weight = 3
      )
  })
  
  # ---- Hydrograph ----
  
  obs <- reactive({
    history |>
      filter(wdid == selected(),
             year >= input$years[1], year <= input$years[2])
  })
  
  norm <- reactive({
    n <- normals |> filter(wdid == selected())
    expand.grid(year = seq(input$years[1], input$years[2]), month = 1:12) |>
      left_join(n, by = "month") |>
      mutate(month_start = as.Date(sprintf("%04d-%02d-01", year, month))) |>
      arrange(month_start)
  })
  
  output$hydrograph <- renderPlot({
    nm <- structures |> filter(wdid == selected()) |> pull(name)
    ggplot() +
      geom_ribbon(data = norm(),
                  aes(month_start, ymin = p25_cfs, ymax = p75_cfs),
                  fill = "grey80", alpha = 0.6) +
      geom_line(data = norm(),
                aes(month_start, p50_cfs),
                color = "grey50", linetype = "dashed") +
      geom_line(data = obs(),
                aes(month_start, mean_cfs),
                color = "#1f77b4", linewidth = 0.7) +
      labs(x = NULL, y = "Mean discharge (cfs)", title = nm,
           subtitle = "Solid: observed. Dashed: median. Ribbon: 25th-75th pct.") +
      theme_minimal(base_size = 13)
  })
}

shinyApp(ui, server)