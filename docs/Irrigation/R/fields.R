#' Default folder holding the CDSS Division 5 irrigated lands shapefiles
div5_dir <- function() {
  Sys.getenv(
    "DIV5_IRRIG_DIR",
    "/Users/nickpenzel/Documents/R Projects/GitHub_Repo/Ag_waterefficiency/Div5_Irrigated_Lands_Shapefiles"
  )
}

#' Read one HUC8 polygon from the project climate zones
#'
#' @param huc8 HUC8 code.
#' @param repo_root Repository root.
#' @return sf polygon in EPSG 26913.
read_huc8 <- function(huc8 = "14010004", repo_root = "../..") {
  file.path(repo_root, "data/reference/climate_zones.geojson") |>
    sf::st_read(quiet = TRUE) |>
    dplyr::filter(zone_id == huc8) |>
    sf::st_transform(26913)
}

#' Irrigated fields inside a HUC8 from the CDSS Division 5 layer
#'
#' A field belongs to the HUC8 when a point on its surface falls inside it.
#' Acres are recomputed from the geometry (EPSG 26913).
#'
#' @param huc8_poly sf polygon from `read_huc8()`.
#' @param year Irrigated lands layer year (2000, 2005, ..., 2023).
#' @return sf of fields with `field_id`, `crop`, `irrig_type`, `acres`, `sw_wdid1`.
read_fields <- function(huc8_poly, year = 2023) {
  x <- file.path(div5_dir(), sprintf("Div5_Irrig_%d.shp", year)) |>
    sf::st_read(quiet = TRUE) |>
    sf::st_transform(26913) |>
    sf::st_make_valid()
  inside <- lengths(sf::st_intersects(sf::st_point_on_surface(sf::st_geometry(x)), huc8_poly)) > 0
  x[inside, ] |>
    dplyr::transmute(
      field_id = as.character(PARCEL_ID),
      crop = tolower(CROP_TYPE),
      irrig_type = tolower(IRRIG_TYPE),
      crop_src = CROP_SRC,
      sw_wdid1 = SW_WDID1,
      acres = as.numeric(sf::st_area(geometry)) / 4046.873
    )
}

#' Shrink fields inward to drop edge pixels
#'
#' Fields too small to survive the buffer are dropped; `pick_buffer()` falls
#' back to their full outline.
#'
#' @param fields sf from `read_fields()`.
#' @param dist_m Inward distance in meters (positive number).
#' @return sf of the shrunk fields with a `buffer_m` column.
shrink_fields <- function(fields, dist_m = 30) {
  inner <- sf::st_buffer(fields, -dist_m)
  inner <- inner[!sf::st_is_empty(inner), ]
  inner$buffer_m <- dist_m
  inner
}

#' Keep one buffer per field: the shrunk outline if it keeps enough pixels
#'
#' @param x Tibble from `field_et_monthly()` with `field_id`, `buffer_m`, `n_pixels`.
#' @param dist_m Preferred inward buffer.
#' @param min_pixels Median ensemble pixels the shrunk outline must keep.
#' @return `x` with one buffer per field.
pick_buffer <- function(x, dist_m = 30, min_pixels = 10) {
  ok <- x |>
    dplyr::distinct() |>
    dplyr::filter(buffer_m == dist_m, variable == "ensemble") |>
    dplyr::group_by(field_id) |>
    dplyr::summarise(px = stats::median(n_pixels, na.rm = TRUE)) |>
    dplyr::filter(px >= min_pixels)
  x |>
    dplyr::distinct() |>
    dplyr::filter(buffer_m == ifelse(field_id %in% ok$field_id, dist_m, 0))
}
