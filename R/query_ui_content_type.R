.content_types_by_ext <- c(
  map          = "application/json; charset=utf-8",
  json         = "application/json; charset=utf-8",
  css          = "text/css; charset=utf-8",
  js           = "application/javascript; charset=utf-8",
  html         = "text/html; charset=utf-8",
  svg          = "image/svg+xml",
  webp         = "image/webp",
  png          = "image/png",
  jpg          = "image/jpeg",
  jpeg         = "image/jpeg",
  ico          = "image/x-icon",
  woff2        = "font/woff2",
  woff         = "font/woff",
  webmanifest  = "application/manifest+json; charset=utf-8"
)

query_ui_content_type <- function(file_name) {
  ext <- tolower(tools::file_ext(file_name))
  result <- .content_types_by_ext[ext]
  if (is.na(result)) "text/plain; charset=utf-8" else unname(result)
}
