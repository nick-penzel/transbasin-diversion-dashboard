# Roaring Fork CU and diversion workflows: audit inventory

Inventory of every function, input, output, and data source in the two irrigation notebooks (`roaring_fork_cu.qmd`, `roaring_fork_diversions.qmd`), their helpers in `R/`, and the publish step to the dashboard. Built from the code on branch `irrigation` (commit `e501ba7`) and the caches on disk on 2026-10-29. Paths are relative to `docs/Irrigation/` unless they start with `scripts/` or `shiny_app/`.

## 1. Run order and dependencies

```         
roaring_fork_diversions.qmd  (to the `windows` chunk)
   writes field_ditch_div5_2023, field_landclass_div5_2023,
          ditch_month_irrigation, field_irrigation_window
        │
        ▼
roaring_fork_cu.qmd
   reads the four caches above, writes data/cu_field_wy.parquet
   and data/dashboard/cu_*.parquet, fields.geojson, figures/cu-*.png
        │
        ▼
roaring_fork_diversions.qmd  (full run)
   reads data/cu_field_wy.parquet, writes data/dashboard/ditches, lorenz, ...
        │
        ▼
scripts/publish_irrigation.R   (from repo root)
   copies data/dashboard/*.parquet|geojson to <data_root>/irrigation/
   copies data/dashboard/figures/*.png to shiny_app/methods/figures/
        │
        ▼
shiny_app/R/shiny_data_source.R → shiny_app/R/mod_irrigation.R
```

The two notebooks depend on each other. On a clean checkout the diversions notebook stops at the `cu` chunk (no `cu_field_wy.parquet` yet) after writing the caches the CU notebook needs, so it has to run twice. The CU notebook's `from_diversions()` stops with a message if those caches are missing.

Repo-level inputs that must exist first: `data/reference/climate_zones.geojson` (`build_climate_zones.R`), `data/reference/flowlines.geojson` (`build_hydrofabric.R`, stream order ≥ 3), and `data/reference/snotel_sites`, `data/snotel_history`, `data/snotel_daily` (`build_snotel_stats.R`, `daily_fetch.R`).

## 2. External data sources

| \# | Source | Access | Endpoint, asset, or path | Auth | Fetched by | Cache |
|----|----|----|----|----|----|----|
| S1 | CDSS Division 5 irrigated lands, 2010, 2015, 2020, 2023 | Local shapefiles and DBF (CDSS blocks scripted download, 403) | `div5_dir()`: `DIV5_IRRIG_DIR` or `/Users/nickpenzel/Documents/R Projects/GitHub_Repo/Ag_waterefficiency/Div5_Irrigated_Lands_Shapefiles/Div5_Irrig_<year>.shp/.dbf` | none | `read_fields()`, `read_field_ditches()` | none for geometry (read each run); links cached |
| S2 | HUC8 14010004 polygon | Repo ETL output | `../../data/reference/climate_zones.geojson`, `zone_id == "14010004"` | none | `read_huc8()` | none |
| S3 | NHDPlus V2 flowlines, order ≥ 3 | Repo ETL output | `../../data/reference/flowlines.geojson` | none | `ref_inputs()` in CU notebook | inside reference caches |
| S4 | SNOTEL sites and daily data (NRCS AWDB, via repo ETL) | Repo datasets | `../../data/reference/snotel_sites`, `../../data/snotel_history`, `../../data/snotel_daily` (filter `huc8 == "14010004"`) | none | `prcp-check` (CU), `snow-years` (diversions) | none |
| S5 | CDSS parcel use | REST | `structures/parcelusets?wdid=&calYear=2023` | `scripts/api_key.txt` | `fetch_parcel_uses()` | `cdss_parcelusets_2023_field_ditches` |
| S6 | CDSS monthly diversion records, all water classes | REST | `structures/divrec/divrecmonth?wdid=<15 csv>&min-dataMeasDate=11/2009&max-dataMeasDate=10/2026` | key | `fetch_divrecmonth()` | `cdss_divrecmonth_field_ditches_200911_202610` |
| S7 | CDSS structures, Water District 38 | REST | `structures?waterDistrict=38` | key | `fetch_structures_wd()` | `cdss_structures_wd38` |
| S8 | CDSS net amount rights, WD 38 | REST | `waterrights/netamount?waterDistrict=38` | key | `fetch_net_rights()` | `cdss_netamount_wd38` |
| S9 | CDSS call analysis per right | REST | `analysisservices/callanalysisbywdid?wdid=&adminNo=&startDate=01/01/2010&endDate=10/22/2026` | key | `fetch_call_analysis()` | `cdss_callanalysis_field_ditch_rights_20100101_20261022` |
| S10 | CDSS historical admin calls, Div 5 | REST | `administrativecalls/historical?division=5&min-dateTimeSet=` | key | `fetch_admin_calls()` | **not called anywhere** |
| S11 | OIT Colorado Public Parcels composite | ArcGIS REST | `gis.colorado.gov/Public/rest/services/Address_and_Parcel/Colorado_Public_Parcels/MapServer/0/query`, envelope = field bbox + 500 m | none | `fetch_oit_parcels()`, `fetch_parcel_owners()` | `field_parcel_overlay_oit2026_div5_2023`, `oit_parcel_owners_hashed_huc14010004_2026` |
| S12 | gridMET daily (pr, tmmx, tmmn, eto) | Earth Engine | `IDAHO_EPSCOR/GRIDMET`, `getRegion` at 4000 m on cell-center points | `EE_PROJECT` + EE credentials | `gridmet_daily()`, `gridmet_transform()` | `gridmet_daily_20231001_20260930`, `gridmet_daily_snotel_rf_sites_20241001_20260930` |
| S13 | OpenET reference ET (bias-corrected gridMET ETo), daily and monthly | Earth Engine | `projects/openet/assets/reference_et/conus/gridmet/daily/v1` and `/monthly/v1`, band `eto` | EE | `gridmet_daily()`, `openet_month_image()` | in gridMET and OpenET caches |
| S14 | OpenET v2.1 monthly ETa: ensemble (`et_ensemble_mad`) and eeMETRIC, SSEBop, geeSEBAL, PT-JPL, SIMS, DisALEXI (`et`) | Earth Engine | `projects/openet/assets/<model>/conus/gridmet/monthly/v2_1`, Oct 2024 to Sep 2026, all provisional | EE | `openet_month_image()`, `field_et_monthly()`, `reference_et_monthly()`, `etof_irrigated()` | `openet_v2_1_*` |
| S15 | USGS 3DEP 10 m DEM | Earth Engine | `USGS/3DEP/10m_collection`, band `elevation` | EE | `dem_3dep()` | `field_elev_div5_2023`; inside reference caches |
| S16 | NLCD 2021 land cover | Earth Engine | `USGS/NLCD_RELEASES/2021_REL/NLCD`, band `landcover` (52 shrub, 71 grass, 90/95 wetland) | EE | `reference_mask()`, `reference_et_monthly(by_class = TRUE)` | inside reference caches |
| S17 | NHD high resolution flowlines, Colorado | Earth Engine community catalog | `projects/sat-io/open-datasets/NHD/NHD_CO/NHDFlowline`, `ftype` 336, 460, 558 | EE | `nhd_distance()` | inside tight reference caches |
| S18 | SSURGO available water capacity | Soil Data Access (`soilDB`) | `SDA_spatialQuery(what = "mupolygon")`, `get_SDA_property("awc_r", "Weighted Average", 0 to 100 cm)` | none | `field_awc()` | `field_awc_div5_2023` |
| S19 | Daymet daily precipitation, single pixel | REST | `daymet.ornl.gov/single-pixel/api/data?vars=prcp&years=2024,2025` | none | `daymet_point_prcp()` | `daymet_prcp_snotel_rf_2024_2025`, `daymet_prcp_field_cells_2024_2025` |
| S20 | Reclamation incidental use, Colorado main stem C-7 to C-13 | Literature constant | `incidental_use_frac <- 0.189` (Reclamation 2025 methods manual, Attachment 1) | n/a | `cu_period()` | n/a |
| S21 | FAO-56 crop parameters | Literature constants | `crop_params` (Tables 11, 12, 22) | n/a | `field_inputs()`, `kc_daily()` | n/a |

Secrets: `scripts/api_key.txt` (CDSS), `EE_PROJECT` and `~/.config/earthengine/` (EE), `OWNER_HASH_KEY` (owner hashing). `OPENET_API_KEY` is documented but not used.

## 3. Function inventory

Columns: inputs are arguments (defaults in brackets); outputs are return values. "Source" names the external source from section 2, if any.

### `R/cache.R`

| Function | Inputs | Output | Notes |
|----|----|----|----|
| `cached(name, build, refresh = FALSE)` | file stem, builder function | data frame | Reads `data/<name>.parquet` if present, else runs `build()` and writes it. Keyed on name only; no check that parameters match. |

### `R/fields.R`

| Function | Inputs | Output | Source |
|----|----|----|----|
| `div5_dir()` | env `DIV5_IRRIG_DIR` | path string | S1, absolute default path |
| `read_huc8(huc8 = "14010004", repo_root = "../..")` | HUC8 code | sf polygon, EPSG 26913 | S2 |
| `read_fields(huc8_poly, year = 2023)` | HUC8 polygon, layer year | sf: field_id (`PARCEL_ID`), crop, irrig_type, crop_src, sw_wdid1, acres (geometry area / 4046.873) | S1. Field kept when `st_point_on_surface` is inside the HUC8. `st_make_valid`. |
| `shrink_fields(fields, dist_m = 30)` | sf fields | sf of inward-buffered fields with `buffer_m`; empties dropped | none |
| `pick_buffer(x, dist_m = 30, min_pixels = 10)` | long ET table with buffer_m, n_pixels | same table, one buffer per field: 30 m if median ensemble pixels ≥ 10, else 0 | none |

### `R/ee_init.R`

| Function | Inputs | Output | Notes |
|----|----|----|----|
| `ee_init(project = Sys.getenv("EE_PROJECT"))` | GCP project ID | Python `ee` module | `reticulate::py_require("earthengine-api")`; stops if unset |

### `R/gridmet_ee.R`

| Function | Inputs | Output | Source |
|----|----|----|----|
| `gridmet_transform(ee)` | ee | numeric affine transform of the gridMET grid | S12 |
| `gridmet_cell_id(lon, lat, tr)` | coordinates, transform | `"row_col"` string | none |
| `gridmet_cells(ee, fields)` | sf fields | tibble: field_id, cell_id, lon, lat (cell center) | S12 (transform only) |
| `gridmet_daily(ee, cells, start, end)` | cells, dates (end exclusive) | tibble: cell_id, date, prcp_mm, tmax_c, tmin_c, eto_gridmet_mm, eto_mm | S12, S13. 12-month slices from `start` (`seq(start, end, by = "year")`), two `getRegion` calls per slice (gridMET, OpenET reference); date parsed from image ID; K to °C. The docstring's "one calendar year per request" is inaccurate. |
| `daymet_point_prcp(lon, lat, years)` | point, years | tibble: date, prcp_mm | S19. 365-day years. |

### `R/openet_ee.R`

| Object / function | Inputs | Output | Source |
|----|----|----|----|
| `openet_models` |  | `c("eemetric", "ssebop", "geesebal", "ptjpl", "sims", "disalexi")` |  |
| `openet_id(model, version = "v2_1")` | model name | asset ID string | S14 |
| `sf_to_ee(ee, x)` | sf | ee.FeatureCollection, EPSG 4326, 6 decimal places | none |
| `openet_month_image(ee, month_start)` | month start Date | ee.Image with bands ensemble, six models, eto (mm/month); `mosaic()` of the month | S13, S14 |
| `field_et_monthly(ee, polys, months)` | sf with field_id, buffer_m; month Dates | tibble: field_id, buffer_m, month, variable, et_mm, n_pixels | S14. `reduceRegions` mean + count at 30 m, EPSG 32613, one call per month. |

### `R/reference_ee.R`

| Function | Inputs | Output | Source |
|----|----|----|----|
| `dem_3dep(ee)` | ee | ee.Image elevation, native projection | S15 |
| `reference_mask(ee, huc8_poly, fields_all, streams, max_slope = 10, near_m = 5000, field_buffer_m = 200, stream_buffer_m = 150, wet_buffer_m = 100)` | HUC8, all-year fields, flowlines | ee.Image mask of NLCD 52/71, slope \< 10°, within 5 km of fields, outside field/stream/wetland buffers | S3, S15, S16 |
| `etof_irrigated(ee, months, threshold = 0.4, min_months = 3)` | month Dates | ee.Image, 1 where eeMETRIC/ETo \> threshold in ≥ min_months | S13, S14 |
| `nhd_distance(ee, region, ftypes, max_m = 500)` | region, FType codes | ee.Image distance (m) | S17 |
| `reference_mask_tight(ee, mask, huc8_poly, wet_months, wet_threshold = 0.6, wet_min_months = length(wet_months), ditch_buffer_m = 100, creek_buffer_m = 60)` | base mask, Jul and Aug Dates | ee.Image mask, also dropping pixels near NHD ditches (100 m), streams/artificial paths (60 m), and mid-summer wet pixels | S17, S14 |
| `reference_et_monthly(ee, mask, huc8_poly, months, by_class = FALSE)` | mask, months | tibble: elev_band (100 m floor), nlcd, month, variable (ensemble, six models, eto), et_mm, n_pixels | S14, S15, S16. Grouped `reduceRegion` at 30 m, `tileScale = 4`. |
| `pool_classes(r)` | output of `reference_et_monthly(by_class = TRUE)` | tibble: variable, elev_band, month, pixel-weighted et_mm, n_pixels | none |
| `field_elevation(ee, fields)` | sf fields | tibble: field_id, elev_m (mean 3DEP at 10 m) | S15 |

### `R/soils.R`

| Function | Inputs | Output | Source |
|----|----|----|----|
| `field_awc(fields, chunk = 50)` | sf fields | tibble: field_id, awc_mm_per_m (area-weighted `awc_r` × 1000), soil_frac | S18 |

### `R/fao56.R`

| Object / function | Inputs | Output | Notes |
|----|----|----|----|
| `crop_params` |  | tibble, alfalfa and grass_pasture: kc_ini, kc_mid, kc_end, root_m, p, len_ini, len_dev | Alfalfa 0.40/0.95/0.90, 1.2 m; grass 0.40/0.90/0.80, 0.6 m; p = 0.55 |
| `swb_settings(...)` | overrides | list: t30_start_c 7, earliest_start 04-15, frost_end_c -4, frost_after 08-15, latest_end 10-31, len_late 20, kc_dormant 0.25, snow_t_c 1, melt_mm_c 3, cn 75, irrig_end 09-30 |  |
| `kc_daily(date, tmean, tmin, crop, s)` | daily vectors for one cell, one crop row | tibble: date, in_season, kc, season_start, season_end | 30-day trailing mean temperature start; frost or Oct 31 end |
| `scs_runoff(w, cn)` | daily water input (mm), CN | runoff (mm) | Ia = 0.2 S |
| `swb_run(prcp, tmean, eto, kc, taw, p, irr_window, s, dr0 = 0.5)` | day × field matrices | list of matrices: pe, ro, dp, et, etc, irr, swe, sw | Kc × ETo balance; degree-day snow; refill to FC when Dr \> RAW |
| `field_inputs(fields, weather, s)` | fields (field_id, cell_id, crop, awc_mm_per_m), `gridmet_daily()` output | list: fields (with taw, p), dates, matrices prcp, tmean, eto, kc, in_season | Unknown crops become grass_pasture. Uses `eto_mm` (OpenET-corrected). |
| `monthly_long(mats, dates, field_id, state = list())` | matrices | tibble: month, field_id, one column per matrix (sums; `state` at month end) |  |
| `field_pe_monthly(fields, weather, s, irrigated = TRUE)` | as `field_inputs` | tibble: field_id, month, prcp_mm, eto_mm, pe_mm, ro_mm, dp_mm, et_sim_mm, etc_mm, irr_mm, sw_end_mm | Kc × ETo balance, irrigation through Sep 30 |
| `eta_daily(eta, x)` | monthly ETa, `field_inputs()` list | day × field matrix, monthly ETa × daily ETo / monthly ETo | NA where no ETa |
| `from_precip(amount, sp, si, mode)` | draw, pool sizes, mode (mix, p, i) | mm taken from precipitation pool |  |
| `swb_eta_run(prcp, tmean, eto, kc, eta, taw, p, irr_window, s, share = c("cul", "mix", "precip_first"), dr0 = 0.5)` | matrices incl. daily ETa | list of matrices: et, et_p, et_i, carry, other, irr, dp, ro, sw_p, sw_i | Two-pool balance; CU = et_i. Docstring for `share` lists only two of the three options. |
| `field_cu_bucket(fields, weather, eta, s, share = "cul", window = NULL)` | fields, weather, monthly ETa for one model, optional field-month `open` window | tibble: field_id, month, eta_mm, et_p_mm, cu_mm, carry_mm, other_mm, irr_mm, dp_mm, sw_p_mm, sw_i_mm | NA window months fall back to modeled season through `irrig_end` |

### `R/cu.R`

| Object / function | Inputs | Output | Notes |
|----|----|----|----|
| `incidental_use_frac` |  | 0.189 | S20 |
| `mm_to_af(mm, acres)` |  | mm / 304.8 × acres |  |
| `water_year(d)` | Dates | Oct to Sep year |  |
| `irr_year(d)` | Dates | Nov to Oct year | Same as `irrigation_year()` in diversions.R |
| `et_wide(et)` | long ET after `pick_buffer()` | wide: field_id, month, ensemble, six models, eto, model_mean, ens_filled | Ensemble NA → model mean; eemetric/ssebop/geesebal NA → ensemble; remaining NA → 0 for ensemble, eemetric, ssebop, geesebal only (ptjpl, sims, disalexi stay NA) |
| `irrigation_status(w, threshold = 0.4, min_months = 3)` | `et_wide()` | field_id, iy, n_months, months_wet, irrigated | Reclamation rule, comparison only |
| `irrigation_status_relative(w, ref_etof, excess = 0.2)` | `et_wide()`, field-month reference EToF | list: status (field_id, iy, irrigated, shorted), wet (field_id, month, wet) | Headline status rule |
| `field_month_wet(w, threshold = 0.4)` | `et_wide()` | field_id, month, wet |  |
| `cu_method_a(eta, pe)` | monthly ETa, monthly Pe | field_id, month, eta_mm, pe_mm, cu_mm | Monthly Reclamation form with carry-forward, reset each IY |
| `field_reference(ref, elev, min_pixels = 500)` | one-variable reference table, field elevations | field_id, month, ref_mm, ref_band | Nearest band with enough pixels |
| `cu_method_b(eta, fref)` | ETa, field reference | field_id, month, eta_mm, ref_mm, cu_mm (may be negative) |  |
| `cu_period(cu, fields, wet, months = 5:9)` | monthly CU, field status and acres, wet months | per field-IY: cu_mm, cu_af, net_cu_af plus status columns | Floors period total at 0; shorted fields count only wet Apr to Oct months; fallow 0 |
| `irrigation_window(win, status, wet, field_ids, months)` | ditch window, status, wet, all fields, months | field_id, month, open (TRUE/FALSE/NA) | Capped to Apr to Oct; shorted fields open only in wet months |

### `R/diversions.R`

| Object / function | Inputs | Output | Source |
|----|----|----|----|
| `cdss_base`, `divrec_release_types` (6, 7, 8, E, L, Q), `pass_through_uses` (Fishery, Recreation), `cdss_use_codes` |  | constants | CDSS dictionaries |
| `cdss_key(path = "../../scripts/api_key.txt")` |  | key string |  |
| `cdss_get(endpoint, ..., key)` | endpoint, query params | tibble of all pages (pageSize 50000) | 404 → empty; `max_tries = 3` (3 attempts total, httr2 default transient codes 429/503 only; a 500 fails); 300 s timeout |
| `read_field_ditches(fields, year = 2023)` | sf fields, year | field_id, master_id, comments, wdid (7-char), slot, acres, n_ditches, acres_split | S1 DBF |
| `field_landclass(links)` | `read_field_ditches()` | field_id, land_class (agricultural/turf), turf_type, basis | `COMMENTS` = GOLF COURSE, PARK, LAWN, RANCHETTES |
| `fetch_parcel_uses(wdids, cal_year = 2023, key, pause = 0.2)` | WDIDs | wdid, field_id, cal_year, acres_prorated, acres_total, n_sw, n_gw | S5. Failed WDIDs logged and skipped. |
| `irrigation_year(d)` | Dates | Nov to Oct year | Duplicate of `irr_year()` |
| `fetch_divrecmonth(wdids, start, end, key, batch = 15, pause = 0.3)` | WDIDs, date range | wdid, month_start, wc_identifier, af, meas_count, approval | S6. Failed batches logged and skipped. |
| `parse_wc(wc)` | water class identifiers | s, f, u, t, g, to |  |
| `divrec_total(x)` | divrecmonth rows | wdid, month_start, af, approval, total_from | Sum of "Total (Diversion)" rows, else `S:X U:Q T:0`, else sum of non-admin classes |
| `divrec_by_use(x, linked)` | divrecmonth rows, linked WDIDs | wdid, month_start, s, u, t, f, g, to, use, carried_in, af, approval | Drops totals, T:0, same-structure F: accounts |
| `ditch_use_mix(by_use, min_share = 0.01)` | by-use rows | wdid, total_af, irr_af, irr_share, other_uses, mix |  |
| `ditch_mean_af(by_use, reported, years)` | by-use rows, reported ditch-years | wdid, n_years, af_mean | Mean over reported years only |
| `fetch_call_analysis(rights, start_date, end_date, key, pause = 0.3)` | wdid, admin_number per right | wdid, admin_number, date, oop_pct, caller | S9. `adminNo` sent as `%.5f`. Max OOP per day. Failed rights logged and skipped. |
| `fetch_admin_calls(division = 5, start_date, key)` |  | call_number, set, released, water_source, location_wdid, location, priority_admin, priority_date | S10. **Unused.** |

### `R/rights.R`

| Object / function | Inputs | Output | Source |
|----|----|----|----|
| `irrigation_use_pattern` |  | `"[1X]"` |  |
| `public_entity_names` |  | tibble of regex → public label |  |
| `classify_contact(x)` | names | none, public entity, ditch company, private business, individual |  |
| `public_name(x, class)` | names, classes | curated public label or ditch company name, else NA |  |
| `summarise_contacts(x)` | one `associatedContacts` string | list: classes, public |  |
| `fetch_structures_wd(water_district = 38, key)` |  | wdid, name, structure_type, ciu, water_source, county, stream_mile, contact_classes, contact_public, lat, lon | S7. Raw contacts dropped. |
| `fetch_net_rights(water_district = 38, key)` |  | wdid, structure_name, structure_type, water_source, appropriation_date, adjudication_date, admin_number, priority_number, decreed_uses, net_absolute, net_conditional, decreed_units, seasonal_limitation | S8 |
| `is_irrigation_use(codes)` | decreed use strings | logical |  |
| `decode_uses(codes)` | decreed use strings | labels |  |
| `ditch_rights(rights)` | net rights | wdid, n_rights, cfs_abs, cfs_irr, senior_admin, junior_admin, wmean_admin, first_approp, uses, nonirr_decree | cfs absolute \> 0 only |
| `gini(x)`, `top_share(x, top)`, `lorenz(x)`, `concentration(x)` | values per holder | Gini; top share; Lorenz points; n, total, gini, top10pct_share, top10_share, holders_for_half |  |
| `gini_per_acre(amount, weight)` | amount, acres | Gini over acres |  |
| `field_blocks(fields, gap_m = 10)` | sf fields | field_id, block_id | Connected components within 10 m |
| `oit_parcels_url` |  | URL | S11 |
| `oit_query_pages(bbox, out_fields, geometry = TRUE, page = 2000)` | bbox | list of pages | S11. Pages while `exceededTransferLimit`. |
| `fetch_oit_parcels(bbox)` | bbox | sf: parcel_id, county, land_use, land_acres | S11, no owner fields |
| `field_parcel_overlay(fields, parcels, min_acres = 0.25)` | fields, parcels | field_id, parcel_id, county, land_use, land_acres, overlap_acres |  |
| `owner_hash_key()` | env `OWNER_HASH_KEY` | key | stops if unset |
| `normalize_owner(x)` | owner names | normalized names |  |
| `owner_placeholder_pattern` |  | regex for withheld owners |  |
| `hash_owner(x, key)` | normalized names | `"O" + 16 hex` HMAC-SHA256 |  |
| `fetch_parcel_owners(bbox, parcels, reveal = FALSE, key)` | bbox, parcels to keep | parcel_id, county, owner_id, owner_class, owner_public (+ owner_name if reveal) | S11 |

### Notebook-local helpers

| Notebook | Helper | What it does |
|----|----|----|
| CU | `ee_session()` | Lazy, memoized `ee_init()` |
| CU | `eta_of(var, x = w)` | One ETa column as field_id, month, eta_mm |
| CU | `run_bucket(eta, share, f, weather, s, win)` | `field_cu_bucket()` from Oct 2024 |
| CU | `summarise_cu(cu, label, months, fy)` | `cu_period()` per ETa model, summed; per-acre CU over irrigated plus shorted acres |
| CU | `ref_inputs()` | Base `reference_mask()` from 2015, 2020, 2023 fields and flowlines |
| CU | `ref_tight(threshold = 0.6, min_months = 2)` | Tight mask per IY; `min_months = 2` means both July and August, `ref_tight(0.6, 1)` means either |
| CU | `season_ref(r)` | May to Sep reference sums, bands 1700 to 2800 m |
| CU | `tidy_comp(...)` | Comparison table with AF per irrigated or shorted acre |
| Div | `period_label(iy)`, `yr_kind(y)` | IY2015-2024 mean / IY2025 / IY2026; dry, wet, other |
| Div | `iy_pos(m)`, `pos_month(p)` | Month to Nov-first position and back |
| Div | `caller_group(x)`, `trib_group(src)` | Caller and water source groupings by regex |
| Div | `summarise_group(d, grp)` | Tercile or source summary: cfs per 100 ac, call days, late/early and augmented shares |
| Div | `level_tables(fa)` | Field, block, parcel, owner, ditch tables for concentration |
| Div | `thin(d, n = 150)` | Resamples Lorenz curves to 150 points |
| Div | `land_use_class(x)` | Assessor land use regex classes |

### Thresholds not set in `R/`

| Where | Value |
|----|----|
| Method B mask variants (`b_variants`) | `field_reference(min_pixels = 300)`; headline uses default 500 |
| Closure table | bands need ≥ 500 pixels |
| `season_ref()`, reference elevation plot | bands 1700 to 2800 m; plot lines need ≥ 300 pixels |
| `outside_huc` | parcel-use acres exceed mapped acres by \> 1 ac |
| Quantity-only reassignment | ditch ≥ 99% irrigation class |
| Ditch window from records | ditch reported through September that IY; else climatology months with irrigation in ≥ 50% of IY2015-2024 reported years |
| `cu_vs` matched ditches | ≥ 5 mapped acres, every linked ditch of every field reported |
| Priority terciles | cut on total mapped acres including turf; `ag_acres > 0` drops only all-turf ditches |
| Dry and wet years | 3 lowest and 3 highest Apr 1 SWE, 2010 to 2025, sites with a full record |
| Diversions `cu` chunk | renames `wy` to `iy` if present; falls back to `A_daily_mix` if `A_daily_cul` is absent |

## 4. Notebook chunk flow

### `roaring_fork_diversions.qmd`

| Chunk | Reads | Functions | Writes / key objects |
|----|----|----|----|
| setup | `R/*.R` |  | `hist_iy = 2015:2024` |
| links | S1, S2 | `read_huc8`, `read_fields`, `read_field_ditches` | cache `field_ditch_div5_2023`; `links`, `wdids` (243). Asserts all fields linked and acres conserved. |
| landclass | links | `field_landclass` | cache `field_landclass_div5_2023` |
| layer-years | S1 (2010, 2015, 2020, 2023) | `read_fields`, `read_field_ditches` | cache `field_ditch_acres_div5_2010_2023` |
| parcel-uses | S5 | `fetch_parcel_uses` | cache `cdss_parcelusets_2023_field_ditches`; `ditch_acres` with `serve_acres = max(mapped, CDSS)` |
| divrec | S6 | `fetch_divrecmonth`, `divrec_total`, `divrec_by_use`, `irrigation_year` | cache `cdss_divrecmonth_field_ditches_200911_202610`; `tot`, `by_use` (quantity-only on ≥ 99% irrigation ditches reassigned to Irrigation), `reported`, `recon_ok` |
| iy2026-lag, use-split | tot, by_use |  | `use_tbl` (IY2015-2024 mean, IY2025, IY2026) |
| pass-through | S7 | `fetch_structures_wd` | cache `cdss_structures_wd38`; `pt` |
| mix | by_use | `ditch_use_mix` | `mix` |
| structures | st |  | contact class table |
| rights | S8 | `fetch_net_rights`, `ditch_rights`, `is_irrigation_use` | cache `cdss_netamount_wd38`; `r_f`, `dr` |
| windows | tot, by_use |  | caches `ditch_month_irrigation` (Oct 2023 to Oct 2026), `field_irrigation_window` (records if the ditch reported through Sep, else ≥ 50% IY2015-2024 climatology) |
| cu | `data/cu_field_wy.parquet` |  | `cu`: method `A_daily_cul`, eeMETRIC, period `irrigation_year` (first period that is not may_sep) |
| ditch-table | above | `ditch_mean_af` | `link_alloc` (share = acres_split / serve_acres), `ditch_tbl`. Asserts ditch CU sums to field CU. |
| owners | S11 | `fetch_oit_parcels`, `field_parcel_overlay`, `fetch_parcel_owners` | caches `field_parcel_overlay_oit2026_div5_2023`, `oit_parcel_owners_hashed_huc14010004_2026`. Asserts no `owner_name`. |
| concentration, turf, lorenz, top-owners, per-acre | above | `field_blocks`, `concentration`, `lorenz`, `gini_per_acre` | `ag_levels`, `conc`, `own_class`, `pa`, `turf_tbl` |
| adequacy | cu `niwr_mm` |  | CU / NIWR per field |
| snow-years | S4 |  | `swe`, dry/wet years (3 lowest/highest Apr 1 SWE, 2010 to 2025) |
| calls | S9 | `fetch_call_analysis` | cache `cdss_callanalysis_field_ditch_rights_20100101_20261022`; `caller_tbl` |
| priority | ca, ditch_tbl |  | `prio` (terciles of acres by cfs-weighted admin no.), `t_tbl`, `g_tbl`, `within` |
| cu-vs-div | link_alloc, irr_by_iy |  | `cu_vs`, `cu_vs_tbl` (matched ditches only) |
| parcels | ov |  | assessor land use table |
| dashboard-export | above |  | `data/dashboard/`: ditches, field_ditch, diversion_use, diversion_month, lorenz, concentration, owner_class, per_acre_gini, turf, priority_tercile, priority_source, callers, priority_spearman, calls_year, snow_years, cu_vs_diversion, cu_vs_diversion_summary; figures rights-lorenz.png, rights-cu-vs-diversion.png |

### `roaring_fork_cu.qmd`

| Chunk | Reads | Functions | Writes / key objects |
|----|----|----|----|
| setup | `R/*.R` | `ee_init` (lazy) | `wy_months` Oct 2024 to Sep 2026; `balance_months` Oct 2023 to Sep 2026; `season = 5:9` |
| fields | S1, S2, `field_landclass_div5_2023` | `read_huc8`, `read_fields` | `fields` (668) |
| weather | S12, S13 | `gridmet_cells`, `gridmet_daily` | caches `field_cells_div5_2023`, `gridmet_daily_20231001_20260930`; `wx` |
| prcp-check | S4, S12, S19 | `gridmet_transform`, `gridmet_daily`, `daymet_point_prcp`, `water_year` | caches `gridmet_daily_snotel_rf_sites_20241001_20260930`, `daymet_prcp_snotel_rf_2024_2025`, `daymet_prcp_field_cells_2024_2025` (diagnostic only) |
| et | S14 | `shrink_fields`, `field_et_monthly`, `pick_buffer`, `et_wide` | cache `openet_v2_1_field_monthly_202410_202609`; `w` |
| fields-map, et-models, et-season, buffer-sensitivity | w, et_all |  | `model_month`, `season_et`, `buf` |
| status | S3, S14 to S17, S1 (2015, 2020, 2023) | `field_elevation`, `reference_mask`, `reference_mask_tight`, `reference_et_monthly(by_class = TRUE)`, `pool_classes`, `field_reference`, `irrigation_status_relative`, `irrigation_status` | caches `field_elev_div5_2023`, `openet_v2_1_reference_tight_monthly_202410_202609`; `ref`, `ref_etof`, `status`, `wet`, `field_year` |
| swb-params | S18 | `field_awc` | cache `field_awc_div5_2023`; `f_tbl` |
| season-length | wx | `kc_daily` | table only |
| swb-run, pe-timing | f_tbl, wx | `field_pe_monthly` | `pe` (Kc × ETo balance) |
| window | `field_irrigation_window` | `irrigation_window` | `window` |
| method-a-daily | f_tbl, wx, w, window | `field_cu_bucket` (via `run_bucket`), `cu_period` (via `summarise_cu`) | `cu_d` (3 models × 3 share rules), `res_d`, `budget` |
| method-a-daily-plot, method-a-daily-tbl | cu_d, res_d |  | figure, table, `pool_start` |
| method-a | pe, w | `cu_method_a` | `cu_a`, `res_a` |
| swb-sensitivity | as method-a-daily | `swb_settings`, `et_wide` | `sens_tbl` (9 runs) |
| groundwater | `field_ditch_div5_2023`, `ditch_month_irrigation` |  | `gw_tbl` |
| reference | S3, S14 to S17 | `reference_et_monthly`, `pool_classes`, `ref_tight` | caches `openet_v2_1_reference_monthly_202410_202609`, `..._etof05_...`, `..._etof07_...`, `..._etof06_either_...`; `ref_variants`, `ref_area`, `field_season` |
| closure, fallow-check | ref, wx |  | closure tables |
| method-b | ref, w, elev | `field_reference`, `cu_method_b` | `cu_b`, `res_b`, `b_variants` |
| cross-check, irrigation-year, land-class, findings, comparison-plot, cu-map | above |  | `comp`, `comp_iy`, `by_class` |
| export | above | `cu_period` | `data/cu_field_wy.parquet`: 5 methods × 3 ETa models × 2 periods × fields × IY2025-2026, with `niwr_mm` |
| dashboard-export | above | `field_reference`, `rmapshaper::ms_simplify` | `data/dashboard/`: fields.geojson, cu_field_month, cu_field_iy, cu_summary, cu_sensitivity, cu_et_models, cu_reference_masks, cu_groundwater_flags, cu_land_class; figures cu-et-models.png, cu-reference-elevation.png, cu-water-sources.png. Asserts monthly sums match IY totals within 1%. |

## 5. Cache inventory (`data/`, on disk 2026-10-29)

| Cache | Rows | Columns | Built by | Read by | Date |
|----|----|----|----|----|----|
| field_ditch_div5_2023 | 756 | field_id, master_id, comments, wdid, slot, acres, n_ditches, acres_split | Div links | Div, CU groundwater | 10-23 |
| field_landclass_div5_2023 | 668 | field_id, land_class, turf_type, basis | Div landclass | Div, CU fields | 10-23 |
| field_ditch_acres_div5_2010_2023 | 4 | year, fields, ditches, acres | Div layer-years | Div | 10-23 |
| cdss_parcelusets_2023_field_ditches | 769 | wdid, field_id, cal_year, acres_prorated, acres_total, n_sw, n_gw | Div | Div | 10-23 |
| cdss_divrecmonth_field_ditches_200911_202610 | 40,283 | wdid, month_start, wc_identifier, af, meas_count, approval | Div | Div | 10-23 |
| cdss_structures_wd38 | 6,437 | wdid, name, structure_type, ciu, water_source, county, stream_mile, contact_classes, contact_public, lat, lon | Div | Div | 10-23 |
| cdss_netamount_wd38 | 6,594 | wdid ... seasonal_limitation | Div | Div | 10-23 |
| cdss_callanalysis_field_ditch_rights_20100101_20261022 | 3,216,836 | wdid, admin_number, date, caller, oop_pct | Div | Div | 10-23 |
| cdss_waterclasses_wd38 | 15,422 | wdid, wc_identifier, divrectype, source_code, source, use_code, use, type_code, type, from_wdid, group_wdid, to_wdid | **no builder in current code** | **nothing** | 10-23 |
| ditch_month_irrigation | 2,698 | wdid, month_start, irr_af | Div windows | CU groundwater | 10-23 |
| field_irrigation_window | 1,336 | field_id, iy, first_month, last_month, basis | Div windows | CU window | 10-23 |
| field_parcel_overlay_oit2026_div5_2023 | 1,929 | field_id, parcel_id, county, land_use, land_acres, overlap_acres | Div owners | Div | 10-23 |
| oit_parcel_owners_hashed_huc14010004_2026 | 1,303 | parcel_id, county, owner_id, owner_class, owner_public | Div owners | Div | 10-23 |
| field_cells_div5_2023 | 668 | field_id, cell_id, lon, lat | CU weather | CU | 10-22 |
| gridmet_daily_20231001_20260930 | 82,200 | cell_id, date, prcp_mm, tmax_c, tmin_c, eto_gridmet_mm, eto_mm | CU weather | CU | 10-22 |
| gridmet_daily_snotel_rf_sites_20241001_20260930 | 5,840 | as above + site_id | CU prcp-check | CU | 10-23 |
| daymet_prcp_snotel_rf_2024_2025 | 5,840 | date, prcp_mm, site_id | CU prcp-check | CU | 10-23 |
| daymet_prcp_field_cells_2024_2025 | 54,750 | date, prcp_mm, cell_id | CU prcp-check | CU | 10-23 |
| openet_v2_1_field_monthly_202410_202609 | 249,984 | buffer_m, field_id, month, variable, n_pixels, et_mm | CU et | CU | 10-22 |
| field_elev_div5_2023 | 668 | field_id, elev_m | CU status | CU | 10-22 |
| field_awc_div5_2023 | 668 | field_id, soil_frac, awc_mm_per_m | CU swb-params | CU | 10-22 |
| openet_v2_1_reference_monthly_202410_202609 | 5,184 | elev_band, variable, et_mm, n_pixels, month (no `nlcd`) | CU reference | CU | 10-22 |
| openet_v2_1_reference_tight_monthly_202410_202609 | 62,208 | elev_band, nlcd, month, variable, et_mm, n_pixels | CU status | CU | 10-23 |
| openet_v2_1_reference_etof05/07/06_either_monthly_202410_202609 | 7,537 / 7,794 / 7,463 | as tight | CU reference | CU | 10-23 |
| cu_field_wy (not via `cached()`) | 40,080 | field_id, iy, method, eta, period, cu_mm, cu_af, niwr_mm, acres, irrigated, shorted, land_class, sw_wdid1 | CU export | Div cu | 10-29 |

## 6. Dashboard outputs and app use

`scripts/publish_irrigation.R` copies every `data/dashboard/*.parquet|geojson` to `<data_root>/irrigation/` (`put_file()`, S3 by default per `~/.Renviron`). It never deletes at the destination, so a table dropped from the export keeps being served, and it checks only that `fields.geojson` and `ditches.parquet` exist. Note that both notebooks read `climate_zones`, `flowlines`, and SNOTEL from local `../../data`, while the app reads the HUC8 polygon from the data root, so the two can use different copies and the PNGs to `shiny_app/methods/figures/`. `shiny_app/R/shiny_data_source.R` loads only the tables in `irrigation_tables` plus `fields.geojson` and the HUC8 polygon.

| Table | Rows | Built by (date) | Loaded by app |
|----|----|----|----|
| fields.geojson | 668 | CU (10-29) | yes |
| cu_field_iy | 2,672 | CU (10-29) | yes |
| cu_field_month | 15,364 | CU (10-29) | yes |
| cu_summary | 64 | CU (10-29) | yes |
| cu_sensitivity | 9 | CU (10-29) | yes |
| cu_et_models | 8 | CU (10-29) | loaded, never read by `mod_irrigation.R` |
| cu_reference_masks | 7 | CU (10-29) | no |
| cu_groundwater_flags | 3 | CU (10-29) | no |
| cu_land_class | 4 | CU (10-29) | no |
| ditches | 243 | Div (10-24) | yes |
| field_ditch | 756 | Div (10-24) | yes |
| diversion_month | 144 | Div (10-24) | yes |
| lorenz | 3,750 | Div (10-24) | yes |
| concentration | 25 | Div (10-24) | yes |
| owner_class | 3 | Div (10-24) | yes |
| priority_tercile | 3 | Div (10-24) | yes |
| calls_year | 51 | Div (10-24) | yes |
| snow_years | 17 | Div (10-24) | yes |
| cu_vs_diversion_summary | 2 | Div (10-24) | yes |
| diversion_use, per_acre_gini, turf, priority_source, callers, priority_spearman, cu_vs_diversion | 24, 3, 5, 8, 26, 7, 185 | Div (10-24) | no |

## 7. Findings after independent review

An independent agent checked this document against the code and caches on 2026-10-29 and reran the eeMETRIC CU&L balance from the caches; its ETa and precipitation-ET columns match `cu_field_month` exactly. Row counts, columns, endpoints, EE assets, chunk reads and writes, and unit conversions (mm / 304.8 × acres, m² / 4046.873, K to °C, 900 m² pixels) were confirmed. Findings, ranked:

| \# | Severity | Finding | Evidence | Status |
|----|----|----|----|----|
| 1 | High | **Irrigation-year CU includes carryover across years.** November to March CU on irrigated fields (irrigation-pool water used after the window closes) is 1,824 AF in IY2025 and 3,634 AF in IY2026, about 6% and 12% of the IY totals. IY2026's comes from water applied in IY2025; IY2025's comes from spin-up irrigation, because `field_irrigation_window` has no IY2024 and the spin-up year falls back to the modeled season. May to September is unaffected. Affects IY totals and CU/diversion ratios. | cu.R `irrigation_window()`, fao56.R `field_cu_bucket()` | open |
| 2 | Medium | **Dashboard "other" ET relabels CU.** `cu_field_month` zeroes CU on shorted fields outside wet months and on fallow fields, then sets `other_mm = pmax(eta - et_p - cu, 0)`. Irrigated fields unchanged. Shorted: other 1,152 vs 321 AF (2025), 2,022 vs 438 AF (2026). Fallow: 618 vs 36, 689 vs 13 AF. Feeds the app's budget chart and `cu-water-sources.png`. | cu.qmd `dashboard-export`; mod_irrigation.R budget chart | open |
| 3 | Medium | **Fallow fields are irrigated inside the balance.** `irrigation_window()` restricts only shorted fields; fallow fields get their ditch window or modeled season, and their CU (582, 676 AF) is zeroed only in `cu_period()`. Their precipitation-ET and other columns come from an irrigated run. | cu.R `irrigation_window()` | open |
| 4 | Medium | **App comparisons mix coverage.** Diversion from reporting ditches only (all provisional, partial for 2026) is compared against CU on all fields; the ditch detail always uses irrigation-year CU even when May to September is selected. | mod_irrigation.R | open |
| 5 | Low | **Field window merges climatology into "records".** In the `field_window` summarise, `basis` is overwritten by the scalar field value before `p[basis %in% "records"]`, so all linked ditches' months are used. 2 field-years differ from a records-only window. | diversions.qmd `windows` | open |
| 6 | Low | **Call analysis is partial.** 524 of 528 rights cached; the 4 missing are dropped by the inner join in `priority` and can change `senior_out`. Other fetches are complete: parcelusets 243/243; divrecmonth 194/243 WDIDs, the 49 missing spread over all batches (consistent with no-data 404s, not failed batches). The log-and-skip plus `cached()` mechanism can still store partial results permanently. | diversions.R fetch functions, cache.R | open |
| 7 | Low | **One owner per parcel.** `fetch_parcel_owners()` keeps the first owner row per parcel; `normalize_owner()` drops tokens like "TR" that can merge distinct owners. 14 parcels missing, 176 withheld. | rights.R | open |
| 8 | Low | **Diversions snow-years does not deduplicate** SNOTEL history plus daily (the CU notebook does). No overlap on disk today. | diversions.qmd `snow-years` | open |
| 9 | Low | **Circular notebook dependency** (section 1). |  | confirmed |
| 10 | Low | **Cache keyed on name only.** `openet_v2_1_reference_monthly_202410_202609` lacks `nlcd`, built by an earlier `reference_et_monthly()`. No effect here (used without `pool_classes()`). |  | confirmed |
| 11 | Low | **CU period and method chosen by position and fallback** in the diversions `cu` chunk. Correct today. |  | confirmed |
| 12 | Info | **Stale timestamps only.** Diversions exports (10-24) predate `cu_field_wy` (10-29), but recomputed ditch CU differs by 0 AF (totals 31,780.5 and 30,544.6 AF). Rerun for provenance only. |  | refuted in values |
| 13 | Info | Orphan cache `cdss_waterclasses_wd38` (once the source of the code labels now hard-coded in `cdss_use_codes`; `diversions_rights.md` still cites it); unused `fetch_admin_calls()`; `irr_year()` duplicated in diversions.R and `shiny_app/R/mod_irrigation.R`; `swb_eta_run()` `share` docstring; hard-coded paths. |  | confirmed |
| 14 | Info | **Provisional inputs.** All OpenET months and all IY2025 (2,979) and IY2026 (1,182) divrec rows are provisional; IY2024 is approved. IY2026 ends Sep 30. |  | confirmed |
| 15 | Info | `et_wide()` fills: 1,116 ensemble months, 4 eeMETRIC months, 2 field-months set to ETa 0. |  | negligible |
| 16 | Info | Assertions are narrow: the 1% monthly check covers only A_daily_cul, eeMETRIC, irrigation year; the ditch-table check covers IY2025 only. |  | confirmed |
