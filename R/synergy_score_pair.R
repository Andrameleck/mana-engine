# Pairwise scoring entry points: query_synergy_score_pair, indirect resource bridges, indirect chain matcher.
# Extracted from R/query_synergy_engine.R as part of the modular refactor.
# Depends on: synergy_utils, synergy_event_registry, synergy_normalize, synergy_axes

query_synergy_score_pair <- function(target, candidate, format_name = "commander") {
  query_synergy_runtime_metrics_mark_call("score_pair")
  produced_to_payoff <- intersect(candidate$produced_events, target$consumed_events)
  payoff_to_produced <- intersect(candidate$consumed_events, target$produced_events)
  shared_plan <- query_synergy_shared_plan_axis(target$strategy_tags, candidate$strategy_tags)
  replaced_target_payoffs <- intersect(candidate$replaced_events, target$consumed_events)
  prevented_target_payoffs <- intersect(candidate$prevented_events, target$consumed_events)
  replaced_candidate_payoffs <- intersect(target$replaced_events, candidate$consumed_events)
  prevented_candidate_payoffs <- intersect(target$prevented_events, candidate$consumed_events)
  replacement_conflicts <- unique(c(replaced_target_payoffs, replaced_candidate_payoffs))
  prevention_conflicts <- unique(c(prevented_target_payoffs, prevented_candidate_payoffs))
  setup_finisher <- unique(c(
    intersect(candidate$setup_events, target$finisher_events),
    intersect(target$setup_events, candidate$finisher_events)
  ))

  color_fit <- query_synergy_color_fit(target$color_identity, candidate$color_identity)
  format_fit <- query_synergy_format_fit(target$legalities, candidate$legalities, format_name)
  tempo_fit <- query_synergy_tempo_fit(target$mana_value, candidate$mana_value)

  direct_event_score <- query_synergy_overlap_axis_score(
    produced_to_payoff,
    target$consumed_events,
    candidate$produced_events
  )
  reciprocal_value_score <- query_synergy_overlap_axis_score(
    payoff_to_produced,
    target$produced_events,
    candidate$consumed_events
  )
  bridge_axes <- query_synergy_pair_bridge_axes(
    target = target,
    candidate = candidate,
    produced_to_payoff = produced_to_payoff,
    payoff_to_produced = payoff_to_produced,
    direct_event_score = direct_event_score,
    reciprocal_value_score = reciprocal_value_score
  )
  role_match <- query_synergy_role_complementarity(target$roles, candidate$roles)
  indirect_engine <- query_synergy_indirect_engine_axis(
    target,
    candidate,
    direct_event_score = direct_event_score,
    role_match = role_match,
    shared_plan = shared_plan
  )
  package_potential <- query_synergy_package_potential_axis(target, candidate, role_match)

  anti_penalty <- query_synergy_anti_penalty(target$anti_tags, candidate$anti_tags)
  anti_conflicts <- query_synergy_anti_conflicts(target$anti_tags, candidate$anti_tags)
  replacement_penalty <- query_synergy_event_conflict_penalty(length(replacement_conflicts), step = 0.6)
  prevention_penalty <- query_synergy_event_conflict_penalty(length(prevention_conflicts), step = 0.5)
  incoherence_penalty <- query_synergy_strategic_incoherence_penalty(
    produced_to_payoff = produced_to_payoff,
    payoff_to_produced = payoff_to_produced,
    shared_plan = shared_plan$tags,
    setup_finisher = setup_finisher,
    resource_bridges = bridge_axes$resource_bridges,
    zone_transition_bridges = bridge_axes$zone_transition_bridges
  )
  tempo_mismatch_penalty <- query_synergy_tempo_mismatch_penalty(tempo_fit, shared_plan$tags)

  anti_synergy_score <- min(1,
    0.42 * anti_penalty +
      0.28 * replacement_penalty +
      0.18 * prevention_penalty +
      0.12 * if (length(anti_conflicts$pairs) > 0L) 1 else 0
  )
  hard_event_conflict <- length(replacement_conflicts) > 0L || length(prevention_conflicts) > 0L
  anti_warning_bucket_score <- min(1,
    anti_synergy_score +
      if (length(replacement_conflicts) > 0L) 0.4 else 0 +
      if (length(prevention_conflicts) > 0L) 0.35 else 0 +
      if (length(anti_conflicts$pairs) > 0L) 0.12 else 0
  )
  shared_plan_score <- shared_plan$score
  cadence_strength <- suppressWarnings(as.numeric(candidate$cadence$strength))
  if (!is.finite(cadence_strength) || is.na(cadence_strength)) {
    cadence_strength <- 0
  }
  cadence_class <- query_api_scalar(candidate$cadence$class, default = "one_shot")
  cadence_bonus <- switch(cadence_class,
    scalable_repeatable = 0.12,
    reliable_repeatable = 0.08,
    conditional_repeatable = 0.03,
    repeatable_scalable = 0.1,
    repeatable = 0.07,
    0
  )
  indirect_engine_effective <- max(0, min(1, suppressWarnings(as.numeric(indirect_engine$score)) * suppressWarnings(as.numeric(bridge_axes$bridge_gate))))
  cadence_support <- max(
    suppressWarnings(as.numeric(direct_event_score)),
    suppressWarnings(as.numeric(reciprocal_value_score)),
    suppressWarnings(as.numeric(bridge_axes$setup_to_converter_score)),
    suppressWarnings(as.numeric(role_match$score))
  )
  cadence_score <- min(1,
    (0.58 * cadence_strength + 0.3 * query_synergy_cadence_class_weight(cadence_class)) *
      (0.4 + 0.6 * max(cadence_support, indirect_engine_effective, package_potential$score)) +
      cadence_bonus
  )
  shell_dependency <- query_synergy_shell_dependency_axis(candidate)
  reliability <- query_synergy_reliability_axis(
    target = target,
    candidate = candidate,
    direct_score = direct_event_score,
    indirect_score = indirect_engine_effective,
    role_match_score = role_match$score,
    shared_plan_score = shared_plan_score,
    shell_dependency_score = shell_dependency$score,
    shell_dependency = shell_dependency
  )
  role_complementarity_score <- role_match$score
  package_score <- package_potential$score

  enabler_payoff_bonus <- if ((direct_event_score >= 0.1 || reciprocal_value_score >= 0.1) &&
                              role_complementarity_score >= 0.4) {
    min(0.30,
        0.20 * max(direct_event_score, reciprocal_value_score) +
        0.10 * indirect_engine_effective +
        0.10 * role_complementarity_score)
  } else {
    0
  }
  setup_converter_bonus <- if (isTRUE(bridge_axes$has_setup_converter_bridge) &&
                               suppressWarnings(as.numeric(bridge_axes$zone_transition_score)) >= 0.3) {
    0.18 * suppressWarnings(as.numeric(bridge_axes$setup_to_converter_score))
  } else {
    0
  }

  positive_score <-
    0.24 * direct_event_score +
    0.13 * indirect_engine_effective +
    0.15 * reciprocal_value_score +
    0.13 * suppressWarnings(as.numeric(bridge_axes$resource_zone_score)) +
    0.07 * package_score +
    0.03 * shared_plan_score +
    0.07 * cadence_score +
    0.09 * role_complementarity_score +
    0.11 * reliability$score +
    0.03 * color_fit +
    0.02 * format_fit +
    0.02 * tempo_fit +
    enabler_payoff_bonus +
    setup_converter_bonus

  score_norm <- positive_score -
    0.28 * anti_synergy_score -
    0.12 * incoherence_penalty -
    0.08 * tempo_mismatch_penalty -
    0.16 * suppressWarnings(as.numeric(bridge_axes$weak_bridge_penalty)) -
    0.1 * shell_dependency$score
  score_norm <- max(0, min(1, score_norm))
  score_value <- as.integer(round(score_norm * 100))

  axis_scores <- list(
    direct_event_score = round(direct_event_score, 4),
    indirect_engine_score = round(indirect_engine_effective, 4),
    reciprocal_value_score = round(reciprocal_value_score, 4),
    package_score = round(package_score, 4),
    event_bridge_score = suppressWarnings(as.numeric(bridge_axes$event_bridge_score)),
    payoff_bridge_score = suppressWarnings(as.numeric(bridge_axes$payoff_bridge_score)),
    resource_bridge_score = suppressWarnings(as.numeric(bridge_axes$resource_bridge_score)),
    zone_transition_bridge_score = suppressWarnings(as.numeric(bridge_axes$zone_transition_score)),
    strong_bridge_score = suppressWarnings(as.numeric(bridge_axes$bridge_strength)),
    setup_converter_score = suppressWarnings(as.numeric(bridge_axes$setup_to_converter_score)),
    anti_synergy_score = round(anti_synergy_score, 4),
    shared_plan_score = round(shared_plan_score, 4),
    cadence_score = round(cadence_score, 4),
    role_complementarity_score = round(role_complementarity_score, 4),
    reliability_score = round(reliability$score, 4),
    shell_dependency_score = round(shell_dependency$score, 4),
    weak_bridge_penalty = suppressWarnings(as.numeric(bridge_axes$weak_bridge_penalty))
  )

  setup_converter_bucket_bonus <- if (isTRUE(bridge_axes$has_setup_converter_bridge) &&
                                      suppressWarnings(as.numeric(bridge_axes$zone_transition_score)) >= 0.3) {
    0.45 * suppressWarnings(as.numeric(bridge_axes$setup_to_converter_score))
  } else {
    0
  }

  bucket_scores <- list(
    direct_enablers = round(max(0, min(1,
      0.36 * direct_event_score +
        0.18 * reciprocal_value_score +
        0.2 * suppressWarnings(as.numeric(bridge_axes$resource_zone_score)) +
        0.12 * suppressWarnings(as.numeric(bridge_axes$setup_to_converter_score)) +
        0.07 * role_complementarity_score +
        0.07 * reliability$score +
        setup_converter_bucket_bonus -
        0.08 * suppressWarnings(as.numeric(bridge_axes$weak_bridge_penalty))
    )), 4),
    indirect_engines = round(max(0, min(1, 0.46 * indirect_engine_effective + 0.16 * cadence_score + 0.14 * role_complementarity_score + 0.08 * package_score + 0.1 * reliability$score - 0.12 * shell_dependency$score)), 4),
    reciprocal_value_cards = round(min(1, 0.68 * reciprocal_value_score + 0.12 * role_complementarity_score + 0.08 * shared_plan_score + 0.12 * reliability$score), 4),
    anti_synergy_warnings = round(anti_warning_bucket_score, 4)
  )

  positive_bucket_scores <- unlist(bucket_scores[c("direct_enablers", "indirect_engines", "reciprocal_value_cards")], use.names = TRUE)
  primary_bucket <- names(which.max(positive_bucket_scores))[[1]]
  if (hard_event_conflict ||
      (bucket_scores$anti_synergy_warnings >= max(positive_bucket_scores) && bucket_scores$anti_synergy_warnings >= 0.35) ||
      (bucket_scores$anti_synergy_warnings >= 0.45 && score_norm <= 0.45)) {
    primary_bucket <- "anti_synergy_warnings"
  }

  reasons <- character(0)
  if (direct_event_score > 0) {
    reasons <- c(reasons, sprintf(
      "Produces %s %s",
      paste(produced_to_payoff, collapse = ", "),
      query_synergy_describe_engine_source(candidate, produced_to_payoff)
    ))
  }
  if (indirect_engine_effective >= 0.18) {
    reasons <- c(reasons, if (isTRUE(candidate$cadence$repeatable)) {
      sprintf("Acts as an engine rather than a direct payoff, with %s cadence", query_synergy_humanize_id(candidate$cadence$class))
    } else {
      "Acts as an engine rather than a direct payoff"
    })
  }
  if (reciprocal_value_score > 0) {
    reasons <- c(reasons, sprintf(
      "Rewards %s produced by %s",
      paste(payoff_to_produced, collapse = ", "),
      target$name
    ))
  }
  if (shared_plan_score > 0) {
    reasons <- c(reasons, sprintf("Shared strategic structure: %s", paste(shared_plan$tags, collapse = ", ")))
  }
  if (package_score > 0.15) {
    reasons <- c(reasons, sprintf("Supports package assembly through %s", paste(package_potential$links, collapse = ", ")))
  }
  if (length(query_synergy_to_vector(bridge_axes$resource_bridges)) > 0L) {
    reasons <- c(reasons, sprintf(
      "Resource bridge match through %s",
      paste(query_synergy_to_vector(bridge_axes$resource_bridges), collapse = ", ")
    ))
  }
  if (length(query_synergy_to_vector(bridge_axes$zone_transition_bridges)) > 0L) {
    reasons <- c(reasons, sprintf(
      "Zone-transition bridge match through %s",
      paste(utils::head(query_synergy_to_vector(bridge_axes$zone_transition_bridges), 3L), collapse = ", ")
    ))
  }
  if (isTRUE(bridge_axes$setup_seed) && suppressWarnings(as.numeric(bridge_axes$setup_to_converter_score)) >= 0.16) {
    reasons <- c(reasons, "Strong setup to converter bridge from seed resource to candidate")
  }
  if (cadence_score > 0.2) {
    reasons <- c(reasons, sprintf("Cadence profile is %s", query_synergy_humanize_id(candidate$cadence$class)))
  }
  if (reliability$score >= 0.45) {
    reasons <- c(reasons, sprintf("Practical reliability is %s for typical games", query_synergy_humanize_id(reliability$class)))
  } else if (reliability$score > 0.22) {
    reasons <- c(reasons, sprintf("Synergy is %s and can require setup", query_synergy_humanize_id(reliability$class)))
  }
  if (shell_dependency$score >= 0.32) {
    shell_clause <- if (length(shell_dependency$signals) > 0L) {
      paste(utils::head(shell_dependency$signals, 3L), collapse = ", ")
    } else {
      "narrow prerequisites"
    }
    reasons <- c(reasons, sprintf("Shell dependence detected: %s", shell_clause))
  }
  if (role_complementarity_score > 0.2 && length(role_match$pairs) > 0L) {
    reasons <- c(reasons, sprintf("Complements the seed as %s", paste(role_match$pairs, collapse = "; ")))
  }
  if (length(replacement_conflicts) > 0L) {
    reasons <- c(reasons, sprintf(
      "Conflicts because it replaces %s the seed wants",
      paste(replacement_conflicts, collapse = ", ")
    ))
  }
  if (length(prevention_conflicts) > 0L) {
    reasons <- c(reasons, sprintf(
      "Conflicts because it prevents %s the seed wants",
      paste(prevention_conflicts, collapse = ", ")
    ))
  }
  if (length(anti_conflicts$reasons) > 0L) {
    reasons <- c(reasons, anti_conflicts$reasons)
  } else if (anti_synergy_score > 0.2) {
    reasons <- c(reasons, "Anti-synergy detected (conflicting hand or graveyard plan)")
  }
  if (incoherence_penalty > 0) {
    reasons <- c(reasons, "Strategic incoherence: no strong event bridge or shared plan")
  }
  if (tempo_mismatch_penalty > 0) {
    reasons <- c(reasons, "Tempo mismatch: mana values diverge with low strategic overlap")
  }
  if (suppressWarnings(as.numeric(bridge_axes$weak_bridge_penalty)) >= 0.2) {
    reasons <- c(reasons, "Weak explicit bridge: candidate is mostly an indirect or shell-dependent neighbor")
  }
  if (length(reasons) == 0L) {
    reasons <- c(reasons, "Weak mechanical overlap")
  }

  classes <- character(0)
  if (direct_event_score > 0.1) {
    classes <- c(classes, "enabler_payoff", "direct_enabler")
  }
  if (reciprocal_value_score > 0.1) {
    classes <- c(classes, "payoff_enabler")
  }
  if (indirect_engine_effective > 0.16) {
    classes <- c(classes, "indirect_engine")
  }
  if (package_score > 0.12) {
    classes <- c(classes, "package_candidate")
  }
  if (shared_plan_score > 0.08) {
    classes <- c(classes, "shared_plan")
  }
  if (cadence_score > 0.18 && reliability$score >= 0.35) {
    classes <- c(classes, "repeatable_cadence")
  }
  if (role_complementarity_score > 0.18) {
    classes <- c(classes, "role_complementary")
  }
  if (shell_dependency$score >= 0.32 && indirect_engine_effective > 0.1) {
    classes <- c(classes, "shell_dependent_engine")
  }
  if (shared_plan_score >= 0.18 && max(direct_event_score, indirect_engine_effective, package_score) < 0.16) {
    classes <- c(classes, "value_cluster")
  }
  if (reliability$score < 0.28 && max(direct_event_score, indirect_engine_effective, package_score) > 0.22) {
    classes <- c(classes, "shell_dependent")
  }
  if (length(query_synergy_to_vector(bridge_axes$resource_bridges)) > 0L) {
    classes <- c(classes, "resource_bridge")
  }
  if (length(query_synergy_to_vector(bridge_axes$zone_transition_bridges)) > 0L) {
    classes <- c(classes, "zone_transition_bridge")
  }
  if (isTRUE(bridge_axes$has_setup_converter_bridge)) {
    classes <- c(classes, "setup_converter_bridge")
  }
  if (!isTRUE(bridge_axes$has_strong_bridge) && indirect_engine_effective > 0.14) {
    classes <- c(classes, "weak_bridge")
  }
  if (anti_synergy_score > 0.2 || hard_event_conflict) {
    classes <- c(classes, "anti_synergy")
  }
  if (length(anti_conflicts$pairs) > 0L) {
    classes <- c(classes, "plan_conflict")
  }
  if (length(replacement_conflicts) > 0L || length(prevention_conflicts) > 0L) {
    classes <- c(classes, "event_conflict")
  }
  if (incoherence_penalty > 0) {
    classes <- c(classes, "strategic_incoherence")
  }
  if (tempo_mismatch_penalty > 0) {
    classes <- c(classes, "tempo_mismatch")
  }

  directional <- list(
    candidate_to_target = list(
      producer = candidate$name,
      payoff = target$name,
      matched_events = produced_to_payoff,
      reason = if (direct_event_score > 0) {
        sprintf("%s enables %s via %s", candidate$name, target$name, paste(produced_to_payoff, collapse = ", "))
      } else if (suppressWarnings(as.numeric(bridge_axes$setup_to_converter_score)) >= 0.16) {
        sprintf("%s converts %s setup through explicit resource bridges", candidate$name, target$name)
      } else if (indirect_engine_effective > 0) {
        sprintf("%s supports %s as an indirect %s", candidate$name, target$name, paste(intersect(candidate$roles, c("engine", "converter", "bridge", "amplifier")), collapse = "/"))
      } else {
        sprintf("%s does not strongly enable %s", candidate$name, target$name)
      }
    ),
    target_to_candidate = list(
      producer = target$name,
      payoff = candidate$name,
      matched_events = payoff_to_produced,
      reason = if (reciprocal_value_score > 0) {
        sprintf("%s enables %s via %s", target$name, candidate$name, paste(payoff_to_produced, collapse = ", "))
      } else {
        sprintf("%s does not strongly enable %s", target$name, candidate$name)
      }
    )
  )

  list(
    score = score_value,
    score_norm = score_norm,
    breakdown = list(
      direct_event_score = axis_scores$direct_event_score,
      indirect_engine_score = axis_scores$indirect_engine_score,
      reciprocal_value_score = axis_scores$reciprocal_value_score,
      package_score = axis_scores$package_score,
      anti_synergy_score = axis_scores$anti_synergy_score,
      shared_plan_score = axis_scores$shared_plan_score,
      cadence_score = axis_scores$cadence_score,
      role_complementarity_score = axis_scores$role_complementarity_score,
      reliability_score = axis_scores$reliability_score,
      shell_dependency_score = axis_scores$shell_dependency_score,
      event_production_match = axis_scores$direct_event_score,
      event_payoff_match = axis_scores$reciprocal_value_score,
      event_bridge_match = axis_scores$event_bridge_score,
      payoff_bridge_match = axis_scores$payoff_bridge_score,
      resource_bridge_match = axis_scores$resource_bridge_score,
      zone_transition_bridge_match = axis_scores$zone_transition_bridge_score,
      strong_bridge_score = axis_scores$strong_bridge_score,
      weak_bridge_penalty = axis_scores$weak_bridge_penalty,
      setup_converter_match = axis_scores$setup_converter_score,
      shared_plan = axis_scores$shared_plan_score,
      setup_finisher = axis_scores$package_score,
      color_fit = round(color_fit, 4),
      format_fit = round(format_fit, 4),
      tempo_fit = round(tempo_fit, 4),
      direct_bridge_bonus = round(min(1, direct_event_score * 0.35 + cadence_score * 0.1), 4),
      anti_penalty = round(anti_penalty, 4),
      replacement_penalty = round(replacement_penalty, 4),
      prevention_penalty = round(prevention_penalty, 4),
      incoherence_penalty = round(incoherence_penalty, 4),
      tempo_mismatch_penalty = round(tempo_mismatch_penalty, 4),
      reliability_class = reliability$class
    ),
    axis_scores = axis_scores,
    bucket_scores = bucket_scores,
    primary_bucket = primary_bucket,
    reasons = unique(reasons),
    explanation_text = paste(utils::head(unique(reasons), 3L), collapse = " "),
    relation_classes = unique(classes),
    directional = directional,
    matched_events = list(
      enabler_to_payoff = produced_to_payoff,
      payoff_to_enabler = payoff_to_produced,
      event_bridge = query_synergy_to_vector(bridge_axes$produced_to_payoff),
      payoff_bridge = query_synergy_to_vector(bridge_axes$payoff_to_produced),
      indirect_engine = indirect_engine$matched_events,
      indirect_families = indirect_engine$family_matches,
      shared_plan = shared_plan$tags,
      setup_finisher = setup_finisher,
      package_links = package_potential$links,
      resource_bridges = query_synergy_to_vector(bridge_axes$resource_bridges),
      zone_transition_bridges = query_synergy_to_vector(bridge_axes$zone_transition_bridges),
      bridge_types = query_synergy_to_vector(bridge_axes$bridge_types),
      setup_converter = if (isTRUE(bridge_axes$has_setup_converter_bridge)) "setup_converter_bridge" else character(0),
      role_pairs = role_match$pairs,
      shell_dependency_signals = shell_dependency$signals,
      replaces_payoff = replacement_conflicts,
      prevents_payoff = prevention_conflicts,
      anti_conflicts = anti_conflicts$pairs
    )
  )
}


# -----------------------------------------------------------------------------
# Direction-invariant role inference for a card pair.
#
# Required by AGENTS.md § 4.1: the functional role of a card in a pair must be
# a property of the card and the relationship, not of which card was supplied
# as the seed. Given the two normalized cards plus the directional event
# matches computed once in each orientation, this returns role labels that are
# stable under (card_a, card_b) swap.
#
# `forward_match`  = events produced by `card_a` that `card_b` consumes/rewards
# `backward_match` = events produced by `card_b` that `card_a` consumes/rewards
#
# The role taxonomy mirrors AGENTS.md § 4.1:
#   "engine/enabler", "payoff/reward", "amplifier", "fuel", "tool/support",
#   "stabilizer", "anti_synergy", "neutral".
# -----------------------------------------------------------------------------
query_synergy_pair_role_label <- function(card,
                                          feeds_other,
                                          fed_by_other,
                                          replaces_other,
                                          prevents_other) {
  if (isTRUE(replaces_other) || isTRUE(prevents_other)) {
    return("anti_synergy")
  }

  card_roles <- query_synergy_to_vector(card$roles)
  card_tags <- query_synergy_to_vector(card$strategy_tags)
  card_target_roles <- query_synergy_to_vector(card$target_roles)

  is_engine_card <- any(card_roles %in% c("engine", "producer", "converter", "bridge"))
  is_payoff_card <- "payoff" %in% card_roles ||
    any(card_tags %in% c("draw_payoff", "death_payoff", "discard_payoff",
                         "spell_payoff", "opponent_draw_punisher",
                         "life_drain_on_opponent_draw"))
  is_amplifier <- "amplifier" %in% card_roles
  is_target <- "target" %in% card_roles || length(card_target_roles) > 0L

  # Decision order: feeds wins over fed_by, but a specialized payoff that is
  # fed_by_other should still be reported as payoff, not as engine.
  if (isTRUE(feeds_other) && isTRUE(fed_by_other)) {
    if (is_amplifier) return("amplifier")
    return("engine_payoff")
  }
  if (isTRUE(feeds_other)) {
    if (is_payoff_card && !is_engine_card) return("payoff/reward")
    return("engine/enabler")
  }
  if (isTRUE(fed_by_other)) {
    if (is_engine_card && !is_payoff_card) return("engine/enabler")
    return("payoff/reward")
  }
  if (is_target) return("payoff/reward")
  if (is_amplifier) return("amplifier")
  if (is_engine_card) return("engine/enabler")
  if (is_payoff_card) return("payoff/reward")
  "tool/support"
}

#' Role-aware bidirectional pair scoring (AGENTS.md § 4.1).
#'
#' Wraps `query_synergy_score_pair()` to satisfy the direction-invariance
#' requirement: scores the pair in both orientations, infers a role for each
#' card that does not depend on which one was supplied as the seed, and
#' returns a `final_pair_score` that is symmetric up to a small documented
#' bonus for bidirectional reinforcement.
#'
#' Naming convention: `card_a` and `card_b` are arbitrary labels for the two
#' input cards. The output exposes:
#'
#' - `card_a_role` / `card_b_role` : direction-invariant role labels.
#' - `a_feeds_b_score` / `b_feeds_a_score` : the two directional scores
#'   (each is the result of `query_synergy_score_pair(producer, consumer)$score`).
#' - `dominant_relationship` : `"a_feeds_b"`, `"b_feeds_a"`,
#'   `"mutual_feedback"`, `"anti_synergy"`, or `"tool_support"`.
#' - `final_pair_score` : the strongest meaningful contribution plus a small
#'   reciprocity bonus (capped at 100). NOT a naive average.
#' - `directional` : the two underlying `query_synergy_score_pair()` results
#'   so callers retain full explainability.
#'
#' @param card_a Normalized card (output of `query_synergy_normalize_card`).
#' @param card_b Normalized card.
#' @param format_name Format used for legality checks (default "commander").
#' @export
query_synergy_score_pair_symmetric <- function(card_a, card_b, format_name = "commander") {
  forward <- query_synergy_score_pair(card_a, card_b, format_name = format_name)
  backward <- query_synergy_score_pair(card_b, card_a, format_name = format_name)

  # Directional event matches:
  #   forward$matched_events$enabler_to_payoff = events produced by card_b
  #     (the candidate of the forward call) that card_a (target) consumes.
  #   That is "b feeds a" in our symmetric naming.
  b_feeds_a_events <- query_synergy_to_vector(forward$matched_events$enabler_to_payoff)
  a_feeds_b_events <- query_synergy_to_vector(backward$matched_events$enabler_to_payoff)

  a_feeds_b <- length(a_feeds_b_events) > 0L
  b_feeds_a <- length(b_feeds_a_events) > 0L

  # Conflicts (replacement / prevention) are direction-invariant in practice;
  # accept either side reporting them.
  a_replaces_b <- length(query_synergy_to_vector(backward$matched_events$replaces_payoff)) > 0L ||
    length(query_synergy_to_vector(forward$matched_events$replaces_payoff)) > 0L
  a_prevents_b <- length(query_synergy_to_vector(backward$matched_events$prevents_payoff)) > 0L ||
    length(query_synergy_to_vector(forward$matched_events$prevents_payoff)) > 0L

  card_a_role <- query_synergy_pair_role_label(
    card_a,
    feeds_other = a_feeds_b,
    fed_by_other = b_feeds_a,
    replaces_other = a_replaces_b,
    prevents_other = a_prevents_b
  )
  card_b_role <- query_synergy_pair_role_label(
    card_b,
    feeds_other = b_feeds_a,
    fed_by_other = a_feeds_b,
    replaces_other = a_replaces_b,
    prevents_other = a_prevents_b
  )

  a_feeds_b_score <- as.integer(forward$score)   # forward = score_pair(a as target, b as candidate)
                                                  # high `direct_event_score` means b feeds a;
                                                  # so forward$score reflects "b feeds a" perspective.
  b_feeds_a_score <- as.integer(backward$score)

  # Map directional scores to the symmetric naming. forward$score is biased
  # toward "b feeds a"; backward$score toward "a feeds b".
  score_b_feeds_a <- a_feeds_b_score
  score_a_feeds_b <- b_feeds_a_score

  is_anti <- (card_a_role == "anti_synergy" || card_b_role == "anti_synergy")

  dominant_relationship <- if (is_anti) {
    "anti_synergy"
  } else if (a_feeds_b && b_feeds_a) {
    "mutual_feedback"
  } else if (a_feeds_b) {
    "a_feeds_b"
  } else if (b_feeds_a) {
    "b_feeds_a"
  } else {
    "tool_support"
  }

  # Final pair score:
  #   - Take the stronger directional score (the "strongest meaningful
  #     functional contribution" required by AGENTS.md).
  #   - Add a small reciprocity bonus when both directions register a feed
  #     (mutual feedback is more reliable than one-way).
  #   - Clamp to [0, 100].
  stronger <- max(score_a_feeds_b, score_b_feeds_a, na.rm = TRUE)
  weaker   <- min(score_a_feeds_b, score_b_feeds_a, na.rm = TRUE)
  reciprocity_bonus <- if (a_feeds_b && b_feeds_a) {
    # 10% of the weaker score, capped at +6.
    min(6L, as.integer(round(weaker * 0.10)))
  } else {
    0L
  }
  final_pair_score <- max(0L, min(100L, stronger + reciprocity_bonus))

  list(
    final_pair_score = final_pair_score,
    card_a_role = card_a_role,
    card_b_role = card_b_role,
    a_feeds_b_score = score_a_feeds_b,
    b_feeds_a_score = score_b_feeds_a,
    a_feeds_b_events = a_feeds_b_events,
    b_feeds_a_events = b_feeds_a_events,
    dominant_relationship = dominant_relationship,
    reciprocity_bonus = reciprocity_bonus,
    directional = list(
      a_as_target = forward,
      b_as_target = backward
    )
  )
}


query_synergy_indirect_resource_bridges <- function(setup, converter) {
  bridges <- character(0)
  setup_events <- unique(c(
    query_synergy_to_vector(setup$produced_events),
    query_synergy_to_vector(setup$setup_events)
  ))
  setup_tags <- query_synergy_to_vector(setup$strategy_tags)
  setup_moves <- query_synergy_to_list(setup$moves)
  if (length(setup_moves) == 0L) {
    setup_moves <- query_synergy_build_move_records(query_synergy_to_vector(setup$produced_events))
  }
  setup_to_zones <- unique(vapply(setup_moves, function(move) query_api_scalar(move$to, default = ""), character(1)))

  converter_tags <- query_synergy_to_vector(converter$strategy_tags)
  converter_roles <- query_synergy_to_vector(converter$roles)
  converter_events <- query_synergy_to_vector(converter$produced_events)
  converter_inputs <- query_synergy_to_vector(converter$consumed_events)
  converter_moves <- query_synergy_to_list(converter$moves)
  if (length(converter_moves) == 0L) {
    converter_moves <- query_synergy_build_move_records(unique(c(converter_inputs, converter_events)))
  }
  converter_from_zones <- unique(vapply(converter_moves, function(move) query_api_scalar(move$from, default = ""), character(1)))
  converter_to_zones <- unique(vapply(converter_moves, function(move) query_api_scalar(move$to, default = ""), character(1)))

  if ((length(intersect(setup_events, c("CREATE_TOKEN", "ETB", "REANIMATE"))) > 0L ||
       "token_producer" %in% setup_tags ||
       any(setup_to_zones %in% c("battlefield"))) &&
      (length(intersect(converter_tags, c("sacrifice_outlet", "combat_engine", "targeted_play"))) > 0L ||
       length(intersect(converter_events, c("SACRIFICE_PERMANENT", "ATTACKS", "TARGETS_CREATURE"))) > 0L ||
       any(converter_from_zones %in% c("battlefield")) ||
       any(converter_to_zones %in% c("battlefield")) ||
       "bridge" %in% converter_roles)) {
    bridges <- c(bridges, "BATTLEFIELD_RESOURCE")
  }

  if ((length(intersect(setup_events, c("MILL_CARD", "DISCARD_CARD", "GRAVEYARD_TO_HAND", "GRAVEYARD_SETUP"))) > 0L ||
       any(setup_to_zones %in% c("graveyard")) ||
       any(c("graveyard_enabler", "graveyard_setup", "graveyard") %in% setup_tags)) &&
      (length(intersect(converter_tags, c("graveyard", "graveyard_finisher", "bridge_engine", "converter"))) > 0L ||
       length(intersect(converter_inputs, c("MILL_CARD", "DISCARD_CARD"))) > 0L ||
       length(intersect(converter_events, c("CAST_SPELL", "REANIMATE", "GRAVEYARD_TO_HAND"))) > 0L ||
       any(converter_from_zones %in% c("graveyard")))) {
    bridges <- c(bridges, "GRAVEYARD_FUEL")
  }

  if ((length(intersect(setup_events, c("DRAW_CARD", "DISCARD_CARD"))) > 0L || any(c("draw_enabler", "discard_enabler") %in% setup_tags)) &&
      (length(intersect(converter_inputs, c("DRAW_CARD", "DISCARD_CARD"))) > 0L ||
       any(c("draw_payoff", "discard_payoff", "converter") %in% converter_tags))) {
    bridges <- c(bridges, "CARD_FLOW_RESOURCE")
  }

  if ((length(intersect(setup_events, c("CAST_SPELL", "NONCREATURE_SPELL_CAST"))) > 0L || "spell_enabler" %in% setup_tags) &&
      (length(intersect(converter_inputs, c("CAST_SPELL", "NONCREATURE_SPELL_CAST"))) > 0L ||
       any(c("spell_payoff", "bridge_engine", "converter") %in% converter_tags))) {
    bridges <- c(bridges, "SPELL_CHAIN_RESOURCE")
  }

  unique(bridges)
}

query_synergy_match_indirect_chain <- function(setup,
                                               converter,
                                               payoff,
                                               registry = query_synergy_event_registry_default()) {
  step1_exact <- intersect(setup$produced_events, converter$consumed_events)
  step2_exact <- intersect(converter$produced_events, payoff$consumed_events)
  step2_family <- intersect(
    query_synergy_event_family_keys(converter$produced_events, registry),
    query_synergy_event_family_keys(payoff$consumed_events, registry)
  )
  step1_bridges <- query_synergy_indirect_resource_bridges(setup, converter)
  step1_roles <- query_synergy_role_complementarity(converter$roles, setup$roles)
  step2_roles <- query_synergy_role_complementarity(payoff$roles, converter$roles)

  step1_strength <- max(
    query_synergy_overlap_axis_score(step1_exact, converter$consumed_events, setup$produced_events),
    if (length(step1_bridges) > 0L) 0.5 else 0
  )
  step2_strength <- max(
    query_synergy_overlap_axis_score(step2_exact, payoff$consumed_events, converter$produced_events),
    if (length(step2_family) > 0L) min(0.5, length(step2_family) / max(1, length(query_synergy_to_vector(payoff$consumed_events)))) else 0
  )

  cadence_factor <- suppressWarnings(as.numeric(converter$cadence$strength))
  if (!is.finite(cadence_factor) || is.na(cadence_factor)) {
    cadence_factor <- 0
  }

  is_valid <- (step1_strength > 0.18 || length(step1_bridges) > 0L) &&
    step2_strength > 0.12 &&
    (step1_roles$score > 0.15 || step2_roles$score > 0.15 || any(query_synergy_to_vector(converter$roles) %in% c("converter", "bridge", "engine")))

  chain_score <- min(1,
    0.35 * step1_strength +
      0.4 * step2_strength +
      0.1 * step1_roles$score +
      0.15 * max(step2_roles$score, cadence_factor)
  )

  list(
    valid = is_valid,
    score = round(chain_score, 4),
    step1_events = step1_exact,
    step1_bridges = step1_bridges,
    step2_events = step2_exact,
    step2_family = step2_family,
    setup_converter_roles = step1_roles$pairs,
    converter_payoff_roles = step2_roles$pairs
  )
}
