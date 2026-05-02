# Card normalization, role/cadence inference, mechanic expansion, ability parsing.
# Extracted from R/query_synergy_engine.R as part of the modular refactor.
# Depends on: synergy_utils, synergy_event_registry.

query_synergy_normalize_card <- function(card,
                                         registry = query_synergy_event_registry_default(),
                                         mechanic_rules = query_synergy_mechanic_rules_default(),
                                         ability_parse_rules = query_synergy_ability_parse_rules_default(registry = registry)) {
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
  extracted <- query_synergy_extract_events_from_text(
    oracle_text,
    registry = registry,
    parse_rules = ability_parse_rules
  )

  produced <- unique(c(expanded$produced, extracted$produced))
  consumed <- unique(c(expanded$consumed, extracted$consumed))
  replaced <- unique(c(expanded$replaced, extracted$replaced))
  prevented <- unique(c(expanded$prevented, extracted$prevented))
  setup_events <- unique(c(expanded$setup, extracted$setup))
  finisher_events <- unique(c(expanded$finisher, extracted$finisher))
  reward_events <- unique(extracted$consumed)
  required_events <- unique(expanded$consumed)

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
  cadence <- query_synergy_infer_card_cadence(
    abilities = abilities,
    type_line = type_line,
    oracle_text = oracle_text,
    mechanics = mechanics,
    produced = produced,
    consumed = consumed
  )
  plans <- list(
    tags = character(0),
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
    finisher_events = finisher_events,
    target_roles = target_roles,
    cadence = cadence,
    produced_events = produced,
    consumed_events = consumed,
    abilities = abilities
  )
  strategy_tags <- unique(c(
    expanded$strategy_tags,
    query_synergy_strategy_tags_from_events(
      produced,
      consumed,
      setup_events,
      finisher_events,
      roles = roles,
      cadence = cadence,
      target_roles = target_roles,
      oracle_text = oracle_text
    )
  ))
  plans$tags <- strategy_tags

  list(
    id = card_id,
    name = card_name,
    model_version = "normalized_card_v2",
    scryfall_id = query_api_scalar(card$scryfall_id, default = ""),
    set_code = query_api_scalar(card$set_code %||% card$set, default = ""),
    set_name = query_api_scalar(card$set_name, default = ""),
    mana_cost = query_api_scalar(card$mana_cost, default = ""),
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
    cadence = cadence,
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
    cadence = list(
      class = "one_shot",
      repeatable = FALSE,
      scalable = FALSE,
      strength = 0,
      contexts = character(0),
      sources = character(0)
    ),
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
                                           finisher_events,
                                           target_roles = character(0),
                                           cadence = list(),
                                           produced_events = character(0),
                                           consumed_events = character(0),
                                           abilities = list()) {
  roles <- character(0)
  cadence_repeatable <- isTRUE(cadence$repeatable)
  cadence_scalable <- isTRUE(cadence$scalable)

  role_keys <- function(records) {
    values <- query_synergy_to_list(records)
    if (length(values) == 0L) {
      return(character(0))
    }

    unique(unlist(lapply(values, function(entry) {
      if (!is.list(entry)) {
        return(character(0))
      }
      c(
        query_api_scalar(entry$event, default = ""),
        query_api_scalar(entry$parent, default = "")
      )
    }), use.names = FALSE))
  }

  produced_keys <- role_keys(produces)
  input_keys <- unique(c(role_keys(rewards), role_keys(requires)))
  setup_values <- unique(query_synergy_to_vector(setup_events))
  finisher_values <- unique(query_synergy_to_vector(finisher_events))
  produced_values <- unique(query_synergy_to_vector(produced_events))
  consumed_values <- unique(query_synergy_to_vector(consumed_events))
  amplifier_signals <- query_synergy_detect_amplifier_signals(
    abilities = abilities,
    produced_events = produced_events,
    consumed_events = consumed_events,
    cadence = cadence
  )

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
  has_setup_support <- length(setup_values) > 0L &&
    (
      length(produced_values) > 0L ||
        length(produces) > 0L ||
        length(moves) > 0L
    )
  if (has_setup_support) {
    roles <- c(roles, "setup")
  }
  if (length(finisher_values) > 0L) {
    roles <- c(roles, "finisher")
  }
  if (length(query_synergy_to_vector(target_roles)) > 0L) {
    roles <- c(roles, "target")
  }

  if (length(produced_keys) > 0L && length(input_keys) > 0L && length(setdiff(produced_keys, input_keys)) > 0L) {
    roles <- c(roles, "converter")
  }

  move_zone_changes <- vapply(query_synergy_to_list(moves), function(entry) {
    if (!is.list(entry)) {
      return(FALSE)
    }
    from_zone <- query_api_scalar(entry$from, default = "")
    to_zone <- query_api_scalar(entry$to, default = "")
    pseudo_zones <- c("", "outside_game", "anywhere", "nowhere")
    nzchar(from_zone) && nzchar(to_zone) &&
      !identical(from_zone, to_zone) &&
      !(from_zone %in% pseudo_zones) &&
      !(to_zone %in% pseudo_zones)
  }, logical(1))
  if (any(move_zone_changes)) {
    roles <- c(roles, "converter")
  }

  engine_support <- cadence_repeatable ||
    ("converter" %in% roles) ||
    (length(requires) > 0L && length(produced_keys) > 0L) ||
    (length(rewards) > 0L && length(intersect(produced_keys, input_keys)) > 0L)
  if (length(produces) > 0L && engine_support) {
    roles <- c(roles, "engine")
  }
  if (("converter" %in% roles || "engine" %in% roles) &&
      length(input_keys) > 0L &&
      (length(produced_keys) > 0L || cadence_repeatable)) {
    roles <- c(roles, "bridge")
  }
  if (amplifier_signals$detected || cadence_scalable) {
    roles <- c(roles, "amplifier")
  }

  unique(roles)
}

query_synergy_detect_amplifier_signals <- function(abilities = list(),
                                                   produced_events = character(0),
                                                   consumed_events = character(0),
                                                   cadence = list()) {
  texts <- unlist(lapply(query_synergy_to_list(abilities), function(ability) {
    if (!is.list(ability)) {
      return(character(0))
    }
    query_api_scalar(ability$text, default = "")
  }), use.names = FALSE)
  source <- tolower(paste(c(texts, query_synergy_to_vector(produced_events), query_synergy_to_vector(consumed_events)), collapse = " "))
  patterns <- c(
    "\\badditional\\b",
    "\\bdouble\\b",
    "\\btwice\\b",
    "\\bcopy\\b",
    "\\bproliferate\\b",
    "\\bpopulate\\b",
    "for each",
    "one or more"
  )
  detected <- any(vapply(patterns, function(pattern) grepl(pattern, source, perl = TRUE), logical(1))) || isTRUE(cadence$scalable)
  list(
    detected = detected,
    source = source
  )
}

query_synergy_infer_card_cadence <- function(abilities = list(),
                                             type_line = "",
                                             oracle_text = "",
                                             mechanics = character(0),
                                             produced = character(0),
                                             consumed = character(0)) {
  ability_values <- query_synergy_to_list(abilities)
  lower_text <- tolower(query_api_scalar(oracle_text, default = ""))
  type_text <- tolower(query_api_scalar(type_line, default = ""))
  permanent <- grepl("\\bartifact\\b|\\bcreature\\b|\\benchantment\\b|\\bland\\b|\\bplaneswalker\\b", type_text, perl = TRUE)

  repeatable_signals <- 0
  scalable_signals <- 0
  contexts <- character(0)
  sources <- character(0)

  for (ability in ability_values) {
    if (!is.list(ability)) {
      next
    }

    kind <- query_api_scalar(ability$kind, default = "")
    sources <- c(sources, query_api_scalar(ability$source, default = ""))
    if (kind %in% c("triggered", "activated", "replacement", "static", "mechanic", "keyword_action")) {
      repeatable_signals <- repeatable_signals + 1L
    }

    ability_text <- tolower(query_api_scalar(ability$text, default = ""))
    if (grepl("\\bx\\b|for each|one or more|additional|double|twice", ability_text, perl = TRUE)) {
      scalable_signals <- scalable_signals + 1L
    }

    trigger_events <- unique(c(
      query_synergy_to_vector(ability$trigger$event),
      query_synergy_to_vector(ability$trigger$events)
    ))
    if (length(trigger_events) > 0L) {
      if (length(intersect(trigger_events, c("ATTACKS", "COMBAT_DAMAGE_TO_PLAYER"))) > 0L) {
        contexts <- c(contexts, "combat")
      }
      if (length(intersect(trigger_events, c("CAST_SPELL", "NONCREATURE_SPELL_CAST"))) > 0L) {
        contexts <- c(contexts, "spell")
      }
      if (length(intersect(trigger_events, c("DRAW_CARD", "SELF_DRAW_CARD", "OPPONENT_DRAW_CARD", "DISCARD_CARD"))) > 0L) {
        contexts <- c(contexts, "card_flow")
      }
      if (length(intersect(trigger_events, c("DIES", "SACRIFICE_PERMANENT"))) > 0L) {
        contexts <- c(contexts, "death")
      }
      if (length(intersect(trigger_events, c("ETB"))) > 0L) {
        contexts <- c(contexts, "etb")
      }
    }

    if (nzchar(query_api_scalar(ability$trigger$cost, default = ""))) {
      contexts <- c(contexts, "activated")
    }
  }

  if (grepl("whenever|at the beginning|each combat|each upkeep|during each", lower_text, perl = TRUE)) {
    repeatable_signals <- repeatable_signals + 1L
  }
  if (grepl("\\bx\\b|for each|one or more|additional|double|twice", lower_text, perl = TRUE)) {
    scalable_signals <- scalable_signals + 1L
  }
  if (grepl("attack|attacking|combat damage", lower_text, perl = TRUE)) {
    contexts <- c(contexts, "combat")
  }
  if (grepl("upkeep|end step", lower_text, perl = TRUE)) {
    contexts <- c(contexts, "turn_cycle")
  }
  if (length(intersect(query_synergy_to_vector(mechanics), c("connive", "cycling", "flashback", "escape", "blitz", "cascade", "discover", "populate", "investigate", "lifelink", "foretell"))) > 0L) {
    repeatable_signals <- repeatable_signals + 1L
  }
  if (length(intersect(query_synergy_to_vector(mechanics), c("connive", "cascade", "discover", "populate", "proliferate", "blitz"))) > 0L) {
    scalable_signals <- scalable_signals + 1L
  }

  consumed_events <- unique(query_synergy_to_vector(consumed))
  repeatable <- (permanent && repeatable_signals > 0L) || repeatable_signals >= 2L
  scalable <- scalable_signals > 0L
  contexts <- unique(contexts)
  sources <- unique(query_synergy_to_vector(sources))
  constrained_contexts <- intersect(contexts, c("combat", "spell", "death", "etb", "activated"))
  conditional_repeatable <- repeatable && (length(constrained_contexts) > 0L || length(consumed_events) > 0L)
  reliable_repeatable <- repeatable && !conditional_repeatable

  strength <- 0
  class_id <- if (repeatable && scalable) {
    "scalable_repeatable"
  } else if (reliable_repeatable) {
    "reliable_repeatable"
  } else if (conditional_repeatable) {
    "conditional_repeatable"
  } else {
    "one_shot"
  }
  class_weight <- query_synergy_cadence_class_weight(class_id)

  strength <- strength + class_weight
  if (permanent) {
    strength <- strength + 0.08
  }
  if (length(contexts) > 0L) {
    strength <- strength + min(0.12, length(contexts) * 0.04)
  }
  if (length(intersect(query_synergy_to_vector(produced), c("DRAW_CARD", "CREATE_TOKEN", "PUT_COUNTER", "CAST_SPELL", "ADD_MANA"))) > 0L && repeatable) {
    strength <- strength + 0.1
  }
  if (conditional_repeatable) {
    strength <- strength - min(0.16, 0.05 + 0.04 * length(constrained_contexts) + 0.03 * length(consumed_events))
  }

  list(
    class = class_id,
    repeatable = repeatable,
    scalable = scalable,
    strength = round(min(1, strength), 4),
    contexts = contexts,
    sources = sources
  )
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
        produced = c("DRAW_CARD", "SELF_DRAW_CARD", "LOOT", "DISCARD_CARD", "SELF_DISCARD", "PUT_COUNTER", "PUT_PLUS_ONE_COUNTER", "CONDITIONAL_COUNTER"),
        consumed = character(0),
        replaced = character(0),
        prevented = character(0),
        setup = c("DRAW_DISCARD_ENGINE", "GRAVEYARD_FUEL"),
        finisher = character(0),
        anti_tags = character(0),
        strategy_tags = c("draw_discard", "loot", "counter_scaling", "graveyard_fuel"),
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
        produced = c("DRAW_CARD", "SELF_DRAW_CARD", "LOOT", "CYCLING_EVENT", "DISCARD_CARD", "SELF_DISCARD"),
        consumed = character(0),
        replaced = character(0),
        prevented = character(0),
        setup = c("DRAW_DISCARD_ENGINE"),
        finisher = character(0),
        anti_tags = character(0),
        strategy_tags = c("draw_discard", "loot", "hand_smoothing"),
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
        produced = c("MILL_CARD", "SURVEIL_EVENT", "GRAVEYARD_FUEL"),
        consumed = character(0),
        replaced = character(0),
        prevented = character(0),
        setup = c("GRAVEYARD_SETUP"),
        finisher = character(0),
        anti_tags = character(0),
        strategy_tags = c("graveyard_setup", "card_selection"),
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
        produced = c("MILL_CARD", "DREDGE_EVENT", "GRAVEYARD_FUEL", "GRAVEYARD_TO_HAND"),
        consumed = character(0),
        replaced = c("DRAW_CARD"),
        prevented = character(0),
        setup = c("GRAVEYARD_SETUP"),
        finisher = character(0),
        anti_tags = c("REPLACES_DRAW"),
        strategy_tags = c("graveyard", "dredge", "self_mill"),
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
      ),
      madness = list(
        keywords = c("madness"),
        produced = c("CAST_SPELL"),
        consumed = c("DISCARD_CARD", "SELF_DISCARD"),
        replaced = character(0),
        prevented = character(0),
        setup = c("DRAW_DISCARD_ENGINE"),
        finisher = character(0),
        anti_tags = character(0),
        strategy_tags = c("draw_discard", "madness"),
        ability_templates = list(
          list(
            kind = "replacement",
            label = "Madness",
            trigger = list(condition = "if you discard this card"),
            effects = list(
              list(role = "require", event = "DISCARD_CARD"),
              list(role = "produce", event = "CAST_SPELL")
            ),
            references = list(
              plans = c("draw_discard", "madness"),
              setup = c("DRAW_DISCARD_ENGINE")
            )
          )
        ),
        notes = "Madness turns discard into cast opportunities"
      ),
      flashback = list(
        keywords = c("flashback"),
        produced = c("CAST_SPELL", "INSTANT_SORCERY_CAST"),
        consumed = c("MILL_CARD", "GRAVEYARD_FUEL"),
        replaced = character(0),
        prevented = character(0),
        setup = character(0),
        finisher = c("GRAVEYARD_SETUP"),
        anti_tags = character(0),
        strategy_tags = c("graveyard", "flashback"),
        ability_templates = list(
          list(
            kind = "activated",
            label = "Flashback",
            trigger = list(zone = "graveyard"),
            effects = list(
              list(role = "require", event = "MILL_CARD"),
              list(role = "produce", event = "CAST_SPELL")
            ),
            references = list(
              plans = c("graveyard", "flashback"),
              finisher = c("GRAVEYARD_SETUP")
            )
          )
        ),
        notes = "Flashback consumes graveyard setup to recast spells"
      ),
      cascade = list(
        keywords = c("cascade"),
        produced = c("CAST_SPELL"),
        consumed = c("CAST_SPELL"),
        replaced = character(0),
        prevented = character(0),
        setup = character(0),
        finisher = character(0),
        anti_tags = character(0),
        strategy_tags = c("value_chain"),
        ability_templates = list(
          list(
            kind = "triggered",
            label = "Cascade",
            trigger = list(event = "CAST_SPELL", scope = "self"),
            effects = list(
              list(role = "require", event = "CAST_SPELL"),
              list(role = "produce", event = "CAST_SPELL")
            ),
            references = list(plans = c("value_chain"))
          )
        ),
        notes = "Cascade chains one cast event into additional cast value"
      ),
      discover = list(
        keywords = c("discover"),
        produced = c("CAST_SPELL"),
        consumed = c("CAST_SPELL"),
        replaced = character(0),
        prevented = character(0),
        setup = character(0),
        finisher = character(0),
        anti_tags = character(0),
        strategy_tags = c("value_chain"),
        ability_templates = list(
          list(
            kind = "triggered",
            label = "Discover",
            trigger = list(event = "CAST_SPELL", scope = "self"),
            effects = list(
              list(role = "require", event = "CAST_SPELL"),
              list(role = "produce", event = "CAST_SPELL")
            ),
            references = list(plans = c("value_chain"))
          )
        ),
        notes = "Discover is modeled as cast conversion value"
      ),
      populate = list(
        keywords = c("populate"),
        produced = c("CREATE_TOKEN"),
        consumed = c("CREATE_TOKEN"),
        replaced = character(0),
        prevented = character(0),
        setup = character(0),
        finisher = c("TOKEN_PAYOFF"),
        anti_tags = character(0),
        strategy_tags = c("tokens"),
        ability_templates = list(
          list(
            kind = "spell_effect",
            label = "Populate",
            trigger = list(),
            effects = list(
              list(role = "require", event = "CREATE_TOKEN"),
              list(role = "produce", event = "CREATE_TOKEN")
            ),
            references = list(
              plans = c("tokens"),
              finisher = c("TOKEN_PAYOFF")
            )
          )
        ),
        notes = "Populate converts token setup into additional token output"
      ),
      investigate = list(
        keywords = c("investigate"),
        produced = c("CREATE_TOKEN", "CREATE_CLUE", "ARTIFACT_ETB", "SELF_DRAW_CARD"),
        consumed = character(0),
        replaced = character(0),
        prevented = character(0),
        setup = character(0),
        finisher = character(0),
        anti_tags = character(0),
        strategy_tags = c("tokens", "card_flow", "artifact"),
        ability_templates = list(
          list(
            kind = "keyword_action",
            label = "Investigate",
            trigger = list(),
            effects = list(
              list(role = "produce", event = "CREATE_TOKEN")
            ),
            references = list(plans = c("tokens", "card_flow"))
          )
        ),
        notes = "Investigate creates Clue token resources"
      ),
      casualty = list(
        keywords = c("casualty"),
        produced = c("SACRIFICE_PERMANENT"),
        consumed = c("CAST_SPELL"),
        replaced = character(0),
        prevented = character(0),
        setup = c("SACRIFICE_ENGINE"),
        finisher = character(0),
        anti_tags = character(0),
        strategy_tags = c("sacrifice", "spells"),
        ability_templates = list(
          list(
            kind = "replacement",
            label = "Casualty",
            trigger = list(condition = "as an additional cost to cast this spell"),
            effects = list(
              list(role = "require", event = "CAST_SPELL"),
              list(role = "produce", event = "SACRIFICE_PERMANENT")
            ),
            references = list(
              plans = c("sacrifice", "spells"),
              setup = c("SACRIFICE_ENGINE")
            )
          )
        ),
        notes = "Casualty converts casting into sacrifice pressure"
      ),
      lifelink = list(
        keywords = c("lifelink"),
        produced = c("GAIN_LIFE", "SELF_GAIN_LIFE"),
        consumed = c("COMBAT_DAMAGE_TO_PLAYER"),
        replaced = character(0),
        prevented = character(0),
        setup = character(0),
        finisher = character(0),
        anti_tags = character(0),
        strategy_tags = c("combat", "life"),
        ability_templates = list(
          list(
            kind = "static",
            label = "Lifelink",
            trigger = list(event = "COMBAT_DAMAGE_TO_PLAYER"),
            effects = list(
              list(role = "require", event = "COMBAT_DAMAGE_TO_PLAYER"),
              list(role = "produce", event = "GAIN_LIFE")
            ),
            references = list(plans = c("combat", "life"))
          )
        ),
        notes = "Lifelink converts combat damage into life gain"
      ),
      foretell = list(
        keywords = c("foretell"),
        produced = c("CAST_SPELL"),
        consumed = c("CAST_SPELL"),
        replaced = character(0),
        prevented = character(0),
        setup = c("DEFERRED_CAST"),
        finisher = character(0),
        anti_tags = character(0),
        strategy_tags = c("tempo", "spells"),
        ability_templates = list(
          list(
            kind = "activated",
            label = "Foretell",
            trigger = list(zone = "exile"),
            effects = list(
              list(role = "require", event = "CAST_SPELL"),
              list(role = "produce", event = "CAST_SPELL")
            ),
            references = list(
              plans = c("tempo", "spells"),
              setup = c("DEFERRED_CAST")
            )
          )
        ),
        notes = "Foretell defers cast timing while preserving cast events"
      ),
      delve = list(
        keywords = c("delve"),
        produced = c("CAST_SPELL"),
        consumed = c("MILL_CARD"),
        replaced = character(0),
        prevented = character(0),
        setup = character(0),
        finisher = c("GRAVEYARD_SETUP"),
        anti_tags = c("GRAVEYARD_DEPENDENT"),
        strategy_tags = c("graveyard", "spells"),
        ability_templates = list(
          list(
            kind = "static",
            label = "Delve",
            trigger = list(cost = "exile cards from your graveyard"),
            effects = list(
              list(role = "require", event = "MILL_CARD"),
              list(role = "produce", event = "CAST_SPELL")
            ),
            references = list(
              plans = c("graveyard", "spells"),
              finisher = c("GRAVEYARD_SETUP"),
              anti = c("GRAVEYARD_DEPENDENT")
            )
          )
        ),
        notes = "Delve consumes graveyard fuel to support casting"
      ),
      escape = list(
        keywords = c("escape"),
        produced = c("CAST_SPELL"),
        consumed = c("MILL_CARD"),
        replaced = character(0),
        prevented = character(0),
        setup = character(0),
        finisher = c("GRAVEYARD_SETUP"),
        anti_tags = c("GRAVEYARD_DEPENDENT"),
        strategy_tags = c("graveyard", "escape"),
        ability_templates = list(
          list(
            kind = "activated",
            label = "Escape",
            trigger = list(zone = "graveyard"),
            effects = list(
              list(role = "require", event = "MILL_CARD"),
              list(role = "produce", event = "CAST_SPELL")
            ),
            references = list(
              plans = c("graveyard", "escape"),
              finisher = c("GRAVEYARD_SETUP"),
              anti = c("GRAVEYARD_DEPENDENT")
            )
          )
        ),
        notes = "Escape recasts from graveyard using graveyard fuel"
      ),
      blitz = list(
        keywords = c("blitz"),
        produced = c("ATTACKS", "DRAW_CARD"),
        consumed = c("CAST_SPELL"),
        replaced = character(0),
        prevented = character(0),
        setup = c("DRAW_DISCARD_ENGINE"),
        finisher = character(0),
        anti_tags = character(0),
        strategy_tags = c("combat", "draw_discard"),
        ability_templates = list(
          list(
            kind = "activated",
            label = "Blitz",
            trigger = list(condition = "when this creature dies, draw a card"),
            effects = list(
              list(role = "require", event = "CAST_SPELL"),
              list(role = "produce", event = "ATTACKS"),
              list(role = "produce", event = "DRAW_CARD")
            ),
            references = list(
              plans = c("combat", "draw_discard"),
              setup = c("DRAW_DISCARD_ENGINE")
            )
          )
        ),
        notes = "Blitz compresses cast, attack pressure, and card flow"
      ),
      offspring = list(
        keywords = c("offspring"),
        produced = c("CREATE_TOKEN"),
        consumed = c("CAST_SPELL"),
        replaced = character(0),
        prevented = character(0),
        setup = character(0),
        finisher = c("TOKEN_PAYOFF"),
        anti_tags = character(0),
        strategy_tags = c("tokens", "creatures"),
        ability_templates = list(
          list(
            kind = "triggered",
            label = "Offspring",
            trigger = list(event = "ETB", scope = "self"),
            effects = list(
              list(role = "require", event = "CAST_SPELL"),
              list(role = "produce", event = "CREATE_TOKEN")
            ),
            references = list(
              plans = c("tokens", "creatures"),
              finisher = c("TOKEN_PAYOFF")
            )
          )
        ),
        notes = "Offspring creates extra body resources from cast sequencing"
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

query_synergy_parse_structured_abilities <- function(oracle_text,
                                                     registry = query_synergy_event_registry_default(),
                                                     parse_rules = query_synergy_ability_parse_rules_default(registry = registry)) {
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
    fragment_out <- query_synergy_parse_ability_fragment(
      fragment,
      index = index,
      registry = registry,
      parse_rules = parse_rules
    )
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

query_synergy_parse_ability_fragment <- function(fragment,
                                                 index = 1L,
                                                 registry = query_synergy_event_registry_default(),
                                                 parse_rules = query_synergy_ability_parse_rules_default(registry = registry)) {
  text <- query_api_scalar(fragment, default = "")
  lower <- tolower(text)
  if (!nzchar(lower)) {
    return(list(ok = FALSE))
  }

  kind <- query_synergy_classify_ability_fragment(lower)
  events <- query_synergy_extract_events_from_fragment(lower, registry = registry, parse_rules = parse_rules)
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

query_synergy_extract_events_from_fragment <- function(text,
                                                       registry = query_synergy_event_registry_default(),
                                                       parse_rules = query_synergy_ability_parse_rules_default(registry = registry)) {
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

  produced_patterns <- parse_rules$produced_patterns
  consumed_patterns <- parse_rules$consumed_patterns

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

  event_aliases <- parse_rules$replacement_aliases
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

  for (tag in names(parse_rules$setup_patterns)) {
    if (any(vapply(parse_rules$setup_patterns[[tag]], function(pattern) grepl(pattern, lower, perl = TRUE), logical(1)))) {
      setup <- c(setup, query_api_scalar(tag, default = ""))
    }
  }
  for (tag in names(parse_rules$finisher_patterns)) {
    if (any(vapply(parse_rules$finisher_patterns[[tag]], function(pattern) grepl(pattern, lower, perl = TRUE), logical(1)))) {
      finisher <- c(finisher, query_api_scalar(tag, default = ""))
    }
  }
  for (tag in names(parse_rules$anti_tag_patterns)) {
    if (any(vapply(parse_rules$anti_tag_patterns[[tag]], function(pattern) grepl(pattern, lower, perl = TRUE), logical(1)))) {
      anti_tags <- c(anti_tags, query_api_scalar(tag, default = ""))
    }
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
query_synergy_extract_events_from_text <- function(oracle_text,
                                                   registry = query_synergy_event_registry_default(),
                                                   parse_rules = query_synergy_ability_parse_rules_default(registry = registry)) {
  query_synergy_parse_structured_abilities(oracle_text, registry = registry, parse_rules = parse_rules)
}

query_synergy_ability_parse_rules_default <- local({
  cached <- NULL

  function(registry = query_synergy_event_registry_default()) {
    if (!is.null(cached)) {
      return(cached)
    }

    cached <<- query_synergy_build_ability_parse_rules(
      base_rules = query_synergy_ability_parse_rules_seed(),
      registry = registry
    )
    cached
  }
})

query_synergy_ability_parse_rules_seed <- function() {
  list(
    produced_patterns = list(
      DRAW_CARD = c("draw\\s+(a|an|x|one|two|three|[0-9]+)\\s+card", "conniv"),
      DISCARD_CARD = c("discard\\s+(a|an|x|one|two|three|[0-9]+)\\s+card", "discards\\s+(a|an|x|one|two|three|[0-9]+)\\s+card", "conniv"),
      LOOT = c("conniv", "draw\\s+a\\s+card.*then discard", "discard\\s+a\\s+card.*then draw", "cycling\\s*\\{"),
      CYCLING_EVENT = c("cycling\\s*\\{"),
      SURVEIL_EVENT = c("surveil\\s+[0-9x]+"),
      DREDGE_EVENT = c("dredge\\s+[0-9]+"),
      GAIN_LIFE = c("gain\\s+[0-9x]+\\s+life"),
      LOSE_LIFE = c("lose\\s+[0-9x]+\\s+life"),
      OPPONENT_LOSE_LIFE = c("each opponent loses\\s+[0-9x]+\\s+life", "target opponent loses\\s+[0-9x]+\\s+life"),
      DRAIN_LIFE = c("each opponent loses\\s+[0-9x]+\\s+life and you gain", "loses?\\s+[0-9x]+\\s+life\\.\\s*you gain"),
      CREATE_TOKEN = c("create\\s+.*token"),
      CREATE_CREATURE_TOKEN = c("create\\s+.*creature token"),
      CREATE_TREASURE = c("create\\s+.*treasure token"),
      CREATE_FOOD = c("create\\s+.*food token"),
      CREATE_CLUE = c("create\\s+.*clue token", "investigat"),
      ADD_MANA = c("add\\s*\\{"),
      PUT_COUNTER = c("put\\s+.*counter"),
      PUT_PLUS_ONE_COUNTER = c("put\\s+[a-z0-9 ]*\\+1/\\+1\\s+counter"),
      CONDITIONAL_COUNTER = c("if .* (discard|sacrific|leaves|dies|enters|attacks).*put\\s+.*counter"),
      SACRIFICE_PERMANENT = c("sacrifice\\s+"),
      ETB = c("enters? the battlefield"),
      CREATURE_ETB = c("whenever .* creature .* enters", "whenever another creature enters"),
      ARTIFACT_ETB = c("whenever .* artifact .* enters", "whenever an artifact enters"),
      ENCHANTMENT_ETB = c("whenever .* enchantment .* enters", "whenever an enchantment enters"),
      LAND_ENTERS = c("whenever .* land .* enters", "whenever a land enters"),
      DIES = c("dies", "is put into (a|your|their) graveyard from the battlefield"),
      TOKEN_DIES = c("whenever a token .* dies", "whenever .* token creature .* dies"),
      ATTACKS = c("whenever .* attacks", "when .* attacks", "target attacking creature"),
      ATTACKS_SELF = c("whenever (this|~|cardname|sm:cardname) attacks"),
      ATTACKS_WITH_CREATURE = c("whenever you attack with", "whenever one or more creatures you control attack"),
      CAST_SPELL = c("cast\\s+(a|an|this|that)?\\s*spell"),
      INSTANT_SORCERY_CAST = c("whenever you cast an instant or sorcery"),
      SECOND_SPELL_TRIGGER = c("the second spell you cast each turn"),
      GRAVEYARD_TO_HAND = c("from your graveyard to your hand"),
      MILL_CARD = c(
        "mill",
        "put the top .* of .* library into .* graveyard",
        "search\\s+[^.]*library[^.]*put\\s+[^.]*into\\s+[^.]*graveyard",
        "put\\s+[^.]*from\\s+[^.]*library\\s+into\\s+[^.]*graveyard"
      ),
      REANIMATE = c("from .* graveyard to the battlefield"),
      EXILE_CARD = c("exile .* card"),
      TARGETS_CREATURE = c("target .* creature")
    ),
    consumed_patterns = list(
      SELF_DRAW_CARD = c("whenever you draw", "if you draw", "whenever you've drawn"),
      OPPONENT_DRAW_CARD = c("whenever an opponent draws", "if an opponent draws"),
      DISCARD_CARD = c("whenever .* discards"),
      SELF_DISCARD = c("whenever you discard", "if you discard"),
      GAIN_LIFE = c("whenever you gain life", "if you gain life"),
      SELF_GAIN_LIFE = c("whenever you gain life", "if you gain life"),
      DRAIN_LIFE = c("whenever an opponent loses life", "whenever a player loses life"),
      OPPONENT_LOSE_LIFE = c("whenever an opponent loses life"),
      DIES = c("whenever .* dies", "whenever a creature dies"),
      TOKEN_DIES = c("whenever a token .* dies"),
      CREATURE_ETB = c("whenever .* creature .* enters", "whenever another creature enters"),
      ARTIFACT_ETB = c("whenever .* artifact .* enters"),
      ENCHANTMENT_ETB = c("whenever .* enchantment .* enters"),
      LAND_ENTERS = c("whenever .* land .* enters"),
      CAST_SPELL = c("whenever you cast"),
      NONCREATURE_SPELL_CAST = c("whenever you cast a noncreature spell"),
      INSTANT_SORCERY_CAST = c("whenever you cast an instant or sorcery"),
      SECOND_SPELL_TRIGGER = c("the second spell you cast each turn"),
      COMBAT_DAMAGE_TO_PLAYER = c("whenever .* deals combat damage to a player"),
      ATTACKS = c("whenever you attack", "when you attack"),
      ATTACKS_WITH_CREATURE = c("whenever one or more creatures you control attack", "whenever you attack with"),
      PUT_PLUS_ONE_COUNTER = c("whenever (a|one or more) \\+1/\\+1 counter(s)? (is|are) put"),
      CREATE_TOKEN = c("whenever .* token .* enters", "whenever you create"),
      HAND_SIZE_PAYOFF = c("for each card in your hand", "no maximum hand size"),
      GRAVEYARD_COUNT_SCALING = c("for each .* card in (your|a) graveyard", "equal to the number of .* cards in (your|a) graveyard"),
      BOARD_WIDTH_PAYOFF = c("for each creature you control", "for each attacking creature", "for each permanent you control"),
      ATTACKER_COUNT_SCALING = c("for each attacking creature", "equal to the number of attacking creatures"),
      CREATURE_COUNT_SCALING = c("for each creature you control", "equal to the number of creatures you control")
    ),
    replacement_aliases = query_synergy_event_text_aliases(),
    setup_patterns = list(
      DRAW_DISCARD_ENGINE = c("whenever you draw|draw\\s+.*card|conniv|cycling\\s*\\{"),
      GRAVEYARD_SETUP = c(
        "surveil|mill|dredge|put the top .* library into .* graveyard",
        "search\\s+[^.]*library[^.]*put\\s+[^.]*into\\s+[^.]*graveyard",
        "put\\s+[^.]*from\\s+[^.]*library\\s+into\\s+[^.]*graveyard"
      )
    ),
    finisher_patterns = list(
      GRAVEYARD_SETUP = c("from .* graveyard to the battlefield|reanimate|unearth")
    ),
    anti_tag_patterns = list(
      HAND_SIZE_PAYOFF = c("no maximum hand size|for each card in your hand"),
      HAND_DISCARD_PRESSURE = c("discard your hand|each player.*discards|that player discards"),
      GRAVEYARD_HATE = c("exile all graveyards|cards in graveyards can't"),
      GRAVEYARD_DEPENDENT = c("from your graveyard")
    )
  )
}

query_synergy_build_ability_parse_rules <- function(rules = list(),
                                                    base_rules = NULL,
                                                    registry = query_synergy_event_registry_default()) {
  merged <- if (is.list(base_rules) && length(base_rules) > 0L) base_rules else query_synergy_ability_parse_rules_seed()
  additions <- if (is.list(rules)) rules else list()

  merge_event_map <- function(base_map, add_map) {
    out <- list()
    all_maps <- list(base_map, add_map)
    for (map in all_maps) {
      if (!is.list(map) || length(map) == 0L) {
        next
      }
      for (event_name in names(map)) {
        event_id <- query_synergy_canonicalize_events(event_name, registry)
        if (length(event_id) == 0L) {
          next
        }
        key <- event_id[[1]]
        out[[key]] <- unique(c(query_synergy_to_vector(out[[key]]), query_synergy_to_vector(map[[event_name]])))
      }
    }
    out
  }

  merge_tag_map <- function(base_map, add_map) {
    out <- list()
    all_maps <- list(base_map, add_map)
    for (map in all_maps) {
      if (!is.list(map) || length(map) == 0L) {
        next
      }
      for (tag_name in names(map)) {
        key <- query_api_scalar(tag_name, default = "")
        if (!nzchar(key)) {
          next
        }
        out[[key]] <- unique(c(query_synergy_to_vector(out[[key]]), query_synergy_to_vector(map[[tag_name]])))
      }
    }
    out
  }

  list(
    produced_patterns = merge_event_map(merged$produced_patterns, additions$produced_patterns),
    consumed_patterns = merge_event_map(merged$consumed_patterns, additions$consumed_patterns),
    replacement_aliases = merge_event_map(merged$replacement_aliases, additions$replacement_aliases),
    setup_patterns = merge_tag_map(merged$setup_patterns, additions$setup_patterns),
    finisher_patterns = merge_tag_map(merged$finisher_patterns, additions$finisher_patterns),
    anti_tag_patterns = merge_tag_map(merged$anti_tag_patterns, additions$anti_tag_patterns)
  )
}

query_synergy_strategy_tags_from_events <- function(produced,
                                                    consumed,
                                                    setup_events,
                                                    finisher_events,
                                                    roles = character(0),
                                                    cadence = list(),
                                                    target_roles = character(0),
                                                    oracle_text = "") {
  tags <- character(0)
  produced_events <- query_synergy_to_vector(produced)
  consumed_events <- query_synergy_to_vector(consumed)
  role_values <- query_synergy_to_vector(roles)
  target_values <- query_synergy_to_vector(target_roles)

  if (length(intersect(produced_events, c("DRAW_CARD", "DISCARD_CARD", "SELF_DRAW_CARD"))) > 0L ||
      length(intersect(consumed_events, c("DRAW_CARD", "SELF_DRAW_CARD", "DISCARD_CARD"))) > 0L) {
    tags <- c(tags, "draw_discard")
  }

  if (length(intersect(produced_events, c("MILL_CARD", "REANIMATE", "GRAVEYARD_TO_HAND"))) > 0L ||
      length(intersect(consumed_events, c("MILL_CARD", "REANIMATE", "GRAVEYARD_TO_HAND"))) > 0L ||
      length(intersect(setup_events, c("GRAVEYARD_SETUP"))) > 0L ||
      length(intersect(finisher_events, c("GRAVEYARD_SETUP"))) > 0L) {
    tags <- c(tags, "graveyard")
  }

  if (length(intersect(produced_events, c("CREATE_TOKEN", "PUT_COUNTER", "ETB", "DIES", "SACRIFICE_PERMANENT"))) > 0L) {
    tags <- c(tags, "board_engine")
  }

  if ("converter" %in% role_values) {
    tags <- c(tags, "converter")
  }
  if ("bridge" %in% role_values) {
    tags <- c(tags, "bridge_engine")
  }
  if ("engine" %in% role_values && isTRUE(cadence$repeatable)) {
    tags <- c(tags, "repeatable_engine")
  }
  if ("amplifier" %in% role_values) {
    tags <- c(tags, "amplifier")
  }
  if ("target" %in% role_values || length(target_values) > 0L) {
    tags <- c(tags, "targeted_play")
  }

  if (length(intersect(produced_events, c("DRAW_CARD", "SELF_DRAW_CARD"))) > 0L) {
    tags <- c(tags, "draw_enabler")
  }
  if (length(intersect(consumed_events, c("DRAW_CARD", "SELF_DRAW_CARD", "OPPONENT_DRAW_CARD"))) > 0L) {
    tags <- c(tags, "draw_payoff")
  }
  if (length(intersect(produced_events, c("DISCARD_CARD"))) > 0L) {
    tags <- c(tags, "discard_enabler")
  }
  if (length(intersect(consumed_events, c("DISCARD_CARD"))) > 0L) {
    tags <- c(tags, "discard_payoff")
  }
  if (length(intersect(produced_events, c("MILL_CARD"))) > 0L) {
    tags <- c(tags, "graveyard_enabler")
  }
  if (length(intersect(produced_events, c("REANIMATE", "GRAVEYARD_TO_HAND"))) > 0L || length(finisher_events) > 0L) {
    tags <- c(tags, "graveyard_finisher")
  }
  if (length(intersect(produced_events, c("CREATE_TOKEN"))) > 0L) {
    tags <- c(tags, "token_producer")
  }
  if (length(intersect(produced_events, c("SACRIFICE_PERMANENT"))) > 0L) {
    tags <- c(tags, "sacrifice_outlet")
  }
  if (length(intersect(consumed_events, c("DIES", "SACRIFICE_PERMANENT"))) > 0L) {
    tags <- c(tags, "death_payoff")
  }
  if (length(intersect(produced_events, c("CAST_SPELL", "NONCREATURE_SPELL_CAST"))) > 0L) {
    tags <- c(tags, "spell_enabler")
  }
  if (length(intersect(consumed_events, c("CAST_SPELL", "NONCREATURE_SPELL_CAST"))) > 0L) {
    tags <- c(tags, "spell_payoff")
  }
  if (length(intersect(produced_events, c("ATTACKS", "COMBAT_DAMAGE_TO_PLAYER"))) > 0L || "combat" %in% query_synergy_to_vector(cadence$contexts)) {
    tags <- c(tags, "combat_engine")
  }

  # Punisher / drain tags --------------------------------------------------
  # Cards that key off opponent draws (Sheoldred, Underworld Dreams, ...).
  consumes_opp_draw <- "OPPONENT_DRAW_CARD" %in% consumed_events
  produces_life_swing <- length(intersect(produced_events, c("GAIN_LIFE", "LOSE_LIFE"))) > 0L
  if (consumes_opp_draw) {
    tags <- c(tags, "opponent_draw_punisher")
    if (produces_life_swing) {
      # Sheoldred-style: each opponent draw drains life (and/or gains life).
      tags <- c(tags, "life_drain_on_opponent_draw")
    }
  }

  # Creature-count / X-scaling --------------------------------------------
  # Connive X / pump X / token X effects whose magnitude depends on a
  # variable board state. Detected from CONDITIONAL_COUNTER events plus a
  # text fallback that catches "X is the number of ..." templates Scryfall
  # uses for board-scaling abilities.
  oracle_text_value <- query_api_scalar(oracle_text, default = "")
  if ("CONDITIONAL_COUNTER" %in% produced_events ||
      grepl("x is the number of", tolower(oracle_text_value), fixed = TRUE)) {
    tags <- c(tags, "creature_count_scaling")
  }

  unique(tags)
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
    madness = "\\bmadness\\b",
    flashback = "\\bflashback\\b",
    cascade = "\\bcascade\\b",
    discover = "\\bdiscover\\b",
    populate = "\\bpopulate\\b",
    mill = "\\bmill\\b",
    investigate = "\\binvestigate\\b",
    casualty = "\\bcasualty\\b",
    lifelink = "\\blifelink\\b",
    foretell = "\\bforetell\\b",
    delve = "\\bdelve\\b",
    proliferate = "\\bproliferate\\b",
    escape = "\\bescape\\b",
    blitz = "\\bblitz\\b",
    offspring = "\\boffspring\\b"
  )

  hits <- names(Filter(function(pattern) {
    grepl(pattern, text, perl = TRUE)
  }, patterns))

  unique(unlist(hits, use.names = FALSE))
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
  # Fast path: card is already a normalized_card_v2 record (e.g. loaded from
  # the enriched SQLite via query_synergy_catalog_normalized_from_sqlite()).
  if (is.list(card) && identical(query_api_scalar(card$model_version, default = ""), "normalized_card_v2")) {
    return(card)
  }

  card_id <- query_synergy_card_id(card)
  signature <- query_synergy_card_signature(card)
  key <- if (nzchar(card_id) || nzchar(signature)) {
    paste0(card_id, "::", signature)
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
