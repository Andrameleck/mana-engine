#!/usr/bin/env Rscript
# Download Moxfield decks into a local SQLite database.
#
# Usage from console:
#   moxfield_ids <- "id1,id2,id3"
#   moxfield_session_cookie <- "cf_clearance=..."
#   source("inst/decks/download_moxfield_decks.R")
#
# Or with all options:
#   moxfield_ids <- "id1,id2,id3"
#   moxfield_session_cookie <- "cf_clearance=..."
#   moxfield_request_delay <- 0.5
#   moxfield_overwrite <- FALSE
#   moxfield_verbose <- TRUE
#   source("inst/decks/download_moxfield_decks.R")
#
# Or from command line:
#   MOXFIELD_IDS="id1,id2,id3" MOXFIELD_SESSION_COOKIE="..." Rscript inst/decks/download_moxfield_decks.R
#
# Environment variables:
#   MOXFIELD_DB_PATH         Path to the SQLite file.
#                            Default: inst/decks/moxfield/moxfield.sqlite
#   MOXFIELD_IDS_FILE        Path to a text file with one deck hash ID per line.
#                            Required unless MOXFIELD_IDS is set.
#   MOXFIELD_IDS             Comma-separated deck hash IDs.
#                            Required unless MOXFIELD_IDS_FILE is set.
#   MOXFIELD_SESSION_COOKIE  Cloudflare session cookie.
#                            Format: cf_clearance=<value>
#   MOXFIELD_REQUEST_DELAY   Seconds between requests. Default: 0.5
#   MOXFIELD_OVERWRITE       Re-fetch already-stored decks. Default: false
#   MOXFIELD_VERBOSE         Print progress. Default: true

if (!exists("devtools_already_loaded")) {
  suppressMessages(devtools::load_all(".", quiet = TRUE))
}

db_dir <- file.path("inst", "decks", "moxfield")
dir.create(db_dir, recursive = TRUE, showWarnings = FALSE)
db_path <- if (exists("moxfield_db_path")) {
  moxfield_db_path
} else {
  Sys.getenv("MOXFIELD_DB_PATH", unset = file.path(db_dir, "moxfield.sqlite"))
}

ids_file <- if (exists("moxfield_ids_file")) {
  moxfield_ids_file
} else {
  trimws(Sys.getenv("MOXFIELD_IDS_FILE", unset = ""))
}

ids_csv <- if (exists("moxfield_ids")) {
  moxfield_ids
} else {
  trimws(Sys.getenv("MOXFIELD_IDS", unset = ""))
}

read_ids_file <- function(path) {
  raw <- trimws(readLines(path, warn = FALSE))
  raw[nzchar(raw)]
}

deck_ids <- character(0)
if (nzchar(ids_file)) {
  if (!file.exists(ids_file)) {
    stop(sprintf("MOXFIELD_IDS_FILE not found: %s", ids_file))
  }
  deck_ids <- c(deck_ids, read_ids_file(ids_file))
}
if (nzchar(ids_csv)) {
  deck_ids <- c(deck_ids, trimws(strsplit(ids_csv, ",", fixed = TRUE)[[1L]]))
}

deck_ids <- unique(deck_ids[nzchar(deck_ids)])
if (length(deck_ids) == 0L) {
  stop("Provide deck IDs via MOXFIELD_IDS_FILE or MOXFIELD_IDS")
}

session_cookie <- if (exists("moxfield_session_cookie")) {
  moxfield_session_cookie
} else {
  trimws(Sys.getenv("MOXFIELD_SESSION_COOKIE", unset = ""))
}
if (!nzchar(session_cookie)) {
  stop("MOXFIELD_SESSION_COOKIE is required (format: cf_clearance=<value>)")
}

request_delay <- if (exists("moxfield_request_delay")) {
  moxfield_request_delay
} else {
  suppressWarnings(as.numeric(Sys.getenv("MOXFIELD_REQUEST_DELAY", unset = "0.5")))
}
if (!is.finite(request_delay) || is.na(request_delay) || request_delay < 0) {
  request_delay <- 0.5
}

overwrite <- if (exists("moxfield_overwrite")) {
  moxfield_overwrite
} else {
  tolower(Sys.getenv("MOXFIELD_OVERWRITE", unset = "false")) %in%
    c("1", "true", "yes", "y", "on")
}

verbose <- if (exists("moxfield_verbose")) {
  moxfield_verbose
} else {
  !tolower(Sys.getenv("MOXFIELD_VERBOSE", unset = "true")) %in%
    c("0", "false", "no", "n", "off")
}

cat("=== Moxfield deck downloader ===\n")
cat(sprintf("DB path         : %s\n", db_path))
if (nzchar(ids_file)) {
  cat(sprintf("IDs file        : %s\n", ids_file))
}
if (nzchar(ids_csv)) {
  cat("IDs source      : MOXFIELD_IDS\n")
}
cat(sprintf("Deck IDs        : %d\n", length(deck_ids)))
cat(sprintf("Request delay   : %.2f s\n", request_delay))
cat(sprintf("Overwrite       : %s\n", if (overwrite) "TRUE" else "FALSE"))
cat(sprintf("Cookie provided : %s\n\n", if (nzchar(session_cookie)) "TRUE" else "FALSE"))

out <- query_moxfield_download_decks_sqlite(
  db_path         = db_path,
  deck_ids        = deck_ids,
  session_cookie  = session_cookie,
  request_delay   = request_delay,
  overwrite       = overwrite,
  verbose         = verbose
)

if (!isTRUE(out$ok)) {
  cat(sprintf("Moxfield download failed: %s\n", out$error %||% "unknown error"))
  quit(status = 1)
}

cat(sprintf(
  "Done — inserted=%d skipped=%d errors=%d db=%s\n",
  out$inserted, out$skipped, out$errors, out$db_path
))
