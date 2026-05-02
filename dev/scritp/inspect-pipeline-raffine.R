devtools::load_all(".", quiet = TRUE)

# Trouve Raffine et Sheoldred dans le catalog enrichi.
catalog_res <- query_synergy_get_catalog()
catalog <- catalog_res$cards
cat("catalog length:", length(catalog), "  source:", catalog_res$source, "\n")
nm <- function(c) {
  if (!is.list(c)) return("")
  tolower(query_api_scalar(c$name, default = ""))
}
sheoldred_idx <- which(vapply(catalog, function(c) grepl("sheoldred, the apocalypse", nm(c), fixed = TRUE), logical(1)))
raffine_idx   <- which(vapply(catalog, function(c) grepl("raffine, scheming seer", nm(c), fixed = TRUE), logical(1)))

cat("sheoldred_idx:", sheoldred_idx, "\n")
cat("raffine_idx:  ", raffine_idx, "\n")

if (length(sheoldred_idx) && length(raffine_idx)) {
  sh <- catalog[[sheoldred_idx[[1]]]]
  ra <- catalog[[raffine_idx[[1]]]]

  cat("\n=== Sheoldred ===\n")
  cat("color_identity :", paste(sh$color_identity, collapse=","), "\n")
  cat("consumed_events:", paste(sh$consumed_events, collapse=","), "\n")
  cat("produced_events:", paste(sh$produced_events, collapse=","), "\n")
  cat("\n=== Raffine ===\n")
  cat("color_identity :", paste(ra$color_identity, collapse=","), "\n")
  cat("consumed_events:", paste(ra$consumed_events, collapse=","), "\n")
  cat("produced_events:", paste(ra$produced_events, collapse=","), "\n")

  # Cheap score Sheoldred-as-target, Raffine-as-candidate.
  sh_profile <- query_synergy_build_compact_profile(sh)
  ra_profile <- query_synergy_build_compact_profile(ra)
  cs <- query_synergy_score_candidate_lightweight(sh_profile, ra_profile)
  cat("\ncheap_score(sh -> ra):", cs$score, "\n")

  # Deep score in both directions.
  fwd <- query_synergy_score_pair(sh, ra)
  bwd <- query_synergy_score_pair(ra, sh)
  cat("deep score(sh -> ra):", fwd$score, "\n")
  cat("deep score(ra -> sh):", bwd$score, "\n")
}
