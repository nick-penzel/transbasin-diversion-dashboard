# Fetch yesterday's daily streamflow for a list of gages.
# Handles two sources via source-specific batched calls:
#   USGS  - read_waterdata_daily, batched by vector of site numbers
#   CDSS  - surfacewatertsday endpoint, one call per CDSS abbrev
#
# Returns a single tibble with unified columns regardless of source:
#   id, date, flow_cfs, source

suppressPackageStartupMessages({
  library(dplyr)
  library(tibble)
  library(httr2)
  library(dataRetrieval)
})

api_key <- trimws(readLines("scripts/api_key.txt", warn = FALSE)[1])


# ---- USGS: one batched call for all sites ----
fetch_usgs_yesterday <- function(gage_ids, target_date) {
  daily <- read_waterdata_daily(
    monitoring_location_id = gage_ids,
    parameter_code = "00060",
    time = c(as.character(target_date), as.character(target_date))
  )
  if (nrow(daily) == 0) return(NULL)

  daily %>%
    sf::st_drop_geometry() %>% 
    transmute(
      id       = monitoring_location_id,
      date     = as.Date(time),
      flow_cfs = value,
      source   = "USGS"
    ) 
}


# ---- CDSS: one call per abbrev (surface water daily endpoint) ----
fetch_cdss_yesterday <- function(abbrev, gage_id, target_date) {
  resp <- request("https://dwr.state.co.us/Rest/GET/api/v2") %>%
    req_url_path_append("surfacewater/surfacewatertsday") %>%
    req_url_query(
      format         = "json",
      abbrev         = abbrev,
      `min-measDate` = format(as.Date(target_date), "%m/%d/%Y"),
      `max-measDate` = format(as.Date(target_date), "%m/%d/%Y"),
      pageSize       = 50000,
      apiKey         = api_key
    ) %>%
    req_perform()

  rows <- resp_body_json(resp, simplifyVector = FALSE)$ResultList
  if (length(rows) == 0) return(NULL)

  r <- rows[[1]]
  tibble(
    id       = gage_id,
    date     = as.Date(substr(r$measDate, 1, 10)),
    flow_cfs = as.numeric(r$value %||% NA),
    source   = "CDSS"
  )
}

fetch_cdss_yesterday_many <- function(gages, target_date) {
  bind_rows(lapply(seq_len(nrow(gages)), function(i) {
    message("CDSS: ", gages$cdss_abbrev[i])
    Sys.sleep(0.3)
    tryCatch(
      fetch_cdss_yesterday(gages$cdss_abbrev[i], gages$id[i], target_date),
      error = function(e) {
        message("  -> FAILED: ", conditionMessage(e))
        NULL
      }
    )
  }))
}


# ---- Unified fetch across both sources ----
fetch_streamflow_yesterday <- function(stream_gages, target_date = Sys.Date() - 1) {
  usgs <- stream_gages %>% filter(type == "USGS")
  cdss <- stream_gages %>% filter(type == "CDSS")

  bind_rows(
    if (nrow(usgs) > 0) tryCatch(fetch_usgs_yesterday(usgs$id, target_date),
                                  error = function(e) {
                                    message("USGS batch failed: ", conditionMessage(e))
                                    NULL
                                  }),
    if (nrow(cdss) > 0) fetch_cdss_yesterday_many(cdss, target_date)
  ) 
}
