# Reading the datasets the app needs at startup. Used by shiny_data_source.R
# and by scripts/build_app_snapshot.R, which saves the result as one file.

library(arrow)
library(dplyr)

DATA_ROOT <- Sys.getenv("TBD_DATA_ROOT", "../data")
SNAPSHOT_FILE <- "app_snapshot.rds"
SNAPSHOT_VERSION <- 1L   # bump whenever read_app_data() changes

# Datasets queried on map clicks and tab changes. They are small, so they are
# held in memory instead of queried over S3 each time.
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

#' Read a dataset if it has been built, else NULL.
read_optional <- function(dataset) {
  if (root_exists(dataset)) collect(read_ds(dataset))
}

#' Read a GeoJSON file under the data root if it exists, else NULL.
read_geojson <- function(path) {
  if (root_exists(path)) sf::st_read(root_file(path), quiet = TRUE)
}

#' Irrigation trial tables and field polygons, or NULL until published.
read_irrigation <- function() {
  if (!root_exists("irrigation/fields.geojson")) return(NULL)
  tables <- c(
    "cu_field_iy", "cu_field_month", "cu_summary", "cu_sensitivity", "cu_et_models",
    "ditches", "field_ditch", "diversion_month", "lorenz", "concentration", "owner_class",
    "priority_tercile", "calls_year", "snow_years", "cu_vs_diversion_summary"
  )
  irr <- lapply(tables, \(name) read_optional(file.path("irrigation", paste0(name, ".parquet"))))
  irr <- c(setNames(irr, tables), list(fields = read_geojson("irrigation/fields.geojson")))
  huc <- read_geojson("reference/climate_zones.geojson")
  if (!is.null(huc)) {
    irr$huc <- huc |>
      filter(zone_id == "14010004") |>
      sf::st_transform(4326)
  }
  irr
}

#' Every dataset the app loads at startup, as a named list.
#'
#' Only reads and fixed filters happen here; anything that depends on today's
#' date is computed in shiny_data_source.R so a snapshot never goes stale by
#' the calendar alone.
read_app_data <- function() {
  flowlines <- read_geojson("reference/flowlines.geojson")
  if (!is.null(flowlines)) flowlines <- flowlines[!sf::st_is_empty(flowlines), ]

  basin_climate <- if (root_exists("climate_daily")) {
    read_ds("climate_daily") |>
      filter(zone_type == "basin", source == "gridmet") |>
      select(basin = zone_id, date, prcp_mm, eto_mm, tmax_c, tmin_c, vpd_kpa) |>
      collect()
  }

  list(
    tables = setNames(lapply(IN_MEMORY, read_optional), IN_MEMORY),
    history = collect(read_ds("diversions_monthly")),
    normals = collect(read_ds("diversions_monthly_normals")),
    structures = collect(read_ds("reference/structures")),
    gages = collect(read_ds("reference/gages")),
    flowlines = flowlines,
    flow_doy_stats = read_optional("streamflow_doy_stats"),
    water_rights = read_optional("reference/water_rights"),
    reach_gage_distance = read_optional("reference/reach_gage_distance"),
    reservoirs = read_optional("reference/reservoirs"),
    reservoir_storage = if (root_exists("reservoir_storage_daily")) {
      read_ds("reservoir_storage_daily") |>
        select(wdid, date, storage_af, provisional) |>
        collect()
    },
    reservoir_doy_stats = read_optional("reservoir_doy_stats"),
    climate_zones = read_optional("reference/climate_zones"),
    basin_climate = basin_climate,
    basin_climate_stats = if (root_exists("climate_doy_stats")) {
      read_ds("climate_doy_stats") |>
        filter(source == "gridmet", variable %in% c("prcp_wy_mm", "eto_wy_mm")) |>
        collect() |>
        filter(zone_id %in% unique(basin_climate$basin)) |>
        rename(basin = zone_id)
    },
    diversion_profiles = if (root_exists("diversion_profiles.json")) {
      jsonlite::read_json(root_file("diversion_profiles.json"), simplifyVector = FALSE)
    } else {
      list()
    },
    diversion_classes = read_optional("diversions_monthly_classes"),
    diversion_doy_stats = read_optional("diversions_doy_stats"),
    basin_outlets = readr::read_csv(root_file("basin_outlets.csv"),
                                    col_types = readr::cols(.default = "c")),
    snotel_sites = read_optional("reference/snotel_sites"),
    snotel_daily = if (root_exists("snotel_daily")) {
      read_ds("snotel_daily") |>
        select(site_id, date, wy, swe_mm) |>
        collect()
    },
    snotel_normals = if (root_exists("snotel_doy_stats")) {
      read_ds("snotel_doy_stats") |>
        filter(variable == "swe_mm") |>
        select(site_id, mmdd, p50, med_9120) |>
        collect()
    },
    irrigation = read_irrigation()
  )
}

#' The startup data from the snapshot file, or NULL if it is missing or was
#' written by a different version of read_app_data().
read_snapshot <- function() {
  if (!root_exists(SNAPSHOT_FILE)) return(NULL)
  snap <- readRDS(root_file(SNAPSHOT_FILE))
  if (!identical(snap$version, SNAPSHOT_VERSION)) return(NULL)
  message("Loaded app snapshot built ", format(snap$built_at, usetz = TRUE))
  snap$data
}
