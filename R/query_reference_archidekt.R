# Archidekt deck reference integration
#
# Archidekt exposes a public JSON REST API for individual decks.
# No authentication required for public decks.
#
# API endpoint:
#   GET https://archidekt.com/api/decks/{id}/       — full deck with cards
#   GET https://archidekt.com/api/decks/{id}/small/ — metadata only (faster)
#
# deckFormat codes (not exhaustive):
#   1 = Standard, 2 = Modern, 3 = Commander / EDH, 4 = Legacy
#   5 = Vintage, 6 = Pauper, 7 = Limited, 8 = Frontier
#   9 = Future Standard, 10 = Penny Dreadful, 11 = 1v1 Commander
#   13 = Oathbreaker, 14 = Historic, 17 = Pioneer
#
# Deck IDs are sequential integers starting at 1. Upper bound is currently
# in the low-8-million range (as of 2026).

# ── helpers ───────────────────────────────────────────────────────────────────

archidekt_fetch_json <- function(url) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    return(list(ok = FALSE, error = "jsonlite package required"))
  }
  raw <- tryCatch(
    paste(readLines(url, warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
    error = function(e) ""
  )
  if (!nzchar(raw)) {
    return(list(ok = FALSE, error = "archidekt unavailable", url = url))
  }
  payload <- tryCatch(
    jsonlite::fromJSON(raw, simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (is.null(payload)) {
    return(list(ok = FALSE, error = "invalid JSON response", url = url))
  }
  list(ok = TRUE, payload = payload, url = url)
}

archidekt_deck_format_label <- function(code) {
  labels <- c(
    "1"  = "Standard",
    "2"  = "Modern",
    "3"  = "Commander",
    "4"  = "Legacy",
    "5"  = "Vintage",
    "6"  = "Pauper",
    "7"  = "Limited",
    "8"  = "Frontier",
    "9"  = "Future Standard",
    "10" = "Penny Dreadful",
    "11" = "1v1 Commander",
    "13" = "Oathbreaker",
    "14" = "Historic",
    "17" = "Pioneer"
  )
  key <- as.character(code %||% "")
  unname(labels[key] %||% key)
}

archidekt_empty_cards_df <- function() {
  data.frame(
    deck_id      = integer(0),
    deck_url     = character(0),
    deck_title   = character(0),
    deck_author  = character(0),
    deck_format  = character(0),
    deck_date    = character(0),
    section      = character(0),
    quantity     = integer(0),
    card_name    = character(0),
    scryfall_id  = character(0),
    stringsAsFactors = FALSE
  )
}

# ── public functions ──────────────────────────────────────────────────────────

#' Fetch metadata for an Archidekt deck (no cards)
#'
#' @param deck_id Integer or string deck ID.
#' @return List with ok, source, deck_id, name, format, owner, updated_at.
query_archidekt_deck_small <- function(deck_id) {
  id <- suppressWarnings(as.integer(deck_id))
  if (is.na(id) || id < 1L) {
    return(query_api_error("deck_id must be a positive integer"))
  }

  url <- sprintf("https://archidekt.com/api/decks/%d/small/?format=json", id)
  result <- archidekt_fetch_json(url)
  if (!isTRUE(result$ok)) {
    return(result)
  }

  p <- result$payload
  if (!is.null(p$error)) {
    return(query_api_error(as.character(p$error), deck_id = id))
  }

  list(
    ok         = TRUE,
    source     = "archidekt_small",
    deck_id    = id,
    deck_url   = sprintf("https://archidekt.com/decks/%d", id),
    name       = trimws(as.character(p$name %||% "")),
    format     = archidekt_deck_format_label(p$deckFormat),
    format_code = as.integer(p$deckFormat %||% 0L),
    owner      = trimws(as.character((p$owner %||% list())$username %||% "")),
    created_at = trimws(as.character(p$createdAt %||% "")),
    updated_at = trimws(as.character(p$updatedAt %||% "")),
    private    = isTRUE(p$private),
    unlisted   = isTRUE(p$unlisted)
  )
}

#' Fetch a full Archidekt deck with its card list
#'
#' @param deck_id Integer or string deck ID.
#' @return List with ok, source, deck_id, deck_url, title, format, owner,
#'   updated_at, card_count, cards (data.frame).
query_archidekt_fetch_deck <- function(deck_id) {
  id <- suppressWarnings(as.integer(deck_id))
  if (is.na(id) || id < 1L) {
    return(query_api_error("deck_id must be a positive integer"))
  }

  url <- sprintf("https://archidekt.com/api/decks/%d/?format=json", id)
  result <- archidekt_fetch_json(url)
  if (!isTRUE(result$ok)) {
    return(result)
  }

  p <- result$payload
  if (!is.null(p$error)) {
    return(query_api_error(as.character(p$error), deck_id = id))
  }

  deck_title  <- trimws(as.character(p$name %||% ""))
  deck_format <- archidekt_deck_format_label(p$deckFormat)
  deck_owner  <- trimws(as.character((p$owner %||% list())$username %||% ""))
  deck_date   <- trimws(as.character(p$updatedAt %||% ""))
  deck_url    <- sprintf("https://archidekt.com/decks/%d", id)

  cards_raw <- p$cards %||% list()

  card_rows <- lapply(cards_raw, function(entry) {
    qty <- suppressWarnings(as.integer(entry$quantity %||% 1L))
    if (is.na(qty) || qty < 1L) qty <- 1L

    card        <- entry$card %||% list()
    oracle_card <- card$oracleCard %||% list()
    card_name   <- trimws(as.character(oracle_card$name %||% card$displayName %||% ""))
    scryfall_id <- trimws(as.character(card$uid %||% oracle_card$uid %||% ""))

    categories <- entry$categories %||% list()
    section <- if (length(categories) > 0L) {
      trimws(as.character(categories[[1L]]))
    } else {
      "Main"
    }

    if (!nzchar(card_name)) return(NULL)

    list(
      section     = section,
      quantity    = qty,
      card_name   = card_name,
      scryfall_id = scryfall_id
    )
  })
  card_rows <- Filter(Negate(is.null), card_rows)

  cards <- if (length(card_rows) == 0L) {
    archidekt_empty_cards_df()
  } else {
    n <- length(card_rows)
    data.frame(
      deck_id     = rep.int(id,          n),
      deck_url    = rep.int(deck_url,    n),
      deck_title  = rep.int(deck_title,  n),
      deck_author = rep.int(deck_owner,  n),
      deck_format = rep.int(deck_format, n),
      deck_date   = rep.int(deck_date,   n),
      section     = vapply(card_rows, `[[`, character(1), "section"),
      quantity    = vapply(card_rows, `[[`, integer(1),   "quantity"),
      card_name   = vapply(card_rows, `[[`, character(1), "card_name"),
      scryfall_id = vapply(card_rows, `[[`, character(1), "scryfall_id"),
      stringsAsFactors = FALSE
    )
  }

  list(
    ok         = TRUE,
    source     = "archidekt_deck",
    deck_id    = id,
    deck_url   = deck_url,
    title      = deck_title,
    format     = deck_format,
    owner      = deck_owner,
    updated_at = deck_date,
    private    = isTRUE(p$private),
    card_count = nrow(cards),
    cards      = cards
  )
}

#' Download a range of Archidekt decks into a SQLite database
#'
#' Scans deck IDs from \code{min_id} to \code{max_id} (or a provided vector)
#' and stores each valid public deck in a SQLite database with two tables:
#' \describe{
#'   \item{decks}{One row per deck: id, url, title, author, format, updated_at}
#'   \item{deck_cards}{One row per card slot: deck_id, section, quantity, card_name, scryfall_id}
#' }
#'
#' Progress is checkpointed so interrupted runs can resume.
#'
#' @param db_path Path to the SQLite file. Created if absent.
#' @param deck_ids Optional integer vector of specific IDs to fetch.
#'   If NULL, scans \code{min_id}:\code{max_id}.
#' @param min_id Lower bound for sequential scan. Default 1.
#' @param max_id Upper bound for sequential scan. Default 9000000.
#' @param request_delay Seconds to wait between requests. Default 0.1.
#' @param overwrite If TRUE, re-fetches decks already in the database.
#' @param verbose Print progress messages. Default TRUE.
#' @return List with ok, db_path, inserted, skipped, errors.
query_archidekt_download_decks_sqlite <- function(db_path,
                                                   deck_ids     = NULL,
                                                   min_id       = 1L,
                                                   max_id       = 9000000L,
                                                   request_delay = 0.1,
                                                   overwrite    = FALSE,
                                                   verbose      = TRUE) {
  if (!requireNamespace("DBI",      quietly = TRUE) ||
      !requireNamespace("RSQLite",  quietly = TRUE)) {
    return(query_api_error("database dependencies missing (DBI/RSQLite)"))
  }

  target_path <- trimws(as.character(db_path))
  if (!nzchar(target_path)) {
    return(query_api_error("db_path is required"))
  }

  con <- tryCatch(
    DBI::dbConnect(RSQLite::SQLite(), target_path),
    error = function(e) NULL
  )
  if (is.null(con)) {
    return(query_api_error(sprintf("cannot open database: %s", target_path)))
  }
  on.exit(try(DBI::dbDisconnect(con), silent = TRUE), add = TRUE)

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS decks (
      id         INTEGER PRIMARY KEY,
      url        TEXT,
      title      TEXT,
      author     TEXT,
      format     TEXT,
      updated_at TEXT,
      fetched_at TEXT
    )
  ")
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS deck_cards (
      deck_id     INTEGER,
      section     TEXT,
      quantity    INTEGER,
      card_name   TEXT,
      scryfall_id TEXT
    )
  ")
  DBI::dbExecute(con, "
    CREATE INDEX IF NOT EXISTS idx_deck_cards_deck_id ON deck_cards (deck_id)
  ")

  ids_to_scan <- if (!is.null(deck_ids)) {
    as.integer(deck_ids)
  } else {
    seq.int(as.integer(min_id), as.integer(max_id))
  }

  existing_ids <- integer(0)
  if (!isTRUE(overwrite)) {
    existing_ids <- DBI::dbGetQuery(con, "SELECT id FROM decks")$id
  }
  ids_to_scan <- ids_to_scan[!ids_to_scan %in% existing_ids]

  n_total  <- length(ids_to_scan)
  inserted <- 0L
  skipped  <- 0L
  errors   <- 0L

  if (isTRUE(verbose)) {
    message(sprintf("Archidekt: %d IDs to scan | db: %s", n_total, target_path))
  }

  for (i in seq_along(ids_to_scan)) {
    id <- ids_to_scan[[i]]
    if (i > 1L && request_delay > 0) Sys.sleep(request_delay)

    result <- query_archidekt_fetch_deck(id)

    if (!isTRUE(result$ok)) {
      skipped <- skipped + 1L
      next
    }

    if (isTRUE(result$private)) {
      skipped <- skipped + 1L
      next
    }

    ts <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

    tryCatch({
      DBI::dbExecute(con,
        "INSERT OR REPLACE INTO decks (id, url, title, author, format, updated_at, fetched_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)",
        params = list(result$deck_id, result$deck_url, result$title,
                      result$owner, result$format, result$updated_at, ts)
      )

      if (nrow(result$cards) > 0L) {
        DBI::dbExecute(con,
          "DELETE FROM deck_cards WHERE deck_id = ?",
          params = list(result$deck_id)
        )
        DBI::dbAppendTable(con, "deck_cards", result$cards[, c("deck_id","section","quantity","card_name","scryfall_id")])
      }

      inserted <- inserted + 1L

      if (isTRUE(verbose) && inserted %% 100L == 0L) {
        message(sprintf("  [%d/%d]  inserted=%d  skipped=%d  errors=%d",
                        i, n_total, inserted, skipped, errors))
      }
    }, error = function(e) {
      errors <<- errors + 1L
      if (isTRUE(verbose)) {
        message(sprintf("  ERROR id=%d: %s", id, conditionMessage(e)))
      }
    })
  }

  if (isTRUE(verbose)) {
    message(sprintf("Archidekt done — inserted=%d  skipped=%d  errors=%d",
                    inserted, skipped, errors))
  }

  list(
    ok       = TRUE,
    source   = "archidekt",
    db_path  = target_path,
    inserted = inserted,
    skipped  = skipped,
    errors   = errors
  )
}
