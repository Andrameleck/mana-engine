# Event registry, canonicalization, and family expansion.
# Extracted from R/query_synergy_engine.R as part of the modular refactor.
# Depends only on synergy_utils helpers (to_vector, normalize_event_id, etc.).

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
    ),
    # ---- Card-flow refinements ---------------------------------------------
    LOOT = list(
      label = "Loot",
      description = "Looking-style draw-then-discard or discard-then-draw",
      parent = "CARD_FLOW",
      aliases = c("LOOT_EVENT", "RUMMAGE", "CONNIVE_LIKE"),
      kind = "resource_flow",
      scope = "self",
      resource = "card",
      zones = list(from = "library", to = "hand"),
      tags = c("card_flow", "card_selection", "loot", "self")
    ),
    CYCLING_EVENT = list(
      label = "Cycling",
      description = "Cycling activated ability (discard then draw)",
      parent = "LOOT",
      aliases = character(0),
      kind = "resource_flow",
      scope = "self",
      resource = "card",
      zones = list(from = "library", to = "hand"),
      tags = c("card_flow", "cycling", "hand_smoothing", "self")
    ),
    SURVEIL_EVENT = list(
      label = "Surveil",
      description = "Surveil keyword action (mill with selection)",
      parent = "MILL_CARD",
      aliases = character(0),
      kind = "zone_change",
      scope = "self",
      resource = "card",
      zones = list(from = "library", to = "graveyard"),
      tags = c("graveyard", "graveyard_setup", "card_selection", "self")
    ),
    DREDGE_EVENT = list(
      label = "Dredge",
      description = "Dredge replacement self-mill draw",
      parent = "MILL_CARD",
      aliases = character(0),
      kind = "zone_change",
      scope = "self",
      resource = "card",
      zones = list(from = "library", to = "graveyard"),
      tags = c("graveyard", "self_mill", "recursion", "self")
    ),
    SELF_DISCARD = list(
      label = "You discard",
      description = "Controller discards a card",
      parent = "DISCARD_CARD",
      aliases = c("YOU_DISCARD"),
      kind = "resource_flow",
      scope = "self",
      resource = "card",
      zones = list(from = "hand", to = "graveyard"),
      tags = c("card_flow", "self_discard", "fuel", "self")
    ),
    OPPONENT_DISCARD = list(
      label = "Opponent discards",
      description = "An opponent discards a card",
      parent = "DISCARD_CARD",
      aliases = character(0),
      kind = "resource_flow",
      scope = "opponent",
      resource = "card",
      zones = list(from = "hand", to = "graveyard"),
      tags = c("card_flow", "opponent", "hand_disruption")
    ),
    HAND_SIZE_PAYOFF = list(
      label = "Hand size payoff",
      description = "Effect scales with cards in hand",
      parent = "CARD_FLOW",
      aliases = character(0),
      kind = "scaling",
      scope = "self",
      resource = "card",
      zones = list(),
      tags = c("hand_size", "scaling")
    ),
    # ---- Life refinements --------------------------------------------------
    SELF_GAIN_LIFE = list(
      label = "You gain life",
      description = "Controller gains life",
      parent = "GAIN_LIFE",
      aliases = c("YOU_GAIN_LIFE"),
      kind = "resource_delta",
      scope = "self",
      resource = "life",
      zones = list(),
      tags = c("life", "self")
    ),
    OPPONENT_LOSE_LIFE = list(
      label = "Opponent loses life",
      description = "An opponent loses life",
      parent = "LOSE_LIFE",
      aliases = character(0),
      kind = "resource_delta",
      scope = "opponent",
      resource = "life",
      zones = list(),
      tags = c("life", "opponent", "drain")
    ),
    DRAIN_LIFE = list(
      label = "Drain life",
      description = "Opponent loses life and you gain life",
      parent = "LOSE_LIFE",
      aliases = c("LIFE_DRAIN"),
      kind = "resource_delta",
      scope = "opponent",
      resource = "life",
      zones = list(),
      tags = c("life", "drain", "payoff_combo")
    ),
    # ---- Counter refinements ----------------------------------------------
    PUT_PLUS_ONE_COUNTER = list(
      label = "Put +1/+1 counter",
      description = "Place a +1/+1 counter on a creature",
      parent = "PUT_COUNTER",
      aliases = c("PLUS_ONE_COUNTER"),
      kind = "board_delta",
      scope = "self",
      resource = "counter",
      zones = list(),
      tags = c("counters", "creature_growth", "self")
    ),
    CONDITIONAL_COUNTER = list(
      label = "Conditional counter",
      description = "Counter triggered by an upstream condition",
      parent = "PUT_COUNTER",
      aliases = character(0),
      kind = "board_delta",
      scope = "self",
      resource = "counter",
      zones = list(),
      tags = c("counters", "conditional")
    ),
    # ---- Combat refinements -----------------------------------------------
    ATTACKS_SELF = list(
      label = "This attacks",
      description = "Whenever this creature attacks",
      parent = "ATTACKS",
      aliases = character(0),
      kind = "combat",
      scope = "self",
      resource = "",
      zones = list(),
      tags = c("combat", "self")
    ),
    ATTACKS_WITH_CREATURE = list(
      label = "Attack with creature(s)",
      description = "Whenever you attack with one or more creatures",
      parent = "ATTACKS",
      aliases = character(0),
      kind = "combat",
      scope = "self",
      resource = "",
      zones = list(),
      tags = c("combat", "board_width_payoff")
    ),
    # ---- Board width / scaling --------------------------------------------
    BOARD_WIDTH_PAYOFF = list(
      label = "Board width payoff",
      description = "Effect scales with number of permanents you control",
      parent = "BOARD_DEVELOPMENT",
      aliases = character(0),
      kind = "scaling",
      scope = "self",
      resource = "permanent",
      zones = list(),
      tags = c("scaling", "wide", "board_width")
    ),
    ATTACKER_COUNT_SCALING = list(
      label = "Attacker count scaling",
      description = "Effect scales with number of attacking creatures",
      parent = "BOARD_WIDTH_PAYOFF",
      aliases = character(0),
      kind = "scaling",
      scope = "self",
      resource = "permanent",
      zones = list(),
      tags = c("scaling", "combat", "board_width")
    ),
    CREATURE_COUNT_SCALING = list(
      label = "Creature count scaling",
      description = "Effect scales with number of creatures you control",
      parent = "BOARD_WIDTH_PAYOFF",
      aliases = character(0),
      kind = "scaling",
      scope = "self",
      resource = "permanent",
      zones = list(),
      tags = c("scaling", "creatures")
    ),
    # ---- Token subkinds ---------------------------------------------------
    CREATE_CREATURE_TOKEN = list(
      label = "Create creature token",
      description = "Create one or more creature tokens",
      parent = "CREATE_TOKEN",
      aliases = character(0),
      kind = "board_delta",
      scope = "self",
      resource = "token",
      zones = list(from = "outside_game", to = "battlefield"),
      tags = c("tokens", "board_width", "creatures")
    ),
    CREATE_TREASURE = list(
      label = "Create treasure",
      description = "Create one or more Treasure tokens",
      parent = "CREATE_TOKEN",
      aliases = character(0),
      kind = "board_delta",
      scope = "self",
      resource = "token",
      zones = list(from = "outside_game", to = "battlefield"),
      tags = c("tokens", "ramp", "sacrifice_fuel", "artifact")
    ),
    CREATE_FOOD = list(
      label = "Create food",
      description = "Create one or more Food tokens",
      parent = "CREATE_TOKEN",
      aliases = character(0),
      kind = "board_delta",
      scope = "self",
      resource = "token",
      zones = list(from = "outside_game", to = "battlefield"),
      tags = c("tokens", "life", "sacrifice_fuel", "artifact")
    ),
    CREATE_CLUE = list(
      label = "Create clue",
      description = "Create one or more Clue tokens (sac for draw)",
      parent = "CREATE_TOKEN",
      aliases = character(0),
      kind = "board_delta",
      scope = "self",
      resource = "token",
      zones = list(from = "outside_game", to = "battlefield"),
      tags = c("tokens", "card_flow", "sacrifice_fuel", "artifact")
    ),
    # ---- ETB / DIES granularity -------------------------------------------
    CREATURE_ETB = list(
      label = "Creature ETB",
      description = "Whenever a creature enters",
      parent = "ETB",
      aliases = character(0),
      kind = "zone_change",
      scope = "generic",
      resource = "permanent",
      zones = list(from = "stack", to = "battlefield"),
      tags = c("battlefield", "creature")
    ),
    ARTIFACT_ETB = list(
      label = "Artifact ETB",
      description = "Whenever an artifact enters",
      parent = "ETB",
      aliases = character(0),
      kind = "zone_change",
      scope = "generic",
      resource = "permanent",
      zones = list(from = "stack", to = "battlefield"),
      tags = c("battlefield", "artifact")
    ),
    ENCHANTMENT_ETB = list(
      label = "Enchantment ETB",
      description = "Whenever an enchantment enters",
      parent = "ETB",
      aliases = character(0),
      kind = "zone_change",
      scope = "generic",
      resource = "permanent",
      zones = list(from = "stack", to = "battlefield"),
      tags = c("battlefield", "enchantment")
    ),
    LAND_ENTERS = list(
      label = "Land enters",
      description = "Whenever a land enters",
      parent = "ETB",
      aliases = character(0),
      kind = "zone_change",
      scope = "generic",
      resource = "permanent",
      zones = list(from = "hand", to = "battlefield"),
      tags = c("battlefield", "land", "ramp")
    ),
    TOKEN_DIES = list(
      label = "Token dies",
      description = "Whenever a token dies",
      parent = "DIES",
      aliases = character(0),
      kind = "zone_change",
      scope = "generic",
      resource = "permanent",
      zones = list(from = "battlefield", to = "graveyard"),
      tags = c("death", "tokens", "aristocrats")
    ),
    # ---- Spell engine refinements -----------------------------------------
    INSTANT_SORCERY_CAST = list(
      label = "Cast instant or sorcery",
      description = "Whenever you cast an instant or sorcery",
      parent = "CAST_SPELL",
      aliases = character(0),
      kind = "stack",
      scope = "self",
      resource = "spell",
      zones = list(from = "hand", to = "stack"),
      tags = c("casting", "spellslinger", "prowess")
    ),
    SECOND_SPELL_TRIGGER = list(
      label = "Second spell each turn",
      description = "Triggers on the second spell cast each turn",
      parent = "CAST_SPELL",
      aliases = character(0),
      kind = "stack",
      scope = "self",
      resource = "spell",
      zones = list(from = "hand", to = "stack"),
      tags = c("casting", "storm_like", "spell_count")
    ),
    # ---- Graveyard refinements --------------------------------------------
    GRAVEYARD_FUEL = list(
      label = "Graveyard fuel",
      description = "Loads or relies on cards in graveyard",
      parent = "GRAVEYARD_FLOW",
      aliases = character(0),
      kind = "scaling",
      scope = "self",
      resource = "card",
      zones = list(to = "graveyard"),
      tags = c("graveyard", "self_mill", "reanimator_setup", "scaling")
    ),
    GRAVEYARD_COUNT_SCALING = list(
      label = "Graveyard count scaling",
      description = "Effect scales with number of cards in graveyard",
      parent = "GRAVEYARD_FLOW",
      aliases = character(0),
      kind = "scaling",
      scope = "self",
      resource = "card",
      zones = list(),
      tags = c("graveyard", "scaling", "delirium_like")
    )
  )
}

query_synergy_build_event_lineage_for_id <- function(event_id, events) {
  lineage <- character(0)
  current <- query_api_scalar(event_id, default = "")
  visited <- character(0)

  while (nzchar(current) && !current %in% visited) {
    lineage <- c(lineage, current)
    visited <- c(visited, current)
    current <- query_api_scalar(events[[current]]$parent, default = "")
  }

  unique(lineage)
}

query_synergy_build_event_family_for_id <- function(event_id, children_by_parent = list()) {
  family <- character(0)
  queue <- query_synergy_to_vector(event_id)

  while (length(queue) > 0L) {
    current <- queue[[1]]
    if (length(queue) == 1L) {
      queue <- character(0)
    } else {
      queue <- queue[-1]
    }

    if (!nzchar(current) || current %in% family) {
      next
    }

    family <- c(family, current)
    children <- setdiff(query_synergy_to_vector(children_by_parent[[current]]), family)
    if (length(children) > 0L) {
      queue <- c(queue, children)
    }
  }

  unique(family)
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

  children_by_parent <- list()
  for (event_id in names(merged)) {
    parent_id <- query_api_scalar(merged[[event_id]]$parent, default = "")
    if (!nzchar(parent_id)) {
      next
    }
    children_by_parent[[parent_id]] <- unique(c(query_synergy_to_vector(children_by_parent[[parent_id]]), event_id))
  }

  lineage_cache <- lapply(names(merged), function(event_id) {
    query_synergy_build_event_lineage_for_id(event_id, merged)
  })
  names(lineage_cache) <- names(merged)

  family_cache <- lapply(names(merged), function(event_id) {
    query_synergy_build_event_family_for_id(event_id, children_by_parent)
  })
  names(family_cache) <- names(merged)

  list(
    events = merged,
    alias_to_id = alias_to_id,
    children_by_parent = children_by_parent,
    lineage_cache = lineage_cache,
    family_cache = family_cache
  )
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

  if (is.list(registry$family_cache) && length(registry$family_cache) > 0L) {
    cached <- unique(unlist(lapply(seeds, function(event_id) {
      query_synergy_to_vector(registry$family_cache[[event_id]])
    }), use.names = FALSE))
    if (length(cached) > 0L) {
      return(unique(cached))
    }
  }

  children_by_parent <- if (is.list(registry$children_by_parent)) registry$children_by_parent else list()
  family <- character(0)
  queue <- seeds

  while (length(queue) > 0L) {
    current <- queue[[1]]
    if (length(queue) == 1L) {
      queue <- character(0)
    } else {
      queue <- queue[-1]
    }

    if (!nzchar(current) || current %in% family) {
      next
    }

    family <- c(family, current)
    children <- setdiff(query_synergy_to_vector(children_by_parent[[current]]), family)
    if (length(children) > 0L) {
      queue <- c(queue, children)
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
