.analysis_relation_coverage <- function(relations) {
  if (!length(relations)) return(list(attested = 0, potential = 0, status = "false"))
  statuses <- vapply(relations, `[[`, character(1), "status")
  list(
    attested = as.numeric(any(statuses %in% c("verified", "inferred"))),
    potential = as.numeric(any(statuses != "false")),
    status = if (any(statuses %in% c("verified", "inferred"))) "inferred" else "unknown"
  )
}

.analysis_rank_key <- function(result) {
  c(-result$coverage_attested, -result$coverage_potential,
    length(result$unknown_conditions), result$candidate_id)
}

#' Analyze Functional Synergy Candidates
#'
#' Find and rank explainable functional relations for one seed card. Strict
#' context constraints are applied before ranking and unknowns stay explicit.
#'
#' @param seed Seed card list.
#' @param candidates List of candidate card lists.
#' @param context A validated analysis context.
#' @param limit Maximum number of displayed candidates.
#'
#' @return A versioned analysis response.
#' @export
analyze_functional_synergies <- function(seed,
                                         candidates,
                                         context = analysis_context(),
                                         limit = 20L) {
  if (!inherits(context, "mtg_analysis_context")) stop("context must come from analysis_context()", call. = FALSE)
  if (!is.list(candidates)) stop("candidates must be a list of cards", call. = FALSE)
  limit <- as.integer(limit)
  if (length(limit) != 1L || is.na(limit) || limit < 1L) stop("limit must be a positive integer", call. = FALSE)

  seed_id <- .analysis_card_id(seed)
  seed_context <- .analysis_context_card_status(seed, context)
  if (identical(seed_context$status, "false")) {
    stop("seed violates the explicit color identity constraint", call. = FALSE)
  }
  results <- list()
  exclusions <- list()
  for (candidate in candidates) {
    candidate_id <- .analysis_card_id(candidate)
    if (identical(seed_id, candidate_id)) next
    context_status <- .analysis_context_card_status(candidate, context)
    if (identical(context_status$status, "false")) {
      exclusions[[length(exclusions) + 1L]] <- list(candidate_id = candidate_id, reasons = context_status$reasons)
      next
    }
    relations <- .analysis_card_pair_relations(seed, candidate, context)
    if (!length(relations)) next
    coverage <- .analysis_relation_coverage(relations)
    unknown <- unique(c(seed_context$unknown, context_status$unknown, unlist(lapply(relations, `[[`, "unknown_conditions"), use.names = FALSE)))
    results[[length(results) + 1L]] <- list(
      candidate_id = candidate_id,
      candidate_name = as.character(candidate$name %||% candidate_id),
      category = "functional_relation",
      coverage_attested = coverage$attested,
      coverage_potential = coverage$potential,
      status = coverage$status,
      relation_count = length(relations),
      families = sort(unique(vapply(relations, `[[`, character(1), "family"))),
      unknown_conditions = unknown,
      relations = relations,
      explanation = vapply(relations, function(x) paste(x$source_name, "supplies", x$supplied$object, "to", x$target_name), character(1))
    )
  }

  if (length(results)) {
    ord <- order(
      -vapply(results, `[[`, numeric(1), "coverage_attested"),
      -vapply(results, `[[`, numeric(1), "coverage_potential"),
      vapply(results, function(x) length(x$unknown_conditions), integer(1)),
      vapply(results, `[[`, character(1), "candidate_id")
    )
    results <- results[ord]
  }
  truncated <- length(results) > limit
  results <- utils::head(results, limit)

  list(
    ok = TRUE,
    model_version = "functional-synergy-0.3.0",
    extractor_version = "functional-rules-0.3.0",
    data_version = context$rules_version,
    context = unclass(context),
    seed_id = seed_id,
    results = results,
    exclusions = exclusions,
    unknown_fields = context$unknown_fields,
    warnings = if (context$mode == "sequence") "sequence execution is not evaluated by this endpoint" else character(0),
    truncated = truncated
  )
}
