query_api_error <- function(message, ...) {
  list(
    ok = FALSE,
    error = as.character(message),
    ...
  )
}

query_api_scalar <- function(value, default = "") {
  if (is.null(value)) {
    return(default)
  }

  raw <- as.character(value)
  if (length(raw) == 0L) {
    return(default)
  }

  raw[is.na(raw)] <- ""
  picked <- trimws(raw[[1]])
  if (!nzchar(picked)) {
    return(default)
  }

  picked
}

query_api_scalar_arg <- function(req, key, default = "") {
  if (is.null(req) || is.null(req$args) || is.null(req$args[[key]])) {
    return(default)
  }
  query_api_scalar(req$args[[key]], default = default)
}

query_api_parse_bool <- function(value, default = FALSE) {
  parsed <- tolower(query_api_scalar(value, default = ""))
  if (!nzchar(parsed)) {
    return(isTRUE(default))
  }

  if (parsed %in% c("1", "true", "yes", "y", "on")) {
    return(TRUE)
  }
  if (parsed %in% c("0", "false", "no", "n", "off")) {
    return(FALSE)
  }

  isTRUE(default)
}

query_api_require_db <- function() {
  has_db_deps <- requireNamespace("DBI", quietly = TRUE) &&
    requireNamespace("RSQLite", quietly = TRUE)
  if (isTRUE(has_db_deps)) {
    return(TRUE)
  }

  query_api_error("database dependencies missing (DBI/RSQLite)")
}
