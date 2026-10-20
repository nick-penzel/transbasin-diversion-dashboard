# Backfill daily reservoir storage history for every reservoir in
# data/reservoirs.csv, one reservoir per request.
#
# Usage: RESERVOIR_START_YEAR=1980 Rscript scripts/backfill_reservoirs.R

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(lubridate)
})

source("scripts/storage.R")
source("scripts/fetch_reservoirs.R")

start_date <- as.Date(sprintf("%s-01-01", Sys.getenv("RESERVOIR_START_YEAR", "1980")))
end_date   <- Sys.Date() - 1

reservoirs <- read_csv("data/reservoirs.csv", col_types = cols(.default = "c"))
storage <- fetch_reservoirs_many(reservoirs, start_date, end_date)

upsert_dataset(mutate(storage, year = as.integer(year(date))),
               "reservoir_storage_daily",
               keys = c("wdid", "date"), partitioning = "year")

storage |>
  summarize(first = min(date), last = max(date), n = n(),
            pct_provisional = round(100 * mean(provisional)),
            max_af = max(storage_af), .by = wdid) |>
  left_join(select(reservoirs, wdid, name, capacity_af), by = "wdid") |>
  print(n = Inf)
