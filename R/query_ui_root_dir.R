query_ui_root_dir <- function() {
  installed_path <- system.file("www", package = "MTGCODEX")
  if (nzchar(installed_path)) {
    return(installed_path)
  }

  file.path(getwd(), "inst", "www")
}
