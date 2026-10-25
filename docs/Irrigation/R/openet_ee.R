openet_models <- c("eemetric", "ssebop", "geesebal", "ptjpl", "sims", "disalexi")

openet_id <- function(model, version = "v2_1") {
  sprintf("projects/openet/assets/%s/conus/gridmet/monthly/%s", model, version)
}

#' Convert sf polygons to an Earth Engine FeatureCollection
#'
#' @param ee Earth Engine module from `ee_init()`.
#' @param x sf object; all non-geometry columns become properties.
#' @return ee.FeatureCollection in EPSG 4326.
sf_to_ee <- function(ee, x) {
  tmp <- tempfile(fileext = ".geojson")
  x |>
    sf::st_transform(4326) |>
    sf::st_write(tmp, quiet = TRUE, layer_options = "COORDINATE_PRECISION=6")
  ee$FeatureCollection(jsonlite::read_json(tmp))
}

#' One month of OpenET ET (ensemble plus six models) and ETo as one image
#'
#' @param ee Earth Engine module.
#' @param month_start Date, first day of the month.
#' @return ee.Image with bands `ensemble`, each model name, and `eto` (mm/month).
openet_month_image <- function(ee, month_start) {
  d0 <- format(month_start)
  d1 <- format(seq(month_start, by = "month", length.out = 2)[2])
  pick <- function(id, band, name) {
    ee$ImageCollection(id)$filterDate(d0, d1)$select(list(band), list(name))$mosaic()
  }
  imgs <- c(
    list(pick(openet_id("ensemble"), "et_ensemble_mad", "ensemble")),
    lapply(openet_models, \(m) pick(openet_id(m), "et", m)),
    list(pick("projects/openet/assets/reference_et/conus/gridmet/monthly/v1", "eto", "eto"))
  )
  ee$Image$cat(imgs)
}

#' Field mean monthly ET from OpenET on Earth Engine
#'
#' Runs one `reduceRegions` call per month so each request stays well under
#' the 5000 element limit.
#'
#' @param ee Earth Engine module.
#' @param polys sf polygons with `field_id` and `buffer_m`.
#' @param months Vector of month start Dates.
#' @return Tibble: field_id, buffer_m, month, variable, et_mm, n_pixels.
field_et_monthly <- function(ee, polys, months) {
  fc <- sf_to_ee(ee, dplyr::select(polys, field_id, buffer_m))
  reducer <- ee$Reducer$mean()$combine(ee$Reducer$count(), sharedInputs = TRUE)
  purrr::map(months, \(m) {
    out <- openet_month_image(ee, m)$reduceRegions(
      collection = fc, reducer = reducer, scale = 30, crs = "EPSG:32613"
    )$getInfo()
    purrr::map(out$features, \(f) tibble::as_tibble(purrr::compact(f$properties))) |>
      dplyr::bind_rows() |>
      dplyr::mutate(month = m)
  }, .progress = TRUE) |>
    dplyr::bind_rows() |>
    tidyr::pivot_longer(
      -c(field_id, buffer_m, month),
      names_to = c("variable", ".value"), names_pattern = "(.*)_(mean|count)"
    ) |>
    dplyr::rename(et_mm = mean, n_pixels = count) |>
    dplyr::distinct()
}
