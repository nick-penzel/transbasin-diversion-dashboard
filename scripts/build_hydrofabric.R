# Download NHDPlus V2 flowlines for Colorado via nhdplusTools, keep larger
# streams, simplify, and save as a map layer under data_root().
#
# Usage: Rscript scripts/build_hydrofabric.R

suppressPackageStartupMessages({
  library(dplyr)
  library(sf)
  library(nhdplusTools)
})

source("scripts/storage.R")

min_order <- as.integer(Sys.getenv("MIN_STREAM_ORDER", "3"))

co_bbox <- st_bbox(c(xmin = -109.06, ymin = 36.99, xmax = -102.04, ymax = 41.00),
                   crs = 4326)

#' Fetch one tile, retrying because the service drops pages with only a warning.
fetch_tile <- function(tile, tries = 3) {
  for (i in seq_len(tries)) {
    out <- tryCatch(
      withCallingHandlers(
        get_nhdplus(AOI = tile, realization = "flowline",
                    streamorder = min_order),
        warning = function(w) stop(conditionMessage(w))
      ),
      error = function(e) {
        message(sprintf("  -> attempt %d failed: %s", i, conditionMessage(e)))
        NULL
      }
    )
    if (!is.null(out)) return(out)
    Sys.sleep(5 * i)
  }
  stop("Tile failed after ", tries, " attempts")
}

# Attributes for the map's click popups. qe_* are EROM gage-adjusted mean
# flows (cfs), elevations are in cm, -9998 means missing.
keep_cols <- c("comid", "gnis_name", "streamorde", "levelpathi", "lengthkm",
               "totdasqkm", "slope", "minelevsmo", "maxelevsmo", "qe_ma",
               sprintf("qe_%02d", 1:12))

# The web service limits feature counts, so query in tiles
tiles <- st_make_grid(st_as_sfc(co_bbox), n = c(10, 6))

flowlines <- lapply(seq_along(tiles), function(i) {
  message(sprintf("[%d/%d] tile", i, length(tiles)))
  fetch_tile(tiles[i]) |>
    select(all_of(keep_cols)) |>
    mutate(across(c(comid, streamorde, levelpathi), as.integer),
           gnis_name = as.character(gnis_name),
           across(c(lengthkm, totdasqkm, slope, minelevsmo, maxelevsmo,
                    starts_with("qe_")), as.numeric)) |>
    st_zm()
}) |>
  bind_rows() |>
  distinct(comid, .keep_all = TRUE) |>
  st_transform(4326) |>
  st_simplify(dTolerance = 15, preserveTopology = TRUE)

# Simplifying collapses short reaches to empty geometries, which leaflet rejects
flowlines <- flowlines |>
  filter(!st_is_empty(flowlines)) |>
  st_cast("MULTILINESTRING")

path <- dataset_path("reference")
dir.create(path, recursive = TRUE, showWarnings = FALSE)
out <- file.path(path, "flowlines.geojson")
st_write(flowlines, out, delete_dsn = TRUE, quiet = TRUE,
         layer_options = "COORDINATE_PRECISION=5")
message(sprintf("Wrote %d flowlines to %s", nrow(flowlines), out))
