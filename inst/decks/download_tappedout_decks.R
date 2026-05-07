#!/usr/bin/env Rscript
# Download TappedOut decks into a local SQLite database.
#
# Uses the public CSV export — no session cookie required.
#
# Usage from console:
#   tappedout_slugs <- c("aggrocrates", "my-edh-deck")
#   source("inst/decks/download_tappedout_decks.R")
#
# Environment variables:
#   TAPPEDOUT_DB_PATH       Path to the SQLite file.
#                           Default: inst/decks/tappedout/tappedout.sqlite
#   TAPPEDOUT_SLUGS_FILE    Path to a text file with one deck slug per line.
#   TAPPEDOUT_SLUGS         Comma-separated deck slugs.
#   TAPPEDOUT_REQUEST_DELAY Seconds between requests. Default: 1.0
#   TAPPEDOUT_OVERWRITE     Re-fetch already-stored decks. Default: false
#   TAPPEDOUT_VERBOSE       Print progress. Default: true

if (!exists("devtools_already_loaded")) {
  suppressMessages(devtools::load_all(".", quiet = TRUE))
}

db_dir <- file.path("inst", "decks", "tappedout")
dir.create(db_dir, recursive = TRUE, showWarnings = FALSE)
db_path <- if (exists("tappedout_db_path")) {
  tappedout_db_path
} else {
  Sys.getenv("TAPPEDOUT_DB_PATH", unset = file.path(db_dir, "tappedout.sqlite"))
}

slugs_file <- if (exists("tappedout_slugs_file")) {
  tappedout_slugs_file
} else {
  trimws(Sys.getenv("TAPPEDOUT_SLUGS_FILE", unset = ""))
}

slugs_csv <- if (exists("tappedout_slugs_csv")) {
  tappedout_slugs_csv
} else {
  trimws(Sys.getenv("TAPPEDOUT_SLUGS", unset = ""))
}

read_slugs_file <- function(path) {
  raw <- trimws(readLines(path, warn = FALSE))
  raw[nzchar(raw)]
}

deck_slugs <- character(0)
if (exists("tappedout_slugs") && is.character(tappedout_slugs)) {
  deck_slugs <- c(deck_slugs, trimws(tappedout_slugs))
}
if (nzchar(slugs_file)) {
  if (!file.exists(slugs_file)) stop(sprintf("TAPPEDOUT_SLUGS_FILE not found: %s", slugs_file))
  deck_slugs <- c(deck_slugs, read_slugs_file(slugs_file))
}
if (nzchar(slugs_csv)) {
  deck_slugs <- c(deck_slugs, trimws(strsplit(slugs_csv, ",", fixed = TRUE)[[1L]]))
}

deck_slugs <- unique(deck_slugs[nzchar(deck_slugs)])
if (length(deck_slugs) == 0L) {
  stop("Provide slugs via tappedout_slugs, TAPPEDOUT_SLUGS_FILE or TAPPEDOUT_SLUGS")
}

request_delay <- if (exists("tappedout_request_delay")) {
  tappedout_request_delay
} else {
  suppressWarnings(as.numeric(Sys.getenv("TAPPEDOUT_REQUEST_DELAY", unset = "1.0")))
}
if (!is.finite(request_delay) || is.na(request_delay) || request_delay < 0) request_delay <- 1.0

overwrite <- if (exists("tappedout_overwrite")) {
  isTRUE(tappedout_overwrite)
} else {
  tolower(Sys.getenv("TAPPEDOUT_OVERWRITE", unset = "false")) %in% c("1", "true", "yes", "y", "on")
}

verbose <- if (exists("tappedout_verbose")) {
  isTRUE(tappedout_verbose)
} else {
  !tolower(Sys.getenv("TAPPEDOUT_VERBOSE", unset = "true")) %in% c("0", "false", "no", "n", "off")
}

cat("=== TappedOut deck downloader ===\n")
cat(sprintf("DB path         : %s\n", db_path))
cat(sprintf("Deck slugs      : %d\n", length(deck_slugs)))
cat(sprintf("Request delay   : %.2f s\n", request_delay))
cat(sprintf("Overwrite       : %s\n\n", if (overwrite) "TRUE" else "FALSE"))

out <- query_tappedout_download_decks_sqlite(
  db_path       = db_path,
  deck_slugs    = deck_slugs,
  request_delay = request_delay,
  overwrite     = overwrite,
  verbose       = verbose
)

if (!isTRUE(out$ok)) {
  cat(sprintf("TappedOut download failed: %s\n", out$error %||% "unknown error"))
  quit(status = 1L)
}

cat(sprintf(
  "Done — inserted=%d skipped=%d errors=%d db=%s\n",
  out$inserted, out$skipped, out$errors, out$db_path
))
