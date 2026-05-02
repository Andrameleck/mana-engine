query_ui_content_type <- function(file_name) {
  lower <- tolower(file_name)
  types <- c(
    "\\.(map|json)$" = "application/json; charset=utf-8",
    "\\.css$" = "text/css; charset=utf-8",
    "\\.js$" = "application/javascript; charset=utf-8",
    "\\.html$" = "text/html; charset=utf-8",
    "\\.svg$" = "image/svg+xml",
    "\\.webp$" = "image/webp",
    "\\.png$" = "image/png",
    "\\.jpe?g$" = "image/jpeg",
    "\\.ico$" = "image/x-icon",
    "\\.woff2$" = "font/woff2",
    "\\.woff$" = "font/woff",
    "\\.webmanifest$" = "application/manifest+json; charset=utf-8"
  )
  matched <- vapply(names(types), grepl, logical(1), x = lower)
  if (any(matched)) {
    return(unname(types[which(matched)[[1]]]))
  }

  "text/plain; charset=utf-8"
}
