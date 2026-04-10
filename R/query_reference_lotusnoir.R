query_lotusnoir_posts <- function(q = "", limit = "20") {
  seed_query <- trimws(as.character(q))
  if (!nzchar(seed_query)) {
    return(list(
      ok = FALSE,
      error = "missing query parameter 'q'",
      results = list()
    ))
  }

  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    return(list(
      ok = FALSE,
      error = "jsonlite package is required",
      results = list()
    ))
  }

  limit_value <- suppressWarnings(as.integer(limit))
  if (!is.finite(limit_value) || is.na(limit_value)) {
    limit_value <- 20L
  }
  limit_value <- max(1L, min(20L, limit_value))

  query_string <- paste0(
    "search=", utils::URLencode(seed_query, reserved = TRUE),
    "&type=post",
    "&per_page=", as.character(limit_value)
  )
  url <- paste0("https://www.lotusnoir.info/wp-json/wp/v2/search?", query_string)

  raw_text <- tryCatch(
    paste(readLines(url, warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
    error = function(e) ""
  )
  if (!nzchar(raw_text)) {
    return(list(
      ok = FALSE,
      error = "LotusNoir unavailable",
      results = list()
    ))
  }

  payload <- tryCatch(
    jsonlite::fromJSON(raw_text, simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (is.null(payload)) {
    return(list(
      ok = FALSE,
      error = "Invalid LotusNoir response",
      results = list()
    ))
  }

  if (is.list(payload) && !is.null(payload$code) && !is.null(payload$message)) {
    return(list(
      ok = FALSE,
      error = as.character(payload$message),
      code = as.character(payload$code),
      results = list()
    ))
  }

  if (!is.list(payload)) {
    payload <- list()
  }

  results <- lapply(payload, function(entry) {
    if (!is.list(entry)) {
      return(NULL)
    }
    post_type <- trimws(as.character(entry$type %||% ""))
    if (nzchar(post_type) && post_type != "post") {
      return(NULL)
    }
    title <- trimws(as.character(entry$title %||% ""))
    url_value <- trimws(as.character(entry$url %||% ""))
    id_value <- trimws(as.character(entry$id %||% ""))
    list(
      id = id_value,
      title = title,
      url = url_value,
      snippet = title
    )
  })
  results <- Filter(Negate(is.null), results)

  list(
    ok = TRUE,
    source = "lotusnoir_wp_search",
    query = seed_query,
    count = length(results),
    results = results
  )
}

`%||%` <- function(x, y) {
  if (is.null(x)) {
    return(y)
  }
  x
}
