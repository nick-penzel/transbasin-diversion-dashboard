# Colorado Water Dashboard

A Shiny app for exploring Colorado's water: transmountain diversions, streamflow, reservoir storage, and basin climate. Built for water resource professionals, written to be readable by the public.

Hosted on Posit Connect Cloud. Data is refreshed daily by GitHub Actions and stored as Parquet on AWS S3.

## Architecture

``` mermaid
flowchart LR
  subgraph Sources
    CDSS[CDSS / DWR REST API]
    USGS[USGS Water Data API]
    RISE[Reclamation RISE]
    GM[gridMET THREDDS]
    DM[Daymet OPeNDAP]
    NHD[NHDPlus V2]
  end
  subgraph GitHub Actions
    DF[daily_fetch.yml<br/>daily]
    RF[backfill.yml<br/>monthly]
  end
  S3[(S3: co-water-data<br/>Hive-partitioned Parquet)]
  APP[Shiny app<br/>Posit Connect Cloud]
  CDSS --> DF & RF
  USGS --> DF
  RISE --> DF & RF
  GM --> DF
  DF --> S3
  RF --> S3
  DM -. local backfill .-> S3
  NHD -. local build .-> S3
  S3 --> APP
```

### ETL

All fetch and build code lives in `../scripts/`. Each fetch module defines a single-site function and a `*_many` wrapper that rate-limits requests and catches per-site errors, so one failed site doesn't stop the run. Fetch functions return tibbles; only the entry-point scripts write data.

| Workflow | Schedule | What it does |
|----|----|----|
| `daily_fetch.yml` | Daily, 13:30 UTC (GitHub often starts it hours late) | Re-pulls the last 7 days of diversion telemetry, streamflow, and reservoir storage, plus the last 75 days of gridMET. Provisional values get revised, so recent days are always refetched. |
| `backfill.yml` | 1st of each month | Re-pulls the last two years of approved CDSS records (monthly diversions, daily diversions, reservoir storage), then rebuilds the day-of-year statistics and water rights. Approved records lag about a year. |

Some steps run locally and are rerun only when their inputs change: the NHDPlus hydrofabric and reach network, the reference tables built from the tracked CSVs, the climate zones, and the long backfills (Daymet, full streamflow and reservoir history).

### Storage

Every dataset lives under one root, set by `TBD_DATA_ROOT`: `s3://co-water-data` in production, or a local folder such as `../data`. Reads and writes use `arrow`, which handles both. `upsert_dataset()` in `scripts/storage.R` replaces rows by key and rewrites only the partitions it touches, so reruns are idempotent.

| Dataset | Contents | Partitioned by |
|----|----|----|
| `streamflow_daily` | Daily mean flow (cfs) for 50 gages, USGS and CDSS | year |
| `diversions_daily` | Provisional daily telemetry (cfs) | year, month |
| `diversions_daily_records` | Approved daily diversion records | year |
| `diversions_monthly` | Approved monthly diversion totals (AF) and mean cfs | year |
| `diversions_monthly_classes` | Monthly records split by water class | year |
| `reservoir_storage_daily` | Daily storage (AF), flagged approved or provisional | year |
| `climate_daily` | Zone-mean daily climate from gridMET and Daymet | year |
| `*_doy_stats`, `diversions_monthly_normals` | Day-of-year percentiles and monthly normals | none |
| `reference/*` | Structures, gages, reservoirs, water rights, climate zones, flowlines, reach-to-gage distances | none |

Curated inputs are tracked in git under `../data/`: `structures.csv`, `stream_gages.csv`, `reservoirs.csv`, `basin_outlets.csv`, and `diversion_profiles.json`. The daily workflow copies `basin_outlets.csv` and `diversion_profiles.json` to S3 because the deployed app only bundles this folder.

### How the app loads data

`R/shiny_data_source.R` runs once per app process:

-   `streamflow_daily`, `diversions_daily`, and `diversions_daily_records` are read fully into memory as Arrow tables (about 40 MB). Map clicks and tab changes query them in memory instead of over S3.
-   Other datasets are collected at startup, filtered where possible (for example, only gridMET basin series are read from `climate_daily`).
-   GeoJSON and JSON files on S3 are downloaded to a temp file before `sf` or `jsonlite` reads them.

Files in `R/` are sourced automatically by `shiny::runApp()`. `manifest.json` pins package versions for Connect Cloud; regenerate it with `rsconnect::writeManifest()` after adding a package or a file in `R/`.

## Database structure

There is no database server. The "database" is a folder of Parquet files in an S3 bucket, laid out so `arrow` can query it like a table. The same code runs against a local folder or the bucket, and switching is one environment variable.

### Layout

```         
s3://co-water-data/
├── streamflow_daily/             # one dataset = one folder
│   ├── year=1990/part-0.parquet  # Hive partitions: key=value folders
│   ├── ...
│   └── year=2026/part-0.parquet
├── diversions_daily/
│   └── year=2026/month=10/part-0.parquet
├── streamflow_doy_stats/
│   └── part-0.parquet            # small tables: one file, no partitions
├── reference/
│   ├── gages/part-0.parquet
│   └── flowlines.geojson         # non-Parquet files sit alongside
├── basin_outlets.csv
└── diversion_profiles.json
```

`open_dataset("s3://co-water-data/streamflow_daily")` reads every partition as one table, and a filter on the partition column (`filter(year == 2026)`) skips the other folders entirely.

### Conventions

-   **One root.** Every path is built as `file.path(data_root(), dataset)`, where `data_root()` reads `TBD_DATA_ROOT`. Never hard-code `data/` or a bucket name.
-   **Each dataset has keys.** For example `id, date` for daily flow. Writes replace rows with the same keys, so a rerun or an overlapping date range never duplicates data.
-   **Partition by year, not finer.** Each partition is a separate file and a separate S3 request. Year/month split this project's streamflow into 442 files and took 16 s to read; by year it is 37 files and 2.4 s. Aim for files of at least a few hundred KB. Small lookup tables get no partitions.
-   **Write the full column set every time.** `open_dataset()` takes its schema from the first file it sees and silently drops columns other files have.
-   **Keep curated inputs in git.** Hand-edited CSVs stay in the repo; the bucket holds only what code produces, plus copies of any curated file the deployed app must read.

### The pieces to copy

1.  **`scripts/storage.R`.** `data_root()`, `upsert_dataset()` (read the affected partitions, drop rows matching the new keys, rewrite those partitions with `existing_data_behavior = "delete_matching"`), `overwrite_dataset()` for small tables, and helpers for paths that base R can't handle on S3: `path_exists()` instead of `file.exists()`/`dir.exists()`, `local_copy()` to download a file for `sf`/`readr`/`jsonlite`, and `put_file()` to upload one.

2.  **App data loader** (`R/shiny_data_source.R`). The same helpers, since only the app folder is deployed. Read small, frequently queried tables into memory once at startup with `as_arrow_table()`; querying S3 on every click is slow.

3.  **`.github/workflows/daily_fetch.yml`.** A cron trigger plus `workflow_dispatch`, `r-lib/actions/setup-r` and `setup-r-dependencies`, a first step that fails if any secret or variable is empty, then the fetch script with `TBD_DATA_ROOT=s3://<bucket>`. A `concurrency` group keeps two workflows from writing to the bucket at once.

4.  **AWS.** A private bucket (Block Public Access on) and two IAM users, each with an inline policy limited to that bucket and an explicit `Deny` on every non-S3 action:

    -   an ETL user with `s3:ListBucket`, `GetObject`, `PutObject`, and `DeleteObject` (delete is needed to replace partitions). Its keys go in GitHub repo secrets.
    -   an app user with only `ListBucket` and `GetObject`. Its keys go in the Connect Cloud app's variables.

    Keys go in as `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`, with `AWS_REGION` alongside. `arrow` reads them from the environment, so no code handles credentials. GitHub OIDC avoids stored keys altogether but needs an AWS account with advanced features enabled.

5.  **Connect Cloud.** Commit a `manifest.json` from `rsconnect::writeManifest()` (list the app files with `appFiles` to leave out stale files), publish from the GitHub repo, and set the variables above plus `TBD_DATA_ROOT`.

## Methods

### Gage condition (WaterWatch percentiles)

Gage colors follow the USGS WaterWatch method. For each gage and calendar day (month-day), `build_flow_stats.R` computes the minimum, maximum, and 10th, 25th, 50th, 75th, and 90th percentiles of daily flow on that day across all prior years. The current calendar year is excluded so today is ranked against history, and a day needs at least 10 years of data to be ranked. Percentiles use R's `quantile(type = 6)`, the Weibull plotting position `p = i / (n + 1)`, which is the convention USGS uses for flow statistics.

The most recent daily value (within the last 30 days) is then placed in one of seven classes: record low, below 10th, 10th to 24th, 25th to 75th, 76th to 90th, above 90th, record high. History starts in 1990, so "record" means the record since 1990 (or since the gage's first year), not the full period of record.

### River condition between gages

Each mapped NHDPlus reach (stream order 3 and up, about 18,000 reaches) gets an estimated flow percentile by inverse distance weighting of gage percentiles:

1.  Each gage's flow is converted to an approximate percentile by linear interpolation between its day-of-year knots (min = 0, p10 = 10, ... p90 = 90, max = 100). Interpolating percentiles rather than cfs makes a small creek and a large river comparable.
2.  Distances are measured along the river network, not straight-line. `build_reach_network.R` uses the NHDPlus value-added attributes (hydrosequence and path length) to find, for every reach and gage, the distance down to their confluence and back up. A gage on a different river system has no path and does not contribute.
3.  The reach estimate is the weighted mean of all connected gage percentiles with weights `1 / d²` (distance in km, floored at 0.5 km).

Reaches with no connected gage are left unranked. These are estimates; the info card says how many gages contributed.

The reach info card also shows NHDPlus EROM mean annual and monthly flow. These are modeled, gage-adjusted estimates for 1971 to 2000, not observations.

### Diversion normals and records

-   **Headgate totals.** CDSS monthly records come in several water classes. The headgate total is the administrative class `S:X U:Q T:0` (DWR Diversion Records Standard v3.0), with the largest class as a fallback.
-   **Daily normals.** Single-day diversion values are noisy, so each calendar day pools approved daily records from ±7 days across all prior years. Only recorded days count, because most ditches don't record outside their season (a missing day means no record, not zero). A day needs at least 5 years of records.
-   **Hydrograph series.** A diversion's chart joins three sources in order: monthly means before daily records begin, approved daily records, then provisional telemetry after the records end.
-   **Use breakdown.** Annual volume by use comes from water classes, dropping administrative totals, quantity-only uses, model and depletion types, releases, storage-to-storage moves, and within-structure moves to avoid double counting. Any remainder of the headgate total is labeled "Carried, use recorded elsewhere", typical of tunnels whose water is used downstream.

### Reservoir storage

-   **Sources.** Reclamation reservoirs come from RISE. Others come from CDSS approved stage-volume records, with CDSS storage telemetry filling days that have no approved record.
-   **Cleaning.** Negative values and values above 110% of a ceiling are dropped as recording errors. The ceiling is the curated capacity, or else the 99.9th percentile of approved values.
-   **Percentiles.** Many CDSS reservoirs record only at month end, so each series is linearly interpolated to daily across gaps of up to 45 days before day-of-year percentiles are computed (same classes and 10-year minimum as gages).
-   **Water-year change.** Storage change is the value closest to September 30 (within 15 days) minus the prior year's, counting only reservoirs with both values.

### Basin water-year accounting

For each of 8 basins and each water year (October 1 to September 30, named for the year it ends):

-   **Outflow** is the sum of the outlet gage(s) in `basin_outlets.csv`. A year counts only if every outlet gage has at least 330 days of data. Volume uses 1 cfs-day = 1.9835 AF.
-   **Exports and imports** come from structures whose source and destination basins differ. Months missing an approved record are filled from provisional telemetry, and the export bar for those years is hatched. CDSS transfer records are sparse before about 2013, so medians use only years with data.
-   **Share exported** = exports / (outflow + exports).
-   **Runoff ratio** = (outflow + exports − imports) / precipitation volume. It is left blank where imports exceed outflow (the South Platte), and is approximate where an outlet gage carries out-of-state inflow or misses part of the basin.
-   **Runoff timing** is the day of the water year when cumulative outflow passes half the annual total, with a least-squares trend in days per decade.

The accounting leaves out consumptive use, ungaged tributaries, and groundwater, so the terms will not balance exactly.

### Climate

Gridded daily climate is reduced to area-weighted means for 100 zones: the in-state part of each of 92 HUC8 watersheds and the 8 basin polygons. Each zone mean weights every grid cell by the share of its area inside the zone.

-   **gridMET** (about 4 km, 1979 to yesterday): precipitation, max and min temperature, grass reference ET (Penman-Monteith), and vapor pressure deficit. Cells are in degrees, so weights are scaled by cell area. The last two months or so are provisional. This is the source the app shows.
-   **Daymet** (1 km, 1980 to last year): precipitation, temperature, and SWE. Stored for future use but not shown, and not spliced with gridMET because the two disagree on mountain precipitation.

Water-year climate needs at least 360 days. Precipitation volume uses 1 mm over 1 km² = 0.8107 AF with geodesic zone areas. Because daily precipitation is mostly zeros, the water-year-to-date chart ranks the running total since October 1 against complete past water years rather than ranking single days. The temperature card shows water-year mean temperature, (Tmax + Tmin) / 2, with a linear trend.

## Running locally

From the repo root:

``` bash
Rscript -e 'shiny::runApp("shiny_app")'
```

With no `TBD_DATA_ROOT` set, the app reads `../data`. To read the production bucket, set `TBD_DATA_ROOT=s3://co-water-data`, `AWS_REGION=us-east-2`, and read-only AWS keys in `~/.Renviron`.

Expect about 10 s for the map to draw its 18,000 reaches at startup.
