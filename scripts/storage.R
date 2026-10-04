# Parquet storage helpers. All datasets live under one root so the same code
# can point at local data/ (Stage 1) or an S3 bucket (Stage 2).

library(arrow)
library(dplyr)

#' Storage root, from TBD_DATA_ROOT or local data/.
data_root <- function() {
  Sys.getenv("TBD_DATA_ROOT", "data")
}

#' Path to a dataset under the storage root.
dataset_path <- function(dataset) {
  file.path(data_root(), dataset)
}

#' Insert or replace rows in a partitioned dataset.
#'
#' Rows in `df` replace existing rows with the same `keys`. Only partitions
#' present in `df` are rewritten, so reruns are idempotent.
upsert_dataset <- function(df, dataset, keys, partitioning) {
  if (nrow(df) == 0) return(invisible(NULL))
  path <- dataset_path(dataset)

  if (dir.exists(path)) {
    parts <- distinct(df, across(all_of(partitioning)))
    existing <- open_dataset(path) |>
      semi_join(parts, by = partitioning) |>
      collect() |>
      anti_join(df, by = keys)
    df <- bind_rows(existing, df)
  }

  write_dataset(
    arrange(df, across(all_of(keys))),
    path,
    partitioning = partitioning,
    existing_data_behavior = "delete_matching"
  )
  message(sprintf("Wrote %d rows to %s", nrow(df), path))
}

#' Replace an unpartitioned dataset with a single Parquet file.
overwrite_dataset <- function(df, dataset) {
  path <- dataset_path(dataset)
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  write_parquet(df, file.path(path, "part-0.parquet"))
  message(sprintf("Wrote %d rows to %s", nrow(df), path))
}
