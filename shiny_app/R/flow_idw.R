# Estimate current flow condition on every NHDPlus reach by inverse distance
# weighting of gage percentiles, with distance measured along the river
# network (scripts/build_reach_network.R). Percentiles (not cfs) are
# interpolated so large and small rivers are comparable.

library(dplyr)

#' Approximate percentile of today's flow from that day's historical stats.
flow_percentile <- function(flow, min_cfs, p10, p25, p50, p75, p90, max_cfs) {
  purrr::pmap_dbl(
    list(flow, min_cfs, p10, p25, p50, p75, p90, max_cfs),
    function(q, ...) {
      knots <- c(...)
      if (is.na(q) || anyNA(knots)) return(NA_real_)
      if (q > knots[7]) return(100)
      if (q < knots[1]) return(0)
      if (n_distinct(knots) < 2) return(50)
      approx(knots, c(0, 10, 25, 50, 75, 90, 100), xout = q, ties = mean)$y
    }
  )
}

#' WaterWatch class for a percentile (no record classes for estimates).
percentile_class <- function(p) {
  case_when(
    is.na(p) ~ "unranked",
    p > 90   ~ "much_above",
    p > 75   ~ "above",
    p >= 25  ~ "normal",
    p >= 10  ~ "below",
    TRUE     ~ "much_below"
  )
}

#' Add pctile, n_gages, class, label, and color to each reach.
#'
#' @param flowlines sf lines with comid.
#' @param gage_points gages with id and pctile.
#' @param distances comid, gage_id, dist_km along the river network.
#' @param power IDW distance exponent.
idw_flowlines <- function(flowlines, gage_points, distances, power = 2) {
  est <- distances |>
    inner_join(filter(select(gage_points, id, pctile), !is.na(pctile)),
               by = c("gage_id" = "id")) |>
    mutate(w = pmax(dist_km, 0.5)^-power) |>
    summarise(pctile = sum(w * pctile) / sum(w), n_gages = n(), .by = comid)

  flowlines |>
    left_join(est, by = "comid") |>
    mutate(n_gages = coalesce(n_gages, 0L),
           class = percentile_class(pctile)) |>
    left_join(flow_classes, by = "class")
}
