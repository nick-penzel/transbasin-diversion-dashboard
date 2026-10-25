gridmet_transform <- function(ee) {
  unlist(ee$ImageCollection("IDAHO_EPSCOR/GRIDMET")$first()$projection()$getInfo()$transform)
}

gridmet_cell_id <- function(lon, lat, tr) {
  paste(floor((lat - tr[6]) / tr[5]), floor((lon - tr[3]) / tr[1]), sep = "_")
}

#' Assign each field to its gridMET cell
#'
#' Uses the grid transform reported by Earth Engine, so cell centers match
#' the source pixels exactly.
#'
#' @param ee Earth Engine module.
#' @param fields sf polygons with `field_id`.
#' @return Tibble: field_id, cell_id, lon, lat (cell center).
gridmet_cells <- function(ee, fields) {
  tr <- gridmet_transform(ee)
  xy <- fields |>
    sf::st_point_on_surface() |>
    sf::st_transform(4326) |>
    sf::st_coordinates()
  col <- floor((xy[, 1] - tr[3]) / tr[1])
  row <- floor((xy[, 2] - tr[6]) / tr[5])
  tibble::tibble(
    field_id = fields$field_id,
    cell_id = gridmet_cell_id(xy[, 1], xy[, 2], tr),
    lon = tr[3] + (col + 0.5) * tr[1],
    lat = tr[6] + (row + 0.5) * tr[5]
  )
}

#' Daily gridMET weather at cell centers
#'
#' Pulls precipitation and temperature from gridMET and both the raw gridMET
#' ETo and the OpenET reference ET collection, one calendar year per request.
#'
#' @param ee Earth Engine module.
#' @param cells Tibble from `gridmet_cells()`.
#' @param start,end Date range (inclusive start, exclusive end).
#' @return Tibble: cell_id, date, prcp_mm, tmax_c, tmin_c, eto_gridmet_mm, eto_mm.
gridmet_daily <- function(ee, cells, start, end) {
  tr <- gridmet_transform(ee)
  pts <- dplyr::distinct(cells, cell_id, lon, lat)
  geom <- ee$Geometry$MultiPoint(purrr::map2(pts$lon, pts$lat, c))
  breaks <- unique(c(seq(start, end, by = "year"), end))
  region <- function(id, bands, names, d0, d1) {
    m <- ee$ImageCollection(id)$filterDate(format(d0), format(d1))$select(bands, names)$getRegion(geom, 4000)$getInfo()
    df <- as.data.frame(do.call(rbind, lapply(m[-1], \(r) sapply(r, \(v) if (is.null(v)) NA else v))))
    names(df) <- unlist(m[[1]])
    df
  }
  purrr::map(seq_len(length(breaks) - 1), \(i) {
    met <- region("IDAHO_EPSCOR/GRIDMET", list("pr", "tmmx", "tmmn", "eto"),
                  list("prcp_mm", "tmax_k", "tmin_k", "eto_gridmet_mm"), breaks[i], breaks[i + 1])
    ref <- region("projects/openet/assets/reference_et/conus/gridmet/daily/v1", list("eto"),
                  list("eto_mm"), breaks[i], breaks[i + 1])
    dplyr::left_join(met, ref[, c("longitude", "latitude", "id", "eto_mm")],
                     by = c("longitude", "latitude", "id"))
  }, .progress = TRUE) |>
    dplyr::bind_rows() |>
    dplyr::mutate(
      dplyr::across(-c(id, time), as.numeric),
      cell_id = gridmet_cell_id(longitude, latitude, tr),
      date = as.Date(substr(id, 1, 8), "%Y%m%d"),
      tmax_c = tmax_k - 273.15,
      tmin_c = tmin_k - 273.15
    ) |>
    dplyr::select(cell_id, date, prcp_mm, tmax_c, tmin_c, eto_gridmet_mm, eto_mm)
}

#' Daily Daymet precipitation at one point from the single-pixel API
#'
#' No login needed. Daymet years have 365 days (leap years drop Dec 31).
#'
#' @param lon,lat Point in degrees.
#' @param years Integer calendar years.
#' @return Tibble: date, prcp_mm.
daymet_point_prcp <- function(lon, lat, years) {
  url <- sprintf(
    "https://daymet.ornl.gov/single-pixel/api/data?lat=%.5f&lon=%.5f&vars=prcp&years=%s&format=csv",
    lat, lon, paste(years, collapse = ",")
  )
  txt <- readLines(url, warn = FALSE)
  start <- grep("^year,yday", txt)
  utils::read.csv(text = txt[start:length(txt)]) |>
    tibble::as_tibble() |>
    dplyr::transmute(date = as.Date(paste(year, yday), "%Y %j"), prcp_mm = prcp..mm.day.)
}
