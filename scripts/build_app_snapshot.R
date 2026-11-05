# One file holding everything the Shiny app reads at startup, so a cold start
# makes one S3 request instead of about 35. Rerun after any fetch, backfill,
# or build script; the daily and monthly workflows run it last. The app falls
# back to reading each dataset when the snapshot is missing or out of date.
#
# Usage: Rscript scripts/build_app_snapshot.R

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
})

source("scripts/storage.R")
source("shiny_app/R/app_data.R")
DATA_ROOT <- data_root()

snap <- list(version = SNAPSHOT_VERSION, built_at = Sys.time(), data = read_app_data())

local <- tempfile(fileext = ".rds")
saveRDS(snap, local)
put_file(local, dataset_path(SNAPSHOT_FILE))
message(sprintf("Wrote %s (%.1f MB)", dataset_path(SNAPSHOT_FILE), file.size(local) / 1e6))
