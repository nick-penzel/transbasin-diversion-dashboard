# Data setup for the shiny app

library(piggyback)
library(arrow)
library(tidyverse)
library(lubridate)

REPO <- "nick-penzel/transbasin-diversion-dashboard"

# Load data

dir.create("cache", showWarnings = FALSE)
pb_download(
  c("historical_monthly.parquet", "monthly_normals.parquet"),
  repo = REPO, tag = "historical-data", dest = "cache"
)

pb_download("streamflow_normals.parquet",
            repo = REPO, tag = "streamflow-data", dest = "cache"
)

# load recent data 

N_DAYS <- 30   # how many days back to show

load_daily_data <- function() {
  dir.create("cache/daily", recursive = TRUE, showWarnings = FALSE)
  
  assets <- pb_list(repo = REPO, tag = "daily-data")
  
  cutoff <- Sys.Date() - N_DAYS
  
  recent <- assets %>%
    filter(grepl("^daily_(diversions|flows)_", file_name)) %>%
    mutate(
      file_date = as.Date(
        stringr::str_extract(file_name, "\\d{4}-\\d{2}-\\d{2}")
      )
    ) %>%
    filter(file_date >= cutoff)
  
  if (nrow(recent) == 0) {
    message("No daily files found in the last ", N_DAYS, " days")
    return(NULL)
  }
  
  # Only download files not already in cache
  
  to_download <- recent %>%
    filter(!file.exists(file.path("cache/daily", file_name)))
  
  if (nrow(to_download) > 0) {
    message(sprintf("Downloading %d new daily files...", nrow(to_download)))
    pb_download(
      file  = to_download$file_name,
      repo  = REPO,
      tag   = "daily-data",
       dest  = "cache/daily"
      # .token = trimws(Sys.getenv("GITHUB_TOKEN"))
    )
  } else {
    message("All recent files already cached")
  }
  
  # Read whatever's now in cache that falls in our window
  cached_files <- list.files(
    "cache/daily",
    pattern = "^daily_(diversions|flows)_.*\\.parquet$",
    full.names = TRUE
  ) %>%
    .[as.Date(stringr::str_extract(., "\\d{4}-\\d{2}-\\d{2}")) >= cutoff]
  
  div_files  <- cached_files[grepl("diversions", cached_files)]
  flow_files <- cached_files[grepl("flows", cached_files)]
  
  list(
    diversions = if (length(div_files)  > 0) open_dataset(div_files)  %>% collect() else NULL,
    flows      = if (length(flow_files) > 0) open_dataset(flow_files) %>% collect() else NULL
  )
}

#read in data 

history <- read_parquet("cache/historical_monthly.parquet")
normals <- read_parquet("cache/monthly_normals.parquet")
stream_normals <- read_parquet("cache/historical_monthly.parquet")

# One row per structure for the map. Expects lat/long + is_transbasin in the
# history file (join them in from your verified structures CSV if not present).

structures_sf <- st_read("data/structures.geojson", quiet = TRUE) %>% 
  st_transform(4326)

structures <- history %>% 
  left_join(structures_sf ,by = "wdid") %>% 
  drop_na(geometry)