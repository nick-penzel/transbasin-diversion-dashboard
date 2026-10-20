# Fetch Daymet daily gridded climate (1 km) from NASA Earthdata OPeNDAP and
# reduce it to area-weighted zone means. Needs EARTHDATA_TOKEN in ~/.Renviron.

library(httr2)
library(dplyr)
library(tibble)

daymet_url <- "https://opendap.earthdata.nasa.gov/collections/C2532426483-ORNL_CLOUD/granules"
daymet_crs <- "+proj=lcc +lat_1=25 +lat_2=60 +lat_0=42.5 +lon_0=-100 +x_0=0 +y_0=0 +ellps=WGS84 +units=m +no_defs"
daymet_vars <- c(prcp = "prcp_mm", tmax = "tmax_c", tmin = "tmin_c", swe = "swe_mm")

#' OPeNDAP request for one North America granule.
daymet_request <- function(var, year, ext, ce) {
  token <- Sys.getenv("EARTHDATA_TOKEN")
  if (!nzchar(token)) stop("EARTHDATA_TOKEN is not set (see ~/.Renviron)")
  request(daymet_url) |>
    req_url_path_append(sprintf("Daymet_Daily_V4R1.daymet_v4_daily_na_%s_%s.nc.%s",
                                var, year, ext)) |>
    req_url_query(dap4.ce = ce) |>
    req_auth_bearer_token(token) |>
    req_timeout(900) |>
    # HTTP/1.1: the server drops HTTP/2 streams mid-transfer
    req_options(http_version = 2) |>
    req_retry(max_tries = 4, retry_on_failure = TRUE)
}

#' Cell-center x and y coordinates (m) of the full Daymet grid.
fetch_daymet_axes <- function(year = 2023) {
  lines <- daymet_request("prcp", year, "dap.csv", "/x;/y") |>
    req_perform() |>
    resp_body_string() |>
    strsplit("\n") |>
    unlist()
  axis <- function(name) {
    line <- lines[startsWith(lines, paste0("/", name, ","))]
    as.numeric(strsplit(line, ",")[[1]][-1])
  }
  list(x = axis("x"), y = axis("y"))
}

#' Request for one variable-year over a window of the grid, as NetCDF.
#'
#' `grid` holds 0-based index ranges `x0`, `x1`, `y0`, `y1`. The coordinate
#' variables come along so GDAL georeferences the file; without them it reads
#' the rows south to north.
daymet_subset_request <- function(var, year, grid) {
  ys <- sprintf("[%d:1:%d]", grid$y0, grid$y1)
  xs <- sprintf("[%d:1:%d]", grid$x0, grid$x1)
  ce <- sprintf("/%s[0:1:364]%s%s;/y%s;/x%s;/lambert_conformal_conic",
                var, ys, xs, ys, xs)
  daymet_request(var, year, "dap.nc4", ce)
}

#' Weighted mean per zone for each layer of a cells x layers matrix.
#'
#' `weights` has `zone_id`, `cell`, and `weight`. Cells with no data are left
#' out of the mean. Returns a zones x layers matrix with zone ids as row names.
weighted_zone_means <- function(vals, weights) {
  zones <- unique(weights$zone_id)
  w <- Matrix::sparseMatrix(
    i = match(weights$zone_id, zones), j = weights$cell, x = weights$weight,
    dims = c(length(zones), nrow(vals))
  )
  ok <- !is.na(vals)
  vals[!ok] <- 0
  means <- as.matrix(w %*% vals) / as.matrix(w %*% ok)
  rownames(means) <- zones
  means
}

#' Long tibble (`zone_id`, `date`, `value`) from a zones x days matrix.
zone_means_long <- function(means, dates) {
  tibble(
    zone_id = rep(rownames(means), times = ncol(means)),
    date    = rep(dates, each = nrow(means)),
    value   = as.vector(means)
  )
}

#' Area-weighted daily zone means from a downloaded Daymet subset.
#'
#' `weights$cell` counts row-major from the northwest corner of the window.
daymet_zone_means <- function(nc_path, year, weights) {
  r <- terra::rast(nc_path)
  stopifnot(terra::is.lonlat(r) == FALSE, terra::yres(r) == 1000)
  means <- weighted_zone_means(terra::values(r, mat = TRUE), weights)

  # Daymet years always have 365 days; leap years drop December 31
  dates <- as.Date(sprintf("%s-01-01", year)) + seq_len(ncol(means)) - 1
  zone_means_long(means, dates)
}

#' All variables for one year, one row per zone and day. The variables
#' download in parallel.
fetch_daymet_year <- function(year, weights, grid, vars = names(daymet_vars)) {
  ncs <- vapply(vars, \(v) tempfile(fileext = ".nc"), "")
  on.exit(unlink(ncs))
  lapply(vars, daymet_subset_request, year = year, grid = grid) |>
    req_perform_parallel(paths = ncs, progress = FALSE)

  out <- lapply(vars, function(var) {
    daymet_zone_means(ncs[[var]], year, weights) |>
      rename(!!daymet_vars[[var]] := value)
  })
  Reduce(\(a, b) full_join(a, b, by = c("zone_id", "date")), out) |>
    # Same columns as gridMET so every Parquet file shares one schema
    mutate(eto_mm = NA_real_, vpd_kpa = NA_real_, source = "daymet")
}

#' Fetch several years, handing each to `write_year`; failures are logged
#' and skipped.
fetch_daymet_many <- function(years, weights, grid, write_year, pause = 1) {
  for (year in years) {
    message(sprintf("[%s] Daymet", year))
    tryCatch(
      write_year(fetch_daymet_year(year, weights, grid)),
      error = function(e) message("  -> FAILED: ", conditionMessage(e))
    )
    Sys.sleep(pause)
  }
}
