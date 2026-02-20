query_ui_static_asset <- function(file, res) {
  file_name <- trimws(as.character(file))
  if (!query_ui_validate_asset_name(file_name)) {
    res$status <- 400L
    return("Invalid asset name")
  }

  root <- query_ui_root_dir()
  path <- file.path(root, file_name)
  if (!file.exists(path)) {
    res$status <- 404L
    return("Asset not found")
  }

  res$setHeader("Content-Type", query_ui_content_type(file_name))

  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)
  size <- file.info(path)$size
  if (!is.finite(size) || size <= 0) {
    return("")
  }
  readChar(con, nchars = size, useBytes = TRUE)
}
