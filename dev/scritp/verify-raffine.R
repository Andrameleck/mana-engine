devtools::load_all(".", quiet = TRUE)

cat_res <- query_synergy_get_catalog()
cards <- cat_res$cards

t0 <- Sys.time()
res <- query_synergy_find_in_catalog(
  list(
    card_name      = "Sheoldred, the Apocalypse",
    format         = "commander",
    max_results    = 200L,
    top_k          = 600L,
    cheap_scan_cap = 12000L,
    package_top_n  = 0L
  ),
  cards
)
cat(sprintf("elapsed: %.1fs\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))

if (isFALSE(res$ok)) {
  cat("ERROR:", res$error, "\n"); quit(status = 1)
}

best <- res$best_matches
cat("total best_matches:", length(best), "\n")
cat("pipeline$cheap_scan_count:", res$pipeline$cheap_scan_count, "\n")
cat("pipeline$indexed_candidate_count:", res$pipeline$indexed_candidate_count, "\n")
cat("pipeline$deep_score_count:", res$pipeline$deep_score_count, "\n\n")

ranks <- which(vapply(best, function(e) {
  grepl("raffine, scheming seer", tolower(query_api_scalar(e$name, default = "")), fixed = TRUE)
}, logical(1)))

if (length(ranks) == 0L) {
  cat("Raffine NOT in top", length(best), "\n")
} else {
  for (r in ranks) {
    e <- best[[r]]
    cat(sprintf("Raffine: rank=%d  score=%d  bucket=%s\n",
                r, as.integer(e$score),
                query_api_scalar(e$bucket, default = "")))
    cat("  reasons:", paste(head(query_synergy_to_vector(e$reasons), 4), collapse = " | "), "\n")
  }
}

cat("\n=== top 10 ===\n")
for (i in seq_len(min(10L, length(best)))) {
  e <- best[[i]]
  cat(sprintf("%2d. %-42s score=%3d  bucket=%s\n",
              i, substr(query_api_scalar(e$name, default = ""), 1, 42),
              as.integer(e$score), query_api_scalar(e$bucket, default = "")))
}
