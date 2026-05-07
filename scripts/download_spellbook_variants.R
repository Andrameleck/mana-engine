#!/usr/bin/env Rscript
# Query Commander Spellbook variants and save results to JSON.
#
# Usage:
#   Rscript scripts/download_spellbook_variants.R
#
# Environment variables:
#   SPELLBOOK_QUERY        Search query (required)
#   SPELLBOOK_LIMIT        Max variants to fetch. Default: 40
#   SPELLBOOK_OUTPUT_PATH  Output JSON path.
#                          Default: inst/decks/spellbook_variants.json

suppressMessages(devtools::load_all(".", quiet = TRUE))

query <- trimws(Sys.getenv("SPELLBOOK_QUERY", unset = ""))
if (!nzchar(query)) {
  stop("SPELLBOOK_QUERY is required")
}

limit <- suppressWarnings(as.integer(Sys.getenv("SPELLBOOK_LIMIT", unset = "40")))
if (is.na(limit) || limit < 1L) {
  limit <- 40L
}

output_path <- trimws(Sys.getenv(
  "SPELLBOOK_OUTPUT_PATH",
  unset = file.path("inst", "decks", "spellbook_variants.json")
))
if (!nzchar(output_path)) {
  stop("SPELLBOOK_OUTPUT_PATH must not be empty")
}
dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)

cat("=== Commander Spellbook variants ===\n")
cat(sprintf("Query       : %s\n", query))
cat(sprintf("Limit       : %d\n", limit))
cat(sprintf("Output path : %s\n\n", output_path))

result <- query_spellbook_variants(q = query, limit = as.character(limit))
if (!isTRUE(result$ok)) {
  stop(sprintf("Spellbook query failed: %s", query_api_scalar(result$error, default = "unknown")))
}

if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("jsonlite package is required")
}

jsonlite::write_json(result, path = output_path, pretty = TRUE, auto_unbox = TRUE, null = "null")

cat(sprintf("Done — count=%d saved=%s\n", result$count %||% 0L, output_path))
