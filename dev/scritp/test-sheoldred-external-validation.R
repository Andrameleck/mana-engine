#!/usr/bin/env Rscript

suppressMessages(devtools::load_all(".", quiet = TRUE))

seed_name <- "Sheoldred, the Apocalypse"
format_name <- "commander"
max_results <- 12L

cat(sprintf("Seed       : %s\n", seed_name))
cat(sprintf("Format     : %s\n", format_name))
cat(sprintf("Max results: %d\n\n", max_results))

# ---------------------------------------------------------------------------
# 1. Heuristic search for Sheoldred, the Apocalypse
# ---------------------------------------------------------------------------
catalog_out <- query_synergy_get_catalog()
if (!isTRUE(catalog_out$ok)) {
  stop(sprintf("catalog load failed: %s", query_api_scalar(catalog_out$error, default = "unknown")))
}

heuristic_out <- query_synergy_find_in_catalog(
  payload = list(
    card_name = seed_name,
    format = format_name,
    max_results = max_results,
    top_k = 128L,
    cheap_scan_cap = 2000L,
    package_top_n = 6L,
    max_groups = 6L
  ),
  catalog = catalog_out$cards
)

if (!isTRUE(heuristic_out$ok)) {
  stop(sprintf("heuristic search failed: %s", query_api_scalar(heuristic_out$error, default = "unknown")))
}

heuristic_entries <- query_synergy_to_list(heuristic_out$best_matches)
heuristic_names <- vapply(heuristic_entries, function(entry) {
  query_api_scalar(entry$name, default = "")
}, character(1))
heuristic_scores <- vapply(heuristic_entries, function(entry) {
  query_synergy_as_int(entry$score, default = 0L, min_value = 0L, max_value = 100L)
}, integer(1))

cat("=== 1. Heuristic results ===\n")
if (length(heuristic_entries) == 0L) {
  cat("(no heuristic results)\n")
} else {
  for (index in seq_along(heuristic_entries)) {
    cat(sprintf(
      "%2d. %-36s heuristic_score=%3d\n",
      index,
      substr(heuristic_names[[index]], 1, 36),
      heuristic_scores[[index]]
    ))
  }
}
cat("\n")

# Keep the seed plus heuristic result names for the two external API checks.
candidate_names <- unique(c(seed_name, heuristic_names[nzchar(heuristic_names)]))

cat("Cards sent to external validation:\n")
cat(paste0(" - ", candidate_names, collapse = "\n"), "\n\n")

# ---------------------------------------------------------------------------
# 2. Spellbook validation using Sheoldred + heuristic card names
# ---------------------------------------------------------------------------
spellbook_entries <- lapply(heuristic_names[nzchar(heuristic_names)], function(name) list(name = name))
spellbook_out <- query_synergy_validate_spellbook(
  seed_name = seed_name,
  entries = spellbook_entries,
  groups = list(),
  limit = 40L
)

cat("=== 2. Spellbook validation ===\n")
if (!isTRUE(spellbook_out$ok)) {
  cat(sprintf("Spellbook ERROR: %s\n\n", query_api_scalar(spellbook_out$error, default = "unknown")))
} else {
  cat(sprintf("variants_checked=%d\n", query_synergy_as_int(spellbook_out$variant_count, default = 0L, min_value = 0L, max_value = 100000L)))
  if (length(spellbook_out$entries) == 0L) {
    cat("(no spellbook validation rows)\n")
  } else {
    for (entry in query_synergy_to_list(spellbook_out$entries)) {
      cat(sprintf(
        "  %-36s score=%.3f refs=%d popularity=%.1f\n",
        substr(query_api_scalar(entry$name, default = ""), 1, 36),
        query_synergy_as_num(entry$score, default = 0, min_value = 0, max_value = 1),
        query_synergy_as_int(entry$refs, default = 0L, min_value = 0L, max_value = 100000L),
        query_synergy_as_num(entry$matched_popularity, default = 0, min_value = 0)
      ))
    }
  }
  cat("\n")
}

# ---------------------------------------------------------------------------
# 3. Lotus Noir validation using Sheoldred + heuristic card names
# ---------------------------------------------------------------------------
lotus_entries <- lapply(heuristic_names[nzchar(heuristic_names)], function(name) list(name = name))
lotus_out <- query_synergy_validate_lotusnoir(
  seed_name = seed_name,
  entries = lotus_entries,
  groups = list(),
  limit = 120L
)

cat("=== 3. Lotus Noir validation ===\n")
if (!isTRUE(lotus_out$ok)) {
  cat(sprintf("Lotus Noir ERROR: %s\n\n", query_api_scalar(lotus_out$error, default = "unknown")))
} else {
  cat(sprintf("posts_checked=%d\n", query_synergy_as_int(lotus_out$post_count, default = 0L, min_value = 0L, max_value = 100000L)))
  if (length(lotus_out$entries) == 0L) {
    cat("(no lotus validation rows)\n")
  } else {
    for (entry in query_synergy_to_list(lotus_out$entries)) {
      cat(sprintf(
        "  %-36s score=%.3f refs=%d\n",
        substr(query_api_scalar(entry$name, default = ""), 1, 36),
        query_synergy_as_num(entry$score, default = 0, min_value = 0, max_value = 1),
        query_synergy_as_int(entry$refs, default = 0L, min_value = 0L, max_value = 100000L)
      ))
    }
  }
  cat("\n")
}

# ---------------------------------------------------------------------------
# 4. Final recap table
# ---------------------------------------------------------------------------
spellbook_map <- setNames(
  query_synergy_to_list(spellbook_out$entries),
  vapply(query_synergy_to_list(spellbook_out$entries), function(entry) {
    query_synergy_external_key(query_api_scalar(entry$name, default = ""))
  }, character(1))
)

lotus_map <- setNames(
  query_synergy_to_list(lotus_out$entries),
  vapply(query_synergy_to_list(lotus_out$entries), function(entry) {
    query_synergy_external_key(query_api_scalar(entry$name, default = ""))
  }, character(1))
)

recap <- data.frame(
  seed = character(0),
  card_name = character(0),
  heuristic_score = integer(0),
  spellbook_score = numeric(0),
  spellbook_refs = integer(0),
  lotus_score = numeric(0),
  lotus_refs = integer(0),
  stringsAsFactors = FALSE
)

for (index in seq_along(heuristic_names)) {
  name <- heuristic_names[[index]]
  key <- query_synergy_external_key(name)
  sb <- if (nzchar(key) && !is.null(spellbook_map[[key]])) spellbook_map[[key]] else list(score = 0, refs = 0L)
  ln <- if (nzchar(key) && !is.null(lotus_map[[key]])) lotus_map[[key]] else list(score = 0, refs = 0L)

  recap[nrow(recap) + 1L, ] <- list(
    seed = seed_name,
    card_name = name,
    heuristic_score = heuristic_scores[[index]],
    spellbook_score = round(query_synergy_as_num(sb$score, default = 0, min_value = 0, max_value = 1), 3),
    spellbook_refs = query_synergy_as_int(sb$refs, default = 0L, min_value = 0L, max_value = 100000L),
    lotus_score = round(query_synergy_as_num(ln$score, default = 0, min_value = 0, max_value = 1), 3),
    lotus_refs = query_synergy_as_int(ln$refs, default = 0L, min_value = 0L, max_value = 100000L)
  )
}

cat("=== 4. Recap table ===\n")
print(recap, row.names = FALSE)
