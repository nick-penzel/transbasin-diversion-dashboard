# Climate and snowpack

## Gridded climate

Two gridded products are reduced to area-weighted daily means for 100 zones: the Colorado part of each of 92 HUC8 watersheds and the eight major basins. Each grid cell is weighted by the fraction of it inside the zone (and by cell area for gridMET, whose grid is in degrees).

- **gridMET** (about 4 km, 1979 to yesterday): precipitation, temperature, grass reference ET (ASCE Penman-Monteith), and vapor pressure deficit. This is what the dashboard shows. Values from roughly the last two months are provisional and are refetched daily.
- **Daymet** (1 km, 1980 to last year): precipitation, temperature, and snow water equivalent. It is stored for comparison. The two agree on temperature but differ on mountain precipitation (Colorado basin 2024: 580 mm in gridMET against 641 mm in Daymet), so they are never spliced into one series.

Water-year precipitation and reference ET are compared with past years as running totals since October 1. Temperature and vapor pressure deficit are compared by calendar day.

## Snowpack

Snow water equivalent (SWE) comes from the 120 Colorado SNOTEL sites in the NRCS Air and Water Database. Each site has a 1991 to 2020 median for every calendar day, matching NRCS "% of median".

- A basin's **% of median** is the total SWE at reporting sites over the total of their medians that day, as NRCS computes basin indexes. It is hidden while the median is under about an inch, when the percentage is too noisy to mean much.
- The basin curve is the mean of the sites' daily SWE against the mean of their medians.
- Sites are assigned to the basin polygon they sit in; two border sites take the nearest basin.
- Temperature sensors at SNOTEL sites log occasional error values; temperatures outside plausible bounds and negative snow or precipitation are removed.
