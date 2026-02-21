query_ui_content_type <- function(file_name) {
  lower <- tolower(file_name)

  if (grepl("\\.map$", lower)) {
    return("application/json; charset=utf-8")
  }
  if (grepl("\\.json$", lower)) {
    return("application/json; charset=utf-8")
  }
  if (grepl("\\.css$", lower)) {
    return("text/css; charset=utf-8")
  }
  if (grepl("\\.js$", lower)) {
    return("application/javascript; charset=utf-8")
  }
  if (grepl("\\.html$", lower)) {
    return("text/html; charset=utf-8")
  }
  if (grepl("\\.svg$", lower)) {
    return("image/svg+xml")
  }
  if (grepl("\\.png$", lower)) {
    return("image/png")
  }
  if (grepl("\\.jpg$|\\.jpeg$", lower)) {
    return("image/jpeg")
  }
  if (grepl("\\.ico$", lower)) {
    return("image/x-icon")
  }
  if (grepl("\\.woff2$", lower)) {
    return("font/woff2")
  }
  if (grepl("\\.woff$", lower)) {
    return("font/woff")
  }

  "text/plain; charset=utf-8"
}
