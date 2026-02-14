query_ui_content_type <- function(file_name) {
  lower <- tolower(file_name)

  if (grepl("\\.css$", lower)) {
    return("text/css; charset=utf-8")
  }
  if (grepl("\\.js$", lower)) {
    return("application/javascript; charset=utf-8")
  }
  if (grepl("\\.html$", lower)) {
    return("text/html; charset=utf-8")
  }

  "text/plain; charset=utf-8"
}
