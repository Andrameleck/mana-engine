query_synergy_cache_env <- local({
  env <- new.env(parent = emptyenv())
  env$catalog <- NULL
  env$catalog_loaded_at <- as.POSIXct(NA)
  env$catalog_source <- ""
  env$normalized_by_id <- new.env(parent = emptyenv(), hash = TRUE)
  env
})

query_synergy_find <- function(req = NULL) {
  payload <- query_synergy_parse_payload(req)
  if (!isTRUE(payload$ok)) {
    return(query_api_error(payload$error, best_matches = list()))
  }

  catalog <- if (is.list(payload$data$cards) && length(payload$data$cards) > 0L) {
    payload$data$cards
  } else {
    catalog_out <- query_synergy_get_catalog(force_refresh = isTRUE(payload$data$force_refresh))
    if (!isTRUE(catalog_out$ok)) {
      return(query_api_error(catalog_out$error, best_matches = list()))
    }
    catalog_out$cards
  }

  result <- query_synergy_find_in_catalog(payload$data, catalog)
  if (!isTRUE(result$ok)) {
    return(query_api_error(result$error, best_matches = list()))
  }

  result
}

query_synergy_normalize_cards <- function(req = NULL) {
  payload <- query_synergy_parse_payload(req)
  if (!isTRUE(payload$ok)) {
    return(query_api_error(payload$error, cards = list()))
  }

  data <- payload$data
  cards <- data$cards
  if (!is.list(cards) || length(cards) == 0L) {
    single <- data$card
    if (is.list(single) && length(single) > 0L) {
      cards <- list(single)
    }
  }

  if (!is.list(cards) || length(cards) == 0L) {
    return(query_api_error("payload must contain card or cards", cards = list()))
  }

  registry <- query_synergy_event_registry_default()
  normalized <- lapply(cards, function(card) {
    query_synergy_normalize_card(card, registry = registry)
  })

  list(
    ok = TRUE,
    count = length(normalized),
    cards = normalized
  )
}

query_synergy_get_card <- function(card_id = "", include_normalized = "true") {
  lookup <- trimws(as.character(card_id))
  if (!nzchar(lookup)) {
    return(query_api_error("missing card id"))
  }

  catalog_out <- query_synergy_get_catalog(force_refresh = FALSE)
  if (!isTRUE(catalog_out$ok)) {
    return(query_api_error(catalog_out$error))
  }

  card <- query_synergy_find_card_by_id_or_name(catalog_out$cards, lookup)
  if (is.null(card)) {
    return(query_api_error("card not found in Scryfall catalog"))
  }

  include_norm <- query_api_parse_bool(include_normalized, default = TRUE)
  out <- list(
    ok = TRUE,
    source = "scryfall_oracle_cards",
    card = card
  )

  if (include_norm) {
    out$normalized <- query_synergy_normalize_card(card, query_synergy_event_registry_default())
  }

  out
}

query_synergy_list_events <- function() {
  registry <- query_synergy_event_registry_default()
  events <- lapply(names(registry$events), function(event_id) {
    event <- registry$events[[event_id]]
    list(
      id = event_id,
      label = event$label,
      description = event$description,
      parent = event$parent,
      aliases = event$aliases
    )
  })

  list(
    ok = TRUE,
    count = length(events),
    events = events
  )
}

query_synergy_list_mechanics <- function() {
  rules <- query_synergy_mechanic_rules_default()
  mechanics <- lapply(names(rules), function(rule_id) {
    rule <- rules[[rule_id]]
    list(
      id = rule_id,
      keywords = rule$keywords,
      produced_events = rule$produced,
      consumed_events = rule$consumed,
      replaced_events = rule$replaced,
      prevented_events = rule$prevented,
      setup_events = rule$setup,
      finisher_events = rule$finisher,
      anti_tags = rule$anti_tags,
      strategy_tags = rule$strategy_tags,
      notes = rule$notes
    )
  })

  list(
    ok = TRUE,
    count = length(mechanics),
    mechanics = mechanics
  )
}

query_synergy_find_in_catalog <- function(payload = list(), catalog = list()) {
  if (!is.list(catalog) || length(catalog) < 3L) {
    return(query_api_error("catalog must contain at least 3 cards"))
  }

  card_name <- query_api_scalar(payload$card_name, default = query_api_scalar(payload$card_id, default = ""))
  if (!nzchar(card_name)) {
    return(query_api_error("card_name is required"))
  }

  target_card <- query_synergy_find_card_by_id_or_name(catalog, card_name)
  if (is.null(target_card)) {
    return(query_api_error("target card not found"))
  }

  format_name <- tolower(query_api_scalar(payload$format, default = "commander"))
  max_results <- query_synergy_as_int(payload$max_results, default = 50L, min_value = 1L, max_value = 200L)
  color_filter <- query_synergy_parse_color_identity(payload$color_identity)

  registry <- query_synergy_event_registry_default()
  target_normalized <- query_synergy_normalize_card_cached(target_card, registry = registry)

  candidate_cards <- Filter(function(card) {
    candidate_id <- query_synergy_card_id(card)
    if (!nzchar(candidate_id) || identical(candidate_id, target_normalized$id)) {
      return(FALSE)
    }

    if (length(color_filter) == 0L) {
      return(TRUE)
    }

    candidate_colors <- query_synergy_card_color_identity(card)
    length(intersect(candidate_colors, color_filter)) > 0L
  }, catalog)

  scored <- lapply(candidate_cards, function(card) {
    candidate <- query_synergy_normalize_card_cached(card, registry = registry)
    score <- query_synergy_score_pair(target_normalized, candidate, format_name)
    list(
      card = candidate,
      score = score
    )
  })

  scored <- Filter(function(entry) {
    is.list(entry$score) && is.finite(entry$score$score) && entry$score$score > 0
  }, scored)

  if (length(scored) == 0L) {
    return(list(
      ok = TRUE,
      card = target_normalized$name,
      card_id = target_normalized$id,
      count = 0,
      format = format_name,
      color_identity = color_filter,
      best_matches = list()
    ))
  }

  ord <- order(vapply(scored, function(entry) entry$score$score, numeric(1)), decreasing = TRUE)
  scored <- scored[ord]
  if (length(scored) > max_results) {
    scored <- scored[seq_len(max_results)]
  }

  matches <- lapply(scored, function(entry) {
    candidate <- entry$card
    score <- entry$score
    list(
      id = candidate$id,
      name = candidate$name,
      score = score$score,
      score_breakdown = score$breakdown,
      reasons = score$reasons,
      relation_classes = score$relation_classes,
      matched_events = score$matched_events
    )
  })

  list(
    ok = TRUE,
    card = target_normalized$name,
    card_id = target_normalized$id,
    count = length(matches),
    format = format_name,
    color_identity = color_filter,
    normalized_target = target_normalized,
    best_matches = matches
  )
}

query_synergy_score_pair <- function(target, candidate, format_name = "commander") {
  produced_to_payoff <- intersect(candidate$produced_events, target$consumed_events)
  payoff_to_produced <- intersect(candidate$consumed_events, target$produced_events)
  shared_plan <- intersect(target$strategy_tags, candidate$strategy_tags)
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

  production_ratio <- if (length(target$consumed_events) > 0L) {
    length(produced_to_payoff) / length(unique(target$consumed_events))
  } else {
    0
  }
  payoff_ratio <- if (length(target$produced_events) > 0L) {
    length(payoff_to_produced) / length(unique(target$produced_events))
  } else {
    0
  }
  shared_ratio <- if (length(target$strategy_tags) > 0L) {
    length(shared_plan) / length(unique(target$strategy_tags))
  } else {
    0
  }
  setup_ratio <- if (length(unique(c(target$setup_events, target$finisher_events))) > 0L) {
    length(setup_finisher) / length(unique(c(target$setup_events, target$finisher_events)))
  } else {
    0
  }

  color_fit <- query_synergy_color_fit(target$color_identity, candidate$color_identity)
  format_fit <- query_synergy_format_fit(target$legalities, candidate$legalities, format_name)
  tempo_fit <- query_synergy_tempo_fit(target$mana_value, candidate$mana_value)

  anti_penalty <- query_synergy_anti_penalty(target$anti_tags, candidate$anti_tags)
  replacement_penalty <- query_synergy_event_conflict_penalty(length(replacement_conflicts), step = 0.6)
  prevention_penalty <- query_synergy_event_conflict_penalty(length(prevention_conflicts), step = 0.5)
  direct_bridge_bonus <- if (length(produced_to_payoff) > 0L) 0.18 else 0
  if ("DRAW_CARD" %in% produced_to_payoff) {
    direct_bridge_bonus <- max(direct_bridge_bonus, 0.26)
  }

  score_norm <-
    0.34 * production_ratio +
    0.24 * payoff_ratio +
    0.15 * shared_ratio +
    0.11 * setup_ratio +
    0.07 * color_fit +
    0.05 * format_fit +
    0.04 * tempo_fit +
    direct_bridge_bonus -
    0.30 * anti_penalty -
    0.35 * replacement_penalty -
    0.25 * prevention_penalty

  score_norm <- max(0, min(1, score_norm))
  score_value <- as.integer(round(score_norm * 100))

  reasons <- character(0)
  if (length(produced_to_payoff) > 0L) {
    reasons <- c(reasons, sprintf(
      "Produces %s that %s rewards",
      paste(produced_to_payoff, collapse = ", "),
      target$name
    ))
  }
  if (length(payoff_to_produced) > 0L) {
    reasons <- c(reasons, sprintf(
      "Rewards %s produced by %s",
      paste(payoff_to_produced, collapse = ", "),
      target$name
    ))
  }
  if (length(shared_plan) > 0L) {
    reasons <- c(reasons, sprintf("Shared plan tags: %s", paste(shared_plan, collapse = ", ")))
  }
  if (length(setup_finisher) > 0L) {
    reasons <- c(reasons, sprintf("Setup/finisher overlap: %s", paste(setup_finisher, collapse = ", ")))
  }
  if (length(replacement_conflicts) > 0L) {
    reasons <- c(reasons, sprintf(
      "Replaces %s needed by %s",
      paste(replacement_conflicts, collapse = ", "),
      target$name
    ))
  }
  if (length(prevention_conflicts) > 0L) {
    reasons <- c(reasons, sprintf(
      "Prevents %s needed by %s",
      paste(prevention_conflicts, collapse = ", "),
      target$name
    ))
  }
  if (anti_penalty > 0) {
    reasons <- c(reasons, "Anti-synergy detected (conflicting hand or graveyard plan)")
  }
  if (length(reasons) == 0L) {
    reasons <- c("Weak mechanical overlap")
  }

  classes <- character(0)
  if (length(produced_to_payoff) > 0L) {
    classes <- c(classes, "enabler_payoff")
  }
  if (length(payoff_to_produced) > 0L) {
    classes <- c(classes, "payoff_enabler")
  }
  if (length(shared_plan) > 0L) {
    classes <- c(classes, "shared_plan")
  }
  if (length(setup_finisher) > 0L) {
    classes <- c(classes, "setup_finisher")
  }
  if (anti_penalty > 0) {
    classes <- c(classes, "anti_synergy")
  }
  if (length(replacement_conflicts) > 0L || length(prevention_conflicts) > 0L) {
    classes <- c(classes, "event_conflict")
  }

  list(
    score = score_value,
    score_norm = score_norm,
    breakdown = list(
      event_production_match = round(production_ratio, 4),
      event_payoff_match = round(payoff_ratio, 4),
      shared_plan = round(shared_ratio, 4),
      setup_finisher = round(setup_ratio, 4),
      color_fit = round(color_fit, 4),
      format_fit = round(format_fit, 4),
      tempo_fit = round(tempo_fit, 4),
      direct_bridge_bonus = round(direct_bridge_bonus, 4),
      anti_penalty = round(anti_penalty, 4),
      replacement_penalty = round(replacement_penalty, 4),
      prevention_penalty = round(prevention_penalty, 4)
    ),
    reasons = unique(reasons),
    relation_classes = unique(classes),
    matched_events = list(
      enabler_to_payoff = produced_to_payoff,
      payoff_to_enabler = payoff_to_produced,
      shared_plan = shared_plan,
      setup_finisher = setup_finisher,
      replaces_payoff = replacement_conflicts,
      prevents_payoff = prevention_conflicts
    )
  )
}
query_synergy_normalize_card <- function(card,
                                         registry = query_synergy_event_registry_default(),
                                         mechanic_rules = query_synergy_mechanic_rules_default()) {
  if (!is.list(card) || length(card) == 0L) {
    return(query_synergy_empty_normalized_card())
  }

  card_id <- query_synergy_card_id(card)
  card_name <- query_api_scalar(card$name, default = card_id)
  oracle_text <- query_api_scalar(card$oracle_text, default = query_api_scalar(card$text, default = ""))
  type_line <- query_api_scalar(card$type_line, default = query_api_scalar(card$type, default = ""))
  mana_value <- suppressWarnings(as.numeric(if (!is.null(card$cmc)) card$cmc else card$mana_value))
  if (!is.finite(mana_value) || is.na(mana_value)) {
    mana_value <- 0
  }

  keywords <- query_synergy_to_vector(card$keywords)
  mechanics_from_text <- query_synergy_detect_mechanics_from_text(oracle_text)
  mechanics <- unique(c(tolower(keywords), mechanics_from_text))

  expanded <- query_synergy_expand_mechanics(mechanics, registry = registry, rules = mechanic_rules)
  extracted <- query_synergy_extract_events_from_text(oracle_text, registry = registry)

  produced <- unique(c(expanded$produced, extracted$produced))
  consumed <- unique(c(expanded$consumed, extracted$consumed))
  replaced <- unique(c(expanded$replaced, extracted$replaced))
  prevented <- unique(c(expanded$prevented, extracted$prevented))
  setup_events <- unique(c(expanded$setup, extracted$setup))
  finisher_events <- unique(c(expanded$finisher, extracted$finisher))
  reward_events <- unique(extracted$consumed)
  required_events <- unique(expanded$consumed)

  strategy_tags <- unique(c(
    expanded$strategy_tags,
    query_synergy_strategy_tags_from_events(produced, consumed, setup_events, finisher_events)
  ))

  anti_tags <- unique(c(expanded$anti_tags, extracted$anti_tags))
  abilities <- query_synergy_build_ability_records(
    keywords = keywords,
    mechanics = mechanics,
    expanded_abilities = expanded$abilities,
    parsed_abilities = extracted$abilities
  )
  produces <- query_synergy_build_event_role_records(produced, "produce", registry)
  rewards <- query_synergy_build_event_role_records(reward_events, "reward", registry)
  requires <- query_synergy_build_event_role_records(required_events, "require", registry)
  replaces <- query_synergy_build_event_role_records(replaced, "replace", registry)
  prevents <- query_synergy_build_event_role_records(prevented, "prevent", registry)
  amplifies <- query_synergy_build_event_role_records(character(0), "amplify", registry)
  moves <- query_synergy_build_move_records(unique(c(produced, replaced)), registry)
  target_roles <- query_synergy_infer_target_roles(type_line, produced, consumed, replaced, prevented)
  plans <- list(
    tags = strategy_tags,
    setup = setup_events,
    finisher = finisher_events,
    anti = anti_tags
  )
  roles <- query_synergy_infer_card_roles(
    produces = produces,
    rewards = rewards,
    requires = requires,
    replaces = replaces,
    prevents = prevents,
    moves = moves,
    setup_events = setup_events,
    finisher_events = finisher_events
  )

  list(
    id = card_id,
    name = card_name,
    model_version = "normalized_card_v2",
    colors = query_synergy_card_colors(card),
    color_identity = query_synergy_card_color_identity(card),
    mana_value = as.numeric(mana_value),
    type_line = type_line,
    oracle_text = oracle_text,
    abilities = abilities,
    produces = produces,
    rewards = rewards,
    requires = requires,
    replaces = replaces,
    prevents = prevents,
    amplifies = amplifies,
    moves = moves,
    target_roles = target_roles,
    plans = plans,
    roles = roles,
    mechanics = mechanics,
    keywords = keywords,
    produced_events = produced,
    consumed_events = consumed,
    replaced_events = replaced,
    prevented_events = prevented,
    setup_events = setup_events,
    finisher_events = finisher_events,
    strategy_tags = strategy_tags,
    anti_tags = anti_tags,
    legalities = query_synergy_card_legalities(card)
  )
}

query_synergy_empty_normalized_card <- function() {
  list(
    id = "",
    name = "",
    model_version = "normalized_card_v2",
    colors = character(0),
    color_identity = character(0),
    mana_value = 0,
    type_line = "",
    oracle_text = "",
    abilities = list(),
    produces = list(),
    rewards = list(),
    requires = list(),
    replaces = list(),
    prevents = list(),
    amplifies = list(),
    moves = list(),
    target_roles = character(0),
    plans = list(
      tags = character(0),
      setup = character(0),
      finisher = character(0),
      anti = character(0)
    ),
    roles = character(0),
    mechanics = character(0),
    keywords = character(0),
    produced_events = character(0),
    consumed_events = character(0),
    replaced_events = character(0),
    prevented_events = character(0),
    setup_events = character(0),
    finisher_events = character(0),
    strategy_tags = character(0),
    anti_tags = character(0),
    legalities = list()
  )
}

query_synergy_build_ability_records <- function(keywords,
                                                mechanics,
                                                expanded_abilities = list(),
                                                parsed_abilities = list()) {
  keyword_values <- query_synergy_to_vector(keywords)
  mechanic_values <- query_synergy_to_vector(mechanics)

  out <- list()
  if (length(keyword_values) > 0L) {
    for (value in keyword_values) {
      out[[length(out) + 1L]] <- list(
        kind = "keyword",
        id = tolower(value),
        label = value,
        source = "keyword",
        text = value,
        trigger = list(),
        effects = list(),
        references = list()
      )
    }
  }
  if (length(mechanic_values) > 0L) {
    for (value in mechanic_values) {
      out[[length(out) + 1L]] <- list(
        kind = "mechanic",
        id = tolower(value),
        label = value,
        source = "mechanic",
        text = value,
        trigger = list(),
        effects = list(),
        references = list()
      )
    }
  }

  out <- c(
    out,
    query_synergy_to_list(expanded_abilities),
    query_synergy_to_list(parsed_abilities)
  )
  query_synergy_unique_abilities(out)
}

query_synergy_unique_abilities <- function(abilities) {
  values <- query_synergy_to_list(abilities)
  if (length(values) == 0L) {
    return(list())
  }

  out <- list()
  seen <- new.env(parent = emptyenv(), hash = TRUE)
  for (ability in values) {
    if (!is.list(ability)) {
      next
    }

    ability_id <- query_api_scalar(ability$id, default = "")
    if (!nzchar(ability_id)) {
      ability_id <- sprintf("ability_%s", length(out) + 1L)
      ability$id <- ability_id
    }
    if (exists(ability_id, envir = seen, inherits = FALSE)) {
      next
    }
    assign(ability_id, TRUE, envir = seen)
    out[[length(out) + 1L]] <- ability
  }

  out
}

query_synergy_to_list <- function(value) {
  if (is.null(value)) {
    return(list())
  }
  if (is.list(value) && length(value) > 0L) {
    return(unname(value))
  }
  list()
}

query_synergy_build_event_role_records <- function(events, role, registry = query_synergy_event_registry_default()) {
  event_ids <- unique(query_synergy_canonicalize_events(events, registry))
  if (length(event_ids) == 0L) {
    return(list())
  }

  out <- vector("list", length(event_ids))
  for (i in seq_along(event_ids)) {
    event_id <- event_ids[[i]]
    event_def <- registry$events[[event_id]]
    out[[i]] <- list(
      event = event_id,
      role = query_api_scalar(role, default = ""),
      parent = query_api_scalar(event_def$parent, default = ""),
      kind = query_api_scalar(event_def$kind, default = "event"),
      scope = query_api_scalar(event_def$scope, default = "generic"),
      resource = query_api_scalar(event_def$resource, default = ""),
      tags = query_synergy_to_vector(event_def$tags)
    )
  }

  out
}

query_synergy_build_move_records <- function(events, registry = query_synergy_event_registry_default()) {
  event_ids <- unique(query_synergy_canonicalize_events(events, registry))
  if (length(event_ids) == 0L) {
    return(list())
  }

  out <- list()
  for (event_id in event_ids) {
    event_def <- registry$events[[event_id]]
    zones <- event_def$zones
    if (!is.list(zones) || length(zones) == 0L) {
      next
    }

    zone_from <- query_api_scalar(zones$from, default = "")
    zone_to <- query_api_scalar(zones$to, default = "")
    if (!nzchar(zone_from) || !nzchar(zone_to) || identical(zone_from, zone_to)) {
      next
    }

    out[[length(out) + 1L]] <- list(
      event = event_id,
      from = zone_from,
      to = zone_to,
      resource = query_api_scalar(event_def$resource, default = ""),
      kind = query_api_scalar(event_def$kind, default = "event")
    )
  }

  out
}

query_synergy_infer_target_roles <- function(type_line, produced, consumed, replaced, prevented) {
  out <- character(0)
  all_events <- unique(c(
    query_synergy_to_vector(produced),
    query_synergy_to_vector(consumed),
    query_synergy_to_vector(replaced),
    query_synergy_to_vector(prevented)
  ))

  if ("TARGETS_CREATURE" %in% all_events) {
    out <- c(out, "creature")
  }

  type_text <- tolower(query_api_scalar(type_line, default = ""))
  if (grepl("\\bartifact\\b", type_text, perl = TRUE)) {
    out <- c(out, "artifact_card")
  }
  if (grepl("\\benchantment\\b", type_text, perl = TRUE)) {
    out <- c(out, "enchantment_card")
  }
  if (grepl("\\bcreature\\b", type_text, perl = TRUE)) {
    out <- c(out, "creature_card")
  }

  unique(out)
}

query_synergy_infer_card_roles <- function(produces,
                                           rewards,
                                           requires,
                                           replaces,
                                           prevents,
                                           moves,
                                           setup_events,
                                           finisher_events) {
  roles <- character(0)

  if (length(produces) > 0L) {
    roles <- c(roles, "producer")
  }
  if (length(rewards) > 0L) {
    roles <- c(roles, "payoff")
  }
  if (length(requires) > 0L) {
    roles <- c(roles, "dependent")
  }
  if (length(replaces) > 0L) {
    roles <- c(roles, "replacer")
  }
  if (length(prevents) > 0L) {
    roles <- c(roles, "preventer")
  }
  if (length(moves) > 0L) {
    roles <- c(roles, "mover")
  }
  if (length(query_synergy_to_vector(setup_events)) > 0L) {
    roles <- c(roles, "setup")
  }
  if (length(query_synergy_to_vector(finisher_events)) > 0L) {
    roles <- c(roles, "finisher")
  }
  if (length(produces) > 0L && length(rewards) > 0L) {
    roles <- c(roles, "engine")
  }

  unique(roles)
}

query_synergy_event_registry_default <- local({
  cached <- NULL

  function() {
    if (!is.null(cached)) {
      return(cached)
    }

    cached <<- query_synergy_build_event_registry(query_synergy_event_registry_seed())
    cached
  }
})

query_synergy_event_registry_seed <- function() {
  list(
    DRAW_CARD = list(
      label = "Draw card",
      description = "Card draw event",
      parent = "CARD_FLOW",
      aliases = c("DRAW"),
      kind = "resource_flow",
      scope = "generic",
      resource = "card",
      zones = list(from = "library", to = "hand"),
      tags = c("card_flow")
    ),
    SELF_DRAW_CARD = list(
      label = "Self draw",
      description = "You draw one or more cards",
      parent = "DRAW_CARD",
      aliases = c("YOU_DRAW_CARD"),
      kind = "resource_flow",
      scope = "self",
      resource = "card",
      zones = list(from = "library", to = "hand"),
      tags = c("card_flow", "self")
    ),
    OPPONENT_DRAW_CARD = list(
      label = "Opponent draw",
      description = "An opponent draws one or more cards",
      parent = "DRAW_CARD",
      aliases = character(0),
      kind = "resource_flow",
      scope = "opponent",
      resource = "card",
      zones = list(from = "library", to = "hand"),
      tags = c("card_flow", "opponent")
    ),
    DISCARD_CARD = list(
      label = "Discard card",
      description = "Card discard event",
      parent = "CARD_FLOW",
      aliases = c("CARD_DISCARDED"),
      kind = "resource_flow",
      scope = "generic",
      resource = "card",
      zones = list(from = "hand", to = "graveyard"),
      tags = c("card_flow")
    ),
    GAIN_LIFE = list(
      label = "Gain life",
      description = "Life gain event",
      parent = "LIFE_TOTAL",
      aliases = c("LIFE_GAINED"),
      kind = "resource_delta",
      scope = "generic",
      resource = "life",
      zones = list(),
      tags = c("life")
    ),
    LOSE_LIFE = list(
      label = "Lose life",
      description = "Life loss event",
      parent = "LIFE_TOTAL",
      aliases = c("LIFE_LOST"),
      kind = "resource_delta",
      scope = "generic",
      resource = "life",
      zones = list(),
      tags = c("life")
    ),
    CREATE_TOKEN = list(
      label = "Create token",
      description = "Token creation event",
      parent = "BOARD_DEVELOPMENT",
      aliases = c("TOKEN_CREATED"),
      kind = "board_delta",
      scope = "generic",
      resource = "token",
      zones = list(from = "outside_game", to = "battlefield"),
      tags = c("tokens")
    ),
    ADD_MANA = list(
      label = "Add mana",
      description = "Mana generation event",
      parent = "MANA_ENGINE",
      aliases = character(0),
      kind = "resource_delta",
      scope = "generic",
      resource = "mana",
      zones = list(),
      tags = c("mana")
    ),
    PUT_COUNTER = list(
      label = "Put counter",
      description = "Counter placement event",
      parent = "BOARD_DEVELOPMENT",
      aliases = c("COUNTER_PLACED"),
      kind = "board_delta",
      scope = "generic",
      resource = "counter",
      zones = list(),
      tags = c("counters")
    ),
    SACRIFICE_PERMANENT = list(
      label = "Sacrifice permanent",
      description = "Sacrifice event",
      parent = "GRAVEYARD_FLOW",
      aliases = character(0),
      kind = "zone_change",
      scope = "generic",
      resource = "permanent",
      zones = list(from = "battlefield", to = "graveyard"),
      tags = c("sacrifice")
    ),
    ETB = list(
      label = "Enters battlefield",
      description = "Permanent ETB event",
      parent = "BOARD_DEVELOPMENT",
      aliases = c("ENTERS_THE_BATTLEFIELD"),
      kind = "zone_change",
      scope = "generic",
      resource = "permanent",
      zones = list(from = "stack", to = "battlefield"),
      tags = c("battlefield")
    ),
    DIES = list(
      label = "Dies",
      description = "Permanent dies event",
      parent = "GRAVEYARD_FLOW",
      aliases = c("CREATURE_DIES"),
      kind = "zone_change",
      scope = "generic",
      resource = "permanent",
      zones = list(from = "battlefield", to = "graveyard"),
      tags = c("death")
    ),
    ATTACKS = list(
      label = "Attacks",
      description = "Attack event",
      parent = "COMBAT",
      aliases = c("ATTACK_DECLARED"),
      kind = "combat",
      scope = "generic",
      resource = "",
      zones = list(),
      tags = c("combat")
    ),
    CAST_SPELL = list(
      label = "Cast spell",
      description = "Spell cast event",
      parent = "STACK",
      aliases = character(0),
      kind = "stack",
      scope = "generic",
      resource = "spell",
      zones = list(from = "hand", to = "stack"),
      tags = c("casting")
    ),
    GRAVEYARD_TO_HAND = list(
      label = "GY to hand",
      description = "Recursion from graveyard to hand",
      parent = "GRAVEYARD_FLOW",
      aliases = c("RECURSION_TO_HAND"),
      kind = "zone_change",
      scope = "generic",
      resource = "card",
      zones = list(from = "graveyard", to = "hand"),
      tags = c("graveyard", "recursion")
    ),
    MILL_CARD = list(
      label = "Mill card",
      description = "Library to graveyard",
      parent = "GRAVEYARD_FLOW",
      aliases = c("SELF_MILL"),
      kind = "zone_change",
      scope = "generic",
      resource = "card",
      zones = list(from = "library", to = "graveyard"),
      tags = c("graveyard", "mill")
    ),
    REANIMATE = list(
      label = "Reanimate",
      description = "Graveyard to battlefield",
      parent = "GRAVEYARD_FLOW",
      aliases = character(0),
      kind = "zone_change",
      scope = "generic",
      resource = "permanent",
      zones = list(from = "graveyard", to = "battlefield"),
      tags = c("graveyard", "reanimate")
    ),
    NONCREATURE_SPELL_CAST = list(
      label = "Cast noncreature",
      description = "Noncreature spell cast",
      parent = "CAST_SPELL",
      aliases = character(0),
      kind = "stack",
      scope = "generic",
      resource = "spell",
      zones = list(from = "hand", to = "stack"),
      tags = c("casting", "noncreature")
    ),
    COMBAT_DAMAGE_TO_PLAYER = list(
      label = "Combat damage to player",
      description = "Combat damage connection",
      parent = "COMBAT",
      aliases = character(0),
      kind = "combat",
      scope = "generic",
      resource = "damage",
      zones = list(),
      tags = c("combat", "damage")
    ),
    TARGETS_CREATURE = list(
      label = "Targets creature",
      description = "Spell or ability targets a creature",
      parent = "STACK",
      aliases = character(0),
      kind = "targeting",
      scope = "generic",
      resource = "creature",
      zones = list(),
      tags = c("targeting")
    ),
    EXILE_CARD = list(
      label = "Exile card",
      description = "Card is exiled",
      parent = "ZONE_CHANGE",
      aliases = character(0),
      kind = "zone_change",
      scope = "generic",
      resource = "card",
      zones = list(to = "exile"),
      tags = c("exile")
    )
  )
}

query_synergy_build_event_registry <- function(events = list(), base_registry = NULL) {
  if (is.list(base_registry) && is.list(base_registry$events)) {
    merged <- base_registry$events
  } else if (is.list(base_registry) && length(base_registry) > 0L && is.null(base_registry$events)) {
    merged <- base_registry
  } else {
    merged <- list()
  }

  additions <- if (is.list(events)) events else list()
  for (name in names(additions)) {
    event_id <- query_synergy_normalize_event_id(name)
    if (!nzchar(event_id)) {
      next
    }
    merged[[event_id]] <- query_synergy_normalize_event_definition(event_id, additions[[name]])
  }

  alias_to_id <- list()
  for (event_id in names(merged)) {
    event_def <- query_synergy_normalize_event_definition(event_id, merged[[event_id]])
    merged[[event_id]] <- event_def
    aliases <- unique(c(event_id, query_synergy_to_vector(event_def$aliases)))
    for (alias in aliases) {
      alias_to_id[[query_synergy_normalize_event_id(alias)]] <- event_id
    }
  }

  list(events = merged, alias_to_id = alias_to_id)
}

query_synergy_normalize_event_definition <- function(event_id, definition) {
  def <- if (is.list(definition)) definition else list()
  zones <- def$zones
  if (!is.list(zones)) {
    zones <- list()
  }

  list(
    id = query_synergy_normalize_event_id(event_id),
    label = query_api_scalar(def$label, default = query_synergy_normalize_event_id(event_id)),
    description = query_api_scalar(def$description, default = ""),
    parent = query_synergy_normalize_event_id(query_api_scalar(def$parent, default = "")),
    aliases = unique(query_synergy_to_vector(def$aliases)),
    kind = query_api_scalar(def$kind, default = "event"),
    scope = query_api_scalar(def$scope, default = "generic"),
    resource = query_api_scalar(def$resource, default = ""),
    zones = list(
      from = query_api_scalar(zones$from, default = ""),
      to = query_api_scalar(zones$to, default = "")
    ),
    tags = unique(query_synergy_to_vector(def$tags))
  )
}

query_synergy_normalize_event_id <- function(value) {
  raw <- toupper(query_api_scalar(value, default = ""))
  key <- gsub("[^A-Z0-9]+", "_", raw)
  key <- gsub("_+", "_", key)
  gsub("^_|_$", "", key)
}

query_synergy_mechanic_rules_default <- local({
  cached <- NULL

  function() {
    if (!is.null(cached)) {
      return(cached)
    }

    cached <<- query_synergy_build_mechanic_rules(list(
      connive = list(
        keywords = c("connive"),
        produced = c("DRAW_CARD", "DISCARD_CARD", "PUT_COUNTER"),
        consumed = character(0),
        replaced = character(0),
        prevented = character(0),
        setup = c("DRAW_DISCARD_ENGINE"),
        finisher = character(0),
        anti_tags = character(0),
        strategy_tags = c("draw_discard", "counter_scaling"),
        ability_templates = list(
          list(
            kind = "triggered",
            label = "Connive",
            trigger = list(event = "ATTACKS", scope = "self"),
            effects = list(
              list(role = "produce", event = "DRAW_CARD"),
              list(role = "produce", event = "DISCARD_CARD"),
              list(role = "produce", event = "PUT_COUNTER", condition = "if a nonland card is discarded")
            ),
            references = list(
              plans = c("draw_discard", "counter_scaling"),
              setup = c("DRAW_DISCARD_ENGINE")
            )
          )
        ),
        notes = "Connive decomposes to draw, discard, and conditional counter growth"
      ),
      cycling = list(
        keywords = c("cycling"),
        produced = c("DRAW_CARD", "DISCARD_CARD"),
        consumed = character(0),
        replaced = character(0),
        prevented = character(0),
        setup = c("DRAW_DISCARD_ENGINE"),
        finisher = character(0),
        anti_tags = character(0),
        strategy_tags = c("draw_discard"),
        ability_templates = list(
          list(
            kind = "activated",
            label = "Cycling",
            trigger = list(cost = "discard this card"),
            effects = list(
              list(role = "produce", event = "DISCARD_CARD"),
              list(role = "produce", event = "DRAW_CARD")
            ),
            references = list(
              plans = c("draw_discard"),
              setup = c("DRAW_DISCARD_ENGINE")
            )
          )
        ),
        notes = "Cycling is modeled as discard this card then draw"
      ),
      surveil = list(
        keywords = c("surveil"),
        produced = c("MILL_CARD"),
        consumed = character(0),
        replaced = character(0),
        prevented = character(0),
        setup = c("GRAVEYARD_SETUP"),
        finisher = character(0),
        anti_tags = character(0),
        strategy_tags = c("graveyard_setup"),
        ability_templates = list(
          list(
            kind = "keyword_action",
            label = "Surveil",
            trigger = list(),
            effects = list(
              list(role = "produce", event = "MILL_CARD")
            ),
            references = list(
              plans = c("graveyard_setup"),
              setup = c("GRAVEYARD_SETUP")
            )
          )
        ),
        notes = "Surveil sets up graveyard resources"
      ),
      exploit = list(
        keywords = c("exploit"),
        produced = c("SACRIFICE_PERMANENT"),
        consumed = c("ETB"),
        replaced = character(0),
        prevented = character(0),
        setup = c("SACRIFICE_ENGINE"),
        finisher = c("DEATH_PAYOFF"),
        anti_tags = character(0),
        strategy_tags = c("sacrifice", "death_triggers"),
        ability_templates = list(
          list(
            kind = "triggered",
            label = "Exploit",
            trigger = list(event = "ETB", scope = "self"),
            effects = list(
              list(role = "require", event = "ETB"),
              list(role = "produce", event = "SACRIFICE_PERMANENT")
            ),
            references = list(
              plans = c("sacrifice", "death_triggers"),
              setup = c("SACRIFICE_ENGINE"),
              finisher = c("DEATH_PAYOFF")
            )
          )
        ),
        notes = "Exploit consumes ETB body and enables death/sacrifice payoffs"
      ),
      reanimate = list(
        keywords = c("reanimate", "unearth"),
        produced = c("REANIMATE"),
        consumed = c("MILL_CARD"),
        replaced = character(0),
        prevented = character(0),
        setup = character(0),
        finisher = c("GRAVEYARD_SETUP"),
        anti_tags = character(0),
        strategy_tags = c("graveyard", "reanimator"),
        ability_templates = list(
          list(
            kind = "spell_effect",
            label = "Reanimate",
            trigger = list(),
            effects = list(
              list(role = "require", event = "MILL_CARD"),
              list(role = "produce", event = "REANIMATE")
            ),
            references = list(
              plans = c("graveyard", "reanimator"),
              finisher = c("GRAVEYARD_SETUP")
            )
          )
        ),
        notes = "Reanimation effects consume graveyard setup"
      ),
      dredge = list(
        keywords = c("dredge"),
        produced = c("MILL_CARD", "GRAVEYARD_TO_HAND"),
        consumed = character(0),
        replaced = c("DRAW_CARD"),
        prevented = character(0),
        setup = c("GRAVEYARD_SETUP"),
        finisher = character(0),
        anti_tags = c("REPLACES_DRAW"),
        strategy_tags = c("graveyard", "dredge"),
        ability_templates = list(
          list(
            kind = "replacement",
            label = "Dredge",
            trigger = list(condition = "if you would draw a card"),
            effects = list(
              list(role = "replace", event = "DRAW_CARD"),
              list(role = "produce", event = "MILL_CARD"),
              list(role = "produce", event = "GRAVEYARD_TO_HAND")
            ),
            references = list(
              plans = c("graveyard", "dredge"),
              setup = c("GRAVEYARD_SETUP"),
              anti = c("REPLACES_DRAW")
            )
          )
        ),
        notes = "Dredge replaces draw with self-mill and recursion to hand"
      )
    ))

    cached
  }
})

query_synergy_build_mechanic_rules <- function(rules = list(),
                                               base_rules = NULL,
                                               registry = query_synergy_event_registry_default()) {
  merged <- if (is.list(base_rules) && length(base_rules) > 0L) base_rules else list()
  additions <- if (is.list(rules)) rules else list()

  for (rule_id in names(additions)) {
    merged[[tolower(query_api_scalar(rule_id, default = ""))]] <- additions[[rule_id]]
  }

  out <- list()
  for (rule_id in names(merged)) {
    normalized_id <- tolower(query_api_scalar(rule_id, default = ""))
    if (!nzchar(normalized_id)) {
      next
    }
    out[[normalized_id]] <- query_synergy_normalize_mechanic_rule(normalized_id, merged[[rule_id]], registry = registry)
  }

  out
}

query_synergy_normalize_mechanic_rule <- function(rule_id, rule, registry = query_synergy_event_registry_default()) {
  value <- if (is.list(rule)) rule else list()
  list(
    keywords = unique(tolower(query_synergy_to_vector(value$keywords))),
    produced = query_synergy_canonicalize_events(value$produced, registry),
    consumed = query_synergy_canonicalize_events(value$consumed, registry),
    replaced = query_synergy_canonicalize_events(value$replaced, registry),
    prevented = query_synergy_canonicalize_events(value$prevented, registry),
    setup = unique(query_synergy_to_vector(value$setup)),
    finisher = unique(query_synergy_to_vector(value$finisher)),
    anti_tags = unique(query_synergy_to_vector(value$anti_tags)),
    strategy_tags = unique(query_synergy_to_vector(value$strategy_tags)),
    ability_templates = query_synergy_normalize_ability_templates(
      value$ability_templates,
      mechanic_id = rule_id,
      registry = registry
    ),
    notes = query_api_scalar(value$notes, default = "")
  )
}

query_synergy_expand_mechanics <- function(mechanics,
                                           registry = query_synergy_event_registry_default(),
                                           rules = query_synergy_mechanic_rules_default()) {
  normalized_mechanics <- tolower(query_synergy_to_vector(mechanics))

  produced <- character(0)
  consumed <- character(0)
  replaced <- character(0)
  prevented <- character(0)
  setup <- character(0)
  finisher <- character(0)
  anti_tags <- character(0)
  strategy_tags <- character(0)
  abilities <- list()

  for (rule_id in names(rules)) {
    rule <- rules[[rule_id]]
    if (length(intersect(normalized_mechanics, rule$keywords)) == 0L) {
      next
    }

    produced <- c(produced, query_synergy_canonicalize_events(rule$produced, registry))
    consumed <- c(consumed, query_synergy_canonicalize_events(rule$consumed, registry))
    replaced <- c(replaced, query_synergy_canonicalize_events(rule$replaced, registry))
    prevented <- c(prevented, query_synergy_canonicalize_events(rule$prevented, registry))
    setup <- c(setup, query_synergy_to_vector(rule$setup))
    finisher <- c(finisher, query_synergy_to_vector(rule$finisher))
    anti_tags <- c(anti_tags, query_synergy_to_vector(rule$anti_tags))
    strategy_tags <- c(strategy_tags, query_synergy_to_vector(rule$strategy_tags))
    abilities <- c(abilities, query_synergy_materialize_rule_abilities(rule$ability_templates, registry = registry))
  }

  list(
    produced = unique(produced),
    consumed = unique(consumed),
    replaced = unique(replaced),
    prevented = unique(prevented),
    setup = unique(setup),
    finisher = unique(finisher),
    anti_tags = unique(anti_tags),
    strategy_tags = unique(strategy_tags),
    abilities = query_synergy_unique_abilities(abilities)
  )
}

query_synergy_normalize_ability_templates <- function(templates,
                                                      mechanic_id = "",
                                                      registry = query_synergy_event_registry_default()) {
  values <- query_synergy_to_list(templates)
  if (length(values) == 0L) {
    return(list())
  }

  out <- list()
  for (index in seq_along(values)) {
    template <- values[[index]]
    if (!is.list(template)) {
      next
    }

    trigger <- if (is.list(template$trigger)) template$trigger else list()
    references <- if (is.list(template$references)) template$references else list()
    effects <- query_synergy_normalize_ability_effects(template$effects, registry = registry)
    template_id <- query_api_scalar(template$id, default = sprintf("%s_%s", mechanic_id, index))

    out[[length(out) + 1L]] <- list(
      id = sprintf("mechanic_rule:%s", query_synergy_normalize_event_id(template_id)),
      kind = query_api_scalar(template$kind, default = "mechanic"),
      label = query_api_scalar(template$label, default = mechanic_id),
      source = "mechanic_rule",
      mechanic = tolower(query_api_scalar(mechanic_id, default = "")),
      text = query_api_scalar(template$text, default = query_api_scalar(template$label, default = mechanic_id)),
      trigger = trigger,
      effects = effects,
      references = list(
        plans = unique(query_synergy_to_vector(references$plans)),
        setup = unique(query_synergy_to_vector(references$setup)),
        finisher = unique(query_synergy_to_vector(references$finisher)),
        anti = unique(query_synergy_to_vector(references$anti))
      )
    )
  }

  out
}

query_synergy_normalize_ability_effects <- function(effects, registry = query_synergy_event_registry_default()) {
  values <- query_synergy_to_list(effects)
  if (length(values) == 0L) {
    return(list())
  }

  out <- list()
  for (entry in values) {
    if (!is.list(entry)) {
      next
    }
    event_id <- query_synergy_canonicalize_events(entry$event, registry)
    if (length(event_id) == 0L) {
      next
    }
    out[[length(out) + 1L]] <- list(
      role = query_api_scalar(entry$role, default = ""),
      event = event_id[[1]],
      condition = query_api_scalar(entry$condition, default = ""),
      parent = query_api_scalar(registry$events[[event_id[[1]]]]$parent, default = "")
    )
  }

  out
}

query_synergy_materialize_rule_abilities <- function(templates, registry = query_synergy_event_registry_default()) {
  values <- query_synergy_to_list(templates)
  if (length(values) == 0L) {
    return(list())
  }

  out <- list()
  for (entry in values) {
    if (!is.list(entry)) {
      next
    }

    effects <- query_synergy_normalize_ability_effects(entry$effects, registry = registry)
    out[[length(out) + 1L]] <- list(
      id = query_api_scalar(entry$id, default = ""),
      kind = query_api_scalar(entry$kind, default = "mechanic"),
      label = query_api_scalar(entry$label, default = ""),
      source = query_api_scalar(entry$source, default = "mechanic_rule"),
      mechanic = query_api_scalar(entry$mechanic, default = ""),
      text = query_api_scalar(entry$text, default = ""),
      trigger = if (is.list(entry$trigger)) entry$trigger else list(),
      effects = effects,
      references = if (is.list(entry$references)) entry$references else list()
    )
  }

  out
}

query_synergy_parse_structured_abilities <- function(oracle_text, registry = query_synergy_event_registry_default()) {
  text <- query_api_scalar(oracle_text, default = "")
  if (!nzchar(text)) {
    return(list(
      abilities = list(),
      produced = character(0),
      consumed = character(0),
      replaced = character(0),
      prevented = character(0),
      setup = character(0),
      finisher = character(0),
      anti_tags = character(0)
    ))
  }

  fragments <- query_synergy_oracle_fragments(text)
  if (length(fragments) == 0L) {
    return(list(
      abilities = list(),
      produced = character(0),
      consumed = character(0),
      replaced = character(0),
      prevented = character(0),
      setup = character(0),
      finisher = character(0),
      anti_tags = character(0)
    ))
  }

  abilities <- list()
  produced <- character(0)
  consumed <- character(0)
  replaced <- character(0)
  prevented <- character(0)
  setup <- character(0)
  finisher <- character(0)
  anti_tags <- character(0)

  for (index in seq_along(fragments)) {
    fragment <- fragments[[index]]
    fragment_out <- query_synergy_parse_ability_fragment(fragment, index = index, registry = registry)
    if (!isTRUE(fragment_out$ok)) {
      next
    }

    abilities[[length(abilities) + 1L]] <- fragment_out$ability
    produced <- c(produced, fragment_out$produced)
    consumed <- c(consumed, fragment_out$consumed)
    replaced <- c(replaced, fragment_out$replaced)
    prevented <- c(prevented, fragment_out$prevented)
    setup <- c(setup, fragment_out$setup)
    finisher <- c(finisher, fragment_out$finisher)
    anti_tags <- c(anti_tags, fragment_out$anti_tags)
  }

  list(
    abilities = query_synergy_unique_abilities(abilities),
    produced = unique(query_synergy_canonicalize_events(produced, registry)),
    consumed = unique(query_synergy_canonicalize_events(consumed, registry)),
    replaced = unique(query_synergy_canonicalize_events(replaced, registry)),
    prevented = unique(query_synergy_canonicalize_events(prevented, registry)),
    setup = unique(setup),
    finisher = unique(finisher),
    anti_tags = unique(anti_tags)
  )
}

query_synergy_oracle_fragments <- function(oracle_text) {
  raw <- query_api_scalar(oracle_text, default = "")
  if (!nzchar(raw)) {
    return(character(0))
  }

  split <- unlist(strsplit(raw, "(\\r?\\n)+|(?<=\\.)\\s+", perl = TRUE), use.names = FALSE)
  split <- trimws(split)
  split <- split[nzchar(split)]
  unique(split)
}

query_synergy_parse_ability_fragment <- function(fragment, index = 1L, registry = query_synergy_event_registry_default()) {
  text <- query_api_scalar(fragment, default = "")
  lower <- tolower(text)
  if (!nzchar(lower)) {
    return(list(ok = FALSE))
  }

  kind <- query_synergy_classify_ability_fragment(lower)
  events <- query_synergy_extract_events_from_fragment(lower, registry = registry)
  effects <- query_synergy_fragment_effect_records(events, registry = registry)
  trigger <- query_synergy_fragment_trigger(kind, lower, events)

  has_static_keyword <- grepl("\\b(flying|trample|vigilance|haste|deathtouch|lifelink|ward|hexproof|menace|first strike|double strike|reach)\\b", lower, perl = TRUE)
  has_signal <- length(effects) > 0L ||
    length(events$anti_tags) > 0L ||
    kind %in% c("replacement", "triggered", "activated") ||
    has_static_keyword

  if (!isTRUE(has_signal)) {
    return(list(ok = FALSE))
  }

  ability <- list(
    id = sprintf("oracle:%03d:%s", as.integer(index), query_synergy_normalize_event_id(substr(lower, 1L, min(40L, nchar(lower))))),
    kind = kind,
    label = query_synergy_fragment_label(kind, lower),
    source = "oracle_parse",
    mechanic = "",
    text = text,
    trigger = trigger,
    effects = effects,
    references = list(
      plans = unique(c(events$setup, events$finisher)),
      setup = unique(events$setup),
      finisher = unique(events$finisher),
      anti = unique(events$anti_tags)
    )
  )

  list(
    ok = TRUE,
    ability = ability,
    produced = events$produced,
    consumed = events$consumed,
    replaced = events$replaced,
    prevented = events$prevented,
    setup = events$setup,
    finisher = events$finisher,
    anti_tags = events$anti_tags
  )
}

query_synergy_classify_ability_fragment <- function(text) {
  value <- tolower(query_api_scalar(text, default = ""))
  if (!nzchar(value)) {
    return("static")
  }
  if (grepl("\\bif\\b.*\\bwould\\b.*\\binstead\\b", value, perl = TRUE) || grepl("\\binstead of\\b", value, perl = TRUE)) {
    return("replacement")
  }
  if (grepl("^whenever\\b|^when\\b|^at the beginning\\b|^at the end\\b", value, perl = TRUE)) {
    return("triggered")
  }
  if (grepl("^[^.:]+:\\s", value, perl = TRUE)) {
    return("activated")
  }
  if (grepl("\\b(flying|trample|vigilance|haste|deathtouch|lifelink|ward|hexproof|menace|first strike|double strike|reach)\\b", value, perl = TRUE)) {
    return("static")
  }
  "spell_effect"
}

query_synergy_fragment_label <- function(kind, text) {
  title <- switch(
    query_api_scalar(kind, default = "static"),
    triggered = "Triggered ability",
    replacement = "Replacement ability",
    activated = "Activated ability",
    static = "Static ability",
    "Spell effect"
  )
  if (!nzchar(query_api_scalar(text, default = ""))) {
    return(title)
  }
  title
}

query_synergy_fragment_trigger <- function(kind, text, events) {
  value <- query_api_scalar(text, default = "")
  lower <- tolower(value)
  role_events <- unique(c(events$consumed, events$replaced, events$prevented))

  if (identical(kind, "triggered")) {
    return(list(
      text = value,
      events = role_events
    ))
  }
  if (identical(kind, "replacement")) {
    return(list(
      condition = value,
      events = role_events
    ))
  }
  if (identical(kind, "activated")) {
    parts <- strsplit(value, ":", fixed = TRUE)[[1]]
    return(list(
      cost = trimws(parts[[1]]),
      events = role_events
    ))
  }

  list(events = role_events)
}

query_synergy_fragment_effect_records <- function(events, registry = query_synergy_event_registry_default()) {
  out <- list()
  mapping <- list(
    produce = events$produced,
    reward = events$consumed,
    replace = events$replaced,
    prevent = events$prevented
  )

  for (role in names(mapping)) {
    event_ids <- unique(query_synergy_canonicalize_events(mapping[[role]], registry))
    if (length(event_ids) == 0L) {
      next
    }
    for (event_id in event_ids) {
      out[[length(out) + 1L]] <- list(
        role = role,
        event = event_id,
        parent = query_api_scalar(registry$events[[event_id]]$parent, default = "")
      )
    }
  }

  out
}

query_synergy_extract_events_from_fragment <- function(text, registry = query_synergy_event_registry_default()) {
  lower <- tolower(query_api_scalar(text, default = ""))
  if (!nzchar(lower)) {
    return(list(
      produced = character(0),
      consumed = character(0),
      replaced = character(0),
      prevented = character(0),
      setup = character(0),
      finisher = character(0),
      anti_tags = character(0)
    ))
  }

  produced <- character(0)
  consumed <- character(0)
  replaced <- character(0)
  prevented <- character(0)
  setup <- character(0)
  finisher <- character(0)
  anti_tags <- character(0)

  produced_patterns <- list(
    DRAW_CARD = c("draw\\s+(a|an|x|one|two|three|[0-9]+)\\s+card", "conniv"),
    DISCARD_CARD = c("discard\\s+(a|an|x|one|two|three|[0-9]+)\\s+card", "discards\\s+(a|an|x|one|two|three|[0-9]+)\\s+card", "conniv"),
    GAIN_LIFE = c("gain\\s+[0-9x]+\\s+life"),
    LOSE_LIFE = c("lose\\s+[0-9x]+\\s+life"),
    CREATE_TOKEN = c("create\\s+.*token"),
    ADD_MANA = c("add\\s*\\{"),
    PUT_COUNTER = c("put\\s+.*counter"),
    SACRIFICE_PERMANENT = c("sacrifice\\s+"),
    ETB = c("enters? the battlefield"),
    DIES = c("dies", "is put into (a|your|their) graveyard from the battlefield"),
    ATTACKS = c("whenever .* attacks", "when .* attacks", "target attacking creature"),
    CAST_SPELL = c("cast\\s+(a|an|this|that)?\\s*spell"),
    GRAVEYARD_TO_HAND = c("from your graveyard to your hand"),
    MILL_CARD = c("mill", "put the top .* of .* library into .* graveyard"),
    REANIMATE = c("from .* graveyard to the battlefield"),
    EXILE_CARD = c("exile .* card"),
    TARGETS_CREATURE = c("target .* creature")
  )

  consumed_patterns <- list(
    SELF_DRAW_CARD = c("whenever you draw", "if you draw"),
    OPPONENT_DRAW_CARD = c("whenever an opponent draws", "if an opponent draws"),
    DISCARD_CARD = c("whenever .* discards"),
    GAIN_LIFE = c("whenever you gain life", "if you gain life"),
    DIES = c("whenever .* dies", "whenever a creature dies"),
    CAST_SPELL = c("whenever you cast"),
    NONCREATURE_SPELL_CAST = c("whenever you cast a noncreature spell"),
    COMBAT_DAMAGE_TO_PLAYER = c("whenever .* deals combat damage to a player"),
    ATTACKS = c("whenever you attack", "when you attack")
  )

  for (event_name in names(produced_patterns)) {
    for (pattern in produced_patterns[[event_name]]) {
      if (grepl(pattern, lower, perl = TRUE)) {
        produced <- c(produced, event_name)
        break
      }
    }
  }

  for (event_name in names(consumed_patterns)) {
    for (pattern in consumed_patterns[[event_name]]) {
      if (grepl(pattern, lower, perl = TRUE)) {
        consumed <- c(consumed, event_name)
        break
      }
    }
  }

  event_aliases <- query_synergy_event_text_aliases()
  for (event_name in names(event_aliases)) {
    aliases <- query_synergy_to_vector(event_aliases[[event_name]])
    if (length(aliases) == 0L) {
      next
    }

    has_replacement <- FALSE
    has_prevention <- FALSE
    for (alias in aliases) {
      alias_group <- sprintf("(?:%s)", alias)
      replace_would_pattern <- sprintf("if\\s+.*would\\s+%s[^.]*instead", alias_group)
      replace_instead_pattern <- sprintf("instead of\\s+%s", alias_group)
      prevent_cant_pattern <- sprintf("(?:can't|cannot)\\s+%s", alias_group)
      prevent_wont_pattern <- sprintf("%s\\s+(?:can't|cannot)", alias_group)

      if (grepl(replace_would_pattern, lower, perl = TRUE) || grepl(replace_instead_pattern, lower, perl = TRUE)) {
        has_replacement <- TRUE
      }
      if (grepl(prevent_cant_pattern, lower, perl = TRUE) || grepl(prevent_wont_pattern, lower, perl = TRUE)) {
        has_prevention <- TRUE
      }
    }

    if (has_replacement) {
      replaced <- c(replaced, event_name)
    }
    if (has_prevention) {
      prevented <- c(prevented, event_name)
    }
  }

  if (grepl("skip your draw step", lower, perl = TRUE)) {
    replaced <- c(replaced, "DRAW_CARD")
  }

  conflicting_events <- query_synergy_expand_event_family(c(replaced, prevented), registry)
  if (length(conflicting_events) > 0L) {
    produced <- setdiff(produced, conflicting_events)
    consumed <- setdiff(consumed, conflicting_events)
    anti_tags <- c(
      anti_tags,
      "EVENT_REPLACEMENT_OR_PREVENTION",
      sprintf("REPLACES_OR_PREVENTS_%s", conflicting_events)
    )
  }

  if (grepl("surveil|mill|put the top .* library into .* graveyard", lower, perl = TRUE)) {
    setup <- c(setup, "GRAVEYARD_SETUP")
  }
  if (grepl("from .* graveyard to the battlefield|reanimate|unearth", lower, perl = TRUE)) {
    finisher <- c(finisher, "GRAVEYARD_SETUP")
  }
  if (grepl("whenever you draw|draw\\s+.*card|conniv", lower, perl = TRUE)) {
    setup <- c(setup, "DRAW_DISCARD_ENGINE")
  }
  if (grepl("no maximum hand size|for each card in your hand", lower, perl = TRUE)) {
    anti_tags <- c(anti_tags, "HAND_SIZE_PAYOFF")
  }
  if (grepl("discard your hand|each player.*discards|that player discards", lower, perl = TRUE)) {
    anti_tags <- c(anti_tags, "HAND_DISCARD_PRESSURE")
  }
  if (grepl("exile all graveyards|cards in graveyards can't", lower, perl = TRUE)) {
    anti_tags <- c(anti_tags, "GRAVEYARD_HATE")
  }
  if (grepl("from your graveyard", lower, perl = TRUE)) {
    anti_tags <- c(anti_tags, "GRAVEYARD_DEPENDENT")
  }
  if ("SELF_DRAW_CARD" %in% consumed || "OPPONENT_DRAW_CARD" %in% consumed) {
    produced <- setdiff(produced, "DRAW_CARD")
    consumed <- c(consumed, "DRAW_CARD")
  }

  list(
    produced = unique(query_synergy_canonicalize_events(produced, registry)),
    consumed = unique(query_synergy_canonicalize_events(consumed, registry)),
    replaced = unique(query_synergy_canonicalize_events(replaced, registry)),
    prevented = unique(query_synergy_canonicalize_events(prevented, registry)),
    setup = unique(setup),
    finisher = unique(finisher),
    anti_tags = unique(anti_tags)
  )
}
query_synergy_extract_events_from_text <- function(oracle_text, registry = query_synergy_event_registry_default()) {
  query_synergy_parse_structured_abilities(oracle_text, registry = registry)
}

query_synergy_strategy_tags_from_events <- function(produced, consumed, setup_events, finisher_events) {
  tags <- character(0)

  if (length(intersect(produced, c("DRAW_CARD", "DISCARD_CARD", "SELF_DRAW_CARD"))) > 0L ||
      length(intersect(consumed, c("DRAW_CARD", "SELF_DRAW_CARD", "DISCARD_CARD"))) > 0L) {
    tags <- c(tags, "draw_discard")
  }

  if (length(intersect(produced, c("MILL_CARD", "REANIMATE", "GRAVEYARD_TO_HAND"))) > 0L ||
      length(intersect(consumed, c("MILL_CARD", "REANIMATE", "GRAVEYARD_TO_HAND"))) > 0L ||
      length(intersect(setup_events, c("GRAVEYARD_SETUP"))) > 0L ||
      length(intersect(finisher_events, c("GRAVEYARD_SETUP"))) > 0L) {
    tags <- c(tags, "graveyard")
  }

  if (length(intersect(produced, c("CREATE_TOKEN", "PUT_COUNTER", "ETB", "DIES", "SACRIFICE_PERMANENT"))) > 0L) {
    tags <- c(tags, "board_engine")
  }

  unique(tags)
}

query_synergy_event_text_aliases <- function() {
  list(
    DRAW_CARD = c("draw\\s+(?:a|an|x|one|two|three|[0-9]+)\\s+card", "draw\\s+cards?"),
    DISCARD_CARD = c("discard\\s+(?:a|an|x|one|two|three|[0-9]+)\\s+card", "discard\\s+cards?"),
    GAIN_LIFE = c("gain\\s+(?:x|[0-9]+)\\s+life"),
    LOSE_LIFE = c("lose\\s+(?:x|[0-9]+)\\s+life"),
    CREATE_TOKEN = c("create\\s+.*token"),
    SACRIFICE_PERMANENT = c("sacrifice\\s+(?:a|an|one|two|three|[0-9]+)?\\s*permanent", "sacrifice\\s+a\\s+creature")
  )
}

query_synergy_expand_event_family <- function(events, registry = query_synergy_event_registry_default()) {
  seeds <- unique(query_synergy_canonicalize_events(events, registry))
  if (length(seeds) == 0L) {
    return(character(0))
  }

  all_events <- names(registry$events)
  family <- seeds
  changed <- TRUE
  while (isTRUE(changed)) {
    changed <- FALSE
    for (event_id in all_events) {
      parent <- query_api_scalar(registry$events[[event_id]]$parent, default = "")
      if (nzchar(parent) && parent %in% family && !event_id %in% family) {
        family <- c(family, event_id)
        changed <- TRUE
      }
    }
  }

  unique(family)
}

query_synergy_canonicalize_events <- function(events, registry = query_synergy_event_registry_default()) {
  values <- query_synergy_to_vector(events)
  if (length(values) == 0L) {
    return(character(0))
  }

  out <- character(0)
  alias_map <- registry$alias_to_id

  for (event_name in values) {
    key <- query_synergy_normalize_event_id(event_name)
    if (!nzchar(key)) {
      next
    }

    if (!is.null(alias_map[[key]])) {
      out <- c(out, alias_map[[key]])
      next
    }

    out <- c(out, key)
  }

  unique(out)
}

query_synergy_detect_mechanics_from_text <- function(oracle_text) {
  text <- tolower(query_api_scalar(oracle_text, default = ""))
  if (!nzchar(text)) {
    return(character(0))
  }

  patterns <- list(
    connive = "\\bconniv(e|es|ed|ing)\\b",
    cycling = "\\bcycl(ing|e|ed)?\\b",
    surveil = "\\bsurveil\\b",
    exploit = "\\bexploit\\b",
    reanimate = "\\breanimate\\b",
    unearth = "\\bunearth\\b",
    dredge = "\\bdredge\\b",
    mill = "\\bmill\\b",
    investigate = "\\binvestigate\\b",
    proliferate = "\\bproliferate\\b",
    flashback = "\\bflashback\\b",
    escape = "\\bescape\\b"
  )

  hits <- names(Filter(function(pattern) {
    grepl(pattern, text, perl = TRUE)
  }, patterns))

  unique(unlist(hits, use.names = FALSE))
}

query_synergy_parse_payload <- function(req = NULL) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    return(list(ok = FALSE, error = "jsonlite package is required"))
  }

  if (is.null(req)) {
    return(list(ok = FALSE, error = "missing request"))
  }

  payload_raw <- ""
  if (!is.null(req$postBody)) {
    payload_raw <- as.character(req$postBody)
  } else if (!is.null(req$body)) {
    payload_raw <- tryCatch(
      jsonlite::toJSON(req$body, auto_unbox = TRUE, null = "null"),
      error = function(e) ""
    )
  }

  payload_raw <- trimws(payload_raw)
  if (!nzchar(payload_raw)) {
    return(list(ok = FALSE, error = "missing JSON payload"))
  }

  payload <- tryCatch(
    jsonlite::fromJSON(payload_raw, simplifyVector = FALSE),
    error = function(e) NULL
  )

  if (is.null(payload) || !is.list(payload)) {
    return(list(ok = FALSE, error = "invalid JSON payload"))
  }

  list(ok = TRUE, data = payload)
}
query_synergy_get_catalog <- function(force_refresh = FALSE, cache_hours = 24L, cache_dir = "") {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    return(list(ok = FALSE, error = "jsonlite package is required"))
  }

  now <- Sys.time()
  max_age <- as.numeric(cache_hours) * 3600
  if (!is.finite(max_age) || max_age <= 0) {
    max_age <- 24 * 3600
  }

  if (!isTRUE(force_refresh) && is.list(query_synergy_cache_env$catalog) && length(query_synergy_cache_env$catalog) > 0L) {
    age <- as.numeric(difftime(now, query_synergy_cache_env$catalog_loaded_at, units = "secs"))
    if (is.finite(age) && age <= max_age) {
      return(list(ok = TRUE, source = query_synergy_cache_env$catalog_source, cards = query_synergy_cache_env$catalog))
    }
  }

  paths <- query_synergy_cache_paths(cache_dir)
  if (!isTRUE(force_refresh) && file.exists(paths$rds_file)) {
    info <- file.info(paths$rds_file)
    age <- as.numeric(difftime(now, info$mtime, units = "secs"))
    if (is.finite(age) && age <= max_age) {
      cards <- tryCatch(readRDS(paths$rds_file), error = function(e) NULL)
      if (is.list(cards) && length(cards) > 0L) {
        query_synergy_cache_env$catalog <- cards
        query_synergy_cache_env$catalog_loaded_at <- now
        query_synergy_cache_env$catalog_source <- "scryfall_oracle_cards"
        return(list(ok = TRUE, source = "scryfall_oracle_cards", cards = cards))
      }
    }
  }

  bulk_meta_raw <- tryCatch(
    paste(readLines("https://api.scryfall.com/bulk-data", warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
    error = function(e) ""
  )
  if (!nzchar(bulk_meta_raw)) {
    return(list(ok = FALSE, error = "Scryfall bulk metadata unavailable"))
  }

  bulk_meta <- tryCatch(jsonlite::fromJSON(bulk_meta_raw, simplifyVector = FALSE), error = function(e) NULL)
  if (!is.list(bulk_meta) || !is.list(bulk_meta$data)) {
    return(list(ok = FALSE, error = "Invalid Scryfall bulk metadata"))
  }

  oracle_entry <- NULL
  for (entry in bulk_meta$data) {
    if (is.list(entry) && identical(entry$type, "oracle_cards") && nzchar(query_api_scalar(entry$download_uri, default = ""))) {
      oracle_entry <- entry
      break
    }
  }

  if (is.null(oracle_entry)) {
    return(list(ok = FALSE, error = "oracle_cards dataset not found in Scryfall bulk metadata"))
  }

  download_uri <- query_api_scalar(oracle_entry$download_uri, default = "")
  if (!nzchar(download_uri)) {
    return(list(ok = FALSE, error = "missing oracle_cards download uri"))
  }

  tmp_file <- paste0(paths$json_file, ".download")
  unlink(tmp_file)

  dl_ok <- tryCatch({
    utils::download.file(download_uri, destfile = tmp_file, mode = "wb", quiet = TRUE)
    TRUE
  }, error = function(e) FALSE)

  if (!isTRUE(dl_ok) || !file.exists(tmp_file)) {
    return(list(ok = FALSE, error = "failed to download Scryfall oracle_cards dataset"))
  }

  ok_rename <- tryCatch({
    if (file.exists(paths$json_file)) {
      unlink(paths$json_file)
    }
    file.rename(tmp_file, paths$json_file)
  }, error = function(e) FALSE)

  if (!isTRUE(ok_rename) || !file.exists(paths$json_file)) {
    return(list(ok = FALSE, error = "unable to persist downloaded oracle_cards dataset"))
  }

  raw_cards <- tryCatch(jsonlite::fromJSON(paths$json_file, simplifyVector = FALSE), error = function(e) NULL)
  if (!is.list(raw_cards) || length(raw_cards) == 0L) {
    return(list(ok = FALSE, error = "invalid oracle_cards dataset"))
  }

  cards <- lapply(raw_cards, query_synergy_trim_card)
  cards <- Filter(function(card) nzchar(query_synergy_card_id(card)) && nzchar(query_api_scalar(card$name, default = "")), cards)

  if (length(cards) == 0L) {
    return(list(ok = FALSE, error = "oracle_cards dataset is empty after normalization"))
  }

  save_ok <- tryCatch({
    saveRDS(cards, paths$rds_file)
    TRUE
  }, error = function(e) FALSE)
  if (!isTRUE(save_ok)) {
    return(list(ok = FALSE, error = "failed to cache normalized Scryfall cards"))
  }

  query_synergy_cache_env$catalog <- cards
  query_synergy_cache_env$catalog_loaded_at <- now
  query_synergy_cache_env$catalog_source <- "scryfall_oracle_cards"

  list(ok = TRUE, source = "scryfall_oracle_cards", cards = cards)
}

query_synergy_cache_paths <- function(cache_dir = "") {
  base_dir <- trimws(as.character(cache_dir))
  if (!nzchar(base_dir)) {
    base_dir <- file.path(tempdir(), "mtgcodex_synergy_cache")
  }

  if (!dir.exists(base_dir)) {
    dir.create(base_dir, recursive = TRUE, showWarnings = FALSE)
  }

  list(
    base_dir = base_dir,
    json_file = file.path(base_dir, "scryfall_oracle_cards.json"),
    rds_file = file.path(base_dir, "scryfall_oracle_cards.rds")
  )
}

query_synergy_trim_card <- function(card) {
  list(
    id = query_synergy_card_id(card),
    name = query_api_scalar(card$name, default = ""),
    oracle_text = query_api_scalar(card$oracle_text, default = query_api_scalar(card$printed_text, default = "")),
    type_line = query_api_scalar(card$type_line, default = ""),
    mana_cost = query_api_scalar(card$mana_cost, default = ""),
    cmc = suppressWarnings(as.numeric(card$cmc)),
    colors = query_synergy_card_colors(card),
    color_identity = query_synergy_card_color_identity(card),
    keywords = query_synergy_to_vector(card$keywords),
    legalities = query_synergy_card_legalities(card)
  )
}

query_synergy_normalize_card_cached <- function(card, registry = query_synergy_event_registry_default()) {
  card_id <- query_synergy_card_id(card)
  key <- if (nzchar(card_id)) {
    card_id
  } else {
    paste0("name::", tolower(query_api_scalar(card$name, default = "")))
  }

  if (nzchar(key) && exists(key, envir = query_synergy_cache_env$normalized_by_id, inherits = FALSE)) {
    return(get(key, envir = query_synergy_cache_env$normalized_by_id, inherits = FALSE))
  }

  normalized <- query_synergy_normalize_card(card, registry = registry)
  if (nzchar(key)) {
    assign(key, normalized, envir = query_synergy_cache_env$normalized_by_id)
  }
  normalized
}

query_synergy_find_card_by_id_or_name <- function(catalog, lookup) {
  if (!is.list(catalog) || length(catalog) == 0L) {
    return(NULL)
  }

  raw <- trimws(as.character(lookup))
  if (!nzchar(raw)) {
    return(NULL)
  }

  needle <- tolower(raw)

  exact_id <- Filter(function(card) {
    identical(tolower(query_synergy_card_id(card)), needle)
  }, catalog)
  if (length(exact_id) > 0L) {
    return(exact_id[[1]])
  }

  exact_name <- Filter(function(card) {
    identical(tolower(query_api_scalar(card$name, default = "")), needle)
  }, catalog)
  if (length(exact_name) > 0L) {
    return(exact_name[[1]])
  }

  fuzzy_name <- Filter(function(card) {
    grepl(needle, tolower(query_api_scalar(card$name, default = "")), fixed = TRUE)
  }, catalog)
  if (length(fuzzy_name) > 0L) {
    return(fuzzy_name[[1]])
  }

  NULL
}
query_synergy_card_id <- function(card) {
  id <- query_api_scalar(card$id, default = "")
  if (nzchar(id)) {
    return(id)
  }

  oracle_id <- query_api_scalar(card$oracle_id, default = "")
  if (nzchar(oracle_id)) {
    return(oracle_id)
  }

  name <- tolower(query_api_scalar(card$name, default = ""))
  if (!nzchar(name)) {
    return("")
  }

  gsub("[^a-z0-9]+", "_", name)
}

query_synergy_card_colors <- function(card) {
  direct <- query_synergy_to_vector(card$colors)
  direct <- toupper(direct)
  direct <- direct[direct %in% c("W", "U", "B", "R", "G")]
  unique(direct)
}

query_synergy_card_color_identity <- function(card) {
  direct <- query_synergy_to_vector(card$color_identity)
  if (length(direct) == 0L) {
    direct <- query_synergy_card_colors(card)
  }
  direct <- toupper(direct)
  direct <- direct[direct %in% c("W", "U", "B", "R", "G", "C")]
  unique(direct)
}

query_synergy_card_legalities <- function(card) {
  legalities <- card$legalities
  if (!is.list(legalities) || length(legalities) == 0L) {
    return(list())
  }

  out <- list()
  keys <- names(legalities)
  if (length(keys) == 0L) {
    return(out)
  }

  for (key in keys) {
    out[[tolower(key)]] <- tolower(query_api_scalar(legalities[[key]], default = ""))
  }

  out
}

query_synergy_parse_color_identity <- function(value) {
  if (is.null(value)) {
    return(character(0))
  }

  out <- query_synergy_to_vector(value)
  out <- toupper(out)
  out <- out[out %in% c("W", "U", "B", "R", "G", "C")]
  unique(out)
}

query_synergy_to_vector <- function(value) {
  if (is.null(value)) {
    return(character(0))
  }

  flattened <- unlist(value, use.names = FALSE)
  if (length(flattened) == 0L) {
    return(character(0))
  }

  out <- trimws(as.character(flattened))
  out <- out[!is.na(out) & nzchar(out)]
  unique(out)
}

query_synergy_as_int <- function(value, default = 0L, min_value = 0L, max_value = 100L) {
  parsed <- suppressWarnings(as.integer(value))
  if (!is.finite(parsed) || is.na(parsed)) {
    parsed <- as.integer(default)
  }
  parsed <- max(as.integer(min_value), parsed)
  parsed <- min(as.integer(max_value), parsed)
  as.integer(parsed)
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
