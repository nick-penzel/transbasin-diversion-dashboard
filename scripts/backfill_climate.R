# Backfill daily climate as zone means for the zones in
# reference/climate_zones, one year at a time. CLIMATE_SOURCE picks the
# product: daymet (1 km; precipitation, temperature, SWE; through last year)
# or gridmet (4 km; precipitation, temperature, reference ET, VPD; through
# yesterday).
#
# Usage: CLIMATE_SOURCE=daymet CLIMATE_START_YEAR=1980 CLIMATE_END_YEAR=2025 Rscript scripts/backfill_climate.R
#        CLIMATE_SOURCE=gridmet CLIMATE_START_YEAR=1979 Rscript scripts/backfill_climate.R
# Daymet years already stored in full are skipped unless CLIMATE_REFRESH=1.

suppressPackageStartupMessages({
  library(dplyr)
  library(arrow)
  library(lubridate)
})

source("scripts/storage.R")
source("scripts/fetch_gridmet.R")

climate_source <- match.arg(Sys.getenv("CLIMATE_SOURCE", "daymet"), c("daymet", "gridmet"))
first_year <- c(daymet = 1980, gridmet = 1979)[[climate_source]]
last_year  <- year(Sys.Date()) - (climate_source == "daymet")
years <- seq(as.integer(Sys.getenv("CLIMATE_START_YEAR", first_year)),
             as.integer(Sys.getenv("CLIMATE_END_YEAR", last_year)))

zones <- read_parquet(file.path(dataset_path("reference/climate_zones"), "part-0.parquet"))
weights <- read_parquet(file.path(dataset_path("reference/daymet_weights"), "part-0.parquet"))
grid <- distinct(weights, x0, x1, y0, y1)

all_years <- years

# Skip years already stored in full so an interrupted run picks up where it
# stopped; set CLIMATE_REFRESH=1 to fetch them again
if (climate_source == "daymet" && path_exists(dataset_path("climate_daily")) &&
    Sys.getenv("CLIMATE_REFRESH") != "1") {
  done <- open_dataset(dataset_path("climate_daily")) |>
    filter(source == "daymet") |>
    count(year) |>
    collect() |>
    filter(n == 365 * nrow(zones))
  years <- setdiff(years, done$year)
}
message(sprintf("Fetching %d years", length(years)))

write_year <- function(df) {
  df |>
    left_join(select(zones, zone_id, zone_type), by = "zone_id") |>
    mutate(year = as.integer(year(date))) |>
    upsert_dataset("climate_daily", keys = c("zone_id", "date", "source"),
                   partitioning = "year")
}

if (climate_source == "daymet") {
  fetch_daymet_many(years, weights, grid, write_year)
} else {
  zone_shapes <- sf::st_read(local_copy(file.path(dataset_path("reference"), "climate_zones.geojson")),
                             quiet = TRUE)
  fetch_gridmet_many(as.Date(sprintf("%s-01-01", min(years))),
                     min(as.Date(sprintf("%s-12-31", max(years))), Sys.Date() - 1),
                     zone_shapes, write_year)
}

open_dataset(dataset_path("climate_daily")) |>
  filter(zone_type == "basin", source == climate_source, year %in% all_years) |>
  collect() |>
  summarize(days = n(), na = sum(is.na(prcp_mm) | is.na(tmax_c) | is.na(tmin_c)),
            prcp_mm = round(sum(prcp_mm)), tmean_c = round(mean((tmax_c + tmin_c) / 2), 1),
            peak_swe_mm = round(max(swe_mm)), eto_mm = round(sum(eto_mm)),
            .by = c(zone_id, year)) |>
  arrange(zone_id, year) |>
  print(n = Inf)
