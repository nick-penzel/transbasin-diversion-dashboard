#' Area-weighted SSURGO available water capacity for each field
#'
#' Queries Soil Data Access for map unit polygons under the fields (in
#' chunks), then weights the map unit `awc_r` (component-weighted mean over
#' 0 to 100 cm) by overlap area.
#'
#' @param fields sf polygons with `field_id`.
#' @param chunk Fields per SDA request.
#' @return Tibble: field_id, awc_mm_per_m, soil_frac (share of field with data).
field_awc <- function(fields, chunk = 50) {
  f <- sf::st_transform(fields, 4326)
  groups <- split(seq_len(nrow(f)), ceiling(seq_len(nrow(f)) / chunk))
  mu <- purrr::map(groups, \(i) {
    soilDB::SDA_spatialQuery(sf::st_union(f[i, ]), what = "mupolygon", geomIntersection = TRUE)
  }, .progress = TRUE) |>
    dplyr::bind_rows() |>
    sf::st_transform(26913)
  awc <- soilDB::get_SDA_property(
    property = "awc_r", method = "Weighted Average",
    mukeys = unique(mu$mukey), top_depth = 0, bottom_depth = 100
  ) |>
    dplyr::transmute(mukey = as.character(mukey), awc = awc_r)
  sf::st_intersection(dplyr::select(fields, field_id), dplyr::select(mu, mukey)) |>
    dplyr::mutate(area = as.numeric(sf::st_area(geometry)), mukey = as.character(mukey)) |>
    sf::st_drop_geometry() |>
    dplyr::left_join(awc, by = "mukey") |>
    dplyr::group_by(field_id) |>
    dplyr::summarise(
      soil_frac = sum(area[!is.na(awc)]) / sum(area),
      awc_mm_per_m = 1000 * stats::weighted.mean(awc, area, na.rm = TRUE),
      .groups = "drop"
    )
}
