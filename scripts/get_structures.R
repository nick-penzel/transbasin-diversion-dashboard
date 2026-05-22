# Look up structure metadata from CDSS.


library(httr2)
library(dplyr)
library(tibble)

api_key <- trimws(readLines("scripts/api_key.txt", warn = FALSE)[1])


#' Look up structures by any combination of filters.
#'
#' Pass any of: wdid, name (partial match), division, water_district,
#' county, structure_type. Returns a tibble; one row per matching structure.
#'
#' Examples:
#'   get_structures(wdid = "0404634")
#'   get_structures(name = "ADAMS TUNNEL")
#'   get_structures(division = 5, structure_type = "Diversion")

get_structures <- function(wdid = NULL,
                           name = NULL,
                           division = NULL,
                           water_district = NULL,
                           county = NULL,
                           structure_type = NULL) {
  
  params <- list(
    format         = "json",
    pageSize       = 50000,
    apiKey         = api_key,
    wdid           = wdid,
    structureName  = name,
    division       = division,
    waterDistrict  = water_district,
    county         = county,
    structureType  = structure_type
  )
  
  params <- params[!sapply(params, is.null)]
  
  resp <- request("https://dwr.state.co.us/Rest/GET/api/v2") %>% 
    req_url_path_append("structures") %>% 
    req_url_query(!!!params) %>% 
    req_perform()
  
  rows <- resp_body_json(resp, simplifyVector = FALSE)$ResultList
  if (length(rows) == 0) return(NULL)
  
  bind_rows(lapply(rows, function(r) {
    tibble(
      wdid           = r$wdid,
      name           = r$structureName,
      structure_type = r$structureType,
      ciu_code       = r$ciuCode,
      water_source   = r$waterSource,
      division       = r$division,
      water_district = r$waterDistrict,
      county         = r$county,
      stream_mile    = r$streamMile %||% NA_real_,
      latitude       = r$latdecdeg %||% NA_real_,
      longitude      = r$longdecdeg %||% NA_real_,
      modified       = r$modified
    )
  }))
}


# Look up many WDIDs and stack the results.

# Returns one combined tibble.
get_structures_many <- function(wdids, pause = 0.2) {
  bind_rows(lapply(seq_along(wdids), function(i) {
    message(sprintf("[%d/%d] %s", i, length(wdids), wdids[i]))
    Sys.sleep(pause)
    tryCatch(
      get_structures(wdid = wdids[i]),
      error = function(e) {
        message(sprintf("  -> FAILED: %s", conditionMessage(e)))
        NULL
      }
    )
  }))
}