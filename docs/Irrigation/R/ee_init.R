#' Start an Earth Engine session
#'
#' Uses the Python earthengine-api through reticulate, in an environment
#' reticulate manages with uv. Credentials come from a one-time
#' `ee$Authenticate()` (stored in `~/.config/earthengine/`).
#'
#' @param project Google Cloud project registered for Earth Engine.
#' @return The `ee` Python module.
ee_init <- function(project = Sys.getenv("EE_PROJECT")) {
  if (!nzchar(project)) {
    stop("Set EE_PROJECT in ~/.Renviron to your Earth Engine cloud project ID.")
  }
  reticulate::py_require("earthengine-api")
  ee <- reticulate::import("ee")
  ee$Initialize(project = project)
  ee
}
