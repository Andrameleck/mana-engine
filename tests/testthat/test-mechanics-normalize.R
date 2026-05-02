test_that("mechanic expansion handles connive", {
  card <- list(
    id = "raffine",
    name = "Raffine, Scheming Seer",
    oracle_text = "Whenever you attack, target attacking creature connives X.",
    colors = c("W", "U", "B"),
    color_identity = c("W", "U", "B"),
    cmc = 3
  )

  normalized <- mtgcodex.api:::query_synergy_normalize_card(card)

  expect_true("connive" %in% normalized$mechanics)
  expect_true("DRAW_CARD" %in% normalized$produced_events)
  expect_true("DISCARD_CARD" %in% normalized$produced_events)
})

test_that("mechanic expansion can produce structured abilities without oracle text hints", {
  rules <- mtgcodex.api:::query_synergy_build_mechanic_rules(list(
    omenwrite = list(
      keywords = c("omenwrite"),
      produced = c("DRAW_CARD"),
      strategy_tags = c("card_flow"),
      ability_templates = list(
        list(
          kind = "spell_effect",
          label = "Omenwrite",
          effects = list(
            list(role = "produce", event = "DRAW_CARD")
          ),
          references = list(plans = c("card_flow"))
        )
      )
    )
  ), base_rules = mtgcodex.api:::query_synergy_mechanic_rules_default())

  normalized <- mtgcodex.api:::query_synergy_normalize_card(
    list(
      id = "omen-card",
      name = "Omen Card",
      oracle_text = "",
      keywords = c("Omenwrite"),
      colors = c("U"),
      color_identity = c("U"),
      cmc = 2
    ),
    mechanic_rules = rules
  )

  effect_events <- unlist(lapply(normalized$abilities, function(ability) {
    vapply(ability$effects, function(effect) effect$event, character(1))
  }), use.names = FALSE)

  expect_true("omenwrite" %in% normalized$mechanics)
  expect_true("DRAW_CARD" %in% normalized$produced_events)
  expect_true(any(vapply(normalized$abilities, function(ability) ability$source == "mechanic_rule", logical(1))))
  expect_true("DRAW_CARD" %in% effect_events)
})

test_that("mechanic expansion is keyword-driven even with non-informative oracle text", {
  normalized <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "flashback-card",
    name = "Echoes From Ash",
    oracle_text = "Flavor text only.",
    keywords = c("Flashback"),
    colors = c("R"),
    color_identity = c("R"),
    cmc = 2
  ))

  expect_true("flashback" %in% normalized$mechanics)
  expect_true("CAST_SPELL" %in% normalized$produced_events)
  expect_true("MILL_CARD" %in% normalized$consumed_events)
  expect_true(any(vapply(
    Filter(function(ability) identical(ability$source, "mechanic_rule"), normalized$abilities),
    function(ability) identical(ability$mechanic, "flashback"),
    logical(1)
  )))
})

test_that("structured ability parsing is extensible through parse rules", {
  registry <- mtgcodex.api:::query_synergy_build_event_registry(
    events = list(
      treasure_created = list(
        label = "Treasure created",
        description = "A treasure token is created",
        parent = "CREATE_TOKEN",
        aliases = c("TREASURE_CREATED"),
        kind = "board_delta",
        scope = "generic",
        resource = "token",
        zones = list(from = "outside_game", to = "battlefield"),
        tags = c("tokens", "treasure")
      )
    ),
    base_registry = mtgcodex.api:::query_synergy_event_registry_default()
  )

  parse_rules <- mtgcodex.api:::query_synergy_build_ability_parse_rules(
    rules = list(
      produced_patterns = list(
        treasure_created = c("manufacture\\s+a\\s+treasure")
      )
    ),
    base_rules = mtgcodex.api:::query_synergy_ability_parse_rules_default(registry = registry),
    registry = registry
  )

  normalized <- mtgcodex.api:::query_synergy_normalize_card(
    list(
      id = "treasure-card",
      name = "Quartermaster Gearwright",
      oracle_text = "Manufacture a Treasure.",
      colors = c("R"),
      color_identity = c("R"),
      cmc = 3
    ),
    registry = registry,
    ability_parse_rules = parse_rules
  )

  parsed_abilities <- Filter(function(ability) identical(ability$source, "oracle_parse"), normalized$abilities)
  produced_effects <- unlist(lapply(parsed_abilities, function(ability) {
    vapply(Filter(function(effect) identical(effect$role, "produce"), ability$effects), function(effect) effect$event, character(1))
  }), use.names = FALSE)

  expect_true("TREASURE_CREATED" %in% normalized$produced_events)
  expect_true("TREASURE_CREATED" %in% produced_effects)
})

test_that("event registry is extensible and canonicalizes aliases", {
  base_registry <- mtgcodex.api:::query_synergy_event_registry_default()
  extended <- mtgcodex.api:::query_synergy_build_event_registry(
    events = list(
      artifact_etb = list(
        label = "Artifact ETB",
        description = "An artifact enters the battlefield",
        parent = "ETB",
        aliases = c("ARTIFACT_ENTERS", "artifact enters the battlefield"),
        kind = "zone_change",
        scope = "artifact",
        resource = "artifact",
        zones = list(from = "stack", to = "battlefield"),
        tags = c("artifact", "battlefield")
      )
    ),
    base_registry = base_registry
  )

  expect_true("ARTIFACT_ETB" %in% names(extended$events))
  expect_identical(extended$events$ARTIFACT_ETB$parent, "ETB")
  expect_identical(extended$alias_to_id$ARTIFACT_ENTERS, "ARTIFACT_ETB")
  expect_identical(
    mtgcodex.api:::query_synergy_canonicalize_events("artifact enters the battlefield", extended),
    "ARTIFACT_ETB"
  )
})

test_that("normalized card model exposes generalized mechanical roles", {
  card <- list(
    id = "raffine",
    name = "Raffine, Scheming Seer",
    oracle_text = "Flying, ward 1. Whenever you attack, target attacking creature connives X.",
    type_line = "Legendary Creature - Sphinx Demon",
    colors = c("W", "U", "B"),
    color_identity = c("W", "U", "B"),
    cmc = 3
  )

  normalized <- mtgcodex.api:::query_synergy_normalize_card(card)
  produced_ids <- vapply(normalized$produces, function(entry) entry$event, character(1))
  ability_kinds <- vapply(normalized$abilities, function(entry) entry$kind, character(1))

  expect_identical(normalized$model_version, "normalized_card_v2")
  expect_true(is.list(normalized$abilities))
  expect_true(is.list(normalized$produces))
  expect_true(is.list(normalized$plans))
  expect_true("mechanic" %in% ability_kinds)
  expect_true("DRAW_CARD" %in% produced_ids)
  expect_true("draw_discard" %in% normalized$plans$tags)
  expect_true("producer" %in% normalized$roles)
  expect_true("setup" %in% normalized$roles)
  expect_true("creature_card" %in% normalized$target_roles)
})

test_that("structured ability parsing captures directional triggers and effects", {
  normalized <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "sheoldred",
    name = "Sheoldred, the Apocalypse",
    oracle_text = "Whenever you draw a card, you gain 2 life. Whenever an opponent draws a card, they lose 2 life.",
    colors = c("B"),
    color_identity = c("B"),
    cmc = 4
  ))

  parsed_abilities <- Filter(function(ability) identical(ability$source, "oracle_parse"), normalized$abilities)
  reward_effects <- unlist(lapply(parsed_abilities, function(ability) {
    vapply(Filter(function(effect) identical(effect$role, "reward"), ability$effects), function(effect) effect$event, character(1))
  }), use.names = FALSE)
  produce_effects <- unlist(lapply(parsed_abilities, function(ability) {
    vapply(Filter(function(effect) identical(effect$role, "produce"), ability$effects), function(effect) effect$event, character(1))
  }), use.names = FALSE)

  expect_gte(length(parsed_abilities), 2)
  expect_true(all(vapply(parsed_abilities, function(ability) ability$kind == "triggered", logical(1))))
  expect_true("SELF_DRAW_CARD" %in% reward_effects)
  expect_true("OPPONENT_DRAW_CARD" %in% reward_effects)
  expect_true("GAIN_LIFE" %in% produce_effects)
  expect_true("LOSE_LIFE" %in% produce_effects)
})

test_that("structured ability parsing distinguishes replacement from raw text mention", {
  normalized <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "stinkweed",
    name = "Stinkweed Imp",
    oracle_text = "Flying. Dredge 5 (If you would draw a card, instead you may mill five cards and return this card from your graveyard to your hand.)",
    colors = c("B"),
    color_identity = c("B"),
    cmc = 3
  ))

  replacement_abilities <- Filter(function(ability) identical(ability$kind, "replacement"), normalized$abilities)
  replace_effects <- unlist(lapply(replacement_abilities, function(ability) {
    vapply(Filter(function(effect) identical(effect$role, "replace"), ability$effects), function(effect) effect$event, character(1))
  }), use.names = FALSE)

  expect_gte(length(replacement_abilities), 1)
  expect_true("DRAW_CARD" %in% replace_effects)
  expect_false(any(vapply(replacement_abilities, function(ability) {
    any(vapply(Filter(function(effect) identical(effect$role, "produce"), ability$effects), function(effect) effect$event == "DRAW_CARD", logical(1)))
  }, logical(1))))
})

test_that("oracle extraction captures Sheoldred draw payoffs", {
  card <- list(
    id = "sheoldred",
    name = "Sheoldred, the Apocalypse",
    oracle_text = "Whenever you draw a card, you gain 2 life. Whenever an opponent draws a card, they lose 2 life.",
    colors = c("B"),
    color_identity = c("B"),
    cmc = 4
  )

  normalized <- mtgcodex.api:::query_synergy_normalize_card(card)

  expect_true("SELF_DRAW_CARD" %in% normalized$consumed_events)
  expect_true("OPPONENT_DRAW_CARD" %in% normalized$consumed_events)
  expect_true("GAIN_LIFE" %in% normalized$produced_events)
})

test_that("replacement effects are not treated as produced draw", {
  card <- list(
    id = "forbidden-crypt",
    name = "Forbidden Crypt",
    oracle_text = "If you would draw a card, return target card from your graveyard to your hand instead.",
    colors = c("B"),
    color_identity = c("B"),
    cmc = 4
  )

  normalized <- mtgcodex.api:::query_synergy_normalize_card(card)

  expect_true("DRAW_CARD" %in% normalized$replaced_events)
  expect_false("DRAW_CARD" %in% normalized$produced_events)
  expect_false("DRAW_CARD" %in% normalized$consumed_events)
})

test_that("normalized card model preserves zone moves from generalized ontology", {
  card <- list(
    id = "stinkweed",
    name = "Stinkweed Imp",
    oracle_text = "Flying. Dredge 5 (If you would draw a card, instead you may mill five cards and return this card from your graveyard to your hand.)",
    type_line = "Creature - Imp",
    colors = c("B"),
    color_identity = c("B"),
    cmc = 3
  )

  normalized <- mtgcodex.api:::query_synergy_normalize_card(card)
  move_pairs <- vapply(normalized$moves, function(entry) paste(entry$from, entry$to, sep = "->"), character(1))

  expect_true("DRAW_CARD" %in% normalized$replaced_events)
  expect_true("GRAVEYARD_TO_HAND" %in% normalized$produced_events)
  expect_true("graveyard->hand" %in% move_pairs)
  expect_true("mover" %in% normalized$roles)
  expect_true("replacer" %in% normalized$roles)
})

