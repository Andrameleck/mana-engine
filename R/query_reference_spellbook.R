# Internal: fetch a URL with exponential backoff on 429 / transient errors.
# Returns raw text or "" on final failure.
.spellbook_fetch_raw <- function(url, max_retries = 4L, base_delay = 2) {
  for (attempt in seq_len(max_retries)) {
    err_msg <- ""
    raw_text <- tryCatch(
      paste(readLines(url, warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
      error = function(e) { err_msg <<- conditionMessage(e); "" }
    )
    if (nzchar(raw_text)) return(raw_text)
    # 429 detected in error message → back off
    is_429 <- grepl("429", err_msg, fixed = TRUE)
    if (attempt < max_retries) {
      wait <- base_delay * 2^(attempt - 1L)  # 2, 4, 8, 16 s
      if (is_429) wait <- max(wait, 30)       # min 30 s on rate-limit
      Sys.sleep(wait)
    }
  }
  ""
}

query_spellbook_variants <- function(q = "", limit = "40") {
  seed_query <- trimws(as.character(q))

  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    return(list(
      ok = FALSE,
      error = "jsonlite package is required",
      results = list()
    ))
  }

  limit_value <- suppressWarnings(as.integer(limit))
  if (!is.finite(limit_value) || is.na(limit_value)) {
    limit_value <- 40L
  }
  limit_value <- max(1L, min(100L, limit_value))

  query_string <- if (nzchar(seed_query)) {
    paste0("q=", utils::URLencode(seed_query, reserved = TRUE), "&limit=", as.character(limit_value))
  } else {
    paste0("limit=", as.character(limit_value))
  }
  url <- paste0("https://backend.commanderspellbook.com/variants/?", query_string)

  raw_text <- .spellbook_fetch_raw(url)
  if (!nzchar(raw_text)) {
    return(list(
      ok = FALSE,
      error = "Commander Spellbook unavailable",
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
      error = "Invalid Commander Spellbook response",
      results = list()
    ))
  }

  if (!is.null(payload$detail) && nzchar(as.character(payload$detail))) {
    return(list(
      ok = FALSE,
      error = as.character(payload$detail),
      results = list()
    ))
  }

  results <- payload$results
  if (is.null(results) || !is.list(results)) {
    results <- list()
  }

  list(
    ok = TRUE,
    source = "commander_spellbook",
    count = length(results),
    total = if (!is.null(payload[["count"]])) as.integer(payload[["count"]]) else NA_integer_,
    next_url = if (!is.null(payload[["next"]])) as.character(payload[["next"]]) else "",
    previous_url = if (!is.null(payload[["previous"]])) as.character(payload[["previous"]]) else "",
    results = results
  )
}

# Fetch a Spellbook API page by its full URL (used for pagination).
query_spellbook_page_url <- function(url) {
  if (!nzchar(trimws(url))) {
    return(list(ok = FALSE, error = "empty url", results = list()))
  }

  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    return(list(ok = FALSE, error = "jsonlite package is required", results = list()))
  }

  raw_text <- .spellbook_fetch_raw(url)
  if (!nzchar(raw_text)) {
    return(list(ok = FALSE, error = "Commander Spellbook unavailable", results = list()))
  }

  payload <- tryCatch(
    jsonlite::fromJSON(raw_text, simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (is.null(payload)) {
    return(list(ok = FALSE, error = "Invalid Commander Spellbook response", results = list()))
  }

  results <- payload$results
  if (is.null(results) || !is.list(results)) results <- list()

  list(
    ok = TRUE,
    source = "commander_spellbook",
    count = length(results),
    total = if (!is.null(payload[["count"]])) as.integer(payload[["count"]]) else NA_integer_,
    next_url = if (!is.null(payload[["next"]])) as.character(payload[["next"]]) else "",
    results = results
  )
}
