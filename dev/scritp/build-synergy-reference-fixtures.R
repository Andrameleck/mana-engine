# Build reference card fixtures from the enriched Scryfall library.
#
# Output: tests/testthat/fixtures/synergy_reference_cards.json
#
# We pick a small, deterministic set of cards covering:
#   * showcase cards (Bloodghast, Entomb, Sol Ring, ...)
#   * one card per major named mechanic (connive, dredge, cycling, ...)
#
# The fixture stores RAW Scryfall fields only (no normalization output),
# so snapshot tests can re-run the engine and compare against the locked
# snapshots. This keeps fixtures stable even when Scryfall ships new sets.

suppressPackageStartupMessages({
  library(DBI); library(RSQLite); library(jsonlite)
})

db_path <- file.path("inst", "collection", "library_scryfall.sqlite")
out_path <- file.path("tests", "testthat", "fixtures",
                      "synergy_reference_cards.json")
dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)

con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
on.exit(DBI::dbDisconnect(con), add = TRUE)

# ---- Showcase cards (always included) --------------------------------------
showcase <- c(
  "Bloodghast", "Entomb", "Sol Ring", "Tarmogoyf",
  "Dockside Extortionist", "Reckoner Bankbuster",
  "Birgi, God of Storytelling // Harnfel, Horn of Bounty",
  "Lightning Bolt", "Counterspell", "Dark Ritual",
  "Skullclamp", "Bitterblossom",
  "Yawgmoth, Thran Physician", "Necropotence",
  "Smothering Tithe", "Rhystic Study"
)

# ---- Per-mechanic anchors --------------------------------------------------
# For each mechanic, pick the card with the LOWEST oracle_id alphabetically
# whose oracle_text actually contains the mechanic word — deterministic and
# avoids surprises from new sets reshuffling rankings.
mechanics <- c(
  "connive", "dredge", "surveil", "exploit", "madness",
  "flashback", "cascade", "discover", "populate", "investigate",
  "casualty", "lifelink", "foretell", "delve", "escape",
  "blitz", "offspring", "cycling", "convoke", "embalm",
  "eternalize", "amass", "adapt", "afflict", "afterlife",
  "ascend", "boast", "champion", "cleave", "cipher",
  "conspire", "crew", "daybound", "devotion", "encore",
  "evoke", "kicker", "miracle", "mutate", "ninjutsu",
  "outlast", "overload", "persist", "phasing", "prowess",
  "rebound", "reinforce", "renown", "ripple", "scry",
  "soulshift", "splice", "storm", "suspend", "transmute",
  "unearth", "unleash", "venture", "vigilance", "ward"
)

mech_query <- paste(
  "SELECT name, oracle_id, oracle_text, type_line, mana_cost, cmc,",
  "       power, toughness, loyalty, colors, color_identity,",
  "       keywords, layout, card_faces",
  "  FROM cards",
  " WHERE oracle_text LIKE ?",
  " ORDER BY oracle_id LIMIT 1"
)

mech_rows <- lapply(mechanics, function(m) {
  res <- DBI::dbGetQuery(con, mech_query, params = list(paste0("%", m, "%")))
  if (!nrow(res)) return(NULL)
  res$mechanic_anchor <- m
  res
})
mech_df <- do.call(rbind, Filter(Negate(is.null), mech_rows))

# ---- Showcase rows ---------------------------------------------------------
show_query <- paste(
  "SELECT name, oracle_id, oracle_text, type_line, mana_cost, cmc,",
  "       power, toughness, loyalty, colors, color_identity,",
  "       keywords, layout, card_faces",
  "  FROM cards WHERE name = ? LIMIT 1"
)
show_rows <- lapply(showcase, function(n) {
  r <- DBI::dbGetQuery(con, show_query, params = list(n))
  if (!nrow(r)) return(NULL)
  r$mechanic_anchor <- NA_character_
  r
})
show_df <- do.call(rbind, Filter(Negate(is.null), show_rows))

# ---- Combine + dedupe ------------------------------------------------------
all_df <- rbind(show_df, mech_df)
all_df <- all_df[!duplicated(all_df$oracle_id), ]

cat(sprintf("[fixtures] picked %d unique cards (%d showcase + %d mechanic anchors)\n",
            nrow(all_df), nrow(show_df), nrow(mech_df)))

# ---- Decode JSON list-cols and build clean records -------------------------
`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1L && is.na(a))) b else a
unbox <- jsonlite::unbox

parse_json_cell <- function(x) {
  if (is.null(x) || is.na(x) || !nzchar(x) || identical(x, "null")) return(NULL)
  tryCatch(jsonlite::fromJSON(x, simplifyVector = TRUE),
           error = function(e) NULL)
}

records <- lapply(seq_len(nrow(all_df)), function(i) {
  r <- all_df[i, , drop = FALSE]
  list(
    oracle_id        = unbox(r$oracle_id),
    name             = unbox(r$name),
    oracle_text      = unbox(r$oracle_text %||% ""),
    type_line        = unbox(r$type_line %||% ""),
    mana_cost        = unbox(r$mana_cost %||% ""),
    cmc              = unbox(suppressWarnings(as.numeric(r$cmc))),
    power            = unbox(r$power %||% ""),
    toughness        = unbox(r$toughness %||% ""),
    loyalty          = unbox(r$loyalty %||% ""),
    layout           = unbox(r$layout %||% ""),
    colors           = parse_json_cell(r$colors)         %||% character(0),
    color_identity   = parse_json_cell(r$color_identity) %||% character(0),
    keywords         = parse_json_cell(r$keywords)       %||% character(0),
    card_faces       = parse_json_cell(r$card_faces),
    mechanic_anchor  = unbox(r$mechanic_anchor %||% NA_character_)
  )
})

# Sort by name for stable diffs
records <- records[order(vapply(records, function(x) as.character(x$name), character(1)))]

writeLines(jsonlite::toJSON(records, pretty = TRUE, auto_unbox = FALSE,
                             null = "null", na = "null"),
           out_path)
cat("[fixtures] wrote ", out_path, "\n", sep = "")
