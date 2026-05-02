suppressPackageStartupMessages({
  devtools::load_all(".", quiet = TRUE)
})

LOG <- file("diag-raffine-out.txt", open = "wt")
sink(LOG, type = "output", split = FALSE)
sink(LOG, type = "message")
on.exit({ sink(type="message"); sink(type="output"); close(LOG) }, add = TRUE)

reg <- query_synergy_event_registry_default()
cat_res <- query_synergy_get_catalog()
cards <- cat_res$cards
precomputed <- query_synergy_get_precomputed_catalog(cards, registry = reg)
profiles <- precomputed$profiles
normalized <- precomputed$normalized
n <- length(cards)

names_lc <- vapply(cards, function(c) tolower(query_api_scalar(c$name, default = "")), character(1))
sh_idx <- which(names_lc == "sheoldred, the apocalypse")[1]
ra_idx <- which(names_lc == "raffine, scheming seer")[1]
stopifnot(!is.na(sh_idx), !is.na(ra_idx))

target_profile <- profiles[[sh_idx]]
ra_profile     <- profiles[[ra_idx]]

cat("Sheoldred consumed_events:\n"); print(target_profile$consumed_events)
cat("Sheoldred produced_events:\n"); print(target_profile$produced_events)
cat("Raffine produced_events:\n");  print(ra_profile$produced_events)
cat("Raffine consumed_events:\n");  print(ra_profile$consumed_events)

cs_ra <- query_synergy_score_candidate_lightweight(target_profile, ra_profile, "commander")
cat("\nRaffine cheap score (sh=target, ra=cand): ", cs_ra$score, "\n", sep = "")
cat("  direct_events: "); print(cs_ra$direct_events)
cat("  reciprocal_events: "); print(cs_ra$reciprocal_events)

cs_ra_rev <- query_synergy_score_candidate_lightweight(ra_profile, target_profile, "commander")
cat("\nRaffine cheap score (ra=target, sh=cand): ", cs_ra_rev$score, "\n", sep = "")

# Compute every cheap score against Sheoldred to see Raffine's rank
cat("\nScanning all candidates...\n")
scores <- integer(n)
t0 <- proc.time()[["elapsed"]]
for (i in seq_len(n)) {
  if (i == sh_idx) { scores[i] <- -1L; next }
  scores[i] <- query_synergy_score_candidate_lightweight(target_profile, profiles[[i]], "commander")$score
}
cat("Scan took ", round(proc.time()[["elapsed"]] - t0, 1), "s\n", sep="")
ord <- order(scores, decreasing = TRUE)
ra_rank <- which(ord == ra_idx)
cat("\nRaffine's cheap-score rank (forward only): ", ra_rank, " / ", n, "  (score=", scores[ra_idx], ")\n", sep="")

cat("\nTop 20 cheap scores (forward):\n")
for (k in seq_len(20)) {
  ix <- ord[k]
  cat(sprintf("%2d. %-45s cheap=%d\n", k, query_api_scalar(cards[[ix]]$name), scores[ix]))
}

# Now try bidirectional cheap: max(forward, reverse)
cat("\nScanning all candidates BIDIRECTIONAL (max forward/reverse)...\n")
scores2 <- integer(n)
t0 <- proc.time()[["elapsed"]]
for (i in seq_len(n)) {
  if (i == sh_idx) { scores2[i] <- -1L; next }
  fwd <- query_synergy_score_candidate_lightweight(target_profile, profiles[[i]], "commander")$score
  bwd <- query_synergy_score_candidate_lightweight(profiles[[i]], target_profile, "commander")$score
  scores2[i] <- max(fwd, bwd)
}
cat("Scan took ", round(proc.time()[["elapsed"]] - t0, 1), "s\n", sep="")
ord2 <- order(scores2, decreasing = TRUE)
ra_rank2 <- which(ord2 == ra_idx)
cat("\nRaffine's cheap-score rank (bidirectional): ", ra_rank2, " / ", n, "  (score=", scores2[ra_idx], ")\n", sep="")

cat("\nTop 20 cheap scores (bidirectional):\n")
for (k in seq_len(20)) {
  ix <- ord2[k]
  cat(sprintf("%2d. %-45s cheap=%d\n", k, query_api_scalar(cards[[ix]]$name), scores2[ix]))
}
