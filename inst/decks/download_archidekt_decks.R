#!/usr/bin/env Rscript
# Download Archidekt decks into a local SQLite database.
#
# Usage:
#   Rscript inst/decks/download_archidekt_decks.R
#
# Environment variables:
#   ARCHIDEKT_DB_PATH      Path to the SQLite file.
#                          Default: inst/decks/archidekt/archidekt.sqlite
#   ARCHIDEKT_MIN_ID       First deck ID to scan. Default: 1
#   ARCHIDEKT_MAX_ID       Last deck ID to scan. Default: 9000000
#   ARCHIDEKT_IDS_FILE     Path to a text file with one deck ID per line.
#                          If set, ARCHIDEKT_MIN_ID/MAX_ID are ignored.
#   ARCHIDEKT_WORKERS      Number of parallel workers. Default: 15
#   ARCHIDEKT_CHUNK        IDs per worker batch. Default: 100
#   ARCHIDEKT_REQUEST_DELAY  Seconds between requests per worker. Default: 0.1
#   ARCHIDEKT_OVERWRITE    Re-fetch already-stored decks. Default: false
#   ARCHIDEKT_VERBOSE      Print progress. Default: true

suppressMessages(devtools::load_all(".", quiet = TRUE))

db_dir <- file.path("inst", "decks", "archidekt")
dir.create(db_dir, recursive = TRUE, showWarnings = FALSE)
db_path <- Sys.getenv(
  "ARCHIDEKT_DB_PATH",
  unset = file.path(db_dir, "archidekt.sqlite")
)
dir.create(dirname(db_path), recursive = TRUE, showWarnings = FALSE)

ids_file <- trimws(Sys.getenv("ARCHIDEKT_IDS_FILE", unset = ""))
deck_ids <- NULL
if (nzchar(ids_file)) {
  if (!file.exists(ids_file)) {
    stop(sprintf("ARCHIDEKT_IDS_FILE not found: %s", ids_file))
  }
  raw_ids <- suppressWarnings(as.integer(readLines(ids_file, warn = FALSE)))
  deck_ids <- raw_ids[!is.na(raw_ids) & raw_ids > 0L]
  if (length(deck_ids) == 0L) {
    stop(sprintf("No valid IDs found in %s", ids_file))
  }
}

min_id <- suppressWarnings(as.integer(Sys.getenv("ARCHIDEKT_MIN_ID", unset = "1")))
if (is.na(min_id) || min_id < 1L) min_id <- 1L

max_id <- suppressWarnings(as.integer(Sys.getenv("ARCHIDEKT_MAX_ID", unset = "9000000")))
if (is.na(max_id) || max_id < min_id) max_id <- 9000000L

workers <- suppressWarnings(as.integer(Sys.getenv("ARCHIDEKT_WORKERS", unset = "15")))
if (is.na(workers) || workers < 1L) workers <- 15L

chunk <- suppressWarnings(as.integer(Sys.getenv("ARCHIDEKT_CHUNK", unset = "100")))
if (is.na(chunk) || chunk < 1L) chunk <- 100L

request_delay <- suppressWarnings(as.numeric(Sys.getenv("ARCHIDEKT_REQUEST_DELAY", unset = "0.1")))
if (!is.finite(request_delay) || is.na(request_delay) || request_delay < 0) {
  request_delay <- 0.1
}

overwrite <- tolower(Sys.getenv("ARCHIDEKT_OVERWRITE", unset = "false")) %in%
  c("1", "true", "yes", "y", "on")

verbose <- !tolower(Sys.getenv("ARCHIDEKT_VERBOSE", unset = "true")) %in%
  c("0", "false", "no", "n", "off")

cat("=== Archidekt deck downloader ===\n")
cat(sprintf("DB path       : %s\n", db_path))
if (!is.null(deck_ids)) {
  cat(sprintf("IDs file      : %s  (%d IDs)\n", ids_file, length(deck_ids)))
} else {
  cat(sprintf("ID range      : %d .. %d\n", min_id, max_id))
}
cat(sprintf("Workers       : %d\n", workers))
cat(sprintf("Chunk size    : %d\n", chunk))
cat(sprintf("Request delay : %.2f s\n", request_delay))
cat(sprintf("Overwrite     : %s\n\n", if (overwrite) "TRUE" else "FALSE"))

scan_script <- file.path("scripts", "scan-archidekt-decks.R")
if (!file.exists(scan_script)) {
  stop(sprintf("Parallel scan script not found: %s", scan_script))
}

env_vars <- c(
  sprintf("ARCHIDEKT_DB=%s",      db_path),
  sprintf("ARCHIDEKT_MIN_ID=%d",  min_id),
  sprintf("ARCHIDEKT_MAX_ID=%d",  max_id),
  sprintf("ARCHIDEKT_WORKERS=%d", workers),
  sprintf("ARCHIDEKT_CHUNK=%d",   chunk),
  sprintf("ARCHIDEKT_DELAY=%.3f", request_delay)
)
if (!is.null(deck_ids)) {
  tmp_ids <- tempfile(fileext = ".txt")
  writeLines(as.character(deck_ids), tmp_ids)
  env_vars <- c(env_vars, sprintf("ARCHIDEKT_IDS_FILE=%s", tmp_ids))
  on.exit(unlink(tmp_ids), add = TRUE)
}

status <- system2(
  command = "env",
  args    = c(env_vars, "Rscript", scan_script),
  stdout  = "",
  stderr  = ""
)

if (status != 0L) {
  cat(sprintf("Scan exited with status %d\n", status))
  quit(status = status)
}
