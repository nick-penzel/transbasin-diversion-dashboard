# Fetch official daily diversion records (divrecday) for a structure. These
# are approved values and lag about a year; telemetry covers the recent gap.

library(httr2)
library(dplyr)
library(tibble)

api_key <- trimws(readLines("scripts/api_key.txt", warn = FALSE)[1])


#' All daily water class records for one structure between two dates.
fetch_divrec_daily <- function(wdid, start_date, end_date) {
  get_page <- function(page) {
    request("https://dwr.state.co.us/Rest/GET/api/v2") |>
      req_url_path_append("structures/divrec/divrecday") |>
      req_url_query(
        format             = "json",
        wdid               = wdid,
        `min-dataMeasDate` = format(as.Date(start_date), "%m/%d/%Y"),
        `max-dataMeasDate` = format(as.Date(end_date), "%m/%d/%Y"),
        pageSize           = 50000,
        pageIndex          = page,
        apiKey             = api_key
      ) |>
      req_timeout(120) |>
      req_perform() |>
      resp_body_json(simplifyVector = FALSE)
  }

  first <- get_page(1)
  rows  <- first$ResultList
  for (page in seq_len(first$PageCount %||% 1)[-1]) {
    rows <- c(rows, get_page(page)$ResultList)
  }
  if (length(rows) == 0) return(NULL)

  bind_rows(lapply(rows, function(r) {
    tibble(
      wdid          = wdid,
      date          = as.Date(substr(r$dataMeasDate, 1, 10)),
      wc_identifier = r$wcIdentifier %||% NA_character_,
      value_cfs     = as.numeric(r$dataValue %||% NA),
      approval      = r$approvalStatus %||% NA_character_
    )
  }))
}

#' One headgate total per day: the S:X U:Q T:0 class, else the
#' "Total (Diversion)" row, else the largest class.
daily_total <- function(records) {
  records |>
    mutate(rank = case_when(
      grepl("S:X .*U:Q T:0", wc_identifier)      ~ 1L,
      grepl("Total \\(Diversion\\)", wc_identifier) ~ 2L,
      grepl("Total \\(Release\\)", wc_identifier)   ~ 9L,
      TRUE                                        ~ 3L
    )) |>
    filter(rank < 9) |>
    group_by(wdid, date) |>
    arrange(rank, desc(value_cfs), .by_group = TRUE) |>
    slice(1) |>
    ungroup() |>
    transmute(wdid, date, discharge_cfs = value_cfs, approval)
}
