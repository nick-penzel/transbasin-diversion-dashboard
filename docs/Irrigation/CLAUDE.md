# Irrigation module

Project specifics for the irrigation consumptive use module. Goals and workflow: `Irrigation_usage_module.md` (the playbook). Science, method options, and citations: `methods.md`. Repo-wide conventions: root `CLAUDE.md`.

## Status

- 2026-10-22: literature review done (`methods.md`). Method proposal sent to Nick; QMD not started until he approves.
- Branch `irrigation` off `main`.

## Scope

- Basin: Roaring Fork, HUC8 14010004 (`zone_id` in `data/reference/climate_zones`, 3,764 km²).
- Period: water year 2025 (Oct 2024 to Sep 2025). Switch to WY2026 once OpenET publishes Aug and Sep 2026.
- Output: irrigation consumptive use (CUirr) volume and depth for the HUC8, by field, month, crop, and irrigation type, compared with a non-irrigated baseline.
- Later: tie fields to ditches (`SW_WDID1..9`) and water rights to show who uses what.

## Data on hand

- CDSS Division 5 irrigated lands 2000 to 2023 shapefiles: `/Users/nickpenzel/Documents/R Projects/GitHub_Repo/Ag_waterefficiency/Div5_Irrigated_Lands_Shapefiles/` (EPSG 26913). 2023 layer in the HUC8: 668 fields, about 19,700 acres, District 38, median 17 acres; alfalfa and grass pasture, flood and sprinkler (`CROP_SRC` often NASS, so crop labels need checking).
- Old repo OpenET client: `Ag_waterefficiency/OpenEtAPI.R` (`openet_raster_sf()`, polygon time series endpoint), plus Div 5 field-level ensemble monthly ET CSVs for 2019 to 2024 (`PARCEL_ID`, `SW_WDID1`, `date`, `et_mm`).
- gridMET precipitation and ETo zone means already in `climate_daily` (`source = gridmet`).

## Access

- OpenET API key: Nick is adding it. Read from env (`OPENET_API_KEY` in `~/.Renviron`), never commit it.
- Google Earth Engine: needed for pixel-level work (non-irrigated reference pixels, interior-pixel filters, per-model collections). `R/ee_init.R` loads the Python `earthengine-api` through `reticulate::py_require()` (uv-managed env, not rgee) and initializes with `EE_PROJECT` from `~/.Renviron`. One-time browser login: `ee$Authenticate(auth_mode = "localhost")`. For CI later, use a service account key. OpenET on EE: use `projects/openet/assets/<model>/conus/gridmet/monthly/v2_0` (the `OpenET/...` catalog IDs are deprecated). As of 2026-10-22 all seven monthly collections end at 2024-12 (DisALEXI starts 2001), so WY2025 Jan to Sep is not on EE yet.

## Layout

- `docs/Irrigation/*.qmd`: investigation notebooks, later collected into a methods book.
- `docs/Irrigation/R/`: helper functions the QMD sources (move to `scripts/` when promoted to ETL).
- `docs/Irrigation/data/`: scratch outputs, gitignored. Promote to `data_root()` / S3 only after review.

## Review steps (from the playbook)

1. QMD done, then code review by a subagent (ETL validity).
2. Scientific review by the `hydrologist-reviewer` agent.
3. Nick reviews, then ETL to S3, dashboard branch and tab, PR to main.
