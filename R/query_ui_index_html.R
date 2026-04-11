query_ui_index_html <- function(res = NULL) {
  if (!is.null(res)) {
    res$setHeader("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
    res$setHeader("Pragma", "no-cache")
    res$setHeader("Expires", "0")
  }

  root <- query_ui_root_dir()
  index_file <- file.path(root, "index.html")

  if (!file.exists(index_file)) {
    return("<h1>UI not found</h1>")
  }

  con <- file(index_file, open = "rb")
  on.exit(close(con), add = TRUE)
  size <- file.info(index_file)$size
  if (!is.finite(size) || size <= 0) {
    return("")
  }
  readChar(con, nchars = size, useBytes = TRUE)
}
