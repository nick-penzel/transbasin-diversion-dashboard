# Irrigation module

Project specifics for the irrigation consumptive use module. Goals and workflow: `Irrigation_usage_module.md` (the playbook). Science, method options, and citations: `methods.md`. Repo-wide conventions: root `CLAUDE.md`.

## Status

- 2026-10-22: `roaring_fork_cu.qmd` built, code-reviewed, and hydrologist-reviewed; fixes applied.
- 2026-10-23, after Nick's first review: Method B renamed "depletion above the native baseline". Method A's main estimate is a daily FAO-56 balance driven by OpenET ETa with precipitation and irrigation pools (`swb_eta_run()`, `field_cu_bucket()`).
- 2026-10-23, after the second code and hydrologist reviews:
  - Irrigation year is Nov to Oct (`irr_year()`), matching DWR and CU&L. IY2026 ends Sep 30 until OpenET posts Oct 2026.
  - Headline sharing rule is "cul" (drainage and ET from precipitation first, Reclamation's Prz definition); "mix" and "precip_first" are comparisons.
  - Irrigation window per field comes from ditch records (`field_irrigation_window`, built by `roaring_fork_diversions.qmd`), capped to Apr to Oct.
  - Status uses `irrigation_status_relative()`: field EToF minus the reference EToF > 0.2 in Jul or Aug means irrigated; only in May or Jun means shorted. The Reclamation 0.4 rule does not discriminate here.
  - Turf (52 fields, about 1,100 ac) is a separate line.
  - Open issue: reference ETa is 1.1 to 1.7 times gridMET P. gridMET checks out against SNOTEL (98%) and Daymet, so suspect eeMETRIC on native land or runon and groundwater. Method A moves less than 10% under P x 1.2 or spring ETa x 0.7.
  - Headline (eeMETRIC, CU&L): May to Sep CU 27,300 AF (2025) and 25,700 AF (2026); irrigation year 31,800 and 30,500 AF.
  - The CU notebook reads caches from the diversions notebook (`field_landclass_div5_2023`, `field_irrigation_window`, `ditch_month_irrigation`, `field_ditch_div5_2023`), so run that notebook first on a clean checkout.
- 2026-10-24: `roaring_fork_cu.qmd` had been rolled back on disk to a pre-10-23 draft; restored from the last knit copy (matches the 10-23 headline). Both notebooks end with a `dashboard-export` chunk (tables and methods figures to `data/dashboard/`); `scripts/publish_irrigation.R` (repo root) copies them to the data root and `shiny_app/methods/figures/`. Dashboard tab: `shiny_app/R/mod_irrigation.R`. Publication write-up: `shiny_app/methods/08-irrigation-cu.md` and `09-irrigation-rights.md`. Run notebooks with `knitr::purl()` then `Rscript` from this folder (about 1 minute total, caches only).
- Framing: Method A = accounting CU (Reclamation CU&L definition); Method B = depletion above native baseline (basin depletion vs natural conditions, dry-up). Method A is consistent in definition with Colorado HCU but is not an HCU determination. eeMETRIC is primary; SSEBop and geeSEBAL are the spread; the ensemble is not used for CU (DisALEXI, PT-JPL low on fields, SIMS high on natural land). Incidental use (18.9%) applies to Method A only.
- Quarto CLI is not installed. Test with `knitr::knit()` on a `.Rmd` copy placed at the same depth as `docs/Irrigation` so `../../data` resolves (scratch copy needs `data/reference`, `data/snotel_history`, `data/snotel_daily` linked).
- Branch `irrigation` off `main`.

## Scope

- Basin: Roaring Fork, HUC8 14010004 (`zone_id` in `data/reference/climate_zones`, 3,764 km²).
- Period: irrigation years (Nov to Oct) 2025 and 2026 (OpenET v2.1 runs through Sep 2026, all months provisional). October 2026 is missing.
- Output: irrigation consumptive use (CUirr) volume and depth for the HUC8, by field, month, crop, and irrigation type, compared with a non-irrigated baseline.
- Fields to ditches (`SW_WDID1..9`) and water rights: see `diversions_rights.md`.

## Data on hand

- CDSS Division 5 irrigated lands 2000 to 2023 shapefiles: `/Users/nickpenzel/Documents/R Projects/GitHub_Repo/Ag_waterefficiency/Div5_Irrigated_Lands_Shapefiles/` (EPSG 26913). NHD high resolution flowlines for Colorado are on EE at `projects/sat-io/open-datasets/NHD/NHD_CO/NHDFlowline` (`ftype` 336 canal/ditch, 460 stream, 558 artificial path); the NHDPlus V2 web service has almost no ditches. 2023 layer in the HUC8: 668 fields, about 19,700 acres, District 38, median 17 acres; alfalfa and grass pasture, flood and sprinkler (`CROP_SRC` often NASS, so crop labels need checking).
- Old repo OpenET client: `Ag_waterefficiency/OpenEtAPI.R` (`openet_raster_sf()`, polygon time series endpoint), plus Div 5 field-level ensemble monthly ET CSVs for 2019 to 2024 (`PARCEL_ID`, `SW_WDID1`, `date`, `et_mm`).
- gridMET precipitation and ETo zone means already in `climate_daily` (`source = gridmet`).

## Access

- OpenET API key: `OPENET_API_KEY` in `~/.Renviron`, never commit it. Not used yet; everything comes from EE.
- Google Earth Engine: needed for pixel-level work (non-irrigated reference pixels, interior-pixel filters, per-model collections). `R/ee_init.R` loads the Python `earthengine-api` through `reticulate::py_require()` (uv-managed env, not rgee) and initializes with `EE_PROJECT` from `~/.Renviron`. One-time browser login: `ee$Authenticate(auth_mode = "localhost")`. For CI later, use a service account key. OpenET on EE: use `projects/openet/assets/<model>/conus/gridmet/monthly/v2_1` (`v2_0` ends at 2024-12; the `OpenET/...` catalog IDs are deprecated). As of 2026-10-22 v2_1 runs through 2026-09, MGRS tile 13S covers the HUC8, scale factor 1. Reference ET: `projects/openet/assets/reference_et/conus/gridmet/{daily,monthly}/v1` (about 10% below raw gridMET ETo here, consistent with OpenET's station bias correction; not confirmed from metadata). EE `getRegion` timestamps overflow through reticulate, so parse dates from image IDs. `projects/openet` asset listing is not permitted.

## Diversions and owners (`roaring_fork_diversions.qmd`, `diversions_rights.md`)

- Owner IDs are HMAC-SHA256 of normalized OIT parcel owner names, keyed with `OWNER_HASH_KEY` in `~/.Renviron`. Names are never cached. `fetch_parcel_owners(..., reveal = TRUE)` reruns the pull and returns names in memory only. Changing the key means deleting `data/oit_parcel_owners_hashed_*` and rerunning. A scratch knit needs the key set.
- Eagle County's OIT submission replaces owner names with "EAGLE COUNTY PROPERTY OWNER" (class "withheld"); owner-level results leave out about 2,000 Eagle field acres.
- Allocate ditch quantities to fields by `serve_acres = max(mapped acres, CDSS parcel use acres)`; 12 ditches serve land outside the HUC8.
- CDSS `analysisservices/callanalysisbywdid` gives the daily out-of-priority share for each right.
- Pass-through: fishery and recreation classes (Paterson D Jacob Ext, RFC Ditch) are reported but left out of diversion and equity totals.
- IY2026 diversion records are partial. Rerun the `divrecmonth` pull under a new cache name in early 2027.
- The repo's `scripts/` `monthly_total()` keeps one "Total (Diversion)" row; structures with several accounts need the rows summed. Not fixed yet.

## Layout

- `docs/Irrigation/*.qmd`: investigation notebooks, later collected into a methods book.
- `docs/Irrigation/R/`: helper functions the QMD sources (move to `scripts/` when promoted to ETL).
- `docs/Irrigation/data/`: Parquet caches from `cached()`, gitignored. The cache is keyed on file name only, so names carry the version and date range (e.g. `openet_v2_1_field_monthly_202410_202609`). Promote to `data_root()` / S3 only after review.
- Paths to fix before promotion: `div5_dir()` defaults to the old repo; `read_huc8()` and the flowlines path assume `../..` from this folder. CDSS blocks scripted downloads (403), so the shapefiles need to be copied into `data/` or S3.
- Incidental use 18.9% comes from Reclamation's 1976 to 1980 CU&L technical appendix (Colorado main stem subareas C-7 to C-13), as shown in the 2025 methods manual, Attachment 1.

## Review steps (from the playbook)

1. QMD done, then code review by a subagent (ETL validity).
2. Scientific review by the `hydrologist-reviewer` agent.
3. Nick reviews, then ETL to S3, dashboard branch and tab, PR to main.
