# Shared plotly styling that follows the app's light/dark mode.

library(plotly)

#' Legend above the plot, left aligned (keeps clear of axis titles).
legend_top <- list(orientation = "h", x = 0, y = 1.02, yanchor = "bottom",
                   font = list(size = 11))

#' Transparent backgrounds and readable text/grid colors for either mode.
style_plotly <- function(p, dark = FALSE,
                         legend = list(orientation = "h", y = -0.15)) {
  fg   <- if (dark) "#dee2e6" else "#343a40"
  grid <- if (dark) "rgba(255,255,255,0.12)" else "rgba(0,0,0,0.08)"
  p |>
    layout(
      paper_bgcolor = "rgba(0,0,0,0)",
      plot_bgcolor  = "rgba(0,0,0,0)",
      font   = list(color = fg, family = "Lato, sans-serif"),
      xaxis  = list(gridcolor = grid, zeroline = FALSE),
      yaxis  = list(gridcolor = grid, zeroline = FALSE),
      legend = legend,
      hoverlabel = list(font = list(family = "Lato, sans-serif"))
    ) |>
    config(displaylogo = FALSE,
           modeBarButtonsToRemove = c("lasso2d", "select2d"))
}
