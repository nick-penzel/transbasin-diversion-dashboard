# Fetch gridMET daily gridded climate (about 4 km, 1979 to yesterday) from the
# Northwest Knowledge Network THREDDS server and reduce it to area-weighted
# zone means. No login needed. The last two months or so are provisional.

library(httr2)
library(dplyr)
library(tibble)

source("scripts/fetch_daymet.R")

gridmet_url <- "http://thredds.northwestknowledge.net:8080/thredds/ncss/MET"

# File prefix, NetCDF variable, stored column, and offset added to the value
gridmet_vars <- tribble(
  ~var,   ~nc_name,                        ~column,    ~offset,
  "pr",   "precipitation_amount",          "prcp_mm",  0,
  "tmmx", "air_temperature",               "tmax_c",   -273.15,
  "tmmn", "air_temperature",               "tmin_c",   -273.15,
  "pet",  "potential_evapotranspiration",  "eto_mm",   0,
  "vpd",  "mean_vapor_pressure_deficit",   "vpd_kpa",  0
)

#' Download one variable for a bounding box and date range within one year.
fetch_gridmet_subset <- function(var, nc_name, start_date, end_date, bbox, dest) {
  request(gridmet_url) |>
    req_url_path_append(var, sprintf("%s_%s.nc", var, format(start_date, "%Y"))) |>
    req_url_query(
      var = nc_name,
      north = bbox[["ymax"]], south = bbox[["ymin"]],
      west = bbox[["xmin"]], east = bbox[["xmax"]],
      time_start = format(start_date, "%Y-%m-%dT00:00:00Z"),
      time_end = format(end_date, "%Y-%m-%dT00:00:00Z"),
      accept = "netcdf"
    ) |>
    req_timeout(600) |>
    req_retry(max_tries = 4, retry_on_failure = TRUE) |>
    req_perform(path = dest)
  dest
}

#' Share of each grid cell's area inside each zone.
#'
#' Cells are in degrees, so the covered fraction is scaled by cell area.
gridmet_weights <- function(r, zones) {
  area <- terra::values(terra::cellSize(r[[1]], unit = "km"))[, 1]
  terra::extract(r[[1]], terra::vect(zones), cells = TRUE, exact = TRUE) |>
    transmute(zone_id = zones$zone_id[ID], cell = as.integer(cell),
              weight = fraction * area[cell])
}

#' All variables for a date range within one year, one row per zone and day.
#'
#' `zones` is an sf object in longitude/latitude with a `zone_id` column.
fetch_gridmet_year <- function(start_date, end_date, zones) {
  bbox <- sf::st_bbox(zones) + c(-0.1, -0.1, 0.1, 0.1)
  weights <- NULL
  out <- lapply(seq_len(nrow(gridmet_vars)), function(i) {
    v <- gridmet_vars[i, ]
    nc <- tempfile(fileext = ".nc")
    on.exit(unlink(nc))
    fetch_gridmet_subset(v$var, v$nc_name, start_date, end_date, bbox, nc)
    r <- terra::rast(nc)
    if (is.null(weights)) weights <<- gridmet_weights(r, zones)
    means <- weighted_zone_means(terra::values(r, mat = TRUE), weights) + v$offset
    zone_means_long(means, as.Date(terra::time(r))) |>
      rename(!!v$column := value)
  })
  Reduce(\(a, b) full_join(a, b, by = c("zone_id", "date")), out) |>
    mutate(swe_mm = NA_real_, source = "gridmet")
}

#' Fetch a date range one calendar year at a time, handing each piece to
#' `write_year`; failures are logged and skipped.
fetch_gridmet_many <- function(start_date, end_date, zones, write_year, pause = 0.5) {
  for (year in format(start_date, "%Y"):format(end_date, "%Y")) {
    from <- max(start_date, as.Date(sprintf("%s-01-01", year)))
    to   <- min(end_date, as.Date(sprintf("%s-12-31", year)))
    message(sprintf("[%s] gridMET %s to %s", year, from, to))
    tryCatch(
      write_year(fetch_gridmet_year(from, to, zones)),
      error = function(e) message("  -> FAILED: ", conditionMessage(e))
    )
    Sys.sleep(pause)
  }
}
