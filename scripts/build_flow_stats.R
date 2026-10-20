# Day-of-year statistics for gages, diversions, and reservoir storage, used to
# color sites by how today compares with history (USGS WaterWatch style). The
# current calendar year is excluded so today is ranked against past years.
#
# Usage: Rscript scripts/build_flow_stats.R

suppressPackageStartupMessages({
  library(dplyr)
  library(lubridate)
})

source("scripts/storage.R")

min_years <- 10
this_year <- year(Sys.Date())

flows <- open_dataset(dataset_path("streamflow_daily")) |>
  filter(year < this_year, !is.na(flow_cfs)) |>
  select(id, date, flow_cfs) |>
  collect()

# Key by month-day so leap years line up with other years
stats <- flows |>
  mutate(mmdd = format(date, "%m-%d")) |>
  group_by(id, mmdd) |>
  summarize(
    n_years   = n(),
    first_yr  = min(year(date)),
    min_cfs   = min(flow_cfs),
    p10_cfs   = quantile(flow_cfs, 0.10, type = 6),
    p25_cfs   = quantile(flow_cfs, 0.25, type = 6),
    p50_cfs   = quantile(flow_cfs, 0.50, type = 6),
    p75_cfs   = quantile(flow_cfs, 0.75, type = 6),
    p90_cfs   = quantile(flow_cfs, 0.90, type = 6),
    max_cfs   = max(flow_cfs),
    .groups   = "drop"
  ) |>
  filter(n_years >= min_years)

overwrite_dataset(stats, "streamflow_doy_stats")

# ---- Diversions: daily normals from official daily records ----
# Single-day diversion values are noisy, so each day pools records within
# +/- 7 days across years. Only recorded days count (most ditches do not
# record outside their season), and a day needs at least 5 years of records.
window   <- 7
min_div_years <- 5

# Day of year on a non-leap calendar so Feb 29 shares Feb 28's slot
doy365 <- function(d) {
  as.integer(format(as.Date(paste0("2001-", format(d, "%m-%d")), optional = TRUE), "%j"))
}

records <- open_dataset(dataset_path("diversions_daily_records")) |>
  filter(year < this_year) |>
  select(wdid, date, discharge_cfs) |>
  collect() |>
  mutate(doy = coalesce(doy365(date), 59L), yr = year(date))

div_stats <- bind_rows(lapply(-window:window, function(k) {
  mutate(records, doy = ((doy - 1 + k) %% 365) + 1)
})) |>
  group_by(wdid, doy) |>
  summarize(
    n_years = n_distinct(yr),
    p10_cfs = quantile(discharge_cfs, 0.10, type = 6),
    p25_cfs = quantile(discharge_cfs, 0.25, type = 6),
    p50_cfs = quantile(discharge_cfs, 0.50, type = 6),
    p75_cfs = quantile(discharge_cfs, 0.75, type = 6),
    p90_cfs = quantile(discharge_cfs, 0.90, type = 6),
    .groups = "drop"
  ) |>
  filter(n_years >= min_div_years) |>
  mutate(mmdd = format(as.Date(doy - 1, origin = "2001-01-01"), "%m-%d"))

overwrite_dataset(div_stats, "diversions_doy_stats")

# ---- Reservoirs: day-of-year storage stats ----
# Many CDSS reservoirs record only at month end, so each reservoir's series is
# linearly interpolated to daily across gaps of up to 45 days first. Values
# above 110% of a ceiling (curated capacity, else the 99.9th percentile of
# approved values) are recording errors and are dropped, as in the app's
# clean_storage().
max_gap <- 45

capacity <- readr::read_csv("data/reservoirs.csv", col_types = readr::cols(.default = "c"),
                            col_select = c(wdid, capacity_af)) |>
  mutate(capacity_af = as.numeric(capacity_af))

#' Daily values between observations, NA across gaps longer than max_gap.
fill_daily <- function(date, value) {
  days <- seq(min(date), max(date), by = "day")
  i <- findInterval(as.numeric(days), as.numeric(date))
  gap <- as.numeric(date[pmin(i + 1, length(date))] - date[i])
  filled <- approx(date, value, xout = days)$y
  tibble(date = days, storage_af = if_else(gap <= max_gap, filled, NA_real_))
}

storage <- open_dataset(dataset_path("reservoir_storage_daily")) |>
  filter(year < this_year) |>
  select(wdid, date, storage_af, provisional) |>
  collect()

ceiling <- storage |>
  summarize(approved_af = quantile(storage_af[!provisional], 0.999, na.rm = TRUE),
            all_af = quantile(storage_af, 0.999), .by = wdid) |>
  left_join(capacity, by = "wdid") |>
  transmute(wdid, ceiling_af = coalesce(capacity_af, approved_af, all_af))

storage <- storage |>
  left_join(ceiling, by = "wdid") |>
  filter(storage_af >= 0, storage_af <= 1.1 * ceiling_af) |>
  arrange(wdid, date)

res_stats <- storage |>
  reframe(fill_daily(date, storage_af), .by = wdid) |>
  filter(!is.na(storage_af)) |>
  mutate(mmdd = format(date, "%m-%d")) |>
  group_by(wdid, mmdd) |>
  summarize(
    n_years  = n(),
    first_yr = min(year(date)),
    min_af   = min(storage_af),
    p10_af   = quantile(storage_af, 0.10, type = 6),
    p25_af   = quantile(storage_af, 0.25, type = 6),
    p50_af   = quantile(storage_af, 0.50, type = 6),
    p75_af   = quantile(storage_af, 0.75, type = 6),
    p90_af   = quantile(storage_af, 0.90, type = 6),
    max_af   = max(storage_af),
    .groups  = "drop"
  ) |>
  filter(n_years >= min_years)

overwrite_dataset(res_stats, "reservoir_doy_stats")

# ---- Climate: day-of-year stats per zone and source ----
# Temperature, VPD, and SWE are ranked by calendar day. Daily precipitation is
# mostly zeros, so it and reference ET are ranked as the running total since
# October 1, using complete water years only.
if (path_exists(dataset_path("climate_daily"))) {
  climate <- open_dataset(dataset_path("climate_daily")) |>
    filter(year < this_year) |>
    select(zone_id, source, date, prcp_mm, eto_mm, tmax_c, tmin_c, vpd_kpa, swe_mm) |>
    collect() |>
    arrange(zone_id, source, date) |>
    mutate(wy = year(date) + (month(date) >= 10)) |>
    mutate(prcp_wy_mm = if (n() >= 360) cumsum(prcp_mm) else NA_real_,
           eto_wy_mm  = if (n() >= 360) cumsum(eto_mm) else NA_real_,
           .by = c(zone_id, source, wy))

  climate_stats <- climate |>
    select(-prcp_mm, -eto_mm, -wy) |>
    tidyr::pivot_longer(c(prcp_wy_mm, eto_wy_mm, tmax_c, tmin_c, vpd_kpa, swe_mm),
                        names_to = "variable", values_drop_na = TRUE) |>
    mutate(mmdd = format(date, "%m-%d")) |>
    group_by(zone_id, source, variable, mmdd) |>
    summarize(
      n_years  = n(),
      first_yr = min(year(date)),
      min      = min(value),
      p10      = quantile(value, 0.10, type = 6),
      p25      = quantile(value, 0.25, type = 6),
      p50      = quantile(value, 0.50, type = 6),
      p75      = quantile(value, 0.75, type = 6),
      p90      = quantile(value, 0.90, type = 6),
      max      = max(value),
      .groups  = "drop"
    ) |>
    filter(n_years >= min_years)

  overwrite_dataset(climate_stats, "climate_doy_stats")
}
