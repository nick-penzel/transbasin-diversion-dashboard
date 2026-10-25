# Copy the Roaring Fork irrigation tables built by the two notebooks in
# docs/Irrigation (their dashboard-export chunks write docs/Irrigation/data/dashboard/)
# to irrigation/ under the data root, where the app's Irrigation tab reads them.
# Figures for the methods book go to shiny_app/methods/figures/ (tracked).
# Rerun after either notebook changes.
#
# Usage: Rscript scripts/publish_irrigation.R

source("scripts/storage.R")

src <- "docs/Irrigation/data/dashboard"
files <- list.files(src, pattern = "\\.(parquet|geojson)$", full.names = TRUE)
stopifnot(length(files) > 0, "fields.geojson" %in% basename(files), "ditches.parquet" %in% basename(files))

for (f in files) put_file(f, file.path(dataset_path("irrigation"), basename(f)))
message(sprintf("Copied %d files to %s", length(files), dataset_path("irrigation")))

figs <- list.files(file.path(src, "figures"), pattern = "\\.png$", full.names = TRUE)
file.copy(figs, "shiny_app/methods/figures", overwrite = TRUE)
message(sprintf("Copied %d figures to shiny_app/methods/figures", length(figs)))
