# Irrigation consumptive use: methods and literature

Reference for agents and authors working on the irrigation module. Goals live in `Irrigation_usage_module.md`; current project state lives in `CLAUDE.md` in this folder. This file holds the scientific context, method options, and citations (APA 7). Sources marked *(abstract/summary only)* were not read in full; check them before quoting numbers.

## 1. Definitions

The literature uses these terms consistently; the module should too.

- **ETa**: actual evapotranspiration from all water sources (precipitation, irrigation, soil storage, shallow groundwater).
- **ETo / ETr**: grass / alfalfa reference ET from the ASCE Standardized Penman-Monteith equation (ASCE-EWRI, 2005).
- **ETc**: potential crop ET under no water stress, `Kc × ETo` (Allen et al., 1998).
- **Effective precipitation (Pe, Prz)**: the part of precipitation that stays in the root zone and is available for ET. Gross precipitation minus surface runoff and deep percolation (Reclamation, 2025).
- **Irrigation consumptive use (CUirr)**: the part of ETa supplied by irrigation water. `CUirr = ETa − Pe` (Huntington et al., 2025; Reclamation, 2025).
- **Net irrigation water requirement (NIWR)**: `ETc − Pe`; what a crop would need from irrigation with full supply. An upper bound on CUirr. Water-short fields fall below it.
- **Net CU**: CUirr plus incidental use (canal evaporation, phreatophytes along ditches), scaled by HUC8 percentages in Reclamation reporting (Reclamation, 2025).
- **Applied water / diversion**: CUirr divided by irrigation efficiency. Not the same as CU; most diverted water returns to the stream. Remote sensing measures consumption, not diversion (WestCAT, n.d.; OWRD, 2025).

## 2. Current standard practice in the Upper Colorado

**Reclamation Consumptive Uses and Losses (CU&L).** The August 2025 methods manual moved Upper Colorado irrigated agriculture from SCS modified Blaney-Criddle to remote sensing for 1991 onward (Reclamation, 2025). This is the closest precedent for our module and the number our results will be compared with:

1. ETa from OpenET **eeMETRIC** (not the ensemble), 30 m, aggregated to fields (Allen et al., 2007; Kilic et al., 2021).
2. Pe (Prz) from the **ET Demands** daily soil water balance (FAO-56 dual crop coefficient) run at each 4 km gridMET cell with bias-corrected reference ET (Allen et al., 2005, 2020; Allen & Robison, 2009).
3. `CUirr = ETa − Prz` per field per month. If monthly Prz exceeds ETa, the remainder carries forward to the next month as stored soil moisture. Water year runs Nov to Oct in their accounting.
4. Field boundaries from state datasets (Colorado: CDSS irrigated lands), with yearly irrigation status from NDVI or EToF. Colorado rule for pre-2016: a pixel is irrigated if monthly EToF > 0.4 in three or more months May to October; 2016 onward uses Harmonized Landsat Sentinel NDVI with classes fallow, shorted, irrigated, and wet soil (wet soil = NDVI-fallow but growing-season EToF > 0.5, common on flood-irrigated meadows).
5. Net CU adds HUC8 incidental use percentages from the 1971 Comprehensive Framework Study.

Full methods: Pearson et al. (2024) *(abstract/summary only)*. The CUWG Phase III report recommended this design and flagged winter Pe as an open problem, since adjacent studies suggest much winter precipitation does not end up in root zone storage (Upper Colorado CUWG, 2022) *(abstract/summary only)*.

**Colorado StateCU.** The state's consumptive use model (CDSS) uses SCS modified Blaney-Criddle as its featured monthly method, with Penman-Monteith and Hargreaves as daily options, and SCS (TR-21) effective precipitation (Colorado Water Conservation Board [CWCB], n.d.). Historic CU datasets exist for the Upper Colorado basin (2015 input files). StateCU gives a potential, supply-limited CU, not observed ETa, so it is a comparison point, not a method to copy. Older CRDSS memos note Blaney-Criddle was chosen because of weather data limits, and that it can differ a lot from Penman-Monteith.

## 3. Remote sensing ETa: OpenET

- OpenET combines six Landsat-based models (ALEXI/DisALEXI, eeMETRIC, geeSEBAL, PT-JPL, SIMS, SSEBop) into an ensemble mean after median absolute deviation outlier removal, 30 m, monthly and daily (Melton et al., 2022).
- Accuracy: against 152 flux stations, cropland ensemble MAE was about 15.8 mm/month (17% of mean), bias about −5.3 mm/month, r² about 0.9. Seasonal and annual errors averaged 10 to 20%. Shrublands and forests showed more model disagreement and lower accuracy (Volk et al., 2024).
- Oregon's statewide project put uncertainty at 10 to 20% for monthly ET and 10 to 30% for CUirr, larger for single fields than aggregates, larger for natural vegetation, with a possible upward ET bias on dry non-irrigated rangeland (OWRD, 2025; Huntington et al., 2025).
- Access: OpenET API (`openet-api.org`, polygon time series, key required; old repo `Ag_waterefficiency/OpenEtAPI.R` has a working client) and Earth Engine collections such as `projects/openet/assets/ensemble/conus/gridmet/monthly/v2_1` (band `et_ensemble_mad`, mm/month; per-model collections exist, e.g. eeMETRIC, SSEBop, geeSEBAL). Check catalog date coverage before use.
- Component model references: eeMETRIC/METRIC (Allen et al., 2007, 2013; Morton et al., 2013; Kilic et al., 2021); SSEBop (Senay et al., 2013).

## 4. Mountain hay meadows (the Roaring Fork context)

Western Slope irrigated land is mostly high-elevation grass hay and pasture, often wild-flooded, and less studied than lowland crops (Cabot et al., 2022).

- Kremmling paired-site study (2,200 m+, 70 frost-free days): May to September eeMETRIC ETa averaged 601 mm over 2016 to 2019; the OpenET ensemble gave 635 mm for the same fields. Weather-based ETp estimates were 695 mm (DWR mountain meadow Kc), 764 mm (ASCE-PM at CoAgMet), and 708 mm (Carlson et al. 1991 lysimeter). Of six models, eeMETRIC agreed best with an on-site eddy covariance tower (slope 1.00, R² 0.78, n = 50). Full irrigation withdrawal cut May to September ETa about 53 to 58%; partial-season withdrawal after June 15 cut it about 15% in the withdrawal year and 16% the next (Cabot et al., 2022). eeMETRIC ETa minus StateCU TR-21 effective precipitation averaged 516 mm on the reference sites over 2016 to 2022. Withdrawn fields recovered toward pre-withdrawal ETa within one to two years, partly through ditch seepage and groundwater.
- Lessons for us: (1) model choice changes seasonal ETa by about 5%; (2) weather-based potential ET overstates actual use on these meadows, so using ETc as "consumptive use" inflates it; (3) the choice of reference condition strongly affects how much use is attributed to irrigation; (4) edges, ponds, ditch seepage, and river proximity show up clearly in 30 m ETa, so field means need edge handling; (5) May to September is the defensible season because winter ET is poorly constrained.
- Flood irrigation runs early with high streamflow and stops around August 1 for haying, which raises valley water tables. Later-season ET is partly fed by that stored water and shallow groundwater.
- Pochop et al. (1984) showed Blaney-Criddle needs altitude corrections in Colorado mountain valleys (cited in Cabot et al., 2022).

## 5. Removing the precipitation and natural contribution

This is the main design choice. Three families exist.

**A. Soil water balance Pe (Reclamation/DRI standard).** Daily FAO-56 water balance per gridMET cell gives root-zone Pe with runoff and deep percolation removed and winter carryover. Physically based and matches CU&L. Weak points: winter Pe and snowmelt infiltration in the mountains, and sensitivity to soil water holding capacity and rooting depth (Allen et al., 1998, 2005, 2020; Reclamation, 2025). ET Demands is open source Python (Open-ET GitHub organization).

**B. Empirical Pe (SCS TR-21, USBR, FAO, ratio methods).** Monthly formulas from precipitation and CU. Simple and used by StateCU, but comparison studies find performance depends on climate and recommend checking against a soil water balance. Useful only as a sensitivity bound.

**C. Non-irrigated reference ET (paired or baseline subtraction).** `CUirr ≈ ETa(irrigated) − ETa(nearby non-irrigated land under similar conditions)`. Used in the St. Mary-Milk study (comparing irrigated and non-irrigated ETa), suggested by WestCAT as a way to approximate Pe, and the basis of the Kremmling paired-site design (International Joint Commission, n.d.; WestCAT, n.d.; Cabot et al., 2022). Strength: uses observed ET from the same weather, snowpack, and soils, so it captures what precipitation actually supports. Weak points: (1) remote sensing ETa is less accurate on natural vegetation (Volk et al., 2024; OWRD, 2025); (2) the reference must match elevation, aspect, soils, and vegetation potential, and shrubland is not hay meadow; (3) valley-bottom references near rivers or irrigated land are subirrigated or fed by irrigation return water, which biases the baseline high and CU low; (4) a rainfed-LAI baseline can strip out real crop traits (a criticism raised in HESS review of a baseline-subtraction study).

**Shallow groundwater and return flow.** In the Lower Arkansas Valley, groundwater upflux supplied 65 to 70% of growing-season ET on uncultivated land with shallow water tables, and ET stayed high with water tables deeper than 2 m (Colorado State University studies; Groeneveld et al., 2007, mapped groundwater ET from Landsat NDVI). In a mountain valley this means some "non-irrigated" land is really using irrigation return water, and some irrigated ETa comes from natural groundwater. Neither method A nor C separates these cleanly; we should state this as a known limit.

## 6. Forcing data

- gridMET: daily, ~4 km, 1979 to present; precipitation and ASCE-PM ETo/ETr (Abatzoglou, 2013). Already in this repo's climate pipeline.
- gridMET reference ET has known biases against agricultural weather stations (Blankenau et al., 2020). OpenET and Reclamation use station-based bias correction surfaces (69 Upper Colorado stations for CU&L). A recent study reports gridMET ETo is 10 to 20% high at most cropland sites, mostly from wind speed *(summary only; verify before citing)*. Use the OpenET bias-corrected ETo when computing ETc or EToF.
- Local check: CoAgMet stations near Carbondale/Glenwood and the Aspen COOP station.

## 7. Fields and irrigation status

- CDSS Division 5 irrigated lands, years 2000, 2005, 2010, 2015, 2020, 2023 (CWCB/DWR). Attributes include `CROP_TYPE`, `CROP_SRC`, `IRRIG_TYPE`, `ACRES`, `SW_WDID1..9` (ditch WDIDs), groundwater IDs. Not intended as a primary source in water court.
- Roaring Fork HUC8 (14010004), 2023 layer: 668 fields, about 19,700 acres, all District 38, median field 17 acres. Crop mix is alfalfa and grass pasture, flood and sprinkler. `CROP_SRC` is often NASS, and alfalfa vs grass may be misclassified in mountain valleys; check before using crop-specific coefficients.
- Fields are small relative to 30 m pixels (a 17 acre field is about 27 pixels), and 100 m Landsat thermal blurs edges. Use an inward buffer or interior-pixel filter and report sensitivity.
- Yearly status: the 2023 layer will not match WY2025 exactly. Apply the Reclamation EToF or NDVI rules to flag fallow or dried-up fields (Reclamation, 2025).
- Development (Aspen to Glenwood) converts hay land; check the 2020 and 2023 layers for dropouts.

## 8. Uncertainty sources to report

1. ET model choice (spread of six OpenET models; eeMETRIC vs ensemble).
2. Pe method (A vs B vs C).
3. Field boundaries, irrigation status, edge pixels.
4. gridMET bias at elevation.
5. Landsat revisit and clouds (fewer clear scenes in the mountains; uncertainty higher before 2000 and in 2012).
6. Shallow groundwater and subirrigation.
7. Aggregation: field-level errors partly cancel at HUC8 scale (OWRD, 2025).

## References

Abatzoglou, J. T. (2013). Development of gridded surface meteorological data for ecological applications and modelling. *International Journal of Climatology, 33*(1), 121–131. https://doi.org/10.1002/joc.3413

Allen, R. G., Burnett, B., Kramber, W., Huntington, J., Kjaersgaard, J., Kilic, A., Kelly, C., & Trezza, R. (2013). Automated calibration of the METRIC-Landsat evapotranspiration process. *Journal of the American Water Resources Association, 49*(3), 563–576. https://doi.org/10.1111/jawr.12056

Allen, R. G., Pereira, L. S., Raes, D., & Smith, M. (1998). *Crop evapotranspiration: Guidelines for computing crop water requirements* (FAO Irrigation and Drainage Paper 56). Food and Agriculture Organization of the United Nations. https://www.fao.org/3/x0490e/x0490e00.htm

Allen, R. G., Pereira, L. S., Smith, M., Raes, D., & Wright, J. L. (2005). FAO-56 dual crop coefficient method for estimating evaporation from soil and application extensions. *Journal of Irrigation and Drainage Engineering, 131*(1), 2–13. https://doi.org/10.1061/(ASCE)0733-9437(2005)131:1(2)

Allen, R. G., & Robison, C. W. (2009). *Evapotranspiration and consumptive irrigation water requirements for Idaho*. University of Idaho. http://www.kimberly.uidaho.edu/ETIdaho/

Allen, R. G., Robison, C. W., Huntington, J., Wright, J. L., & Kilic, A. (2020). Applying the FAO-56 dual Kc method for irrigation water requirements over large areas of the western U.S. *Transactions of the ASABE, 63*(6), 2059–2081.

Allen, R. G., Tasumi, M., & Trezza, R. (2007). Satellite-based energy balance for mapping evapotranspiration with internalized calibration (METRIC): Model. *Journal of Irrigation and Drainage Engineering, 133*(4), 380–394. https://doi.org/10.1061/(ASCE)0733-9437(2007)133:4(380)

ASCE-EWRI. (2005). *The ASCE standardized reference evapotranspiration equation*. American Society of Civil Engineers, Environmental and Water Resources Institute.

Blankenau, P. A., Kilic, A., & Allen, R. (2020). An evaluation of gridded weather data sets for the purpose of estimating reference evapotranspiration in the United States. *Agricultural Water Management, 242*, 106376. *(DOI to verify)*

Cabot, P. E., Derwingson, A. R., Bromley, M., Volk, J. M., Torres-Rua, A., & Holm, H. I. (2022). *Evaluating conserved consumptive use in the Upper Colorado: 2022 annual report. Application of an energy balance method for estimating actual evapotranspiration in high-elevation hay pastures under different irrigation regimes*. Colorado State University; Colorado Basin Roundtable. https://www.coloradobasinroundtable.org/wp-content/uploads/2023/11/Technical-Memo-2022-Evaluating-Conserved-Consumptive-Use-Upper-Colorado-Remote-Sensing.pdf

Colorado Water Conservation Board. (n.d.). *StateCU user documentation*. Colorado's Decision Support Systems. https://opencdss.state.co.us/statecu/latest/doc-user/

Groeneveld, D. P., Baugh, W. M., Sanderson, J. S., & Cooper, D. J. (2007). Annual groundwater evapotranspiration mapped from single satellite scenes. *Journal of Hydrology, 344*(1–2), 146–156. *(authors, pages, DOI to verify)*

Huntington, J., Minor, B., Bromley, M., Pearson, C., Beamer, J., Ingwersen, K., Carrara, K., Atkin, J., Brito, J., Morton, C., Dunkerly, C., Volk, J., Ott, T., ReVelle, P., Fellows, A., & Hoskinson, M. (2025). *Crop evapotranspiration, consumptive use, and open water evaporation for Oregon* (DRI Report 41306). Desert Research Institute.

International Joint Commission. (n.d.). *St. Mary–Milk Rivers consumptive use study: Remote sensing component*. https://ijc.org/en/aosmmr/st-mary-milk-rivers-consumptive-use-study-remote-sensing-component

Kilic, A., Allen, R. G., Blankenau, P., ReVelle, P., Ozturk, D., & Huntington, J. (2021). Global production and free access to Landsat-scale evapotranspiration with EEFlux and eeMETRIC. In *6th Decennial National Irrigation Symposium*. American Society of Agricultural and Biological Engineers. https://doi.org/10.13031/irrig.2020-038

Melton, F. S., Huntington, J., Grimm, R., Herring, J., Hall, M., Rollison, D., Erickson, T., et al. (2022). OpenET: Filling a critical data gap in water management for the western United States. *Journal of the American Water Resources Association, 58*(6), 971–994. https://doi.org/10.1111/1752-1688.12956

Morton, C. G., Huntington, J. L., Pohll, G. M., Allen, R. G., McGwire, K. C., & Bassett, S. D. (2013). Assessing calibration uncertainty and automation for estimating evapotranspiration from agricultural areas using METRIC. *Journal of the American Water Resources Association, 49*(3), 549–562. https://doi.org/10.1111/jawr.12054

Oregon Water Resources Department. (2025). *Statewide ET project and remotely sensed ET data: Applications for the Oregon Water Resources Department* [Technical memorandum]. https://www.oregon.gov/owrd/WRDPublications1/FINAL_OWRD_ET_Applications_Memo_28MAR2025.pdf

Pearson, C., Minor, B., Morton, C., Volk, J., Dunkerly, C., Jensen, E., ReVelle, P., Kilic, A., Allen, R., & Huntington, J. L. (2024). *Historical evapotranspiration and consumptive use of irrigated areas of the Upper Colorado River Basin* (Publication No. 41304). Desert Research Institute. https://doi.org/10.13140/RG.2.2.31069.63206

Bureau of Reclamation. (2025). *Upper Colorado River System consumptive uses and losses methods manual 1991–2025*. U.S. Department of the Interior, Interior Region 7: Upper Colorado Basin. https://www.usbr.gov/uc/DocLibrary/Reports/ConsumptiveUsesLosses/uc-ucrs-cul-methodsmanual1991-2025-508-20250800.pdf

Senay, G. B., Bohms, S., Singh, R. K., Gowda, P. H., Velpuri, N. M., Alemu, H., & Verdin, J. P. (2013). Operational evapotranspiration mapping using remote sensing and weather datasets: A new parameterization for the SSEB approach. *Journal of the American Water Resources Association, 49*(3), 577–591. https://doi.org/10.1111/jawr.12057

Upper Colorado River Commission Consumptive Use Working Group. (2022). *Assessing agricultural consumptive use in the Upper Colorado River Basin: Phase III report*. *(abstract/summary only)*

Volk, J. M., Huntington, J. L., Melton, F. S., et al. (2024). Assessing the accuracy of OpenET satellite-based evapotranspiration data to support water resource and land management applications. *Nature Water, 2*, 193–205. https://doi.org/10.1038/s44221-023-00181-7

WestCAT. (n.d.). *WestCAT frequently asked questions*. Western States Water Council. https://westernstateswater.org/westcat/

## Still to read

- Pearson et al. (2024) full text: ET Demands settings for grass pasture, winter Pe handling, and per-HUC8 results (a cross-check for 14010004).
- CWCB Upper Colorado historic crop CU report (2015) for StateCU pasture grass coefficients and District 38 acreage.
- Cabot et al. eddy covariance and soil moisture appendices (Colorado Basin Roundtable, 2026 uploads).
- Recent gridMET ETo bias study (Volk et al., 2026) and the CONUS-AgWeather dataset (Dunkerly et al., 2026); confirm citations.
- Full author lists for Melton et al. (2022) and Volk et al. (2024) (shortened with "et al."), and the Blankenau and Groeneveld entries, need checking against the DOIs before the QMD `.bib` is built.
