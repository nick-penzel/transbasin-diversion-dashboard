# SNOTEL history and day-of-year normals. Run once to seed, then each October
# after the water year closes:
#   1. Moves closed water years from snotel_daily (what daily_fetch writes and
#      the app reads) into snotel_history (archive, not read by the app).
#   2. Re-pulls the last closed water year from NRCS AWDB, since values get
#      revised through the summer. With no history yet, it seeds from
#      SNOTEL_CSV (the old snotelr pull) or pulls the full record from AWDB.
#   3. Rebuilds snotel_doy_stats from closed water years.
#
# Usage: SNOTEL_CSV=local_data/co_snotell_all.csv Rscript scripts/build_snotel_stats.R

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(lubridate)
})

source("scripts/storage.R")
source("scripts/fetch_snotel.R")

min_years   <- 10
current_wy  <- water_year(Sys.Date())
last_closed <- current_wy - 1
last_sep30  <- as.Date(sprintf("%d-09-30", last_closed))
keys        <- c("site_id", "date")

sites <- open_dataset(dataset_path("reference/snotel_sites")) |> collect()

#' Read the snotelr CSV into the snotel_daily schema. snotelr reports SWE,
#' snow depth, and accumulated precip as start-of-day values, so the value on
#' date D is AWDB's value for D - 1; temperatures and daily precip line up.
read_snotelr_csv <- function(path, shift = TRUE) {
  raw <- read_csv(path, col_types = cols(site_id = "c", date = "D", .default = "?"),
                  col_select = c(site_id, date, snow_water_equivalent, snow_depth,
                                 precipitation_cumulative, precipitation,
                                 temperature_max, temperature_min, temperature_mean))
  snow <- transmute(raw, site_id, date = date - shift,
                    swe_mm = snow_water_equivalent, snow_depth_mm = snow_depth,
                    prcp_accum_mm = precipitation_cumulative)
  met <- transmute(raw, site_id, date, prcp_mm = precipitation,
                   tmax_c = temperature_max, tmin_c = temperature_min,
                   tavg_c = temperature_mean)
  full_join(snow, met, by = keys) |>
    bind_rows(empty_snotel()) |>
    mutate(wy = water_year(date)) |>
    select(names(empty_snotel())) |>
    qc_snotel() |>
    filter(!if_all(swe_mm:tavg_c, is.na))
}

#' Share of rows where a column agrees with AWDB within a tolerance.
agreement <- function(a, b, column, tol) {
  inner_join(a, b, by = keys, suffix = c("", "_awdb")) |>
    filter(!is.na(.data[[column]]), !is.na(.data[[paste0(column, "_awdb")]])) |>
    summarize(share = mean(abs(.data[[column]] - .data[[paste0(column, "_awdb")]]) <= tol),
              n = n()) |>
    mutate(column = column)
}

#' AWDB pull one water year at a time.
fetch_snotel_years <- function(sites, start_date, end_date) {
  wys <- water_year(start_date):water_year(end_date)
  bind_rows(lapply(wys, function(wy) {
    from <- max(start_date, as.Date(sprintf("%d-10-01", wy - 1)))
    to   <- min(end_date, as.Date(sprintf("%d-09-30", wy)))
    fetch_snotel_many(filter(sites, end_date >= from, begin_date <= to), from, to)
  }), empty_snotel())
}

# ---- 1. Roll closed water years out of snotel_daily ----
if (path_exists(dataset_path("snotel_daily"))) {
  daily <- open_dataset(dataset_path("snotel_daily")) |> collect()
  closed <- filter(daily, wy < current_wy)
  if (nrow(closed) > 0) {
    upsert_dataset(closed, "snotel_history", keys = keys, partitioning = "wy")
    delete_dataset("snotel_daily")
    upsert_dataset(filter(daily, wy >= current_wy), "snotel_daily",
                   keys = keys, partitioning = "wy")
  }
}

# ---- 2. Seed or refresh history ----
has_history <- path_exists(dataset_path("snotel_history"))
csv_path <- Sys.getenv("SNOTEL_CSV", "local_data/co_snotell_all.csv")
seed <- if (!has_history && file.exists(csv_path)) read_snotelr_csv(csv_path) else NULL

refresh_from <- if (has_history || !is.null(seed)) {
  last_have <- if (has_history) {
    open_dataset(dataset_path("snotel_history")) |>
      summarize(d = max(date)) |>
      collect() |>
      pull(d)
  } else {
    max(seed$date)
  }
  min(as.Date(sprintf("%d-10-01", last_closed - 1)), last_have + 1)
} else {
  min(sites$begin_date)
}

awdb <- fetch_snotel_years(sites, refresh_from, last_sep30)
message(sprintf("AWDB: %d rows, %s to %s", nrow(awdb), refresh_from, last_sep30))

if (!is.null(seed)) {
  unshifted <- read_snotelr_csv(csv_path, shift = FALSE)
  check <- bind_rows(
    agreement(seed, awdb, "swe_mm", 2.6) |> mutate(version = "shifted"),
    agreement(unshifted, awdb, "swe_mm", 2.6) |> mutate(version = "unshifted"),
    agreement(seed, awdb, "prcp_accum_mm", 2.6) |> mutate(version = "shifted"),
    agreement(seed, awdb, "tmax_c", 0.15) |> mutate(version = "shifted")
  )
  print(check)
  if (check$share[1] < 0.9 || check$share[1] <= check$share[2]) {
    stop("Shifted CSV does not match AWDB; check the date alignment before seeding")
  }
  upsert_dataset(anti_join(seed, awdb, by = keys), "snotel_history",
                 keys = keys, partitioning = "wy")
}
upsert_dataset(awdb, "snotel_history", keys = keys, partitioning = "wy")

# ---- 3. Day-of-year normals from closed water years ----
# Accumulated precip resets each Oct 1, so it is already a water-year total.
history <- open_dataset(dataset_path("snotel_history")) |>
  filter(wy <= last_closed) |>
  select(site_id, date, wy, swe_mm, snow_depth_mm, prcp_wy_mm = prcp_accum_mm,
         tmax_c, tmin_c) |>
  collect()

snotel_stats <- history |>
  tidyr::pivot_longer(c(swe_mm, snow_depth_mm, prcp_wy_mm, tmax_c, tmin_c),
                      names_to = "variable", values_drop_na = TRUE) |>
  mutate(mmdd = format(date, "%m-%d")) |>
  group_by(site_id, variable, mmdd) |>
  summarize(
    n_years  = n(),
    first_yr = min(wy),
    min      = min(value),
    p10      = quantile(value, 0.10, type = 6),
    p25      = quantile(value, 0.25, type = 6),
    p50      = quantile(value, 0.50, type = 6),
    p75      = quantile(value, 0.75, type = 6),
    p90      = quantile(value, 0.90, type = 6),
    max      = max(value),
    # NRCS normals period, for "% of median"
    med_9120 = if (sum(between(wy, 1991, 2020)) >= min_years) {
      median(value[between(wy, 1991, 2020)])
    } else {
      NA_real_
    },
    .groups  = "drop"
  ) |>
  filter(n_years >= min_years)

overwrite_dataset(snotel_stats, "snotel_doy_stats")

history |>
  summarize(first = min(date), last = max(date), n = n(),
            pct_na_swe = round(100 * mean(is.na(swe_mm))), .by = site_id) |>
  left_join(select(sites, site_id, name), by = "site_id") |>
  arrange(first) |>
  print(n = Inf)
