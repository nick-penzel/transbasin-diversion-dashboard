#' Read a cached Parquet file, or build and write it
#'
#' @param name File stem under `data/` in this folder. Put the parameters
#'   that define the data (version, date range) in the name, since the cache
#'   is keyed on the name alone.
#' @param build Function returning a data frame.
#' @param refresh Rebuild even if the file exists.
#' @return The cached or freshly built data frame.
cached <- function(name, build, refresh = FALSE) {
  path <- file.path("data", paste0(name, ".parquet"))
  if (file.exists(path) && !refresh) {
    return(arrow::read_parquet(path))
  }
  dir.create("data", showWarnings = FALSE)
  x <- build()
  arrow::write_parquet(x, path)
  x
}
