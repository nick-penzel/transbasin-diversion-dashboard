# Daily fetch: diversion telemetry, streamflow, reservoir storage, and SNOTEL
# for a date range, upserted
# into partitioned Parquet datasets under data_root(). Defaults to the last
# 7 days so provisional values that get revised are refreshed. gridMET climate
# is refreshed for the 75 days up to END_DATE, since its recent values stay
# provisional for about two months.
#
# Usage: Rscript scripts/daily_fetch.R [START_DATE] [END_DATE]
#   Last year of telemetry: Rscript scripts/daily_fetch.R 2025-10-04 2026-10-03

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(lubridate)
})

source("scripts/storage.R")
source("scripts/fetch_telemetry.R")
source("scripts/fetch_streamflow.R")
source("scripts/fetch_reservoirs.R")
source("scripts/fetch_gridmet.R")
source("scripts/fetch_snotel.R")

args <- commandArgs(trailingOnly = TRUE)
end_date   <- if (length(args) > 1) as.Date(args[2]) else Sys.Date() - 1
start_date <- if (length(args) > 0) as.Date(args[1]) else end_date - 6
message(sprintf("Fetching %s to %s", start_date, end_date))

add_partitions <- function(df) {
  mutate(df, year = as.integer(year(date)), month = as.integer(month(date)))
}

structures <- read_csv("data/structures.csv",
                       col_types = cols(.default = "c"))
div_results <- fetch_telemetry_many(structures, start_date, end_date)

stream_gages <- read_csv("data/stream_gages.csv",
                         col_types = cols(.default = "c"))
flow_results <- fetch_streamflow(stream_gages, start_date, end_date)

reservoirs <- read_csv("data/reservoirs.csv", col_types = cols(.default = "c"))
res_results <- fetch_reservoirs_many(reservoirs, start_date, end_date)

if (nrow(div_results) == 0 && nrow(flow_results) == 0) {
  stop("No diversion or streamflow data returned")
}

upsert_dataset(add_partitions(div_results), "diversions_daily",
               keys = c("wdid", "date"), partitioning = c("year", "month"))
upsert_dataset(mutate(flow_results, year = as.integer(year(date))), "streamflow_daily",
               keys = c("id", "date"), partitioning = "year")
upsert_dataset(mutate(res_results, year = as.integer(year(date))),
               "reservoir_storage_daily",
               keys = c("wdid", "date"), partitioning = "year")

snotel_path <- dataset_path("reference/snotel_sites")
if (path_exists(snotel_path)) {
  snotel_sites <- open_dataset(snotel_path) |> filter(active) |> collect()
  fetch_snotel_many(snotel_sites, start_date, end_date) |>
    upsert_dataset("snotel_daily", keys = c("site_id", "date"), partitioning = "wy")
}

zones_path <- file.path(dataset_path("reference"), "climate_zones.geojson")
if (path_exists(zones_path)) {
  zones <- sf::st_read(local_copy(zones_path), quiet = TRUE)
  fetch_gridmet_many(end_date - 74, end_date, zones, function(df) {
    df |>
      left_join(sf::st_drop_geometry(zones)[c("zone_id", "zone_type")], by = "zone_id") |>
      mutate(year = as.integer(year(date))) |>
      upsert_dataset("climate_daily", keys = c("zone_id", "date", "source"),
                     partitioning = "year")
  })
}
