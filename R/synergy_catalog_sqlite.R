# Standalone helper to load a synergy-ready catalog from a SQLite database
# without going through the Scryfall bulk download. Useful for tests, local
# scripts, and any deployment that already maintains its own cards table.
#
# Expected schema (column names, all TEXT unless noted):
#   scryfall_id, name, oracle_text, type_line, mana_cost,
#   cmc (REAL), colors, color_identity, keywords (optional), legalities (optional)
#
# Color/legality columns may be stored as JSON strings, "{...}" blobs, or
# delimited values (",", "|", "/"). Both are handled.

#' Load a synergy catalog from a local SQLite database
#'
#' Returns a list of trimmed card records ready for `query_synergy_*`
#' pipelines, with the same attributes (`synergy_source`, `synergy_cache_key`,
#' `synergy_source_signature`) the Scryfall path attaches.
#'
#' @param db_path Path to the SQLite file. Defaults to the per-user cache
#'   location (`tools::R_user_dir("mana-engine","cache")/all_cards.sqlite`).
#' @param table Table name to query. Defaults to `"cards_api"`.
#' @param where Optional SQL `WHERE` clause (without the keyword) to restrict
#'   the rows pulled (for example `"lang = 'en'"`).
#' @param limit Optional integer row cap.
#' @param source_label Logical source name attached as `synergy_source` on the
#'   returned list. Defaults to `"sqlite_cards"`.
#' @param dedupe_by_name Logical. If `TRUE` (default), keep only the first row
#'   per card name when the table contains duplicates.
#' @return A list of card records on success, or a `query_api_error` payload
#'   when dependencies/files are missing.
#' @export
query_synergy_catalog_from_sqlite <- function(db_path = NULL,
                                              table = "cards_api",
                                              where = NULL,
                                              limit = NULL,
                                              source_label = "sqlite_cards",
                                              dedupe_by_name = TRUE) {
  if (!requireNamespace("DBI", quietly = TRUE) ||
      !requireNamespace("RSQLite", quietly = TRUE)) {
    return(query_api_error("database dependencies missing (DBI/RSQLite)"))
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

  con <- tryCatch(
    DBI::dbConnect(RSQLite::SQLite(), resolved_path),
    error = function(e) NULL
  )
  if (is.null(con)) {
    return(query_api_error("failed to open sqlite database"))
  }
  on.exit(try(DBI::dbDisconnect(con), silent = TRUE), add = TRUE)

  if (!DBI::dbExistsTable(con, table)) {
    return(query_api_error(sprintf("table not found: %s", table)))
  }

  sql <- sprintf("SELECT * FROM %s", DBI::dbQuoteIdentifier(con, table))
  has_where <- FALSE
  if (isTRUE(dedupe_by_name) && "name" %in% DBI::dbListFields(con, table)) {
    # Collapse reprints down to one row per card name (keeps the lowest
    # rowid, which is typically the earliest printing). Drops ~65% of the
    # 87k-row catalog and is required for the precomputed-profile cache to
    # build in a reasonable time on the full set.
    sql <- sprintf(
      "SELECT * FROM %s WHERE rowid IN (SELECT MIN(rowid) FROM %s GROUP BY name)",
      DBI::dbQuoteIdentifier(con, table),
      DBI::dbQuoteIdentifier(con, table)
    )
    has_where <- TRUE
  }
  if (!is.null(where) && nzchar(where)) {
    sql <- paste(sql, if (has_where) "AND" else "WHERE", where)
  }
  if (!is.null(limit)) {
    n <- query_synergy_as_int(limit, default = 0L, min_value = 0L, max_value = 1e7)
    if (n > 0L) {
      sql <- paste(sql, "LIMIT", n)
    }
  }

  rows <- tryCatch(DBI::dbGetQuery(con, sql), error = function(e) NULL)
  if (!is.data.frame(rows) || nrow(rows) == 0L) {
    return(query_api_error("no rows returned from sqlite query"))
  }

  cards <- query_synergy_sqlite_rows_to_cards(rows)
  cards <- Filter(
    function(card) {
      nzchar(query_synergy_card_id(card)) &&
        nzchar(query_api_scalar(card$name, default = ""))
    },
    cards
  )

  if (length(cards) == 0L) {
    return(query_api_error("no usable card rows after normalization"))
  }

  signature <- query_synergy_file_signature(resolved_path)
  attr(cards, "synergy_source") <- source_label
  attr(cards, "synergy_source_signature") <- signature
  attr(cards, "synergy_cache_key") <- query_synergy_catalog_cache_key(
    cards,
    source = source_label,
    source_signature = signature
  )

  cards
}

# Convert a data.frame of rows into the trimmed card list shape expected by
# `query_synergy_normalize_card`. Tolerates both JSON-encoded and delimited
# representations for `colors`, `color_identity`, `keywords`, `legalities`.
# Implementation note: extracts columns once and walks indices to avoid the
# quadratic cost of `rows[i, , drop = FALSE]` slicing on wide tables.
query_synergy_sqlite_rows_to_cards <- function(rows) {
  if (!is.data.frame(rows) || nrow(rows) == 0L) {
    return(list())
  }

  cols <- names(rows)
  n <- nrow(rows)

  has <- function(name) name %in% cols

  # Pull whole columns once. For columns that don't exist at all in the
  # table, we substitute a constant default and skip per-row parsing entirely
  # (massive speedup when the enriched DB only carries Scryfall basics like
  # colors/color_identity but no legalities/keywords).
  ids <- if (has("scryfall_id")) rows[["scryfall_id"]]
         else if (has("id")) rows[["id"]]
         else rep(NA_character_, n)
  names_    <- if (has("name")) rows[["name"]] else rep(NA_character_, n)
  oracle    <- if (has("oracle_text")) rows[["oracle_text"]]
               else if (has("printed_text")) rows[["printed_text"]]
               else rep(NA_character_, n)
  type_line <- if (has("type_line")) rows[["type_line"]] else rep(NA_character_, n)
  mana_cost <- if (has("mana_cost")) rows[["mana_cost"]] else rep(NA_character_, n)
  cmc       <- if (has("cmc")) suppressWarnings(as.numeric(rows[["cmc"]])) else rep(NA_real_, n)

  has_colors <- has("colors")
  has_ci     <- has("color_identity")
  has_kw     <- has("keywords")
  has_leg    <- has("legalities")

  colors_raw <- if (has_colors) rows[["colors"]] else NULL
  ci_raw     <- if (has_ci) rows[["color_identity"]] else NULL
  kw_raw     <- if (has_kw) rows[["keywords"]] else NULL
  leg_raw    <- if (has_leg) rows[["legalities"]] else NULL

  parse_text_list_one <- function(value) {
    if (is.na(value)) return(character(0))
    raw <- as.character(value)
    if (!nzchar(raw) || raw == "[]" || raw == "{}") return(character(0))
    first <- substr(raw, 1L, 1L)
    if (first == "[" || first == "{" || first == "\"") {
      parsed <- tryCatch(
        jsonlite::fromJSON(raw, simplifyVector = TRUE),
        error = function(e) NULL
      )
      if (!is.null(parsed)) {
        return(query_synergy_to_vector(parsed))
      }
    }
    parts <- unlist(strsplit(raw, "[,|/]"), use.names = FALSE)
    query_synergy_to_vector(trimws(parts))
  }

  parse_legalities_one <- function(value) {
    if (is.na(value)) return(list())
    raw <- as.character(value)
    if (!nzchar(raw) || raw == "{}" || raw == "[]") return(list())
    first <- substr(raw, 1L, 1L)
    if (first != "{" && first != "[") return(list())
    parsed <- tryCatch(
      jsonlite::fromJSON(raw, simplifyVector = FALSE),
      error = function(e) NULL
    )
    if (is.list(parsed)) parsed else list()
  }

  empty_chr <- character(0)
  empty_list <- list()

  scalar <- function(v) {
    if (is.na(v)) "" else as.character(v)
  }

  out <- vector("list", n)
  for (i in seq_len(n)) {
    out[[i]] <- list(
      id             = scalar(ids[[i]]),
      name           = scalar(names_[[i]]),
      oracle_text    = scalar(oracle[[i]]),
      type_line      = scalar(type_line[[i]]),
      mana_cost      = scalar(mana_cost[[i]]),
      cmc            = cmc[[i]],
      colors         = if (has_colors) parse_text_list_one(colors_raw[[i]]) else empty_chr,
      color_identity = if (has_ci)     parse_text_list_one(ci_raw[[i]])     else empty_chr,
      keywords       = if (has_kw)     parse_text_list_one(kw_raw[[i]])     else empty_chr,
      legalities     = if (has_leg)    parse_legalities_one(leg_raw[[i]])   else empty_list
    )
  }

  out
}
