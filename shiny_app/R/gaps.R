# Make missing data visible on line charts: break the observed line at gaps
# and build separate bridge segments to draw across them.

library(dplyr)

#' Fill a regular time series so missing steps become NA rows.
#'
#' @param df data with columns `x` (Date) and `y`.
#' @param step "day" or "month".
complete_series <- function(df, step) {
  if (nrow(df) == 0) return(df)
  full <- tibble(x = seq(min(df$x), max(df$x), by = step))
  left_join(full, df, by = "x")
}

#' Segments spanning each interior run of NA values, from the last observed
#' point before the gap to the first one after it. Segments are separated by
#' NA rows so plotly draws them as one broken trace.
gap_bridges <- function(df) {
  if (nrow(df) == 0) return(tibble(x = as.Date(character()), y = numeric()))
  obs <- which(!is.na(df$y))
  jumps <- which(diff(obs) > 1)
  if (length(jumps) == 0) return(tibble(x = as.Date(character()), y = numeric()))

  bind_rows(lapply(jumps, function(j) {
    a <- obs[j]
    b <- obs[j + 1]
    tibble(x = c(df$x[a], df$x[b], NA), y = c(df$y[a], df$y[b], NA))
  }))
}
