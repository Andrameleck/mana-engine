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

query_api_allowed_source_roots <- function() {
  configured <- trimws(Sys.getenv("MTGCODEX_API_ALLOWED_SOURCE_DIRS", unset = ""))
  roots <- if (nzchar(configured)) {
    strsplit(configured, .Platform$path.sep, fixed = TRUE)[[1]]
  } else {
    default_db <- query_collection_default_db_path()
    if (nzchar(default_db)) dirname(default_db) else character(0)
  }

  roots <- trimws(roots)
  roots <- roots[nzchar(roots) & dir.exists(roots)]
  unique(normalizePath(roots, winslash = "/", mustWork = TRUE))
}

query_api_path_is_within <- function(path, root) {
  normalized_path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  normalized_root <- normalizePath(root, winslash = "/", mustWork = TRUE)

  if (.Platform$OS.type == "windows") {
    normalized_path <- tolower(normalized_path)
    normalized_root <- tolower(normalized_root)
  }

  identical(normalized_path, normalized_root) ||
    startsWith(normalized_path, paste0(sub("/+$", "", normalized_root), "/"))
}

query_api_resolve_source_path <- function(path) {
  raw_path <- trimws(as.character(path))
  if (!nzchar(raw_path) || !file.exists(raw_path)) {
    return(query_api_error("file not found"))
  }

  normalized <- normalizePath(raw_path, winslash = "/", mustWork = TRUE)
  roots <- query_api_allowed_source_roots()
  allowed <- length(roots) > 0L && any(vapply(
    roots,
    function(root) query_api_path_is_within(normalized, root),
    logical(1)
  ))
  if (!allowed) {
    return(query_api_error("path is outside configured source directories"))
  }

  list(ok = TRUE, path = normalized)
}
