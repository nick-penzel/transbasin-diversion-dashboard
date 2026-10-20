# Reservoir storage status and water-year storage change. Storage is in
# acre-feet; values above 110% of the curated capacity are recording errors.

library(dplyr)

#' Drop negative storage and values above 110% of a ceiling: the curated
#' capacity, else the 99.9th percentile of approved values (telemetry has
#' spikes and stuck sensors, e.g. Dillon at 20 million AF).
clean_storage <- function(storage, reservoirs) {
  ceiling <- storage |>
    summarize(approved_af = quantile(storage_af[!provisional], 0.999, na.rm = TRUE),
              all_af = quantile(storage_af, 0.999), .by = wdid) |>
    left_join(select(reservoirs, wdid, capacity_af), by = "wdid") |>
    transmute(wdid, ceiling_af = coalesce(capacity_af, approved_af, all_af))
  storage |>
    left_join(ceiling, by = "wdid") |>
    filter(storage_af >= 0, storage_af <= 1.1 * ceiling_af) |>
    select(-ceiling_af)
}

#' Latest storage per reservoir with % full, % of median, and flow class.
#'
#' Reservoirs without a curated capacity use the largest value on record.
reservoir_status <- function(reservoirs, storage, stats) {
  record <- storage |>
    summarize(max_obs_af = max(storage_af), record_start = min(lubridate::year(date)),
              .by = wdid)
  latest <- storage |>
    slice_max(date, by = wdid, n = 1, with_ties = FALSE) |>
    select(wdid, date, storage_af, provisional)

  reservoirs |>
    left_join(latest, by = "wdid") |>
    left_join(record, by = "wdid") |>
    mutate(capacity = coalesce(capacity_af, max_obs_af),
           capacity_note = if_else(is.na(capacity_af),
                                   sprintf("largest on record since %s", record_start),
                                   capacity_source),
           pct_full = 100 * storage_af / capacity,
           mmdd = format(date, "%m-%d")) |>
    left_join(stats, by = c("wdid", "mmdd")) |>
    mutate(pct_median = 100 * storage_af / p50_af,
           class = classify_flow(storage_af, min_af, p10_af, p25_af, p75_af,
                                 p90_af, max_af)) |>
    left_join(flow_classes, by = "class")
}

#' Water-year storage change (AF) per basin: storage near Sep 30 minus the
#' prior Sep 30, using the value closest to Sep 30 within 15 days. Only
#' reservoirs with both values count.
storage_by_wy <- function(storage, reservoirs) {
  sep30 <- storage |>
    filter(format(date, "%m") %in% c("09", "10")) |>
    mutate(wy = lubridate::year(date),
           off = abs(as.numeric(date - as.Date(sprintf("%d-09-30", wy))))) |>
    filter(off <= 15) |>
    slice_min(off, by = c(wdid, wy), n = 1, with_ties = FALSE)

  sep30 |>
    inner_join(sep30 |> transmute(wdid, wy = wy + 1, prior_af = storage_af,
                                  prior_prov = provisional),
               by = c("wdid", "wy")) |>
    inner_join(select(reservoirs, wdid, basin), by = "wdid") |>
    summarize(storage_change_af = sum(storage_af - prior_af),
              n_res = n(),
              p_sto = any(provisional | prior_prov),
              .by = c(basin, wy))
}

#' Info card body for one reservoir row from reservoir_status().
reservoir_info_ui <- function(r) {
  full <- min(max(r$pct_full, 0), 100)
  tagList(
    h4(r$name),
    p(class = "small text-muted", "WDID ", r$wdid, " on ", r$water_source),
    p(strong(sprintf("%s AF on %s", fmt_num(r$storage_af), format(r$date, "%b %d, %Y"))),
      if (isTRUE(r$provisional)) tags$span(class = "badge bg-secondary ms-1", "provisional")),
    div(class = "progress mb-2", style = "height: 18px;",
        div(class = "progress-bar", role = "progressbar",
            style = sprintf("width: %.0f%%; background-color: #31688e;", full),
            sprintf("%.0f%% full", r$pct_full))),
    p(tags$span(style = sprintf(
        "display:inline-block;width:12px;height:12px;border-radius:50%%;background:%s;border:1px solid #333;margin-right:6px;vertical-align:middle;",
        r$color)),
      r$label),
    tags$table(
      class = "table table-sm small",
      tags$tbody(
        tags$tr(tags$td("Capacity"),
                tags$td(sprintf("%s AF (%s)", fmt_num(r$capacity), r$capacity_note))),
        tags$tr(tags$td(sprintf("Median for %s", format(r$date, "%b %d"))),
                tags$td(if (is.na(r$p50_af)) "n/a" else
                  sprintf("%s AF (now %.0f%% of median)", fmt_num(r$p50_af), r$pct_median))),
        tags$tr(tags$td("Record for the day"),
                tags$td(if (is.na(r$p50_af)) "n/a" else
                  sprintf("%s to %s AF (%d years since %d)", fmt_num(r$min_af),
                          fmt_num(r$max_af), r$n_years, r$first_yr))),
        tags$tr(tags$td("Data source"),
                tags$td(if (r$source == "rise") "Reclamation RISE"
                        else "CDSS stage-volume records and telemetry"))
      )
    )
  )
}
