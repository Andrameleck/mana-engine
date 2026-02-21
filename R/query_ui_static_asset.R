query_ui_static_asset <- function(file, res) {
  file_name <- trimws(as.character(file))
  if (!query_ui_validate_asset_name(file_name)) {
    res$status <- 400L
    res$setHeader("Content-Type", "text/plain; charset=utf-8")
    res$body <- charToRaw("Invalid asset name")
    return(invisible(NULL))
  }

  root <- query_ui_root_dir()
  path <- file.path(root, file_name)
  if (!file.exists(path)) {
    res$status <- 404L
    res$setHeader("Content-Type", "text/plain; charset=utf-8")
    res$body <- charToRaw("Asset not found")
    return(invisible(NULL))
  }

  res$setHeader("Content-Type", query_ui_content_type(file_name))

  size <- file.info(path)$size
  if (!is.finite(size) || size <= 0) {
    res$body <- raw(0)
    return(invisible(NULL))
  }

  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)
  res$body <- readBin(con, what = "raw", n = as.integer(size))
  invisible(NULL)
}
