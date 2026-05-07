#!/usr/bin/env Rscript
# Download Commander Spellbook combo variants and store as "core" decks.
#
# Usage from console:
#   spellbook_queries <- c("infinite mana", "draw combo")
#   source("inst/decks/download_spellbook_combos.R")
#
# Or with options:
#   spellbook_queries <- c("infinite mana", "draw combo")
#   spellbook_limit <- 50
#   spellbook_request_delay <- 0.5
#   source("inst/decks/download_spellbook_combos.R")
#
# Environment variables:
#   SPELLBOOK_DB_PATH      Path to the SQLite file.
#                          Default: inst/decks/spellbook/spellbook.sqlite
#   SPELLBOOK_QUERIES      Comma-separated search queries.
#                          Example: "infinite mana,draw combo"
#   SPELLBOOK_QUERIES_FILE Path to file with one query per line.
#   SPELLBOOK_LIMIT        Max variants per query. Default: 40
#   SPELLBOOK_REQUEST_DELAY Seconds between queries. Default: 0.5
#   SPELLBOOK_OVERWRITE    Re-fetch already-stored combos. Default: false
#   SPELLBOOK_VERBOSE      Print progress. Default: true

if (!exists("devtools_already_loaded")) {
  suppressMessages(devtools::load_all(".", quiet = TRUE))
}

db_dir <- file.path("inst", "decks", "spellbook")
dir.create(db_dir, recursive = TRUE, showWarnings = FALSE)
db_path <- if (exists("spellbook_db_path")) {
  spellbook_db_path
} else {
  Sys.getenv("SPELLBOOK_DB_PATH", unset = file.path(db_dir, "spellbook.sqlite"))
}

# Vérifier que le répertoire existe
if (!dir.exists(dirname(db_path))) {
  dir.create(dirname(db_path), recursive = TRUE, showWarnings = FALSE)
}

queries_file <- if (exists("spellbook_queries_file")) {
  spellbook_queries_file
} else {
  trimws(Sys.getenv("SPELLBOOK_QUERIES_FILE", unset = ""))
}

queries_csv <- if (exists("spellbook_queries_csv")) {
  spellbook_queries_csv
} else {
  trimws(Sys.getenv("SPELLBOOK_QUERIES", unset = ""))
}

read_queries_file <- function(path) {
  raw <- trimws(readLines(path, warn = FALSE))
  raw[nzchar(raw)]
}

queries <- character(0)

# Si spellbook_queries existe comme variable R (vecteur)
if (exists("spellbook_queries") && is.character(spellbook_queries)) {
  queries <- c(queries, trimws(spellbook_queries))
}

if (nzchar(queries_file)) {
  if (!file.exists(queries_file)) {
    stop(sprintf("SPELLBOOK_QUERIES_FILE not found: %s", queries_file))
  }
  queries <- c(queries, read_queries_file(queries_file))
}
if (nzchar(queries_csv)) {
  queries <- c(queries, trimws(strsplit(queries_csv, ",", fixed = TRUE)[[1L]]))
}

fetch_all <- if (exists("spellbook_fetch_all")) {
  isTRUE(spellbook_fetch_all)
} else {
  tolower(Sys.getenv("SPELLBOOK_FETCH_ALL", unset = "false")) %in% c("1", "true", "yes")
}

queries <- unique(queries[nzchar(queries)])
if (length(queries) == 0L && !fetch_all) {
  stop("Provide queries via SPELLBOOK_QUERIES_FILE, SPELLBOOK_QUERIES, or set spellbook_fetch_all <- TRUE")
}
if (fetch_all) {
  queries <- c("")  # sentinel: empty query = no filter
}

start_offset <- if (exists("spellbook_start_offset")) {
  suppressWarnings(as.integer(spellbook_start_offset))
} else {
  suppressWarnings(as.integer(Sys.getenv("SPELLBOOK_START_OFFSET", unset = "0")))
}
if (is.na(start_offset) || start_offset < 0L) start_offset <- 0L

limit <- if (exists("spellbook_limit")) {
  spellbook_limit
} else {
  suppressWarnings(as.integer(Sys.getenv("SPELLBOOK_LIMIT", unset = "40")))
}
if (is.na(limit) || limit < 1L) {
  limit <- 40L
}

request_delay <- if (exists("spellbook_request_delay")) {
  spellbook_request_delay
} else {
  suppressWarnings(as.numeric(Sys.getenv("SPELLBOOK_REQUEST_DELAY", unset = "0.5")))
}
if (!is.finite(request_delay) || is.na(request_delay) || request_delay < 0) {
  request_delay <- 0.5
}

overwrite <- if (exists("spellbook_overwrite")) {
  spellbook_overwrite
} else {
  tolower(Sys.getenv("SPELLBOOK_OVERWRITE", unset = "false")) %in%
    c("1", "true", "yes", "y", "on")
}

verbose <- if (exists("spellbook_verbose")) {
  spellbook_verbose
} else {
  !tolower(Sys.getenv("SPELLBOOK_VERBOSE", unset = "true")) %in%
    c("0", "false", "no", "n", "off")
}

cat("=== Commander Spellbook combos downloader ===\n")
cat(sprintf("DB path         : %s\n", db_path))
cat(sprintf("Queries         : %d\n", length(queries)))
cat(sprintf("Limit per query : %d\n", limit))
cat(sprintf("Request delay   : %.2f s\n", request_delay))
cat(sprintf("Overwrite       : %s\n\n", if (overwrite) "TRUE" else "FALSE"))

if (!requireNamespace("DBI",     quietly = TRUE) ||
    !requireNamespace("RSQLite", quietly = TRUE)) {
  stop("database dependencies missing (DBI/RSQLite)")
}

# Créer/ouvrir la connexion
cat("Opening database connection...\n")
con <- DBI::dbConnect(RSQLite::SQLite(), db_path, timeout = 30L)
cat(sprintf("Connection valid: %s\n\n", DBI::dbIsValid(con)))

# Créer les tables
DBI::dbExecute(con, "PRAGMA journal_mode = WAL")
DBI::dbExecute(con, "PRAGMA busy_timeout = 5000")

DBI::dbExecute(con, "
  CREATE TABLE IF NOT EXISTS decks (
    id          TEXT PRIMARY KEY,
    url         TEXT,
    title       TEXT,
    author      TEXT,
    format      TEXT,
    description TEXT,
    produces    TEXT,
    updated_at  TEXT,
    fetched_at  TEXT
  )
")
# Migration: add produces column if not present in older DB
existing_cols <- DBI::dbGetQuery(con, "PRAGMA table_info(decks)")$name
if (!"produces" %in% existing_cols) {
  DBI::dbExecute(con, "ALTER TABLE decks ADD COLUMN produces TEXT DEFAULT ''")
}
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

total_combos <- 0L
total_inserted <- 0L
total_errors <- 0L

for (i in seq_along(queries)) {
  query <- queries[[i]]
  if (i > 1L && request_delay > 0) {
    Sys.sleep(request_delay)
  }

  if (isTRUE(verbose)) {
    cat(sprintf("[%d/%d] Query: %s\n", i, length(queries), query))
  }

  # Build initial URL: apply start_offset for fetch_all resume
  if (fetch_all && start_offset > 0L) {
    init_url <- sprintf(
      "https://backend.commanderspellbook.com/variants/?limit=%d&offset=%d",
      limit, start_offset
    )
    if (isTRUE(verbose)) cat(sprintf("  Resuming from offset %d\n", start_offset))
    result <- query_spellbook_page_url(init_url)
  } else {
    result <- query_spellbook_variants(q = if (nzchar(query)) query else "", limit = as.character(limit))
  }
  if (!isTRUE(result$ok)) {
    if (isTRUE(verbose)) {
      cat(sprintf("  ERROR: %s\n", result$error %||% "unknown"))
    }
    total_errors <- total_errors + 1L
    next
  }

  if (!is.na(result$total) && isTRUE(verbose)) {
    cat(sprintf("  Total available: %d\n", result$total))
  }

  page_num <- 1L
  next_url <- result$next_url %||% ""

  repeat {
    variants <- result$results %||% list()
    if (length(variants) == 0L) {
      if (isTRUE(verbose)) cat("  No variants on this page.\n")
      break
    }

    if (isTRUE(verbose)) {
      cat(sprintf("  Page %d: %d variants\n", page_num, length(variants)))
    }

  for (v in variants) {
    total_combos <- total_combos + 1L

    combo_id <- trimws(as.character(v$id %||% ""))
    if (!nzchar(combo_id)) {
      combo_id <- sprintf("spellbook_%d", total_combos)
    } else {
      combo_id <- sprintf("spellbook_%s", combo_id)
    }

    # "uses" contient les cartes, "of" contient les combo-results
    uses  <- v$uses  %||% list()
    combo_desc <- trimws(as.character(v$description %||% ""))
    combo_produces <- paste(
      vapply(v$produces %||% list(), function(p) trimws(as.character(p$feature$name %||% "")), character(1L)),
      collapse = ", "
    )

    # Construire le nom depuis les cartes
    card_names_for_title <- vapply(uses, function(u) {
      trimws(as.character(u$card$name %||% ""))
    }, character(1L))
    card_names_for_title <- card_names_for_title[nzchar(card_names_for_title)]
    combo_name <- if (length(card_names_for_title) > 0L) {
      paste(card_names_for_title, collapse = " + ")
    } else {
      combo_id
    }

    if (length(uses) == 0L) {
      if (isTRUE(verbose)) cat(sprintf("  Skipped %s: no cards\n", combo_id))
      next
    }

    card_rows <- list()
    for (u in uses) {
      card_name   <- trimws(as.character(u$card$name %||% ""))
      scryfall_id <- trimws(as.character(u$card$oracleId %||% ""))
      if (!nzchar(card_name)) next
      card_rows[[length(card_rows) + 1L]] <- list(
        card_name   = card_name,
        scryfall_id = scryfall_id
      )
    }

    if (length(card_rows) == 0L) next

    ts <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

    tryCatch({
      # Si overwrite=FALSE, skip les combos déjà présents
      if (!isTRUE(overwrite)) {
        already <- DBI::dbGetQuery(con,
          "SELECT 1 FROM decks WHERE id = ?",
          params = list(combo_id)
        )
        if (nrow(already) > 0L) {
          next
        }
      }

      DBI::dbExecute(con,
        "INSERT OR REPLACE INTO decks (id, url, title, author, format, description, produces, updated_at, fetched_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        params = list(combo_id, "", combo_name, "", "Spellbook Combo", combo_desc, combo_produces, "", ts)
      )

      # Toujours nettoyer les anciennes cartes avant de re-insérer
      DBI::dbExecute(con,
        "DELETE FROM deck_cards WHERE deck_id = ?",
        params = list(combo_id)
      )

      for (j in seq_along(card_rows)) {
        row <- card_rows[[j]]
        DBI::dbExecute(con,
          "INSERT INTO deck_cards (deck_id, section, quantity, card_name, scryfall_id)
           VALUES (?, ?, ?, ?, ?)",
          params = list(combo_id, "Core", 1L, row$card_name, row$scryfall_id)
        )
      }

      total_inserted <- total_inserted + 1L

    }, error = function(e) {
      total_errors <<- total_errors + 1L
      if (isTRUE(verbose)) {
        cat(sprintf("  ERROR inserting combo %s: %s\n", combo_id, conditionMessage(e)))
      }
    })
  }  # end for (v in variants)

    # Paginer si une page suivante existe
    if (!nzchar(next_url)) break
    if (request_delay > 0) Sys.sleep(request_delay)
    page_num <- page_num + 1L
    result <- query_spellbook_page_url(next_url)
    if (!isTRUE(result$ok)) {
      if (isTRUE(verbose)) cat(sprintf("  ERROR on page %d: %s\n", page_num, result$error %||% "unknown"))
      break
    }
    next_url <- result$next_url %||% ""
  }  # end repeat
}  # end for (i in seq_along(queries))

if (isTRUE(verbose)) {
  cat("\n")
}
cat(sprintf("Done — total_combos=%d inserted=%d errors=%d db=%s\n",
            total_combos, total_inserted, total_errors, db_path))

# Fermer la connexion explicitement
if (DBI::dbIsValid(con)) {
  DBI::dbDisconnect(con)
}
