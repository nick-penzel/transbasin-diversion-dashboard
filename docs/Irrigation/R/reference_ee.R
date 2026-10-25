#' USGS 3DEP 10 m elevation as one image with its native projection
dem_3dep <- function(ee) {
  ic <- ee$ImageCollection("USGS/3DEP/10m_collection")
  ic$mosaic()$select("elevation")$setDefaultProjection(ic$first()$projection())
}

#' Mask of non-irrigated reference pixels near irrigated land
#'
#' Keeps NLCD 2021 grassland (71) and shrub (52) on slopes under `max_slope`,
#' within `near_m` of irrigated fields, and outside irrigated fields (any
#' mapped year, plus `field_buffer_m`), mapped streams (plus `stream_buffer_m`),
#' and NLCD wetlands (plus `wet_buffer_m`).
#'
#' @param ee Earth Engine module.
#' @param huc8_poly sf polygon (EPSG 26913).
#' @param fields_all sf of irrigated fields from all years to exclude.
#' @param streams sf of flowlines (any CRS).
#' @return ee.Image, 1 where a pixel is a reference pixel, masked elsewhere.
reference_mask <- function(ee, huc8_poly, fields_all, streams, max_slope = 10, near_m = 5000,
                           field_buffer_m = 200, stream_buffer_m = 150, wet_buffer_m = 100) {
  zone <- function(x, d) {
    x |>
      sf::st_buffer(d) |>
      sf::st_union() |>
      sf::st_simplify(dTolerance = 20) |>
      sf::st_intersection(sf::st_geometry(huc8_poly)) |>
      sf::st_cast("POLYGON") |>
      sf::st_sf(id = 1, geometry = _)
  }
  streams <- sf::st_transform(streams, 26913) |>
    sf::st_filter(huc8_poly)
  paint <- function(x) ee$Image(0)$paint(sf_to_ee(ee, x), 1)
  excl <- paint(zone(fields_all, field_buffer_m))$Or(paint(zone(streams, stream_buffer_m)))
  near <- paint(zone(fields_all, near_m))
  lc <- ee$ImageCollection("USGS/NLCD_RELEASES/2021_REL/NLCD")$first()$select("landcover")
  wet <- lc$eq(90L)$Or(lc$eq(95L))$focalMax(radius = wet_buffer_m, units = "meters")
  slope <- ee$Terrain$slope(dem_3dep(ee))
  lc$eq(71L)$Or(lc$eq(52L))$
    And(slope$lt(max_slope))$
    And(near)$
    And(excl$Not())$
    And(wet$Not())$
    selfMask()$
    rename("ref")
}

#' Pixels that pass the irrigated EToF rule in one season
#'
#' Same rule as `irrigation_status()`: eeMETRIC EToF above `threshold` in at
#' least `min_months` of the given months.
#'
#' @param ee Earth Engine module.
#' @param months Vector of month start Dates (one season).
#' @return ee.Image, 1 where the pixel looks irrigated, 0 elsewhere.
etof_irrigated <- function(ee, months, threshold = 0.4, min_months = 3) {
  wet <- lapply(months, \(m) {
    img <- openet_month_image(ee, m)
    img$select("eemetric")$divide(img$select("eto"))$gt(threshold)$unmask(0)
  })
  ee$ImageCollection(wet)$sum()$gte(min_months)
}

#' Distance to NHD high resolution flowlines of given feature types
#'
#' Uses the Colorado NHD in the Earth Engine community catalog. FType 336 is
#' canal or ditch, 460 stream or river, 558 artificial path.
#'
#' @param ee Earth Engine module.
#' @param region ee.Geometry to search.
#' @param ftypes Integer FType codes.
#' @param max_m Search radius in meters.
#' @return ee.Image of distance in meters, masked beyond `max_m`.
nhd_distance <- function(ee, region, ftypes, max_m = 500) {
  ee$FeatureCollection("projects/sat-io/open-datasets/NHD/NHD_CO/NHDFlowline")$
    filterBounds(region)$
    filter(ee$Filter$inList("ftype", as.list(as.integer(ftypes))))$
    distance(searchRadius = max_m, maxError = 5)
}

#' Tighter reference mask: no wet-looking pixels, ditches, or creeks
#'
#' Starts from `reference_mask()` and also drops pixels within
#' `ditch_buffer_m` of NHD canals and ditches, within `creek_buffer_m` of any
#' NHD stream, and pixels that stay wet in mid-summer (eeMETRIC EToF above
#' `wet_threshold` in at least `wet_min_months` of `wet_months`). The Reclamation rule
#' (EToF > 0.4 in three months) is not used here: most native shrubland near
#' the fields passes it in May, June, and October.
#'
#' @param ee Earth Engine module.
#' @param mask Image from `reference_mask()`.
#' @param huc8_poly sf polygon.
#' @param wet_months Month start Dates, e.g. July and August of the season.
#' @return ee.Image mask.
reference_mask_tight <- function(ee, mask, huc8_poly, wet_months, wet_threshold = 0.6,
                                 wet_min_months = length(wet_months), ditch_buffer_m = 100,
                                 creek_buffer_m = 60) {
  region <- sf_to_ee(ee, sf::st_sf(id = 1, geometry = sf::st_geometry(huc8_poly)))$geometry()
  near_ditch <- nhd_distance(ee, region, 336L)$lt(ditch_buffer_m)$unmask(0)
  near_creek <- nhd_distance(ee, region, c(460L, 558L))$lt(creek_buffer_m)$unmask(0)
  wet <- etof_irrigated(ee, wet_months, wet_threshold, wet_min_months)
  mask$updateMask(near_ditch$Or(near_creek)$Or(wet)$Not())
}

#' Monthly reference ET by 100 m elevation band, optionally by land cover
#'
#' @param ee Earth Engine module.
#' @param mask Image from `reference_mask()` or `reference_mask_tight()`.
#' @param huc8_poly sf polygon.
#' @param months Vector of month start Dates.
#' @param by_class Also split by NLCD class (52 shrub, 71 grassland).
#' @return Tibble: elev_band (m, band floor), nlcd (NA unless `by_class`),
#'   month, variable, et_mm, n_pixels.
reference_et_monthly <- function(ee, mask, huc8_poly, months, by_class = FALSE) {
  region <- sf_to_ee(ee, sf::st_sf(id = 1, geometry = sf::st_geometry(huc8_poly)))$geometry()
  band <- dem_3dep(ee)$divide(100)$floor()$int()
  if (by_class) {
    lc <- ee$ImageCollection("USGS/NLCD_RELEASES/2021_REL/NLCD")$first()$select("landcover")
    band <- band$multiply(100L)$add(lc)$int()
  }
  band <- band$rename("band")
  vars <- c("ensemble", openet_models, "eto")
  purrr::map(months, \(m) {
    img <- openet_month_image(ee, m)$updateMask(mask)$addBands(band)
    reducer <- ee$Reducer$mean()$`repeat`(length(vars))$
      combine(ee$Reducer$count()$`repeat`(length(vars)), sharedInputs = TRUE)$
      group(groupField = length(vars), groupName = "band")
    g <- img$reduceRegion(reducer = reducer, geometry = region, scale = 30,
                          crs = "EPSG:32613", maxPixels = 1e10, tileScale = 4)$getInfo()$groups
    purrr::map(g, \(x) tibble::tibble(
      key = x$band, variable = vars,
      et_mm = purrr::map_dbl(x$mean, \(v) if (is.null(v)) NA else v),
      n_pixels = unlist(x$count)
    )) |>
      dplyr::bind_rows() |>
      dplyr::mutate(month = m)
  }, .progress = TRUE) |>
    dplyr::bind_rows() |>
    dplyr::mutate(
      elev_band = if (by_class) key %/% 100 * 100 else key * 100,
      nlcd = if (by_class) key %% 100 else NA_integer_
    ) |>
    dplyr::filter(n_pixels > 0) |>
    dplyr::select(elev_band, nlcd, month, variable, et_mm, n_pixels)
}

#' Pool land cover classes into one pixel-weighted reference per band
#'
#' @param r Tibble from `reference_et_monthly(by_class = TRUE)`.
#' @return Tibble: variable, elev_band, month, et_mm, n_pixels.
pool_classes <- function(r) {
  r |>
    dplyr::filter(!is.na(et_mm)) |>
    dplyr::group_by(variable, elev_band, month) |>
    dplyr::summarise(et_mm = sum(et_mm * n_pixels) / sum(n_pixels), n_pixels = sum(n_pixels), .groups = "drop")
}

#' Mean elevation of each field from 3DEP 10 m
#'
#' @param ee Earth Engine module.
#' @param fields sf with `field_id`.
#' @return Tibble: field_id, elev_m.
field_elevation <- function(ee, fields) {
  fc <- sf_to_ee(ee, dplyr::select(fields, field_id))
  out <- dem_3dep(ee)$reduceRegions(
    collection = fc, reducer = ee$Reducer$mean(), scale = 10
  )$getInfo()
  tibble::tibble(
    field_id = purrr::map_chr(out$features, \(f) f$properties$field_id),
    elev_m = purrr::map_dbl(out$features, \(f) f$properties$mean)
  )
}
