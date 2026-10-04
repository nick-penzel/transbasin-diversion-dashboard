# Fetch daily streamflow for a list of gages between two dates.
#   USGS - read_waterdata_daily, one batched call for all sites
#   CDSS - surfacewatertsday endpoint, one call per CDSS abbrev
#
# Returns one tibble regardless of source: id, date, flow_cfs, source, approval

suppressPackageStartupMessages({
  library(dplyr)
  library(tibble)
  library(httr2)
  library(dataRetrieval)
})

api_key <- trimws(readLines("scripts/api_key.txt", warn = FALSE)[1])


#' USGS daily mean discharge for many sites.
fetch_usgs_daily <- function(gage_ids, start_date, end_date) {
  daily <- read_waterdata_daily(
    monitoring_location_id = gage_ids,
    parameter_code = "00060",
    statistic_id   = "00003",
    time           = c(as.character(start_date), as.character(end_date)),
    skipGeometry   = TRUE
  )
  if (nrow(daily) == 0) return(NULL)

  daily |>
    transmute(
      id       = monitoring_location_id,
      date     = as.Date(time),
      flow_cfs = as.numeric(value),
      source   = "USGS",
      approval = approval_status
    )
}


#' CDSS daily streamflow for one station.
fetch_cdss_daily <- function(abbrev, gage_id, start_date, end_date) {
  resp <- request("https://dwr.state.co.us/Rest/GET/api/v2") |>
    req_url_path_append("surfacewater/surfacewatertsday") |>
    req_url_query(
      format         = "json",
      abbrev         = abbrev,
      `min-measDate` = format(as.Date(start_date), "%m/%d/%Y"),
      `max-measDate` = format(as.Date(end_date), "%m/%d/%Y"),
      pageSize       = 50000,
      apiKey         = api_key
    ) |>
    req_perform()

  rows <- resp_body_json(resp, simplifyVector = FALSE)$ResultList
  if (length(rows) == 0) return(NULL)

  bind_rows(lapply(rows, function(r) {
    tibble(
      id       = gage_id,
      date     = as.Date(substr(r$measDate, 1, 10)),
      flow_cfs = as.numeric(r$value %||% NA),
      source   = "CDSS",
      approval = NA_character_
    )
  }))
}


fetch_cdss_daily_many <- function(gages, start_date, end_date) {
  bind_rows(lapply(seq_len(nrow(gages)), function(i) {
    message("CDSS: ", gages$cdss_abbrev[i])
    Sys.sleep(0.3)
    tryCatch(
      fetch_cdss_daily(gages$cdss_abbrev[i], gages$id[i], start_date, end_date),
      error = function(e) {
        message("  -> FAILED: ", conditionMessage(e))
        NULL
      }
    )
  }))
}


#' Daily streamflow for all gages in `stream_gages` across both sources.
fetch_streamflow <- function(stream_gages, start_date, end_date) {
  usgs <- stream_gages |> filter(type == "USGS")
  cdss <- stream_gages |> filter(type == "CDSS")

  bind_rows(
    if (nrow(usgs) > 0) {
      tryCatch(fetch_usgs_daily(usgs$id, start_date, end_date),
               error = function(e) {
                 message("USGS batch failed: ", conditionMessage(e))
                 NULL
               })
    },
    if (nrow(cdss) > 0) fetch_cdss_daily_many(cdss, start_date, end_date)
  )
}
