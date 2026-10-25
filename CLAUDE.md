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
Rscript scripts/build_reach_network.R      # along-river reach-to-gage distances, ~20 s
Rscript scripts/build_story_assets.R       # public story map rivers and header art, ~10 s
Rscript scripts/daily_fetch.R [START] [END] # telemetry, streamflow, reservoir storage, default last 7 days; gridMET last 75 days
STREAMFLOW_START_YEAR=1990 Rscript scripts/backfill_streamflow.R
BACKFILL_START_YEAR=1985 BACKFILL_END_YEAR=2025 Rscript scripts/backfill_history.R
Rscript scripts/backfill_daily_records.R   # official daily diversion records (divrecday), ~6 min
RESERVOIR_START_YEAR=1980 Rscript scripts/backfill_reservoirs.R  # daily reservoir storage
Rscript scripts/build_flow_stats.R         # day-of-year percentiles for gages, diversions, reservoirs, climate
Rscript scripts/build_water_rights.R       # CDSS net amount rights for each structure
Rscript scripts/build_climate_zones.R      # HUC8 + basin zones and Daymet cell weights, ~1 min
CLIMATE_SOURCE=daymet CLIMATE_START_YEAR=1980 CLIMATE_END_YEAR=2025 Rscript scripts/backfill_climate.R  # Daymet zone means, ~2 min per year
CLIMATE_SOURCE=gridmet CLIMATE_START_YEAR=1979 Rscript scripts/backfill_climate.R  # gridMET zone means to yesterday, ~15 min
SNOTEL_CSV=local_data/co_snotell_all.csv Rscript scripts/build_snotel_stats.R  # SNOTEL history + normals, ~2 min; rerun each October
Rscript scripts/publish_irrigation.R       # Roaring Fork irrigation tables + methods figures from docs/Irrigation (run its two notebooks first)
Rscript -e 'shiny::runApp("shiny_app")'
```

Full rebuild order: `build_reference` → `backfill_streamflow` → `backfill_history` → `backfill_daily_records` → `backfill_reservoirs` → `build_flow_stats` → `build_water_rights` (`build_hydrofabric` is independent; rerun `build_reach_network` after it or after the gage list changes; `build_climate_zones` → `backfill_climate` (both sources) → `build_flow_stats` is the climate chain; Daymet only needs a rerun each spring when the prior year is released, and `daily_fetch` keeps gridMET current). SNOTEL: `build_reference` → `build_snotel_stats` once, then each October after the water year closes. Day to day only `daily_fetch` is needed; rerun the records backfills and `build_flow_stats` every few months since approved records lag about a year.

-   CDSS API key: fetch scripts read `scripts/api_key.txt` when sourced (gitignored). In CI it is written from the `CDSS_API_KEY` secret.
-   No test suite, linter, or package structure (no DESCRIPTION/renv). Verify by running scripts on a short range and checking row counts, dates, and NAs.

## Style

Write using the tidyverse style. When generating text, avoid em dashes and other classic AI tells. Do not add Claude attribution (`Co-Authored-By` trailers or "Generated with Claude Code" lines) to commit messages or PR descriptions. Favor clean and beautiful visuals with viridis color palettes. Use ggplot2 and leaflet for visualizations. Use `dplyr`, `tidyr`, and `purrr` for data manipulation. Keep functions small and focused, and document them with roxygen2-style comments.

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
| `reference/reach_gage_distance` | comid, gage_id | none |
| `reservoir_storage_daily` | wdid, date | year |
| `reservoir_doy_stats` | wdid, mmdd | none |
| `reference/reservoirs` | wdid | none (with lat/long) |
| `climate_daily` | zone_id, date, source | year |
| `climate_doy_stats` | zone_id, source, variable, mmdd | none |
| `reference/climate_zones` (+ `.geojson`) | zone_id | none |
| `reference/daymet_weights` | zone_id, cell | none |
| `snotel_daily` (current water year) | site_id, date | wy |
| `snotel_history` (archive, not read by the app) | site_id, date | wy |
| `snotel_doy_stats` | site_id, variable, mmdd | none |
| `reference/snotel_sites` | site_id | none (with lat/long, basin, elev_band) |
| `irrigation/*.parquet`, `irrigation/fields.geojson` | single files | none (Roaring Fork trial, from the docs/Irrigation notebooks) |

Output under `data/*/` is gitignored. Input CSVs (`data/structures.csv`, `data/stream_gages.csv`, `data/reservoirs.csv`) and the hand-curated `data/diversion_profiles.json` (researched history blurbs with sources) are tracked.

**Gage network** (`data/stream_gages.csv`, 50 sites): the original 16 plus, for each HUC8 in Colorado, the most downstream active USGS stream gage with drainage area ≥ 50 mi² and record since 2000 or earlier, plus CDSS Rio Grande gages (Del Norte, Mogote) because USGS has none there. Arkansas River at Holly was swapped for Arkansas River near Granada because the USGS API has no Holly history before 2023. All USGS sites are fetched in one batched request per date range.

**Reservoirs** (`data/reservoirs.csv`, 55 major reservoirs): `source = rise` reads daily storage from Reclamation RISE (`rise_item_id` is the catalog item for "Daily Lake/Reservoir Storage-af", found via location → catalog-record → catalog-item); `source = cdss` reads CDSS `structures/divrec/stagevolume` (approved, lags about a year, many only at month end) with `STORAGE` telemetry filling days with no record. `capacity_af` is curated from published figures (spot-check them); where blank, the app uses the largest value on record. Values above 110% of capacity are dropped as recording errors (CDSS has some, e.g. Rampart at 26 million AF). Not included: Trinidad (no data since 2010), Elevenmile, and the plains reservoirs CDSS doesn't list as active reservoirs.

**Climate** (`scripts/fetch_daymet.R`, `fetch_gridmet.R`, `build_climate_zones.R`, `backfill_climate.R`): two gridded products reduced to area-weighted daily means for 100 zones: the in-state part of each of 92 HUC8s (`zone_type = huc8`) and the 8 basin polygons (`zone_type = basin`). Both live in `climate_daily`, told apart by `source`, with one shared set of columns (`prcp_mm`, `tmax_c`, `tmin_c`, `swe_mm`, `eto_mm`, `vpd_kpa`; NA where a product lacks the variable).

-   `source = daymet`: 1 km, 1980 to last calendar year, prcp/tmax/tmin/swe. `build_climate_zones` computes the fraction of each grid cell inside each zone once (`reference/daymet_weights`, with the 0-based grid window `x0..x1`, `y0..y1`); the backfill subsets Colorado server-side over Earthdata OPeNDAP (four variables in parallel) and each year is one sparse matrix product.
-   `source = gridmet`: about 4 km, 1979 to yesterday, prcp/tmax/tmin plus grass reference ET (`eto_mm`, Penman-Monteith) and mean vapor pressure deficit. Fetched from the Northwest Knowledge Network THREDDS subset service (no login); weights are computed on the fly from the first file and scaled by cell area because the grid is in degrees. This is the source the app and the current water year use.

HUC8s get a `basin` only when most of their area is inside a basin polygon; 24 are NA because the basin polygons leave out the Republican, Smoky Hill, Cimarron, Laramie, and a few border drainages. `build_flow_stats` writes `climate_doy_stats` in long form per source (`variable` = `tmax_c`, `tmin_c`, `vpd_kpa`, `swe_mm`, `prcp_wy_mm`, `eto_wy_mm`): the `_wy_` variables are running totals since October 1 over complete water years (daily precipitation is mostly zeros), the rest are ranked by calendar day. The app reads only the gridMET basin series; the HUC8 series and Daymet are stored but not shown yet.

**SNOTEL** (`scripts/fetch_snotel.R`, `build_snotel_stats.R`): all 120 Colorado SNTL sites (118 active) from the NRCS AWDB REST API (`wcc.sc.egov.usda.gov/awdbRestApi/services/v1`, no key, many stations per request), stored in mm and °C. `daily_fetch` upserts active sites into `snotel_daily`, which holds only the current water year. Each October `build_snotel_stats` moves closed water years into `snotel_history`, re-pulls the last closed year (NRCS revises values over the summer), and rebuilds `snotel_doy_stats`: `swe_mm`, `snow_depth_mm`, `tmax_c`, `tmin_c`, and `prcp_wy_mm` (NRCS accumulated precip, which resets Oct 1) by calendar day, plus `med_9120`, the 1991 to 2020 median that matches NRCS "% of median" (checked against AWDB `centralTendencyType=MEDIAN`). History was seeded from an old `snotelr` pull in `local_data/` (gitignored); with no CSV and no history the script pulls the full record from AWDB. `reference/snotel_sites` has `basin` (point in the basin polygons; 2 border sites are NA, and the app assigns them the nearest basin), `huc8`, and `elev_band` (elevation quartiles). The app reads only `snotel_daily`, the SWE rows of `snotel_doy_stats`, and the sites.

**Fetch modules** (`scripts/fetch_*.R`, `get_structures.R`): each defines a single-item fetch function and a `*_many` wrapper that loops with `Sys.sleep()` rate limiting and `tryCatch` so one failed site doesn't abort the run. Fetch functions return tibbles and never write files.

**Entry points:** `daily_fetch.R` (date range of telemetry via `telemetrystations/telemetrytimeseriesday` for structures with an `abbrev`, plus streamflow: USGS batched, CDSS per abbrev; rerun recent days because provisional values get revised), `backfill_streamflow.R` (daily gage history by year for the joyplot), `backfill_history.R` (monthly `structures/divrec/divrecmonth`, then normals recomputed from the full stored record), and the `build_*` reference scripts. GitHub Actions workflows exist but the daily cron is disabled until Stage 2; they still reference the old piggyback setup.

**Shared hydrograph** (`shiny_app/R/hydrograph.R`): `site_series()` builds a site's daily series (gages: streamflow; diversions: approved daily records, then telemetry after records end, then monthly means before records begin) and `plot_site_hydrograph()` draws it over day-of-year percentile bands with a period selector (past year default, 5, 10 years, all). Used by the Map tab's bottom chart (gage or diversion, set by map clicks or the picker) and the Diversions tab.

**Basins tab** (`shiny_app/R/mod_basin.R`): water-year accounting per basin. Outflow is the sum of the outlet gage(s) in the tracked `data/basin_outlets.csv` (a year counts only if every outlet has ≥ 330 days). Transfers come from `structures.csv` with source/destination mapped to the 8 basin polygons (Gunnison to Colorado, Yampa to Yampa/White); same-basin transfers are dropped. Recent months use provisional telemetry where approved records are missing (telemetry matched records within ~1% where they overlap). Also a basin-to-basin Sankey, runoff timing (date half of WY outflow passes, with trend), and current gage status. CDSS transfer records are sparse before ~2013 (about 30 structures report vs about 45 after), so medians use only years with data.

**Shiny app** (`shiny_app/`): `R/shiny_data_source.R` opens the datasets from `TBD_DATA_ROOT` (default `../data`). Files in `shiny_app/R/` are auto-loaded by `runApp()` (don't also `source()` them). `app.R` is a `bslib` navbar with four tabs, each tab's server logic in its own module:

-   **Map**: clickable NHDPlus reaches (EROM flow stats), diversions, gages colored by flow percentile, and reservoirs colored by storage percentile (size by capacity); an expanded layer control toggles each group and its legend; one info card; the shared hydrograph below follows map clicks.
-   **Gage hydrographs** (`R/mod_joyplot.R`): one ridge per year of daily flow, current year highlighted, filters for years, months, and calendar or water year.
-   **Diversions** (`R/mod_diversion.R`): curated profile, value boxes, shared hydrograph, annual volume by use, typical month, decreed rights.
-   **Basins** (`R/mod_basin.R`): see above, plus storage today, water-year reservoir storage change (Sep 30 to Sep 30, ±15 days) in the accounting chart, a reservoir table, and three gridMET climate cards: water-year precipitation with reference ET and a runoff ratio (outflow plus exports minus imports over precipitation volume, blank where that is negative), running water-year-to-date precipitation or reference ET against past-year percentiles, and water-year mean temperature with vapor pressure deficit. A snowpack card (`R/snowpack.R`) shows this water year's mean SNOTEL SWE against the mean of the sites' 1991 to 2020 medians, with a basin % of median (total SWE over total median at sites reporting that day, NRCS style; hidden while the median is under 1 inch), next to a table of the basin's SNOTEL sites.

**Public and professional views:** a navbar switch (`pro_view`) shows either the public story tab (default) or the four tabs above; `?view=pro` opens the professional tabs. The story (`R/mod_story.R`, numbers from `R/story_data.R`, graphics in `R/story_plots.R`, styles in `www/story.css`) is one scrolling page of six chapters: statewide precipitation budget as 100 droplets, outflow at the state line, transfers across the Continental Divide, snowmelt timing, this winter's statewide snowpack, and warming, reservoir tanks, and a live river-conditions map. Its prose fills numbers from the data, so recheck wording when a claim could flip (e.g. reservoirs above normal). A second public tab, **River basins** (`R/mod_explore.R`), shows one basin at a time: a spotlight map of its rivers, gages, reservoirs, and diversions (exports, imports, local) beside the latest complete water year's numbers; clicking a feature opens a plain-language card (diversions use `diversion_profiles.json`) and its past year against normal; then the basin's 100 drops, yearly outflow, and reservoir tanks. Basin blurbs (`basin_blurb` in `R/story_plots.R`) are hand-written. `scripts/build_story_assets.R` writes `shiny_app/data/major_rivers.geojson` and the header art `www/hero_rivers.png` (rerun after `build_hydrofabric`). Population west of the Divide (about 10%) and "18 states and Mexico" are hard-coded.

**Irrigation** (`R/mod_irrigation.R`, both views): the Roaring Fork irrigation consumptive use trial. Value boxes, a field map (color by CU, status, adequacy, crop; click a field or pick a ditch for its monthly water budget against native land), diversion vs CU by month, largest ditches, Lorenz curves and Gini by owner/farm block/ditch, owner classes, call days by seniority tercile, and method/model spread plus sensitivity. Tables come from the `dashboard-export` chunks at the end of `docs/Irrigation/roaring_fork_cu.qmd` and `roaring_fork_diversions.qmd` (written to `docs/Irrigation/data/dashboard/`), copied to `irrigation/` under the data root by `scripts/publish_irrigation.R`. The tab is blank with a notice until they are published. No owner IDs leave the notebooks.

**Methods** (`R/mod_methods.R`, both views): the running methods book, one Markdown chapter per file in `shiny_app/methods/NN-slug.md` (also readable on GitHub), rendered with `commonmark`; figures in `methods/figures/` are served at `methods-files/`. Add a chapter and a methods log row in `01-about.md` whenever a method is deployed or changed. Links with class `methods-link` (`methods_link()` in `mod_irrigation.R`) and `NN-slug.md#anchor` links inside chapters open a chapter and section (`www/methods.js`); anchors are GitHub-style heading slugs. Chapters quote numbers by hand, so recheck them when the data are rebuilt.

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
-   Daymet gridded files need a NASA Earthdata Login: `EARTHDATA_TOKEN` in `~/.Renviron` (generate at urs.earthdata.nasa.gov, expires after 60 days). The old ORNL THREDDS URLs redirect to `opendap.earthdata.nasa.gov` and return 401 without it. The single-pixel API (`daymet.ornl.gov/single-pixel/api/data`) needs no auth and is handy for spot checks.
-   Daymet OPeNDAP subsets must include the `x`, `y`, and `lambert_conformal_conic` variables in the `dap4.ce` constraint. Without them GDAL reads the rows south to north and zone means come out plausible but wrong (north and south swapped).
-   Daymet years always have 365 days; leap years drop December 31, so that date is missing, not zero. Daymet `swe` is a simple model output and weak in the Rockies; treat SNOTEL as the snow source when it arrives.
-   Daymet's Lambert conformal grid is not equal-area: a nominal 1 km cell covers about 1.09 km² on the ground in Colorado. Zone means are unaffected; use `area_km2` (geodesic) from `reference/climate_zones` for volumes (1 mm over 1 km² = 0.8107 AF).
-   gridMET days end at midnight Mountain Standard Time; values after `last_permanent_slice` in the file metadata (roughly the last two months) are provisional, so `daily_fetch` re-pulls 75 days. Temperatures arrive in Kelvin. Requests past the last available day are clamped, not errors. Its THREDDS subset service returns classic NetCDF only (`accept=netcdf`; `netcdf4` gives a 500).
-   Every Parquet file in `climate_daily` must carry the same columns: `open_dataset()` takes its schema from the first file and silently drops columns that file lacks. Both fetch modules emit the full column set for that reason.
-   `snotelr` (NRCS report generator, start-of-day values) dates SWE, snow depth, and accumulated precip one day later than AWDB: its value on D is AWDB's D - 1. Temperatures and daily precip line up. The seed shifts those columns back a day (99.8% SWE agreement with AWDB vs 81% unshifted).
-   SNOTEL temperature sensors log error values (e.g. repeated -51.3 °C, highs above 100 °C); `qc_snotel()` blanks temperatures outside plausible bounds and negative snow or precip.
-   gridMET and Daymet agree closely on basin temperature but differ on mountain precipitation (Colorado basin 2024: 580 vs 641 mm), so do not splice them into one series.
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
