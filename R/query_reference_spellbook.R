query_spellbook_variants <- function(q = "", limit = "40") {
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
    limit_value <- 40L
  }
  limit_value <- max(1L, min(100L, limit_value))

  query_string <- paste0(
    "q=", utils::URLencode(seed_query, reserved = TRUE),
    "&limit=", as.character(limit_value)
  )
  url <- paste0("https://backend.commanderspellbook.com/variants/?", query_string)

  raw_text <- tryCatch(
    paste(readLines(url, warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
    error = function(e) ""
  )
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
    next_url = if (!is.null(payload[["next"]])) as.character(payload[["next"]]) else "",
    previous_url = if (!is.null(payload[["previous"]])) as.character(payload[["previous"]]) else "",
    results = results
  )
}
