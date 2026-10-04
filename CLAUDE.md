# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

R ETL pipelines + Shiny dashboard for exploring Colorado water resources. `README.md` is the source of truth for goals and scope; the existing scripts predate it and are being brought in line.

Started as transmountain diversions and how much water leaves the state; scope now includes storage, streamflow, and historical use. Audience: water resource professionals, but accessible to the public.

Sources: CDSS/DWR REST API (`https://dwr.state.co.us/Rest/GET/api/v2`), USGS via `dataRetrieval`, and US Bureau of Reclamation if needed.

### Stages

1. **Stage 1 (current):** ETL, API calls, and beta dashboard running locally. Focus on transmountain diversions plus a few critical river gages. Write Parquet to the project `data/` folder, with a layout that can move to S3 unchanged. Write ETL so it can later run unattended in GitHub Actions.
2. **Stage 2:** deploy beta app to Posit hosting, move ETL into GitHub Actions, store data on AWS S3.
3. **Stage 3:** gridded climate and precipitation data (including SNOTEL) for basic basin water balance modeling.

**Dashboard:** interactive map (NHDPlus hydrofabric basemap) where users select features, view current data, and compare against history. More tabs added over time.

## Running things

Scripts run from the **repo root**. The Shiny app runs with **`shiny_app/`** as working directory and reads data from `../data`.

``` bash
Rscript scripts/build_reference.R          # structure + gage coordinates (rerun when the CSVs change)
MIN_STREAM_ORDER=3 Rscript scripts/build_hydrofabric.R  # NHDPlus flowlines for CO, ~20 min
Rscript scripts/daily_fetch.R [START] [END] # telemetry + streamflow, default last 7 days
STREAMFLOW_START_YEAR=1990 Rscript scripts/backfill_streamflow.R
BACKFILL_START_YEAR=1985 BACKFILL_END_YEAR=2025 Rscript scripts/backfill_history.R
Rscript -e 'shiny::runApp("shiny_app")'
```

-   CDSS API key: fetch scripts read `scripts/api_key.txt` when sourced (gitignored). In CI it is written from the `CDSS_API_KEY` secret.
-   No test suite, linter, or package structure (no DESCRIPTION/renv). Verify by running scripts on a short range and checking row counts, dates, and NAs.

## Style

Write using the tidyverse style. When generating text, avoid em dashes and other classic AI tells. Favor clean and beautiful visuals with viridis color palettes. Use ggplot2 and leaflet for visualizations. Use `dplyr`, `tidyr`, and `purrr` for data manipulation. Keep functions small and focused, and document them with roxygen2-style comments.

## Architecture

**Storage** (`scripts/storage.R`): every dataset lives under `data_root()` (`TBD_DATA_ROOT`, default `data`) so Stage 2 can point it at S3. `upsert_dataset()` replaces rows by key and rewrites only the touched Hive partitions, so reruns are idempotent. Datasets:

| Dataset | Keys | Partitioned by |
|---|---|---|
| `diversions_daily` | wdid, date | year, month |
| `streamflow_daily` | id, date | year, month |
| `diversions_monthly` | wdid, month_start | year |
| `diversions_monthly_normals` | wdid, month | none |
| `reference/structures`, `reference/gages` | | none (with lat/long) |
| `reference/flowlines.geojson` | comid | none |

Output under `data/*/` is gitignored. Input CSVs (`data/structures.csv`, `data/stream_gages.csv`) are tracked.

**Fetch modules** (`scripts/fetch_*.R`, `get_structures.R`): each defines a single-item fetch function and a `*_many` wrapper that loops with `Sys.sleep()` rate limiting and `tryCatch` so one failed site doesn't abort the run. Fetch functions return tibbles and never write files.

**Entry points:** `daily_fetch.R` (date range of telemetry via `telemetrystations/telemetrytimeseriesday` for structures with an `abbrev`, plus streamflow: USGS batched, CDSS per abbrev; rerun recent days because provisional values get revised), `backfill_streamflow.R` (daily gage history by year for the joyplot), `backfill_history.R` (monthly `structures/divrec/divrecmonth`, then normals recomputed from the full stored record), and the `build_*` reference scripts. GitHub Actions workflows exist but the daily cron is disabled until Stage 2; they still reference the old piggyback setup.

**Shiny app** (`shiny_app/`): `R/shiny_data_source.R` opens the datasets from `TBD_DATA_ROOT` (default `../data`). Files in `shiny_app/R/` are auto-loaded by `runApp()` (don't also `source()` them). `app.R` is a `bslib` navbar: the Map tab (clickable NHDPlus reaches with EROM flow stats, diversions, gages, one info card) plus a diversion hydrograph that shows monthly records for history and daily telemetry for the last 365 days; the Gage hydrographs tab (`R/mod_joyplot.R`) draws one ridge per year of daily flow with the current year highlighted. `shiny_app/data/structure_meta.csv`, `structures.geojson`, `stream_gages.csv`, and `shiny_app/cache/` are leftovers from the GitHub Release setup and are no longer read.

## Data and domain notes

-   `data/structures.csv` is the master structure list and drives both fetch scripts. Daily fetch requires `wdid`, `abbrev`, `parameter` columns; backfill joins `name`, `source_basin`, `is_transbasin`. Edit this file carefully (Excel round-trips have introduced BOMs and trailing empty columns).
-   WDIDs are 7-character strings with leading zeros (e.g. `0404634`); read them as character, not numeric.
-   `wdid_pod` = point of diversion, `wdid` = telemetry/accounting structure, `wdid_release` = release structure. They can differ for one diversion.
-   CDSS `divrecmonth` returns multiple water classes per month; the code keeps the max `diversion_af` per month as the DivTotal. Acre-feet to mean cfs: `af / (1.9835 * days_in_month)`.
-   CDSS `telemetrytimeseriesday` ignores `min-measDate`/`max-measDate` and returns the last year; use `startDate`/`endDate`. Other endpoints (`surfacewatertsday`, `divrecmonth`) accept `min-`/`max-` params.
-   CDSS returns HTTP 404 when a station has no data in the requested range; treat it as empty, not as an outage.
-   NHDPlus stream order ≥ 3 puts about 77% of Colorado's active USGS stream gages on a mapped reach (order ≥ 4: 52%); the misses are headwater creeks. Simplification can produce empty geometries, which break leaflet; the build drops them.
-   The NHDPlus web service fails intermittently: bulk `get_nhdplus(comid = ...)` returns 500s, and paging can silently drop features with only a warning. The build treats that warning as an error and retries.
-   NHDPlus `slope` on smoothed main stems is often a 1e-5 placeholder; the app reports river-average gradient instead.
-   In `arrow` queries, compute date cutoffs in R first (`cutoff <- Sys.Date() - n`); `Sys.Date() - n` inside `filter()` fails.
-   `cache/` and `shiny_app/cache/` are leftover snapshots from the old GitHub Release storage.
-   `docs/transbasin.qmd` is a scratch notebook, not documentation.

## Project agents

`.claude/agents/`: `etl-engineer` (fetch, transform, and storage code), `shiny-dashboard` (app UI, map, and plots), `doc-maintainer` (doc reconciliation, run only on request).
