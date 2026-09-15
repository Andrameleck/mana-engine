.analysis_object_compatible <- function(produced, required) {
  if (identical(produced, required)) return(TRUE)
  token_base <- sub("_token$", "", produced)
  cast_base <- sub("_cast$", "", produced)
  token_base != produced && required %in% unique(c(token_base, "token", if (token_base %in% c("creature", "artifact", "enchantment", "planeswalker", "land")) "permanent")) ||
    produced == "creature_card" && required %in% c("card", "permanent") ||
    produced %in% c("creature", "artifact", "enchantment", "planeswalker", "land") && required == "permanent" ||
    cast_base != produced && required == "spell_cast" ||
    produced == "permanent" && required == "object"
}

.analysis_fact_compatible <- function(produced, required) {
  controller_ok <- identical(produced$controller, required$controller) ||
    identical(required$controller, "any")
  zone_ok <- !nzchar(required$zone) || !nzchar(produced$zone) || identical(produced$zone, required$zone)
  qualifier_ok <- !("nontoken" %in% required$qualifiers && grepl("token$", produced$object)) &&
    !("token" %in% required$qualifiers && !grepl("token$", produced$object))
  identical(produced$kind, required$kind) &&
    zone_ok &&
    controller_ok && qualifier_ok &&
    .analysis_object_compatible(produced$object, required$object)
}

.analysis_relation_status <- function(source_ability, target_ability) {
  unknown <- unique(c(source_ability$unknown_conditions, target_ability$unknown_conditions))
  if (length(unknown)) return("unknown")
  if (identical(source_ability$status, "verified") && identical(target_ability$status, "verified")) "verified" else "inferred"
}

#' Find Directed Functional Relations
#'
#' Match outputs of source abilities to the explicit requirements and costs of
#' target abilities. A returned relation is directional.
#'
#' @param source_card Source card list, optionally with manual `abilities`.
#' @param target_card Target card list, optionally with manual `abilities`.
#' @param context An object returned by [analysis_context()].
#'
#' @return A list of functional relation records.
#' @export
functional_relations <- function(source_card, target_card, context = analysis_context()) {
  if (!inherits(context, "mtg_analysis_context")) stop("context must come from analysis_context()", call. = FALSE)
  source_id <- .analysis_card_id(source_card)
  target_id <- .analysis_card_id(target_card)
  if (identical(source_id, target_id)) return(list())

  source_abilities <- source_card$abilities %||% extract_functional_abilities(source_card)$abilities
  target_abilities <- target_card$abilities %||% extract_functional_abilities(target_card)$abilities
  source_context <- .analysis_context_card_status(source_card, context)
  target_context <- .analysis_context_card_status(target_card, context)
  if (identical(source_context$status, "false") || identical(target_context$status, "false")) return(list())

  relations <- list()
  for (source_ability in source_abilities) {
    for (target_ability in target_abilities) {
      needs <- c(target_ability$requires, target_ability$costs)
      cost_start <- length(target_ability$requires) + 1L
      if (!length(source_ability$produces) || !length(needs)) next
      hit_matrix <- vapply(needs, function(need) {
        vapply(source_ability$produces, function(produced) .analysis_fact_compatible(produced, need), logical(1))
      }, logical(length(source_ability$produces)))
      if (is.null(dim(hit_matrix))) hit_matrix <- matrix(hit_matrix, nrow = length(source_ability$produces))
      matched_needs <- which(colSums(hit_matrix) > 0L)
      if (!length(matched_needs)) next
      matched_outputs <- unique(unlist(lapply(matched_needs, function(j) which(hit_matrix[, j])), use.names = FALSE))
      missing_needs <- setdiff(seq_along(needs), matched_needs)
      unknown <- unique(c(
        source_ability$unknown_conditions, target_ability$unknown_conditions,
        source_context$unknown, target_context$unknown,
        if (length(missing_needs)) "additional_requirements_not_supplied_by_this_card" else character(0)
      ))
      relation_types <- unique(ifelse(matched_needs >= cost_start && length(target_ability$costs), "supplies_cost", "supplies_requirement"))
      relations[[length(relations) + 1L]] <- list(
        source_card = source_id,
        source_name = as.character(source_card$name %||% source_id),
        source_ability = source_ability$id,
        target_card = target_id,
        target_name = as.character(target_card$name %||% target_id),
        target_ability = target_ability$id,
        family = target_ability$family,
        relation_type = if (length(relation_types) == 1L) relation_types else "supplies_multiple_interfaces",
        supplied = source_ability$produces[[matched_outputs[[1]]]],
        supplied_ports = source_ability$produces[matched_outputs],
        matched_requirements = needs[matched_needs],
        unsatisfied_requirements = needs[missing_needs],
        interface_coverage = length(matched_needs) / length(needs),
        structural_status = "matched",
        feasibility_status = if (length(missing_needs) || length(unknown)) "indeterminate" else "structural_witness_only",
        status = if (length(unknown)) "unknown" else .analysis_relation_status(source_ability, target_ability),
        satisfied_conditions = if (length(matched_needs)) paste0("interface_", matched_needs) else character(0),
        unsatisfied_conditions = if (length(missing_needs)) paste0("interface_", missing_needs) else character(0),
        unknown_conditions = unknown,
        evidence = list(source = source_ability$evidence, target = target_ability$evidence),
        rule_ids = c(source_ability$id, target_ability$id)
      )
    }
  }
  relations
}

.analysis_relation_key <- function(relation) {
  paste(relation$source_card, relation$source_ability, relation$target_card, relation$target_ability, sep = "|")
}

.analysis_card_pair_relations <- function(card_a, card_b, context) {
  .analysis_filter_objective(
    c(functional_relations(card_a, card_b, context), functional_relations(card_b, card_a, context)),
    context
  )
}
