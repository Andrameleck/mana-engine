#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)

db_path <- if (length(args) >= 1L) args[[1L]] else Sys.getenv(
  "ARCHIDEKT_DB_PATH",
  unset = file.path("inst", "decks", "archidekt.sqlite")
)

card_name <- if (length(args) >= 2L) args[[2L]] else Sys.getenv(
  "CARD_NAME",
  unset = "Sheoldred, the Apocalypse"
)

top_n <- if (length(args) >= 3L) suppressWarnings(as.integer(args[[3L]])) else
  suppressWarnings(as.integer(Sys.getenv("TOP_N", unset = "25")))
if (is.na(top_n) || top_n < 1L) {
  top_n <- 25L
}

if (!file.exists(db_path)) {
  stop(sprintf("Database not found: %s", db_path))
}

con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
on.exit(DBI::dbDisconnect(con), add = TRUE)

# Normalize names for case-insensitive and trim-safe matching.
norm <- function(x) {
  tolower(trimws(x))
}

target_norm <- norm(card_name)

target_rows <- DBI::dbGetQuery(
  con,
  "
  SELECT DISTINCT deck_id
  FROM deck_cards
  WHERE lower(trim(card_name)) = ?
  ",
  params = list(target_norm)
)

target_deck_count <- nrow(target_rows)

target_total_copies <- DBI::dbGetQuery(
  con,
  "
  SELECT COALESCE(SUM(quantity), 0) AS total_copies
  FROM deck_cards
  WHERE lower(trim(card_name)) = ?
  ",
  params = list(target_norm)
)$total_copies[[1L]]

cat("=== Card stats ===\n")
cat(sprintf("DB path               : %s\n", db_path))
cat(sprintf("Target card           : %s\n", card_name))
cat(sprintf("Decks containing card : %d\n", target_deck_count))
cat(sprintf("Total copies in DB    : %d\n\n", as.integer(target_total_copies)))

if (target_deck_count == 0L) {
  cat("No deck contains this card.\n")
  quit(status = 0)
}

cooc <- DBI::dbGetQuery(
  con,
  "
  WITH target_decks AS (
    SELECT DISTINCT deck_id
    FROM deck_cards
    WHERE lower(trim(card_name)) = ?
  )
  SELECT
    dc.card_name AS card_name,
    COUNT(DISTINCT dc.deck_id) AS decks_together,
    COALESCE(SUM(dc.quantity), 0) AS total_copies_together
  FROM deck_cards dc
  INNER JOIN target_decks td
    ON td.deck_id = dc.deck_id
  WHERE lower(trim(dc.card_name)) <> ?
  GROUP BY dc.card_name
  ORDER BY decks_together DESC, total_copies_together DESC, card_name ASC
  LIMIT ?
  ",
  params = list(target_norm, target_norm, top_n)
)

if (nrow(cooc) == 0L) {
  cat("No co-occurring cards found.\n")
  quit(status = 0)
}

cooc$share_pct <- round(100 * cooc$decks_together / target_deck_count, 1)

cat(sprintf("Top %d co-occurring cards (by shared decks):\n", top_n))
print(cooc, row.names = FALSE)
