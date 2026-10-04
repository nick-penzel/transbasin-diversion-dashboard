# Daily fetch: diversion telemetry and streamflow for a date range, upserted
# into partitioned Parquet datasets under data_root(). Defaults to the last
# 7 days so provisional values that get revised are refreshed.
#
# Usage: Rscript scripts/daily_fetch.R [START_DATE] [END_DATE]
#   Last year of telemetry: Rscript scripts/daily_fetch.R 2025-10-04 2026-10-03

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(lubridate)
})

source("scripts/storage.R")
source("scripts/fetch_telemetry.R")
source("scripts/fetch_streamflow.R")

args <- commandArgs(trailingOnly = TRUE)
end_date   <- if (length(args) > 1) as.Date(args[2]) else Sys.Date() - 1
start_date <- if (length(args) > 0) as.Date(args[1]) else end_date - 6
message(sprintf("Fetching %s to %s", start_date, end_date))

add_partitions <- function(df) {
  mutate(df, year = as.integer(year(date)), month = as.integer(month(date)))
}

structures <- read_csv("data/structures.csv",
                       col_types = cols(.default = "c"))
div_results <- fetch_telemetry_many(structures, start_date, end_date)

stream_gages <- read_csv("data/stream_gages.csv",
                         col_types = cols(.default = "c"))
flow_results <- fetch_streamflow(stream_gages, start_date, end_date)

if (nrow(div_results) == 0 && nrow(flow_results) == 0) {
  stop("No diversion or streamflow data returned")
}

upsert_dataset(add_partitions(div_results), "diversions_daily",
               keys = c("wdid", "date"), partitioning = c("year", "month"))
upsert_dataset(add_partitions(flow_results), "streamflow_daily",
               keys = c("id", "date"), partitioning = c("year", "month"))
