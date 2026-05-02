# scripts/enrich-scryfall-library.R
#
# Enrich inst/collection/library_scryfall.sqlite with mechanics-first
# normalized data produced by query_synergy_normalize_card().
#
# Adds (in the same SQLite file):
#   - cards_enriched         : 1 row per (oracle_id, face_index)
#   - card_<X>                : long lookup tables for keywords, mechanics,
#                               roles, target_roles, strategy_tags,
#                               produced/consumed/replaced/prevented/
#                               setup/finisher events, and anti_tags
#   - enrichment_meta        : provenance and counts
#
# Usage:
#   Rscript scripts/enrich-scryfall-library.R
#
# Env options:
#   SCRYFALL_DB_PATH   target sqlite (default inst/collection/library_scryfall.sqlite)
#   ENRICH_LIMIT       integer cap for testing (default = all rows)
#   ENRICH_CHUNK       chunk size (default 2000)

suppressPackageStartupMessages({
  library(DBI)
  library(RSQLite)
  library(jsonlite)
})

db_path <- Sys.getenv(
  "SCRYFALL_DB_PATH",
  unset = file.path("inst", "collection", "library_scryfall.sqlite")
)
limit_env <- suppressWarnings(as.integer(Sys.getenv("ENRICH_LIMIT", "")))
chunk_size <- suppressWarnings(as.integer(Sys.getenv("ENRICH_CHUNK", "2000")))
if (!is.finite(chunk_size) || chunk_size < 1L) chunk_size <- 2000L

if (!file.exists(db_path)) {
  stop("Scryfall library not found at ", db_path,
       " - run scripts/download-scryfall-library.R first.")
}

# ---- Load engine ------------------------------------------------------------
# We source R/ directly so the script does not depend on devtools/pkgload.
message("[enrich] loading R/ ...")
r_files <- list.files("R", pattern = "\\.R$", full.names = TRUE)
for (f in r_files) suppressMessages(source(f, local = FALSE, encoding = "UTF-8"))

if (!exists("query_synergy_normalize_card", mode = "function")) {
  stop("query_synergy_normalize_card() not loaded - check R/ sources")
}

registry        <- query_synergy_event_registry_default()
mechanic_rules  <- query_synergy_mechanic_rules_default()
parse_rules     <- query_synergy_ability_parse_rules_default(registry = registry)

# ---- Helpers ----------------------------------------------------------------

# Decode a JSON-serialised list-column value back to an R object.
decode_json <- function(x) {
  if (is.null(x) || length(x) == 0L) return(NULL)
  s <- x[[1L]]
  if (is.na(s) || !nzchar(s) || identical(s, "null")) return(NULL)
  tryCatch(jsonlite::fromJSON(s, simplifyVector = TRUE),
           error = function(e) NULL)
}

# Encode any R object to compact JSON (NA -> "null").
encode_json <- function(x) {
  if (is.null(x)) return(NA_character_)
  if (is.atomic(x) && length(x) == 0L) return(NA_character_)
  jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", na = "null")
}

# Collapse a character vector to a CSV-ish text scalar; "" if empty.
collapse_chr <- function(x, sep = ";") {
  if (is.null(x)) return(NA_character_)
  v <- as.character(x)
  v <- v[!is.na(v) & nzchar(v)]
  if (!length(v)) return(NA_character_)
  paste(unique(v), collapse = sep)
}

scalar_or_na <- function(x) {
  if (is.null(x) || length(x) == 0L) return(NA_character_)
  v <- x[[1L]]
  if (is.na(v)) return(NA_character_)
  as.character(v)
}

num_or_na <- function(x) {
  if (is.null(x) || length(x) == 0L) return(NA_real_)
  v <- suppressWarnings(as.numeric(x[[1L]]))
  if (!is.finite(v)) return(NA_real_)
  v
}

# Build a card object suitable for query_synergy_normalize_card() given a row
# from the Scryfall `cards` table and an optional face override.
build_card_obj <- function(row, face = NULL) {
  base <- list(
    id          = scalar_or_na(row$oracle_id),
    name        = scalar_or_na(row$name),
    oracle_text = scalar_or_na(row$oracle_text),
    type_line   = scalar_or_na(row$type_line),
    mana_cost   = scalar_or_na(row$mana_cost),
    cmc         = num_or_na(row$cmc),
    power       = scalar_or_na(row$power),
    toughness   = scalar_or_na(row$toughness),
    loyalty     = scalar_or_na(row$loyalty),
    keywords    = decode_json(row$keywords) %||% character(0),
    colors      = decode_json(row$colors) %||% character(0),
    color_identity = decode_json(row$color_identity) %||% character(0)
  )

  if (is.list(face) && length(face)) {
    # face overrides take precedence when present and non-empty
    pick <- function(field, fallback) {
      v <- face[[field]]
      if (is.null(v)) return(fallback)
      if (is.character(v) && (length(v) == 0L || !nzchar(v[[1L]]))) return(fallback)
      v
    }
    base$name        <- pick("name",        base$name)
    base$oracle_text <- pick("oracle_text", base$oracle_text)
    base$type_line   <- pick("type_line",   base$type_line)
    base$mana_cost   <- pick("mana_cost",   base$mana_cost)
    base$power       <- pick("power",       base$power)
    base$toughness   <- pick("toughness",   base$toughness)
    base$loyalty     <- pick("loyalty",     base$loyalty)
    if (!is.null(face$colors))   base$colors   <- face$colors
    if (!is.null(face$keywords)) base$keywords <- face$keywords
  }
  base
}

`%||%` <- function(a, b) if (is.null(a) || (is.atomic(a) && length(a) == 0L)) b else a

# Decide the list of (face_index, face_obj) to normalize for a given row.
plan_faces <- function(row) {
  faces <- decode_json(row$card_faces)
  has_real_face <- function(f) {
    is.list(f) &&
      ((!is.null(f$oracle_text) && length(f$oracle_text) > 0L &&
        any(nzchar(as.character(f$oracle_text)))) ||
       (!is.null(f$type_line)   && length(f$type_line) > 0L &&
        any(nzchar(as.character(f$type_line)))))
  }

  # jsonlite::fromJSON often returns a data.frame for an array of objects;
  # normalise to a list-of-lists.
  if (is.data.frame(faces)) {
    faces <- lapply(seq_len(nrow(faces)), function(i) as.list(faces[i, , drop = FALSE]))
  }

  if (!is.list(faces) || !length(faces) ||
      !any(vapply(faces, has_real_face, logical(1)))) {
    return(list(list(face_index = 0L, face_name = scalar_or_na(row$name), face = NULL)))
  }

  lapply(seq_along(faces), function(i) {
    f <- faces[[i]]
    list(
      face_index = i - 1L,
      face_name  = scalar_or_na(if (!is.null(f$name)) f$name else row$name),
      face       = f
    )
  })
}

# ---- Open DB ----------------------------------------------------------------
message("[enrich] opening ", db_path)
con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
on.exit(try(DBI::dbDisconnect(con), silent = TRUE), add = TRUE)

DBI::dbExecute(con, "PRAGMA journal_mode = WAL;")
DBI::dbExecute(con, "PRAGMA synchronous = NORMAL;")
DBI::dbExecute(con, "PRAGMA temp_store = MEMORY;")

select_sql <- paste(
  "SELECT oracle_id, id AS scryfall_id, name, lang, layout, mana_cost, cmc,",
  "       type_line, oracle_text, power, toughness, loyalty, defense,",
  "       colors, color_identity, keywords, card_faces, produced_mana,",
  "       \"set\" AS set_code, set_name, rarity, edhrec_rank",
  "  FROM cards",
  " WHERE oracle_id IS NOT NULL AND oracle_id <> ''",
  " ORDER BY oracle_id"
)
if (is.finite(limit_env) && limit_env > 0L) {
  select_sql <- paste(select_sql, "LIMIT", limit_env)
}

# Distinct-by-oracle_id is achieved by grouping on a single row per oracle_id.
# We just take the first printing seen, which is enough for mechanic data
# (oracle text is the same across printings of the same oracle_id).
total_query <- if (is.finite(limit_env) && limit_env > 0L) {
  sprintf("SELECT COUNT(DISTINCT oracle_id) AS n FROM (SELECT oracle_id FROM cards WHERE oracle_id IS NOT NULL AND oracle_id <> '' LIMIT %d)", limit_env)
} else {
  "SELECT COUNT(DISTINCT oracle_id) AS n FROM cards WHERE oracle_id IS NOT NULL AND oracle_id <> ''"
}
n_oracle <- DBI::dbGetQuery(con, total_query)$n
message(sprintf("[enrich] %d distinct oracle_ids to process", n_oracle))

# ---- Drop & recreate enriched tables ---------------------------------------
enriched_tables <- c(
  "cards_enriched",
  "card_keywords", "card_mechanics",
  "card_roles", "card_target_roles", "card_strategy_tags",
  "card_produced_events", "card_consumed_events",
  "card_replaced_events", "card_prevented_events",
  "card_setup_events", "card_finisher_events",
  "card_anti_tags", "enrichment_meta"
)
for (tbl in enriched_tables) {
  DBI::dbExecute(con, sprintf("DROP TABLE IF EXISTS %s", tbl))
}

DBI::dbExecute(con, "
  CREATE TABLE cards_enriched (
    oracle_id           TEXT NOT NULL,
    face_index          INTEGER NOT NULL,
    face_name           TEXT,
    name                TEXT,
    scryfall_id         TEXT,
    layout              TEXT,
    set_code            TEXT,
    set_name            TEXT,
    rarity              TEXT,
    edhrec_rank         INTEGER,
    mana_cost           TEXT,
    mana_value          REAL,
    cmc                 REAL,
    type_line           TEXT,
    oracle_text         TEXT,
    power               TEXT,
    toughness           TEXT,
    loyalty             TEXT,
    colors              TEXT,
    color_identity      TEXT,
    produced_mana       TEXT,
    keywords            TEXT,
    mechanics           TEXT,
    roles               TEXT,
    target_roles        TEXT,
    strategy_tags       TEXT,
    produced_events     TEXT,
    consumed_events     TEXT,
    replaced_events     TEXT,
    prevented_events    TEXT,
    setup_events        TEXT,
    finisher_events     TEXT,
    anti_tags           TEXT,
    cadence_class       TEXT,
    cadence_repeatable  INTEGER,
    cadence_scalable    INTEGER,
    cadence_strength    REAL,
    cadence_contexts_json TEXT,
    cadence_sources_json  TEXT,
    abilities_json      TEXT,
    produces_json       TEXT,
    rewards_json        TEXT,
    requires_json       TEXT,
    replaces_json       TEXT,
    prevents_json       TEXT,
    amplifies_json      TEXT,
    moves_json          TEXT,
    plans_json          TEXT,
    legalities_json     TEXT,
    PRIMARY KEY (oracle_id, face_index)
  )")

# Long tables (oracle_id, face_index, value)
long_specs <- list(
  card_keywords        = "keyword",
  card_mechanics       = "mechanic",
  card_roles           = "role",
  card_target_roles    = "role",
  card_strategy_tags   = "tag",
  card_produced_events = "event",
  card_consumed_events = "event",
  card_replaced_events = "event",
  card_prevented_events= "event",
  card_setup_events    = "event",
  card_finisher_events = "event",
  card_anti_tags       = "tag"
)
for (tbl in names(long_specs)) {
  col <- long_specs[[tbl]]
  DBI::dbExecute(con, sprintf("
    CREATE TABLE %s (
      oracle_id  TEXT NOT NULL,
      face_index INTEGER NOT NULL,
      %s         TEXT NOT NULL
    )", tbl, col))
}

# ---- Iterate ----------------------------------------------------------------
message("[enrich] reading source rows ...")
all_rows <- DBI::dbGetQuery(con, select_sql)
message(sprintf("[enrich] %d rows loaded into memory", nrow(all_rows)))

processed <- 0L
seen_oracle <- new.env(parent = emptyenv(), hash = TRUE)
skipped_dupe <- 0L
skipped_error <- 0L
n_rows_written <- 0L
t0 <- Sys.time()

# Wide-row buffers (environment, mutated in-place by $<-)
wide_fields <- list(
  oracle_id = character(), face_index = integer(), face_name = character(),
  name = character(), scryfall_id = character(), layout = character(),
  set_code = character(), set_name = character(), rarity = character(),
  edhrec_rank = integer(),
  mana_cost = character(), mana_value = numeric(), cmc = numeric(),
  type_line = character(), oracle_text = character(),
  power = character(), toughness = character(), loyalty = character(),
  colors = character(), color_identity = character(), produced_mana = character(),
  keywords = character(), mechanics = character(), roles = character(),
  target_roles = character(), strategy_tags = character(),
  produced_events = character(), consumed_events = character(),
  replaced_events = character(), prevented_events = character(),
  setup_events = character(), finisher_events = character(),
  anti_tags = character(),
  cadence_class = character(),
  cadence_repeatable = integer(), cadence_scalable = integer(),
  cadence_strength = numeric(),
  cadence_contexts_json = character(), cadence_sources_json = character(),
  abilities_json = character(), produces_json = character(),
  rewards_json = character(), requires_json = character(),
  replaces_json = character(), prevents_json = character(),
  amplifies_json = character(),
  moves_json = character(), plans_json = character(),
  legalities_json = character()
)
W <- list2env(wide_fields, parent = emptyenv())

# Long-row buffers: list of environments
L <- setNames(
  lapply(names(long_specs), function(t) {
    list2env(
      list(oracle_id = character(), face_index = integer(), value = character()),
      parent = emptyenv()
    )
  }),
  names(long_specs)
)

flush_buffers <- function() {
  if (length(W$oracle_id) == 0L) return(invisible(NULL))
  wide_df <- as.data.frame(as.list(W), stringsAsFactors = FALSE)
  # Re-order columns to match the table definition.
  wide_df <- wide_df[, names(wide_fields), drop = FALSE]
  DBI::dbAppendTable(con, "cards_enriched", wide_df)
  for (tbl in names(L)) {
    if (length(L[[tbl]]$oracle_id) == 0L) next
    col <- long_specs[[tbl]]
    df <- data.frame(
      oracle_id  = L[[tbl]]$oracle_id,
      face_index = L[[tbl]]$face_index,
      v          = L[[tbl]]$value,
      stringsAsFactors = FALSE
    )
    names(df)[3] <- col
    DBI::dbAppendTable(con, tbl, df)
  }
  # reset (in-place via environment $<-)
  for (k in names(wide_fields)) W[[k]] <- wide_fields[[k]]
  for (tbl in names(L)) {
    L[[tbl]]$oracle_id  <- character()
    L[[tbl]]$face_index <- integer()
    L[[tbl]]$value      <- character()
  }
  invisible(NULL)
}

# Build legalities JSON from the wide row
legalities_for_row <- function(row) {
  cols <- grep("^legalities\\.", names(row), value = TRUE)
  if (!length(cols)) return(NA_character_)
  lst <- as.list(row[, cols, drop = TRUE])
  names(lst) <- sub("^legalities\\.", "", cols)
  lst <- lapply(lst, function(v) {
    if (is.null(v) || length(v) == 0L) return(NA_character_)
    s <- v[[1]]
    if (is.na(s)) NA_character_ else as.character(s)
  })
  encode_json(lst)
}

repeat_chunks <- split(
  seq_len(nrow(all_rows)),
  ceiling(seq_len(nrow(all_rows)) / chunk_size)
)

for (chunk_idx in seq_along(repeat_chunks)) {
  rows_idx <- repeat_chunks[[chunk_idx]]
  chunk <- all_rows[rows_idx, , drop = FALSE]

  for (i in seq_len(nrow(chunk))) {
    row <- chunk[i, , drop = FALSE]
    oid <- scalar_or_na(row$oracle_id)
    if (is.na(oid) || !nzchar(oid)) next
    if (exists(oid, envir = seen_oracle, inherits = FALSE)) {
      skipped_dupe <- skipped_dupe + 1L
      next
    }
    assign(oid, TRUE, envir = seen_oracle)

    plan <- plan_faces(row)
    leg_json <- NA_character_  # legalities stored on cards table directly
    # (we did not select legalities columns to keep memory small; query separately if needed)

    for (face_spec in plan) {
      card_obj <- build_card_obj(row, face_spec$face)
      norm <- tryCatch(
        query_synergy_normalize_card(
          card_obj,
          registry        = registry,
          mechanic_rules  = mechanic_rules,
          ability_parse_rules = parse_rules
        ),
        error = function(e) {
          skipped_error <<- skipped_error + 1L
          NULL
        }
      )
      if (is.null(norm)) next

      fi <- face_spec$face_index
      cad <- norm$cadence
      if (!is.list(cad)) cad <- list()

      # Append wide row (W is an environment -> $<- mutates in place)
      W$oracle_id        <- c(W$oracle_id,        oid)
      W$face_index       <- c(W$face_index,       fi)
      W$face_name        <- c(W$face_name,        face_spec$face_name %||% NA_character_)
      W$name             <- c(W$name,             scalar_or_na(row$name))
      W$scryfall_id      <- c(W$scryfall_id,      scalar_or_na(row$scryfall_id))
      W$layout           <- c(W$layout,           scalar_or_na(row$layout))
      W$set_code         <- c(W$set_code,         scalar_or_na(row$set_code))
      W$set_name         <- c(W$set_name,         scalar_or_na(row$set_name))
      W$rarity           <- c(W$rarity,           scalar_or_na(row$rarity))
      er <- suppressWarnings(as.integer(row$edhrec_rank))
      W$edhrec_rank      <- c(W$edhrec_rank,      if (is.finite(er)) er else NA_integer_)
      W$mana_cost        <- c(W$mana_cost,        card_obj$mana_cost %||% NA_character_)
      W$mana_value       <- c(W$mana_value,       as.numeric(norm$mana_value))
      W$cmc              <- c(W$cmc,              num_or_na(row$cmc))
      W$type_line        <- c(W$type_line,        norm$type_line %||% NA_character_)
      W$oracle_text      <- c(W$oracle_text,      norm$oracle_text %||% NA_character_)
      W$power            <- c(W$power,            card_obj$power %||% NA_character_)
      W$toughness        <- c(W$toughness,        card_obj$toughness %||% NA_character_)
      W$loyalty          <- c(W$loyalty,          card_obj$loyalty %||% NA_character_)
      W$colors           <- c(W$colors,           collapse_chr(norm$colors))
      W$color_identity   <- c(W$color_identity,   collapse_chr(norm$color_identity))
      W$produced_mana    <- c(W$produced_mana,    collapse_chr(decode_json(row$produced_mana)))
      W$keywords         <- c(W$keywords,         collapse_chr(norm$keywords))
      W$mechanics        <- c(W$mechanics,        collapse_chr(norm$mechanics))
      W$roles            <- c(W$roles,            collapse_chr(norm$roles))
      W$target_roles     <- c(W$target_roles,     collapse_chr(norm$target_roles))
      W$strategy_tags    <- c(W$strategy_tags,    collapse_chr(norm$strategy_tags))
      W$produced_events  <- c(W$produced_events,  collapse_chr(norm$produced_events))
      W$consumed_events  <- c(W$consumed_events,  collapse_chr(norm$consumed_events))
      W$replaced_events  <- c(W$replaced_events,  collapse_chr(norm$replaced_events))
      W$prevented_events <- c(W$prevented_events, collapse_chr(norm$prevented_events))
      W$setup_events     <- c(W$setup_events,     collapse_chr(norm$setup_events))
      W$finisher_events  <- c(W$finisher_events,  collapse_chr(norm$finisher_events))
      W$anti_tags        <- c(W$anti_tags,        collapse_chr(norm$anti_tags))
      W$cadence_class    <- c(W$cadence_class,    cad$class %||% NA_character_)
      W$cadence_repeatable <- c(W$cadence_repeatable, as.integer(isTRUE(cad$repeatable)))
      W$cadence_scalable   <- c(W$cadence_scalable,   as.integer(isTRUE(cad$scalable)))
      cs <- suppressWarnings(as.numeric(cad$strength)); if (!is.finite(cs)) cs <- NA_real_
      W$cadence_strength <- c(W$cadence_strength, cs)
      W$cadence_contexts_json <- c(W$cadence_contexts_json, encode_json(cad$contexts))
      W$cadence_sources_json  <- c(W$cadence_sources_json,  encode_json(cad$sources))
      W$abilities_json   <- c(W$abilities_json,   encode_json(norm$abilities))
      W$produces_json    <- c(W$produces_json,    encode_json(norm$produces))
      W$rewards_json     <- c(W$rewards_json,     encode_json(norm$rewards))
      W$requires_json    <- c(W$requires_json,    encode_json(norm$requires))
      W$replaces_json    <- c(W$replaces_json,    encode_json(norm$replaces))
      W$prevents_json    <- c(W$prevents_json,    encode_json(norm$prevents))
      W$amplifies_json   <- c(W$amplifies_json,   encode_json(norm$amplifies))
      W$moves_json       <- c(W$moves_json,       encode_json(norm$moves))
      W$plans_json       <- c(W$plans_json,       encode_json(norm$plans))
      W$legalities_json  <- c(W$legalities_json,  encode_json(norm$legalities))

      # Long rows (L[[tbl]] is an environment)
      add_long <- function(tbl, vec) {
        if (is.null(vec)) return(invisible(NULL))
        v <- as.character(vec)
        v <- v[!is.na(v) & nzchar(v)]
        v <- unique(v)
        if (!length(v)) return(invisible(NULL))
        env <- L[[tbl]]
        env$oracle_id  <- c(env$oracle_id,  rep(oid, length(v)))
        env$face_index <- c(env$face_index, rep(fi,  length(v)))
        env$value      <- c(env$value,      v)
        invisible(NULL)
      }
      add_long("card_keywords",        norm$keywords)
      add_long("card_mechanics",       norm$mechanics)
      add_long("card_roles",           norm$roles)
      add_long("card_target_roles",    norm$target_roles)
      add_long("card_strategy_tags",   norm$strategy_tags)
      add_long("card_produced_events", norm$produced_events)
      add_long("card_consumed_events", norm$consumed_events)
      add_long("card_replaced_events", norm$replaced_events)
      add_long("card_prevented_events",norm$prevented_events)
      add_long("card_setup_events",    norm$setup_events)
      add_long("card_finisher_events", norm$finisher_events)
      add_long("card_anti_tags",       norm$anti_tags)

      n_rows_written <- n_rows_written + 1L
    }
    processed <- processed + 1L
  }

  flush_buffers()

  if (chunk_idx %% 2L == 0L || chunk_idx == length(repeat_chunks)) {
    elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
    rate <- if (elapsed > 0) processed / elapsed else NA_real_
    message(sprintf(
      "[enrich] processed=%d  faces=%d  dupes=%d  errors=%d  elapsed=%.1fs  rate=%.0f/s",
      processed, n_rows_written, skipped_dupe, skipped_error, elapsed,
      rate
    ))
  }
}

flush_buffers()

# ---- Indexes ----------------------------------------------------------------
message("[enrich] creating indexes ...")
DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_ce_name ON cards_enriched(name)")
DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_ce_set  ON cards_enriched(set_code)")
DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_ce_type ON cards_enriched(type_line)")
DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_ce_cad  ON cards_enriched(cadence_class)")
for (tbl in names(long_specs)) {
  col <- long_specs[[tbl]]
  DBI::dbExecute(con, sprintf("CREATE INDEX IF NOT EXISTS idx_%s_oid  ON %s(oracle_id, face_index)", tbl, tbl))
  DBI::dbExecute(con, sprintf("CREATE INDEX IF NOT EXISTS idx_%s_val  ON %s(%s)", tbl, tbl, col))
}

# ---- Metadata ---------------------------------------------------------------
meta <- data.frame(
  enriched_at        = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  normalizer_version = "normalized_card_v2",
  precompute_version = query_synergy_precompute_version(),
  oracle_ids         = processed,
  face_rows          = n_rows_written,
  skipped_duplicate  = skipped_dupe,
  skipped_error      = skipped_error,
  source_table       = "cards",
  stringsAsFactors   = FALSE
)
DBI::dbWriteTable(con, "enrichment_meta", meta, overwrite = TRUE)

DBI::dbExecute(con, "VACUUM;")

elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
message(sprintf(
  "[enrich] done. oracle_ids=%d face_rows=%d errors=%d total=%.1fs file=%.1f MB",
  processed, n_rows_written, skipped_error, elapsed,
  file.info(db_path)$size / 1024 / 1024
))
