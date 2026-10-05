# Backfill daily streamflow history for all gages, one year at a time.
#
# Usage: STREAMFLOW_START_YEAR=1990 Rscript scripts/backfill_streamflow.R
#
# Set API_USGS_PAT (free key from api.waterdata.usgs.gov) in ~/.Renviron.
# Without it the USGS API rate-limits anonymous callers and httr2 sleeps for
# the server's Retry-After, which stalled earlier backfills for 10 to 30 min.

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(lubridate)
})

source("scripts/storage.R")
source("scripts/fetch_streamflow.R")

start_year <- as.integer(Sys.getenv("STREAMFLOW_START_YEAR", "1990"))
end_date   <- Sys.Date() - 1

stream_gages <- read_csv("data/stream_gages.csv",
                         col_types = cols(.default = "c"))

for (yr in seq(start_year, year(end_date))) {
  t0 <- Sys.time()
  message(format(t0, "%H:%M:%S"), " year ", yr, " start")
  flows <- fetch_streamflow(stream_gages,
                            as.Date(sprintf("%d-01-01", yr)),
                            min(as.Date(sprintf("%d-12-31", yr)), end_date))
  if (nrow(flows) == 0) next
  upsert_dataset(
    mutate(flows, year = as.integer(year(date)), month = as.integer(month(date))),
    "streamflow_daily",
    keys = c("id", "date"), partitioning = c("year", "month")
  )
  message(sprintf("%s year %d done: %d rows, %d gages, %.1f s",
                  format(Sys.time(), "%H:%M:%S"), yr, nrow(flows),
                  n_distinct(flows$id), as.numeric(Sys.time() - t0, units = "secs")))
}
