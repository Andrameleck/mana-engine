# Reproduces the runtime behavior of the Strategy Finder tab when the user
# enables BOTH the Spellbook bonus and the LotusNoir bonus on a synergy
# request seeded with "Sheoldred, the Apocalypse".
#
# Output: full score breakdown for Raffine, Scheming Seer
#   - backend axis_scores from query_synergy_find_in_catalog
#   - Spellbook bonus computed from /reference/spellbook/variants
#   - LotusNoir bonus computed from /reference/lotusnoir/posts
#   - boosted final score, mirroring applyExternalBoostToBackendResults() in
#     inst/www/main.js

suppressMessages(devtools::load_all(".", quiet = TRUE))

normalize_strategy_name <- function(x) {
  s <- tolower(as.character(x %||% ""))
  s <- gsub("[^a-z0-9]+", " ", s)
  s <- trimws(s)
  s
}
`%||%` <- function(a, b) if (is.null(a) || (is.character(a) && !nzchar(a))) b else a

strip_html <- function(x) {
  s <- as.character(x %||% "")
  s <- gsub("<[^>]*>", " ", s)
  s <- gsub("&nbsp;", " ", s, fixed = TRUE)
  s <- gsub("&amp;", "&", s, fixed = TRUE)
  s <- gsub("&quot;", '"', s, fixed = TRUE)
  s <- gsub("&#39;", "'", s, fixed = TRUE)
  s <- gsub("\\s+", " ", s)
  trimws(s)
}

SEED_NAME <- "Sheoldred, the Apocalypse"
TARGET_NAME <- "Raffine, Scheming Seer"
seed_key <- normalize_strategy_name(SEED_NAME)
target_key <- normalize_strategy_name(TARGET_NAME)

cat("=== 1) Backend mechanical synergy ===\n")
catalog <- query_synergy_get_catalog()
res <- query_synergy_find_in_catalog(
  list(
    card_name      = SEED_NAME,
    format         = "commander",
    max_results    = 200L,
    top_k          = 600L,
    cheap_scan_cap = 5000L,
    package_top_n  = 6L
  ),
  catalog$cards
)
if (isFALSE(res$ok)) {
  cat("ERROR:", res$error, "\n"); quit(status = 1)
}
best <- res$best_matches
cat(sprintf("best_matches returned: %d\n", length(best)))

raffine_idx <- which(vapply(best, function(e) {
  normalize_strategy_name(query_api_scalar(e$name, default = "")) == target_key
}, logical(1)))

if (length(raffine_idx) == 0L) {
  cat("Raffine NOT in best_matches.\n")
  quit(status = 0)
}

r <- best[[raffine_idx[[1L]]]]
backend_total <- as.numeric(query_api_scalar(r$total_score,
                                             default = query_api_scalar(r$score, default = 0)))
cat(sprintf("rank=%d  backend total_score=%.2f  bucket=%s\n",
            raffine_idx[[1L]],
            backend_total,
            query_api_scalar(r$bucket, default = "")))

cat("\nbackend axis_scores:\n")
ax <- r$axis_scores
if (is.list(ax) && length(ax) > 0L) {
  for (nm in names(ax)) {
    cat(sprintf("  %-32s = %s\n", nm, format(ax[[nm]])))
  }
} else {
  cat("  (none)\n")
}

cat("\nbackend reasons:\n")
reasons <- query_synergy_to_vector(r$reasons)
for (msg in head(reasons, 10)) cat("  - ", msg, "\n", sep = "")

cat("\nroles / matched events:\n")
roles <- query_synergy_to_vector(r$roles)
events <- query_synergy_to_vector(r$matched_events)
cat("  roles  : ", paste(roles, collapse = ", "), "\n", sep = "")
cat("  events : ", paste(events, collapse = ", "), "\n", sep = "")

# --- 2) Spellbook bonus ---
cat("\n=== 2) Commander Spellbook bonus ===\n")
sb <- query_spellbook_variants(SEED_NAME, "40")
sb_bonus <- 0
sb_refs <- 0
sb_popularity <- 0
if (isFALSE(sb$ok)) {
  cat("Spellbook unavailable:", sb$error, "\n")
} else {
  cat(sprintf("variants returned: %d\n", length(sb$results)))
  boost_by_key <- list()
  refs_by_key <- list()
  pop_by_key <- list()
  for (variant in sb$results) {
    uses <- variant$uses
    status <- toupper(as.character(variant$status %||% ""))
    if (!is.list(uses) || length(uses) == 0L) next
    if (nzchar(status) && status != "OK") next
    keys <- vapply(uses, function(u) normalize_strategy_name(u$card$name %||% ""),
                   character(1))
    keys <- keys[nzchar(keys)]
    if (!(seed_key %in% keys)) next
    popularity <- suppressWarnings(as.numeric(variant$popularity %||% 0))
    if (!is.finite(popularity)) popularity <- 0
    pop_factor <- min(1, log10(popularity + 1) / 4)
    base_boost <- 0.28 + pop_factor * 0.32
    for (k in unique(keys)) {
      if (k == seed_key) next
      prev <- as.numeric(boost_by_key[[k]] %||% 0)
      boost_by_key[[k]] <- min(1.2, prev + base_boost)
      refs_by_key[[k]] <- (as.integer(refs_by_key[[k]] %||% 0L)) + 1L
      pop_by_key[[k]]  <- (as.numeric(pop_by_key[[k]] %||% 0)) + popularity
    }
  }
  sb_boost <- as.numeric(boost_by_key[[target_key]] %||% 0)
  sb_refs <- as.integer(refs_by_key[[target_key]] %||% 0L)
  sb_popularity <- as.numeric(pop_by_key[[target_key]] %||% 0)
  sb_bonus <- sb_boost * 18  # scale=18 in applySpellbookBoostToBackendResults
  cat(sprintf("Raffine variants co-featured with Sheoldred: %d (cum. popularity=%.0f)\n",
              sb_refs, sb_popularity))
  cat(sprintf("  boost factor (capped at 1.2) = %.4f\n", sb_boost))
  cat(sprintf("  Spellbook bonus = %.4f * scale(18) = %.2f pt\n", sb_boost, sb_bonus))
}

# --- 3) LotusNoir bonus ---
cat("\n=== 3) LotusNoir bonus ===\n")
ln <- query_lotusnoir_posts(SEED_NAME, "120")
ln_refs <- 0L
ln_post_count <- 0L
ln_bonus <- 0
if (isFALSE(ln$ok)) {
  cat("LotusNoir unavailable:", ln$error, "\n")
} else {
  posts <- ln$results
  cat(sprintf("posts returned: %d\n", length(posts)))
  # dedup by id
  seen <- character(0)
  unique_posts <- list()
  for (p in posts) {
    pid <- as.character(p$id %||% "")
    if (!nzchar(pid) || pid %in% seen) next
    seen <- c(seen, pid)
    title <- strip_html(p$title %||% "")
    snippet <- strip_html(p$snippet %||% "")
    link <- strip_html(p$url %||% "")
    unique_posts[[length(unique_posts) + 1L]] <- paste(title, snippet, link, sep = "\n")
  }
  ln_post_count <- length(unique_posts)
  for (txt in unique_posts) {
    norm <- paste0(" ", normalize_strategy_name(txt), " ")
    if (!grepl(paste0(" ", seed_key, " "), norm, fixed = TRUE)) next
    if (grepl(paste0(" ", target_key, " "), norm, fixed = TRUE)) {
      ln_refs <- ln_refs + 1L
    }
  }
  if (ln_post_count == 0L || ln_refs == 0L) {
    cat(sprintf("Raffine co-occurrences in Sheoldred posts: %d / %d\n",
                ln_refs, ln_post_count))
    cat("  (no boost — note: LotusNoir search endpoint only returns title+snippet, not full body)\n")
  } else {
    ratio <- ln_refs / max(1L, ln_post_count)
    boost <- min(0.34, 0.08 + ratio * 0.44)
    ln_bonus <- boost * 30  # scale=30 in applyLotusBoostToBackendResults
    cat(sprintf("Raffine co-occurrences in Sheoldred posts: %d / %d (ratio=%.3f)\n",
                ln_refs, ln_post_count, ratio))
    cat(sprintf("  boost factor (capped at 0.34) = %.4f\n", boost))
    cat(sprintf("  LotusNoir bonus = %.4f * scale(30) = %.2f pt\n", boost, ln_bonus))
  }
}

# --- 4) Final boosted score ---
cat("\n=== 4) Final boosted score for Raffine ===\n")
final_total <- backend_total + sb_bonus + ln_bonus
cat(sprintf("backend_total      = %7.2f\n", backend_total))
cat(sprintf("+ spellbook_bonus  = %7.2f\n", sb_bonus))
cat(sprintf("+ lotusnoir_bonus  = %7.2f\n", ln_bonus))
cat(sprintf("--------------------------\n"))
cat(sprintf("= boosted total    = %7.2f\n", final_total))
