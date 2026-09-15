.analysis_cards_by_id <- function(cards) {
  ids <- vapply(cards, .analysis_card_id, character(1))
  if (anyDuplicated(ids)) stop("cards must have unique canonical ids", call. = FALSE)
  stats::setNames(cards, ids)
}

.analysis_build_relation_graph <- function(cards, context, max_relations) {
  by_id <- .analysis_cards_by_id(cards)
  ids <- names(by_id)
  outgoing <- stats::setNames(vector("list", length(ids)), ids)
  explored <- 0L
  truncated <- FALSE
  if (length(ids) < 2L) return(list(outgoing = outgoing, explored = 0L, truncated = FALSE))

  for (source_id in ids) {
    for (target_id in ids) {
      if (identical(source_id, target_id)) next
      explored <- explored + 1L
      if (explored > max_relations) {
        truncated <- TRUE
        return(list(outgoing = outgoing, explored = explored - 1L, truncated = truncated))
      }
      relations <- .analysis_filter_objective(
        functional_relations(by_id[[source_id]], by_id[[target_id]], context),
        context
      )
      if (length(relations)) outgoing[[source_id]] <- c(outgoing[[source_id]], relations)
    }
  }
  list(outgoing = outgoing, explored = explored, truncated = truncated)
}

.analysis_group_from_path <- function(first, second) {
  unknown <- unique(c(first$unknown_conditions, second$unknown_conditions))
  relation_statuses <- c(first$status, second$status)
  list(
    category = "functional_group",
    card_ids = c(first$source_card, first$target_card, second$target_card),
    card_names = c(first$source_name, first$target_name, second$target_name),
    status = if (length(unknown)) "unknown" else if (all(relation_statuses == "verified")) "verified" else "inferred",
    coverage_attested = if (length(unknown)) 0 else 1,
    coverage_potential = 1,
    relation_count = 2L,
    families = sort(unique(c(first$family, second$family))),
    unknown_conditions = unknown,
    relations = list(first, second),
    explanation = c(
      paste(first$source_name, "supplies", first$supplied$object, "to", first$target_name),
      paste(second$source_name, "supplies", second$supplied$object, "to", second$target_name)
    )
  )
}

#' Find Explainable Three-card Functional Groups
#'
#' Searches deterministic directed paths of two evidenced relations. Search and
#' display budgets are reported separately.
#'
#' @param cards List of unique canonical card lists.
#' @param context A validated analysis context.
#' @param limit Maximum displayed groups.
#' @param max_pair_evaluations Maximum directed card pairs evaluated.
#'
#' @return A versioned response containing complete three-card groups.
#' @export
analyze_functional_groups <- function(cards,
                                      context = analysis_context(),
                                      limit = 20L,
                                      max_pair_evaluations = 10000L) {
  if (!inherits(context, "mtg_analysis_context")) stop("context must come from analysis_context()", call. = FALSE)
  if (!is.list(cards)) stop("cards must be a list", call. = FALSE)
  limit <- as.integer(limit)
  max_pair_evaluations <- as.integer(max_pair_evaluations)
  if (is.na(limit) || limit < 1L || is.na(max_pair_evaluations) || max_pair_evaluations < 1L) {
    stop("limits must be positive integers", call. = FALSE)
  }

  graph <- .analysis_build_relation_graph(cards, context, max_pair_evaluations)
  groups <- list()
  seen <- character(0)
  for (source_id in names(graph$outgoing)) {
    for (first in graph$outgoing[[source_id]]) {
      middle_id <- first$target_card
      for (second in graph$outgoing[[middle_id]]) {
        if (second$target_card %in% c(first$source_card, first$target_card)) next
        group <- .analysis_group_from_path(first, second)
        signature <- paste(group$card_ids, vapply(group$relations, .analysis_relation_key, character(1)), collapse = "|")
        if (signature %in% seen) next
        seen <- c(seen, signature)
        groups[[length(groups) + 1L]] <- group
      }
    }
  }
  if (length(groups)) {
    ord <- order(
      -vapply(groups, `[[`, numeric(1), "coverage_attested"),
      vapply(groups, function(x) length(x$unknown_conditions), integer(1)),
      vapply(groups, function(x) paste(x$card_ids, collapse = "|"), character(1))
    )
    groups <- groups[ord]
  }
  display_truncated <- length(groups) > limit

  strategy <- discover_strategy_engines(
    cards = cards, context = context, limit = limit,
    max_pair_evaluations = max_pair_evaluations
  )
  engine_groups <- lapply(strategy$results, function(engine) {
    setup <- engine$realizations$setup[[1]]
    executor <- engine$realizations$executor[[1]]
    alternatives <- c(
      if (length(engine$realizations$setup) > 1L) paste("Preparations alternatives:", paste(vapply(engine$realizations$setup, `[[`, character(1), "card_name"), collapse = ", ")) else character(0),
      if (length(engine$realizations$executor) > 1L) paste("Executions alternatives:", paste(vapply(engine$realizations$executor, `[[`, character(1), "card_name"), collapse = ", ")) else character(0)
    )
    list(
      category = "strategy_engine",
      card_ids = c(setup$card_id, executor$card_id),
      card_names = c(setup$card_name, executor$card_name),
      status = "inferred",
      structural_status = engine$structural_status,
      feasibility_status = engine$feasibility_status,
      coverage_attested = 0,
      coverage_potential = 1,
      relation_count = 2L,
      families = "strategy_engine",
      unknown_conditions = engine$unknown_conditions,
      relations = list(),
      engine = engine,
      explanation = c(paste("Moteur:", engine$pattern), alternatives)
    )
  })
  combined_results <- c(engine_groups, utils::head(groups, limit))
  combined_results <- utils::head(combined_results, limit)

  list(
    ok = TRUE,
    model_version = "functional-synergy-0.3.0",
    extractor_version = "functional-rules-0.3.0",
    data_version = context$rules_version,
    context = unclass(context),
    results = combined_results,
    strategic_engines = strategy$results,
    unknown_fields = context$unknown_fields,
    warnings = character(0),
    search = list(pair_evaluations = graph$explored, budget = max_pair_evaluations),
    search_truncated = graph$truncated || strategy$search_truncated,
    display_truncated = display_truncated || strategy$display_truncated || length(engine_groups) + length(groups) > limit
  )
}
