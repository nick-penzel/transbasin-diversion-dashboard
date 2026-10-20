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

#' Whether a path is an S3 URI.
is_s3 <- function(path) {
  startsWith(path, "s3://")
}

#' Whether a file or dataset exists, locally or on S3.
path_exists <- function(path) {
  if (!is_s3(path)) return(file.exists(path))
  x <- FileSystem$from_uri(path)
  x$fs$GetFileInfo(x$path)[[1]]$type != FileType$NotFound
}

#' Local path to a single file, downloading it to a temp file if on S3.
#'
#' For readers that need a real file (sf, jsonlite, readr).
local_copy <- function(path) {
  if (!is_s3(path)) return(path)
  dest <- tempfile(fileext = paste0(".", tools::file_ext(path)))
  x <- FileSystem$from_uri(path)
  stream <- x$fs$OpenInputFile(x$path)
  on.exit(stream$close())
  writeBin(as.raw(stream$Read()), dest)
  dest
}

#' Copy a local file to a path under the storage root.
put_file <- function(local, path) {
  if (!is_s3(path)) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    file.copy(local, path, overwrite = TRUE)
    return(invisible(path))
  }
  x <- FileSystem$from_uri(path)
  stream <- x$fs$OpenOutputStream(x$path)
  on.exit(stream$close())
  stream$write(buffer(readBin(local, "raw", file.size(local))))
  invisible(path)
}

#' Insert or replace rows in a partitioned dataset.
#'
#' Rows in `df` replace existing rows with the same `keys`. Only partitions
#' present in `df` are rewritten, so reruns are idempotent.
upsert_dataset <- function(df, dataset, keys, partitioning) {
  if (nrow(df) == 0) return(invisible(NULL))
  path <- dataset_path(dataset)

  if (path_exists(path)) {
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
  if (!is_s3(path)) dir.create(path, recursive = TRUE, showWarnings = FALSE)
  write_parquet(df, file.path(path, "part-0.parquet"))
  message(sprintf("Wrote %d rows to %s", nrow(df), path))
}
