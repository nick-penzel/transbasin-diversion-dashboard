# Static assets for the app's public story view: simplified major rivers for
# its maps and the river-network artwork in the page header. Rerun after
# build_hydrofabric.R.
#
# Usage: Rscript scripts/build_story_assets.R

suppressPackageStartupMessages({
  library(dplyr)
  library(sf)
  library(ggplot2)
})

source("scripts/storage.R")

flowlines <- st_read(local_copy(file.path(dataset_path("reference"), "flowlines.geojson")),
                     quiet = TRUE) |>
  filter(!st_is_empty(geometry))

#' Merge reaches along each river (NHDPlus level path) and simplify.
merge_rivers <- function(fl, min_order, tolerance_m) {
  fl |>
    filter(streamorde >= min_order) |>
    st_transform(26913) |>
    group_by(levelpathi) |>
    summarize(name = first(na.omit(gnis_name)), order = max(streamorde),
              qe_ma = max(qe_ma, na.rm = TRUE), .groups = "drop") |>
    st_line_merge() |>
    st_simplify(dTolerance = tolerance_m) |>
    filter(!st_is_empty(geometry))
}

rivers <- merge_rivers(flowlines, 5, 150) |> st_transform(4326)
st_write(rivers, "shiny_app/data/major_rivers.geojson", delete_dsn = TRUE, quiet = TRUE)
message("major rivers: ", nrow(rivers), " level paths")

# Header art: every mapped river, brighter and wider downstream
art <- merge_rivers(flowlines, 3, 60) |> arrange(order)
basins <- st_read("shiny_app/data/basins.geojson", quiet = TRUE) |> st_transform(26913)
bb <- st_bbox(basins)

p <- ggplot() +
  geom_sf(data = basins, fill = NA, color = "#ffffff26", linewidth = 0.2) +
  geom_sf(data = art, aes(color = order, linewidth = order), lineend = "round") +
  scale_color_viridis_c(option = "mako", begin = 0.45, end = 0.95, guide = "none") +
  scale_linewidth(range = c(0.08, 1.1), guide = "none") +
  coord_sf(xlim = bb[c("xmin", "xmax")], ylim = bb[c("ymin", "ymax")], expand = FALSE) +
  theme_void() +
  theme(plot.background = element_rect(fill = "transparent", color = NA),
        panel.background = element_rect(fill = "transparent", color = NA))

ggsave("shiny_app/www/hero_rivers.png", p, device = ragg::agg_png,
       width = 14, height = 14 * diff(bb[c(2, 4)]) / diff(bb[c(1, 3)]),
       dpi = 160, bg = "transparent")
message("wrote shiny_app/www/hero_rivers.png")
