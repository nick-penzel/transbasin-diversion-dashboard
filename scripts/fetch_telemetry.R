# Fetch yesterday's daily mean discharge (cfs) for a CDSS structure given its WDID.
#
# Workflow:
#   1. Query /telemetrystations/ filtered by wdid -> get telemetry abbrev(s)
#   2. Query /telemetrystations/telemetrytimeseriesday/ for yesterday's value
#   3. Return a tidy tibble row (or NULL if no telemetry / no data for that day)
#
# Reads API key from a local text file (default: api_key.txt next to this script).
# Anonymous requests work but are rate-limited as of Dec 2025 — get a free key
# at https://dwr.state.co.us/Rest/GET/Help.

library(httr2)
library(dplyr)
library(tibble)
library(purrr)

API_BASE     <- "https://dwr.state.co.us/Rest/GET/api/v2"
USER_AGENT   <- "CO-Water-Dashboard/0.1"
API_KEY_FILE <- "data/cdss_apikey.txt"


#' Read the API key from a text file. Returns "" if the file is missing.
read_api_key <- function(path = API_KEY_FILE) {
  if (!file.exists(path)) {
    warning("API key file not found at '", path, "'; making anonymous requests")
    return("")
  }
  trimws(readLines(path, warn = FALSE)[1])
}

# Read once at source-time so we don't hit the disk on every request
.CDSS_API_KEY <- read_api_key()

# CDSS expects MM/DD/YYYY in query params
fmt_date <- function(d) format(as.Date(d), "%m/%d/%Y")


#' GET an API endpoint and return the ResultList as a list of records.
cdss_get <- function(path, params = list()) {
  if (nzchar(.CDSS_API_KEY)) params$apiKey <- .CDSS_API_KEY
  params$format <- "json"

  resp <- request(API_BASE) |>
    req_url_path_append(path) |>
    req_url_query(!!!params) |>
    req_user_agent(USER_AGENT) |>
    req_timeout(30) |>
    req_perform()

  body <- resp_body_json(resp, simplifyVector = FALSE)
  body$ResultList %||% list()
}


#' Find telemetry station(s) associated with a WDID.
#'
#' Most structures with telemetry have one station; some have multiple
#' (e.g. inflow + outflow). Caller decides which to use.
find_telemetry_abbrev <- function(wdid) {
  cdss_get("telemetrystations/telemetrystation", list(wdid = wdid))
}


#' Fetch daily timeseries from telemetrytimeseriesday for [start, end] inclusive.
get_daily_discharge <- function(abbrev, start, end, parameter = "DISCHRG") {
  cdss_get(
    "telemetrystations/telemetrytimeseriesday",
    list(
      abbrev    = abbrev,
      parameter = parameter,
      startDate = fmt_date(start),
      endDate   = fmt_date(end)
    )
  )
}


#' Get yesterday's daily mean discharge (cfs) for a structure by WDID.
#'
#' Returns NULL when the WDID has no telemetry station, or a tibble row when
#' a station exists. If the station exists but has no value for the date,
#' discharge_cfs will be NA and `note` will explain why — that's the signal
#' to fall back to divrec.

fetch_yesterday <- function(wdid, target_date = Sys.Date() - 1) {
  stations <- find_telemetry_abbrev(wdid)
  if (length(stations) == 0) return(NULL)

  # Take the first station; report count so caller can flag multi-station WDIDs
  station <- stations[[1]]
  abbrev  <- station$abbrev
  if (is.null(abbrev)) return(NULL)

  # Stations report under different parameter codes (DISCHRG, DISCHRG2, DISCHRG3).
  # Use what the station tells us; fall back to DISCHRG if the field is missing.
  
  parameter <- station$parameter %||% "DISCHRG"

  rows <- get_daily_discharge(abbrev, target_date, target_date, parameter = parameter)

  if (length(rows) == 0) {
    return(tibble(
      wdid             = wdid,
      abbrev           = abbrev,
      station_name     = station$stationName %||% NA_character_,
      date             = target_date,
      meas_date        = as.Date(NA),
      parameter        = parameter,
      discharge_cfs    = NA_real_,
      units            = NA_character_,
      flag_a           = NA_character_,
      flag_b           = NA_character_,
      meas_count       = NA_integer_,
      modified         = NA_character_,
      n_stations_found = length(stations),
      note             = "telemetry station exists but no data for this date"
    ))
  }

  row <- rows[[1]]
  tibble(
    wdid             = wdid,
    abbrev           = abbrev,
    station_name     = station$stationName %||% NA_character_,
    date             = target_date,
    meas_date        = as.Date(substr(row$measDate %||% "", 1, 10)),
    parameter        = parameter,
    discharge_cfs    = as.numeric(row$measValue %||% NA),
    units            = row$measUnit %||% "cfs",
    flag_a           = row$flagA %||% NA_character_,
    flag_b           = row$flagB %||% NA_character_,
    meas_count       = row$measCount %||% NA_integer_,
    modified         = row$modified %||% NA_character_,
    n_stations_found = length(stations),
    note             = NA_character_
  )
}


#' Convenience wrapper: fetch many WDIDs and bind into one tibble.
#'
#' WDIDs with no telemetry are dropped from the result; track them separately
#' so you know which ones need the divrec fallback.

fetch_yesterday_many <- function(wdids, target_date = Sys.Date() - 1, pause = 0.3) {
  results <- map(wdids, function(w) {
    Sys.sleep(pause)  # be polite to the API
    tryCatch(
      fetch_yesterday(w, target_date),
      error = function(e) {
        message(sprintf("WDID %s: %s", w, conditionMessage(e)))
        NULL
      }
    )
  })

  bind_rows(results)
}

