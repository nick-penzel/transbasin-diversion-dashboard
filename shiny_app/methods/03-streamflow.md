# Streamflow conditions

## Gauge conditions

Each gauge's latest daily flow is compared with flows on the same calendar day in past years, following the U.S. Geological Survey WaterWatch classes:

| Class | Percentile of flows on this day |
|---|---|
| Much below normal | below the 10th |
| Below normal | 10th to 24th |
| Normal | 25th to 75th |
| Above normal | 76th to 90th |
| Much above normal | above the 90th |
| Record low or high | below the lowest or above the highest for the day |

Percentiles use the Weibull plotting position (R `quantile` type 6) over the daily record since 1990, and a gauge is ranked only with at least 10 years for that day. Because history starts in 1990, "normal" here means normal for the last three decades, not the full gauge record.

## River conditions between gauges

Reaches without a gauge are estimated from nearby gauges. Each gauge's percentile (not its flow, so large and small rivers are comparable) is weighted by the inverse square of the distance along the river network to the reach, with a minimum of 0.5 km. Distances follow NHDPlus flow paths up and down stream. The result is labeled an estimate and uses the same classes without record categories.

## Hydrographs

Site hydrographs plot daily flow over bands for the 10th to 90th and 25th to 75th percentiles of the same calendar day. Diversion structures use approved daily records, then telemetry after records end, then monthly means before daily records begin. Diversion bands pool records within plus or minus 7 days across years and need at least 5 years, because single-day diversion values are noisy and most ditches record only in their season. A day with no record is shown as missing, not zero.

## Runoff timing

Runoff timing is the date in each water year when half of the year's outflow has passed a basin's outlet gauges. Earlier dates mean earlier snowmelt. Years count only when every outlet gauge has at least 330 days of data, and the trend is a straight-line fit in days per decade.
