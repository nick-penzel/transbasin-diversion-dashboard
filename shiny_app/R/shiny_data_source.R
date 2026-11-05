# Data loading for the Shiny app. Reads the snapshot written by
# scripts/build_app_snapshot.R (one request on S3), or every dataset from
# TBD_DATA_ROOT when the snapshot is missing or from an older version.

N_DAYS <- 30   # how far back to look for the latest daily value

#' Most recent value per site within the last N_DAYS.
latest_daily <- function(dataset, site_col) {
  cutoff <- Sys.Date() - N_DAYS
  read_ds(dataset) |>
    filter(date >= cutoff) |>
    collect() |>
    slice_max(date, by = all_of(site_col), n = 1, with_ties = FALSE)
}

app_data <- read_snapshot()
if (is.null(app_data)) app_data <- read_app_data()

ds_cache <- lapply(Filter(Negate(is.null), app_data$tables), as_arrow_table)
list2env(app_data[setdiff(names(app_data), "tables")], environment())
rm(app_data)

structures <- filter(structures, !is.na(latitude))
gages      <- filter(gages, !is.na(latitude))

latest_diversions <- latest_daily("diversions_daily", "wdid")

# Last 365 days of daily telemetry; older history comes from monthly records
recent_cutoff <- Sys.Date() - 366
diversions_recent <- read_ds("diversions_daily") |>
  filter(date >= recent_cutoff) |>
  select(wdid, date, discharge_cfs) |>
  collect()
latest_flows      <- latest_daily("streamflow_daily", "id")

reservoirs <- if (!is.null(reservoirs)) filter(reservoirs, !is.na(latitude))
if (!is.null(reservoir_storage)) {
  reservoir_storage <- clean_storage(reservoir_storage, reservoirs)
}

# SNOTEL: this water year's daily SWE
if (!is.null(snotel_daily)) {
  this_wy <- water_year(Sys.Date())
  snotel_daily <- snotel_daily |>
    filter(wy == this_wy) |>
    select(site_id, date, swe_mm)
}
