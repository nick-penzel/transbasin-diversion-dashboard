# Backfill monthly history, compute normals, upload to a GitHub Release.

library(dplyr)
library(arrow)
library(piggyback)
library(readr)
library(lubridate)

source("scripts/fetch_monthly.R")

start_year <- as.integer(Sys.getenv("BACKFILL_START_YEAR", "1985"))
end_year_raw <- Sys.getenv("BACKFILL_END_YEAR", "")
end_year <- if (nzchar(end_year_raw)) as.integer(end_year_raw) else year(Sys.Date())
repo       <- Sys.getenv("GITHUB_REPOSITORY", "nickpenzel/transbasin_div")

structures <- read_csv("data/structures.csv", show_col_types = FALSE)

# Fetch
history <- fetch_monthly_many(structures$wdid, start_year, end_year)
history <- history |>
  left_join(structures |> select(wdid, name, source_basin, is_transbasin),
            by = "wdid")

# Compute monthly normals
normals <- history |>
  filter(!is.na(mean_cfs)) |>
  group_by(wdid, name, source_basin, is_transbasin, month) |>
  summarize(
    n_years  = n(),
    p25_cfs  = quantile(mean_cfs, 0.25),
    p50_cfs  = quantile(mean_cfs, 0.50),
    p75_cfs  = quantile(mean_cfs, 0.75),
    mean_cfs = mean(mean_cfs),   # must come LAST — reassigns the column it reads
    .groups  = "drop"
  )

# Write Parquet
write_parquet(history, "data/historical_monthly.parquet")
write_parquet(normals, "data/monthly_normals.parquet")

# Create release if it doesn't exist (safe to call when it does)
tryCatch(
  pb_release_create(repo = repo, tag = "historical-data",
                    name = "Historical monthly data"),
  error = function(e) message("Release already exists, continuing")
)

# Upload to Release
pb_upload(
  c("data/historical_monthly.parquet", "data/monthly_normals.parquet"),
  repo      = repo,
  tag       = "historical-data",
  overwrite = TRUE
)

message("Done.")