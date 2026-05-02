devtools::load_all(".", quiet = TRUE)

cat_res <- query_synergy_get_catalog()
cards <- cat_res$cards
nm <- function(c) tolower(query_api_scalar(c$name, default = ""))
target_idx <- which(vapply(cards, function(c) is.list(c) && grepl("sheoldred, the apocalypse", nm(c), fixed = TRUE), logical(1)))[[1]]
raffine_oracle_id <- {
  ridx <- which(vapply(cards, function(c) is.list(c) && grepl("raffine, scheming seer", nm(c), fixed = TRUE), logical(1)))[[1]]
  cards[[ridx]]$id
}
cat("Sheoldred catalog idx:", target_idx, "\n")
cat("Raffine oracle_id:    ", raffine_oracle_id, "\n\n")

target <- cards[[target_idx]]
target_profile <- query_synergy_build_compact_profile(target)
precomputed <- query_synergy_build_precomputed_catalog(cards)

# ---- step 1: candidate index filter ------------------------------------
indexed <- query_synergy_collect_indexed_candidate_indexes(target_profile, precomputed, top_k = 600L)
eligible <- Filter(function(i) {
  p <- precomputed$profiles[[i]]
  cid <- query_api_scalar(p$id, default = "")
  nzchar(cid) && !identical(cid, target$id)
}, seq_along(precomputed$profiles))
raffine_pos_in_eligible <- which(vapply(eligible, function(i) identical(precomputed$profiles[[i]]$id, raffine_oracle_id), logical(1)))
cat("eligible total           :", length(eligible), "\n")
cat("raffine pos in eligible  :", if (length(raffine_pos_in_eligible)) raffine_pos_in_eligible else "ABSENT", "\n")
cat("raffine in 'indexed' set :", any(vapply(indexed, function(i) identical(precomputed$profiles[[i]]$id, raffine_oracle_id), logical(1))), "\n")

# ---- step 2: cheap-scan top-K -----------------------------------------
candidate_indexes <- eligible
cheap_cap <- 1500L
if (length(candidate_indexes) > cheap_cap) {
  prio <- c(intersect(indexed, candidate_indexes), setdiff(candidate_indexes, indexed))
  candidate_indexes <- prio[seq_len(cheap_cap)]
}
cat("after cheap_cap          :", length(candidate_indexes), "\n")
cat("raffine still in cap     :", any(vapply(candidate_indexes, function(i) identical(precomputed$profiles[[i]]$id, raffine_oracle_id), logical(1))), "\n")

light_scores <- lapply(candidate_indexes, function(i) {
  list(index = i, cheap_score = query_synergy_score_candidate_lightweight(target_profile, precomputed$profiles[[i]], "commander")$score)
})
light_scores <- light_scores[order(-vapply(light_scores, function(e) e$cheap_score, numeric(1)))]
top_k_keep <- 600L
if (length(light_scores) > top_k_keep) light_scores <- light_scores[seq_len(top_k_keep)]
raffine_top_k_pos <- which(vapply(light_scores, function(e) identical(precomputed$profiles[[e$index]]$id, raffine_oracle_id), logical(1)))
cat("after top_k=600          :", length(light_scores), "\n")
cat("raffine pos in top_k     :", if (length(raffine_top_k_pos)) raffine_top_k_pos else "ABSENT", "\n")
if (length(raffine_top_k_pos)) {
  cat("raffine cheap_score      :", light_scores[[raffine_top_k_pos]]$cheap_score, "\n")
}

# ---- step 3: deep scoring for Raffine specifically --------------------
if (length(raffine_top_k_pos)) {
  ra_card <- precomputed$normalized[[ light_scores[[raffine_top_k_pos]]$index ]]
  fwd <- query_synergy_score_pair(target, ra_card, "commander")
  bwd <- query_synergy_score_pair(ra_card, target, "commander")
  chosen <- if (isTRUE(bwd$score > fwd$score)) bwd else fwd
  cat("\ndeep fwd (sh->ra) :", fwd$score, "\n")
  cat("deep bwd (ra->sh) :", bwd$score, "\n")
  cat("engine chosen     :", chosen$score, "  bucket:", chosen$primary_bucket, "\n")
}
