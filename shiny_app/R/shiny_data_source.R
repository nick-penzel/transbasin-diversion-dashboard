# Data loading for the Shiny app. Reads Parquet datasets written by the ETL
# scripts from TBD_DATA_ROOT (local ../data by default, S3 in Stage 2).

library(arrow)
library(dplyr)

DATA_ROOT <- Sys.getenv("TBD_DATA_ROOT", "../data")
N_DAYS    <- 30   # how far back to look for the latest daily value

# Datasets queried on map clicks and tab changes. They are small, so they are
# read once here and queried in memory instead of over S3 each time.
IN_MEMORY <- c("streamflow_daily", "diversions_daily", "diversions_daily_records")
ds_cache <- list()

#' Open a dataset under the data root, or its in-memory copy.
read_ds <- function(dataset) {
  if (!is.null(ds_cache[[dataset]])) return(ds_cache[[dataset]])
  open_dataset(file.path(DATA_ROOT, dataset))
}

#' Whether a file or dataset exists under the data root, locally or on S3.
root_exists <- function(path) {
  path <- file.path(DATA_ROOT, path)
  if (!startsWith(path, "s3://")) return(file.exists(path))
  x <- FileSystem$from_uri(path)
  x$fs$GetFileInfo(x$path)[[1]]$type != FileType$NotFound
}

#' Local path to a file under the data root, downloaded first if on S3.
root_file <- function(path) {
  path <- file.path(DATA_ROOT, path)
  if (!startsWith(path, "s3://")) return(path)
  dest <- tempfile(fileext = paste0(".", tools::file_ext(path)))
  x <- FileSystem$from_uri(path)
  stream <- x$fs$OpenInputFile(x$path)
  on.exit(stream$close())
  writeBin(as.raw(stream$Read()), dest)
  dest
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

for (d in IN_MEMORY) {
  if (root_exists(d)) ds_cache[[d]] <- as_arrow_table(read_ds(d))
}

latest_diversions <- latest_daily("diversions_daily", "wdid")

# Last 365 days of daily telemetry; older history comes from monthly records
recent_cutoff <- Sys.Date() - 366
diversions_recent <- read_ds("diversions_daily") |>
  filter(date >= recent_cutoff) |>
  select(wdid, date, discharge_cfs) |>
  collect()
latest_flows      <- latest_daily("streamflow_daily", "id")

flowlines <- if (root_exists("reference/flowlines.geojson")) {
  fl <- sf::st_read(root_file("reference/flowlines.geojson"), quiet = TRUE)
  fl[!sf::st_is_empty(fl), ]
}

#' Read a dataset if it has been built, else NULL.
read_optional <- function(dataset) {
  if (root_exists(dataset)) collect(read_ds(dataset))
}

flow_doy_stats <- read_optional("streamflow_doy_stats")
water_rights   <- read_optional("reference/water_rights")
reach_gage_distance <- read_optional("reference/reach_gage_distance")

reservoirs <- read_optional("reference/reservoirs")
reservoirs <- if (!is.null(reservoirs)) filter(reservoirs, !is.na(latitude))
reservoir_storage <- read_optional("reservoir_storage_daily")
if (!is.null(reservoir_storage)) {
  reservoir_storage <- reservoir_storage |>
    select(wdid, date, storage_af, provisional) |>
    clean_storage(reservoirs)
}
reservoir_doy_stats <- read_optional("reservoir_doy_stats")

# Daily gridMET climate for the 8 basin polygons (Daymet is stored too but
# stops at the last calendar year and has no reference ET)
climate_zones <- read_optional("reference/climate_zones")
basin_climate <- if (root_exists("climate_daily")) {
  read_ds("climate_daily") |>
    filter(zone_type == "basin", source == "gridmet") |>
    select(basin = zone_id, date, prcp_mm, eto_mm, tmax_c, tmin_c, vpd_kpa) |>
    collect()
}
basin_climate_stats <- if (root_exists("climate_doy_stats")) {
  read_ds("climate_doy_stats") |>
    filter(source == "gridmet", variable %in% c("prcp_wy_mm", "eto_wy_mm")) |>
    collect() |>
    filter(zone_id %in% unique(basin_climate$basin)) |>
    rename(basin = zone_id)
}

# Researched history blurbs, curated by hand (tracked in git)
diversion_profiles <- if (root_exists("diversion_profiles.json")) {
  jsonlite::read_json(root_file("diversion_profiles.json"), simplifyVector = FALSE)
} else {
  list()
}

diversion_classes <- read_optional("diversions_monthly_classes")
diversion_doy_stats <- read_optional("diversions_doy_stats")
basin_outlets <- readr::read_csv(root_file("basin_outlets.csv"),
                                 col_types = readr::cols(.default = "c"))

# SNOTEL: sites, this water year's daily SWE, and SWE normals by day
snotel_sites <- read_optional("reference/snotel_sites")
snotel_daily <- if (root_exists("snotel_daily")) {
  this_wy <- water_year(Sys.Date())
  read_ds("snotel_daily") |>
    filter(wy == this_wy) |>
    select(site_id, date, swe_mm) |>
    collect()
}
snotel_normals <- if (root_exists("snotel_doy_stats")) {
  read_ds("snotel_doy_stats") |>
    filter(variable == "swe_mm") |>
    select(site_id, mmdd, p50, med_9120) |>
    collect()
}
