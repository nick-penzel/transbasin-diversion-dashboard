library(httr)
library(jsonlite)
library(dplyr)
library(purrr)

get_divrec_month <- function(wdids,
                             format = "json",
                             verbose = TRUE) {
  # Ensure wdids is a character vector
  wdids <- as.character(wdids)
  
  # might need to join multiple WDIDs.
  # According to help: "Can now search by multiple WDID's in one request"
  
  base_url <- "https://dwr.state.co.us/Rest/GET/api/v2/structures/divrec/divrecmonth"
  query_params <- list(
    format = format,
    wdid = paste(wdids, collapse = ",")
  )
  
  if (verbose) {
    message("Requesting WDIDs: ", query_params$wdid)
  }
  
  resp <- httr::GET(url = base_url, query = query_params)
  
  # Check for HTTP errors
  httr::stop_for_status(resp)
  
  text <- httr::content(resp, "text", encoding = "UTF-8")
  
  # Check empty‐records case
  if (text == "This URL is properly formatted, but returns zero records from CDSS.") {
    if (verbose) message("No records returned for WDIDs: ", query_params$wdid)
    return(tibble::tibble())
  }
  
  # Parse JSON
  parsed <- jsonlite::fromJSON(text, flatten = TRUE)
  
  # According to example, data might be wrapped in “ResultList”
  if ("ResultList" %in% names(parsed)) {
    df <- tibble::as_tibble(parsed$ResultList)
  } else {
    df <- tibble::as_tibble(parsed)
  }
  
  return(df)
}

