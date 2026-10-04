# Fetch daily mean discharge from CDSS telemetry stations for diversion
# structures.

library(httr2)
library(dplyr)
library(tibble)

api_key <- trimws(readLines("scripts/api_key.txt", warn = FALSE)[1])


#' Daily telemetry for one structure between two dates (inclusive).
fetch_telemetry <- function(wdid, abbrev, parameter, start_date, end_date) {
  if (is.na(abbrev)) return(NULL)

  resp <- request("https://dwr.state.co.us/Rest/GET/api/v2") |>
    req_url_path_append("telemetrystations/telemetrytimeseriesday") |>
    req_url_query(
      format    = "json",
      abbrev    = abbrev,
      parameter = parameter,
      # This endpoint ignores min-/max-measDate and returns the last year
      startDate = format(as.Date(start_date), "%m/%d/%Y"),
      endDate   = format(as.Date(end_date), "%m/%d/%Y"),
      pageSize  = 50000,
      apiKey    = api_key
    ) |>
    req_perform()

  rows <- resp_body_json(resp, simplifyVector = FALSE)$ResultList
  if (length(rows) == 0) return(NULL)

  bind_rows(lapply(rows, function(r) {
    tibble(
      wdid          = wdid,
      abbrev        = abbrev,
      date          = as.Date(substr(r$measDate, 1, 10)),
      discharge_cfs = as.numeric(r$measValue %||% NA),
      parameter     = parameter,
      meas_count    = as.integer(r$measCount %||% NA),
      flag_a        = r$flagA %||% NA_character_
    )
  })) |>
    filter(date >= as.Date(start_date), date <= as.Date(end_date))
}


#' Daily telemetry for every structure with a telemetry abbrev.
fetch_telemetry_many <- function(structures, start_date, end_date, pause = 0.3) {
  to_fetch <- structures |> filter(!is.na(abbrev))

  bind_rows(lapply(seq_len(nrow(to_fetch)), function(i) {
    s <- to_fetch[i, ]
    message(sprintf("[%d/%d] %s", i, nrow(to_fetch), s$wdid))
    Sys.sleep(pause)
    tryCatch(
      fetch_telemetry(s$wdid, s$abbrev, s$parameter, start_date, end_date),
      error = function(e) {
        message("  -> FAILED: ", conditionMessage(e))
        NULL
      }
    )
  }))
}
