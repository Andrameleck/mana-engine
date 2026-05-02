# Fast-path loader for the precomputed-enriched SQLite catalog produced by
# `scripts/enrich-scryfall-library.R`.
#
# When the enriched tables are present and stamped with the current
# `query_synergy_precompute_version()`, this module reconstructs already
# `normalized_card_v2` records straight from the database, allowing
# `query_synergy_get_precomputed_catalog()` to skip the per-card
# normalisation step entirely (only the in-memory inverted indexes still
# need to be built).
#
# The schema is owned by `scripts/enrich-scryfall-library.R`. Keep the two
# files in sync when adding fields.
#
# Depends on: synergy_utils, synergy_event_registry, synergy_normalize,
#             synergy_cache (for `query_synergy_precompute_version` /
#             `query_synergy_file_signature`).

#' Inspect a SQLite database for an enriched, version-matching catalog.
#'
#' Returns a list with logical flags and counters used by callers to decide
#' whether the fast path is usable. Never throws.
#'
#' @keywords internal
query_synergy_enriched_sqlite_status <- function(db_path) {
  out <- list(
    available = FALSE,
    version_match = FALSE,
    precompute_version = NA_character_,
    normalizer_version = NA_character_,
    enriched_at = NA_character_,
    rows = 0L,
    db_path = as.character(db_path %||% "")
  )

  if (!is.character(db_path) || !nzchar(db_path) || !file.exists(db_path)) {
    return(out)
  }
  if (!requireNamespace("DBI", quietly = TRUE) ||
      !requireNamespace("RSQLite", quietly = TRUE) ||
      !requireNamespace("jsonlite", quietly = TRUE)) {
    return(out)
  }

  con <- tryCatch(DBI::dbConnect(RSQLite::SQLite(), db_path), error = function(e) NULL)
  if (is.null(con)) {
    return(out)
  }
  on.exit(try(DBI::dbDisconnect(con), silent = TRUE), add = TRUE)

  if (!DBI::dbExistsTable(con, "cards_enriched") ||
      !DBI::dbExistsTable(con, "enrichment_meta")) {
    return(out)
  }

  meta <- tryCatch(DBI::dbGetQuery(con, "SELECT * FROM enrichment_meta LIMIT 1"),
                   error = function(e) NULL)
  if (!is.data.frame(meta) || nrow(meta) == 0L) {
    return(out)
  }

  precompute_version <- query_api_scalar(meta$precompute_version, default = "")
  normalizer_version <- query_api_scalar(meta$normalizer_version, default = "")
  out$precompute_version <- if (nzchar(precompute_version)) precompute_version else NA_character_
  out$normalizer_version <- if (nzchar(normalizer_version)) normalizer_version else NA_character_
  out$enriched_at <- query_api_scalar(meta$enriched_at, default = NA_character_)

  count_row <- tryCatch(
    DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM cards_enriched"),
    error = function(e) NULL
  )
  if (is.data.frame(count_row) && nrow(count_row) > 0L) {
    n <- suppressWarnings(as.integer(count_row$n[[1]]))
    if (is.finite(n)) {
      out$rows <- n
    }
  }

  out$available <- isTRUE(out$rows > 0L)
  out$version_match <- isTRUE(identical(precompute_version, query_synergy_precompute_version()))
  out
}

# Split a ";"-collapsed TEXT cell back into a character vector.
query_synergy_enriched_split_chr <- function(value) {
  if (is.null(value) || length(value) == 0L) return(character(0))
  v <- value[[1]]
  if (is.na(v)) return(character(0))
  raw <- as.character(v)
  if (!nzchar(raw)) return(character(0))
  parts <- unlist(strsplit(raw, ";", fixed = TRUE), use.names = FALSE)
  parts <- trimws(parts)
  parts[nzchar(parts)]
}

# Decode a JSON cell back to its R object (list/vector). Returns the
# `default` when the cell is NULL/NA/empty/invalid.
query_synergy_enriched_decode_json <- function(value, default = list()) {
  if (is.null(value) || length(value) == 0L) return(default)
  v <- value[[1]]
  if (is.na(v)) return(default)
  raw <- as.character(v)
  if (!nzchar(raw) || identical(raw, "null")) return(default)
  parsed <- tryCatch(
    jsonlite::fromJSON(raw, simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (is.null(parsed)) default else parsed
}

# Reconstruct a single `normalized_card_v2` list from one row of
# `cards_enriched`. The row is expected to be a single-row data.frame
# slice (named columns).
query_synergy_enriched_row_to_normalized <- function(row) {
  empty_chr <- character(0)
  empty_list <- list()

  cad_strength <- suppressWarnings(as.numeric(row$cadence_strength))
  if (!is.finite(cad_strength) || is.na(cad_strength)) cad_strength <- 0

  mana_value <- suppressWarnings(as.numeric(row$mana_value))
  if (!is.finite(mana_value) || is.na(mana_value)) mana_value <- 0

  list(
    id              = query_api_scalar(row$oracle_id, default = ""),
    name            = query_api_scalar(row$face_name %||% row$name, default = ""),
    model_version   = "normalized_card_v2",
    scryfall_id     = query_api_scalar(row$scryfall_id, default = ""),
    set_code        = query_api_scalar(row$set_code, default = ""),
    set_name        = query_api_scalar(row$set_name, default = ""),
    mana_cost       = query_api_scalar(row$mana_cost, default = ""),
    colors          = query_synergy_enriched_split_chr(row$colors),
    color_identity  = query_synergy_enriched_split_chr(row$color_identity),
    mana_value      = mana_value,
    type_line       = query_api_scalar(row$type_line, default = ""),
    oracle_text     = query_api_scalar(row$oracle_text, default = ""),
    abilities       = query_synergy_enriched_decode_json(row$abilities_json, default = empty_list),
    produces        = query_synergy_enriched_decode_json(row$produces_json,  default = empty_list),
    rewards         = query_synergy_enriched_decode_json(row$rewards_json,   default = empty_list),
    requires        = query_synergy_enriched_decode_json(row$requires_json,  default = empty_list),
    replaces        = query_synergy_enriched_decode_json(row$replaces_json,  default = empty_list),
    prevents        = query_synergy_enriched_decode_json(row$prevents_json,  default = empty_list),
    amplifies       = query_synergy_enriched_decode_json(row$amplifies_json, default = empty_list),
    moves           = query_synergy_enriched_decode_json(row$moves_json,     default = empty_list),
    target_roles    = query_synergy_enriched_split_chr(row$target_roles),
    plans           = query_synergy_enriched_decode_json(row$plans_json,     default = list(
                        tags = empty_chr, setup = empty_chr,
                        finisher = empty_chr, anti = empty_chr)),
    roles           = query_synergy_enriched_split_chr(row$roles),
    cadence         = list(
      class       = query_api_scalar(row$cadence_class, default = "one_shot"),
      repeatable  = isTRUE(as.logical(suppressWarnings(as.integer(row$cadence_repeatable))) %in% TRUE),
      scalable    = isTRUE(as.logical(suppressWarnings(as.integer(row$cadence_scalable))) %in% TRUE),
      strength    = cad_strength,
      contexts    = query_synergy_to_vector(query_synergy_enriched_decode_json(row$cadence_contexts_json, default = empty_chr)),
      sources     = query_synergy_to_vector(query_synergy_enriched_decode_json(row$cadence_sources_json,  default = empty_chr))
    ),
    mechanics       = query_synergy_enriched_split_chr(row$mechanics),
    keywords        = query_synergy_enriched_split_chr(row$keywords),
    produced_events = query_synergy_enriched_split_chr(row$produced_events),
    consumed_events = query_synergy_enriched_split_chr(row$consumed_events),
    replaced_events = query_synergy_enriched_split_chr(row$replaced_events),
    prevented_events= query_synergy_enriched_split_chr(row$prevented_events),
    setup_events    = query_synergy_enriched_split_chr(row$setup_events),
    finisher_events = query_synergy_enriched_split_chr(row$finisher_events),
    strategy_tags   = query_synergy_enriched_split_chr(row$strategy_tags),
    anti_tags       = query_synergy_enriched_split_chr(row$anti_tags),
    legalities      = query_synergy_enriched_decode_json(row$legalities_json, default = empty_list)
  )
}

#' Load already-normalized cards from the enriched SQLite catalog.
#'
#' Returns a list of `normalized_card_v2` records (skipping any rows whose
#' `oracle_id` and `name` are both empty). Each call validates that
#' `enrichment_meta.precompute_version` matches
#' `query_synergy_precompute_version()`; mismatches yield a
#' `query_api_error()` so callers can fall back to live normalisation.
#'
#' The returned list carries the same `synergy_*` attributes that
#' `query_synergy_catalog_from_sqlite()` attaches, plus
#' `synergy_normalized = TRUE` so `query_synergy_get_precomputed_catalog()`
#' knows it can skip the per-card normalisation pass.
#'
#' @param db_path Path to the SQLite file holding `cards_enriched`. Defaults
#'   to the per-user cache `all_cards.sqlite`.
#' @param source_label Logical source name attached as `synergy_source`.
#'   Defaults to `"enriched_sqlite"`.
#' @return A list of normalized cards, or a `query_api_error()` payload.
#' @export
query_synergy_catalog_normalized_from_sqlite <- function(db_path = NULL,
                                                         source_label = "enriched_sqlite") {
  if (!requireNamespace("DBI", quietly = TRUE) ||
      !requireNamespace("RSQLite", quietly = TRUE) ||
      !requireNamespace("jsonlite", quietly = TRUE)) {
    return(query_api_error("database dependencies missing (DBI/RSQLite/jsonlite)"))
  }

  resolved_path <- if (is.null(db_path) || !nzchar(db_path)) {
    paths <- query_synergy_cache_paths()
    file.path(paths$base_dir, "all_cards.sqlite")
  } else {
    db_path
  }
  if (!file.exists(resolved_path)) {
    return(query_api_error(sprintf("sqlite database not found: %s", resolved_path)))
  }

  status <- query_synergy_enriched_sqlite_status(resolved_path)
  if (!isTRUE(status$available)) {
    return(query_api_error("enriched tables not found in sqlite database"))
  }
  if (!isTRUE(status$version_match)) {
    return(query_api_error(sprintf(
      "enriched precompute_version mismatch (db=%s, engine=%s)",
      status$precompute_version %||% "NA",
      query_synergy_precompute_version()
    )))
  }

  con <- tryCatch(DBI::dbConnect(RSQLite::SQLite(), resolved_path), error = function(e) NULL)
  if (is.null(con)) {
    return(query_api_error("failed to open sqlite database"))
  }
  on.exit(try(DBI::dbDisconnect(con), silent = TRUE), add = TRUE)

  rows <- tryCatch(
    DBI::dbGetQuery(con, "SELECT * FROM cards_enriched"),
    error = function(e) NULL
  )
  if (!is.data.frame(rows) || nrow(rows) == 0L) {
    return(query_api_error("enriched table is empty"))
  }

  n <- nrow(rows)
  cards <- vector("list", n)
  for (i in seq_len(n)) {
    cards[[i]] <- query_synergy_enriched_row_to_normalized(rows[i, , drop = FALSE])
  }
  cards <- Filter(function(card) {
    nzchar(query_api_scalar(card$id, default = "")) ||
      nzchar(query_api_scalar(card$name, default = ""))
  }, cards)
  if (length(cards) == 0L) {
    return(query_api_error("no usable rows in enriched table"))
  }

  signature <- paste(
    query_synergy_file_signature(resolved_path),
    status$precompute_version %||% "",
    length(cards),
    sep = "::"
  )

  attr(cards, "synergy_source") <- source_label
  attr(cards, "synergy_source_signature") <- signature
  attr(cards, "synergy_normalized") <- TRUE
  attr(cards, "synergy_cache_key") <- sprintf(
    "%s|%s|%d|%s",
    query_synergy_precompute_version(),
    source_label,
    length(cards),
    signature
  )
  cards
}
