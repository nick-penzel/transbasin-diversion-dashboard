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
Rscript scripts/backfill_daily_records.R   # official daily diversion records (divrecday), ~6 min
Rscript scripts/build_flow_stats.R         # day-of-year percentiles for gages and diversions
Rscript scripts/build_water_rights.R       # CDSS net amount rights for each structure
Rscript -e 'shiny::runApp("shiny_app")'
```

Full rebuild order: `build_reference` → `backfill_streamflow` → `backfill_history` → `backfill_daily_records` → `build_flow_stats` → `build_water_rights` (`build_hydrofabric` is independent). Day to day only `daily_fetch` is needed; rerun the records backfills and `build_flow_stats` every few months since approved records lag about a year.

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
| `diversions_monthly_classes` | wdid, month_start, wc_identifier | year |
| `streamflow_doy_stats` | id, mmdd | none |
| `diversions_daily_records` | wdid, date | year |
| `diversions_doy_stats` | wdid, doy (mmdd) | none |
| `reference/water_rights` | wdid, right_wdid, admin_number | none |
| `reference/structures`, `reference/gages` | | none (with lat/long) |
| `reference/flowlines.geojson` | comid | none |

Output under `data/*/` is gitignored. Input CSVs (`data/structures.csv`, `data/stream_gages.csv`) and the hand-curated `data/diversion_profiles.json` (researched history blurbs with sources) are tracked.

**Gage network** (`data/stream_gages.csv`, 50 sites): the original 16 plus, for each HUC8 in Colorado, the most downstream active USGS stream gage with drainage area ≥ 50 mi² and record since 2000 or earlier, plus CDSS Rio Grande gages (Del Norte, Mogote) because USGS has none there. Arkansas River at Holly was swapped for Arkansas River near Granada because the USGS API has no Holly history before 2023. All USGS sites are fetched in one batched request per date range.

**Fetch modules** (`scripts/fetch_*.R`, `get_structures.R`): each defines a single-item fetch function and a `*_many` wrapper that loops with `Sys.sleep()` rate limiting and `tryCatch` so one failed site doesn't abort the run. Fetch functions return tibbles and never write files.

**Entry points:** `daily_fetch.R` (date range of telemetry via `telemetrystations/telemetrytimeseriesday` for structures with an `abbrev`, plus streamflow: USGS batched, CDSS per abbrev; rerun recent days because provisional values get revised), `backfill_streamflow.R` (daily gage history by year for the joyplot), `backfill_history.R` (monthly `structures/divrec/divrecmonth`, then normals recomputed from the full stored record), and the `build_*` reference scripts. GitHub Actions workflows exist but the daily cron is disabled until Stage 2; they still reference the old piggyback setup.

**Shared hydrograph** (`shiny_app/R/hydrograph.R`): `site_series()` builds a site's daily series (gages: streamflow; diversions: approved daily records, then telemetry after records end, then monthly means before records begin) and `plot_site_hydrograph()` draws it over day-of-year percentile bands with a period selector (past year default, 5, 10 years, all). Used by the Map tab's bottom chart (gage or diversion, set by map clicks or the picker) and the Diversions tab.

**Basins tab** (`shiny_app/R/mod_basin.R`): water-year accounting per basin. Outflow is the sum of the outlet gage(s) in the tracked `data/basin_outlets.csv` (a year counts only if every outlet has ≥ 330 days). Transfers come from `structures.csv` with source/destination mapped to the 8 basin polygons (Gunnison to Colorado, Yampa to Yampa/White); same-basin transfers are dropped. Recent months use provisional telemetry where approved records are missing (telemetry matched records within ~1% where they overlap). Also a basin-to-basin Sankey, runoff timing (date half of WY outflow passes, with trend), and current gage status. CDSS transfer records are sparse before ~2013 (about 30 structures report vs about 45 after), so medians use only years with data.

**Shiny app** (`shiny_app/`): `R/shiny_data_source.R` opens the datasets from `TBD_DATA_ROOT` (default `../data`). Files in `shiny_app/R/` are auto-loaded by `runApp()` (don't also `source()` them). `app.R` is a `bslib` navbar with four tabs, each tab's server logic in its own module:

-   **Map**: clickable NHDPlus reaches (EROM flow stats), diversions, and gages colored by flow percentile; one info card; the shared hydrograph below follows map clicks.
-   **Gage hydrographs** (`R/mod_joyplot.R`): one ridge per year of daily flow, current year highlighted, filters for years, months, and calendar or water year.
-   **Diversions** (`R/mod_diversion.R`): curated profile, value boxes, shared hydrograph, annual volume by use, typical month, decreed rights.
-   **Basins** (`R/mod_basin.R`): see above.

Charts are plotly; `R/plotly_theme.R` styles them for the `input_dark_mode()` toggle (pass the `dark` reactive into modules). Basemaps: Esri light gray, Esri dark gray (direct tile URL, not in `leaflet::providers`), OpenStreetMap; CARTO tiles now need an API key. The Map tab's ~18k reaches take about 10 s to render at startup and block other outputs in that session until done. `shiny_app/data/structure_meta.csv`, `structures.geojson`, `stream_gages.csv`, and `shiny_app/cache/` are leftovers from the GitHub Release setup and are no longer read.

## Data and domain notes

-   `data/structures.csv` is the master structure list and drives both fetch scripts. Daily fetch requires `wdid`, `abbrev`, `parameter` columns; backfill joins `name`, `source_basin`, `is_transbasin`. Edit this file carefully (Excel round-trips have introduced BOMs and trailing empty columns).
-   WDIDs are 7-character strings with leading zeros (e.g. `0404634`); read them as character, not numeric.
-   `wdid_pod` = point of diversion, `wdid` = telemetry/accounting structure, `wdid_release` = release structure. They can differ for one diversion.
-   CDSS `divrecmonth` returns multiple water classes per month. The headgate total is the administrative class `S:X U:Q T:0` (DWR Diversion Records Standard v3.0); `monthly_total()` selects it and falls back to the largest class. Rows labeled "Total (Diversion)/(Release)" have no codes. Acre-feet to mean cfs: `af / (1.9835 * days_in_month)`.
-   Water class codes: `S` source (1 natural, 2 storage, 4 transmountain, X total), `U` use (0 storage, 1 irrigation, 2 municipal, T transmountain export, Q quantity only), `T` type (0 admin, 7 released to stream, 8 released off-stream). Use breakdowns drop T:0/R/V/X/Y/Z/D/J and release types, U:Q/B, and FROM = WDID records to avoid double counting. Tunnels that only convey water record U:Q, so their use is recorded downstream.
-   Water rights `decreedUnits` come back as `C` (cfs) and `A` (acre-feet); `adminNumber` lower = more senior. Rights are looked up at both `wdid` and `wdid_pod`.
-   Daily diversion records (`divrecday`, approved, lag about a year) go back to ~1989 for most structures; `daily_total()` picks `S:X U:Q T:0`, then "Total (Diversion)", then the largest class. Ditches mostly record only in their season, so missing days are "no record", not zero. Diversion daily normals pool ±7 days across years and need ≥ 5 years; gage normals use the exact calendar day (USGS method).
-   USGS Water Data API needs `API_USGS_PAT` in `~/.Renviron`. Without it the anonymous hourly limit is hit quickly and httr2 sleeps for the server's `Retry-After` with no cap, which looks like a 10 to 30 minute hang. Watch long pulls and kill them if a step stalls.
-   Gage colors follow USGS WaterWatch: today's flow vs. same calendar day in prior years (≥ 10 years required), classes <10, 10 to 24, 25 to 75, 76 to 90, >90 percentile plus record high/low. History starts in 1990, so percentiles are based on that period, not the full record.
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
