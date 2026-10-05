# Classify current gage flow against day-of-year history, following the
# USGS WaterWatch percentile classes and colors.

library(dplyr)

flow_classes <- tibble::tribble(
  ~class,       ~label,                         ~color,
  "high",       "Record high for the day",      "#000000",
  "much_above", "Much above normal (>90th)",    "#0000ff",
  "above",      "Above normal (76th to 90th)",  "#40dfd0",
  "normal",     "Normal (25th to 75th)",        "#00ff00",
  "below",      "Below normal (10th to 24th)",  "#ffa400",
  "much_below", "Much below normal (<10th)",    "#ff0000",
  "low",        "Record low for the day",       "#8b0000",
  "unranked",   "Not ranked",                   "#b0b0b0"
)

#' Percentile class for each flow given that day's historical stats.
classify_flow <- function(flow, min_cfs, p10, p25, p75, p90, max_cfs) {
  case_when(
    is.na(flow) | is.na(p10) ~ "unranked",
    flow > max_cfs           ~ "high",
    flow < min_cfs           ~ "low",
    flow > p90               ~ "much_above",
    flow > p75               ~ "above",
    flow >= p25              ~ "normal",
    flow >= p10              ~ "below",
    TRUE                     ~ "much_below"
  )
}

#' Add class, label, and color columns to gage points with latest flow.
add_flow_status <- function(points, doy_stats) {
  points |>
    mutate(mmdd = format(date, "%m-%d")) |>
    left_join(doy_stats, by = c("id", "mmdd")) |>
    mutate(class = classify_flow(flow_cfs, min_cfs, p10_cfs, p25_cfs,
                                 p75_cfs, p90_cfs, max_cfs)) |>
    left_join(flow_classes, by = "class")
}
