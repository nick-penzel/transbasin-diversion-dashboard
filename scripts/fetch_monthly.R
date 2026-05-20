# Fetch monthly diversion records (divrec) for a structure by WDID.
# Self-contained: no dependencies on other project scripts.
#
# Endpoint: structures/divrec/divrecmonth
# Returns monthly diverted volume in acre-feet, converted to mean cfs.

library(httr2)
library(dplyr)
library(tibble)
library(lubridate)

api_key <- trimws(readLines("scripts/api_key.txt", warn = FALSE)[1])


fetch_monthly <- function(wdid, start_year, end_year = year(Sys.Date())) {
  resp <- request("https://dwr.state.co.us/Rest/GET/api/v2") |>
    req_url_path_append("structures/divrec/divrecmonth") |>
    req_url_query(
      format             = "json",
      wdid               = wdid,
      `min-dataMeasDate` = sprintf("01/%d", start_year),
      `max-dataMeasDate` = sprintf("12/%d", end_year),
      pageSize           = 50000,
      apiKey             = api_key
    ) |>
    req_perform()
  
  rows <- resp_body_json(resp, simplifyVector = FALSE)$ResultList
  if (length(rows) == 0) {
    message(sprintf("WDID %s: no monthly records", wdid))
    return(NULL)
  }
  
  bind_rows(lapply(rows, function(r) {
    month_start <- as.Date(paste0(r$dataMeasDate, "-01"))
    af <- as.numeric(r$dataValue %||% NA)
    days <- as.integer(days_in_month(month_start))
    tibble(
      wdid         = wdid,
      year         = year(month_start),
      month        = month(month_start),
      month_start  = month_start,
      diversion_af = af,
      mean_cfs     = af / (1.9835 * days)
    )
  })) |>
    # CDSS returns multiple water classes per month; the largest diversion_af
    # value per month is DivTotal (everything through the headgate).
    group_by(month_start) |>
    slice_max(diversion_af, n = 1, with_ties = FALSE) |>
    ungroup() |>
    arrange(month_start)
}


fetch_monthly_many <- function(wdids, start_year, end_year = year(Sys.Date())) {
  bind_rows(lapply(seq_along(wdids), function(i) {
    message(sprintf("[%d/%d] %s", i, length(wdids), wdids[i]))
    Sys.sleep(0.3)
    fetch_monthly(wdids[i], start_year, end_year)
  }))
}