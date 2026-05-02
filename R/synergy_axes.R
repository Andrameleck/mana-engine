# Scoring axes: lightweight overlap, shell dependency, reliability, role complementarity, indirect engine, package potential, pair bridge, color/format/tempo and anti-synergy penalties.
# Extracted from R/query_synergy_engine.R as part of the modular refactor.
# Depends on: synergy_utils, synergy_event_registry, synergy_normalize

query_synergy_lightweight_overlap <- function(matches, target_events, source_events) {
  matched <- unique(query_synergy_to_vector(matches))
  target_ids <- unique(query_synergy_to_vector(target_events))
  source_ids <- unique(query_synergy_to_vector(source_events))
  if (length(matched) == 0L || length(target_ids) == 0L || length(source_ids) == 0L) {
    return(0)
  }

  recall <- length(matched) / max(1, length(target_ids))
  precision <- length(matched) / max(1, length(source_ids))
  min(1, 0.7 * recall + 0.3 * precision)
}

query_synergy_cadence_class_weight <- function(class_id = "") {
  key <- query_api_scalar(class_id, default = "one_shot")
  switch(key,
    one_shot = 0.12,
    conditional_repeatable = 0.48,
    reliable_repeatable = 0.68,
    scalable_repeatable = 0.82,
    repeatable = 0.62,
    repeatable_scalable = 0.8,
    scalable = 0.38,
    0.12
  )
}

query_synergy_specific_strategy_tags <- function(tags, min_weight = 0.7) {
  values <- unique(query_synergy_to_vector(tags))
  if (length(values) == 0L) {
    return(character(0))
  }

  threshold <- suppressWarnings(as.numeric(min_weight))
  if (!is.finite(threshold) || is.na(threshold)) {
    threshold <- 0.7
  }
  Filter(function(tag) query_synergy_plan_tag_specificity_weight(tag) >= threshold, values)
}

query_synergy_shell_dependency_axis <- function(card) {
  query_synergy_runtime_metrics_mark_call("shell_dependency_axis")
  if (!is.list(card)) {
    return(list(
      score = 0,
      signals = character(0),
      components = list(prerequisite = 0, tags = 0, context = 0, target = 0, activation = 0)
    ))
  }

  strategy_tags <- unique(query_synergy_to_vector(card$strategy_tags))
  consumed_events <- unique(query_synergy_to_vector(card$consumed_events))
  target_roles <- unique(query_synergy_to_vector(card$target_roles))
  roles <- unique(query_synergy_to_vector(card$roles))
  cadence <- if (is.list(card$cadence)) card$cadence else list()
  contexts <- unique(query_synergy_to_vector(cadence$contexts))
  ability_values <- query_synergy_to_list(card$abilities)
  ability_text <- tolower(paste(vapply(ability_values, function(ability) {
    if (!is.list(ability)) {
      return("")
    }
    query_api_scalar(ability$text, default = "")
  }, character(1)), collapse = " "))
  has_trigger_cost <- any(vapply(ability_values, function(ability) {
    is.list(ability) && nzchar(query_api_scalar(ability$trigger$cost, default = ""))
  }, logical(1)))

  prerequisite_component <- min(1, (max(0, length(consumed_events) - 1L) / 3) + if ("dependent" %in% roles && length(consumed_events) > 0L) 0.24 else 0)
  conditional_contexts <- intersect(contexts, c("combat", "spell", "death", "etb", "activated"))
  context_component <- min(1,
    (length(conditional_contexts) / 3) +
      if ("combat" %in% conditional_contexts) 0.35 else 0 +
      if ("spell" %in% conditional_contexts) 0.18 else 0
  )
  target_component <- min(1, (length(intersect(target_roles, c("creature_card", "artifact_card", "enchantment_card", "creature", "artifact", "enchantment"))) / 2) + if ("target" %in% roles && length(target_roles) > 0L) 0.2 else 0)

  tag_patterns <- list(
    list(pattern = "tribal|kindred", weight = 0.3, label = "tribal density"),
    list(pattern = "spell_payoff|spell_enabler|spellslinger|noncreature", weight = 0.2, label = "spell density"),
    list(pattern = "combat_engine|combat", weight = 0.18, label = "combat connection"),
    list(pattern = "graveyard_finisher|graveyard_enabler|graveyard", weight = 0.16, label = "graveyard density"),
    list(pattern = "token_producer|sacrifice_outlet|death_payoff", weight = 0.16, label = "board-state package"),
    list(pattern = "targeted_play", weight = 0.12, label = "specific target support")
  )
  tag_hits <- Filter(function(entry) {
    any(vapply(strategy_tags, function(tag) grepl(entry$pattern, tag, perl = TRUE), logical(1)))
  }, tag_patterns)
  tag_component <- min(1, sum(vapply(tag_hits, function(entry) entry$weight, numeric(1))))
  tag_signals <- unique(vapply(tag_hits, function(entry) entry$label, character(1)))

  activation_hits <- sum(vapply(c(
    "as an additional cost",
    "\\bsacrifice\\b",
    "\\bdiscard\\b",
    "\\bexile\\b",
    "\\btap\\b"
  ), function(pattern) grepl(pattern, ability_text, perl = TRUE), logical(1)))
  activation_component <- min(1,
    (if (has_trigger_cost) 0.5 else 0) +
      min(0.5, activation_hits * 0.16)
  )

  shell_score <- min(1,
    0.28 * prerequisite_component +
      0.24 * tag_component +
      0.24 * context_component +
      0.14 * target_component +
      0.1 * activation_component +
      if ("combat" %in% conditional_contexts) 0.12 else 0
  )

  signals <- unique(c(
    tag_signals,
    if (prerequisite_component >= 0.45) "multiple prerequisites" else character(0),
    if (context_component >= 0.34) "conditional cadence context" else character(0),
    if (target_component >= 0.34) "specific target type requirement" else character(0),
    if (activation_component >= 0.34) "activation/setup cost" else character(0)
  ))

  list(
    score = round(shell_score, 4),
    signals = signals,
    components = list(
      prerequisite = round(prerequisite_component, 4),
      tags = round(tag_component, 4),
      context = round(context_component, 4),
      target = round(target_component, 4),
      activation = round(activation_component, 4)
    )
  )
}

query_synergy_reliability_axis <- function(target,
                                           candidate,
                                           direct_score = 0,
                                           indirect_score = 0,
                                           role_match_score = 0,
                                           shared_plan_score = 0,
                                           shell_dependency_score = 0,
                                           shell_dependency = NULL) {
  query_synergy_runtime_metrics_mark_call("reliability_axis")
  card <- if (is.list(candidate)) candidate else list()
  cadence <- if (is.list(card$cadence)) card$cadence else list()
  cadence_class <- query_api_scalar(cadence$class, default = "one_shot")
  cadence_strength <- suppressWarnings(as.numeric(cadence$strength))
  if (!is.finite(cadence_strength) || is.na(cadence_strength)) {
    cadence_strength <- 0
  }
  cadence_weight <- query_synergy_cadence_class_weight(cadence_class)
  consumed_events <- unique(query_synergy_to_vector(card$consumed_events))
  contexts <- unique(query_synergy_to_vector(cadence$contexts))
  target_roles <- unique(query_synergy_to_vector(card$target_roles))

  shell_axis <- if (is.list(shell_dependency)) shell_dependency else query_synergy_shell_dependency_axis(card)
  activation_cost_component <- suppressWarnings(as.numeric(shell_axis$components$activation))
  if (!is.finite(activation_cost_component) || is.na(activation_cost_component)) {
    activation_cost_component <- 0
  }
  prerequisite_penalty <- min(0.45, max(0, length(consumed_events) - 1L) * 0.08)
  context_penalty <- 0
  if ("combat" %in% contexts && suppressWarnings(as.numeric(direct_score)) < 0.28) {
    context_penalty <- context_penalty + 0.12
  }
  if ("activated" %in% contexts) {
    context_penalty <- context_penalty + 0.05
  }
  type_penalty <- if (length(target_roles) > 0L) min(0.14, length(target_roles) * 0.05) else 0
  shared_only_penalty <- if (suppressWarnings(as.numeric(shared_plan_score)) >= 0.2 &&
    max(suppressWarnings(as.numeric(direct_score)), suppressWarnings(as.numeric(indirect_score))) < 0.14) {
    0.12
  } else {
    0
  }
  shell_score <- suppressWarnings(as.numeric(shell_dependency_score))
  if (!is.finite(shell_score) || is.na(shell_score)) {
    shell_score <- suppressWarnings(as.numeric(shell_axis$score))
    if (!is.finite(shell_score) || is.na(shell_score)) {
      shell_score <- 0
    }
  }
  shell_penalty <- min(0.45, shell_score * 0.45)

  reliability <- min(1,
    0.3 * cadence_weight +
      0.18 * cadence_strength +
      0.24 * suppressWarnings(as.numeric(direct_score)) +
      0.12 * suppressWarnings(as.numeric(indirect_score)) +
      0.1 * suppressWarnings(as.numeric(role_match_score)) +
      0.06 * (1 - min(1, activation_cost_component))
  )
  reliability <- reliability -
    prerequisite_penalty -
    context_penalty -
    type_penalty -
    shared_only_penalty -
    shell_penalty
  reliability <- max(0, min(1, reliability))

  reliability_class <- if (reliability >= 0.72) {
    "high_reliability"
  } else if (reliability >= 0.5) {
    "medium_reliability"
  } else if (reliability >= 0.32) {
    "situational_reliability"
  } else {
    "low_reliability"
  }

  list(
    score = round(reliability, 4),
    class = reliability_class,
    penalties = list(
      prerequisite = round(prerequisite_penalty, 4),
      context = round(context_penalty, 4),
      target = round(type_penalty, 4),
      shared_only = round(shared_only_penalty, 4),
      shell = round(shell_penalty, 4)
    )
  )
}

query_synergy_score_candidate_lightweight <- function(target,
                                                      candidate,
                                                      format_name = "commander") {
  # Cheap-scan contract: keep this stage strictly lightweight for full-catalog coverage.
  # Allowed here: coarse event/family overlap, coarse role/plan fit, anti flags, cadence/color/format/tempo.
  # Excluded here: reliability/shell analysis, rich explanations, role reinterpretation, and group typing.
  query_synergy_runtime_metrics_mark_call("lightweight_score")
  produced_to_payoff <- intersect(candidate$produced_events, target$consumed_events)
  payoff_to_produced <- intersect(candidate$consumed_events, target$produced_events)
  produced_family_overlap <- intersect(candidate$produced_families, target$consumed_families)
  consumed_family_overlap <- intersect(candidate$consumed_families, target$produced_families)
  shared_plan <- query_synergy_shared_plan_axis(target$strategy_tags, candidate$strategy_tags)
  role_match <- query_synergy_role_complementarity(target$roles, candidate$roles)
  setup_finisher <- unique(c(
    intersect(candidate$setup_events, target$finisher_events),
    intersect(target$setup_events, candidate$finisher_events)
  ))
  replacement_conflicts <- unique(c(
    intersect(candidate$replaced_events, target$consumed_events),
    intersect(target$replaced_events, candidate$consumed_events)
  ))
  prevention_conflicts <- unique(c(
    intersect(candidate$prevented_events, target$consumed_events),
    intersect(target$prevented_events, candidate$consumed_events)
  ))

  direct_score <- query_synergy_lightweight_overlap(
    produced_to_payoff,
    target$consumed_events,
    candidate$produced_events
  )
  reciprocal_score <- query_synergy_lightweight_overlap(
    payoff_to_produced,
    target$produced_events,
    candidate$consumed_events
  )
  family_bridge_score <- max(
    query_synergy_lightweight_overlap(
      produced_family_overlap,
      target$consumed_families,
      candidate$produced_families
    ),
    query_synergy_lightweight_overlap(
      consumed_family_overlap,
      target$produced_families,
      candidate$consumed_families
    )
  )
  setup_score <- min(1, length(setup_finisher) / max(1, length(unique(c(target$setup_events, target$finisher_events, candidate$setup_events, candidate$finisher_events)))))

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
  cadence_score <- min(1,
    (0.58 * cadence_strength + 0.3 * query_synergy_cadence_class_weight(cadence_class)) *
      (0.45 + 0.55 * max(direct_score, family_bridge_score, role_match$score)) +
      cadence_bonus
  )
  cadence_penalty <- if (identical(cadence_class, "conditional_repeatable") && max(direct_score, family_bridge_score) < 0.2) 0.04 else 0

  color_fit <- query_synergy_color_fit(target$color_identity, candidate$color_identity)
  format_fit <- query_synergy_format_fit(target$legalities, candidate$legalities, format_name)
  tempo_fit <- query_synergy_tempo_fit(target$mana_value, candidate$mana_value)
  anti_penalty <- query_synergy_anti_penalty(target$anti_tags, candidate$anti_tags)
  replacement_penalty <- query_synergy_event_conflict_penalty(length(replacement_conflicts), step = 0.6)
  prevention_penalty <- query_synergy_event_conflict_penalty(length(prevention_conflicts), step = 0.5)

  score_norm <- 0.33 * direct_score +
    0.14 * reciprocal_score +
    0.22 * family_bridge_score +
    0.07 * shared_plan$score +
    0.12 * role_match$score +
    0.06 * setup_score +
    0.03 * color_fit +
    0.02 * format_fit +
    0.02 * tempo_fit +
    0.09 * cadence_score -
    cadence_penalty -
    0.12 * anti_penalty -
    0.14 * replacement_penalty -
    0.1 * prevention_penalty
  score_norm <- max(0, min(1, score_norm))

  list(
    score = as.integer(round(score_norm * 100)),
    score_norm = round(score_norm, 4),
    direct_events = produced_to_payoff,
    reciprocal_events = payoff_to_produced,
    family_bridge = unique(c(produced_family_overlap, consumed_family_overlap)),
    replacement_conflicts = replacement_conflicts,
    prevention_conflicts = prevention_conflicts
  )
}

query_synergy_overlap_axis_score <- function(matches, target_events, source_events) {
  matched <- unique(query_synergy_to_vector(matches))
  target_ids <- unique(query_synergy_to_vector(target_events))
  source_ids <- unique(query_synergy_to_vector(source_events))
  if (length(matched) == 0L || length(target_ids) == 0L || length(source_ids) == 0L) {
    return(0)
  }

  recall <- length(matched) / length(target_ids)
  precision <- length(matched) / length(source_ids)
  min(1, 0.65 * recall + 0.35 * precision)
}

query_synergy_plan_tag_specificity_weight <- function(tag) {
  key <- query_api_scalar(tag, default = "")
  if (!nzchar(key)) {
    return(0)
  }

  broad_tags <- c(
    "draw_discard", "graveyard", "board_engine", "card_flow",
    "tokens", "spells", "combat", "life", "value_chain"
  )
  if (key %in% broad_tags) {
    return(0.2)
  }
  if (grepl("_enabler$|_payoff$|_outlet$|_producer$|_finisher$|converter|bridge|repeatable_engine|combat_engine|graveyard_finisher|graveyard_enabler|death_payoff|targeted_play|tribal|kindred|spellslinger", key, perl = TRUE)) {
    return(0.95)
  }
  0.5
}

query_synergy_shared_plan_axis <- function(target_tags, candidate_tags) {
  left <- unique(query_synergy_to_vector(target_tags))
  right <- unique(query_synergy_to_vector(candidate_tags))
  shared <- intersect(left, right)
  if (length(shared) == 0L) {
    return(list(score = 0, tags = character(0), weight = 0))
  }

  union_tags <- unique(c(left, right))
  shared_weight <- sum(vapply(shared, query_synergy_plan_tag_specificity_weight, numeric(1)))
  union_weight <- sum(vapply(union_tags, query_synergy_plan_tag_specificity_weight, numeric(1)))

  list(
    score = round(min(1, if (union_weight > 0) shared_weight / union_weight else 0), 4),
    tags = shared,
    weight = shared_weight
  )
}

query_synergy_role_complementarity <- function(target_roles, candidate_roles) {
  target_values <- unique(query_synergy_to_vector(target_roles))
  candidate_values <- unique(query_synergy_to_vector(candidate_roles))
  if (length(target_values) == 0L || length(candidate_values) == 0L) {
    return(list(score = 0, pairs = character(0)))
  }

  pairs <- list(
    list(candidate = "producer", target = "payoff", weight = 1.0),
    list(candidate = "engine", target = "payoff", weight = 0.95),
    list(candidate = "engine", target = "target", weight = 0.75),
    list(candidate = "setup", target = "finisher", weight = 1.0),
    list(candidate = "converter", target = "payoff", weight = 0.95),
    list(candidate = "converter", target = "finisher", weight = 0.8),
    list(candidate = "bridge", target = "payoff", weight = 0.85),
    list(candidate = "bridge", target = "finisher", weight = 0.85),
    list(candidate = "amplifier", target = "engine", weight = 0.8),
    list(candidate = "amplifier", target = "producer", weight = 0.72),
    list(candidate = "target", target = "producer", weight = 0.7),
    list(candidate = "finisher", target = "setup", weight = 0.95)
  )

  matched <- Filter(function(pair) {
    pair$candidate %in% candidate_values && pair$target %in% target_values
  }, pairs)
  if (length(matched) == 0L) {
    return(list(score = 0, pairs = character(0)))
  }

  weights <- sort(unique(vapply(matched, function(pair) pair$weight, numeric(1))), decreasing = TRUE)
  top_weights <- weights[seq_len(min(3L, length(weights)))]

  list(
    score = round(min(1, sum(top_weights) / 2.2), 4),
    pairs = unique(vapply(matched, function(pair) sprintf("%s + %s", pair$candidate, pair$target), character(1)))
  )
}

query_synergy_event_family_keys <- function(events, registry = query_synergy_event_registry_default()) {
  event_ids <- unique(query_synergy_canonicalize_events(events, registry))
  if (length(event_ids) == 0L) {
    return(character(0))
  }

  out <- character(0)
  for (event_id in event_ids) {
    lineage <- if (is.list(registry$lineage_cache) && !is.null(registry$lineage_cache[[event_id]])) {
      query_synergy_to_vector(registry$lineage_cache[[event_id]])
    } else {
      query_synergy_build_event_lineage_for_id(event_id, registry$events)
    }
    descendants <- if (is.list(registry$family_cache) && !is.null(registry$family_cache[[event_id]])) {
      query_synergy_to_vector(registry$family_cache[[event_id]])
    } else {
      query_synergy_expand_event_family(event_id, registry)
    }
    out <- c(out, lineage, descendants)
  }

  unique(out)
}

query_synergy_find_relevant_ability <- function(card,
                                                relevant_events,
                                                effect_role = "produce",
                                                registry = query_synergy_event_registry_default()) {
  if (!is.list(card) || !is.list(card$abilities)) {
    return(list(ability = NULL, matched_events = character(0)))
  }

  relevant_ids <- unique(query_synergy_canonicalize_events(relevant_events, registry))
  relevant_family <- unique(query_synergy_event_family_keys(relevant_ids, registry))
  if (length(relevant_family) == 0L) {
    relevant_family <- relevant_ids
  }

  for (ability in card$abilities) {
    if (!is.list(ability) || !is.list(ability$effects)) {
      next
    }
    matched <- character(0)
    for (effect in ability$effects) {
      if (!is.list(effect) || !identical(query_api_scalar(effect$role, default = ""), effect_role)) {
        next
      }
      event_id <- query_api_scalar(effect$event, default = "")
      parent_id <- query_api_scalar(effect$parent, default = "")
      if (event_id %in% relevant_family || parent_id %in% relevant_family) {
        matched <- c(matched, event_id)
      }
    }
    if (length(matched) > 0L) {
      return(list(ability = ability, matched_events = unique(matched)))
    }
  }

  list(ability = NULL, matched_events = character(0))
}

query_synergy_describe_engine_source <- function(card,
                                                 relevant_events = character(0),
                                                 effect_role = "produce",
                                                 registry = query_synergy_event_registry_default()) {
  query_synergy_runtime_metrics_mark_call("describe_engine_source")
  if (!is.list(card)) {
    return("through a structured ability")
  }

  match <- query_synergy_find_relevant_ability(card, relevant_events, effect_role = effect_role, registry = registry)
  cadence <- if (is.list(card$cadence)) card$cadence else list()
  contexts <- query_synergy_to_vector(cadence$contexts)
  context_phrase <- ""
  if (length(contexts) > 0L) {
    mapped <- unique(vapply(contexts, function(context) {
      switch(
        query_api_scalar(context, default = ""),
        combat = "combat-linked",
        spell = "spell-linked",
        card_flow = "card-flow",
        death = "death-linked",
        etb = "ETB-linked",
        turn_cycle = "turn-cycle",
        activated = "activated",
        query_synergy_humanize_id(context)
      )
    }, character(1)))
    mapped <- mapped[nzchar(mapped)]
    if (length(mapped) > 0L) {
      context_phrase <- paste(mapped, collapse = "/")
    }
  }

  cadence_prefix <- if (isTRUE(cadence$repeatable)) {
    "repeatable "
  } else if (isTRUE(cadence$scalable)) {
    "scalable "
  } else {
    ""
  }

  engine_phrase <- if (nzchar(context_phrase)) {
    sprintf("%s%s engine", cadence_prefix, context_phrase)
  } else if (nzchar(cadence_prefix)) {
    sprintf("%sengine", cadence_prefix)
  } else {
    "structured ability"
  }

  ability <- match$ability
  if (is.list(ability) && identical(query_api_scalar(ability$source, default = ""), "mechanic_rule") && nzchar(query_api_scalar(ability$mechanic, default = ""))) {
    mechanic_name <- query_synergy_humanize_id(query_api_scalar(ability$mechanic, default = ""))
    return(sprintf("via %s on a %s", mechanic_name, engine_phrase))
  }
  if (nzchar(engine_phrase) && !identical(engine_phrase, "structured ability")) {
    article <- if (grepl("^[aeiou]", engine_phrase, perl = TRUE)) "an" else "a"
    return(sprintf("via %s %s", article, engine_phrase))
  }
  "through a structured ability"
}

query_synergy_indirect_engine_axis <- function(target,
                                               candidate,
                                               direct_event_score,
                                               role_match,
                                               shared_plan,
                                               registry = query_synergy_event_registry_default()) {
  candidate_roles <- intersect(query_synergy_to_vector(candidate$roles), c("engine", "converter", "bridge", "amplifier"))
  direct_match <- query_synergy_find_relevant_ability(candidate, target$consumed_events, effect_role = "produce", registry = registry)
  produced_family <- unique(query_synergy_event_family_keys(candidate$produced_events, registry))
  target_family <- unique(query_synergy_event_family_keys(target$consumed_events, registry))
  family_matches <- setdiff(intersect(produced_family, target_family), query_synergy_to_vector(target$consumed_events))

  if (length(candidate_roles) == 0L && length(direct_match$matched_events) == 0L && length(family_matches) == 0L && !isTRUE(candidate$cadence$repeatable)) {
    return(list(score = 0, engine_roles = character(0), matched_events = character(0), family_matches = character(0)))
  }

  cadence_factor <- suppressWarnings(as.numeric(candidate$cadence$strength))
  if (!is.finite(cadence_factor) || is.na(cadence_factor)) {
    cadence_factor <- 0
  }
  structured_factor <- if (length(direct_match$matched_events) > 0L) {
    min(1, length(direct_match$matched_events) / max(1, length(unique(target$consumed_events))))
  } else {
    0
  }
  family_factor <- if (length(target_family) > 0L) {
    min(1, length(family_matches) / length(unique(target_family)))
  } else {
    0
  }
  structural_anchor <- max(structured_factor, family_factor, suppressWarnings(as.numeric(direct_event_score)))
  role_factor <- suppressWarnings(as.numeric(role_match$score))
  shared_factor <- suppressWarnings(as.numeric(shared_plan$score))
  if (!is.finite(role_factor) || is.na(role_factor)) {
    role_factor <- 0
  }
  if (!is.finite(shared_factor) || is.na(shared_factor)) {
    shared_factor <- 0
  }

  score <- min(1,
    0.18 * min(1, length(candidate_roles) / 3) +
      0.2 * cadence_factor +
      0.28 * structured_factor +
      0.18 * family_factor +
      0.12 * role_factor +
      0.04 * shared_factor
  )
  cadence_scalable <- isTRUE(candidate$cadence$scalable)
  if (structural_anchor < 0.1) {
    score <- score * if (cadence_scalable && cadence_factor >= 0.6) 0.6 else 0.3
  } else if (structural_anchor < 0.2) {
    score <- score * 0.72
  }

  list(
    score = round(score, 4),
    engine_roles = candidate_roles,
    matched_events = unique(direct_match$matched_events),
    family_matches = unique(family_matches)
  )
}

query_synergy_package_potential_axis <- function(target, candidate, role_match) {
  setup_overlap <- unique(intersect(candidate$setup_events, target$finisher_events))
  finisher_overlap <- unique(intersect(candidate$finisher_events, target$setup_events))
  bridge_inputs <- unique(query_synergy_to_vector(candidate$consumed_events))
  bridge_factor <- if (any(query_synergy_to_vector(candidate$roles) %in% c("converter", "bridge")) && length(bridge_inputs) > 0L) {
    min(1, length(bridge_inputs) / max(1, length(unique(c(candidate$consumed_events, candidate$produced_events)))))
  } else {
    0
  }
  setup_factor <- if (length(target$finisher_events) > 0L) {
    length(setup_overlap) / length(unique(target$finisher_events))
  } else {
    0
  }
  finisher_factor <- if (length(target$setup_events) > 0L) {
    length(finisher_overlap) / length(unique(target$setup_events))
  } else {
    0
  }

  list(
    score = round(min(1, 0.35 * setup_factor + 0.25 * finisher_factor + 0.25 * bridge_factor + 0.15 * role_match$score), 4),
    links = unique(c(setup_overlap, finisher_overlap, bridge_inputs))
  )
}

query_synergy_is_setup_seed_card <- function(card) {
  if (!is.list(card)) {
    return(FALSE)
  }

  roles <- unique(query_synergy_to_vector(card$roles))
  setup_events <- unique(query_synergy_to_vector(card$setup_events))
  produced_events <- unique(query_synergy_to_vector(card$produced_events))
  moves <- query_synergy_to_list(card$moves)

  has_setup_role <- "setup" %in% roles
  has_setup_events <- length(setup_events) > 0L
  has_setup_move <- any(vapply(moves, function(move) {
    to_zone <- query_api_scalar(move$to, default = "")
    from_zone <- query_api_scalar(move$from, default = "")
    nzchar(to_zone) &&
      !identical(to_zone, from_zone) &&
      to_zone %in% c("graveyard", "battlefield", "hand", "exile")
  }, logical(1)))
  has_seed_output <- length(produced_events) > 0L

  isTRUE(has_setup_role || has_setup_events || (has_setup_move && has_seed_output))
}

query_synergy_pair_bridge_axes <- function(target,
                                           candidate,
                                           produced_to_payoff = character(0),
                                           payoff_to_produced = character(0),
                                           direct_event_score = 0,
                                           reciprocal_value_score = 0,
                                           registry = query_synergy_event_registry_default()) {
  source <- if (is.list(target)) target else list()
  sink <- if (is.list(candidate)) candidate else list()
  setup_seed <- query_synergy_is_setup_seed_card(source)
  resource_bridges <- unique(query_synergy_indirect_resource_bridges(source, sink))
  transitions <- query_synergy_collect_resource_transitions(source, sink, registry = registry)
  zone_transitions <- Filter(function(transition) {
    query_api_scalar(transition$kind, default = "") %in% c("zone_chain", "zone_transition_bridge")
  }, transitions)

  zone_transition_labels <- unique(vapply(zone_transitions, function(transition) {
    via <- query_api_scalar(transition$via, default = query_api_scalar(transition$resource, default = "zone_chain"))
    from_zone <- query_api_scalar(transition$from, default = "")
    to_zone <- query_api_scalar(transition$to, default = "")
    if (nzchar(from_zone) || nzchar(to_zone)) {
      sprintf("%s:%s->%s", via, if (nzchar(from_zone)) from_zone else "?", if (nzchar(to_zone)) to_zone else "?")
    } else {
      via
    }
  }, character(1)))

  event_bridge_score <- max(0, min(1, suppressWarnings(as.numeric(direct_event_score))))
  payoff_bridge_score <- max(0, min(1, suppressWarnings(as.numeric(reciprocal_value_score))))
  resource_bridge_score <- min(1, length(resource_bridges) / 2)
  zone_transition_score <- min(1, length(zone_transitions) / 2)
  resource_zone_score <- max(resource_bridge_score, zone_transition_score)
  candidate_roles <- unique(query_synergy_to_vector(sink$roles))
  setup_converter_score <- if (setup_seed) {
    converter_role_support <- as.numeric(any(candidate_roles %in% c("converter", "bridge", "engine")))
    min(1,
      0.42 * converter_role_support +
        0.33 * resource_zone_score +
        0.25 * payoff_bridge_score
    )
  } else {
    max(payoff_bridge_score, event_bridge_score, resource_zone_score)
  }
  has_setup_converter_bridge <- setup_seed && setup_converter_score >= 0.24
  bridge_strength <- max(event_bridge_score, payoff_bridge_score, resource_zone_score, if (has_setup_converter_bridge) setup_converter_score else 0)

  has_event_bridge <- event_bridge_score >= 0.14
  has_payoff_bridge <- payoff_bridge_score >= 0.14
  has_resource_bridge <- resource_bridge_score >= 0.24
  has_zone_bridge <- zone_transition_score >= 0.24
  strong_bridge_count <- sum(c(has_event_bridge, has_payoff_bridge, has_resource_bridge, has_zone_bridge, has_setup_converter_bridge))
  has_strong_bridge <- strong_bridge_count > 0L

  setup_to_converter_score <- setup_converter_score

  bridge_gate <- if (has_strong_bridge) {
    1
  } else if (bridge_strength >= 0.18) {
    0.72
  } else if (bridge_strength >= 0.08) {
    0.52
  } else {
    0.35
  }

  weak_bridge_penalty <- if (has_strong_bridge) {
    0
  } else if (bridge_strength >= 0.18) {
    0.08
  } else if (bridge_strength >= 0.08) {
    0.2
  } else {
    0.34
  }
  if (setup_seed && setup_to_converter_score < 0.12) {
    weak_bridge_penalty <- min(0.5, weak_bridge_penalty + 0.12)
  }

  bridge_types <- unique(c(
    if (has_event_bridge) "event_bridge" else character(0),
    if (has_payoff_bridge) "payoff_bridge" else character(0),
    if (has_resource_bridge) "resource_bridge" else character(0),
    if (has_zone_bridge) "zone_transition_bridge" else character(0),
    if (has_setup_converter_bridge) "setup_converter_bridge" else character(0)
  ))

  list(
    event_bridge_score = round(event_bridge_score, 4),
    payoff_bridge_score = round(payoff_bridge_score, 4),
    resource_bridge_score = round(resource_bridge_score, 4),
    zone_transition_score = round(zone_transition_score, 4),
    resource_zone_score = round(resource_zone_score, 4),
    bridge_strength = round(bridge_strength, 4),
    setup_to_converter_score = round(setup_to_converter_score, 4),
    strong_bridge_count = as.integer(strong_bridge_count),
    has_strong_bridge = isTRUE(has_strong_bridge),
    setup_seed = isTRUE(setup_seed),
    bridge_gate = round(bridge_gate, 4),
    weak_bridge_penalty = round(weak_bridge_penalty, 4),
    resource_bridges = resource_bridges,
    zone_transition_bridges = zone_transition_labels,
    zone_transition_count = as.integer(length(zone_transitions)),
    bridge_types = bridge_types,
    has_setup_converter_bridge = isTRUE(has_setup_converter_bridge),
    produced_to_payoff = unique(query_synergy_to_vector(produced_to_payoff)),
    payoff_to_produced = unique(query_synergy_to_vector(payoff_to_produced))
  )
}


query_synergy_color_fit <- function(target_colors, candidate_colors) {
  left <- unique(query_synergy_to_vector(target_colors))
  right <- unique(query_synergy_to_vector(candidate_colors))

  if (length(left) == 0L || length(right) == 0L) {
    return(0.5)
  }

  inter <- intersect(left, right)
  union <- unique(c(left, right))
  jaccard <- if (length(union) == 0L) 0 else length(inter) / length(union)

  if (length(inter) == 0L) {
    return(0.2)
  }

  min(1, 0.65 + 0.35 * jaccard)
}

query_synergy_format_fit <- function(target_legalities, candidate_legalities, format_name = "commander") {
  format_key <- tolower(query_api_scalar(format_name, default = "commander"))
  if (!nzchar(format_key)) {
    return(0.5)
  }

  target_legality <- tolower(query_api_scalar(target_legalities[[format_key]], default = ""))
  candidate_legality <- tolower(query_api_scalar(candidate_legalities[[format_key]], default = ""))

  if (!nzchar(target_legality) || !nzchar(candidate_legality)) {
    return(0.5)
  }

  legal_values <- c("legal", "restricted")
  if (target_legality %in% legal_values && candidate_legality %in% legal_values) {
    return(1)
  }
  if (target_legality %in% legal_values || candidate_legality %in% legal_values) {
    return(0.35)
  }

  0.1
}

query_synergy_tempo_fit <- function(target_mana_value, candidate_mana_value) {
  left <- suppressWarnings(as.numeric(target_mana_value))
  right <- suppressWarnings(as.numeric(candidate_mana_value))
  if (!is.finite(left) || is.na(left) || !is.finite(right) || is.na(right)) {
    return(0.5)
  }

  distance <- abs(left - right)
  max(0, 1 - min(distance, 7) / 7)
}

query_synergy_anti_penalty <- function(target_anti_tags, candidate_anti_tags) {
  left <- unique(query_synergy_to_vector(target_anti_tags))
  right <- unique(query_synergy_to_vector(candidate_anti_tags))

  if (length(left) == 0L || length(right) == 0L) {
    return(0)
  }

  pairs <- list(
    c("HAND_SIZE_PAYOFF", "HAND_DISCARD_PRESSURE"),
    c("GRAVEYARD_DEPENDENT", "GRAVEYARD_HATE")
  )

  penalty <- 0
  for (pair in pairs) {
    if ((pair[[1]] %in% left && pair[[2]] %in% right) || (pair[[2]] %in% left && pair[[1]] %in% right)) {
      penalty <- penalty + 0.5
    }
  }

  min(1, penalty)
}

query_synergy_event_conflict_penalty <- function(conflict_count, step = 0.5) {
  n <- suppressWarnings(as.integer(conflict_count))
  if (!is.finite(n) || is.na(n) || n <= 0L) {
    return(0)
  }

  weight <- suppressWarnings(as.numeric(step))
  if (!is.finite(weight) || is.na(weight) || weight <= 0) {
    weight <- 0.5
  }

  min(1, n * weight)
}

query_synergy_anti_conflicts <- function(target_anti_tags, candidate_anti_tags) {
  left <- unique(query_synergy_to_vector(target_anti_tags))
  right <- unique(query_synergy_to_vector(candidate_anti_tags))
  if (length(left) == 0L || length(right) == 0L) {
    return(list(pairs = character(0), reasons = character(0)))
  }

  pair_map <- list(
    HAND_SIZE_PAYOFF = "HAND_DISCARD_PRESSURE",
    GRAVEYARD_DEPENDENT = "GRAVEYARD_HATE"
  )

  pairs <- character(0)
  reasons <- character(0)
  for (lhs in names(pair_map)) {
    rhs <- pair_map[[lhs]]
    if ((lhs %in% left && rhs %in% right) || (rhs %in% left && lhs %in% right)) {
      pair_id <- sprintf("%s<->%s", lhs, rhs)
      pairs <- c(pairs, pair_id)
      if (identical(pair_id, "HAND_SIZE_PAYOFF<->HAND_DISCARD_PRESSURE")) {
        reasons <- c(reasons, "Plan conflict: hand-size payoff clashes with discard pressure")
      }
      if (identical(pair_id, "GRAVEYARD_DEPENDENT<->GRAVEYARD_HATE")) {
        reasons <- c(reasons, "Plan conflict: graveyard-dependent card clashes with graveyard hate")
      }
    }
  }

  list(
    pairs = unique(pairs),
    reasons = unique(reasons)
  )
}

query_synergy_strategic_incoherence_penalty <- function(produced_to_payoff,
                                                        payoff_to_produced,
                                                        shared_plan,
                                                        setup_finisher,
                                                        resource_bridges = character(0),
                                                        zone_transition_bridges = character(0)) {
  bridge_count <- length(unique(c(
    query_synergy_to_vector(produced_to_payoff),
    query_synergy_to_vector(payoff_to_produced),
    query_synergy_to_vector(setup_finisher),
    query_synergy_to_vector(resource_bridges),
    query_synergy_to_vector(zone_transition_bridges)
  )))
  plan_count <- length(unique(query_synergy_to_vector(shared_plan)))

  if (bridge_count == 0L && plan_count == 0L) {
    return(0.78)
  }
  if (bridge_count == 0L && plan_count <= 1L) {
    return(0.42)
  }
  if (bridge_count <= 1L && plan_count == 0L) {
    return(0.18)
  }
  0
}

query_synergy_tempo_mismatch_penalty <- function(tempo_fit, shared_plan) {
  fit <- suppressWarnings(as.numeric(tempo_fit))
  if (!is.finite(fit) || is.na(fit)) {
    return(0)
  }
  if (fit < 0.3 && length(query_synergy_to_vector(shared_plan)) == 0L) {
    return(0.6)
  }
  if (fit < 0.15) {
    return(0.8)
  }
  0
}
