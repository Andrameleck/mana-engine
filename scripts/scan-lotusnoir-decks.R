#!/usr/bin/env Rscript
# Parallel LotusNoir deck scanner — shard-per-worker architecture.
#
# The DID range is split into N equal shards, one per worker.
# Each worker runs fully independently:
#   - reads its own checkpoint from the shared SQLite (WAL mode)
#   - applies an optional adaptive coarse-skip within its shard
#   - fetches decks and writes directly to SQLite
#   - writes its own checkpoint every LOTUSNOIR_CHECKPOINT_EVERY DIDs
#
# LotusNoir DID space is very sparse: most IDs return "Deck Introuvable"
# or "Il n'y a aucune carte". Use LOTUSNOIR_COARSE_STEP (e.g. 500) with
# LOTUSNOIR_COARSE_MISS (e.g. 2) to skip large gaps quickly.
#
# Environment variables:
#   LOTUSNOIR_DB            SQLite output. Default: inst/decks/lotusnoir/lotusnoir.sqlite
#   LOTUSNOIR_MIN_DID       First DID. Default: 1
#   LOTUSNOIR_MAX_DID       Last DID.  Default: 20500000
#   LOTUSNOIR_WORKERS       Parallel workers / shards. Default: 5
#   LOTUSNOIR_DELAY         Seconds between requests per worker. Default: 2
#   LOTUSNOIR_OVERWRITE     Re-fetch stored decks. Default: false
#   LOTUSNOIR_COARSE_STEP   Adaptive skip: probe every N DIDs inside each shard;
#                           switch to fast-forward after LOTUSNOIR_COARSE_MISS
#                           consecutive probe misses. Default: 500
#                           Set to 0 to disable coarse scanning.
#   LOTUSNOIR_COARSE_MISS   Consecutive fine-scan misses before fast-forward.
#                           Default: 2
#   LOTUSNOIR_CHECKPOINT_EVERY  DIDs processed between checkpoint writes. Default: 200

suppressMessages(devtools::load_all(".", quiet = TRUE))

# ── config ────────────────────────────────────────────────────────────────────
db_path <- Sys.getenv("LOTUSNOIR_DB",
  unset = file.path("inst", "decks", "lotusnoir", "lotusnoir.sqlite"))
dir.create(dirname(db_path), recursive = TRUE, showWarnings = FALSE)

n_workers   <- max(1L, suppressWarnings(as.integer(
  Sys.getenv("LOTUSNOIR_WORKERS", unset = "5"))))
delay       <- max(0, suppressWarnings(as.numeric(
  Sys.getenv("LOTUSNOIR_DELAY", unset = "2"))))
overwrite   <- tolower(Sys.getenv("LOTUSNOIR_OVERWRITE", unset = "false")) %in%
  c("1", "true", "yes", "y", "on")
coarse_step <- max(0L, suppressWarnings(as.integer(
  Sys.getenv("LOTUSNOIR_COARSE_STEP", unset = "500"))))
coarse_miss <- max(1L, suppressWarnings(as.integer(
  Sys.getenv("LOTUSNOIR_COARSE_MISS", unset = "2"))))
ckpt_every  <- max(10L, suppressWarnings(as.integer(
  Sys.getenv("LOTUSNOIR_CHECKPOINT_EVERY", unset = "200"))))

min_did <- max(1L, suppressWarnings(as.integer(
  Sys.getenv("LOTUSNOIR_MIN_DID", unset = "1"))))
max_did <- suppressWarnings(as.integer(
  Sys.getenv("LOTUSNOIR_MAX_DID", unset = "20500000")))
if (is.na(max_did)) max_did <- 20500000L

ts <- function() format(Sys.time(), "[%Y-%m-%d %H:%M:%S]")

# ── DB init ───────────────────────────────────────────────────────────────────
if (!requireNamespace("DBI",     quietly = TRUE) ||
    !requireNamespace("RSQLite", quietly = TRUE))
  stop("DBI and RSQLite packages are required")

init_db <- function(con) {
  DBI::dbExecute(con, "PRAGMA journal_mode=WAL")
  DBI::dbExecute(con, "PRAGMA busy_timeout=15000")
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS decks (
      id         INTEGER PRIMARY KEY,
      url        TEXT,
      title      TEXT,
      author     TEXT,
      format     TEXT,
      updated_at TEXT,
      fetched_at TEXT
    )")
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS deck_cards (
      deck_id     INTEGER,
      section     TEXT,
      quantity    INTEGER,
      card_name   TEXT,
      scryfall_id TEXT
    )")
  DBI::dbExecute(con,
    "CREATE INDEX IF NOT EXISTS idx_deck_cards_deck_id ON deck_cards (deck_id)")
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS scan_checkpoint (
      key   TEXT PRIMARY KEY,
      value TEXT
    )")
}

con0 <- DBI::dbConnect(RSQLite::SQLite(), db_path)
init_db(con0)

# ── determine full DID list ───────────────────────────────────────────────────
all_dids <- seq.int(min_did, max_did)

if (!isTRUE(overwrite)) {
  stored <- DBI::dbGetQuery(con0, "SELECT id FROM decks")$id
  all_dids <- all_dids[!all_dids %in% stored]

  ckpts <- DBI::dbGetQuery(con0,
    "SELECT key, value FROM scan_checkpoint WHERE key LIKE 'last_did_w%'")
  if (nrow(ckpts) > 0L) {
    full_dids  <- seq.int(min_did, max_did)
    shard_idx0 <- cut(seq_along(full_dids), breaks = n_workers,
                      labels = FALSE, include.lowest = TRUE)
    orig_shards <- split(full_dids, shard_idx0)
    done_dids <- unlist(lapply(seq_len(nrow(ckpts)), function(k) {
      key   <- ckpts$key[k]
      w_idx <- suppressWarnings(as.integer(sub("last_did_w", "", key)))
      last  <- suppressWarnings(as.integer(ckpts$value[k]))
      if (is.na(w_idx) || is.na(last)) return(integer(0))
      shard <- orig_shards[[w_idx]]
      if (is.null(shard)) return(integer(0))
      shard[shard <= last]
    }), use.names = FALSE)
    all_dids <- all_dids[!all_dids %in% done_dids]
  }
}
DBI::dbDisconnect(con0)

n_total <- length(all_dids)
if (n_total == 0L) { message(ts(), " Nothing to do."); quit(status = 0L) }

message(sprintf("%s LotusNoir shard scan", ts()))
message(sprintf("  DB          : %s", db_path))
message(sprintf("  DIDs        : %d  workers=%d  delay=%.1fs", n_total, n_workers, delay))
message(sprintf("  coarse_step : %d  coarse_miss=%d", coarse_step, coarse_miss))
message(sprintf("  ETA raw     : ~%.0f min  (%.1f req/s est.  coarse skips not accounted for)",
                n_total / (n_workers / max(delay, 0.5)) / 60,
                n_workers / max(delay, 0.5)))

# ── split into shards ─────────────────────────────────────────────────────────
shard_idx <- cut(seq_along(all_dids), breaks = n_workers,
                 labels = FALSE, include.lowest = TRUE)
shards    <- split(all_dids, shard_idx)

# ── fetch helpers (available inside forked workers) ───────────────────────────

# Parse LotusNoir text export format.
# Returns a list with title, author, format, category, date, cards — or NULL
# if the response signals a missing / empty deck.
parse_lotusnoir_export <- function(text, deck_did) {
  if (!nzchar(trimws(text))) return(NULL)

  # "Deck Introuvable" → not found
  if (grepl("Deck Introuvable", text, fixed = TRUE)) return(NULL)

  # "Il n'y a aucune carte" → exists but empty; skip
  if (grepl("aucune carte", text, fixed = TRUE)) return(NULL)

  lines <- trimws(unlist(strsplit(text, "\n", fixed = TRUE)))
  lines <- lines[nzchar(lines)]

  deck_title    <- ""
  deck_author   <- ""
  deck_format   <- ""
  deck_category <- ""
  deck_date     <- ""

  # Extract metadata from comment lines
  for (line in lines) {
    if (grepl("^//\\s*NAME\\s*:", line)) {
      deck_title <- trimws(sub("^//\\s*NAME\\s*:\\s*(\\[Deck Lotus Noir\\]\\s*)?", "", line, perl = TRUE))
      next
    }
    if (grepl("^//\\s*AUTHOR\\s*:", line, ignore.case = TRUE)) {
      deck_author <- trimws(sub("^//\\s*AUTHOR\\s*:\\s*", "", line, ignore.case = TRUE, perl = TRUE))
      next
    }
    if (grepl("^//\\s*FORMAT\\s*:", line, ignore.case = TRUE)) {
      deck_format <- trimws(sub("^//\\s*FORMAT\\s*:\\s*", "", line, ignore.case = TRUE, perl = TRUE))
      next
    }
    if (grepl("^//\\s*CATEGORY\\s*:", line, ignore.case = TRUE)) {
      deck_category <- trimws(sub("^//\\s*CATEGORY\\s*:\\s*", "", line, ignore.case = TRUE, perl = TRUE))
      next
    }
    if (grepl("^//\\s*DATE\\s*:", line, ignore.case = TRUE)) {
      deck_date <- trimws(sub("^//\\s*DATE\\s*:\\s*", "", line, ignore.case = TRUE, perl = TRUE))
      next
    }
  }

  card_rows     <- list()
  current_block <- "MAIN DECK"
  current_section <- ""

  for (line in lines) {
    if (grepl("^//\\s*NAME\\s*:", line)) next
    if (grepl("^//\\s*MAIN DECK", line)) {
      current_block   <- "MAIN DECK"
      current_section <- "MAIN DECK"
      next
    }
    if (grepl("^//\\s*SIDE DECK", line)) {
      current_block   <- "SIDE DECK"
      current_section <- "SIDE DECK"
      next
    }
    if (grepl("^//", line)) {
      section_line <- trimws(sub("^//\\s*", "", line))
      section_line <- trimws(sub("\\s*\\([0-9]+\\)\\s*$", "", section_line))
      current_section <- if (nzchar(section_line)) section_line else current_block
      next
    }

    is_sb <- grepl("^SB:\\s*", line)
    clean <- if (is_sb) trimws(sub("^SB:\\s*", "", line)) else line

    m <- regexec("^([0-9]+)\\s+(.+)$", clean, perl = TRUE)
    g <- regmatches(clean, m)[[1]]
    if (length(g) < 3L) next

    qty  <- suppressWarnings(as.integer(g[[2]]))
    name <- trimws(g[[3]])
    if (!nzchar(name)) next

    sec <- current_section
    if (!nzchar(sec))
      sec <- if (is_sb || identical(current_block, "SIDE DECK")) "SIDE DECK" else "MAIN DECK"

    card_rows[[length(card_rows) + 1L]] <- list(
      section         = sec,
      quantity        = if (!is.na(qty) && is.finite(qty)) qty else 0L,
      card_name = name
    )
  }

  if (length(card_rows) == 0L) return(NULL)

  list(
    did      = as.integer(deck_did),
    title    = deck_title,
    author   = deck_author,
    format   = deck_format,
    category = deck_category,
    date     = deck_date,
    cards    = card_rows
  )
}

fetch_one <- function(did, delay_s) {
  if (delay_s > 0) Sys.sleep(delay_s)
  url  <- sprintf("https://www.lotusnoir.info/magic/decks/?action=export&did=%d", as.integer(did))
  text <- tryCatch({
    con <- base::url(url, open = "rb")
    on.exit(try(close(con), silent = TRUE), add = TRUE)
    paste(readLines(con, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  }, error = function(e) "")
  if (!nzchar(text)) return(NULL)
  parse_lotusnoir_export(text, did)
}

db_write <- function(con, deck, ts_now) {
  for (attempt in 1:5) {
    ok <- tryCatch({
      DBI::dbExecute(con,
        "INSERT OR REPLACE INTO decks
           (id, url, title, author, format, updated_at, fetched_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)",
        params = list(
          deck$did,
          sprintf("https://www.lotusnoir.info/magic/decks/?action=view&did=%d", deck$did),
          deck$title,
          deck$author,
          deck$format,
          deck$updated_at,
          ts_now
        ))
      if (length(deck$cards) > 0L) {
        DBI::dbExecute(con, "DELETE FROM deck_cards WHERE deck_id = ?",
                       params = list(deck$did))
        n <- length(deck$cards)
        DBI::dbAppendTable(con, "deck_cards", data.frame(
          deck_id     = rep.int(deck$did, n),
          section     = vapply(deck$cards, `[[`, character(1), "section"),
          quantity    = vapply(deck$cards, `[[`, integer(1),   "quantity"),
          card_name   = vapply(deck$cards, `[[`, character(1), "card_name"),
          scryfall_id = rep.int("", n),
          stringsAsFactors = FALSE))
      }
      TRUE
    }, error = function(e) { Sys.sleep(0.2 * attempt); FALSE })
    if (ok) return(TRUE)
  }
  FALSE
}

# ── worker: scan one shard ────────────────────────────────────────────────────
run_shard <- function(worker_id, ids, db_path, delay,
                      coarse_step, coarse_miss, ckpt_every, overwrite) {
  if (!requireNamespace("DBI",     quietly = TRUE) ||
      !requireNamespace("RSQLite", quietly = TRUE)) return(NULL)

  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(try(DBI::dbDisconnect(con), silent = TRUE), add = TRUE)
  DBI::dbExecute(con, "PRAGMA journal_mode=WAL")
  DBI::dbExecute(con, "PRAGMA busy_timeout=15000")

  if (length(ids) == 0L)
    return(list(worker_id = worker_id, inserted = 0L, skipped = 0L))

  ckpt_key    <- sprintf("last_did_w%d", worker_id)
  inserted    <- 0L
  skipped     <- 0L
  miss_streak <- 0L
  fast_mode   <- FALSE
  fast_pos    <- ids[1L]

  write_ckpt <- function(id) {
    tryCatch(DBI::dbExecute(con,
      "INSERT OR REPLACE INTO scan_checkpoint (key, value) VALUES (?, ?)",
      params = list(ckpt_key, as.character(id))), error = function(e) NULL)
  }

  i <- 1L
  while (i <= length(ids)) {
    id <- ids[i]

    if (fast_mode) {
      fast_pos <- fast_pos + coarse_step
      if (fast_pos < id) {
        probe_id <- fast_pos
        deck <- fetch_one(probe_id, delay * 0.25)
        if (!is.null(deck)) {
          fast_mode   <- FALSE
          miss_streak <- 0L
          ts_now <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
          db_write(con, deck, ts_now)
          inserted <- inserted + 1L
          rewind_from <- fast_pos - coarse_step
          i <- which(ids >= rewind_from)[1L]
          if (is.na(i)) i <- length(ids) + 1L
        } else {
          skipped_here <- sum(ids >= (fast_pos - coarse_step) & ids < fast_pos)
          skipped <- skipped + skipped_here
          i <- which(ids >= fast_pos)[1L]
          if (is.na(i)) i <- length(ids) + 1L
        }
        if ((inserted + skipped) %% ckpt_every == 0L) write_ckpt(fast_pos)
        next
      } else {
        fast_mode <- FALSE
      }
    }

    # fine-scan mode
    deck <- fetch_one(id, delay)
    if (!is.null(deck)) {
      miss_streak <- 0L
      ts_now <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
      db_write(con, deck, ts_now)
      inserted <- inserted + 1L
    } else {
      skipped     <- skipped + 1L
      miss_streak <- miss_streak + 1L
      if (coarse_step >= 10L && miss_streak >= coarse_miss) {
        fast_mode   <- TRUE
        fast_pos    <- id
        miss_streak <- 0L
      }
    }

    if ((inserted + skipped) %% ckpt_every == 0L) write_ckpt(id)
    i <- i + 1L
  }

  write_ckpt(ids[length(ids)])
  list(worker_id = worker_id, inserted = inserted, skipped = skipped)
}

# ── launch all shards in parallel ─────────────────────────────────────────────
t0 <- proc.time()[["elapsed"]]
message(sprintf("%s Launching %d independent shards...", ts(), length(shards)))

results <- parallel::mclapply(
  seq_along(shards),
  function(i) run_shard(
    worker_id   = i,
    ids         = shards[[i]],
    db_path     = db_path,
    delay       = delay,
    coarse_step = coarse_step,
    coarse_miss = coarse_miss,
    ckpt_every  = ckpt_every,
    overwrite   = overwrite
  ),
  mc.cores = length(shards)
)

elapsed   <- proc.time()[["elapsed"]] - t0
total_ins <- sum(vapply(results, function(r) if (is.null(r)) 0L else r$inserted %||% 0L, integer(1)))
total_skp <- sum(vapply(results, function(r) if (is.null(r)) 0L else r$skipped  %||% 0L, integer(1)))

message(sprintf(
  "%s Done — inserted=%d  skipped=%d  elapsed=%.0fs  db=%s",
  ts(), total_ins, total_skp, elapsed, db_path
))
