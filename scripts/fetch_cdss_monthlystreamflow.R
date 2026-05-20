# Fetch monthly surface water time series from CDSS for a station abbreviation
# and date range.
#
# Endpoint: /surfacewater/surfacewatertsmonth/
# Filters by min-calYear / max-calYear (not measDate — note the difference
# from the daily endpoint, which does use measDate).
#
# Native field names from CDSS (after lowercasing/snake_case normalization,
# matching the cdssr package convention):
#   cal_year, cal_mon_num, avg_qcfs, min_qcfs, max_qcfs, meas_count, modified

library(httr2)
library(dplyr)
library(tibble)
library(purrr)
library(lubridate)

API_BASE     <- "https://dwr.state.co.us/Rest/GET/api/v2"
USER_AGENT   <- "CO-Water-Dashboard/0.1"
API_KEY_FILE <- "cdss_apikey.txt"
PAGE_SIZE    <- 50000


read_api_key <- function(path = API_KEY_FILE) {
  if (!file.exists(path)) {
    warning("API key file not found at '", path, "'; making anonymous requests")
    return("")
  }
  trimws(readLines(path, warn = FALSE)[1])
}

.CDSS_API_KEY <- read_api_key()


#' Snake_case the camelCase field names CDSS returns, matching cdssr's convention.
clean_names <- function(x) {
  gsub(" ", "_", tolower(gsub("(.)([A-Z])", "\\1 \\2", x)))
}


#' GET a CDSS endpoint with pagination, return all rows as a list of records.
cdss_get_paged <- function(path, params = list()) {
  if (nzchar(.CDSS_API_KEY)) params$apiKey <- .CDSS_API_KEY
  params$format    <- "json"
  params$pageSize  <- PAGE_SIZE
  params$pageIndex <- 1
  
  all_rows <- list()
  repeat {
    resp <- request(API_BASE) |>
      req_url_path_append(path) |>
      req_url_query(!!!params) |>
      req_user_agent(USER_AGENT) |>
      req_timeout(60) |>
      req_perform()
    
    body <- resp_body_json(resp, simplifyVector = FALSE)
    page <- body$ResultList %||% list()
    all_rows <- c(all_rows, page)
    
    if (length(page) < PAGE_SIZE) break
    params$pageIndex <- params$pageIndex + 1
  }
  all_rows
}


#' Fetch monthly surface water time series for one station.
#'
#' @param abbrev     CDSS station abbreviation (e.g. "CLAFTCCO").
#' @param start_date Date or "YYYY-MM-DD". Filtered by calendar year only;
#'                   day and month are ignored, you get the full start year.
#' @param end_date   Date or "YYYY-MM-DD". Filtered by calendar year only;
#'                   you get the full end year through December.
#' @return Tibble with one row per month, sorted by date.
fetch_monthly_streamflow <- function(abbrev, start_date, end_date) {
  start_date <- as.Date(start_date)
  end_date   <- as.Date(end_date)
  if (start_date > end_date) stop("start_date must be on or before end_date")
  
  rows <- cdss_get_paged(
    "surfacewater/surfacewatertsmonth",
    list(
      abbrev        = abbrev,
      `min-calYear` = year(start_date),
      `max-calYear` = year(end_date),
      dateFormat    = "spaceSepToSeconds"
    )
  )
  
  if (length(rows) == 0) {
    return(tibble(
      abbrev      = character(),
      year        = integer(),
      month       = integer(),
      month_start = as.Date(character()),
      avg_qcfs    = numeric(),
      min_qcfs    = numeric(),
      max_qcfs    = numeric(),
      total_af    = numeric(),
      meas_count  = integer(),
      modified    = character()
    ))
  }
  
  # Normalize each record's keys, then build the tibble
  bind_rows(lapply(rows, function(r) {
    names(r) <- clean_names(names(r))
    
    yr  <- as.integer(r$cal_year %||% NA)
    mo  <- as.integer(r$cal_mon_num %||% NA)
    avg <- as.numeric(r$avg_qcfs %||% NA)
    
    month_start <- if (!is.na(yr) && !is.na(mo)) {
      as.Date(sprintf("%04d-%02d-01", yr, mo))
    } else {
      as.Date(NA)
    }
    
    days <- if (!is.na(month_start)) as.integer(days_in_month(month_start)) else NA_integer_
    total_af <- if (!is.na(avg) && !is.na(days)) avg * 1.9835 * days else NA_real_
    
    tibble(
      abbrev      = abbrev,
      year        = yr,
      month       = mo,
      month_start = month_start,
      avg_qcfs    = avg,
      min_qcfs    = as.numeric(r$min_qcfs %||% NA),
      max_qcfs    = as.numeric(r$max_qcfs %||% NA),
      total_af    = total_af,
      meas_count  = as.integer(r$meas_count %||% NA),
      modified    = r$modified %||% NA_character_
    )
  })) |>
    arrange(month_start)
}


fetch_monthly_streamflow_many <- function(abbrevs, start_date, end_date, pause = 0.3) {
  results <- map(abbrevs, function(a) {
    Sys.sleep(pause)
    tryCatch(
      fetch_monthly_streamflow(a, start_date, end_date),
      error = function(e) {
        message(sprintf("Station %s: %s", a, conditionMessage(e)))
        NULL
      }
    )
  })
  bind_rows(results)
}


# ---- Demo when run directly ----
if (sys.nframe() == 0) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) < 3) {
    message("Usage: Rscript fetch_monthly_streamflow.R <abbrev> <start_date> <end_date>")
    message("Running demo: CLAFTCCO 2020-2024")
    out <- fetch_monthly_streamflow("CLAFTCCO", "2020-01-01", "2024-12-31")
  } else {
    out <- fetch_monthly_streamflow(args[1], args[2], args[3])
  }
  print(out)
}


