# Daily fetch: pull yesterday's telemetry for every WDID in the structures table
# and append to diversion_readings. Designed to run as a cron job.


suppressPackageStartupMessages({
  library(DBI)
  library(RSQLite)
  library(dplyr)
  library(tibble)
})

# Resolve paths relative to this script so cron doesn't need to cd anywhere

SCRIPT_DIR <- tryCatch(
  dirname(normalizePath(sys.frame(1)$ofile)),
  error = function(e) getwd()
)

DB_PATH    <- file.path(SCRIPT_DIR, "water_cache.sqlite")
LOG_PATH   <- file.path(SCRIPT_DIR, "fetch.log")

source(file.path(SCRIPT_DIR, "fetch_telemetry.R"))


log_msg <- function(msg, ...) {
  line <- sprintf("[%s] %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), sprintf(msg, ...))
  cat(line, "\n", file = LOG_PATH, append = TRUE)
  cat(line, "\n")
}


# Make sure the readings table exists with the schema we need.
ensure_schema <- function(con) {
  dbExecute(con, "
    CREATE TABLE IF NOT EXISTS diversion_readings (
      wdid          TEXT NOT NULL,
      date          DATE NOT NULL,
      discharge_cfs REAL,
      abbrev        TEXT,
      parameter     TEXT,
      meas_count    INTEGER,
      flag_a        TEXT,
      data_source   TEXT NOT NULL,  
      fetched_at    TIMESTAMP NOT NULL,
      note          TEXT,
      PRIMARY KEY (wdid, date)
    )
  ")
  dbExecute(con, "
    CREATE INDEX IF NOT EXISTS idx_diversion_readings_date
      ON diversion_readings(date)
  ")
}


# Append rows, replacing any existing (wdid, date) entries.
# SQLite's INSERT OR REPLACE handles the idempotency. dbWriteTable doesn't
# expose this option, so we build the statement manually.
upsert_readings <- function(con, df) {
  if (nrow(df) == 0) return(0L)

  # Make sure column order matches the table
  cols <- c("wdid", "date", "discharge_cfs", "abbrev", "parameter",
            "meas_count", "flag_a", "data_source", "fetched_at", "note")
  df <- df[, cols, drop = FALSE]

  placeholders <- paste(rep("?", length(cols)), collapse = ", ")
  sql <- sprintf(
    "INSERT OR REPLACE INTO diversion_readings (%s) VALUES (%s)",
    paste(cols, collapse = ", "),
    placeholders
  )

  dbExecute(con, "BEGIN TRANSACTION")
  on.exit(dbExecute(con, "ROLLBACK"), add = TRUE)
  dbExecute(con, sql, params = unname(as.list(df)))
  dbExecute(con, "COMMIT")
  on.exit(NULL)  # cancel rollback now that commit succeeded

  nrow(df)
}


main <- function() {
  target_date <- Sys.Date() - 1
  log_msg("Starting fetch for %s", target_date)

  con <- dbConnect(SQLite(), DB_PATH)
  on.exit(dbDisconnect(con), add = TRUE)

  ensure_schema(con)

  # Pull the structures table (built and curated by you)
  structures <- dbReadTable(con, "structures") |> as_tibble()
  wdids <- structures$wdid
  log_msg("Fetching %d WDIDs", length(wdids))

  # fetch_yesterday_many already handles per-WDID errors gracefully and pauses
  # between requests. Returns a tibble; WDIDs without telemetry are silently
  # dropped (NULL returns get filtered out by bind_rows).
  results <- fetch_yesterday_many(wdids, target_date = target_date)

  if (nrow(results) == 0) {
    log_msg("No telemetry returned — nothing to write")
    return(invisible())
  }

  # Shape the results to match the readings schema
  to_write <- results |>
    transmute(
      wdid,
      date          = as.character(date),  # SQLite stores DATE as TEXT
      discharge_cfs,
      abbrev,
      parameter,
      meas_count,
      flag_a,
      data_source   = "telemetry",
      fetched_at    = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      note
    )

  n_written <- upsert_readings(con, to_write)

  # Diagnostics: how many of our WDIDs got real values vs NA vs no station
  n_with_data    <- sum(!is.na(results$discharge_cfs))
  n_station_no_data <- sum(is.na(results$discharge_cfs))
  n_no_station   <- length(wdids) - nrow(results)

  log_msg("Wrote %d rows (%d with data, %d station-but-no-value, %d no-telemetry)",
          n_written, n_with_data, n_station_no_data, n_no_station)

  if (n_no_station > 0) {
    missing <- setdiff(wdids, results$wdid)
    log_msg("No telemetry for: %s", paste(missing, collapse = ", "))
  }
}


# Run when executed via Rscript
if (!interactive()) {
  tryCatch(
    main(),
    error = function(e) {
      log_msg("FATAL: %s", conditionMessage(e))
      quit(status = 1)
    }
  )
}
