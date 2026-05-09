# Moxfield deck reference integration
#
# Moxfield uses an unofficial JSON API (no public documentation).
# The API is protected by Cloudflare; direct server-side access is blocked.
#
# Status: UNAVAILABLE for automated server-side access.
#
# Cloudflare blocks curl / R's readLines unless a valid browser session
# cookie is provided. There is no official API key programme.
#
# Future options:
#   1. Use a Cloudflare-bypass library with a real browser driver (Playwright).
#   2. Request an official API key from Moxfield support.
#   3. Use user-supplied session cookies (requires manual login).
#
# The functions below are stubs that return a clear error rather than
# silently failing.

# \u2500\u2500 helpers \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

MOXFIELD_BLOCKED_MSG <- paste(
  "Moxfield API is protected by Cloudflare and cannot be accessed",
  "from server-side R without a valid browser session cookie.",
  "See R/query_reference_moxfield.R for options."
)

moxfield_empty_cards_df <- function() {
  data.frame(
    deck_id     = character(0),
    deck_url    = character(0),
    deck_title  = character(0),
    deck_author = character(0),
    deck_format = character(0),
    deck_date   = character(0),
    section     = character(0),
    quantity    = integer(0),
    card_name   = character(0),
    scryfall_id = character(0),
    stringsAsFactors = FALSE
  )
}

# \u2500\u2500 public functions \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

#' Fetch a Moxfield deck by its public hash ID
#'
#' @param deck_id The alphanumeric hash ID visible in the Moxfield URL.
#' @param session_cookie Optional Cloudflare session cookie string.
#'   Format: \code{"cf_clearance=<value>"}.
#' @return Error payload with instructions if no cookie is provided.
query_moxfield_fetch_deck <- function(deck_id, session_cookie = NULL) {
  id <- trimws(as.character(deck_id %||% ""))
  if (!nzchar(id)) {
    return(query_api_error("deck_id is required"))
  }

  cookie <- trimws(as.character(session_cookie %||% ""))
  if (!nzchar(cookie)) {
    return(query_api_error(MOXFIELD_BLOCKED_MSG, source = "moxfield"))
  }

  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    return(query_api_error("jsonlite package required"))
  }

  url <- sprintf("https://api2.moxfield.com/v2/decks/all/%s", utils::URLencode(id, reserved = TRUE))

  raw <- tryCatch({
    h <- c(
      "Accept"       = "application/json",
      "User-Agent"   = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36",
      "Cookie"       = cookie
    )
    paste(readLines(url, warn = FALSE, encoding = "UTF-8", n = -1L), collapse = "\n")
  }, error = function(e) "")

  if (!nzchar(raw)) {
    return(query_api_error("Moxfield request failed (still blocked?)", url = url))
  }

  payload <- tryCatch(
    jsonlite::fromJSON(raw, simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (is.null(payload)) {
    return(query_api_error("invalid Moxfield JSON response", url = url))
  }

  deck_title  <- trimws(as.character(payload$name %||% ""))
  deck_format <- trimws(as.character((payload$format %||% list())$name %||% ""))
  deck_owner  <- trimws(as.character((payload$createdByUser %||% list())$userName %||% ""))
  deck_date   <- trimws(as.character(payload$lastUpdatedAtUtc %||% ""))
  deck_url    <- sprintf("https://www.moxfield.com/decks/%s", id)

  boards <- payload$boards %||% list()
  section_names <- c(
    mainboard  = "Main",
    sideboard  = "Sideboard",
    maybeboard = "Maybeboard",
    commanders = "Commander",
    companions = "Companion",
    attractions = "Attraction",
    stickers   = "Sticker"
  )

  card_rows <- list()
  for (board_key in names(section_names)) {
    board <- boards[[board_key]] %||% list()
    entries <- board$cards %||% list()
    section_label <- section_names[[board_key]]

    for (entry in entries) {
      qty <- suppressWarnings(as.integer(entry$quantity %||% 1L))
      if (is.na(qty) || qty < 1L) qty <- 1L

      card        <- entry$card %||% list()
      card_name   <- trimws(as.character(card$name %||% ""))
      scryfall_id <- trimws(as.character(card$scryfall_id %||% card$id %||% ""))

      if (!nzchar(card_name)) next

      card_rows[[length(card_rows) + 1L]] <- list(
        section     = section_label,
        quantity    = qty,
        card_name   = card_name,
        scryfall_id = scryfall_id
      )
    }
  }

  cards <- if (length(card_rows) == 0L) {
    moxfield_empty_cards_df()
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
    source     = "moxfield_deck",
    deck_id    = id,
    deck_url   = deck_url,
    title      = deck_title,
    format     = deck_format,
    owner      = deck_owner,
    updated_at = deck_date,
    card_count = nrow(cards),
    cards      = cards
  )
}

#' Download Moxfield decks into a SQLite database
#'
#' Requires a valid Cloudflare session cookie. See \code{query_moxfield_fetch_deck}
#' for details. The database schema is identical to the Archidekt one.
#'
#' @param db_path Path to the SQLite file.
#' @param deck_ids Character vector of Moxfield hash IDs to fetch.
#' @param session_cookie Cloudflare session cookie string.
#' @param request_delay Seconds between requests. Default 0.5.
#' @param overwrite Re-fetch decks already in the database. Default FALSE.
#' @param verbose Print progress. Default TRUE.
#' @return List with ok, db_path, inserted, skipped, errors.
query_moxfield_download_decks_sqlite <- function(db_path,
                                                  deck_ids,
                                                  session_cookie = NULL,
                                                  request_delay  = 0.5,
                                                  overwrite      = FALSE,
                                                  verbose        = TRUE) {
  cookie <- trimws(as.character(session_cookie %||% ""))
  if (!nzchar(cookie)) {
    return(query_api_error(MOXFIELD_BLOCKED_MSG, source = "moxfield"))
  }

  if (!requireNamespace("DBI",     quietly = TRUE) ||
      !requireNamespace("RSQLite", quietly = TRUE)) {
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
      id         TEXT PRIMARY KEY,
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
      deck_id     TEXT,
      section     TEXT,
      quantity    INTEGER,
      card_name   TEXT,
      scryfall_id TEXT
    )
  ")
  DBI::dbExecute(con,
    "CREATE INDEX IF NOT EXISTS idx_deck_cards_deck_id ON deck_cards (deck_id)"
  )

  ids <- as.character(deck_ids)
  existing_ids <- character(0)
  if (!isTRUE(overwrite)) {
    existing_ids <- DBI::dbGetQuery(con, "SELECT id FROM decks")$id
  }
  ids <- ids[!ids %in% existing_ids]

  n_total  <- length(ids)
  inserted <- 0L
  skipped  <- 0L
  errors   <- 0L

  if (isTRUE(verbose)) {
    message(sprintf("Moxfield: %d IDs to fetch | db: %s", n_total, target_path))
  }

  for (i in seq_along(ids)) {
    id <- ids[[i]]
    if (i > 1L && request_delay > 0) Sys.sleep(request_delay)

    result <- query_moxfield_fetch_deck(id, session_cookie = cookie)

    if (!isTRUE(result$ok)) {
      errors <- errors + 1L
      if (isTRUE(verbose)) {
        message(sprintf("  ERROR id=%s: %s", id, result$error %||% "unknown"))
      }
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
        DBI::dbAppendTable(con, "deck_cards",
          result$cards[, c("deck_id","section","quantity","card_name","scryfall_id")]
        )
      }

      inserted <- inserted + 1L

      if (isTRUE(verbose) && inserted %% 50L == 0L) {
        message(sprintf("  [%d/%d]  inserted=%d  skipped=%d  errors=%d",
                        i, n_total, inserted, skipped, errors))
      }
    }, error = function(e) {
      errors <<- errors + 1L
    })
  }

  if (isTRUE(verbose)) {
    message(sprintf("Moxfield done -- inserted=%d  skipped=%d  errors=%d",
                    inserted, skipped, errors))
  }

  list(
    ok       = TRUE,
    source   = "moxfield",
    db_path  = target_path,
    inserted = inserted,
    skipped  = skipped,
    errors   = errors
  )
}
