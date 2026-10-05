# Backfill official daily diversion records (headgate totals) for every
# structure. Rerun occasionally; records are approved about a year late.
#
# Usage: Rscript scripts/backfill_daily_records.R

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(lubridate)
})

source("scripts/storage.R")
source("scripts/fetch_divrec_daily.R")

start_date <- as.Date(Sys.getenv("RECORDS_START", "1985-01-01"))
end_date   <- Sys.Date() - 1

structures <- read_csv("data/structures.csv", col_types = cols(.default = "c")) |>
  filter(!is.na(wdid))

for (i in seq_len(nrow(structures))) {
  w  <- structures$wdid[i]
  t0 <- Sys.time()
  recs <- tryCatch(
    fetch_divrec_daily(w, start_date, end_date),
    error = function(e) {
      message("  -> FAILED: ", conditionMessage(e))
      NULL
    }
  )
  n <- 0
  if (!is.null(recs) && nrow(recs) > 0) {
    totals <- daily_total(recs) |> mutate(year = as.integer(year(date)))
    upsert_dataset(totals, "diversions_daily_records",
                   keys = c("wdid", "date"), partitioning = "year")
    n <- nrow(totals)
  }
  message(sprintf("%s [%d/%d] %s: %d days, %.1f s",
                  format(Sys.time(), "%H:%M:%S"), i, nrow(structures), w, n,
                  as.numeric(Sys.time() - t0, units = "secs")))
  Sys.sleep(0.3)
}
