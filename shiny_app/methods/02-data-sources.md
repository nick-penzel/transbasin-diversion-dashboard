# Data sources

| Source | What it provides | Used for |
|---|---|---|
| Colorado Decision Support System (CDSS) REST API, Colorado Division of Water Resources | Diversion telemetry and approved diversion records, stream gauges DWR operates, reservoir stage-volume records, water rights, call analysis, irrigated lands | Diversions, transfers, reservoirs, Rio Grande gauges, irrigation |
| U.S. Geological Survey Water Data API | Daily streamflow | Gauges, river conditions, basin outflow |
| U.S. Bureau of Reclamation RISE | Daily reservoir storage | Reclamation reservoirs |
| gridMET, University of California Merced and Northwest Knowledge Network (Abatzoglou, 2013) | Daily 4 km precipitation, temperature, reference ET, vapor pressure deficit, 1979 to yesterday | Basin climate, irrigation weather |
| Daymet v4, Oak Ridge National Laboratory (Thornton et al., 2022) | Daily 1 km precipitation, temperature, snow water equivalent, 1980 to last year | Stored for comparison; not shown yet |
| NRCS SNOTEL, Air and Water Database | Daily snow water equivalent, snow depth, precipitation, temperature at 120 Colorado sites | Snowpack |
| NHDPlus Version 2 | River network and mean annual flow by reach | River map, along-river distances |
| OpenET v2.1 (Melton et al., 2022) | Monthly 30 m actual evapotranspiration from six satellite models | Irrigation consumptive use |
| Colorado OIT statewide parcels | Assessor parcels and owner names | Irrigation landowners (hashed) |
| NRCS SSURGO, USGS 3DEP, NLCD 2021 | Soils, elevation, land cover | Irrigation soil water balance and native reference land |

## Sites

- **Stream gauges** (50): 16 key river gauges plus, for each HUC8 watershed in Colorado, the most downstream active USGS gauge draining at least 50 square miles with records back to 2000 or earlier. Two CDSS gauges cover the Rio Grande, where USGS has none that qualify.
- **Diversions**: the transmountain and transbasin structures in `data/structures.csv`, with the telemetry station, point of diversion, and release structure for each.
- **Reservoirs** (55): the state's major reservoirs. Capacities are taken from published figures; where none is listed, the largest value on record stands in.
- **Climate zones** (100): the Colorado part of each of 92 HUC8 watersheds and the 8 major basins.

## Storage

Every dataset is stored as Parquet under one data root, partitioned by year where it is large, so the same code runs against local files or cloud storage. Reruns replace rows by key, so they are safe to repeat.

## References

Abatzoglou, J. T. (2013). Development of gridded surface meteorological data for ecological applications and modelling. *International Journal of Climatology, 33*(1), 121-131. https://doi.org/10.1002/joc.3413

Melton, F. S., Huntington, J., Grimm, R., Herring, J., Hall, M., Rollison, D., Erickson, T., et al. (2022). OpenET: Filling a critical data gap in water management for the western United States. *Journal of the American Water Resources Association, 58*(6), 971-994. https://doi.org/10.1111/1752-1688.12956

Thornton, M. M., Shrestha, R., Wei, Y., Thornton, P. E., Kao, S.-C., & Wilson, B. E. (2022). *Daymet: Daily surface weather data on a 1-km grid for North America, version 4 R1*. ORNL DAAC. https://doi.org/10.3334/ORNLDAAC/2129
