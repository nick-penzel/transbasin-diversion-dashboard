# Daily fetch: yesterday's diversion telemetry AND streamflow.
# Writes two separate Parquet files (different schemas) and uploads both
# to the daily-data release. Append-only.

suppressPackageStartupMessages({
  library(dplyr)
  library(arrow)
  library(piggyback)
  library(readr)
})

source("scripts/fetch_telemetry.R")
source("scripts/fetch_streamflow.R")

repo        <- Sys.getenv("GITHUB_REPOSITORY", "nick-penzel/transbasin-diversion-dashboard")
target_date <- Sys.Date() - 1

# Diversions
structures <- read_csv("data/structures.csv", show_col_types = FALSE)
div_results <- fetch_yesterday_many(structures$wdid, target_date = target_date)

if (nrow(div_results) > 0) {
  div_file <- sprintf("data/daily_diversions_%s.parquet", target_date)
  write_parquet(div_results, div_file)
  message(sprintf("Wrote %s (%d rows)", div_file, nrow(div_results)))
} else {
  div_file <- NULL
  message("No diversion telemetry for ", target_date)
}

# Streamflow
stream_gages <- read_csv("data/stream_gages.csv", show_col_types = FALSE)
flow_results <- fetch_streamflow_yesterday(stream_gages, target_date = target_date)

if (nrow(flow_results) > 0) {
  flow_file <- sprintf("data/daily_flows_%s.parquet", target_date)
  write_parquet(flow_results, flow_file)
  message(sprintf("Wrote %s (%d rows)", flow_file, nrow(flow_results)))
} else {
  flow_file <- NULL
  message("No streamflow for ", target_date)
}

# Bail if both empty
to_upload <- c(div_file, flow_file)
if (length(to_upload) == 0) {
  message("Nothing to upload, exiting.")
  quit(status = 0)
}

# Ensure release exists
tryCatch(
  pb_release_create(repo = repo, tag = "daily-data",
                    name = "Daily telemetry data",
                    .token = trimws(Sys.getenv("GITHUB_TOKEN"))),
  error = function(e) message("Release already exists, continuing")
)

pb_upload(
  to_upload,
  repo      = repo,
  tag       = "daily-data",
  overwrite = TRUE,
  .token    = trimws(Sys.getenv("GITHUB_TOKEN"))
)
