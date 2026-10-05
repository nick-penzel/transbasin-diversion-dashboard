# Day-of-year flow statistics for each gage, used to color gages by how
# current flow compares with history (USGS WaterWatch style). The current
# calendar year is excluded so today's flow is ranked against past years.
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
