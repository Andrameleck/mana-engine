# =============================================================================
# Commander Spellbook combo matching for synergy group scoring.
#
# The spellbook SQLite database catalogues known combos, each as a "deck":
#   decks(id, title, description, produces)
#   deck_cards(deck_id, card_name, ...)
#
# For a synergy group, we check whether its members contain a known Spellbook
# combo and, if so, apply a score bonus and attach the combo details.
#
# Match types (checked in priority order):
#   exact     – group cards == combo cards (all pieces present, no extras)
#   contains  – group ⊇ combo (group has all combo pieces + more)
#   partial   – ≥2 shared cards with a combo of ≥3 pieces (weak signal only)
#
# Score bonus applied to group$total_score (0-100 scale):
#   exact:    +15
#   contains: +10
#   partial:  +4
# =============================================================================

# Internal: resolve default DB path.
.spellbook_default_db_path <- function() {
  query_synergy_cooccurrence_db_path("spellbook")
}

# Load all Spellbook combos into memory. Memoised per session.
query_synergy_spellbook_combos_load <- local({
  cache <- NULL
  function(db_path = NULL) {
    if (!is.null(cache)) return(cache)
    if (is.null(db_path) || !nzchar(db_path)) {
      db_path <- .spellbook_default_db_path()
    }
    if (!nzchar(db_path) || !file.exists(db_path)) {
      cache <<- list()
      return(cache)
    }
    con <- tryCatch(
      DBI::dbConnect(RSQLite::SQLite(), db_path),
      error = function(e) NULL
    )
    if (is.null(con)) {
      cache <<- list()
      return(cache)
    }
    on.exit(tryCatch(DBI::dbDisconnect(con), error = function(e) NULL), add = TRUE)

    decks_df <- tryCatch(
      DBI::dbGetQuery(con, "SELECT id, title, description, produces FROM decks"),
      error = function(e) NULL
    )
    cards_df <- tryCatch(
      DBI::dbGetQuery(con, "SELECT deck_id, card_name FROM deck_cards"),
      error = function(e) NULL
    )
    if (is.null(decks_df) || is.null(cards_df)) {
      cache <<- list()
      return(cache)
    }

    # Build per-combo card sets (lowercase, sorted).
    deck_ids <- unique(decks_df$id)
    combos <- lapply(seq_len(nrow(decks_df)), function(i) {
      did <- decks_df$id[[i]]
      cards_raw <- cards_df$card_name[cards_df$deck_id == did]
      cards_lower <- unique(tolower(trimws(cards_raw)))
      cards_lower <- cards_lower[nzchar(cards_lower)]
      key <- paste(sort(cards_lower), collapse = "|")
      list(
        id = did,
        title = decks_df$title[[i]],
        description = decks_df$description[[i]],
        produces = decks_df$produces[[i]],
        cards = cards_lower,
        key = key,
        size = length(cards_lower)
      )
    })
    # Drop combos with no cards (data quality guard).
    combos <- Filter(function(c) c$size > 0L, combos)
    cache <<- combos
    combos
  }
})

# Score bonus constants are read from the central registry. The legacy
# `.spellbook_bonus` symbol is preserved for tests that imported it directly.
# It is a function-shaped accessor to defer loading until the registry exists.
.spellbook_bonus <- list(exact = 15L, contains = 10L, partial = 4L)
.spellbook_bonus_table <- function() {
  tbl <- tryCatch(query_synergy_spellbook_bonus_tbl(), error = function(e) NULL)
  if (is.list(tbl) && length(tbl) > 0L) tbl else .spellbook_bonus
}

# For a group (list of card names), find matching Spellbook combos.
# Returns a list of match records sorted by priority (exact > contains > partial).
query_synergy_spellbook_match_group <- function(card_names, combos = NULL) {
  if (is.null(combos)) combos <- query_synergy_spellbook_combos_load()
  if (length(combos) == 0L || length(card_names) == 0L) return(list())

  group_lower <- unique(tolower(trimws(card_names)))
  group_lower <- group_lower[nzchar(group_lower)]
  if (length(group_lower) == 0L) return(list())
  group_set <- new.env(hash = TRUE, parent = emptyenv())
  for (n in group_lower) assign(n, TRUE, envir = group_set)
  group_key <- paste(sort(group_lower), collapse = "|")
  group_size <- length(group_lower)

  matches <- list()
  for (combo in combos) {
    if (combo$size == 0L) next
    shared <- sum(vapply(combo$cards, function(n) exists(n, envir = group_set, inherits = FALSE), logical(1)))

    match_type <- if (combo$key == group_key) {
      "exact"
    } else if (shared == combo$size && combo$size <= group_size) {
      "contains"
    } else if (shared >= 2L && combo$size >= 3L) {
      "partial"
    } else {
      next
    }
    bonus <- .spellbook_bonus_table()[[match_type]]
    matches[[length(matches) + 1L]] <- list(
      id = combo$id,
      title = query_api_scalar(combo$title, default = ""),
      produces = query_api_scalar(combo$produces, default = ""),
      description = query_api_scalar(combo$description, default = ""),
      match_type = match_type,
      bonus = bonus,
      shared_cards = shared,
      combo_size = combo$size
    )
  }
  if (length(matches) == 0L) return(list())

  # Sort: exact first, then contains, then partial; within each type by shared desc.
  priority <- c(exact = 1L, contains = 2L, partial = 3L)
  ord <- order(
    vapply(matches, function(m) priority[[m$match_type]], integer(1)),
    vapply(matches, function(m) -m$shared_cards, integer(1))
  )
  matches[ord]
}

# Annotate groups with Spellbook combo matches and apply score bonus.
# `groups` must be a list of group objects with `$members[[i]]$name` fields.
query_synergy_spellbook_annotate_groups <- function(groups) {
  if (!is.list(groups) || length(groups) == 0L) return(groups)
  combos <- query_synergy_spellbook_combos_load()
  if (length(combos) == 0L) return(groups)

  lapply(groups, function(group) {
    members <- query_synergy_to_list(group$members)
    card_names <- vapply(members, function(m) query_api_scalar(m$name, default = ""), character(1))
    card_names <- card_names[nzchar(card_names)]
    if (length(card_names) == 0L) return(group)

    all_matches <- query_synergy_spellbook_match_group(card_names, combos)
    if (length(all_matches) == 0L) return(group)

    # Best bonus = maximum over all matches (can't double-count).
    best_bonus <- max(vapply(all_matches, function(m) m$bonus, integer(1)))
    best_match <- all_matches[[which.max(vapply(all_matches, function(m) m$bonus, integer(1)))]]
    old_score <- suppressWarnings(as.numeric(group$total_score))
    if (is.finite(old_score)) {
      # Record the base score (before any modifier) once and store the
      # spellbook delta in score_modifiers so the breakdown stays auditable.
      if (is.null(group$score_base)) {
        group$score_base <- as.integer(round(old_score))
      }
      modifiers <- if (is.list(group$score_modifiers)) group$score_modifiers else list()
      modifiers$spellbook <- list(
        amount = as.integer(best_bonus),
        match_type = best_match$match_type,
        combo_title = best_match$title,
        combo_id = best_match$id
      )
      group$score_modifiers <- modifiers
      group$total_score <- min(100L, group$score_base +
                                 sum(vapply(modifiers, function(m) as.integer(m$amount %||% 0L), integer(1))))
    }

    # Expose top matches (cap at 5 to keep response lean).
    group$spellbook_matches <- utils::head(all_matches, 5L)
    group
  })
}
