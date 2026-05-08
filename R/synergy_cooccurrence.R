# =============================================================================
# Card-group co-occurrence in real decks (Archidekt + Spellbook databases).
#
# Both databases share the schema:
#   deck_cards(deck_id, section, quantity, card_name, scryfall_id)
#
# For a synergy group {A, B, C}, we count how many distinct decks contain
# ALL of those cards. The result is attached to each group as:
#   $cooccurrence = list(
#     archidekt = list(decks = N, total = T),
#     spellbook = list(decks = N, total = T)
#   )
# where N = decks containing every card and T = total decks scanned in the
# source.
#
# Performance:
#   * The first query on a source lazily creates idx_deck_cards_card_name if
#     missing; subsequent queries are fast (~5 ms per group on archidekt).
#   * Per-source connections are opened once per engine call and shared
#     across all groups, then closed.
#   * Per-call cache keyed by sorted(card_names) avoids re-querying identical
#     groups.
# =============================================================================

# Resolve the on-disk path for a packaged deck source database.
# `source_key` is one of "archidekt" or "spellbook".
query_synergy_cooccurrence_db_path <- function(source_key) {
  source_key <- tolower(query_api_scalar(source_key, default = ""))
  if (!nzchar(source_key)) return("")
  rel <- file.path("decks", source_key, paste0(source_key, ".sqlite"))

  installed_path <- system.file(rel, package = "mtgcodex.api")
  if (nzchar(installed_path) && file.exists(installed_path)) {
    return(installed_path)
  }

  project_dir <- Sys.getenv("MTGCODEX_API_PROJECT_DIR", unset = "")
  candidates <- c(
    if (nzchar(project_dir)) file.path(project_dir, "inst", rel),
    file.path(getwd(), "inst", rel),
    file.path(getwd(), "..", "inst", rel)
  )
  existing <- candidates[file.exists(candidates)]
  if (length(existing) > 0L) existing[[1]] else ""
}

# Returns a named list of available source paths (only existing files).
query_synergy_cooccurrence_sources <- function() {
  out <- list()
  for (key in c("archidekt", "spellbook")) {
    path <- query_synergy_cooccurrence_db_path(key)
    if (nzchar(path)) out[[key]] <- path
  }
  out
}

# Open a SQLite connection and ensure idx_deck_cards_card_name exists.
# Returns the connection (caller must close it).
query_synergy_cooccurrence_open <- function(db_path) {
  if (!nzchar(db_path) || !file.exists(db_path)) return(NULL)
  con <- tryCatch(
    DBI::dbConnect(RSQLite::SQLite(), db_path),
    error = function(e) NULL
  )
  if (is.null(con)) return(NULL)
  tryCatch({
    indexes <- DBI::dbGetQuery(
      con,
      "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='deck_cards'"
    )
    if (!"idx_deck_cards_card_name" %in% indexes$name) {
      # Lazy index creation. ~10 s on archidekt, ~0.3 s on spellbook. Done once.
      DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_deck_cards_card_name ON deck_cards(card_name)")
    }
  }, error = function(e) NULL)
  con
}

# Total deck count (for context in the UI).
query_synergy_cooccurrence_total_decks <- function(con) {
  if (is.null(con)) return(0L)
  res <- tryCatch(
    DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM decks"),
    error = function(e) NULL
  )
  if (is.null(res) || nrow(res) == 0L) 0L else as.integer(res$n[[1]])
}

# Count distinct decks that contain ALL of the supplied card names.
# Names are matched case-insensitively against deck_cards.card_name.
query_synergy_cooccurrence_count <- function(con, card_names) {
  if (is.null(con)) return(0L)
  names_clean <- unique(vapply(card_names, function(n) {
    tolower(trimws(query_api_scalar(n, default = "")))
  }, character(1)))
  names_clean <- names_clean[nzchar(names_clean)]
  n <- length(names_clean)
  if (n == 0L) return(0L)

  placeholders <- paste(rep("?", n), collapse = ", ")
  sql <- sprintf(
    "SELECT COUNT(*) AS n FROM (
       SELECT deck_id
       FROM deck_cards
       WHERE LOWER(card_name) IN (%s)
       GROUP BY deck_id
       HAVING COUNT(DISTINCT LOWER(card_name)) >= ?
     )",
    placeholders
  )
  res <- tryCatch(
    DBI::dbGetQuery(con, sql, params = c(as.list(names_clean), list(n))),
    error = function(e) NULL
  )
  if (is.null(res) || nrow(res) == 0L) 0L else as.integer(res$n[[1]])
}

# Annotate each group with co-occurrence counts across the available
# deck sources. `groups` is the engine's ranked group list. Each group must
# expose a `members` list with `name` fields.
query_synergy_cooccurrence_annotate_groups <- function(groups) {
  if (!is.list(groups) || length(groups) == 0L) return(groups)
  sources <- query_synergy_cooccurrence_sources()
  if (length(sources) == 0L) return(groups)

  con_map <- list()
  totals <- list()
  on.exit({
    for (con in con_map) {
      tryCatch(DBI::dbDisconnect(con), error = function(e) NULL)
    }
  }, add = TRUE)

  for (key in names(sources)) {
    con <- query_synergy_cooccurrence_open(sources[[key]])
    if (!is.null(con)) {
      con_map[[key]] <- con
      totals[[key]] <- query_synergy_cooccurrence_total_decks(con)
    }
  }
  if (length(con_map) == 0L) return(groups)

  # Per-call cache keyed by sorted lowercase names.
  cache <- new.env(parent = emptyenv())

  lapply(groups, function(group) {
    members <- query_synergy_to_list(group$members)
    names_vec <- vapply(members, function(m) query_api_scalar(m$name, default = ""), character(1))
    names_vec <- names_vec[nzchar(names_vec)]
    if (length(names_vec) == 0L) return(group)
    key <- paste(sort(unique(tolower(names_vec))), collapse = "|")

    cooc <- list()
    for (src in names(con_map)) {
      cache_key <- paste0(src, "::", key)
      if (exists(cache_key, envir = cache, inherits = FALSE)) {
        n_decks <- get(cache_key, envir = cache, inherits = FALSE)
      } else {
        n_decks <- query_synergy_cooccurrence_count(con_map[[src]], names_vec)
        assign(cache_key, n_decks, envir = cache)
      }
      cooc[[src]] <- list(
        decks = as.integer(n_decks),
        total = as.integer(totals[[src]] %||% 0L)
      )
    }
    group$cooccurrence <- cooc
    group
  })
}
