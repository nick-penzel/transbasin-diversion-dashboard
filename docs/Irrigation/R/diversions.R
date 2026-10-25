#' CDSS REST API base URL
cdss_base <- "https://dwr.state.co.us/Rest/GET/api/v2"

#' Water class type codes that mark releases, not diversions to use
#'
#' 6 replacement to stream, 7 released to river, 8 release off-stream,
#' E release of excess, L release of dominion and control, Q release of a
#' quantified amount (CDSS `structures/divrec/waterclasses` dictionary).
divrec_release_types <- c("6", "7", "8", "E", "L", "Q")

#' Water class uses treated as non-consumptive pass-through
#'
#' Fishery and recreation water runs through ponds and stream amenities and
#' returns to the river (pond evaporation aside). It is reported on its own
#' and left out of diversion-to-field and equity totals.
pass_through_uses <- c("Fishery", "Recreation")

#' CDSS decreed use and water class use codes
#'
#' One codebook serves both `decreedUses` on net amount rights and the `U`
#' code in water classes (labels from `structures/divrec/waterclasses`;
#' X, C, F, N, S added from the DWR net amount documentation). Used by
#' `divrec_by_use()` here and `decode_uses()` in rights.R.
cdss_use_codes <- tibble::tribble(
  ~code, ~use,
  "0", "Storage", "1", "Irrigation", "2", "Municipal", "3", "Commercial",
  "4", "Industrial", "5", "Recreation", "6", "Fishery", "7", "Fire",
  "8", "Domestic", "9", "Stock", "A", "Augmentation", "B", "Sub-basin export",
  "C", "Cumulative accretion", "D", "Cumulative depletion", "E", "Evaporation",
  "F", "Federal reserved", "G", "Geothermal", "H", "Household use only",
  "K", "Snow making", "M", "Minimum stream flow", "N", "Net effect on river",
  "P", "Power generation", "Q", "Other", "R", "Recharge", "S", "Export from state",
  "T", "Transbasin export", "W", "Wildlife", "X", "All beneficial uses", "Z", "Other"
)

#' Read the CDSS API key without printing it
#'
#' @param path Key file, relative to `docs/Irrigation`.
#' @return The key as a string.
cdss_key <- function(path = "../../scripts/api_key.txt") {
  trimws(readLines(path, warn = FALSE)[1])
}

#' All rows from one CDSS endpoint, following pages
#'
#' HTTP 404 means no data in the request and returns an empty tibble.
#'
#' @param endpoint Path under `api/v2`, e.g. `"structures/divrec/divrecmonth"`.
#' @param ... Query parameters.
#' @param key CDSS API key.
#' @return Tibble, one row per record, CDSS field names.
cdss_get <- function(endpoint, ..., key = cdss_key()) {
  get_page <- function(page) {
    resp <- httr2::request(cdss_base) |>
      httr2::req_url_path_append(endpoint) |>
      httr2::req_url_query(format = "json", apiKey = key, pageSize = 50000, pageIndex = page, ...) |>
      httr2::req_timeout(300) |>
      httr2::req_retry(max_tries = 3) |>
      httr2::req_error(is_error = \(r) httr2::resp_status(r) >= 400 && httr2::resp_status(r) != 404) |>
      httr2::req_perform()
    if (httr2::resp_status(resp) == 404) return(list(ResultList = list(), PageCount = 1))
    httr2::resp_body_json(resp, simplifyVector = TRUE)
  }
  first <- get_page(1)
  rest <- lapply(seq_len(first$PageCount %||% 1)[-1], \(p) get_page(p)$ResultList)
  pages <- Filter(\(x) length(x) > 0, c(list(first$ResultList), rest))
  if (length(pages) == 0) return(tibble::tibble())
  dplyr::bind_rows(lapply(pages, tibble::as_tibble))
}

#' Field to ditch links from the CDSS irrigated lands layer
#'
#' Takes the fields from `read_fields()` (same HUC8 rule and recomputed
#' acres) and adds `SW_WDID1..9`, `MASTER_ID`, and `COMMENTS` from the
#' layer's attribute table. Each field's acres are split equally among its
#' ditches, the same rule CDSS uses for `acresProrated` in
#' `structures/parcelusets`.
#'
#' @param fields sf from `read_fields()` for the same layer year.
#' @param year Irrigated lands layer year.
#' @return Tibble: field_id, master_id, comments, wdid, slot, n_ditches, acres, acres_split.
read_field_ditches <- function(fields, year = 2023) {
  attrs <- file.path(div5_dir(), sprintf("Div5_Irrig_%d.dbf", year)) |>
    foreign::read.dbf(as.is = TRUE) |>
    dplyr::transmute(
      field_id = as.character(PARCEL_ID), master_id = as.character(MASTER_ID),
      comments = COMMENTS, dplyr::across(dplyr::matches("^SW_WDID[1-9]$"), as.character)
    )
  fields |>
    sf::st_drop_geometry() |>
    dplyr::select(field_id, acres) |>
    dplyr::inner_join(attrs, by = "field_id") |>
    tidyr::pivot_longer(dplyr::starts_with("SW_WDID"), names_to = "slot", values_to = "wdid") |>
    dplyr::filter(!is.na(wdid), wdid != "", wdid != "0") |>
    dplyr::transmute(
      field_id, master_id, comments,
      wdid = stringr::str_pad(trimws(wdid), 7, pad = "0"),
      slot = as.integer(sub("SW_WDID", "", slot)),
      acres
    ) |>
    dplyr::add_count(field_id, name = "n_ditches") |>
    dplyr::mutate(acres_split = acres / n_ditches)
}

#' Agricultural or turf class for each field from the layer's comments
#'
#' The CDSS layer labels non-farm irrigated turf in `COMMENTS`. Everything
#' else is agricultural; "SOME SUB-IRRIGATION", "UNDECREED", and "APPLE"
#' stay agricultural with the comment kept as the basis.
#'
#' @param links Tibble from `read_field_ditches()`.
#' @return Tibble: field_id, land_class, turf_type, basis.
field_landclass <- function(links) {
  links |>
    dplyr::distinct(field_id, comments) |>
    dplyr::mutate(
      turf_type = dplyr::case_when(
        comments == "GOLF COURSE" ~ "golf",
        comments == "PARK" ~ "park",
        comments == "LAWN" ~ "lawn",
        comments == "RANCHETTES" ~ "ranchette",
        TRUE ~ NA_character_
      ),
      land_class = ifelse(is.na(turf_type), "agricultural", "turf"),
      basis = ifelse(is.na(comments), "no layer comment", paste0("CDSS 2023 layer COMMENTS = ", comments))
    ) |>
    dplyr::select(field_id, land_class, turf_type, basis)
}

#' CDSS parcel use records (structure to irrigated parcel links) for a year
#'
#' One request per WDID; the endpoint does not take lists.
#'
#' @param wdids Character WDIDs.
#' @param cal_year Irrigated lands year.
#' @param key CDSS API key.
#' @param pause Seconds between requests.
#' @return Tibble: wdid, field_id, cal_year, acres_prorated, acres_total, n_sw, n_gw.
fetch_parcel_uses <- function(wdids, cal_year = 2023, key = cdss_key(), pause = 0.2) {
  purrr::map(seq_along(wdids), \(i) {
    Sys.sleep(pause)
    tryCatch(
      cdss_get("structures/parcelusets", wdid = wdids[i], calYear = cal_year, key = key),
      error = \(e) {
        message(sprintf("parcelusets %s failed: %s", wdids[i], conditionMessage(e)))
        NULL
      }
    )
  }) |>
    dplyr::bind_rows() |>
    dplyr::transmute(
      wdid, field_id = as.character(parcelId), cal_year = calYear,
      acres_prorated = acresProrated, acres_total = acresTotal,
      n_sw = as.integer(assocSwWdid), n_gw = as.integer(assocGwWdid)
    )
}

#' Irrigation year, November to October, labeled by the year it ends in
#'
#' DWR keeps diversion records by irrigation year (Nov 1 to Oct 31).
#'
#' @param d Dates.
#' @return Integer irrigation year.
irrigation_year <- function(d) as.integer(format(d, "%Y")) + (as.integer(format(d, "%m")) >= 11)

#' Monthly diversion records, every water class, for many structures
#'
#' Requests go out in batches of comma-separated WDIDs; a failed batch is
#' reported and skipped. Values are acre-feet.
#'
#' @param wdids Character WDIDs.
#' @param start,end First and last month (dates; only year and month are used).
#' @param key CDSS API key.
#' @param batch WDIDs per request.
#' @param pause Seconds between requests.
#' @return Tibble: wdid, month_start, wc_identifier, af, meas_count, approval.
fetch_divrecmonth <- function(wdids, start, end, key = cdss_key(), batch = 15, pause = 0.3) {
  groups <- split(wdids, ceiling(seq_along(wdids) / batch))
  purrr::map(seq_along(groups), \(i) {
    Sys.sleep(pause)
    tryCatch(
      cdss_get(
        "structures/divrec/divrecmonth",
        wdid = paste(groups[[i]], collapse = ","),
        `min-dataMeasDate` = format(as.Date(start), "%m/%Y"),
        `max-dataMeasDate` = format(as.Date(end), "%m/%Y"),
        key = key
      ),
      error = \(e) {
        message(sprintf("divrecmonth batch %d failed: %s", i, conditionMessage(e)))
        NULL
      }
    )
  }) |>
    dplyr::bind_rows() |>
    dplyr::transmute(
      wdid,
      month_start = as.Date(paste0(dataMeasDate, "-01")),
      wc_identifier = wcIdentifier,
      af = as.numeric(dataValue),
      meas_count = measCount,
      approval = approvalStatus
    )
}

#' Split a water class identifier into its codes
#'
#' Identifiers look like `"3800757 S:1 F: U:1 T:A G:3604900 To:"`.
#'
#' @param wc Character vector of identifiers.
#' @return Tibble: s, f, u, t, g, to (empty codes as NA).
parse_wc <- function(wc) {
  code <- function(tag) {
    v <- stringr::str_match(wc, paste0("\\s", tag, ":(\\S*)"))[, 2]
    dplyr::na_if(v, "")
  }
  tibble::tibble(s = code("S"), f = code("F"), u = code("U"), t = code("T"), g = code("G"), to = code("To"))
}

#' One headgate total per structure and month
#'
#' Sums the "Total (Diversion)" rows (a structure with several accounts,
#' such as `3800712.001` and `.002`, has one per account). Without them,
#' takes the administrative total class (`S:X ... U:Q T:0`), then the sum
#' of the diversion classes, leaving out any other T:0 administrative rows.
#'
#' @param x Tibble from `fetch_divrecmonth()`.
#' @return Tibble: wdid, month_start, af, approval, total_from.
divrec_total <- function(x) {
  x <- dplyr::bind_cols(x, parse_wc(x$wc_identifier)) |>
    dplyr::mutate(rank = dplyr::case_when(
      grepl("Total \\(Diversion\\)", wc_identifier) ~ 1L,
      s %in% "X" & u %in% "Q" & t %in% "0" ~ 2L,
      grepl("Total|Comment", wc_identifier) ~ 9L,
      t %in% "0" ~ 9L,
      TRUE ~ 3L
    )) |>
    dplyr::filter(rank < 9)
  x |>
    dplyr::group_by(wdid, month_start) |>
    dplyr::filter(rank == min(rank)) |>
    dplyr::summarise(
      af = sum(af),
      approval = ifelse(any(approval == "Provisional"), "Provisional", "Approved"),
      total_from = c("total rows", "admin total", "sum of classes")[min(rank)],
      .groups = "drop"
    ) |>
    dplyr::arrange(wdid, month_start)
}

#' Diversions split by use from the water class codes
#'
#' Every diversion class gets one category, so categories sum to the
#' headgate total from `divrec_total()`. Totals, comments, and all
#' administrative records (T:0) are dropped.
#'
#' - A known `U` code gets its use label (Irrigation, Fishery, ...).
#' - Release types (T:6/7/8/E/L/Q) are "Released to stream": water taken
#'   at the headgate and put back under a plan or account.
#' - `U:Q` with a `To:` structure is "Carried to another structure" (its
#'   use is recorded at the destination); other `U:Q` is "Quantity only".
#' - Rows whose `F:` is an account of the same structure (e.g.
#'   `F:3800925.001` at 3800925) re-account water already counted and are
#'   dropped.
#' - `carried_in` is TRUE for water that another headgate in `linked`
#'   diverted and this structure only conveys: carrier rows (T:3) and
#'   blank-type `F:` rows from a linked ditch (e.g. Kelso carrying
#'   Paterson's water). Drop those before summing across ditches. Exchanges
#'   (T:1), alternate points (T:4), augmentation (T:A), and storage
#'   re-diversions (S:2) are water taken at this headgate and stay.
#'
#' @param x Tibble from `fetch_divrecmonth()`.
#' @param linked WDIDs of the structures being summed together.
#' @return Tibble: wdid, month_start, s, u, t, f, g, to, use, carried_in, af, approval.
divrec_by_use <- function(x, linked = unique(x$wdid)) {
  labels <- rlang::set_names(cdss_use_codes$use, cdss_use_codes$code)
  dplyr::bind_cols(x, parse_wc(x$wc_identifier)) |>
    dplyr::mutate(f_wdid = substr(f, 1, 7)) |>
    dplyr::filter(
      !grepl("Total|Comment", wc_identifier),
      !t %in% "0",
      is.na(f) | f_wdid != wdid
    ) |>
    dplyr::mutate(
      use = dplyr::case_when(
        t %in% divrec_release_types ~ "Released to stream",
        u %in% "Q" & !is.na(to) ~ "Carried to another structure",
        u %in% "Q" | is.na(u) ~ "Quantity only",
        TRUE ~ unname(labels[u])
      ),
      carried_in = !is.na(f) & (t %in% "3" | (is.na(t) & f_wdid %in% linked))
    ) |>
    dplyr::select(wdid, month_start, s, u, t, f, g, to, use, carried_in, af, approval)
}

#' Mixed-use class for a ditch from its use breakdown
#'
#' Released, carried, and pass-through water count as non-irrigation.
#'
#' @param by_use Tibble from `divrec_by_use()`, already limited to the period of interest.
#' @param min_share A non-irrigation use counts only above this share of the ditch total.
#' @return Tibble: wdid, total_af, irr_af, irr_share, other_uses, mix.
ditch_use_mix <- function(by_use, min_share = 0.01) {
  by_use |>
    dplyr::group_by(wdid, use) |>
    dplyr::summarise(af = sum(af), .groups = "drop_last") |>
    dplyr::mutate(share = af / sum(af)) |>
    dplyr::summarise(
      total_af = sum(af),
      irr_af = sum(af[use == "Irrigation"]),
      irr_share = irr_af / total_af,
      other_uses = paste(sort(use[use != "Irrigation" & share >= min_share]), collapse = ", "),
      .groups = "drop"
    ) |>
    dplyr::mutate(mix = dplyr::case_when(
      irr_share >= 1 - min_share ~ "irrigation only",
      irr_share >= 0.5 ~ "mostly irrigation",
      irr_share > 0 ~ "mostly other use",
      TRUE ~ "no irrigation class"
    ))
}

#' Mean annual volume per ditch over the years it reported
#'
#' A ditch-year counts as reported when the ditch has any diversion record
#' that irrigation year. Ditches that never reported get NA, not zero.
#'
#' @param by_use Tibble from `divrec_by_use()` with an `iy` column, filtered to the uses wanted.
#' @param reported Tibble of reported ditch-years (`wdid`, `iy`).
#' @param years Irrigation years to average over.
#' @return Tibble: wdid, n_years, af_mean.
ditch_mean_af <- function(by_use, reported, years) {
  annual <- by_use |>
    dplyr::filter(iy %in% years) |>
    dplyr::group_by(wdid, iy) |>
    dplyr::summarise(af = sum(af), .groups = "drop")
  reported |>
    dplyr::filter(iy %in% years) |>
    dplyr::left_join(annual, by = c("wdid", "iy")) |>
    dplyr::group_by(wdid) |>
    dplyr::summarise(n_years = dplyr::n(), af_mean = sum(af, na.rm = TRUE) / n_years)
}

#' Daily call analysis for water rights
#'
#' Asks CDSS whether each right was out of priority on each day
#' (`analysisservices/callanalysisbywdid`). Days with several calls keep
#' the largest out-of-priority share and the calls that caused it.
#'
#' @param rights Tibble with `wdid` and `admin_number`, one row per right.
#' @param start_date,end_date Dates.
#' @param key CDSS API key.
#' @param pause Seconds between requests.
#' @return Tibble: wdid, admin_number, date, oop_pct, caller.
fetch_call_analysis <- function(rights, start_date, end_date, key = cdss_key(), pause = 0.3) {
  one <- function(i) {
    cdss_get(
      "analysisservices/callanalysisbywdid",
      wdid = rights$wdid[i],
      adminNo = sprintf("%.5f", rights$admin_number[i]),
      startDate = format(as.Date(start_date), "%m/%d/%Y"),
      endDate = format(as.Date(end_date), "%m/%d/%Y"),
      key = key
    ) |>
      dplyr::transmute(
        wdid = rights$wdid[i], admin_number = rights$admin_number[i],
        date = as.Date(substr(analysisDate, 1, 10)),
        oop_pct = as.numeric(analysisOutOfPriorityPercentOfDay),
        caller = ifelse(oop_pct > 0, locationStructure, NA_character_)
      )
  }
  purrr::map(seq_len(nrow(rights)), \(i) {
    Sys.sleep(pause)
    tryCatch(one(i), error = \(e) {
      message(sprintf(
        "call analysis %s %s failed: %s",
        rights$wdid[i], rights$admin_number[i], conditionMessage(e)
      ))
      NULL
    })
  }) |>
    dplyr::bind_rows() |>
    dplyr::group_by(wdid, admin_number, date) |>
    dplyr::summarise(
      caller = paste(sort(unique(stats::na.omit(caller[oop_pct == max(oop_pct)]))), collapse = "; "),
      oop_pct = max(oop_pct),
      .groups = "drop"
    )
}

#' Historical administrative calls in a water division
#'
#' @param division Water division.
#' @param start_date Earliest date a call was set.
#' @param key CDSS API key.
#' @return Tibble: call_number, set, released, water_source, location_wdid, location,
#'   priority_admin, priority_date.
fetch_admin_calls <- function(division = 5, start_date = "2010-01-01", key = cdss_key()) {
  cdss_get("administrativecalls/historical", division = division,
           `min-dateTimeSet` = format(as.Date(start_date), "%m/%d/%Y"), key = key) |>
    dplyr::transmute(
      call_number = callNumber,
      set = as.POSIXct(dateTimeSet, format = "%Y-%m-%dT%H:%M:%S"),
      released = as.POSIXct(dateTimeReleased, format = "%Y-%m-%dT%H:%M:%S"),
      water_source = waterSourceName, location_wdid = locationWdid, location = locationStructureName,
      priority_admin = as.numeric(priorityAdminNumber),
      priority_date = as.Date(substr(priorityDate, 1, 10))
    )
}
