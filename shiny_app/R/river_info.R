# Summaries for a clicked NHDPlus reach and the river it belongs to.

library(dplyr)
library(ggplot2)

#' NHDPlus uses -9998 and similar for missing values.
nhd_na <- function(x) if_else(x < 0, NA_real_, as.numeric(x))

fmt_num <- function(x, digits = 0, suffix = "") {
  if (is.na(x)) return("n/a")
  paste0(format(round(x, digits), big.mark = ",", nsmall = digits), suffix)
}

#' HTML card body describing a reach and its river (shared level path).
river_info_ui <- function(reach, flowlines) {
  river <- sf::st_drop_geometry(flowlines) |>
    filter(levelpathi == reach$levelpathi)

  name <- if (is.na(reach$gnis_name)) "Unnamed reach" else reach$gnis_name
  cm_to_ft <- function(x) nhd_na(x) / 100 * 3.28084
  reach_elev <- mean(cm_to_ft(c(reach$minelevsmo, reach$maxelevsmo)))
  river_elev <- range(cm_to_ft(c(river$minelevsmo, river$maxelevsmo)), na.rm = TRUE)
  river_mi   <- sum(river$lengthkm) * 0.621371

  tagList(
    h4(name),
    p(class = "text-muted small", sprintf("NHDPlus V2 reach %s", reach$comid)),
    tags$table(
      class = "table table-sm small",
      tags$tbody(
        tags$tr(tags$td("Mean annual flow (est.)"),
                tags$td(fmt_num(nhd_na(reach$qe_ma), 0, " cfs"))),
        tags$tr(tags$td("Drainage area"),
                tags$td(fmt_num(reach$totdasqkm * 0.386102, 0, " mi²"))),
        tags$tr(tags$td("Stream order"), tags$td(reach$streamorde)),
        tags$tr(tags$td("Elevation here"), tags$td(fmt_num(reach_elev, 0, " ft"))),
        tags$tr(tags$td("River elevation range"),
                tags$td(sprintf("%s to %s ft", fmt_num(river_elev[1]),
                                fmt_num(river_elev[2])))),
        tags$tr(tags$td("River length on map"),
                tags$td(fmt_num(river_mi, 0, " mi"))),
        tags$tr(tags$td("Average river gradient"),
                tags$td(fmt_num(diff(river_elev) / river_mi, 1, " ft/mi")))
      )
    ),
    p(class = "small text-muted",
      "Flow is the NHDPlus EROM gage-adjusted estimate (1971 to 2000),",
      "not an observation.")
  )
}

#' Bar chart of NHDPlus estimated mean monthly flow for a reach.
plot_reach_monthly <- function(reach) {
  monthly <- tibble(
    month = factor(month.abb, levels = month.abb),
    flow  = nhd_na(unlist(sf::st_drop_geometry(reach)[sprintf("qe_%02d", 1:12)]))
  )
  ggplot(monthly, aes(month, flow, fill = flow)) +
    geom_col(width = 0.8, na.rm = TRUE) +
    scale_fill_viridis_c(option = "mako", begin = 0.3, end = 0.85,
                         guide = "none") +
    scale_x_discrete(labels = substr(month.abb, 1, 1)) +
    labs(x = NULL, y = "cfs", title = "Estimated mean monthly flow") +
    theme_minimal(base_size = 11) +
    theme(panel.grid.major.x = element_blank(),
          plot.title = element_text(size = 10))
}
