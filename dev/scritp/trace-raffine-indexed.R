devtools::load_all(".", quiet = TRUE)
cat_res <- query_synergy_get_catalog()
cards <- cat_res$cards
nm <- function(c) tolower(query_api_scalar(c$name, default = ""))
target_idx <- which(vapply(cards, function(c) is.list(c) && grepl("sheoldred, the apocalypse", nm(c), fixed = TRUE), logical(1)))[[1]]
target <- cards[[target_idx]]
target_profile <- query_synergy_build_compact_profile(target)
precomputed <- query_synergy_build_precomputed_catalog(cards)

raffine_oracle_id <- "9307f7e9-bcd9-41f9-88f8-0fb9700a6b12"
raffine_idx_in_precomp <- which(vapply(precomputed$profiles, function(p) identical(p$id, raffine_oracle_id), logical(1)))
cat("raffine indices in precomp:", paste(raffine_idx_in_precomp, collapse=","), "\n")

indexed <- query_synergy_collect_indexed_candidate_indexes(target_profile, precomputed, top_k = 600L)
cat("indexed length:", length(indexed), "\n")
for (ri in raffine_idx_in_precomp) {
  pos <- which(indexed == ri)
  cat("raffine precomp idx", ri, "-> position in 'indexed':", if (length(pos)) pos else "ABSENT", "\n")
}
