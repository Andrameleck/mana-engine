#!/usr/bin/env Rscript
# Query MTGJSON cards and save results to JSON.
#
# Usage:
#   Rscript scripts/download_mtgjson_cards.R
#
# Environment variables:
#   MTGJSON_SET_CODE         Set code (required unless MTGJSON_UUID is set)
#   MTGJSON_UUID             Card UUID (required unless MTGJSON_SET_CODE is set)
#   MTGJSON_QUERY            Name filter (optional)
#   MTGJSON_COLLECTOR_NUMBER Collector number filter (optional)
#   MTGJSON_LIMIT            Max cards to return. Default: 40
#   MTGJSON_OUTPUT_PATH      Output JSON path.
#                            Default: inst/decks/mtgjson_cards.json

suppressMessages(devtools::load_all(".", quiet = TRUE))

set_code <- trimws(Sys.getenv("MTGJSON_SET_CODE", unset = ""))
uuid <- trimws(Sys.getenv("MTGJSON_UUID", unset = ""))
query <- trimws(Sys.getenv("MTGJSON_QUERY", unset = ""))
collector_number <- trimws(Sys.getenv("MTGJSON_COLLECTOR_NUMBER", unset = ""))

if (!nzchar(set_code) && !nzchar(uuid)) {
  stop("Provide MTGJSON_SET_CODE or MTGJSON_UUID")
}

limit <- suppressWarnings(as.integer(Sys.getenv("MTGJSON_LIMIT", unset = "40")))
if (is.na(limit) || limit < 1L) {
  limit <- 40L
}

output_path <- trimws(Sys.getenv(
  "MTGJSON_OUTPUT_PATH",
  unset = file.path("inst", "decks", "mtgjson_cards.json")
))
if (!nzchar(output_path)) {
  stop("MTGJSON_OUTPUT_PATH must not be empty")
}
dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)

cat("=== MTGJSON cards ===\n")
if (nzchar(set_code)) {
  cat(sprintf("Set code      : %s\n", set_code))
}
if (nzchar(uuid)) {
  cat(sprintf("UUID          : %s\n", uuid))
}
if (nzchar(query)) {
  cat(sprintf("Name filter   : %s\n", query))
}
if (nzchar(collector_number)) {
  cat(sprintf("Collector #   : %s\n", collector_number))
}
cat(sprintf("Limit         : %d\n", limit))
cat(sprintf("Output path   : %s\n\n", output_path))

result <- query_mtgjson_cards(
  q = query,
  set_code = set_code,
  collector_number = collector_number,
  uuid = uuid,
  limit = as.character(limit)
)

if (!isTRUE(result$ok)) {
  stop(sprintf("MTGJSON query failed: %s", query_api_scalar(result$error, default = "unknown")))
}

if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("jsonlite package is required")
}

jsonlite::write_json(result, path = output_path, pretty = TRUE, auto_unbox = TRUE, null = "null")

cat(sprintf("Done — count=%d saved=%s\n", result$count %||% 0L, output_path))
