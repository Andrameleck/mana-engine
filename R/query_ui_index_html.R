query_ui_index_html <- function() {
  root <- query_ui_root_dir()
  index_file <- file.path(root, "index.html")

  if (!file.exists(index_file)) {
    return("<h1>UI not found</h1>")
  }

  html <- paste(readLines(index_file, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  css_file <- file.path(root, "styles.css")

  if (file.exists(css_file)) {
    css <- paste(readLines(css_file, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
    inline_style <- paste0("<style>\n", css, "\n</style>\n")
    html <- sub("</head>", paste0(inline_style, "</head>"), html, fixed = TRUE)
  }

  html
}
