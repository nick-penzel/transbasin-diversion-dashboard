# About these methods

This is the running methods book for the Colorado Water dashboard. Each chapter describes one part of the dashboard: where the data come from, how the numbers are calculated, and what they can and cannot tell you. Chapters are added as new analyses are deployed, and the log below records what changed.

The dashboard is written for people who live and work with Colorado's rivers. The tabs keep explanations short; this book holds the detail a water professional needs to judge the numbers.

## How the dashboard is built

Scripts in the project repository pull data from public sources on a schedule, store it as Parquet files, and the Shiny app reads those files. Nothing in the dashboard is entered by hand except a few curated lists (gauges, diversions, reservoirs, reservoir capacities, and the history notes on major diversions). The code and these chapters are public: https://github.com/nick-penzel/transbasin-diversion-dashboard

Most values are **provisional**. Streamflow, diversion telemetry, and satellite ET are revised after they are first published, and approved diversion records lag about a year. The dashboard refetches recent periods so revisions flow through.

## Chapters

1. [Data sources](02-data-sources.md)
2. [Streamflow conditions](03-streamflow.md)
3. [Diversions and transfers between basins](04-diversions.md)
4. [Reservoir storage](05-reservoirs.md)
5. [Basin water-year accounting](06-basin-accounting.md)
6. [Climate and snowpack](07-climate-snowpack.md)
7. [Irrigation consumptive use](08-irrigation-cu.md) (Roaring Fork trial)
8. [Diversions, rights, and landowners](09-irrigation-rights.md) (Roaring Fork trial)

## Units and years

- Flow is in cubic feet per second (cfs). One cfs for a day is 1.9835 acre-feet (AF).
- An acre-foot is the water that covers one acre one foot deep, about 326,000 gallons.
- A **water year** runs October 1 to September 30 and is labeled by the year it ends in. An **irrigation year** runs November 1 to October 31, as in Colorado Division of Water Resources (DWR) diversion records.
- Depths of water over land are given in inches on the public pages and in millimeters in the irrigation chapters, where the source data are metric.

## Methods log

| Date | Change |
|---|---|
| 2026-10-24 | Irrigation tab and the two Roaring Fork irrigation chapters (trial). This methods book started. |
| 2026-10-22 | SNOTEL snowpack on the Basins tab and the story. |
| 2026-10-21 | Public story and River basins pages. |
| 2026-10-04 | 50-gauge network, day-of-year normals, Basins and Diversions tabs. |

## Citing

Cite the dashboard as: Penzel, N. (2026). *Colorado Water dashboard* [Web application and methods]. https://github.com/nick-penzel/transbasin-diversion-dashboard. Please also cite the underlying data sources listed in each chapter.
