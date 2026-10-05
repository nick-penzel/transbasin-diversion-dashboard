# Fetch monthly diversion records (divrec) for a structure by WDID.
# Self-contained: no dependencies on other project scripts.
#
# Endpoint: structures/divrec/divrecmonth
# Returns every water class per month in acre-feet and mean cfs; use
# monthly_total() for the headgate total.

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
    tibble(
      wdid          = wdid,
      year          = year(month_start),
      month         = month(month_start),
      month_start   = month_start,
      wc_identifier = r$wcIdentifier %||% NA_character_,
      diversion_af  = af,
      mean_cfs      = af / (1.9835 * days_in_month(month_start))
    )
  })) |>
    arrange(month_start)
}

#' One headgate total per month from all water classes.
#'
#' Per the DWR Diversion Records Standard, the "total through headgate"
#' record is the administrative class S:X U:Q T:0. When a month lacks it,
#' fall back to the largest class.
monthly_total <- function(classes) {
  classes |>
    mutate(is_total = grepl("S:X .*U:Q T:0", wc_identifier)) |>
    group_by(wdid, month_start) |>
    arrange(desc(is_total), desc(diversion_af), .by_group = TRUE) |>
    slice(1) |>
    ungroup() |>
    select(-wc_identifier, -is_total)
}

fetch_monthly_many <- function(wdids, start_year, end_year = year(Sys.Date())) {
  bind_rows(lapply(seq_along(wdids), function(i) {
    message(sprintf("[%d/%d] %s", i, length(wdids), wdids[i]))
    Sys.sleep(0.3)
    tryCatch(
      fetch_monthly(wdids[i], start_year, end_year),
      error = function(e) {
        message(sprintf("  -> FAILED: %s", conditionMessage(e)))
        NULL
      }
    )
  }))
}