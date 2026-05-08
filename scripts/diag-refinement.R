# Diagnostic script: trace group refinement for a given seed card.
#
# Usage:
#   Rscript scripts/diag-refinement.R "Sheoldred, the Apocalypse"
#   Rscript scripts/diag-refinement.R "Sheoldred, the Apocalypse" 2 3
#                                     ^seed                       ^iter ^topN
#
# Prints, for each top group:
#   - initial composition + score
#   - identified weakest member
#   - candidate replacements drawn from each anchor's neighborhood
#   - winning swap (if any) + delta
#   - per-iteration before/after snapshot

suppressPackageStartupMessages({
  if (!requireNamespace("devtools", quietly = TRUE)) {
    stop("devtools is required: install.packages('devtools')")
  }
})

devtools::load_all(".", quiet = TRUE)

args <- commandArgs(trailingOnly = TRUE)
seed_name <- if (length(args) >= 1L) args[[1L]] else "Sheoldred, the Apocalypse"
max_iterations <- if (length(args) >= 2L) suppressWarnings(as.integer(args[[2L]])) else 2L
top_n_groups <- if (length(args) >= 3L) suppressWarnings(as.integer(args[[3L]])) else 3L
package_top_n <- if (length(args) >= 4L) suppressWarnings(as.integer(args[[4L]])) else 12L

if (!is.finite(max_iterations) || is.na(max_iterations)) max_iterations <- 2L
if (!is.finite(top_n_groups) || is.na(top_n_groups)) top_n_groups <- 3L
if (!is.finite(package_top_n) || is.na(package_top_n)) package_top_n <- 12L

format_name <- "commander"
registry <- mtgcodex.api:::query_synergy_event_registry_default()

hr <- function(char = "-", n = 78) cat(strrep(char, n), "\n", sep = "")

cat("================================================================================\n")
cat(sprintf("Diagnostic refinement trace\n"))
cat(sprintf("  seed:           %s\n", seed_name))
cat(sprintf("  max_iterations: %d\n", max_iterations))
cat(sprintf("  top_n_groups:   %d\n", top_n_groups))
cat(sprintf("  package_top_n:  %d\n", package_top_n))
cat("================================================================================\n\n")

# --- 1. Load catalog ----------------------------------------------------------
cat("[1] Loading catalog...\n")
mark <- proc.time()[["elapsed"]]
catalog_info <- mtgcodex.api:::query_synergy_get_catalog()
if (!isTRUE(catalog_info$ok)) {
  stop(catalog_info$error)
}
cat(sprintf("    catalog size: %d cards (%.1fs)\n\n",
            length(catalog_info$cards),
            proc.time()[["elapsed"]] - mark))

# --- 2. Resolve seed card -----------------------------------------------------
cat("[2] Resolving seed card...\n")
seed_card_raw <- mtgcodex.api:::query_synergy_find_card_by_id_or_name(catalog_info$cards, seed_name)
if (is.null(seed_card_raw)) {
  stop(sprintf("seed card not found: %s", seed_name))
}
seed_normalized <- mtgcodex.api:::query_synergy_normalize_card_cached(seed_card_raw, registry = registry)
cat(sprintf("    resolved: %s (id=%s)\n",
            mtgcodex.api:::query_api_scalar(seed_normalized$name, default = ""),
            mtgcodex.api:::query_api_scalar(seed_normalized$id, default = "")))
cat(sprintf("    produced events: %s\n",
            paste(mtgcodex.api:::query_synergy_to_vector(seed_normalized$produced_events), collapse = ", ")))
cat(sprintf("    consumed events: %s\n\n",
            paste(mtgcodex.api:::query_synergy_to_vector(seed_normalized$consumed_events), collapse = ", ")))

# --- 3. Run engine to get initial groups + broader pool -----------------------
cat("[3] Running engine to get initial groups + broader pool...\n")
mark <- proc.time()[["elapsed"]]
engine_out <- mtgcodex.api:::query_synergy_find_in_catalog(
  list(
    card_name = seed_name,
    format = format_name,
    max_results = 100L,
    top_k = 120L,
    package_top_n = package_top_n,
    group_refine_iterations = 0L,    # disable internal refinement, we do it manually
    group_refine_top_n = 0L
  ),
  catalog_info$cards
)
cat(sprintf("    engine done in %.1fs\n", proc.time()[["elapsed"]] - mark))

if (!isTRUE(engine_out$ok)) {
  stop(mtgcodex.api:::query_api_scalar(engine_out$error, default = "engine failed"))
}

initial_groups <- mtgcodex.api:::query_synergy_to_list(engine_out$buckets$synergy_groups$results)
if (length(initial_groups) == 0L) {
  initial_groups <- mtgcodex.api:::query_synergy_to_list(engine_out$buckets$packages$results)
}
if (length(initial_groups) == 0L) {
  cat("    NO INITIAL GROUPS DETECTED — nothing to refine.\n")
  quit(save = "no")
}
cat(sprintf("    initial groups detected: %d\n\n", length(initial_groups)))

# Reconstruct the broader pool the way the engine does: deep-scored cards.
# We re-run the deep-scoring approximation by pulling the best_matches list
# (which is the deep-scored, top_k-ordered set).
best_matches <- mtgcodex.api:::query_synergy_to_list(engine_out$best_matches)
cat(sprintf("[3b] Building broader pool from best_matches (n=%d)...\n", length(best_matches)))
broader_pool <- list()
for (entry in best_matches) {
  cid <- mtgcodex.api:::query_api_scalar(entry$id, default = "")
  if (!nzchar(cid)) next
  raw <- mtgcodex.api:::query_synergy_find_card_by_id_or_name(catalog_info$cards, cid)
  if (is.null(raw)) next
  norm <- mtgcodex.api:::query_synergy_normalize_card_cached(raw, registry = registry)
  if (is.list(norm)) broader_pool[[length(broader_pool) + 1L]] <- norm
}
cat(sprintf("    broader pool size: %d normalized cards\n\n", length(broader_pool)))

# --- 4. Trace refinement for top-N groups -------------------------------------
print_group_summary <- function(group, label = "GROUP") {
  members <- mtgcodex.api:::query_synergy_to_list(group$members)
  cat(sprintf("    [%s] score=%s | id=%s\n",
              label,
              mtgcodex.api:::query_api_scalar(group$total_score, default = "?"),
              mtgcodex.api:::query_api_scalar(group$id, default = "?")))
  for (i in seq_along(members)) {
    m <- members[[i]]
    seed_marker <- if (isTRUE(m$is_seed)) "  (SEED)" else ""
    cat(sprintf("        %d. %-32s [role=%s, id=%s]%s\n",
                i,
                substr(mtgcodex.api:::query_api_scalar(m$name, default = ""), 1, 32),
                mtgcodex.api:::query_api_scalar(m$inferred_role, default = "?"),
                mtgcodex.api:::query_api_scalar(m$id, default = "?"),
                seed_marker))
  }
  edges <- mtgcodex.api:::query_synergy_to_list(group$edges)
  if (length(edges) > 0L) {
    cat(sprintf("        edges: %s\n",
                paste(vapply(edges, function(e) {
                  sprintf("(%s→%s s=%s c=%.2f)",
                          substr(mtgcodex.api:::query_api_scalar(e$from, default = "?"), 1, 8),
                          substr(mtgcodex.api:::query_api_scalar(e$to, default = "?"), 1, 8),
                          mtgcodex.api:::query_api_scalar(e$score, default = "?"),
                          suppressWarnings(as.numeric(e$continuity_score)))
                }, character(1)), collapse = " ")))
  }
}

trace_one_iteration <- function(group, iteration_index) {
  cat(sprintf("    --- iteration %d ---\n", iteration_index))

  # Identify weakest member.
  weakness <- mtgcodex.api:::query_synergy_group_member_weakness(group)
  if (is.null(weakness)) {
    cat("    [iter] no weakest member identifiable; abort iteration\n")
    return(group)
  }
  cat(sprintf("    weakest member: %s (pos=%d, mean_continuity=%.3f)\n",
              mtgcodex.api:::query_api_scalar(weakness$member$name, default = "?"),
              weakness$position,
              suppressWarnings(as.numeric(weakness$contribution))))

  members <- mtgcodex.api:::query_synergy_to_list(group$members)
  group_ids <- vapply(members, function(m) mtgcodex.api:::query_api_scalar(m$id, default = ""), character(1))
  weakest_id <- mtgcodex.api:::query_api_scalar(weakness$member$id, default = "")
  seed_id <- mtgcodex.api:::query_api_scalar(seed_normalized$id, default = "")
  anchor_ids <- setdiff(group_ids, c(weakest_id, seed_id))

  # Build pool_by_id for this iteration.
  pool_by_id <- list()
  for (card in broader_pool) {
    cid <- mtgcodex.api:::query_api_scalar(card$id, default = "")
    if (nzchar(cid)) pool_by_id[[cid]] <- card
  }
  pool_by_id[[seed_id]] <- seed_normalized

  cat(sprintf("    anchors used for neighbor lookup: %s\n",
              paste(anchor_ids, collapse = ", ")))

  # Show top neighbors per anchor.
  for (aid in anchor_ids) {
    anchor_card <- pool_by_id[[aid]]
    if (is.null(anchor_card)) {
      cat(sprintf("        anchor %s NOT in broader pool, skipping\n", aid))
      next
    }
    neighbors <- mtgcodex.api:::query_synergy_member_top_neighbors(
      member = anchor_card,
      candidate_cards = broader_pool,
      format_name = format_name,
      registry = registry,
      k = 8L,
      exclude_ids = c(seed_id, group_ids)
    )
    cat(sprintf("        anchor=%s top-%d neighbors:\n",
                mtgcodex.api:::query_api_scalar(anchor_card$name, default = "?"),
                length(neighbors)))
    for (n in neighbors) {
      cat(sprintf("            %-32s (cheap_score=%.3f)\n",
                  substr(mtgcodex.api:::query_api_scalar(n$card$name, default = ""), 1, 32),
                  suppressWarnings(as.numeric(n$cheap_score))))
    }
  }

  # Run the actual single-group refinement and report outcome.
  refined <- mtgcodex.api:::query_synergy_refine_single_group(
    group = group,
    seed = seed_normalized,
    broader_pool = broader_pool,
    format_name = format_name,
    registry = registry,
    k_member = 12L,
    theta_seed_score = 18,
    max_replacements_to_try = 6L
  )

  prov <- refined$refinement_provenance
  if (is.null(prov)) {
    cat("    OUTCOME: no improvement found; group unchanged.\n")
  } else {
    cat(sprintf("    OUTCOME: replaced '%s' with '%s' (delta=%+.1f pts)\n",
                prov$replaced_member_name,
                prov$with_member_name,
                suppressWarnings(as.numeric(prov$delta_score))))
  }
  refined
}

n_to_trace <- min(top_n_groups, length(initial_groups))
for (gi in seq_len(n_to_trace)) {
  hr("=")
  cat(sprintf("Group #%d (of %d traced)\n", gi, n_to_trace))
  hr("=")
  current <- initial_groups[[gi]]
  print_group_summary(current, label = "BEFORE")
  cat("\n")

  seen_ids <- character(0)
  for (iter in seq_len(max_iterations)) {
    sig <- mtgcodex.api:::query_api_scalar(current$id, default = "")
    if (sig %in% seen_ids) {
      cat(sprintf("    [iter %d] cycle detected on group id; stopping.\n", iter))
      break
    }
    seen_ids <- c(seen_ids, sig)

    refined <- trace_one_iteration(current, iter)
    old_score <- suppressWarnings(as.numeric(current$total_score))
    new_score <- suppressWarnings(as.numeric(refined$total_score))
    if (!is.finite(new_score) || !is.finite(old_score) || new_score <= old_score) {
      cat(sprintf("    [iter %d] no score improvement (old=%s, new=%s); stopping.\n",
                  iter,
                  if (is.finite(old_score)) sprintf("%.0f", old_score) else "?",
                  if (is.finite(new_score)) sprintf("%.0f", new_score) else "?"))
      current <- refined
      break
    }
    current <- refined
    cat("\n")
    print_group_summary(current, label = sprintf("AFTER iter %d", iter))
    cat("\n")
  }

  hr("-")
  print_group_summary(current, label = "FINAL")
  cat("\n")
}

cat("Done.\n")
