#' Reclamation incidental use share for Colorado main stem HUC8s (C-7 to C-13)
incidental_use_frac <- 0.189

mm_to_af <- function(mm, acres) mm / 304.8 * acres

water_year <- function(d) as.integer(format(d, "%Y")) + (as.integer(format(d, "%m")) >= 10)

#' Irrigation year, November to October, labeled by the year it ends in
#'
#' Matches DWR diversion records and Reclamation's CU&L accounting year.
irr_year <- function(d) as.integer(format(d, "%Y")) + (as.integer(format(d, "%m")) >= 11)

#' Field-month ET in wide form, with winter ensemble gaps filled
#'
#' The ensemble is missing in some snow-covered months; those take the mean
#' of the models that reported. Missing eeMETRIC, SSEBop, or geeSEBAL months
#' take the ensemble.
#' A month with no model at all (tiny fields in winter) is set to zero.
#'
#' @param et Tibble from `field_et_monthly()` after `pick_buffer()`.
#' @return Tibble: field_id, month, one column per variable, `ens_filled`.
et_wide <- function(et) {
  et |>
    dplyr::select(field_id, month, variable, et_mm) |>
    tidyr::pivot_wider(names_from = variable, values_from = et_mm) |>
    dplyr::mutate(
      model_mean = rowMeans(dplyr::pick(dplyr::all_of(openet_models)), na.rm = TRUE),
      ens_filled = is.na(ensemble),
      ensemble = dplyr::coalesce(ensemble, model_mean),
      dplyr::across(c(eemetric, ssebop, geesebal), \(v) dplyr::coalesce(v, ensemble)),
      dplyr::across(c(ensemble, eemetric, ssebop, geesebal), \(v) dplyr::coalesce(v, 0))
    )
}

#' Irrigation status from Reclamation's Colorado EToF rule
#'
#' Irrigated when monthly eeMETRIC EToF exceeds 0.4 in three or more months
#' from May to October of one calendar year (Reclamation, 2025). Kept for
#' comparison with `irrigation_status_relative()`. The season is labeled with
#' its calendar year, which is also its irrigation year.
#'
#' @param w Tibble from `et_wide()`.
#' @return Tibble: field_id, iy, n_months, months_wet, irrigated.
irrigation_status <- function(w, threshold = 0.4, min_months = 3) {
  field_month_wet(w, threshold) |>
    dplyr::mutate(iy = as.integer(format(month, "%Y")), m = as.integer(format(month, "%m"))) |>
    dplyr::filter(m %in% 5:10) |>
    dplyr::group_by(field_id, iy) |>
    dplyr::summarise(n_months = dplyr::n(), months_wet = sum(wet), .groups = "drop") |>
    dplyr::mutate(irrigated = months_wet >= min_months)
}

#' Irrigation status from field EToF above the native reference
#'
#' A month is wet when the field's eeMETRIC EToF exceeds the reference EToF
#' in its elevation band by more than `excess`. Irrigated: wet in July or
#' August. Shorted: not wet in July or August but wet in May or June, the
#' mid-season dry-up Reclamation's shorted class describes. Fallow: neither.
#'
#' @param w Tibble from `et_wide()`.
#' @param ref_etof Tibble: field_id, month, ref_etof.
#' @return List: `status` (field_id, iy, irrigated, shorted) and `wet`
#'   (field_id, month, wet).
irrigation_status_relative <- function(w, ref_etof, excess = 0.2) {
  wet <- w |>
    dplyr::inner_join(ref_etof, by = c("field_id", "month")) |>
    dplyr::transmute(field_id, month, wet = dplyr::coalesce(eemetric / eto - ref_etof > excess, FALSE))
  status <- wet |>
    dplyr::mutate(iy = as.integer(format(month, "%Y")), m = as.integer(format(month, "%m"))) |>
    dplyr::filter(m %in% 5:8) |>
    dplyr::group_by(field_id, iy) |>
    dplyr::summarise(
      irrigated = any(wet[m %in% 7:8]),
      shorted = !irrigated & any(wet[m %in% 5:6]),
      .groups = "drop"
    )
  list(status = status, wet = wet)
}

#' Field months with eeMETRIC EToF above the irrigation threshold
#'
#' @param w Tibble from `et_wide()`.
#' @return Tibble: field_id, month, wet.
field_month_wet <- function(w, threshold = 0.4) {
  w |>
    dplyr::transmute(field_id, month, wet = dplyr::coalesce(eemetric / eto > threshold, FALSE))
}

#' Method A: CUirr = ETa - effective precipitation, with carry-forward
#'
#' When a month's effective precipitation exceeds ETa, the remainder carries
#' into the next month (Reclamation, 2025). The carry resets each irrigation
#' year (November).
#'
#' @param eta Tibble: field_id, month, eta_mm.
#' @param pe Tibble: field_id, month, pe_mm.
#' @return Tibble: field_id, month, eta_mm, pe_mm, cu_mm.
cu_method_a <- function(eta, pe) {
  x <- dplyr::inner_join(eta, pe, by = c("field_id", "month"))
  stopifnot(nrow(x) == nrow(eta))
  x |>
    dplyr::mutate(iy = irr_year(month)) |>
    dplyr::arrange(field_id, month) |>
    dplyr::group_by(field_id, iy) |>
    dplyr::mutate(cu_mm = {
      carry <- 0
      purrr::map2_dbl(eta_mm, pe_mm, \(e, p) {
        avail <- p + carry
        carry <<- max(0, avail - e)
        max(0, e - avail)
      })
    }) |>
    dplyr::ungroup() |>
    dplyr::select(field_id, month, eta_mm, pe_mm, cu_mm)
}

#' Reference ET for each field from its elevation band
#'
#' Bands with fewer than `min_pixels` reference pixels in a month borrow the
#' nearest band that has enough.
#'
#' @param ref Tibble from `reference_et_monthly()`, one variable.
#' @param elev Tibble: field_id, elev_m.
#' @return Tibble: field_id, month, ref_mm, ref_band.
field_reference <- function(ref, elev, min_pixels = 500) {
  ok <- dplyr::filter(ref, n_pixels >= min_pixels, !is.na(et_mm))
  elev |>
    dplyr::mutate(band = floor(elev_m / 100) * 100) |>
    dplyr::cross_join(dplyr::distinct(ok, month)) |>
    dplyr::left_join(ok, by = "month", relationship = "many-to-many") |>
    dplyr::group_by(field_id, month) |>
    dplyr::slice_min(abs(elev_band - band), n = 1, with_ties = FALSE) |>
    dplyr::ungroup() |>
    dplyr::select(field_id, month, ref_mm = et_mm, ref_band = elev_band)
}

#' Method B: CUirr = ETa(field) - ETa(non-irrigated reference), by month
#'
#' Monthly differences may be negative; season and year totals are floored
#' at zero per field when summarised.
#'
#' @param eta Tibble: field_id, month, eta_mm.
#' @param fref Tibble from `field_reference()`.
#' @return Tibble: field_id, month, eta_mm, ref_mm, cu_mm.
cu_method_b <- function(eta, fref) {
  x <- dplyr::inner_join(eta, fref, by = c("field_id", "month"))
  stopifnot(nrow(x) == nrow(eta))
  x |>
    dplyr::mutate(cu_mm = eta_mm - ref_mm) |>
    dplyr::select(field_id, month, eta_mm, ref_mm, cu_mm)
}

#' Sum monthly CU to a period per field and convert to acre-feet
#'
#' Irrigated fields count every month. Shorted fields count only April to
#' October months they were wet (`wet`), and other fields count nothing.
#'
#' @param cu Tibble with field_id, month, cu_mm.
#' @param fields Tibble: field_id, iy, acres, irrigated, shorted.
#' @param wet Tibble from `field_month_wet()`.
#' @param months Integer months to include (default May to September).
#' @return Tibble per field and irrigation year: cu_mm, cu_af, net_cu_af.
cu_period <- function(cu, fields, wet, months = 5:9) {
  cu |>
    dplyr::filter(as.integer(format(month, "%m")) %in% months) |>
    dplyr::left_join(wet, by = c("field_id", "month")) |>
    dplyr::mutate(iy = irr_year(month)) |>
    dplyr::group_by(field_id, iy) |>
    dplyr::summarise(
      cu_all = max(0, sum(cu_mm)),
      cu_wet = max(0, sum(cu_mm[wet %in% TRUE & as.integer(format(month, "%m")) %in% 4:10])),
      .groups = "drop"
    ) |>
    dplyr::left_join(fields, by = c("field_id", "iy")) |>
    dplyr::mutate(
      cu_mm = dplyr::case_when(irrigated ~ cu_all, shorted ~ cu_wet, .default = 0),
      cu_af = mm_to_af(cu_mm, acres),
      net_cu_af = cu_af * (1 + incidental_use_frac)
    ) |>
    dplyr::select(-cu_all, -cu_wet)
}

#' Monthly irrigation window for each field from ditch records and status
#'
#' A month is open when it falls between the first and last month its ditches
#' recorded irrigation that irrigation year, capped to April to October (some
#' ditches record stock or domestic flow as irrigation in winter). Shorted
#' fields are open only in their wet months, and inside the ditch window when
#' one is known. Months with no ditch window and no status are NA, which
#' `field_cu_bucket()` fills with the modeled growing season.
#'
#' @param win Tibble: field_id, iy, first_month, last_month.
#' @param status Tibble: field_id, iy, shorted.
#' @param wet Tibble: field_id, month, wet.
#' @param field_ids All field ids.
#' @param months Month start Dates covering the balance.
#' @return Tibble: field_id, month, open.
irrigation_window <- function(win, status, wet, field_ids, months) {
  idx <- \(m) (m - 11) %% 12
  tidyr::expand_grid(field_id = field_ids, month = months) |>
    dplyr::mutate(iy = irr_year(month), m = as.integer(format(month, "%m"))) |>
    dplyr::left_join(win, by = c("field_id", "iy")) |>
    dplyr::left_join(dplyr::select(status, field_id, iy, shorted), by = c("field_id", "iy")) |>
    dplyr::left_join(wet, by = c("field_id", "month")) |>
    dplyr::mutate(
      open = dplyr::if_else(is.na(first_month), NA, idx(m) >= idx(first_month) & idx(m) <= idx(last_month) & m %in% 4:10),
      open = dplyr::if_else(shorted %in% TRUE, !(open %in% FALSE) & wet %in% TRUE, open)
    ) |>
    dplyr::select(field_id, month, open)
}
