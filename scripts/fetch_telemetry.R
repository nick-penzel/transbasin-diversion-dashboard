# fetch_telemetry.R

library(httr2)
library(dplyr)
library(tibble)

api_key <- trimws(readLines("scripts/api_key.txt", warn = FALSE)[1])


#' Fetch yesterday's daily mean discharge for one structure.
#' Caller provides the telemetry abbrev and parameter.
fetch_yesterday <- function(wdid, abbrev, parameter, target_date = Sys.Date() - 1) {
  if (is.na(abbrev)) return(NULL) 
  
  resp <- request("https://dwr.state.co.us/Rest/GET/api/v2") %>%
    req_url_path_append("telemetrystations/telemetrytimeseriesday") %>%
    req_url_query(
      format         = "json",
      abbrev         = abbrev,
      parameter      = parameter,
      `min-measDate` = format(as.Date(target_date), "%m/%d/%Y"),
      `max-measDate` = format(as.Date(target_date), "%m/%d/%Y"),
      apiKey         = api_key
    ) %>%
    req_perform()
  
  rows <- resp_body_json(resp, simplifyVector = FALSE)$ResultList
  if (length(rows) == 0) return(NULL)
  
  r <- rows[[1]]
  tibble(
    wdid          = wdid,
    abbrev        = abbrev,
    date          = as.Date(substr(r$measDate, 1, 10)),
    discharge_cfs = as.numeric(r$measValue %||% NA),
    parameter     = parameter,
    meas_count    = as.integer(r$measCount %||% NA),
    flag_a        = r$flagA %||% NA_character_
  )
}


#' Fetch yesterday's discharge for many structures from a structures table

fetch_yesterday_many <- function(structures, target_date = Sys.Date() - 1, pause = 0.3) {

  to_fetch <- structures %>% filter(!is.na(abbrev))
  
  bind_rows(lapply(seq_len(nrow(to_fetch)), function(i) {
    s <- to_fetch[i, ]
    message(sprintf("[%d/%d] %s", i, nrow(to_fetch), s$wdid))
    Sys.sleep(pause)
    tryCatch(
      fetch_yesterday(s$wdid, s$abbrev, s$parameter, target_date),
      error = function(e) {
        message("  -> FAILED: ", conditionMessage(e))
        NULL
      }
    )
  }))
}