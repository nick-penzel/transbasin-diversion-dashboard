# Fetch daily reservoir storage (acre-feet). Reclamation reservoirs come from
# the USBR RISE API; the rest from CDSS approved stage-volume records, with
# CDSS storage telemetry filling days that have no approved record.

library(httr2)
library(dplyr)
library(tibble)

source("scripts/fetch_telemetry.R")

cdss_url <- "https://dwr.state.co.us/Rest/GET/api/v2"
rise_url <- "https://data.usbr.gov/rise/api"

empty_storage <- function() {
  tibble(wdid = character(), date = as.Date(character()),
         storage_af = numeric(), provisional = logical(), source = character())
}

#' CDSS approved (and some provisional) daily stage-volume records.
fetch_stagevolume <- function(wdid, start_date, end_date) {
  resp <- request(cdss_url) |>
    req_url_path_append("structures/divrec/stagevolume") |>
    req_url_query(
      format = "json",
      wdid = wdid,
      `min-dataMeasDate` = format(as.Date(start_date), "%m/%d/%Y"),
      `max-dataMeasDate` = format(as.Date(end_date), "%m/%d/%Y"),
      pageSize = 50000,
      apiKey = api_key
    ) |>
    req_error(is_error = \(r) resp_status(r) >= 400 && resp_status(r) != 404) |>
    req_perform()
  if (resp_status(resp) == 404) return(empty_storage())

  rows <- resp_body_json(resp, simplifyVector = FALSE)$ResultList
  if (length(rows) == 0) return(empty_storage())
  tibble(
    wdid        = wdid,
    date        = as.Date(substr(vapply(rows, \(r) r$dataMeasDate, ""), 1, 10)),
    storage_af  = vapply(rows, \(r) as.numeric(r$volume %||% NA), 0),
    provisional = vapply(rows, \(r) !identical(r$approvalStatus, "Approved"), TRUE),
    source      = "cdss_record"
  )
}

#' CDSS daily storage telemetry (provisional).
fetch_storage_telemetry <- function(wdid, abbrev, start_date, end_date) {
  # CDSS returns 404 when a station has no data in the range
  tele <- tryCatch(fetch_telemetry(wdid, abbrev, "STORAGE", start_date, end_date),
                   httr2_http_404 = function(e) NULL)
  if (is.null(tele)) return(empty_storage())
  transmute(tele, wdid, date, storage_af = discharge_cfs, provisional = TRUE,
            source = "cdss_telemetry")
}

#' USBR RISE daily storage for one catalog item, all pages.
fetch_rise_storage <- function(wdid, item_id, start_date, end_date) {
  out <- list()
  page <- 1
  repeat {
    body <- request(rise_url) |>
      req_url_path_append("result") |>
      req_headers(Accept = "application/vnd.api+json") |>
      req_url_query(
        itemId = item_id,
        `dateTime[after]` = format(as.Date(start_date) - 1),
        `dateTime[before]` = format(as.Date(end_date) + 1),
        `order[dateTime]` = "ASC",
        itemsPerPage = 10000,
        page = page
      ) |>
      req_retry(max_tries = 3) |>
      req_perform() |>
      resp_body_json(simplifyVector = FALSE)
    out <- c(out, body$data)
    if (is.null(body$links[["next"]])) break
    page <- page + 1
  }
  if (length(out) == 0) return(empty_storage())
  tibble(
    wdid        = wdid,
    date        = as.Date(substr(vapply(out, \(r) r$attributes$dateTime, ""), 1, 10)),
    storage_af  = vapply(out, \(r) as.numeric(r$attributes$result %||% NA), 0),
    provisional = FALSE,
    source      = "usbr_rise"
  ) |>
    filter(date >= as.Date(start_date), date <= as.Date(end_date))
}

#' Daily storage for one reservoir row of data/reservoirs.csv. CDSS approved
#' records win over telemetry on the same day.
fetch_reservoir <- function(res, start_date, end_date) {
  if (res$source == "rise") {
    return(fetch_rise_storage(res$wdid, res$rise_item_id, start_date, end_date))
  }
  records <- fetch_stagevolume(res$wdid, start_date, end_date)
  tele <- if (!is.na(res$abbrev)) {
    fetch_storage_telemetry(res$wdid, res$abbrev, start_date, end_date)
  } else {
    empty_storage()
  }
  bind_rows(records, anti_join(tele, records, by = "date"))
}

#' Daily storage for every reservoir; failures are logged and skipped.
fetch_reservoirs_many <- function(reservoirs, start_date, end_date, pause = 0.3) {
  bind_rows(lapply(seq_len(nrow(reservoirs)), function(i) {
    res <- reservoirs[i, ]
    message(sprintf("[%d/%d] %s", i, nrow(reservoirs), res$name))
    Sys.sleep(pause)
    tryCatch(
      fetch_reservoir(res, start_date, end_date),
      error = function(e) {
        message("  -> FAILED: ", conditionMessage(e))
        NULL
      }
    )
  })) |>
    filter(!is.na(storage_af)) |>
    distinct(wdid, date, .keep_all = TRUE)
}
