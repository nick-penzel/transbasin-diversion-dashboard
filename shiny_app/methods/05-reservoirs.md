# Reservoir storage

Daily storage comes from Reclamation's RISE database for Reclamation reservoirs and from CDSS stage-volume records for the rest. CDSS approved records lag about a year and many are only month-end values, so storage telemetry fills days with no record.

- **Cleaning**: negative values and values above 110% of capacity are dropped as recording errors (for example, one record lists Rampart Reservoir at 26 million AF). Where no capacity is curated, the ceiling is the 99.9th percentile of approved values.
- **Percent full**: storage over the curated capacity, or over the largest value on record when no capacity is listed.
- **Condition**: today's storage against the same calendar day in past years, with the same percentile classes as streamflow (at least 10 years).
- **Water-year change**: storage near September 30 minus storage near the previous September 30, using the value closest to that date within 15 days. Only reservoirs with both values count.

Not included: Trinidad (no data since 2010), Elevenmile, and plains reservoirs that CDSS does not list as active.
