query_ui_root_dir <- function() {
  project_dir <- Sys.getenv(
    "MANA_ENGINE_API_PROJECT_DIR",
    unset = Sys.getenv("MTGCODEX_API_PROJECT_DIR", unset = "")
  )
  if (nzchar(project_dir)) {
    return(file.path(project_dir, "inst", "www"))
  }

  local_path <- file.path(getwd(), "inst", "www")
  if (dir.exists(local_path)) {
    return(local_path)
  }

  installed_path <- system.file("www", package = "mtgcodex.api")
  if (nzchar(installed_path)) {
    return(installed_path)
  }

  local_path
}
