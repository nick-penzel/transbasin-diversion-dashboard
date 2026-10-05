# Shared plotly styling that follows the app's light/dark mode.

library(plotly)

#' Transparent backgrounds and readable text/grid colors for either mode.
style_plotly <- function(p, dark = FALSE) {
  fg   <- if (dark) "#dee2e6" else "#343a40"
  grid <- if (dark) "rgba(255,255,255,0.12)" else "rgba(0,0,0,0.08)"
  p |>
    layout(
      paper_bgcolor = "rgba(0,0,0,0)",
      plot_bgcolor  = "rgba(0,0,0,0)",
      font   = list(color = fg, family = "Lato, sans-serif"),
      xaxis  = list(gridcolor = grid, zeroline = FALSE),
      yaxis  = list(gridcolor = grid, zeroline = FALSE),
      legend = list(orientation = "h", y = -0.15),
      hoverlabel = list(font = list(family = "Lato, sans-serif"))
    ) |>
    config(displaylogo = FALSE,
           modeBarButtonsToRemove = c("lasso2d", "select2d"))
}
