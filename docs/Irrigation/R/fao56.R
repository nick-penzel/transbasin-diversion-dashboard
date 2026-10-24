#' Crop parameters for the lean FAO-56 soil water balance
#'
#' Kc values are FAO-56 Table 12 (grass reference): alfalfa hay averaged over
#' cuttings, and grass hay set between grazing pasture and rye grass hay.
#' Root depths are on the shallow side of Table 22 for mountain soils. Stage
#' lengths (days) are short for established perennials, which green up soon
#' after melt (FAO-56 Table 11, alfalfa first cycle and pasture).
crop_params <- tibble::tribble(
  ~crop,            ~kc_ini, ~kc_mid, ~kc_end, ~root_m, ~p,   ~len_ini, ~len_dev,
  "alfalfa",           0.40,    0.95,    0.90,     1.2, 0.55,       10,       30,
  "grass_pasture",     0.40,    0.90,    0.80,     0.6, 0.55,       10,       20
)

#' Default soil water balance settings
#'
#' @return Named list used by `kc_daily()` and `swb_run()`.
swb_settings <- function(...) {
  utils::modifyList(list(
    t30_start_c = 7,      # season starts when 30 day mean air temp reaches this
    earliest_start = "04-15",
    frost_end_c = -4,     # killing frost after `frost_after` ends the season
    frost_after = "08-15",
    latest_end = "10-31",
    len_late = 20,
    kc_dormant = 0.25,    # bare or dormant ground with no snow
    snow_t_c = 1,         # precipitation falls as snow below this mean temp
    melt_mm_c = 3,        # degree day melt factor, mm per degree C per day
    cn = 75,              # SCS curve number for runoff
    irrig_end = "09-30"
  ), list(...))
}

#' Daily crop coefficient from a temperature-driven season
#'
#' @param date,tmean,tmin Daily vectors for one location.
#' @param crop One row of `crop_params`.
#' @param s Settings from `swb_settings()`.
#' @return Tibble: date, in_season, kc, season_start, season_end.
kc_daily <- function(date, tmean, tmin, crop, s = swb_settings()) {
  t30 <- as.numeric(stats::filter(tmean, rep(1 / 30, 30), sides = 1))
  yr <- as.integer(format(date, "%Y"))
  md <- format(date, "%m-%d")
  season <- purrr::map(unique(yr), \(y) {
    i <- yr == y
    start <- date[i & md >= s$earliest_start & !is.na(t30) & t30 >= s$t30_start_c][1]
    frost <- date[i & md >= s$frost_after & tmin <= s$frost_end_c][1]
    end <- min(frost, as.Date(paste0(y, "-", s$latest_end)), na.rm = TRUE)
    tibble::tibble(year = y, start = start, end = end)
  }) |>
    dplyr::bind_rows()
  tibble::tibble(date, year = yr) |>
    dplyr::left_join(season, by = "year") |>
    dplyr::mutate(
      in_season = !is.na(start) & date >= start & date <= end,
      day = as.numeric(date - start),
      to_end = as.numeric(end - date),
      kc = dplyr::case_when(
        !in_season ~ s$kc_dormant,
        day < crop$len_ini ~ crop$kc_ini,
        day < crop$len_ini + crop$len_dev ~ crop$kc_ini + (crop$kc_mid - crop$kc_ini) * (day - crop$len_ini) / crop$len_dev,
        to_end < s$len_late ~ crop$kc_end + (crop$kc_mid - crop$kc_end) * to_end / s$len_late,
        TRUE ~ crop$kc_mid
      )
    ) |>
    dplyr::select(date, in_season, kc, season_start = start, season_end = end)
}

#' SCS curve number runoff from daily water input
scs_runoff <- function(w, cn) {
  s <- 25400 / cn - 254
  ia <- 0.2 * s
  ifelse(w > ia, (w - ia)^2 / (w + 0.8 * s), 0)
}

#' Run the daily soil water balance for many fields at once
#'
#' Matrices are days by fields. Each day: snow accumulates or melts, rain plus
#' melt infiltrates after curve number runoff, water above field capacity
#' drains (deep percolation), ET is Ks x Kc x ETo (zero under snow), and in
#' the irrigated run the root zone is refilled when depletion passes RAW.
#' Effective precipitation is infiltrated rain and melt minus its deep
#' percolation.
#'
#' @param prcp,tmean,eto,kc,in_season Day by field matrices.
#' @param taw Total available water per field (mm).
#' @param p Depletion fraction per field.
#' @param irr_window Day by field logical matrix: irrigation allowed.
#' @param s Settings from `swb_settings()`.
#' @param dr0 Starting root zone depletion as a fraction of TAW.
#' @return List of day by field matrices: pe, ro, dp, et, etc, irr, swe, and
#'   sw (root zone water above wilting point at the end of the day).
swb_run <- function(prcp, tmean, eto, kc, taw, p, irr_window, s = swb_settings(), dr0 = 0.5) {
  n <- nrow(prcp)
  m <- ncol(prcp)
  out <- lapply(stats::setNames(nm = c("pe", "ro", "dp", "et", "etc", "irr", "swe", "sw")), \(x) matrix(0, n, m))
  dr <- dr0 * taw
  swe <- rep(0, m)
  raw <- p * taw
  for (d in seq_len(n)) {
    snow <- tmean[d, ] < s$snow_t_c
    swe <- swe + ifelse(snow, prcp[d, ], 0)
    melt <- pmin(swe, pmax(0, tmean[d, ]) * s$melt_mm_c)
    swe <- swe - melt
    w <- ifelse(snow, 0, prcp[d, ]) + melt
    ro <- scs_runoff(w, s$cn)
    dr <- dr - (w - ro)
    dp <- pmax(0, -dr)
    dr <- pmax(0, dr)
    covered <- swe > 0
    etc <- ifelse(covered, 0, kc[d, ] * eto[d, ])
    ks <- ifelse(dr > raw, pmax(0, (taw - dr) / (taw - raw)), 1)
    et <- pmin(ks * etc, taw - dr)
    dr <- dr + et
    irr <- ifelse(irr_window[d, ] & dr > raw, dr, 0)
    dr <- dr - irr
    out$pe[d, ] <- w - ro - dp
    out$ro[d, ] <- ro
    out$dp[d, ] <- dp
    out$et[d, ] <- et
    out$etc[d, ] <- etc
    out$irr[d, ] <- irr
    out$swe[d, ] <- swe
    out$sw[d, ] <- taw - dr
  }
  out
}

#' Day by field input matrices for the soil water balance
#'
#' Joins daily weather to fields through their gridMET cell and builds the
#' crop coefficient and season for each cell and crop.
#'
#' @param fields Tibble: field_id, cell_id, crop, awc_mm_per_m.
#' @param weather Tibble from `gridmet_daily()`.
#' @param s Settings from `swb_settings()`.
#' @return List: fields (with taw, p), dates, and day by field matrices prcp,
#'   tmean, eto, kc, in_season.
field_inputs <- function(fields, weather, s = swb_settings()) {
  fields <- fields |>
    dplyr::mutate(crop = ifelse(crop %in% crop_params$crop, crop, "grass_pasture")) |>
    dplyr::left_join(crop_params, by = "crop") |>
    dplyr::mutate(taw = awc_mm_per_m * root_m)
  weather <- dplyr::mutate(weather, tmean_c = (tmax_c + tmin_c) / 2)
  kc <- fields |>
    dplyr::distinct(cell_id, crop) |>
    dplyr::mutate(k = purrr::map2(cell_id, crop, \(cl, cr) {
      w <- weather[weather$cell_id == cl, ]
      kc_daily(w$date, w$tmean_c, w$tmin_c, crop_params[crop_params$crop == cr, ], s)
    })) |>
    tidyr::unnest(k)
  dates <- sort(unique(weather$date))
  as_mat <- function(df, col, key) {
    w <- df |>
      dplyr::select(dplyr::all_of(c(key, "date", col))) |>
      tidyr::pivot_wider(names_from = date, values_from = dplyr::all_of(col))
    t(as.matrix(w[match(fields[[key]], w[[key]]), as.character(dates)]))
  }
  fields$cell_crop <- paste(fields$cell_id, fields$crop)
  kc$cell_crop <- paste(kc$cell_id, kc$crop)
  list(
    fields = fields, dates = dates,
    prcp = as_mat(weather, "prcp_mm", "cell_id"),
    tmean = as_mat(weather, "tmean_c", "cell_id"),
    eto = as_mat(weather, "eto_mm", "cell_id"),
    kc = as_mat(kc, "kc", "cell_crop"),
    in_season = as_mat(kc, "in_season", "cell_crop") == 1
  )
}

#' Sum day by field matrices to monthly long tibbles and join them
#'
#' @param mats Named list of day by field matrices.
#' @param dates Dates for the rows.
#' @param field_id Field ids for the columns.
#' @param state Optional named list of matrices reported on the last day of
#'   each month instead of summed.
#' @return Tibble: month, field_id, one column per matrix.
monthly_long <- function(mats, dates, field_id, state = list()) {
  month <- format(dates, "%Y-%m-01")
  last_day <- !duplicated(month, fromLast = TRUE)
  to_long <- function(m, name, rows) {
    colnames(m) <- field_id
    tibble::as_tibble(m) |>
      dplyr::mutate(month = rows) |>
      tidyr::pivot_longer(-month, names_to = "field_id", values_to = name)
  }
  sums <- purrr::imap(mats, \(m, name) {
    r <- rowsum(m, month)
    to_long(r, name, rownames(r))
  })
  ends <- purrr::imap(state, \(m, name) to_long(m[last_day, , drop = FALSE], name, month[last_day]))
  c(sums, ends) |>
    purrr::reduce(dplyr::left_join, by = c("month", "field_id")) |>
    dplyr::mutate(month = as.Date(month))
}

#' Monthly effective precipitation and crop demand for each field
#'
#' Runs `swb_run()` (ET = Ks x Kc x ETo) and sums to months.
#'
#' @inheritParams field_inputs
#' @param irrigated Simulate irrigation (TRUE) or rainfed (FALSE).
#' @return Tibble: field_id, month, prcp_mm, eto_mm, pe_mm, ro_mm, dp_mm,
#'   et_sim_mm, etc_mm, irr_mm, and sw_end_mm (root zone water on the last day).
field_pe_monthly <- function(fields, weather, s = swb_settings(), irrigated = TRUE) {
  x <- field_inputs(fields, weather, s)
  md <- format(x$dates, "%m-%d")
  r <- swb_run(
    prcp = x$prcp, tmean = x$tmean, eto = x$eto, kc = x$kc,
    taw = x$fields$taw, p = x$fields$p,
    irr_window = x$in_season & irrigated & (md <= s$irrig_end),
    s = s
  )
  monthly_long(
    list(prcp_mm = x$prcp, eto_mm = x$eto, pe_mm = r$pe, ro_mm = r$ro, dp_mm = r$dp,
         et_sim_mm = r$et, etc_mm = r$etc, irr_mm = r$irr),
    x$dates, x$fields$field_id, state = list(sw_end_mm = r$sw)
  )
}

#' Spread monthly ETa to days in proportion to daily ETo
#'
#' @param eta Tibble: field_id, month, eta_mm.
#' @param x List from `field_inputs()`.
#' @return Day by field matrix of daily ETa; NA where the month has no ETa.
eta_daily <- function(eta, x) {
  month <- format(x$dates, "%Y-%m-01")
  eto_month <- rowsum(x$eto, month)
  eta_wide <- eta |>
    dplyr::mutate(month = format(month, "%Y-%m-01")) |>
    tidyr::pivot_wider(id_cols = month, names_from = field_id, values_from = eta_mm)
  m <- as.matrix(eta_wide[match(month, eta_wide$month), x$fields$field_id])
  m * x$eto / eto_month[month, , drop = FALSE]
}

#' Amount of a draw taken from the precipitation pool
#'
#' @param amount Water to remove (mm, per field).
#' @param sp,si Precipitation and irrigation pool volumes (mm).
#' @param mode Per field: "mix" (in proportion to volume), "p" (precipitation
#'   first), or "i" (irrigation first).
#' @return mm taken from the precipitation pool; the rest comes from irrigation.
from_precip <- function(amount, sp, si, mode) {
  fp <- ifelse(sp + si > 0, sp / (sp + si), 1)
  dplyr::case_when(
    mode == "mix" ~ amount * fp,
    mode == "p" ~ pmin(amount, sp),
    .default = pmax(0, amount - si)
  )
}

#' Daily soil water balance driven by observed ETa, tracking water sources
#'
#' Same snow, runoff, and drainage steps as `swb_run()`, but daily ET is the
#' OpenET ETa (from `eta_daily()`) instead of Ks x Kc x ETo. Root zone water
#' is kept in two pools, precipitation and irrigation. ET draws first on the
#' snowpack (sublimation, counted as precipitation), then the root zone. ETa
#' the root zone cannot supply comes from irrigation inside the irrigation
#' window and is counted as `other` (groundwater, sublimation, or ETa error)
#' outside it. After ET, the root zone refills with irrigation water when
#' depletion passes RAW. Days with no ETa fall back to Ks x Kc x ETo.
#'
#' Sharing rules for drainage and ET when both pools hold water:
#' - `"cul"`: drainage removes precipitation water first and ET takes
#'   precipitation water first, the Reclamation CU&L convention (Prz is
#'   precipitation minus runoff and deep percolation of precipitation, and
#'   all of it is credited against ETa).
#' - `"mix"`: both in proportion to pool volume.
#' - `"precip_first"`: drainage removes irrigation water first and ET takes
#'   precipitation water first, the most credit precipitation can get.
#' Outside the irrigation window every rule except `"mix"` takes ET from
#' irrigation water first, so water left after the season is used up before
#' the next one.
#'
#' @inheritParams swb_run
#' @param eta Day by field matrix of daily ETa (NA = fall back).
#' @param share "mix" or "precip_first".
#' @return List of day by field matrices: et, et_p (from precipitation,
#'   including sublimation), et_i (from irrigation, the CU), carry (the part
#'   of et_i used outside the irrigation window), other, irr, dp, ro, sw_p,
#'   sw_i.
swb_eta_run <- function(prcp, tmean, eto, kc, eta, taw, p, irr_window, s = swb_settings(),
                        share = c("cul", "mix", "precip_first"), dr0 = 0.5) {
  share <- match.arg(share)
  n <- nrow(prcp)
  m <- ncol(prcp)
  out <- lapply(stats::setNames(nm = c("et", "et_p", "et_i", "carry", "other", "irr", "dp", "ro", "sw_p", "sw_i")),
                \(x) matrix(0, n, m))
  sp <- (1 - dr0) * taw
  si <- rep(0, m)
  swe <- rep(0, m)
  raw <- p * taw
  for (d in seq_len(n)) {
    win <- irr_window[d, ]
    snow <- tmean[d, ] < s$snow_t_c
    swe <- swe + ifelse(snow, prcp[d, ], 0)
    melt <- pmin(swe, pmax(0, tmean[d, ]) * s$melt_mm_c)
    swe <- swe - melt
    w <- ifelse(snow, 0, prcp[d, ]) + melt
    ro <- scs_runoff(w, s$cn)
    sp <- sp + w - ro
    dp <- pmax(0, sp + si - taw)
    dp_p <- from_precip(dp, sp, si, switch(share, cul = "p", mix = "mix", precip_first = "i"))
    sp <- sp - dp_p
    si <- si - (dp - dp_p)

    demand <- eta[d, ]
    fallback <- is.na(demand)
    if (any(fallback)) {
      dr <- taw - sp - si
      ks <- ifelse(dr > raw, pmax(0, (taw - dr) / (taw - raw)), 1)
      demand[fallback] <- (ifelse(swe > 0, 0, ks * kc[d, ] * eto[d, ]))[fallback]
    }
    sub <- pmin(swe, demand)
    swe <- swe - sub
    e <- demand - sub
    soil <- pmin(e, sp + si)
    et_p <- from_precip(soil, sp, si, if (share == "mix") "mix" else ifelse(win, "p", "i"))
    et_i <- soil - et_p
    sp <- sp - et_p
    si <- si - et_i
    unmet <- e - soil
    irr <- ifelse(win, unmet, 0)
    refill <- ifelse(win & (taw - sp - si) > raw, taw - sp - si, 0)
    si <- si + refill

    out$et[d, ] <- demand
    out$et_p[d, ] <- et_p + sub
    out$et_i[d, ] <- et_i + irr
    out$carry[d, ] <- ifelse(win, 0, et_i)
    out$other[d, ] <- ifelse(win, 0, unmet)
    out$irr[d, ] <- irr + refill
    out$dp[d, ] <- dp
    out$ro[d, ] <- ro
    out$sw_p[d, ] <- sp
    out$sw_i[d, ] <- si
  }
  out
}

#' Monthly irrigation CU from the ETa-driven balance for each field
#'
#' @inheritParams field_inputs
#' @param eta Tibble: field_id, month, eta_mm (one ETa model).
#' @param share Passed to `swb_eta_run()`.
#' @param window Optional tibble: field_id, month (month start), open. Months
#'   where `open` is TRUE allow irrigation; NA or missing months fall back to
#'   the growing season through `irrig_end`. Must have a column for every
#'   field once widened.
#' @return Tibble: field_id, month, eta_mm (balance ET, including fallback
#'   months), et_p_mm, cu_mm (ET from irrigation water), carry_mm (part of
#'   cu_mm used outside the irrigation window), other_mm, irr_mm, dp_mm, and
#'   end-of-month sw_p_mm, sw_i_mm.
field_cu_bucket <- function(fields, weather, eta, s = swb_settings(), share = "cul", window = NULL) {
  x <- field_inputs(fields, weather, s)
  md <- format(x$dates, "%m-%d")
  win <- x$in_season & (md <= s$irrig_end)
  if (!is.null(window)) {
    wm <- window |>
      dplyr::mutate(month = format(month, "%Y-%m-01")) |>
      tidyr::pivot_wider(id_cols = month, names_from = field_id, values_from = open)
    m <- as.matrix(wm[match(format(x$dates, "%Y-%m-01"), wm$month), x$fields$field_id])
    win <- ifelse(is.na(m), win, m)
  }
  r <- swb_eta_run(
    prcp = x$prcp, tmean = x$tmean, eto = x$eto, kc = x$kc, eta = eta_daily(eta, x),
    taw = x$fields$taw, p = x$fields$p, irr_window = win, s = s, share = share
  )
  monthly_long(
    list(eta_mm = r$et, et_p_mm = r$et_p, cu_mm = r$et_i, carry_mm = r$carry, other_mm = r$other,
         irr_mm = r$irr, dp_mm = r$dp),
    x$dates, x$fields$field_id, state = list(sw_p_mm = r$sw_p, sw_i_mm = r$sw_i)
  )
}
