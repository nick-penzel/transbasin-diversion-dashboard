# Backfill monthly diversion history and compute monthly normals.
#
# Usage: BACKFILL_START_YEAR=1985 BACKFILL_END_YEAR=2025 Rscript scripts/backfill_history.R

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(lubridate)
})

source("scripts/storage.R")
source("scripts/fetch_monthly.R")

start_year <- as.integer(Sys.getenv("BACKFILL_START_YEAR", "1985"))
end_year_raw <- Sys.getenv("BACKFILL_END_YEAR", "")
end_year <- if (nzchar(end_year_raw)) as.integer(end_year_raw) else year(Sys.Date())

structures <- read_csv("data/structures.csv",
                       col_types = cols(.default = "c"))

classes <- fetch_monthly_many(structures$wdid, start_year, end_year) |>
  mutate(year = as.integer(year), month = as.integer(month))

if (nrow(classes) == 0) stop("No monthly records returned")

history <- monthly_total(classes) |>
  left_join(structures |> select(wdid, name, source_basin, is_transbasin),
            by = "wdid")

upsert_dataset(classes, "diversions_monthly_classes",
               keys = c("wdid", "month_start", "wc_identifier"),
               partitioning = "year")

upsert_dataset(history, "diversions_monthly",
               keys = c("wdid", "month_start"), partitioning = "year")

# Normals use the full stored record, not just this run's years
normals <- open_dataset(dataset_path("diversions_monthly")) |>
  filter(!is.na(mean_cfs)) |>
  collect() |>
  group_by(wdid, name, source_basin, is_transbasin, month) |>
  summarize(
    n_years  = n(),
    p25_cfs  = quantile(mean_cfs, 0.25),
    p50_cfs  = quantile(mean_cfs, 0.50),
    p75_cfs  = quantile(mean_cfs, 0.75),
    mean_cfs = mean(mean_cfs),   # must come LAST, reassigns the column it reads
    .groups  = "drop"
  )

overwrite_dataset(normals, "diversions_monthly_normals")
