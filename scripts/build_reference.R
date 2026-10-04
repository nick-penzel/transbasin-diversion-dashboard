# Build reference tables with coordinates for the map: structures (from
# data/structures.csv + CDSS structure metadata) and stream gages (from
# data/stream_gages.csv + USGS/CDSS station locations).
#
# Usage: Rscript scripts/build_reference.R

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(httr2)
  library(dataRetrieval)
})

source("scripts/storage.R")
source("scripts/get_structures.R")

#' Coordinates for CDSS surface water stations by abbrev.
get_cdss_station_coords <- function(abbrevs) {
  bind_rows(lapply(abbrevs, function(abbrev) {
    Sys.sleep(0.3)
    resp <- request("https://dwr.state.co.us/Rest/GET/api/v2") |>
      req_url_path_append("surfacewater/surfacewaterstations") |>
      req_url_query(format = "json", abbrev = abbrev, apiKey = api_key) |>
      req_perform()
    r <- resp_body_json(resp, simplifyVector = FALSE)$ResultList
    if (length(r) == 0) return(NULL)
    tibble(
      cdss_abbrev = abbrev,
      latitude    = as.numeric(r[[1]]$latitude %||% NA),
      longitude   = as.numeric(r[[1]]$longitude %||% NA)
    )
  }))
}

#' Coordinates for USGS monitoring locations (ids like "USGS-09163500").
get_usgs_site_coords <- function(ids) {
  sites <- read_waterdata_monitoring_location(monitoring_location_id = ids)
  coords <- sf::st_coordinates(sites)
  tibble(
    id        = sites$monitoring_location_id,
    longitude = coords[, "X"],
    latitude  = coords[, "Y"]
  )
}

# Structures
structures <- read_csv("data/structures.csv", col_types = cols(.default = "c"))

structure_meta <- get_structures_many(structures$wdid) |>
  select(wdid, water_source, longitude, latitude)

structures_ref <- structures |>
  left_join(structure_meta, by = "wdid")

# Gages
gages <- read_csv("data/stream_gages.csv", col_types = cols(.default = "c"))

usgs_coords <- get_usgs_site_coords(filter(gages, type == "USGS")$id)
cdss_coords <- gages |>
  filter(type == "CDSS") |>
  select(id, cdss_abbrev) |>
  inner_join(get_cdss_station_coords(filter(gages, type == "CDSS")$cdss_abbrev),
             by = "cdss_abbrev") |>
  select(-cdss_abbrev)

gages_ref <- gages |>
  left_join(bind_rows(usgs_coords, cdss_coords), by = "id")

missing <- bind_rows(
  structures_ref |> filter(is.na(latitude)) |> transmute(id = wdid, name),
  gages_ref |> filter(is.na(latitude)) |> select(id, name)
)
if (nrow(missing) > 0) {
  message("Missing coordinates:")
  print(missing, n = Inf)
}

overwrite_dataset(structures_ref, "reference/structures")
overwrite_dataset(gages_ref, "reference/gages")
