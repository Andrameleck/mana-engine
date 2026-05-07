# TappedOut deck reference integration
#
# TappedOut is a community deck builder at https://tappedout.net.
#
# The CSV export endpoint is publicly accessible without authentication:
#   https://tappedout.net/mtg-decks/<slug>/?fmt=csv
#
# CSV columns: Board, Qty, Name, Printing, Foil, Alter, Signed, Condition, Language, Commander
# Board values: main, side, maybe, acquire, maybeboard, considering
#
# No session cookie required.

# ── helpers ───────────────────────────────────────────────────────────────────

tappedout_empty_cards_df <- function() {
  data.frame(
    deck_slug   = character(0),
    deck_url    = character(0),
    deck_title  = character(0),
    deck_author = character(0),
    deck_format = character(0),
    section     = character(0),
    quantity    = integer(0),
    card_name   = character(0),
    stringsAsFactors = FALSE
  )
}

tappedout_board_to_section <- function(board) {
  switch(tolower(trimws(board)),
    "main"        = "Main",
    "side"        = "Sideboard",
    "maybe"       = "Maybeboard",
    "maybeboard"  = "Maybeboard",
    "acquire"     = "Acquire",
    "considering" = "Considering",
    "Main"
  )
}

# Minimal CSV line parser handling double-quoted fields with embedded commas
.tappedout_parse_csv_line <- function(line) {
  fields  <- character(0)
  current <- ""
  in_quotes <- FALSE
  nc <- nchar(line)
  i  <- 1L
  while (i <= nc) {
    ch <- substr(line, i, i)
    if (in_quotes) {
      if (ch == '"') {
        if (i < nc && substr(line, i + 1L, i + 1L) == '"') {
          current <- paste0(current, '"'); i <- i + 1L
        } else {
          in_quotes <- FALSE
        }
      } else {
        current <- paste0(current, ch)
      }
    } else {
      if      (ch == '"') { in_quotes <- TRUE }
      else if (ch == ',') { fields <- c(fields, current); current <- "" }
      else                { current <- paste0(current, ch) }
    }
    i <- i + 1L
  }
  c(fields, current)
}

tappedout_parse_csv_export <- function(text, deck_slug = "", deck_url = "") {
  if (!nzchar(trimws(text))) {
    return(query_api_error("empty CSV export", deck_url = deck_url))
  }
  lines <- unlist(strsplit(text, "\n", fixed = TRUE))
  lines <- lines[nzchar(trimws(lines))]
  if (length(lines) < 2L) {
    return(query_api_error("CSV has no data rows", deck_url = deck_url))
  }

  header    <- trimws(strsplit(lines[[1L]], ",", fixed = TRUE)[[1L]])
  header_lc <- tolower(header)
  col_board <- match("board",      header_lc)
  col_qty   <- match("qty",        header_lc)
  col_name  <- match("name",       header_lc)
  col_cmd   <- match("commander",  header_lc)

  if (is.na(col_name)) {
    return(query_api_error("CSV missing Name column", deck_url = deck_url))
  }

  card_rows  <- list()
  commander  <- character(0)

  for (line in lines[-1L]) {
    fields <- .tappedout_parse_csv_line(line)
    board  <- if (!is.na(col_board) && col_board <= length(fields)) trimws(fields[[col_board]]) else "main"
    qty    <- if (!is.na(col_qty)   && col_qty   <= length(fields)) suppressWarnings(as.integer(trimws(fields[[col_qty]]))) else 1L
    name   <- if (col_name <= length(fields)) trimws(fields[[col_name]]) else ""
    is_cmd <- !is.na(col_cmd) && col_cmd <= length(fields) &&
              tolower(trimws(fields[[col_cmd]])) %in% c("true", "1", "yes")

    if (!nzchar(name)) next
    if (is.na(qty) || qty < 1L) qty <- 1L
    section <- tappedout_board_to_section(board)
    if (section %in% c("Maybeboard", "Acquire", "Considering")) next
    if (is_cmd) commander <- c(commander, name)

    card_rows[[length(card_rows) + 1L]] <- list(
      section   = section,
      quantity  = qty,
      card_name = name
    )
  }

  url_val    <- if (nzchar(deck_url)) deck_url else
    if (nzchar(deck_slug)) sprintf("https://tappedout.net/mtg-decks/%s/", deck_slug) else ""
  deck_title <- if (length(commander) > 0L) paste(commander, collapse = " & ") else deck_slug

  cards <- if (length(card_rows) == 0L) {
    tappedout_empty_cards_df()
  } else {
    n <- length(card_rows)
    data.frame(
      deck_slug   = rep.int(deck_slug,  n),
      deck_url    = rep.int(url_val,    n),
      deck_title  = rep.int(deck_title, n),
      deck_author = rep.int("",         n),
      deck_format = rep.int("",         n),
      section     = vapply(card_rows, `[[`, character(1), "section"),
      quantity    = vapply(card_rows, `[[`, integer(1),   "quantity"),
      card_name   = vapply(card_rows, `[[`, character(1), "card_name"),
      stringsAsFactors = FALSE
    )
  }

  list(
    ok         = TRUE,
    source     = "tappedout_csv",
    deck_slug  = deck_slug,
    deck_url   = url_val,
    title      = deck_title,
    card_count = nrow(cards),
    cards      = cards
  )
}

# ── public functions ──────────────────────────────────────────────────────────

#' Fetch a TappedOut deck by its URL slug (no auth required)
#'
#' Uses the public CSV export endpoint.
#'
#' @param deck_slug The slug from the TappedOut URL, e.g. \code{"aggrocrates"}.
#' @return Parsed deck list or error payload.
query_tappedout_fetch_deck <- function(deck_slug) {
  slug <- trimws(as.character(deck_slug %||% ""))
  if (!nzchar(slug)) return(query_api_error("deck_slug is required"))

  url <- sprintf("https://tappedout.net/mtg-decks/%s/?fmt=csv", slug)
  raw <- tryCatch(
    paste(readLines(url, warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
    error = function(e) ""
  )

  if (!nzchar(raw) || grepl("<!DOCTYPE html", raw, fixed = TRUE)) {
    return(query_api_error(
      sprintf("TappedOut deck not accessible: %s", slug),
      source = "tappedout", url = url
    ))
  }

  deck_url <- sprintf("https://tappedout.net/mtg-decks/%s/", slug)
  tappedout_parse_csv_export(raw, deck_slug = slug, deck_url = deck_url)
}

#' Download TappedOut decks into a SQLite database (no auth required)
#'
#' @param db_path Path to the SQLite file.
#' @param deck_slugs Character vector of TappedOut URL slugs.
#' @param request_delay Seconds between requests. Default 1.
#' @param overwrite Re-fetch decks already in the database. Default FALSE.
#' @param verbose Print progress. Default TRUE.
#' @return List with ok, db_path, inserted, skipped, errors.
query_tappedout_download_decks_sqlite <- function(db_path,
                                                   deck_slugs,
                                                   request_delay = 1.0,
                                                   overwrite     = FALSE,
                                                   verbose       = TRUE) {
  if (!requireNamespace("DBI",     quietly = TRUE) ||
      !requireNamespace("RSQLite", quietly = TRUE)) {
    return(query_api_error("database dependencies missing (DBI/RSQLite)"))
  }

  target_path <- trimws(as.character(db_path))
  if (!nzchar(target_path)) return(query_api_error("db_path is required"))

  con <- tryCatch(DBI::dbConnect(RSQLite::SQLite(), target_path), error = function(e) NULL)
  if (is.null(con)) {
    return(query_api_error(sprintf("cannot open database: %s", target_path)))
  }
  on.exit(try(DBI::dbDisconnect(con), silent = TRUE), add = TRUE)

  DBI::dbExecute(con, "PRAGMA journal_mode = WAL")
  DBI::dbExecute(con, "PRAGMA busy_timeout = 5000")
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS decks (
      id TEXT PRIMARY KEY, url TEXT, title TEXT, author TEXT,
      format TEXT, updated_at TEXT, fetched_at TEXT
    )
  ")
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS deck_cards (
      deck_id TEXT, section TEXT, quantity INTEGER, card_name TEXT
    )
  ")
  DBI::dbExecute(con,
    "CREATE INDEX IF NOT EXISTS idx_deck_cards_deck_id ON deck_cards (deck_id)"
  )

  slugs <- as.character(deck_slugs)
  if (!isTRUE(overwrite)) {
    existing_ids <- DBI::dbGetQuery(con, "SELECT id FROM decks")$id
    slugs <- slugs[!slugs %in% existing_ids]
  }

  n_total  <- length(slugs)
  inserted <- 0L
  skipped  <- length(as.character(deck_slugs)) - n_total
  errors   <- 0L

  if (isTRUE(verbose)) {
    cat(sprintf("TappedOut: %d slugs to fetch | db: %s\n", n_total, target_path))
  }

  for (i in seq_along(slugs)) {
    slug <- slugs[[i]]
    if (i > 1L && request_delay > 0) Sys.sleep(request_delay)

    result <- query_tappedout_fetch_deck(slug)

    if (!isTRUE(result$ok)) {
      errors <- errors + 1L
      if (isTRUE(verbose)) cat(sprintf("  ERROR %s: %s\n", slug, result$error %||% "unknown"))
      next
    }

    ts <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    tryCatch({
      DBI::dbExecute(con,
        "INSERT OR REPLACE INTO decks (id, url, title, author, format, updated_at, fetched_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)",
        params = list(slug, result$deck_url, result$title, "", "", "", ts)
      )
      DBI::dbExecute(con, "DELETE FROM deck_cards WHERE deck_id = ?", params = list(slug))
      if (nrow(result$cards) > 0L) {
        DBI::dbAppendTable(con, "deck_cards", data.frame(
          deck_id   = slug,
          section   = result$cards$section,
          quantity  = result$cards$quantity,
          card_name = result$cards$card_name,
          stringsAsFactors = FALSE
        ))
      }
      inserted <- inserted + 1L
      if (isTRUE(verbose)) {
        cat(sprintf("  [%d/%d] %s — %d cards\n", i, n_total, slug, nrow(result$cards)))
      }
    }, error = function(e) {
      errors <<- errors + 1L
      if (isTRUE(verbose)) cat(sprintf("  ERROR inserting %s: %s\n", slug, conditionMessage(e)))
    })
  }

  if (isTRUE(verbose)) {
    cat(sprintf("Done — inserted=%d skipped=%d errors=%d\n", inserted, skipped, errors))
  }
  list(ok = TRUE, source = "tappedout", db_path = target_path,
       inserted = inserted, skipped = skipped, errors = errors)
}
