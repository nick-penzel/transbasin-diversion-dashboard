# Data loading for the Shiny app. Reads Parquet datasets written by the ETL
# scripts from TBD_DATA_ROOT (local ../data by default, S3 in Stage 2).

library(arrow)
library(dplyr)

DATA_ROOT <- Sys.getenv("TBD_DATA_ROOT", "../data")
N_DAYS    <- 30   # how far back to look for the latest daily value

#' Open a dataset under the data root.
read_ds <- function(dataset) {
  open_dataset(file.path(DATA_ROOT, dataset))
}

#' Most recent value per site within the last N_DAYS.
latest_daily <- function(dataset, site_col) {
  cutoff <- Sys.Date() - N_DAYS
  read_ds(dataset) |>
    filter(date >= cutoff) |>
    collect() |>
    slice_max(date, by = all_of(site_col), n = 1, with_ties = FALSE)
}

history    <- read_ds("diversions_monthly") |> collect()
normals    <- read_ds("diversions_monthly_normals") |> collect()
structures <- read_ds("reference/structures") |> collect() |>
  filter(!is.na(latitude))
gages      <- read_ds("reference/gages") |> collect() |>
  filter(!is.na(latitude))

latest_diversions <- latest_daily("diversions_daily", "wdid")

# Last 365 days of daily telemetry; older history comes from monthly records
recent_cutoff <- Sys.Date() - 366
diversions_recent <- read_ds("diversions_daily") |>
  filter(date >= recent_cutoff) |>
  select(wdid, date, discharge_cfs) |>
  collect()
latest_flows      <- latest_daily("streamflow_daily", "id")

flowlines_path <- file.path(DATA_ROOT, "reference", "flowlines.geojson")
flowlines <- if (file.exists(flowlines_path)) {
  fl <- sf::st_read(flowlines_path, quiet = TRUE)
  fl[!sf::st_is_empty(fl), ]
}

#' Read a dataset if it has been built, else NULL.
read_optional <- function(dataset) {
  if (dir.exists(file.path(DATA_ROOT, dataset))) collect(read_ds(dataset))
}

flow_doy_stats <- read_optional("streamflow_doy_stats")
water_rights   <- read_optional("reference/water_rights")

# Researched history blurbs, curated by hand (tracked in git)
profiles_path <- file.path(DATA_ROOT, "diversion_profiles.json")
diversion_profiles <- if (file.exists(profiles_path)) {
  jsonlite::read_json(profiles_path, simplifyVector = FALSE)
} else {
  list()
}

diversion_classes <- read_optional("diversions_monthly_classes")
diversion_doy_stats <- read_optional("diversions_doy_stats")
basin_outlets <- readr::read_csv(file.path(DATA_ROOT, "basin_outlets.csv"),
                                 col_types = readr::cols(.default = "c"))
