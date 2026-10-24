# Diversions, water rights, and who benefits: Roaring Fork (HUC8 14010004)

Companion to the consumptive use (CU) work. This file holds the diversion, water rights, call, and equity investigation: data sources, methods, coverage, results, limits, and open questions. It does not repeat the CU science.

- CU definitions (CUirr, applied water, net CU, incidental use): `methods.md` sections 1 and 2.
- CU methods and results: `roaring_fork_cu.qmd`, "Method A: accounting consumptive use" (headline CU used here is `A_daily_cul`, eeMETRIC, `period = irrigation_year`) and "Method B: depletion above the native baseline".
- Field layer, crop labels, and irrigation status: `methods.md` section 7 and `roaring_fork_cu.qmd` "Study area and fields" and "Which fields were irrigated".
- Runnable analysis: `roaring_fork_diversions.qmd`. Helpers: `R/diversions.R`, `R/rights.R`. Caches: `data/` (gitignored).

Status: 2026-10-23, second pass. It includes Nick's decisions, the code review, and the hydrologist review. Diversions are summarized by DWR irrigation year (IY, November to October, labeled by the year it ends in). IY2025 and IY2026 records are provisional; IY2026 is partial.

## Questions

1. How much water was diverted to the irrigated fields, and how far can CDSS separate irrigation from other uses on mixed-use ditches?
2. How many users are responsible for irrigated use, and is water spread evenly across the basin or held by a few?

## Short answers

- **Diversions.** On the 243 structures linked to the 668 mapped fields, irrigation class diversion averaged 229,100 AF a year (IY2015 to 2024, each ditch averaged over the years it reported) and was 244,000 AF in IY2025. On matched ditches, CU is 9.6% of irrigation diversion in IY2025 (11.5% as Net CU with incidental use). Irrigation diversion overstates water applied to the mapped fields, because the irrigation class also covers lawns, subdivisions, and other land outside the layer.
- **Mixed use.** CDSS water classes resolve use at the headgate: categories reconcile to the headgate total in essentially all ditch-years. The large non-irrigation volume is pass-through fishery and recreation water on three structures (Paterson D Jacob Ext, Kelso, RFC), now reported separately. CDSS cannot split the irrigation class between mapped fields and other land under a ditch, or between farms within a ditch.
- **Users.** About 690 owners hold the agricultural acres with a known owner (Eagle County withholds owner names). Owners are concentrated: 35 owners hold half the known-owner agricultural acres, the top 10% of owners hold 66% of acres and 70% of CU, and private businesses (ranches, LLCs, trusts) hold 79% of acres.
- **Priority binds, within each source.** In dry years the junior tercile had 31% of its decreed cfs out of priority on an average day (seniors 7%), and juniors' best right was out 31 days (seniors 11). Within each source, seniority ranks call exposure closely (Spearman 0.67 to 0.96). Juniors kept diverting about the same per acre because 15% of their dry-year irrigation diversion ran under augmentation (seniors 1%). Every tercile cut late-season diversion in dry years.
- **Equity per acre.** Diversion per mapped acre is uneven across reporting ditches (acre-weighted Gini 0.54; 0.60 in IY2025). Adequacy (CU / NIWR) has a median near 1.0, with 15% of irrigated agricultural fields below 0.75 in IY2025 and 22% in IY2026.

## Nick's decisions applied

| Decision | Applied |
|---|---|
| Owner join, keyed hash, reproducible | HMAC-SHA256 of the normalized name with `OWNER_HASH_KEY`; `fetch_parcel_owners(reveal = FALSE)`; caches hold hashes only |
| Turf separate but kept | `data/field_landclass_div5_2023.parquet`; equity tables use agricultural fields; turf has its own table |
| 2020 to 2023 acreage loss | Stated as likely real dry-up (Nick's read), not verified |
| Fishery is pass-through | Fishery and recreation classes reported separately and excluded from diversion-to-field and equity totals |
| RFC Ditch | Looked up and kept in the linked set (see Pass-through water) |
| Calls | Daily call analysis for 524 of 528 rights, IY2010 to Oct 2026 |
| Ditch company records | Listed as open research |

## Data sources

| Source | Endpoint or file | Use here | Cache |
|---|---|---|---|
| CDSS irrigated lands, Div 5, 2010 to 2023 | `Div5_Irrig_<year>.shp` / `.dbf` in `div5_dir()` | Fields, `SW_WDID1..9`, comments | `field_ditch_div5_2023`, `field_ditch_acres_div5_2010_2023` |
| Land class | Layer `COMMENTS` | Agricultural vs turf (golf, park, lawn, ranchette) | `field_landclass_div5_2023` |
| CDSS parcel use | `structures/parcelusets` (per WDID) | Acreage split check, acres served outside the HUC8 | `cdss_parcelusets_2023_field_ditches` |
| CDSS monthly diversion records | `structures/divrec/divrecmonth` (batched WDID lists) | Headgate totals and water classes, Nov 2009 to Oct 2026 | `cdss_divrecmonth_field_ditches_200911_202610` |
| CDSS net amount rights | `waterrights/netamount` (`waterDistrict=38`) | Rate, admin number, uses | `cdss_netamount_wd38` |
| CDSS structures | `structures` (`waterDistrict=38`) | Type, source, contacts as classes plus curated public names | `cdss_structures_wd38` |
| CDSS call analysis | `analysisservices/callanalysisbywdid` (per right) | Daily share of each right out of priority, and the calling structure | `cdss_callanalysis_field_ditch_rights_20100101_20261022` |
| CDSS water class dictionary | `structures/divrec/waterclasses` | Code labels | `cdss_waterclasses_wd38` |
| OIT Colorado Public Parcels | `gis.colorado.gov/.../Colorado_Public_Parcels/MapServer/0` | Parcels under fields; owners hashed | `field_parcel_overlay_oit2026_div5_2023`, `oit_parcel_owners_hashed_huc14010004_2026` |
| Field CU | `data/cu_field_wy.parquet` | `A_daily_cul`, eeMETRIC, irrigation year; `niwr_mm` | (CU notebook) |
| SNOTEL | `../../data/snotel_history`, `snotel_daily` | April 1 SWE, Roaring Fork sites | (repo) |

Outputs written for the CU notebook: `data/field_irrigation_window.parquet` (field_id, iy, first_month, last_month, basis) and `data/ditch_month_irrigation.parquet` (wdid, month_start, irr_af, 2023-10 to 2026-10; rows only for months the ditch reported, so a missing row means no record).

The repo's `scripts/fetch_*.R` read the API key from a repo-root path when sourced, so they cannot be sourced from `docs/Irrigation`. `R/diversions.R` has a paged `cdss_get()` with the same conventions: WDIDs as 7-character strings, 404 = empty, rate limiting, and `tryCatch` per request or batch.

## Methods

### Fields to ditches

- `read_field_ditches()` takes `read_fields()` output (same HUC8 rule and acres) and adds `SW_WDID1..9`, `MASTER_ID`, and `COMMENTS` from the layer's `.dbf`. 597 fields have one ditch, 59 have two, 12 have three or four. No field lists a groundwater structure.
- **Split rule:** a field's acres are divided equally among its ditches. This is the CDSS rule (`acresProrated`). CDSS parcel use acres per ditch match the shapefile split (r = 0.996; 95% of ditches within half an acre). The database's 2023 parcel IDs differ from the shapefile's `PARCEL_ID`.
- **Allocation:** ditch quantities go to fields by each field's share of `serve_acres = max(mapped acres, CDSS parcel use acres)`. Twelve ditches also serve land outside the HUC8 (1,796 CDSS acres against 1,414 mapped inside), so in-HUC fields are not credited with water used outside.

### Diversions

- **Irrigation year:** November to October (`irrigation_year()`), the DWR record year.
- **Headgate total** (`divrec_total()`): sum of the "Total (Diversion)" rows per structure and month. A structure with several accounts has one row per account, and the repo's `monthly_total()` keeps only one. Fallbacks are the administrative total `S:X U:Q T:0`, then the sum of the non-administrative classes.
- **Use split** (`divrec_by_use()`): every diversion class gets one category.
  - All T:0 administrative rows are dropped.
  - Same-structure account transfers (e.g. `F:3800925.001` at 3800925) re-account water already counted and are dropped.
  - Release types T:6/7/8/E/L/Q are "Released to stream".
  - `U:Q` with `To:` is "Carried to another structure"; other `U:Q` is "Quantity only". On ditches whose other classes are at least 99% irrigation, quantity-only water is assigned to irrigation (307 ditch-months, 2,537 AF over the record).
  - **Carried in** (dropped before summing across ditches): carrier rows (T:3), and blank-type `F:` rows whose source is a linked ditch (Kelso carrying Paterson's water).
  - **Kept:** exchanges (T:1), alternate points (T:4), augmented diversions (T:A), and storage re-diversions (S:2). They are water taken at this headgate and have no matching row at the source.
- **Pass-through:** fishery and recreation classes (`pass_through_uses`).
- **Per-ditch means:** each ditch is averaged over the irrigation years it reported (`ditch_mean_af()`). A ditch with no records is NA, not zero, and is left out of diversion statistics.
- **Use mix** per ditch from IY2015 to 2025: irrigation only (≥ 99% irrigation class), mostly irrigation (≥ 50%), mostly other use, no irrigation class.

### Rights and calls

- Net amount rights at the linked WDIDs, all in cfs. A right is irrigation when its decreed uses include 1 or X (`is_irrigation_use()`, one rule throughout).
- Seniority is the cfs-weighted mean admin number (`wmean_admin`). Terciles are cut on mapped acres.
- **Call analysis:** for every absolute right, the daily out-of-priority share and the calling structure, April to October.
  - Per ditch-day: the cfs-weighted share of its rights out of priority, and whether its most senior right was out.
  - Per ditch-year: the mean share and the count of days.
- **Sources:** each ditch's CDSS water source is grouped as Roaring Fork mainstem, Crystal, Fryingpan, Snowmass, Capitol, Cattle, Fourmile, or other tributaries.
- **Dry and wet years:** the lowest and highest April 1 SWE (mean of the seven Roaring Fork SNOTEL sites with a full record), 2010 to 2025.
  - Dry: 2012, 2015, 2013. Wet: 2011, 2023, 2019.
  - April 1, 2026 SWE (128 mm) was the lowest since 2010 (median 415 mm), but IY2026 diversions are partial.

### Owners

1. Parcels under the fields come from the OIT composite (overlay by area share). The `owner` field is fetched only inside `fetch_parcel_owners()`.
2. **Classing:** the raw name is classed first (`classify_contact()`). Private markers (LLC, INC, TRUST, HOLDINGS, HOA) are tested before public ones.
3. **Normalizing:** upper case, `&` to AND, punctuation removed, and LLC, INC, TRUST, TRUSTEE, REVOCABLE, LIVING, ET AL, JT TEN, and a leading THE dropped.
4. **Hashing:** HMAC-SHA256 with `OWNER_HASH_KEY`, keeping the first 16 hex characters (`O...`).
5. **What is stored:** caches keep `parcel_id`, `county`, `owner_id`, `owner_class`, and `owner_public`. `owner_public` is a curated label for public entities (`public_entity_names`) or a ditch company name, and NA otherwise.
6. **Placeholders:** placeholder owners are class "withheld" with no ID. Eagle County submits "EAGLE COUNTY PROPERTY OWNER" for every parcel.

**Rerun to reveal** (in memory only, never cached):

```r
for (f in list.files("R", full.names = TRUE)) source(f)
ov <- arrow::read_parquet("data/field_parcel_overlay_oit2026_div5_2023.parquet")
fields <- read_fields(read_huc8())
bb <- as.numeric(sf::st_bbox(sf::st_transform(sf::st_buffer(sf::st_union(fields), 500), 4326)))
who <- fetch_parcel_owners(bb, dplyr::distinct(ov, parcel_id, county), reveal = TRUE)
dplyr::filter(who, owner_id == "O...")   # the normalized name for a hashed ID
```

The same key gives the same IDs. If the key changes, every ID changes and the cache must be rebuilt. If `OWNER_HASH_KEY` is missing, the function stops with instructions. Parcel ownership changes between annual OIT submissions, so a reveal against a later submission can differ.

### Equity

- **Levels:** field, field block (fields within 10 m, `field_blocks()`), tax parcel, owner, ditch. Agricultural fields only; turf is summarized separately.
- **Quantities:** acres, CU (IY2025, IY2026), irrigation class diversion (IY2015 to 2024 per-ditch mean), absolute decreed cfs. Diversion statistics count only holders whose fields all sit on reporting ditches, and n is reported.
- **Metrics:** Gini, Lorenz curve, share held by the top 10% and top 10, and the number of holders with half. The result depends on the "water use agent" (Cullis & van Koppen, 2007), so each level is reported.
- **Per-acre:** Gini with acres as the population (`gini_per_acre()`), following the equal-depth definition of canal equity (Anwar & Ul Haq, 2013; Shah et al., 2016).
- **Adequacy:** CU / NIWR per irrigated field. This adapts the Molden and Gates (1990) adequacy measure, with CU in place of delivered water.

## Coverage

| Item | Value |
|---|---|
| Fields / acres | 668 / 19,722 (616 agricultural, 18,622 acres; 52 turf, 1,099 acres) |
| Linked structures | 243 (221 active ditches, plus pumps, springs, wells, pipelines, 1 reservoir) |
| Structures with any record IY2010 to 2026 | 194; the other 49 serve 2,352 mapped acres |
| Ditches reporting per year | 132 to 168 (IY2010 to 2024); 148 in IY2025; 112 in IY2026 |
| Mapped acres on reporting ditches | about 14,400 to 15,900 (IY2010 to 2025) |
| IY2026 | Provisional and partial: June to September has 75 to 98 ditches reporting vs 112 to 149 in 2024 to 2025. Rerun with a new cache name or `refresh = TRUE` in early 2027 |
| Call analysis | 524 of 528 absolute rights (4 returned HTTP 400, likely admin numbers with more than five decimals) |
| Owners | 1,113 of 1,303 parcels have a usable owner (89% of overlay acres); Eagle County's 176 parcels (2,008 acres) are withheld |

## Results

### Diversions by use (headgate, linked structures, carried water removed)

| Use (water class) | IY2015 to 2024 mean | IY2025 | IY2026 (partial) |
|---|---|---|---|
| Irrigation | 229,100 (71%) | 244,000 (69%) | 165,600 |
| Fishery (pass-through) | 65,700 (20%) | 92,200 (26%) | not yet entered |
| Released to stream | 10,700 (3%) | 11,600 (3%) | 0 |
| Quantity only (mixed ditches) | 8,600 (3%) | 0 | 0 |
| Recreation (pass-through) | 4,200 (1%) | 1,800 (1%) | 2,400 |
| Carried to another structure | 3,400 (1%) | 3,100 (1%) | 0 |
| Stock, power, domestic, recharge | about 1,300 | about 1,700 | 800 |

AF per year (share).

### Pass-through water

| Structure | Use | Mapped acres | IY2015 to 2024 mean (AF/yr) | IY2025 (AF) |
|---|---|---|---|---|
| Paterson D Jacob Ext | Fishery | 50 | 64,377 | 92,224 |
| Kelso Ditch (carried from Paterson) | Fishery | 54 | 6,618 | 0 |
| RFC Ditch | Recreation | 59 | 4,140 | 1,849 |
| Kelso Ditch (own) | Fishery | 54 | 1,294 | 0 |

**Paterson D Jacob Ext.** Its one right is 63 cfs (1966), decreed for commercial, recreation, fishery, domestic, and other uses, with no irrigation. Its water goes back to the river (Nick).

**RFC Ditch (3801541).** This is the headgate of a private club's water system on the Roaring Fork at stream mile 27.5 (Pitkin County, records since 2004). The system has eight RFC ponds, seven wells, a pump and pipeline, an augmentation plan, and an exchange (cases 95CW0356, 97CW0053, 05CW0139, 07CW0054, 16CW3136).
- Its own diversions are recreation class.
- Its 1885 to 1904 irrigation rights now show zero net absolute, consistent with a change of use. The active right is a 1995 junior 19.9 cfs for storage, irrigation, recreation, and fishery.
- Its two golf course polygons (58.6 acres) get irrigation water through alternate-point classes from Grace and Shehi Ditch and Red Rock Bluff Ditch.

**Decision:** keep RFC Ditch in the linked set, because it serves mapped turf, and count its recreation water as pass-through. Its irrigation is counted at the alternate-point classes.

### Use mix (IY2015 to 2025, per-ditch mean over reported years)

| Use mix | Ditches | Mapped acres | Diversion (AF/yr) | Irrigation class (AF/yr) |
|---|---|---|---|---|
| Irrigation only | 138 | 12,069 | 160,936 | 160,811 |
| Mostly irrigation | 37 | 3,992 | 92,037 | 80,399 |
| No records IY2015 to 2025 | 59 | 2,799 | n/a | n/a |
| Mostly other use | 5 | 604 | 10,425 | 2,566 |
| No irrigation class | 4 | 258 | 76,422 | 0 |

Most "mostly irrigation" ditches are mixed only because part of the diversion is released back to the river under an augmentation or exchange account.

### Fifteen largest irrigation diverters (IY2015 to 2024, mean over reported years; water allocated to in-HUC fields)

| Ditch | Mapped acres | Irr. diversion (AF/yr) | AF per mapped acre | Absolute cfs | cfs-weighted admin no. | CU IY2025 (AF) | Use mix |
|---|---|---|---|---|---|---|---|
| Home Supply Ditch | 961 | 18,560 | 19.3 | 59.0 | 24,740 | 1,895 | irrigation only |
| Sweet Jessup Canal | 1,284 | 14,171 | 11.0 | 75.0 | 24,269 | 2,577 | irrigation only |
| Robinson Ditch | 148 | 10,465 | 70.9 | 49.3 | 27,479 | 263 | mostly irrigation |
| Basin Ditch | 218 | 9,856 | 45.3 | 45.0 | 26,118 | 358 | irrigation only |
| Lowline Ditch | 327 | 9,567 | 29.3 | 40.5 | 25,486 | 818 | irrigation only |
| East Mesa Ditch | 516 | 9,499 | 18.4 | 41.8 | 23,400 | 1,210 | irrigation only |
| Glenwood Ditch | 167 | 9,129 | 54.8 | 45.9 | 25,060 | 380 | mostly irrigation |
| Slough D and Banning Lat | 242 | 7,274 | 30.1 | 49.3 | 30,898 | 609 | irrigation only |
| Rockford Ditch | 127 | 5,598 | 44.0 | 35.2 | 25,613 | 271 | irrigation only |
| Salvation Ditch | 336 | 5,355 | 15.9 | 59.0 | 20,568 | 280 | mostly irrigation |
| Harris & Reed Ditch | 54 | 4,749 | 88.0 | 23.6 | 24,051 | 112 | mostly irrigation |
| Grace and Shehi Ditch | 69 | 4,217 | 61.5 | 23.7 | 27,437 | 136 | mostly irrigation |
| Kester Ditch | 127 | 4,166 | 32.7 | 22.5 | 32,517 | 270 | mostly irrigation |
| Ella Ditch | 202 | 4,028 | 19.9 | 14.3 | 25,665 | 545 | irrigation only |
| Robertson Ditch | 212 | 3,785 | 17.9 | 26.7 | 34,206 | 461 | mostly irrigation |

### CU against diversion (matched ditches)

Matched ditches are those with a record that year and at least 5 mapped acres, all of whose fields are served only by reporting ditches.

| IY | Ditches | Mapped acres | Irr. diversion (AF) | CU (AF) | CU / diversion | Net CU / diversion | Ditch median CU / diversion |
|---|---|---|---|---|---|---|---|
| 2025 | 116 | 12,934 | 213,300 | 20,562 | 9.6% | 11.5% | 12.4% |
| 2026 (partial) | 69 | 7,688 | 141,557 | 14,995 | 10.6% | 12.6% | 12.6% |

**Why the ratio is low.** It is not irrigation efficiency.
- Most diverted water returns to the river and is diverted again downstream. Lagged groundwater returns from flood-irrigated meadows support late-season baseflow.
- Some Glenwood-area returns reach the Colorado River below the HUC8 outlet.
- The irrigation class also serves land outside the field layer.
- Incidental losses sit on the diversion side.
- The 2023 layer maps about 5,800 fewer acres than 2020. Nick's read is real dry-up; not yet verified.

**Comparisons.**
- On the eight largest Crystal River ditches, Aspen Journalism's OpenET eeMETRIC estimate put crop consumption at under 1% to about 30% of diversion (Sackett & Lassalle, 2024).
- No StateCU District 38 system efficiency figure was found. A 1951 to 1983 CWCB table lists about 45% efficiency for District 38, but the OCR is unreliable and it is not used here.

### Concentration across holders (agricultural fields)

| Level | Quantity | Holders | Gini | Top 10% hold | Top 10 hold | Holders with half |
|---|---|---|---|---|---|---|
| Field | Acres | 616 | 0.54 | 39% | 12% | 97 |
| Field | CU IY2025 | 616 | 0.60 | 43% | 13% | 81 |
| Field | Irrigation diversion | 520 | 0.62 | 45% | 17% | 63 |
| Field | Decreed cfs | 616 | 0.61 | 46% | 16% | 74 |
| Field block | Acres | 374 | 0.67 | 54% | 29% | 32 |
| Field block | CU IY2025 | 374 | 0.73 | 60% | 33% | 25 |
| Field block | Irrigation diversion | 309 | 0.71 | 57% | 33% | 23 |
| Tax parcel | Acres | 1,087 | 0.74 | 60% | 21% | 69 |
| Tax parcel | CU IY2025 | 1,087 | 0.77 | 63% | 21% | 60 |
| **Owner** | **Acres** | **689** | **0.77** | **66%** | **28%** | **35** |
| **Owner** | **CU IY2025** | **689** | **0.80** | **70%** | **30%** | **30** |
| Owner | Irrigation diversion | 583 | 0.76 | 65% | 28% | 31 |
| Owner | Decreed cfs | 689 | 0.78 | 67% | 28% | 33 |
| Ditch | Acres | 240 | 0.66 | 51% | 33% | 23 |
| Ditch | CU IY2025 | 240 | 0.71 | 55% | 36% | 20 |
| Ditch | Irrigation diversion | 181 | 0.73 | 61% | 46% | 13 |
| Ditch | Decreed cfs | 240 | 0.66 | 51% | 28% | 24 |

- **Excluded from the owner level:** Eagle County fields (owners withheld). Holders without a diversion value (96 fields, 65 blocks, 168 parcels, 106 owners, 59 ditches) have at least one field on a ditch with no records.
- **Largest owner:** a private business with 1,291 agricultural acres (7.8% of known-owner acres, 9.6% of CU).
- **By owner class:**

| Owner class | Owners | Ag acres | Share of acres | Share of CU |
|---|---|---|---|---|
| Private business | 379 | 13,197 | 79% | 78% |
| Individual | 294 | 3,061 | 18% | 20% |
| Public entity | 17 | 393 | 2% | 3% |

Public owners among them are Pitkin County (197 acres), City of Aspen, Town of Carbondale, Town of Basalt, Town of Snowmass Village, the federal government, the State of Colorado, Colorado Parks and Wildlife, and Roaring Fork School District RE-1.

**Comparison.** The owner-level Gini (0.77 for acres, 0.80 for CU) is lower than the Olifants registered irrigation users (0.81) and Chile's surface consumptive rights (0.95) (Cullis & van Koppen, 2007; Correa-Parra et al., 2020). It counts only landowners with irrigated land, not households without water, so it is not comparable to Olifants' 0.96 for all rural users. Consumption follows land: the CU Gini runs 0.03 to 0.06 above the acres Gini at every level.

### Turf

| Land class | Fields | Acres | CU IY2025 (AF) | CU IY2026 (AF) | Irr. diversion (AF/yr) | CU AF/ac IY2025 |
|---|---|---|---|---|---|---|
| Agricultural | 616 | 18,622 | 29,863 | 28,608 | 205,130 | 1.60 |
| Turf: golf | 47 | 920 | 1,726 | 1,812 | 22,707 | 1.88 |
| Turf: park | 1 | 32 | 65 | 54 | 2,302 | 1.99 |
| Turf: ranchette | 3 | 143 | 120 | 64 | 734 | 0.84 |
| Turf: lawn | 1 | 4 | 6 | 7 | 76 | 1.46 |

Irrigation diversion here sums the fields on reporting ditches. Golf courses consume more per acre than hay land and take about 10% of the allocated irrigation diversion on 5% of the acres.

### Diversion per mapped acre and adequacy

| Quantity | Ditches | Gini across mapped acres |
|---|---|---|
| Decreed cfs per mapped acre | 227 | 0.51 |
| Irrigation diversion per mapped acre, IY2015 to 2024 | 184 | 0.54 |
| Irrigation diversion per mapped acre, IY2025 | 148 | 0.60 |

**Diversion per acre** is uneven across ditches, but CDSS cannot say how much of that is water spread over unmapped land.

**Adequacy (CU / NIWR), irrigated fields:**

| IY | Land class | Fields | 10th pct | Median | 90th pct | Share below 0.75 |
|---|---|---|---|---|---|---|
| 2025 | Agricultural | 541 | 0.69 | 1.07 | 1.44 | 15% |
| 2025 | Turf | 50 | 0.69 | 1.07 | 1.36 | 16% |
| 2026 | Agricultural | 497 | 0.60 | 1.02 | 1.38 | 22% |
| 2026 | Turf | 49 | 0.33 | 0.87 | 1.25 | 39% |

- A median above 1 means eeMETRIC ETa often exceeds the Kc-based requirement on these meadows. This is consistent with the CU notebook's Kc cross-check and with shallow groundwater, so read adequacy as relative, not absolute.
- The low tail grew in IY2026, the lowest snow year since 2010.
- Mapping adequacy spatially, by ditch, and by tercile is the next step (open question 4).

### Priority and calls

**Calling structures** (April to October, IY2010 to Oct 2026; days with at least one linked right out of priority):

| Caller | Rights called out | Ditches | Days |
|---|---|---|---|
| Four Mile Ditch | 29 | 8 | 1,663 |
| C and M Ditch | 14 | 7 | 1,363 |
| Mason Ditch | 28 | 21 | 1,352 |
| Walthen Ditch | 26 | 11 | 1,073 |
| Colorado mainstem (Cameo / Grand Valley) | 307 | 174 | 964 |
| Hatch, Cramer, H C and L, Needham, Atkinson, and others | | | fewer |
| Ruedi Reservoir, Crystal and Hunter Creek minimum flows | | | fewer |

Local tributary calls are frequent. The Cameo call reaches the most rights, but only the juniors.

**By priority tercile** (cfs-weighted admin number; acre-weighted means over the three dry or wet years):

| Tercile | Ditches | Acres | cfs per 100 ac | Senior right days out, dry / wet | Share of cfs out, dry / wet | Jul-Sep / May-Jun diversion, dry / wet | Augmented share of irrigation, dry / wet |
|---|---|---|---|---|---|---|---|
| Senior | 74 | 6,239 | 6.0 | 10.6 / 1.0 | 0.07 / 0.01 | 1.34 / 2.11 | 0.01 / 0.00 |
| Middle | 29 | 6,148 | 9.3 | 16.7 / 6.8 | 0.20 / 0.05 | 1.46 / 2.26 | 0.07 / 0.01 |
| Junior | 121 | 6,790 | 19.0 | 30.9 / 9.0 | 0.31 / 0.08 | 1.42 / 1.97 | 0.15 / 0.01 |

**By source:**

| Source | Ditches | Acres | Senior right days out, dry / wet | Share of cfs out, dry / wet | Jul-Sep / May-Jun, dry / wet | Augmented share, dry / wet | Spearman, admin no. vs share out (dry) |
|---|---|---|---|---|---|---|---|
| Other tributaries | 122 | 7,286 | 21.4 / 3.8 | 0.17 / 0.03 | 1.39 / 2.03 | 0.10 / 0.01 | 0.67 |
| Roaring Fork mainstem | 35 | 3,653 | 13.5 / 1.5 | 0.17 / 0.03 | 1.58 / 2.41 | 0.12 / 0.01 | 0.91 |
| Crystal River | 17 | 2,982 | 0.7 / 0.1 | 0.12 / 0.03 | 1.42 / 2.37 | 0.05 / 0.01 | 0.96 |
| Cattle Creek | 15 | 1,750 | 56.0 / 27.0 | 0.41 / 0.16 | 0.43 / 0.92 | 0.00 / 0.00 | 0.68 |
| Snowmass Creek | 13 | 1,275 | 7.6 / 0.5 | 0.19 / 0.04 | 2.38 / 2.75 | 0.11 / 0.02 | 0.95 |
| Capitol Creek | 10 | 1,265 | 7.9 / 0.4 | 0.07 / 0.01 | 1.64 / 3.78 | 0.08 / 0.00 | 0.75 |
| Fourmile Creek | 8 | 898 | 55.0 / 28.7 | 0.48 / 0.19 | 0.50 / 0.53 | 0.00 / 0.00 | 0.74 |
| Fryingpan River | 4 | 68 | 51.8 / 11.9 | 0.26 / 0.05 | 3.16 / 2.38 | 0.40 / 0.07 | n < 5 |

**Reading.** Priority binds. Junior ditches are out of priority far more, and within every source seniority orders call exposure.
- **Why juniors still divert:** in dry years they divert under augmentation (Ruedi, Basalt Water Conservancy District, West Divide contracts and plans).
- **Short sources:** on Cattle and Fourmile Creeks, where no augmentation is recorded, even senior rights are out for weeks and late-season diversion falls below early-season.
- **Shortage is shared:** all terciles roughly halve their Jul-Sep to May-Jun ratio in dry years. That is supply shortage on top of administration.
- **Per acre, juniors hold more:** juniors have about three times the decreed cfs per acre of seniors, mostly junior enlargements that are out of priority when water is short.

### Users and ownership

**CDSS has no ownership.**
- `associatedContacts` lists contacts, not holders, and `waterrights/netamount` has no holder field.
- Contacts are reduced to classes: of 243 linked structures, 110 list only individuals, 62 list individuals plus private businesses, and 47 list only private businesses. Nine list a ditch company, and 14 a public entity.
- Public names come only from a curated list or a ditch company pattern. Named contacts:
  - Public entities: City of Aspen, Town of Carbondale, Pitkin County, Basalt Water Conservancy District, Colorado Parks and Wildlife, Aspen School District RE-1.
  - Ditch companies: Ella, Glenwood Irrigation, Last Chance, Monarch, Needham, Park, Robinson, Salvation.
- Most decreed rights on a company ditch are held by the company, and shareholders own them pro rata (Magnuson & Smith, 2010).

**Field layer:** `FARM_UNIT` is empty in every Div 5 layer from 2010 to 2023. `MASTER_ID` tracks a field across years, not a farm.

**Assessor owners:**
- Owners come from the hashed join above.
- Eagle County withholds owner names in its OIT submission ("EAGLE COUNTY PROPERTY OWNER" on 24,615 of 25,064 parcels; the rest are blank). An earlier note that 98% of Eagle parcels had owners was wrong.
- Pitkin's labels put 5,836 field acres on agricultural parcels and 2,169 on residential parcels. Garfield and most of Eagle use coded classes that need a county crosswalk.

## How far the mixed-use problem goes

| Question | Solvable with CDSS? | Notes |
|---|---|---|
| How much each ditch diverted, by month | Yes | 194 of 243 structures; IY2026 partial until early 2027 |
| Irrigation vs fishery, recreation, stock, export at the headgate | Yes | Water class `U` codes; categories reconcile to the total |
| Water diverted then released under augmentation or exchange | Yes | Release accounts (T:7 and others) |
| Water diverted under augmentation while out of priority | Yes | T:A classes; 15% of junior dry-year irrigation |
| Double counting where one ditch carries another's water | Yes | `F:`, `To:`, and T:3 codes |
| Irrigation water to mapped fields vs lawns, subdivisions, ponds under the same ditch | No | One irrigation class; needs ditch company or municipal raw-water records or a better irrigated-land map |
| Water per farm or shareholder within a ditch | No | Needs company share registers; shares per acre vary between farms (Magnuson & Smith, 2010) |
| Return flow and reuse downstream | No | Needs a return-flow model |
| Who owns the land | Mostly | Hashed owners for Pitkin, Garfield, Gunnison; Eagle withheld |
| Who owns the water | Partly | Rights are on structures; shareholders and contract water are not in the API |

## Limitations

- **Unmapped irrigated land.** Irrigation class diversion also serves land outside the 2023 layer, which biases diversion per acre high and CU / diversion low, by unknown amounts per ditch.
- **Equal split.** Multi-ditch fields (71 fields, 2,736 acres) get an equal share from each ditch, as CDSS does.
- **Field blocks are not farms,** and owners are assessor names. One operator can lease land from many owners, and one family can own through several entities that normalization does not merge.
- **Eagle County owners withheld** (2,008 field acres), so the owner level covers 89% of overlay acres.
- **Provisional records.** IY2025 is provisional and IY2026 partial.
- **Call analysis** covers absolute rights at the linked structures. It does not cover augmentation plan coverage or contract water, which show up only through T:A diversions.
- **Adequacy** uses CU, not delivered water, and NIWR from a Kc curve that eeMETRIC often exceeds on these meadows.
- **Literature comparisons** use owners or registered users as the unit and include non-irrigators in some cases.

## Open questions for Nick

1. **Owner key.** Add `OWNER_HASH_KEY` to `~/.Renviron` (the coordinator has the suggested key). The cached hashes were built with that key, so changing it means rebuilding `oit_parcel_owners_hashed_huc14010004_2026`.
2. **Eagle County owners.** These are withheld in the OIT layer. Should we request the Eagle assessor's export, or report the owner level without Eagle?
3. **Multi-entity owners.** Should owners that share a mailing address be merged? That needs the owner address fields, hashed the same way.
4. **Adequacy next step.** Map CU / NIWR by field and summarize by ditch and tercile, now that NIWR is in the CU export.
5. **Augmentation.** Pull the augmentation plan structures (`G:` WDIDs on T:A classes, e.g. 3604900) to name the plans and contract sources behind junior diversions.
6. **Ditch company records** (open research, not now): share registers and delivery records from Home Supply, Sweet Jessup, Salvation, Robinson, and Glenwood are the only route to within-ditch equity.

## References

Anwar, A. A., & Ul Haq, Z. (2013). An old-new measure of canal water inequity. *Water International, 38*(5), 536–551. https://doi.org/10.1080/02508060.2013.832124 *(abstract only)*

Correa-Parra, J., Vergara-Perucich, J. F., & Aguirre-Nuñez, C. (2020). Water privatization and inequality: Gini coefficient for water resources in Chile. *Water, 12*(12), Article 3369. https://doi.org/10.3390/w12123369 *(abstract and reported results only)*

Cullis, J., & van Koppen, B. (2007). *Applying the Gini coefficient to measure inequality of water use in the Olifants River water management area, South Africa* (IWMI Research Report 113). International Water Management Institute. https://doi.org/10.3910/2009.113

Leonard, B., & Libecap, G. D. (2019). Collective action by contract: Prior appropriation and the development of irrigation in the western United States. *The Journal of Law and Economics, 62*(1), 67–115. https://doi.org/10.1086/700934 *(abstract only)*

Magnuson, D. O., & Smith, S. W. (2010). The case for ditch-wide water rights analysis in Colorado. In *Meeting irrigation demands in a water-challenged environment* (pp. 145–151). U.S. Committee on Irrigation and Drainage. https://mountainscholar.org/handle/10217/210900

Molden, D. J., & Gates, T. K. (1990). Performance measures for evaluation of irrigation-water-delivery systems. *Journal of Irrigation and Drainage Engineering, 116*(6), 804–823. https://doi.org/10.1061/(ASCE)0733-9437(1990)116:6(804) *(abstract only)*

Sackett, H., & Lassalle, L. (2024, March 10; updated 2026, January 6). Crystal River mapping project. *Aspen Journalism*. https://aspenjournalism.org/?p=868034

Shah, M. A. A., Anwar, A. A., Bell, A. R., & ul Haq, Z. (2016). Equity in a tertiary canal of the Indus Basin Irrigation System (IBIS). *Agricultural Water Management, 178*, 201–214. https://doi.org/10.1016/j.agwat.2016.09.018 *(abstract only)*
