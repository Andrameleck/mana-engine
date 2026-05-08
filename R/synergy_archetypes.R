# =============================================================================
# Archetype registry for synergy group classification & filtering.
#
# Each archetype defines a strategic theme (Aristocrats, Reanimator, Spellslinger,
# etc.) along with the strategy_tags, produced/consumed events, and role patterns
# that signal it.
#
# Archetype detection produces, for each card or group of cards:
#   - a list of matching archetype keys
#   - a per-archetype "fit" score in [0, 1]
#
# The registry is intentionally compact (~25 archetypes covering the major
# Magic: The Gathering strategic themes from the user's list). It groups
# overlapping concepts (e.g. Reanimator subsumes Recursion and Self-mill,
# Aristocrats subsumes Sacrifice + Death triggers + Tokens go-wide-sac).
# =============================================================================

query_synergy_archetype_registry <- local({
  registry <- NULL
  function() {
    if (!is.null(registry)) return(registry)

    registry <<- list(
      aggro = list(
        label = "Aggro",
        description = "Fast creature pressure, low curve, combat damage focused.",
        any_tags = c("combat_engine", "token_producer", "amplifier"),
        any_produced = c("ATTACKS", "COMBAT_DAMAGE_TO_PLAYER", "CREATE_TOKEN"),
        any_consumed = c("ATTACKS", "COMBAT_DAMAGE_TO_PLAYER"),
        roles = c("amplifier", "engine"),
        weight_tag = 1.0,
        weight_event = 0.8
      ),
      midrange = list(
        label = "Midrange",
        description = "Balanced creatures, removal, and value engines.",
        any_tags = c("converter", "bridge_engine", "draw_payoff"),
        any_produced = character(0),
        any_consumed = character(0),
        roles = c("bridge", "converter"),
        weight_tag = 0.7,
        weight_event = 0.5
      ),
      control = list(
        label = "Control",
        description = "Disruption, removal, late-game card advantage.",
        any_tags = c("draw_enabler", "draw_payoff", "spell_payoff"),
        any_produced = c("EXILE_CARD", "RETURN_FROM_GRAVEYARD"),
        any_consumed = c("CAST_SPELL", "NONCREATURE_SPELL_CAST"),
        roles = c("payoff", "amplifier"),
        weight_tag = 0.8,
        weight_event = 0.6
      ),
      combo = list(
        label = "Combo",
        description = "Specific card interactions producing a winning loop or burst.",
        any_tags = c("combo_piece", "tutor", "infinite_loop"),
        any_produced = c("INFINITE_MANA", "INFINITE_DAMAGE"),
        any_consumed = character(0),
        roles = c("payoff", "engine"),
        weight_tag = 1.2,
        weight_event = 1.0
      ),
      ramp = list(
        label = "Ramp / Big Mana",
        description = "Mana acceleration to deploy expensive threats.",
        any_tags = c("ramp", "mana_rock", "treasure_producer"),
        any_produced = c("MANA_ROCK_ETB", "TREASURE_TOKEN", "LAND_ENTERS"),
        any_consumed = character(0),
        roles = c("setup", "engine"),
        weight_tag = 1.0,
        weight_event = 0.8
      ),
      mill = list(
        label = "Mill",
        description = "Move opponent (or self) library cards to graveyard.",
        any_tags = c("graveyard_enabler"),
        any_produced = c("MILL_CARD"),
        any_consumed = character(0),
        roles = c("engine", "amplifier"),
        weight_tag = 1.2,
        weight_event = 1.0
      ),
      discard = list(
        label = "Discard",
        description = "Force opponents (or self) to discard cards.",
        any_tags = c("discard_enabler", "discard_payoff"),
        any_produced = c("DISCARD_CARD"),
        any_consumed = c("DISCARD_CARD"),
        roles = c("engine", "payoff"),
        weight_tag = 1.0,
        weight_event = 0.9
      ),
      card_draw = list(
        label = "Card Draw / Advantage",
        description = "Repeatable card draw and draw-trigger payoffs.",
        any_tags = c("draw_enabler", "draw_payoff"),
        any_produced = c("DRAW_CARD", "SELF_DRAW_CARD"),
        any_consumed = c("DRAW_CARD", "SELF_DRAW_CARD"),
        roles = c("engine", "payoff"),
        weight_tag = 1.0,
        weight_event = 0.9
      ),
      graveyard = list(
        label = "Graveyard / Reanimator / Recursion",
        description = "Use the graveyard as a resource: reanimate, return, recur.",
        any_tags = c("graveyard", "graveyard_enabler", "graveyard_finisher"),
        any_produced = c("MILL_CARD", "REANIMATE", "GRAVEYARD_TO_HAND", "RETURN_FROM_GRAVEYARD"),
        any_consumed = c("REANIMATE", "RETURN_FROM_GRAVEYARD", "GRAVEYARD_TO_HAND"),
        roles = c("setup", "converter", "payoff"),
        weight_tag = 1.1,
        weight_event = 1.0
      ),
      aristocrats = list(
        label = "Aristocrats / Sacrifice",
        description = "Token making + sacrifice outlets + death-trigger payoffs.",
        any_tags = c("sacrifice_outlet", "death_payoff", "token_producer"),
        any_produced = c("SACRIFICE_PERMANENT", "DIES", "CREATE_TOKEN"),
        any_consumed = c("DIES", "SACRIFICE_PERMANENT"),
        roles = c("engine", "converter", "payoff"),
        weight_tag = 1.2,
        weight_event = 1.0
      ),
      tokens = list(
        label = "Tokens / Go-wide",
        description = "Generate many creature tokens and reward going wide.",
        any_tags = c("token_producer", "amplifier"),
        any_produced = c("CREATE_TOKEN"),
        any_consumed = c("CREATE_TOKEN"),
        roles = c("engine", "amplifier"),
        weight_tag = 1.0,
        weight_event = 0.9
      ),
      voltron = list(
        label = "Voltron / Go-tall",
        description = "Single big creature loaded with auras/equipment.",
        any_tags = c("aura", "equipment", "amplifier"),
        any_produced = c("PUT_COUNTER", "ATTACH"),
        any_consumed = character(0),
        roles = c("amplifier", "payoff"),
        weight_tag = 1.0,
        weight_event = 0.7
      ),
      lifegain = list(
        label = "Lifegain / Drain",
        description = "Gain life as a resource and convert it into card value or damage.",
        any_tags = c("life_drain_on_opponent_draw", "lifegain_payoff", "lifelink"),
        any_produced = c("GAIN_LIFE", "LOSE_LIFE", "OPPONENT_LOSE_LIFE"),
        any_consumed = c("GAIN_LIFE"),
        roles = c("engine", "payoff"),
        weight_tag = 1.1,
        weight_event = 0.9
      ),
      spellslinger = list(
        label = "Spellslinger / Storm",
        description = "Cast many noncreature spells; reward count or copies.",
        any_tags = c("spell_enabler", "spell_payoff"),
        any_produced = c("CAST_SPELL", "NONCREATURE_SPELL_CAST"),
        any_consumed = c("CAST_SPELL", "NONCREATURE_SPELL_CAST"),
        roles = c("engine", "payoff"),
        weight_tag = 1.1,
        weight_event = 0.9
      ),
      blink = list(
        label = "Blink / Flicker / ETB",
        description = "Repeatedly trigger enter-the-battlefield abilities.",
        any_tags = c("etb_payoff", "blink_enabler"),
        any_produced = c("ETB", "EXILE_THEN_RETURN"),
        any_consumed = c("ETB"),
        roles = c("engine", "payoff"),
        weight_tag = 1.1,
        weight_event = 0.9
      ),
      counters = list(
        label = "+1/+1 Counters / Proliferate",
        description = "Place counters and amplify them via proliferate.",
        any_tags = c("counter_scaling", "amplifier"),
        any_produced = c("PUT_COUNTER", "PROLIFERATE"),
        any_consumed = c("PUT_COUNTER"),
        roles = c("engine", "amplifier", "payoff"),
        weight_tag = 1.0,
        weight_event = 0.9
      ),
      poison = list(
        label = "Poison / Infect / Toxic",
        description = "Win via poison counters, infect or toxic damage.",
        any_tags = c("toxic", "infect", "poison_payoff"),
        any_produced = c("POISON_COUNTER"),
        any_consumed = c("POISON_COUNTER"),
        roles = c("engine", "payoff"),
        weight_tag = 1.3,
        weight_event = 1.1
      ),
      artifacts = list(
        label = "Artifacts",
        description = "Artifact-themed value engines and payoffs.",
        any_tags = c("artifact_payoff", "treasure_producer"),
        any_produced = c("ARTIFACT_ETB", "TREASURE_TOKEN"),
        any_consumed = c("ARTIFACT_ETB"),
        roles = c("engine", "amplifier"),
        weight_tag = 1.0,
        weight_event = 0.9
      ),
      enchantments = list(
        label = "Enchantments",
        description = "Enchantment-themed engines, constellation, sagas.",
        any_tags = c("enchantment_payoff", "constellation"),
        any_produced = c("ENCHANTMENT_ETB"),
        any_consumed = c("ENCHANTMENT_ETB"),
        roles = c("engine", "amplifier"),
        weight_tag = 1.0,
        weight_event = 0.9
      ),
      lands = list(
        label = "Lands matter / Landfall",
        description = "Land-based engines and landfall triggers.",
        any_tags = c("landfall_payoff", "land_recursion"),
        any_produced = c("LAND_ENTERS"),
        any_consumed = c("LAND_ENTERS"),
        roles = c("engine", "payoff"),
        weight_tag = 1.1,
        weight_event = 1.0
      ),
      tribal = list(
        label = "Tribal",
        description = "Creature-type-themed synergies (Elves, Goblins, etc.).",
        any_tags = c("tribal_lord", "creature_type_matters"),
        any_produced = character(0),
        any_consumed = character(0),
        roles = c("amplifier", "payoff"),
        weight_tag = 1.0,
        weight_event = 0.5
      ),
      stax = list(
        label = "Stax / Prison / Hatebear",
        description = "Lock pieces, taxes, and asymmetric prison effects.",
        any_tags = c("stax_piece", "tax_effect", "hatebear"),
        any_produced = character(0),
        any_consumed = character(0),
        roles = c("setup", "amplifier"),
        weight_tag = 1.2,
        weight_event = 0.4
      ),
      extra_turns = list(
        label = "Extra Turns / Combats",
        description = "Take extra turns or extra combats.",
        any_tags = c("extra_turn", "extra_combat"),
        any_produced = c("EXTRA_TURN", "EXTRA_COMBAT"),
        any_consumed = character(0),
        roles = c("amplifier", "payoff"),
        weight_tag = 1.4,
        weight_event = 1.2
      ),
      wheels = list(
        label = "Wheels / Hand reset",
        description = "Discard hand and draw a new one; punish opponent draws.",
        any_tags = c("wheel", "draw_enabler", "discard_enabler"),
        any_produced = c("DRAW_CARD", "DISCARD_CARD", "OPPONENT_DRAW_CARD"),
        any_consumed = c("OPPONENT_DRAW_CARD", "DISCARD_CARD"),
        roles = c("engine", "amplifier"),
        weight_tag = 1.1,
        weight_event = 1.0
      ),
      tutors = list(
        label = "Tutors / Consistency",
        description = "Find specific cards on demand to assemble a plan.",
        any_tags = c("tutor", "search_library"),
        any_produced = c("TUTOR"),
        any_consumed = character(0),
        roles = c("setup"),
        weight_tag = 1.3,
        weight_event = 1.0
      )
    )
    registry
  }
})

# Returns a named list: archetype_key -> fit_score [0,1]
# Only returns archetypes whose fit > min_fit.
query_synergy_archetypes_for_card <- function(card, min_fit = 0.18) {
  registry <- query_synergy_archetype_registry()
  card_tags <- unique(query_synergy_to_vector(card$strategy_tags))
  produced <- unique(query_synergy_to_vector(card$produced_events))
  consumed <- unique(query_synergy_to_vector(card$consumed_events))
  roles <- unique(query_synergy_to_vector(card$roles))

  out <- list()
  for (key in names(registry)) {
    spec <- registry[[key]]
    tag_hits <- length(intersect(card_tags, spec$any_tags))
    prod_hits <- length(intersect(produced, spec$any_produced))
    cons_hits <- length(intersect(consumed, spec$any_consumed))
    role_hits <- length(intersect(roles, spec$roles))
    event_hits <- prod_hits + cons_hits

    tag_w <- query_synergy_as_num(spec$weight_tag, default = 1)
    event_w <- query_synergy_as_num(spec$weight_event, default = 0.8)
    n_tags <- max(1, length(spec$any_tags))
    n_events <- max(1, length(spec$any_produced) + length(spec$any_consumed))
    n_roles <- max(1, length(spec$roles))

    fit <- min(1,
      0.55 * tag_w * (tag_hits / n_tags) +
        0.30 * event_w * (event_hits / n_events) +
        0.15 * (role_hits / n_roles)
    )
    if (is.finite(fit) && fit >= min_fit) {
      out[[key]] <- round(fit, 3)
    }
  }
  out
}

# Returns a named list: archetype_key -> mean_fit across group members.
# Only archetypes where at least 2 members have a positive fit OR the mean
# fit is above min_group_fit are returned.
query_synergy_archetypes_for_group_members <- function(member_cards, min_group_fit = 0.12) {
  if (!is.list(member_cards) || length(member_cards) == 0L) {
    return(list())
  }
  per_member <- lapply(member_cards, function(card) {
    query_synergy_archetypes_for_card(card, min_fit = 0.06)
  })
  registry <- query_synergy_archetype_registry()
  all_keys <- names(registry)

  scores <- list()
  for (key in all_keys) {
    fits <- vapply(per_member, function(m) {
      v <- m[[key]]
      if (is.null(v)) 0 else suppressWarnings(as.numeric(v))
    }, numeric(1))
    contributors <- sum(fits > 0)
    mean_fit <- if (length(fits) > 0L) mean(fits) else 0
    if (contributors >= 2L || mean_fit >= min_group_fit) {
      scores[[key]] <- list(
        score = round(mean_fit, 3),
        contributors = contributors,
        label = registry[[key]]$label
      )
    }
  }
  # Sort by score desc.
  if (length(scores) == 0L) return(list())
  ord <- order(vapply(scores, function(e) e$score, numeric(1)), decreasing = TRUE)
  scores[ord]
}

# Computes an alignment score [0,1] between a group's detected archetypes
# and the user-selected archetype filter.  Returns:
#   - 1.0 when no filter is active (all archetypes selected or empty filter)
#   - max fit across selected archetypes otherwise
#   - 0 when the group matches none of the selected archetypes
query_synergy_group_archetype_alignment <- function(group_archetypes, selected_keys) {
  if (length(selected_keys) == 0L) return(1)
  registry_keys <- names(query_synergy_archetype_registry())
  if (length(intersect(selected_keys, registry_keys)) == length(registry_keys)) {
    # Everything selected -> treat as no filter.
    return(1)
  }
  if (length(group_archetypes) == 0L) return(0)
  hits <- vapply(selected_keys, function(key) {
    entry <- group_archetypes[[key]]
    if (is.null(entry)) 0 else suppressWarnings(as.numeric(entry$score))
  }, numeric(1))
  hits <- hits[is.finite(hits)]
  if (length(hits) == 0L) 0 else max(hits)
}

# Public listing endpoint helper.
query_synergy_archetypes_list <- function() {
  registry <- query_synergy_archetype_registry()
  lapply(names(registry), function(key) {
    spec <- registry[[key]]
    list(
      key = key,
      label = query_api_scalar(spec$label, default = key),
      description = query_api_scalar(spec$description, default = "")
    )
  })
}
