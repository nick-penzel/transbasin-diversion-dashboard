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

# ---- Load data at startup ----
dir.create("cache", showWarnings = FALSE)
pb_download(
  c("historical_monthly.parquet", "monthly_normals.parquet"),
  repo = REPO, tag = TAG, dest = "cache"
)
history <- read_parquet("cache/historical_monthly.parquet")
normals <- read_parquet("cache/monthly_normals.parquet")

# One row per structure for the map. Expects lat/long + is_transbasin in the
# history file (join them in from your verified structures CSV if not present).

structures_sf <- st_read("data/structures.geojson", quiet = TRUE) %>% 
  st_transform(4326)

structures <- history %>% 
  left_join(structures_sf ,by = "wdid") %>% 
  drop_na(geometry)


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
    leaflet(structures) |>
      addTiles() |>
      addCircleMarkers(
        lng = ~longitude, lat = ~latitude,
        layerId = ~wdid,                       # so clicks report which structure
        radius = ~pmax(4, sqrt(mean_cfs) / 8),  # size by magnitude, floor at 4px
        color = ~ifelse(is_transbasin, "#1f77b4", "#888888"),
        fillOpacity = 0.7, stroke = TRUE, weight = 1,
        popup = ~paste0("<b>", name, "</b><br>",
                        source_basin, "<br>",
                        round(mean_cfs), " AF/yr avg")
      )
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