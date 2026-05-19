# query_card_search.R
# Full-text card search against the local Scryfall oracle SQLite library.
#
# Parameters
#   q        : free text (matches name OR oracle_text, case-insensitive)
#   colors   : comma-separated color codes to require in color_identity, e.g. "W,U"
#   cmc_min  : minimum converted mana cost (integer or "")
#   cmc_max  : maximum converted mana cost (integer or "")
#   type_line: partial match on type_line (e.g. "Creature", "Instant")
#   keywords : partial match on keywords JSON (e.g. "Flying", "Lifelink")
#   limit    : max rows returned (default 60, max 200)
#   offset   : pagination offset (default 0)
#
# Returns a list(ok, count, total, results) where each result is a named list.

query_card_search <- function(
  q        = "",
  colors   = "",
  cmc_min  = "",
  cmc_max  = "",
  type_line = "",
  keywords = "",
  limit    = "60",
  offset   = "0"
) {
  db_check <- query_api_require_db()
  if (!isTRUE(db_check)) {
    return(db_check)
  }

  db_path <- query_card_search_db_path()
  if (!nzchar(db_path) || !file.exists(db_path)) {
    return(query_api_error(
      "Scryfall oracle library not found. Run scripts/download-scryfall-library.R first.",
      results = list()
    ))
  }

  # ── Parse and clamp parameters ───────────────────────────────────────────
  q_val        <- trimws(as.character(q[[1]] %||% ""))
  type_val     <- trimws(as.character(type_line[[1]] %||% ""))
  keywords_val <- trimws(as.character(keywords[[1]] %||% ""))
  colors_raw   <- trimws(as.character(colors[[1]] %||% ""))

  limit_val  <- query_card_search_clamp_int(limit,  1L, 200L, 60L)
  offset_val <- query_card_search_clamp_int(offset, 0L, 50000L, 0L)

  cmc_min_val <- query_card_search_parse_numeric(cmc_min)
  cmc_max_val <- query_card_search_parse_numeric(cmc_max)

  color_codes <- if (nzchar(colors_raw)) {
    toupper(strsplit(colors_raw, "[,; ]+")[[1]])
  } else {
    character(0)
  }
  color_codes <- color_codes[color_codes %in% c("W", "U", "B", "R", "G", "C")]

  # ── Build SQL WHERE clauses ───────────────────────────────────────────────
  where_clauses <- character(0)
  bind_vals     <- list()

  # Exclude non-game objects
  where_clauses <- c(where_clauses,
    "COALESCE(layout, '') NOT IN ('art_series', 'token', 'double_faced_token', 'emblem', 'vanguard', 'scheme', 'planar')"
  )
  where_clauses <- c(where_clauses,
    "lang = 'en'"
  )

  # Free text search on name + oracle_text
  if (nzchar(q_val)) {
    where_clauses <- c(where_clauses,
      "(lower(name) LIKE '%' || lower(:q) || '%' OR lower(COALESCE(oracle_text,'')) LIKE '%' || lower(:q) || '%')"
    )
    bind_vals[["q"]] <- q_val
  }

  # Type line partial match
  if (nzchar(type_val)) {
    where_clauses <- c(where_clauses,
      "lower(COALESCE(type_line, '')) LIKE '%' || lower(:type_val) || '%'"
    )
    bind_vals[["type_val"]] <- type_val
  }

  # Keywords partial match (stored as JSON array text)
  if (nzchar(keywords_val)) {
    where_clauses <- c(where_clauses,
      "lower(COALESCE(keywords, '')) LIKE '%' || lower(:keywords_val) || '%'"
    )
    bind_vals[["keywords_val"]] <- keywords_val
  }

  # CMC range
  if (is.finite(cmc_min_val)) {
    where_clauses <- c(where_clauses, "COALESCE(cmc, 0) >= :cmc_min")
    bind_vals[["cmc_min"]] <- cmc_min_val
  }
  if (is.finite(cmc_max_val)) {
    where_clauses <- c(where_clauses, "COALESCE(cmc, 0) <= :cmc_max")
    bind_vals[["cmc_max"]] <- cmc_max_val
  }

  # Color identity filter — each required color must appear in the JSON string
  if (length(color_codes) > 0) {
    for (ci in seq_along(color_codes)) {
      code <- color_codes[[ci]]
      param_name <- paste0("color_", ci)
      where_clauses <- c(where_clauses,
        sprintf("lower(COALESCE(color_identity, '')) LIKE '%%' || lower(:%s) || '%%'", param_name)
      )
      bind_vals[[param_name]] <- code
    }
  }

  where_sql <- if (length(where_clauses) > 0) {
    paste("WHERE", paste(where_clauses, collapse = "\n  AND "))
  } else {
    ""
  }

  count_sql <- sprintf("SELECT COUNT(*) AS n FROM cards %s", where_sql)
  data_sql  <- sprintf(
    "SELECT id, name, mana_cost, cmc, type_line, oracle_text, colors, color_identity, keywords, rarity, \"set\" AS set_code, set_name, collector_number
     FROM cards
     %s
     ORDER BY name ASC
     LIMIT :lim OFFSET :off",
    where_sql
  )

  bind_vals[["lim"]] <- limit_val
  bind_vals[["off"]] <- offset_val

  # ── Query ─────────────────────────────────────────────────────────────────
  con <- tryCatch(
    query_db_connect(db_path),
    error = function(e) NULL
  )
  if (is.null(con)) {
    return(query_api_error("Failed to connect to Scryfall oracle database.", results = list()))
  }
  on.exit(tryCatch(DBI::dbDisconnect(con), error = function(e) NULL), add = TRUE)

  total <- tryCatch({
    row <- DBI::dbGetQuery(con, count_sql, params = bind_vals[names(bind_vals) != "lim" & names(bind_vals) != "off"])
    as.integer(row$n[[1]] %||% 0L)
  }, error = function(e) 0L)

  rows <- tryCatch(
    DBI::dbGetQuery(con, data_sql, params = bind_vals),
    error = function(e) {
      message("[card_search] SQL error: ", conditionMessage(e))
      data.frame()
    }
  )

  results <- if (is.data.frame(rows) && nrow(rows) > 0) {
    lapply(seq_len(nrow(rows)), function(i) {
      r <- rows[i, , drop = FALSE]
      list(
        id             = query_api_scalar(r$id),
        name           = query_api_scalar(r$name),
        mana_cost      = query_api_scalar(r$mana_cost),
        cmc            = as.numeric(r$cmc %||% 0),
        type_line      = query_api_scalar(r$type_line),
        oracle_text    = query_api_scalar(r$oracle_text),
        colors         = query_api_scalar(r$colors),
        color_identity = query_api_scalar(r$color_identity),
        keywords       = query_api_scalar(r$keywords),
        rarity         = query_api_scalar(r$rarity),
        set_code       = query_api_scalar(r$set_code),
        set_name       = query_api_scalar(r$set_name),
        collector_number = query_api_scalar(r$collector_number)
      )
    })
  } else {
    list()
  }

  list(
    ok      = TRUE,
    total   = total,
    count   = length(results),
    limit   = limit_val,
    offset  = offset_val,
    results = results
  )
}

# ── Helpers ──────────────────────────────────────────────────────────────────

query_card_search_db_path <- function() {
  candidates <- c(
    Sys.getenv("SCRYFALL_DB_PATH", unset = ""),
    file.path(system.file("collection", package = "mtgcodex.api", mustWork = FALSE), "library_scryfall.sqlite"),
    file.path("inst", "collection", "library_scryfall.sqlite")
  )
  for (p in candidates) {
    if (nzchar(p) && file.exists(p)) return(p)
  }
  ""
}

query_card_search_clamp_int <- function(value, min_val, max_val, default) {
  parsed <- suppressWarnings(as.integer(value[[1]] %||% default))
  if (is.na(parsed) || !is.finite(parsed)) return(default)
  max(min_val, min(max_val, parsed))
}

query_card_search_parse_numeric <- function(value) {
  raw <- trimws(as.character(value[[1]] %||% ""))
  if (!nzchar(raw)) return(NA_real_)
  parsed <- suppressWarnings(as.numeric(raw))
  if (is.na(parsed) || !is.finite(parsed)) return(NA_real_)
  parsed
}
