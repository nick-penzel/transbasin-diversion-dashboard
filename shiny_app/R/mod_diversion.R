# Diversions tab: researched profile, summary stats, current water year
# hydrograph against history, annual and monthly volumes, and water rights.
# Water years run Oct 1 to Sep 30, named for the year they end in.

library(dplyr)
library(plotly)

af_per_cfs_day <- 1.9835

water_year <- function(date) {
  as.integer(format(date, "%Y")) + (as.integer(format(date, "%m")) >= 10)
}

fmt_af <- function(x) {
  if (length(x) == 0 || is.na(x)) "n/a" else paste(format(round(x), big.mark = ","), "AF")
}

#' Profile card body from a curated research entry (or a fallback).
profile_ui <- function(s, profile) {
  header <- tagList(
    h4(s$name),
    p(class = "text-muted small",
      sprintf("WDID %s. %s basin to %s basin%s.", s$wdid, s$source_basin,
              s$destination_basin,
              if (identical(s$is_transbasin, "yes")) ", transmountain" else ""))
  )
  if (is.null(profile) || !isTRUE(profile$found)) {
    return(tagList(header, p(class = "text-muted",
                             "No published history found for this structure.")))
  }
  meta <- list(Built = profile$built, Operator = profile$operator,
               Serves = profile$serves)
  meta <- meta[!vapply(meta, is.null, logical(1))]
  tagList(
    header,
    p(profile$summary),
    if (length(meta) > 0) {
      tags$dl(class = "row small mb-2",
              lapply(names(meta), function(k) {
                tagList(tags$dt(class = "col-sm-3", k),
                        tags$dd(class = "col-sm-9", meta[[k]]))
              }))
    },
    if (length(profile$facts) > 0) {
      tags$ul(class = "small", lapply(profile$facts, tags$li))
    },
    if (length(profile$sources) > 0) {
      p(class = "small text-muted", "Sources: ",
        lapply(seq_along(profile$sources), function(i) {
          tagList(if (i > 1) ", ",
                  tags$a(href = profile$sources[[i]], target = "_blank",
                         sprintf("[%d]", i)))
        }))
    }
  )
}

#' Annual volumes by water year from monthly records (acre-feet).
annual_volumes <- function(history, wdid_sel) {
  history |>
    filter(wdid == wdid_sel, !is.na(diversion_af)) |>
    mutate(wy = water_year(month_start)) |>
    group_by(wy) |>
    summarize(af = sum(diversion_af), months = n(), .groups = "drop")
}

vb <- function(title, out_id, icon) {
  bslib::value_box(
    title, textOutput(out_id, inline = TRUE),
    p(class = "small mb-0", textOutput(paste0(out_id, "_note"), inline = TRUE)),
    showcase = bsicons::bs_icon(icon, size = "1.75rem"),
    showcase_layout = "left center"
  )
}

diversion_ui <- function(id, structures) {
  ns <- NS(id)
  choices <- split(setNames(structures$wdid, structures$name),
                   paste(structures$source_basin, "basin"))
  bslib::layout_sidebar(
    sidebar = bslib::sidebar(
      width = 300,
      selectInput(ns("wdid"), "Diversion", choices = choices),
      uiOutput(ns("profile"))
    ),
    tags$style(".div-vb .value-box-value { font-size: 1.4rem; }
                .div-vb .value-box-showcase { max-width: 3.5rem; }"),
    bslib::layout_column_wrap(
      width = 1 / 4, fill = FALSE, class = "div-vb",
      vb("Latest daily flow", ns("vb_latest"), "droplet"),
      vb("This water year", ns("vb_wytd"), "calendar3"),
      vb("Average year", ns("vb_mean"), "bar-chart"),
      vb("Record year", ns("vb_record"), "trophy")
    ),
    bslib::card(
      bslib::card_header(
        class = "d-flex justify-content-between align-items-center",
        "Daily flow vs. history",
        radioButtons(ns("period"), NULL, inline = TRUE,
                     choices = names(hydro_periods), selected = "Past year")
      ),
      plotlyOutput(ns("current"), height = "340px")
    ),
    bslib::layout_columns(
      col_widths = c(7, 5),
      bslib::card(bslib::card_header("Annual volume by use"),
                  plotlyOutput(ns("annual"), height = "280px")),
      bslib::card(bslib::card_header("Typical year by month"),
                  plotlyOutput(ns("monthly"), height = "280px"))
    ),
    bslib::card(
      bslib::card_header("Decreed water rights"),
      uiOutput(ns("rights"))
    )
  )
}

#' @param selected reactive WDID chosen elsewhere (map clicks).
#' @param dark reactive, TRUE in dark mode.
diversion_server <- function(id, structures, history, classes, daily_recent,
                             normals, rights, profiles, selected, dark) {
  moduleServer(id, function(input, output, session) {
    observeEvent(selected(), {
      updateSelectInput(session, "wdid", selected = selected())
    }, ignoreNULL = TRUE)

    s       <- reactive(filter(structures, wdid == input$wdid))
    annual  <- reactive(annual_volumes(history, input$wdid))
    daily   <- reactive(filter(daily_recent, wdid == input$wdid))
    this_wy <- water_year(Sys.Date())

    complete_years <- reactive(filter(annual(), months >= 1, wy < this_wy))

    output$profile <- renderUI({
      req(nrow(s()) == 1)
      profile_ui(s(), profiles[[input$wdid]])
    })

    latest <- reactive({
      d <- filter(daily(), !is.na(discharge_cfs))
      if (nrow(d) > 0) slice_max(d, date, n = 1, with_ties = FALSE)
    })
    output$vb_latest <- renderText({
      if (is.null(latest())) "No telemetry" else
        sprintf("%s cfs", format(round(latest()$discharge_cfs, 1)))
    })
    output$vb_latest_note <- renderText({
      if (!is.null(latest())) format(latest()$date, "%b %d, %Y")
    })
    output$vb_wytd_note <- renderText(sprintf("WY %d to date", this_wy))
    output$vb_mean_note <- renderText({
      yrs <- complete_years()$wy
      if (length(yrs) > 0) sprintf("WY %d to %d", min(yrs), max(yrs))
    })
    output$vb_record_note <- renderText("Highest annual volume")

    # Water year to date from daily telemetry (cfs-days to acre-feet)
    output$vb_wytd <- renderText({
      d <- filter(daily(), water_year(date) == this_wy)
      if (nrow(d) == 0) {
        return(fmt_af(filter(annual(), wy == this_wy)$af))
      }
      fmt_af(sum(d$discharge_cfs, na.rm = TRUE) * af_per_cfs_day)
    })

    output$vb_mean <- renderText(fmt_af(mean(complete_years()$af)))

    output$vb_record <- renderText({
      a <- complete_years()
      if (nrow(a) == 0) return("n/a")
      top <- slice_max(a, af, n = 1, with_ties = FALSE)
      sprintf("%s (WY %d)", fmt_af(top$af), top$wy)
    })

    output$current <- renderPlotly({
      stats <- if (!is.null(diversion_doy_stats)) {
        filter(diversion_doy_stats, wdid == input$wdid)
      }
      plot_site_hydrograph(site_series("diversion", input$wdid), stats,
                           title = NULL, days = hydro_periods[[input$period]],
                           dark = dark())
    })

    by_use <- reactive({
      if (is.null(classes)) {
        return(mutate(annual(), use = "Carried, use recorded elsewhere") |>
                 select(wy, use, af))
      }
      use_breakdown(filter(classes, wdid == input$wdid), annual())
    })

    output$annual <- renderPlotly({
      a <- annual()
      validate(need(nrow(a) > 0, "No diversion records for this structure."))
      avg <- mean(complete_years()$af)
      u <- by_use()
      uses <- u |> group_by(use) |> summarize(t = sum(af)) |> arrange(desc(t))
      pal <- setNames(viridisLite::viridis(max(nrow(uses), 1), begin = 0.1, end = 0.9),
                      uses$use)
      pal["Carried, use recorded elsewhere"] <- "#9e9e9e"

      p <- plot_ly()
      for (k in uses$use) {
        d <- filter(u, use == k)
        p <- p |>
          add_bars(data = d, x = ~wy, y = ~af, name = k,
                   marker = list(color = pal[[k]]),
                   text = ~sprintf("WY %d %s: %s", wy, k, fmt_vec(af)),
                   hoverinfo = "text", textposition = "none")
      }
      p |>
        layout(barmode = "stack",
               xaxis = list(title = "Water year"),
               yaxis = list(title = "Acre-feet"),
               shapes = list(list(type = "line", xref = "paper", x0 = 0, x1 = 1,
                                  y0 = avg, y1 = avg,
                                  line = list(color = "grey", dash = "dash"))),
               annotations = list(list(xref = "paper", x = 1, y = avg,
                                       text = sprintf("Average %s", fmt_af(avg)),
                                       showarrow = FALSE, xanchor = "right",
                                       yanchor = "bottom", font = list(size = 11)))) |>
        style_plotly(dark())
    })

    output$monthly <- renderPlotly({
      m <- history |>
        filter(wdid == input$wdid, !is.na(diversion_af),
               water_year(month_start) < this_wy) |>
        group_by(month) |>
        summarize(af = sum(diversion_af) / n_distinct(water_year(month_start)),
                  .groups = "drop") |>
        right_join(tibble(month = c(10:12, 1:9)), by = "month") |>
        mutate(af = coalesce(af, 0),
               label = factor(month.abb[month], levels = month.abb[c(10:12, 1:9)]),
               share = af / sum(af))
      validate(need(sum(m$af) > 0, "No diversion records for this structure."))
      plot_ly(m, x = ~label, y = ~af, type = "bar",
              marker = list(color = viridisLite::mako(12, begin = 0.3, end = 0.85)[
                rank(m$af, ties.method = "first")]),
              text = ~sprintf("%s: %s (%.0f%% of year)", label, fmt_vec(af), 100 * share),
              hoverinfo = "text", textposition = "none") |>
        layout(xaxis = list(title = ""), yaxis = list(title = "Average acre-feet")) |>
        style_plotly(dark())
    })

    output$rights <- renderUI({
      r <- if (is.null(rights)) tibble() else filter(rights, wdid == input$wdid)
      if (nrow(r) == 0) {
        return(p(class = "text-muted",
                 "No decreed rights found at this structure's WDIDs. Rights",
                 "for some diversions are decreed at other structures",
                 "(for example, upstream reservoirs)."))
      }
      rights_table(r)
    })
  })
}

fmt_vec <- function(x) paste(format(round(x), big.mark = ","), "AF")

# ---- Water classes and rights (codes from DWR Diversion Records Standard v3.0
# and the CDSS netamount API help) ----

use_labels <- c(
  "0" = "Storage", "1" = "Irrigation", "2" = "Municipal", "3" = "Commercial",
  "4" = "Industrial", "5" = "Recreation", "6" = "Fishery", "7" = "Fire",
  "8" = "Domestic", "9" = "Stock", "A" = "Augmentation",
  "B" = "Sub-basin export", "C" = "Change of use return flow",
  "E" = "Evaporation", "F" = "Federal reserved", "G" = "Geothermal",
  "H" = "Household", "K" = "Snowmaking", "M" = "Minimum streamflow",
  "P" = "Power", "Q" = "Other", "R" = "Recharge", "S" = "Export from state",
  "T" = "Transmountain export", "W" = "Wildlife", "X" = "All beneficial uses",
  "Z" = "Other"
)

decode_uses <- function(codes) {
  vapply(codes, function(x) {
    if (is.na(x) || x == "") return("")
    labs <- use_labels[strsplit(x, "")[[1]]]
    paste(labs[!is.na(labs)], collapse = ", ")
  }, character(1), USE.NAMES = FALSE)
}

wc_field <- function(wc, key) {
  out <- regmatches(wc, regexec(paste0(key, ":(\\S*)"), wc))
  vapply(out, function(m) if (length(m) > 1) m[2] else "", character(1))
}

#' Annual volume by use (acre-feet) from water classes, avoiding double
#' counting per the Standard: drop admin/total records (T:0), quantity-only
#' uses (U:Q, U:B), model and depletion types, releases, and within-structure
#' moves. Any remainder of the headgate total is labeled "Unspecified".
use_breakdown <- function(classes, totals) {
  parts <- classes |>
    mutate(
      src = wc_field(wc_identifier, "S"),
      use = wc_field(wc_identifier, "U"),
      typ = wc_field(wc_identifier, "T"),
      frm = wc_field(wc_identifier, "F")
    ) |>
    filter(!typ %in% c("0", "R", "V", "X", "Y", "Z", "D", "J",
                       "7", "8", "L", "E", "Q", "W"),
           !use %in% c("Q", "B", ""),
           frm == "" | substr(frm, 1, 7) != wdid,
           !(use == "0" & src == "2")) |>
    mutate(use = coalesce(use_labels[use], "Other"),
           wy = water_year(month_start)) |>
    group_by(wy, use) |>
    summarize(af = sum(diversion_af, na.rm = TRUE), .groups = "drop")

  rest <- totals |>
    left_join(parts |> group_by(wy) |> summarize(parts = sum(af)), by = "wy") |>
    transmute(wy, use = "Carried, use recorded elsewhere",
              af = pmax(af - coalesce(parts, 0), 0)) |>
    filter(af > 0.5)

  bind_rows(parts, rest)
}

#' HTML table of decreed rights, most senior first.
rights_table <- function(r) {
  r <- r |>
    arrange(admin_number) |>
    mutate(
      amount = paste(
        format(net_absolute, big.mark = ",", drop0trailing = TRUE),
        ifelse(decreed_units == "A", "AF", "cfs"),
        ifelse(coalesce(net_conditional, 0) > 0,
               sprintf("(+%s conditional)", format(net_conditional, drop0trailing = TRUE)),
               "")
      ),
      uses = decode_uses(decreed_uses)
    )
  tags$div(
    class = "table-responsive",
    tags$table(
      class = "table table-sm small align-middle",
      tags$thead(tags$tr(
        tags$th("Structure"), tags$th("Appropriation"), tags$th("Admin no."),
        tags$th("Decreed amount"), tags$th("Uses"), tags$th("Case"), tags$th("")
      )),
      tags$tbody(lapply(seq_len(nrow(r)), function(i) {
        x <- r[i, ]
        tags$tr(
          tags$td(tools::toTitleCase(tolower(x$structure_name))),
          tags$td(format(x$appropriation_date, "%b %d, %Y")),
          tags$td(format(x$admin_number, nsmall = 2)),
          tags$td(x$amount),
          tags$td(x$uses),
          tags$td(x$case_numbers),
          tags$td(if (!is.na(x$more_info))
            tags$a(href = x$more_info, target = "_blank", "CDSS"))
        )
      }))
    ),
    p(class = "small text-muted",
      "Lower admin numbers are more senior. Net amounts from CDSS; some",
      "diversions also rely on rights decreed at other structures.")
  )
}
