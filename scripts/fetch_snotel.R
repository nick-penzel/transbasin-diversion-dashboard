# Fetch NRCS SNOTEL daily data for Colorado from the AWDB REST API (no key).
# Values arrive in inches and degrees F and are stored in mm and degrees C.

library(httr2)
library(dplyr)
library(tibble)

awdb_url <- "https://wcc.sc.egov.usda.gov/awdbRestApi/services/v1"

# AWDB element code, stored column, and unit conversion
snotel_elements <- tribble(
  ~element, ~column,         ~convert,
  "WTEQ",   "swe_mm",        \(x) x * 25.4,
  "SNWD",   "snow_depth_mm", \(x) x * 25.4,
  "PREC",   "prcp_accum_mm", \(x) x * 25.4,
  "PRCP",   "prcp_mm",       \(x) x * 25.4,
  "TMAX",   "tmax_c",        \(x) (x - 32) * 5 / 9,
  "TMIN",   "tmin_c",        \(x) (x - 32) * 5 / 9,
  "TAVG",   "tavg_c",        \(x) (x - 32) * 5 / 9
)

#' Water year (Oct 1 to Sep 30, named by the ending year).
water_year <- function(date) {
  as.integer(format(date, "%Y")) + (as.integer(format(date, "%m")) >= 10)
}

#' Empty tibble with the full snotel daily column set.
empty_snotel <- function() {
  tibble(site_id = character(), date = as.Date(character()), wy = integer(),
         swe_mm = numeric(), snow_depth_mm = numeric(), prcp_accum_mm = numeric(),
         prcp_mm = numeric(), tmax_c = numeric(), tmin_c = numeric(),
         tavg_c = numeric())
}

#' Blank out sensor errors: temperatures outside what these high sites see
#' (some are error codes like -51.3 C) and negative snow or precip.
qc_snotel <- function(df) {
  mutate(df,
    tmax_c = if_else(between(tmax_c, -40, 38), tmax_c, NA_real_),
    tmin_c = if_else(between(tmin_c, -45, 30), tmin_c, NA_real_),
    tavg_c = if_else(between(tavg_c, -45, 35), tavg_c, NA_real_),
    across(c(swe_mm, snow_depth_mm, prcp_accum_mm, prcp_mm), \(x) if_else(x >= 0, x, NA_real_))
  )
}

#' All Colorado SNOTEL stations, including inactive ones.
fetch_snotel_sites <- function() {
  sites <- request(awdb_url) |>
    req_url_path_append("stations") |>
    req_url_query(stationTriplets = "*:CO:SNTL", activeOnly = "false",
                  returnStationElements = "false") |>
    req_timeout(60) |>
    req_retry(max_tries = 3, retry_on_failure = TRUE) |>
    req_perform() |>
    resp_body_json(simplifyVector = FALSE)

  tibble(
    site_id    = vapply(sites, \(s) s$stationId, ""),
    triplet    = vapply(sites, \(s) s$stationTriplet, ""),
    name       = vapply(sites, \(s) s$name, ""),
    latitude   = vapply(sites, \(s) as.numeric(s$latitude), 0),
    longitude  = vapply(sites, \(s) as.numeric(s$longitude), 0),
    elev_m     = vapply(sites, \(s) as.numeric(s$elevation) * 0.3048, 0),
    county     = vapply(sites, \(s) s$countyName %||% NA_character_, ""),
    huc12      = vapply(sites, \(s) s$huc %||% NA_character_, ""),
    begin_date = as.Date(substr(vapply(sites, \(s) s$beginDate, ""), 1, 10)),
    end_date   = as.Date(substr(vapply(sites, \(s) s$endDate, ""), 1, 10))
  ) |>
    mutate(active = end_date > Sys.Date()) |>
    arrange(site_id)
}

#' Daily SNOTEL values for a set of station triplets, one request.
fetch_snotel <- function(triplets, start_date, end_date) {
  body <- request(awdb_url) |>
    req_url_path_append("data") |>
    req_url_query(
      stationTriplets = paste(triplets, collapse = ","),
      elements        = paste(snotel_elements$element, collapse = ","),
      duration        = "DAILY",
      beginDate       = format(as.Date(start_date)),
      endDate         = format(as.Date(end_date))
    ) |>
    req_timeout(60) |>
    req_retry(max_tries = 3, retry_on_failure = TRUE) |>
    req_perform() |>
    resp_body_json(simplifyVector = FALSE)

  long <- bind_rows(lapply(body, function(station) {
    bind_rows(lapply(station$data, function(el) {
      if (length(el$values) == 0) return(NULL)
      tibble(
        site_id = sub(":.*", "", station$stationTriplet),
        element = el$stationElement$elementCode,
        date    = as.Date(vapply(el$values, \(v) v$date, "")),
        value   = vapply(el$values, \(v) as.numeric(v$value %||% NA), 0)
      )
    }))
  }))
  if (nrow(long) == 0) return(empty_snotel())

  long |>
    inner_join(snotel_elements, by = "element") |>
    mutate(value = convert[[1]](value), .by = element) |>
    select(site_id, date, column, value) |>
    tidyr::pivot_wider(names_from = column, values_from = value) |>
    bind_rows(empty_snotel()) |>
    mutate(wy = water_year(date)) |>
    select(names(empty_snotel())) |>
    qc_snotel()
}

#' Daily SNOTEL values for many sites in chunks; failed chunks are logged.
fetch_snotel_many <- function(sites, start_date, end_date, chunk = 20, pause = 1) {
  groups <- split(sites$triplet, ceiling(seq_along(sites$triplet) / chunk))
  bind_rows(lapply(seq_along(groups), function(i) {
    message(sprintf("[%d/%d] SNOTEL %s to %s", i, length(groups), start_date, end_date))
    Sys.sleep(pause)
    tryCatch(
      fetch_snotel(groups[[i]], start_date, end_date),
      error = function(e) {
        message("  -> FAILED: ", conditionMessage(e))
        NULL
      }
    )
  }), empty_snotel()) |>
    filter(!if_all(swe_mm:tavg_c, is.na)) |>
    distinct(site_id, date, .keep_all = TRUE)
}
