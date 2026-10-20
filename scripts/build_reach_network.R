# Along-river distance from every map reach to every stream gage, used to
# interpolate gage flow percentiles onto the river network. Reads the
# flowlines from build_hydrofabric.R and gages from build_reference.R.
#
# Usage: Rscript scripts/build_reach_network.R

suppressPackageStartupMessages({
  library(dplyr)
  library(sf)
  library(nhdplusTools)
})

source("scripts/storage.R")

flowlines <- st_read(local_copy(file.path(dataset_path("reference"), "flowlines.geojson")),
                     quiet = TRUE)
gages <- arrow::read_parquet(file.path(dataset_path("reference/gages"),
                                       "part-0.parquet"))

# National VAA table (downloaded once to the nhdplusTools cache)
vaa <- get_vaa(c("hydroseq", "dnhydroseq", "pathlength", "lengthkm"))
vaa_dn <- match(vaa$dnhydroseq, vaa$hydroseq)

reaches <- tibble(comid = flowlines$comid) |>
  distinct() |>
  mutate(vaa_i = match(comid, vaa$comid)) |>
  filter(!is.na(vaa_i)) |>
  mutate(hydroseq = vaa$hydroseq[vaa_i],
         bottom = vaa$pathlength[vaa_i],
         top = bottom + vaa$lengthkm[vaa_i],
         mid = (bottom + top) / 2) |>
  arrange(hydroseq)  # hydroseq decreases downstream, so outlets come first

#' Index (in `reaches`) of the first map reach at or below a VAA row.
#'
#' Walks the national network so short reaches dropped from the map, and
#' stretches that leave the state and return, don't break the path.
first_mapped <- function(vaa_i, max_steps = 5000) {
  for (step in seq_len(max_steps)) {
    if (is.na(vaa_i)) return(NA_integer_)
    hit <- match(vaa_i, reaches$vaa_i)
    if (!is.na(hit)) return(hit)
    vaa_i <- vaa_dn[vaa_i]
  }
  NA_integer_
}

reaches$dn <- vapply(vaa_dn[reaches$vaa_i], first_mapped, integer(1))

#' NLDI comid and position along the reach (percent from the downstream end).
nldi_index <- function(id) {
  Sys.sleep(0.2)
  out <- tryCatch(
    get_nldi_feature(list(featureSource = "nwissite", featureID = id)),
    error = function(e) NULL
  )
  if (is.null(out) || nrow(out) == 0) return(tibble(comid = NA_integer_, measure = NA_real_))
  tibble(comid = as.integer(out$comid[1]), measure = as.numeric(out$measure[1]))
}

gage_index <- gages |>
  mutate(nldi = purrr::map(id, \(x) if (startsWith(x, "USGS-")) nldi_index(x)
                                    else tibble(comid = NA_integer_, measure = NA_real_))) |>
  tidyr::unnest(nldi)

# Gages NLDI can't place (CDSS sites) snap to the nearest map reach
nearest <- flowlines$comid[st_nearest_feature(
  st_as_sf(gage_index, coords = c("longitude", "latitude"), crs = 4326),
  flowlines
)]

gage_index <- gage_index |>
  mutate(snapped = is.na(comid),
         comid = coalesce(comid, nearest),
         vaa_i = match(comid, vaa$comid),
         host = vapply(vaa_i, first_mapped, integer(1)),
         on_host = !is.na(host) & reaches$comid[host] == comid,
         pos = if_else(on_host & !is.na(measure),
                       vaa$pathlength[vaa_i] + vaa$lengthkm[vaa_i] * measure / 100,
                       reaches$mid[host]))

message("Gage placement:")
gage_index |>
  transmute(id, name, comid, snapped, on_map_reach = on_host) |>
  print(n = Inf)

gage_index <- filter(gage_index, !is.na(host))
n <- nrow(reaches)
g <- nrow(gage_index)

# below[i, j]: reach i is the gage's host reach or downstream of it
below <- matrix(FALSE, n, g)
for (j in seq_len(g)) {
  i <- gage_index$host[j]
  while (!is.na(i) && !below[i, j]) {
    below[i, j] <- TRUE
    i <- reaches$dn[i]
  }
}

# meet[i, j]: first reach on reach i's downstream path that is at or below
# gage j. Outlets are processed first, so dn rows are already filled.
meet <- matrix(NA_integer_, n, g)
for (i in seq_len(n)) {
  dn <- reaches$dn[i]
  meet[i, ] <- if (is.na(dn)) ifelse(below[i, ], i, NA_integer_)
               else ifelse(below[i, ], i, meet[dn, ])
}

# Along-river distance: straight up or down the same path, otherwise down
# to the confluence (top of the meeting reach) and back up
pos <- matrix(gage_index$pos, n, g, byrow = TRUE)
host <- matrix(gage_index$host, n, g, byrow = TRUE)
mid <- matrix(reaches$mid, n, g)
same_path <- meet == row(meet) | meet == host
confluence <- matrix(reaches$top[meet], n, g)
dist <- ifelse(same_path, abs(mid - pos), mid + pos - 2 * confluence)

distances <- tibble(
  comid = rep(reaches$comid, g),
  gage_id = rep(gage_index$id, each = n),
  dist_km = as.vector(dist)
) |>
  filter(!is.na(dist_km))

message(sprintf("%d of %d reaches connect to at least one gage",
                n_distinct(distances$comid), n))
overwrite_dataset(distances, "reference/reach_gage_distance")
