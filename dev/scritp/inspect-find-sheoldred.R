devtools::load_all(".", quiet = TRUE)

cat_res <- query_synergy_get_catalog()
cards <- cat_res$cards
res <- query_synergy_find_in_catalog(
  list(
    card_name      = "Sheoldred, the Apocalypse",
    format         = "commander",
    max_results    = 200L,
    top_k          = 600L,
    cheap_scan_cap = 5000L,
    package_top_n  = 6L
  ),
  cards
)

if (isFALSE(res$ok)) {
  cat("ERROR:", res$error, "\n")
  quit(status = 1)
}

best <- res$best_matches
cat("total best_matches:", length(best), "\n\n")

# Show top 20.
cat("=== Top 20 ===\n")
for (i in seq_len(min(20L, length(best)))) {
  e <- best[[i]]
  cat(sprintf("%2d. %-40s score=%3d  bucket=%s\n",
              i,
              substr(query_api_scalar(e$name, default=""), 1, 40),
              as.integer(e$score),
              query_api_scalar(e$bucket, default="")))
}

# Find Raffine.
ranks <- which(vapply(best, function(e) {
  grepl("raffine, scheming seer", tolower(query_api_scalar(e$name, default="")), fixed = TRUE)
}, logical(1)))

cat("\n=== Raffine, Scheming Seer ===\n")
if (length(ranks) == 0L) {
  cat("NOT in top", length(best), "\n")
} else {
  for (r in ranks) {
    e <- best[[r]]
    cat(sprintf("rank=%d  score=%d  bucket=%s\n", r, as.integer(e$score),
                query_api_scalar(e$bucket, default="")))
    cat("  reasons:", paste(head(query_synergy_to_vector(e$reasons), 4), collapse=" | "), "\n")
  }
}
