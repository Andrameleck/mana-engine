query_ui_root_dir <- function() {
  installed_path <- system.file("www", package = "mtgcodex.api")
  if (nzchar(installed_path)) {
    return(installed_path)
  }

  project_dir <- Sys.getenv("MTGCODEX_API_PROJECT_DIR", unset = "")
  if (nzchar(project_dir)) {
    return(file.path(project_dir, "inst", "www"))
  }

  file.path(getwd(), "inst", "www")
}
