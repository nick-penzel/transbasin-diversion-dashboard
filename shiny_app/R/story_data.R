# Numbers behind the public story view, computed once at startup from the
# same datasets the professional tabs use. Volumes in acre-feet.

library(dplyr)
library(sf)

west_slope <- c("Colorado", "Yampa/White", "Dolores", "San Juan")

#' Water-year outflow (AF) for every basin from its outlet gage(s).
outflow_all_basins <- function(outlets) {
  outlets |>
    group_by(basin) |>
    group_modify(\(d, k) outflow_by_wy(d$gage_id)) |>
    ungroup()
}

#' Statewide water-year budget: precipitation on the 8 basins, outflow at
#' the basin outlets, and transfers across the Continental Divide. A year
#' counts only when every basin has outflow and precipitation.
statewide_budget <- function(outflow, climate_wy, transfers) {
  across_divide <- transfers |>
    filter(from %in% west_slope, !to %in% west_slope) |>
    summarize(divide_af = sum(af), .by = wy)
  outflow |>
    left_join(select(climate_wy, basin, wy, prcp_af), by = c("basin", "wy")) |>
    summarize(west_outflow_af = sum(outflow_af[basin %in% west_slope]),
              outflow_af = sum(outflow_af), prcp_af = sum(prcp_af),
              n = n(), .by = wy) |>
    filter(n == 8, !is.na(outflow_af), !is.na(prcp_af)) |>
    left_join(across_divide, by = "wy") |>
    mutate(divide_af = coalesce(divide_af, 0),
           other_af = prcp_af - outflow_af - divide_af) |>
    select(-n) |>
    arrange(wy)
}

#' Split 100 between parts by largest remainder, giving each part at least one.
hundredths <- function(x) {
  raw <- 100 * x / sum(x)
  n <- pmax(floor(raw), 1)
  extra <- 100 - sum(n)
  if (extra > 0) {
    idx <- order(raw - floor(raw), decreasing = TRUE)[seq_len(extra)]
    n[idx] <- n[idx] + 1
  } else if (extra < 0) {
    idx <- order(n, decreasing = TRUE)[seq_len(-extra)]
    n[idx] <- n[idx] - 1
  }
  n
}

#' The Continental Divide as the shared edge of the west and east basins.
continental_divide <- function(basins) {
  b <- st_transform(basins, 26913)
  west <- st_union(b[b$basin %in% west_slope, ])
  east <- st_union(b[!b$basin %in% west_slope, ])
  st_intersection(st_boundary(west), st_buffer(east, 300)) |>
    st_line_merge() |>
    st_simplify(dTolerance = 300) |>
    st_transform(4326)
}

#' Mean date half of each basin's outflow passes, early years vs recent years.
runoff_shift <- function(outlets, early = 1991:2000, recent_n = 10) {
  outlets |>
    group_by(basin) |>
    group_modify(\(d, k) runoff_timing(d$gage_id)) |>
    ungroup() |>
    group_by(basin) |>
    summarize(
      early_day = mean(day[wy %in% early]),
      recent_day = mean(day[wy > max(wy) - recent_n]),
      recent_from = max(wy) - recent_n + 1, recent_to = max(wy),
      trend = coef(lm(day ~ wy))[["wy"]] * 10,
      .groups = "drop"
    ) |>
    filter(!is.na(early_day)) |>
    mutate(shift = recent_day - early_day)
}

#' Area-weighted statewide mean temperature (deg F) per complete water year.
statewide_temperature <- function(climate_wy, zones) {
  climate_wy |>
    left_join(select(zones, basin = zone_id, area_km2), by = "basin") |>
    summarize(tmean_f = to_f(weighted.mean(tmean_c, area_km2)),
              prcp_in = inches(weighted.mean(prcp_mm, area_km2)),
              n = n(), .by = wy) |>
    filter(n == 8) |>
    select(-n) |>
    arrange(wy)
}

#' Everything the story needs, as one list.
build_story <- function(outlets, climate_wy, climate_zones, transfers, basins,
                        reservoirs, gage_points) {
  outflow <- outflow_all_basins(outlets)
  list(
    outflow = outflow,
    budget = statewide_budget(outflow, climate_wy, transfers),
    divide = continental_divide(basins),
    shift = runoff_shift(outlets),
    temperature = statewide_temperature(climate_wy, climate_zones),
    transfers = transfers,
    reservoirs = reservoirs,
    gages = gage_points
  )
}

#' Typical January and spring peak flow at a gage, and one year's spring peak
#' (cfs). Typical values are medians by calendar day over earlier years.
snow_stats <- function(flow, year) {
  d <- flow |> mutate(wy = water_year(date), mmdd = format(date, "%m-%d"),
                      month = as.integer(format(date, "%m")))
  typ <- d |> filter(wy < year) |>
    summarize(q = median(flow_cfs, na.rm = TRUE), month = first(month), .by = mmdd)
  list(winter = median(typ$q[typ$month == 1]),
       typ_peak = max(typ$q[typ$month %in% 4:7]),
       this_peak = max(d$flow_cfs[d$wy == year & d$month %in% 4:7], na.rm = TRUE))
}

fmt_cfs <- function(x) format(signif(round(x), 2), big.mark = ",")
