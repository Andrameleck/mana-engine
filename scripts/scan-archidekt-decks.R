#!/usr/bin/env Rscript
# Parallel Archidekt deck scanner — shard-per-worker architecture.
#
# The ID range is split into N equal shards, one per worker.
# Each worker runs fully independently:
#   - reads its own checkpoint from the shared SQLite (WAL mode)
#   - applies an optional adaptive coarse-skip within its shard
#   - fetches decks and writes directly to SQLite
#   - writes its own checkpoint every ARCHIDEKT_CHECKPOINT_EVERY IDs
#
# Environment variables:
#   ARCHIDEKT_DB            SQLite output. Default: inst/decks/archidekt.sqlite
#   ARCHIDEKT_MIN_ID        First deck ID. Default: 1
#   ARCHIDEKT_MAX_ID        Last deck ID.  Default: 9000000
#   ARCHIDEKT_IDS_FILE      File with one ID per line (overrides MIN/MAX).
#   ARCHIDEKT_WORKERS       Parallel workers / shards. Default: 15
#   ARCHIDEKT_DELAY         Seconds between requests per worker. Default: 0.1
#   ARCHIDEKT_OVERWRITE     Re-fetch stored decks. Default: false
#   ARCHIDEKT_COARSE_STEP   Adaptive skip: probe every N IDs inside each shard;
#                           switch to fast-forward after ARCHIDEKT_COARSE_MISS
#                           consecutive probe misses. Default: 0 (off)
#                           Suggested: 500
#   ARCHIDEKT_COARSE_MISS   Consecutive fine-scan misses before fast-forward.
#                           Default: 2
#   ARCHIDEKT_CHECKPOINT_EVERY  IDs processed between checkpoint writes. Default: 500

suppressMessages(devtools::load_all(".", quiet = TRUE))

# ── config ────────────────────────────────────────────────────────────────────
db_path   <- Sys.getenv("ARCHIDEKT_DB",
  unset = file.path("inst", "decks", "archidekt", "archidekt.sqlite"))
dir.create(dirname(db_path), recursive = TRUE, showWarnings = FALSE)

ids_file    <- trimws(Sys.getenv("ARCHIDEKT_IDS_FILE", unset = ""))
n_workers   <- max(1L, suppressWarnings(as.integer(
  Sys.getenv("ARCHIDEKT_WORKERS", unset = "15"))))
delay       <- max(0, suppressWarnings(as.numeric(
  Sys.getenv("ARCHIDEKT_DELAY", unset = "0.1"))))
overwrite   <- tolower(Sys.getenv("ARCHIDEKT_OVERWRITE", unset = "false")) %in%
  c("1","true","yes","y","on")
coarse_step <- max(0L, suppressWarnings(as.integer(
  Sys.getenv("ARCHIDEKT_COARSE_STEP", unset = "0"))))
coarse_miss <- max(1L, suppressWarnings(as.integer(
  Sys.getenv("ARCHIDEKT_COARSE_MISS", unset = "2"))))
ckpt_every  <- max(10L, suppressWarnings(as.integer(
  Sys.getenv("ARCHIDEKT_CHECKPOINT_EVERY", unset = "500"))))

min_id <- max(1L, suppressWarnings(as.integer(
  Sys.getenv("ARCHIDEKT_MIN_ID", unset = "1"))))
max_id <- suppressWarnings(as.integer(
  Sys.getenv("ARCHIDEKT_MAX_ID", unset = "9000000")))
if (is.na(max_id)) max_id <- 9000000L

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

# ── determine full ID list ────────────────────────────────────────────────────
if (nzchar(ids_file)) {
  if (!file.exists(ids_file)) stop(sprintf("IDs file not found: %s", ids_file))
  all_ids <- suppressWarnings(as.integer(readLines(ids_file, warn = FALSE)))
  all_ids <- sort(all_ids[!is.na(all_ids) & all_ids > 0L])
} else {
  all_ids <- seq.int(min_id, max_id)
}

if (!isTRUE(overwrite)) {
  # IDs in decks table = already fetched successfully
  stored  <- DBI::dbGetQuery(con0, "SELECT id FROM decks")$id
  all_ids <- all_ids[!all_ids %in% stored]

  # IDs covered by per-worker checkpoints = already scanned (hit or miss)
  # Each checkpoint last_id_w{i} means worker i processed all its IDs up to that point.
  # Reconstruct shard boundaries from the original range to know which IDs each
  # worker owned, then drop everything <= its checkpoint.
  ckpts <- DBI::dbGetQuery(con0,
    "SELECT key, value FROM scan_checkpoint WHERE key LIKE 'last_id_w%'")
  if (nrow(ckpts) > 0L) {
    # Build the original shards from the full range (before stored filtering)
    full_ids   <- if (nzchar(ids_file)) all_ids else seq.int(min_id, max_id)
    shard_idx0 <- cut(seq_along(full_ids), breaks = n_workers,
                      labels = FALSE, include.lowest = TRUE)
    orig_shards <- split(full_ids, shard_idx0)
    done_ids <- unlist(lapply(seq_len(nrow(ckpts)), function(k) {
      key   <- ckpts$key[k]
      w_idx <- suppressWarnings(as.integer(sub("last_id_w", "", key)))
      last  <- suppressWarnings(as.integer(ckpts$value[k]))
      if (is.na(w_idx) || is.na(last)) return(integer(0))
      shard <- orig_shards[[w_idx]]
      if (is.null(shard)) return(integer(0))
      shard[shard <= last]
    }), use.names = FALSE)
    all_ids <- all_ids[!all_ids %in% done_ids]
  }
}
DBI::dbDisconnect(con0)

n_total <- length(all_ids)
if (n_total == 0L) { message(ts(), " Nothing to do."); quit(status = 0L) }

message(sprintf("%s Archidekt shard scan", ts()))
message(sprintf("  DB          : %s", db_path))
message(sprintf("  IDs         : %d  workers=%d  delay=%.2fs", n_total, n_workers, delay))
message(sprintf("  coarse_step : %d  coarse_miss=%d", coarse_step, coarse_miss))
message(sprintf("  ETA         : ~%.0f min  (%.0f req/s est.)",
                n_total / (n_workers / max(delay, 0.05)) / 60,
                n_workers / max(delay, 0.05)))

# ── split into shards ─────────────────────────────────────────────────────────
shard_idx <- cut(seq_along(all_ids), breaks = n_workers,
                 labels = FALSE, include.lowest = TRUE)
shards    <- split(all_ids, shard_idx)

# ── helpers (available inside forked workers) ─────────────────────────────────
fmt_codes <- c("1"="Standard","2"="Modern","3"="Commander","4"="Legacy",
               "5"="Vintage","6"="Pauper","7"="Limited","8"="Frontier",
               "9"="Future Standard","10"="Penny Dreadful",
               "11"="1v1 Commander","13"="Oathbreaker",
               "14"="Historic","17"="Pioneer")

fetch_one <- function(id, delay_s) {
  if (delay_s > 0) Sys.sleep(delay_s)
  url <- sprintf("https://archidekt.com/api/decks/%d/?format=json", as.integer(id))
  raw <- tryCatch(
    paste(readLines(url, warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
    error = function(e) "")
  if (!nzchar(raw)) return(NULL)
  p <- tryCatch(jsonlite::fromJSON(raw, simplifyVector = FALSE),
                error = function(e) NULL)
  if (is.null(p) || !is.null(p$error)) return(NULL)
  if (isTRUE(p$private) || isTRUE(p$unlisted)) return(NULL)

  fmt <- unname(fmt_codes[as.character(p$deckFormat %||% "")])
  if (is.null(fmt) || is.na(fmt)) fmt <- as.character(p$deckFormat %||% "")

  card_rows <- Filter(Negate(is.null), lapply(p$cards %||% list(), function(entry) {
    qty         <- suppressWarnings(as.integer(entry$quantity %||% 1L))
    if (is.na(qty) || qty < 1L) qty <- 1L
    card        <- entry$card %||% list()
    oracle_card <- card$oracleCard %||% list()
    card_name   <- trimws(as.character(oracle_card$name %||% card$displayName %||% ""))
    if (!nzchar(card_name)) return(NULL)
    cats    <- entry$categories %||% list()
    section <- if (length(cats) > 0L) trimws(as.character(cats[[1L]])) else "Main"
    list(section     = section, quantity    = qty,
         card_name   = card_name,
         scryfall_id = trimws(as.character(card$uid %||% oracle_card$uid %||% "")))
  }))

  list(id = as.integer(id),
       url        = sprintf("https://archidekt.com/decks/%d", as.integer(id)),
       title      = trimws(as.character(p$name %||% "")),
       author     = trimws(as.character((p$owner %||% list())$username %||% "")),
       format     = fmt,
       updated_at = trimws(as.character(p$updatedAt %||% "")),
       cards      = card_rows)
}

db_write <- function(con, deck, ts_now) {
  for (attempt in 1:5) {
    ok <- tryCatch({
      DBI::dbExecute(con,
        "INSERT OR REPLACE INTO decks
           (id, url, title, author, format, updated_at, fetched_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)",
        params = list(deck$id, deck$url, deck$title, deck$author,
                      deck$format, deck$updated_at, ts_now))
      if (length(deck$cards) > 0L) {
        DBI::dbExecute(con, "DELETE FROM deck_cards WHERE deck_id = ?",
                       params = list(deck$id))
        n <- length(deck$cards)
        DBI::dbAppendTable(con, "deck_cards", data.frame(
          deck_id     = rep.int(deck$id, n),
          section     = vapply(deck$cards, `[[`, character(1), "section"),
          quantity    = vapply(deck$cards, `[[`, integer(1),   "quantity"),
          card_name   = vapply(deck$cards, `[[`, character(1), "card_name"),
          scryfall_id = vapply(deck$cards, `[[`, character(1), "scryfall_id"),
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
  if (!requireNamespace("DBI",      quietly = TRUE) ||
      !requireNamespace("RSQLite",  quietly = TRUE) ||
      !requireNamespace("jsonlite", quietly = TRUE)) return(NULL)

  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(try(DBI::dbDisconnect(con), silent = TRUE), add = TRUE)
  DBI::dbExecute(con, "PRAGMA journal_mode=WAL")
  DBI::dbExecute(con, "PRAGMA busy_timeout=15000")

  # IDs are pre-filtered by main process — no further resume logic needed here
  if (length(ids) == 0L)
    return(list(worker_id = worker_id, inserted = 0L, skipped = 0L))

  ckpt_key <- sprintf("last_id_w%d", worker_id)

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
      # In fast mode, advance fast_pos by coarse_step until we catch up to id
      fast_pos <- fast_pos + coarse_step
      if (fast_pos < id) {
        # still before current id: test the probe point then skip to next
        probe_id <- fast_pos
        deck <- fetch_one(probe_id, delay * 0.25)
        if (!is.null(deck)) {
          # found a hit: exit fast mode, fine-scan backwards from here
          fast_mode   <- FALSE
          miss_streak <- 0L
          # write the hit we just found
          ts_now <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
          db_write(con, deck, ts_now)
          inserted <- inserted + 1L
          # rewind i to the first ID >= (fast_pos - coarse_step) to catch IDs we skipped
          rewind_from <- fast_pos - coarse_step
          i <- which(ids >= rewind_from)[1L]
          if (is.na(i)) i <- length(ids) + 1L
        } else {
          # still cold — stay in fast mode, skip all ids up to fast_pos
          skipped_here <- sum(ids >= (fast_pos - coarse_step) & ids < fast_pos)
          skipped <- skipped + skipped_here
          # advance i past all ids < fast_pos
          i <- which(ids >= fast_pos)[1L]
          if (is.na(i)) i <- length(ids) + 1L
        }
        if ((inserted + skipped) %% ckpt_every == 0L) write_ckpt(fast_pos)
        next
      } else {
        # fast_pos caught up to or passed current id: exit fast mode
        fast_mode <- FALSE
      }
    }

    # ── fine-scan mode ────────────────────────────────────────────────────────
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
