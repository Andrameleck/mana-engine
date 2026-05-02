# Internal utility helpers for the synergy engine.
# Extracted from R/query_synergy_engine.R as part of the modular refactor.
# These helpers are intentionally dependency-free (besides query_api_scalar)
# so they can be loaded by every other synergy module without circular risk.

query_synergy_to_list <- function(value) {
  if (is.null(value)) {
    return(list())
  }
  if (is.list(value) && length(value) > 0L) {
    return(unname(value))
  }
  list()
}

query_synergy_to_vector <- function(value) {
  if (is.null(value)) {
    return(character(0))
  }

  flattened <- unlist(value, use.names = FALSE)
  if (length(flattened) == 0L) {
    return(character(0))
  }

  out <- trimws(as.character(flattened))
  out <- out[!is.na(out) & nzchar(out)]
  unique(out)
}

query_synergy_as_int <- function(value, default = 0L, min_value = 0L, max_value = 100L) {
  parsed <- suppressWarnings(as.integer(value))
  if (length(parsed) == 0L || any(!is.finite(parsed)) || any(is.na(parsed))) {
    parsed <- as.integer(default)
  }
  parsed <- max(as.integer(min_value), parsed)
  parsed <- min(as.integer(max_value), parsed)
  as.integer(parsed)
}

# Convenience helper: coerce `value` to a finite scalar number, falling back to
# `default` when the input is NULL, empty, NA or non-finite. Replaces the
# pervasive `suppressWarnings(as.numeric(...))` + `is.finite`/`is.na` guard
# pattern. Adopt opportunistically in new/edited code.
query_synergy_as_num <- function(value, default = 0, min_value = -Inf, max_value = Inf) {
  x <- suppressWarnings(as.numeric(value))
  if (length(x) == 0L || !is.finite(x[[1]]) || is.na(x[[1]])) {
    x <- as.numeric(default)
  } else {
    x <- x[[1]]
  }
  min(as.numeric(max_value), max(as.numeric(min_value), x))
}

query_synergy_humanize_id <- function(value) {
  text <- tolower(query_api_scalar(value, default = ""))
  if (!nzchar(text)) {
    return("")
  }
  gsub("\\s+", " ", trimws(gsub("_", " ", text)))
}

query_synergy_elapsed_ms <- function(start_elapsed) {
  end_elapsed <- proc.time()[["elapsed"]]
  round(max(0, (end_elapsed - start_elapsed) * 1000), 1)
}

query_synergy_emit_progress <- function(callback, percent = 0, stage = "", meta = list()) {
  if (!is.function(callback)) {
    return(invisible(NULL))
  }

  payload <- list(
    percent = as.integer(round(max(0, min(100, suppressWarnings(as.numeric(percent)) %||% 0)))),
    stage = query_api_scalar(stage, default = ""),
    meta = if (is.list(meta)) meta else list()
  )
  tryCatch(callback(payload), error = function(e) NULL)
  invisible(payload)
}

query_synergy_card_id <- function(card) {
  id <- query_api_scalar(card$id, default = "")
  if (nzchar(id)) {
    return(id)
  }

  oracle_id <- query_api_scalar(card$oracle_id, default = "")
  if (nzchar(oracle_id)) {
    return(oracle_id)
  }

  name <- tolower(query_api_scalar(card$name, default = ""))
  if (!nzchar(name)) {
    return("")
  }

  gsub("[^a-z0-9]+", "_", name)
}

query_synergy_card_colors <- function(card) {
  direct <- query_synergy_to_vector(card$colors)
  direct <- toupper(direct)
  direct <- direct[direct %in% c("W", "U", "B", "R", "G")]
  unique(direct)
}

query_synergy_card_color_identity <- function(card) {
  direct <- query_synergy_to_vector(card$color_identity)
  if (length(direct) == 0L) {
    direct <- query_synergy_card_colors(card)
  }
  direct <- toupper(direct)
  direct <- direct[direct %in% c("W", "U", "B", "R", "G", "C")]
  unique(direct)
}

query_synergy_card_legalities <- function(card) {
  legalities <- card$legalities
  if (!is.list(legalities) || length(legalities) == 0L) {
    return(list())
  }

  out <- list()
  keys <- names(legalities)
  if (length(keys) == 0L) {
    return(out)
  }

  for (key in keys) {
    out[[tolower(key)]] <- tolower(query_api_scalar(legalities[[key]], default = ""))
  }

  out
}

query_synergy_parse_color_identity <- function(value) {
  if (is.null(value)) {
    return(character(0))
  }

  out <- query_synergy_to_vector(value)
  out <- toupper(out)
  out <- out[out %in% c("W", "U", "B", "R", "G", "C")]
  unique(out)
}
