query_lotusnoir_posts <- function(q = "", limit = "120") {
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
    limit_value <- 120L
  }
  limit_value <- max(1L, min(120L, limit_value))

  per_page <- min(100L, limit_value)
  max_pages <- max(1L, as.integer(ceiling(limit_value / per_page)))
  all_entries <- list()
  page_count <- 0L

  for (page in seq_len(max_pages)) {
    query_string <- paste0(
      "search=", utils::URLencode(seed_query, reserved = TRUE),
      "&type=post",
      "&per_page=", as.character(per_page),
      "&page=", as.character(page)
    )
    url <- paste0("https://www.lotusnoir.info/wp-json/wp/v2/search?", query_string)

    raw_text <- tryCatch(
      paste(readLines(url, warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
      error = function(e) ""
    )
    if (!nzchar(raw_text)) {
      if (page == 1L) {
        return(list(
          ok = FALSE,
          error = "LotusNoir unavailable",
          results = list()
        ))
      }
      break
    }

    payload <- tryCatch(
      jsonlite::fromJSON(raw_text, simplifyVector = FALSE),
      error = function(e) NULL
    )
    if (is.null(payload)) {
      if (page == 1L) {
        return(list(
          ok = FALSE,
          error = "Invalid LotusNoir response",
          results = list()
        ))
      }
      break
    }

    if (is.list(payload) && !is.null(payload$code) && !is.null(payload$message)) {
      if (page == 1L) {
        return(list(
          ok = FALSE,
          error = as.character(payload$message),
          code = as.character(payload$code),
          results = list()
        ))
      }
      break
    }

    if (!is.list(payload) || length(payload) == 0L) {
      break
    }

    page_count <- page_count + 1L
    all_entries <- c(all_entries, payload)
    if (length(all_entries) >= limit_value) {
      break
    }
  }

  results <- lapply(all_entries, function(entry) {
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
  if (length(results) > limit_value) {
    results <- results[seq_len(limit_value)]
  }

  list(
    ok = TRUE,
    source = "lotusnoir_wp_search",
    query = seed_query,
    fetched_pages = page_count,
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
