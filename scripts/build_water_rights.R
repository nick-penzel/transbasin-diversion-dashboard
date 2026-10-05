# Decreed water rights (net amounts) for each diversion structure, looked up
# by both the accounting WDID and the point-of-diversion WDID.
#
# Usage: Rscript scripts/build_water_rights.R

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(httr2)
})

source("scripts/storage.R")

api_key <- trimws(readLines("scripts/api_key.txt", warn = FALSE)[1])

#' Net amount water rights decreed to one structure.
fetch_water_rights <- function(wdid) {
  resp <- request("https://dwr.state.co.us/Rest/GET/api/v2") |>
    req_url_path_append("waterrights/netamount") |>
    req_url_query(format = "json", wdid = wdid, pageSize = 50000,
                  apiKey = api_key) |>
    req_perform()

  rows <- resp_body_json(resp, simplifyVector = FALSE)$ResultList
  if (length(rows) == 0) return(NULL)

  bind_rows(lapply(rows, function(r) {
    tibble(
      right_wdid         = r$wdid,
      structure_name     = r$structureName,
      water_source       = r$waterSource %||% NA_character_,
      appropriation_date = as.Date(substr(r$appropriationDate %||% NA, 1, 10)),
      adjudication_date  = as.Date(substr(r$adjudicationDate %||% NA, 1, 10)),
      admin_number       = as.numeric(r$adminNumber %||% NA),
      decreed_uses       = r$decreedUses %||% NA_character_,
      net_absolute       = as.numeric(r$netAbsolute %||% NA),
      net_conditional    = as.numeric(r$netConditional %||% NA),
      decreed_units      = r$decreedUnits %||% NA_character_,
      case_numbers       = r$associatedCaseNumbers %||% NA_character_,
      comments           = r$comments %||% NA_character_,
      more_info          = r$moreInformation %||% NA_character_
    )
  }))
}

structures <- read_csv("data/structures.csv", col_types = cols(.default = "c"))

lookups <- bind_rows(
  structures |> transmute(wdid, right_wdid = wdid),
  structures |> transmute(wdid, right_wdid = wdid_pod)
) |>
  filter(!is.na(right_wdid)) |>
  distinct()

rights <- bind_rows(lapply(seq_len(nrow(lookups)), function(i) {
  message(sprintf("[%d/%d] %s", i, nrow(lookups), lookups$right_wdid[i]))
  Sys.sleep(0.3)
  tryCatch(
    fetch_water_rights(lookups$right_wdid[i]),
    error = function(e) {
      message("  -> FAILED: ", conditionMessage(e))
      NULL
    }
  )
})) |>
  distinct()

rights <- lookups |>
  inner_join(rights, by = "right_wdid", relationship = "many-to-many") |>
  arrange(wdid, admin_number)

if (nrow(rights) == 0) stop("No water rights returned")
overwrite_dataset(rights, "reference/water_rights")
