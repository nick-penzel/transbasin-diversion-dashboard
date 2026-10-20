# Build the zones climate grids are summarized to (Colorado HUC8s plus the
# 8 basin polygons) and the Daymet cell weights for each zone.
#
# Usage: Rscript scripts/build_climate_zones.R

suppressPackageStartupMessages({
  library(dplyr)
  library(sf)
  library(terra)
})

source("scripts/storage.R")
source("scripts/fetch_daymet.R")

# Geometry work happens in the Daymet projection (planar)
basins <- st_read("shiny_app/data/basins.geojson", quiet = TRUE) |>
  select(basin)
# Colorado's borders follow parallels and meridians, so the basins' bounding
# box stands in for the state (the basin polygons leave out the Republican
# and Laramie drainages)
bb <- st_bbox(basins)
lon <- seq(bb[["xmin"]], bb[["xmax"]], length.out = 500)
lat <- seq(bb[["ymin"]], bb[["ymax"]], length.out = 300)
ring <- rbind(cbind(lon, bb[["ymin"]]), cbind(bb[["xmax"]], lat),
              cbind(rev(lon), bb[["ymax"]]), cbind(bb[["xmin"]], rev(lat)))
ring <- ring[!duplicated(ring), ]
state <- st_sfc(st_polygon(list(rbind(ring, ring[1, ]))), crs = 4326) |>
  st_transform(daymet_crs)

# In-state part of each HUC8, assigned to the basin that holds most of it
# (none for HUC8s outside the basin polygons)
hucs <- nhdplusTools::get_huc(AOI = st_transform(state, 4326), type = "huc08") |>
  select(huc8, name) |>
  st_transform(daymet_crs) |>
  st_make_valid() |>
  st_intersection(state)
basins <- st_transform(basins, daymet_crs)

overlap <- suppressWarnings(st_intersection(select(hucs, huc8), basins))
huc_basin <- overlap |>
  mutate(area = as.numeric(st_area(overlap))) |>
  st_drop_geometry() |>
  left_join(tibble(huc8 = hucs$huc8, huc_area = as.numeric(st_area(hucs))),
            by = "huc8") |>
  filter(area / huc_area > 0.5) |>
  select(huc8, basin)

zones <- bind_rows(
  hucs |>
    left_join(huc_basin, by = "huc8") |>
    transmute(zone_id = huc8, zone_type = "huc8", name, basin),
  basins |>
    transmute(zone_id = basin, zone_type = "basin", name = basin, basin)
)
# Geodesic area; the projection is conformal, not equal-area
zones <- zones |>
  mutate(area_km2 = as.numeric(st_area(st_transform(zones, 4326))) / 1e6) |>
  filter(area_km2 >= 1)

overwrite_dataset(st_drop_geometry(zones), "reference/climate_zones")
zones_tmp <- tempfile(fileext = ".geojson")
zones |>
  st_simplify(dTolerance = 200) |>
  st_transform(4326) |>
  st_write(zones_tmp, quiet = TRUE)
put_file(zones_tmp, file.path(dataset_path("reference"), "climate_zones.geojson"))

# Window of the Daymet grid that covers the zones, one cell of padding
axes <- fetch_daymet_axes()
zbb <- st_bbox(zones)
xi <- which(axes$x >= zbb[["xmin"]] - 1000 & axes$x <= zbb[["xmax"]] + 1000)
yi <- which(axes$y >= zbb[["ymin"]] - 1000 & axes$y <= zbb[["ymax"]] + 1000)
template <- rast(
  nrows = length(yi), ncols = length(xi), crs = daymet_crs,
  xmin = min(axes$x[xi]) - 500, xmax = max(axes$x[xi]) + 500,
  ymin = min(axes$y[yi]) - 500, ymax = max(axes$y[yi]) + 500
)
values(template) <- 1

# Fraction of each 1 km cell inside each zone, computed once so the backfill
# is a matrix product per year
weights <- terra::extract(template, vect(zones), cells = TRUE, exact = TRUE) |>
  transmute(zone_id = zones$zone_id[ID], cell = as.integer(cell),
            weight = fraction,
            x0 = min(xi) - 1L, x1 = max(xi) - 1L,
            y0 = min(yi) - 1L, y1 = max(yi) - 1L)

overwrite_dataset(weights, "reference/daymet_weights")

as_tibble(weights) |>
  summarize(cells = n(), weight_km2 = sum(weight), .by = zone_id) |>
  left_join(st_drop_geometry(zones), by = "zone_id") |>
  mutate(diff_pct = round(100 * (weight_km2 / area_km2 - 1), 2)) |>
  arrange(zone_type, zone_id) |>
  print(n = Inf)
