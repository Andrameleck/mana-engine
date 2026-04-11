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

test_that("scoring detects Sheoldred and Raffine synergy", {
  sheoldred <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "sheoldred",
    name = "Sheoldred, the Apocalypse",
    oracle_text = "Whenever you draw a card, you gain 2 life. Whenever an opponent draws a card, they lose 2 life.",
    colors = c("B"),
    color_identity = c("B"),
    cmc = 4,
    legalities = list(commander = "legal")
  ))

  raffine <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "raffine",
    name = "Raffine, Scheming Seer",
    oracle_text = "Flying, ward 1. Whenever you attack, target attacking creature connives X.",
    colors = c("W", "U", "B"),
    color_identity = c("W", "U", "B"),
    cmc = 3,
    legalities = list(commander = "legal")
  ))

  score <- mtgcodex.api:::query_synergy_score_pair(sheoldred, raffine, "commander")

  expect_gte(score$score, 60)
  expect_true("enabler_payoff" %in% score$relation_classes)
  expect_true(any(grepl("DRAW_CARD", score$reasons, fixed = TRUE)))
})

test_that("draw replacement is penalized against draw payoff seeds", {
  sheoldred <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "sheoldred",
    name = "Sheoldred, the Apocalypse",
    oracle_text = "Whenever you draw a card, you gain 2 life. Whenever an opponent draws a card, they lose 2 life.",
    colors = c("B"),
    color_identity = c("B"),
    cmc = 4,
    legalities = list(commander = "legal")
  ))

  raffine <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "raffine",
    name = "Raffine, Scheming Seer",
    oracle_text = "Flying, ward 1. Whenever you attack, target attacking creature connives X.",
    colors = c("W", "U", "B"),
    color_identity = c("W", "U", "B"),
    cmc = 3,
    legalities = list(commander = "legal")
  ))

  forbidden_crypt <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "forbidden-crypt",
    name = "Forbidden Crypt",
    oracle_text = "If you would draw a card, return target card from your graveyard to your hand instead.",
    colors = c("B"),
    color_identity = c("B"),
    cmc = 4,
    legalities = list(commander = "legal")
  ))

  raffine_score <- mtgcodex.api:::query_synergy_score_pair(sheoldred, raffine, "commander")
  crypt_score <- mtgcodex.api:::query_synergy_score_pair(sheoldred, forbidden_crypt, "commander")

  expect_gt(raffine_score$score, crypt_score$score)
  expect_gt(crypt_score$breakdown$replacement_penalty, 0)
  expect_true("event_conflict" %in% crypt_score$relation_classes)
})

test_that("anti synergy penalizes conflicting hand plans", {
  hand_payoff <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "hand-payoff",
    name = "Archive Sage",
    oracle_text = "You have no maximum hand size. Whenever you draw a card, gain 1 life.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 3,
    legalities = list(commander = "legal")
  ))

  discard_pressure <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "discard-pressure",
    name = "Pit of Forgetting",
    oracle_text = "At the beginning of each player's upkeep, that player discards a card.",
    colors = c("B"),
    color_identity = c("B"),
    cmc = 3,
    legalities = list(commander = "legal")
  ))

  score <- mtgcodex.api:::query_synergy_score_pair(hand_payoff, discard_pressure, "commander")

  expect_gt(score$breakdown$anti_penalty, 0)
  expect_lt(score$score, 55)
  expect_true("anti_synergy" %in% score$relation_classes)
})

test_that("synergy finder ranks Raffine for Sheoldred in a mini catalog", {
  catalog <- list(
    list(
      id = "sheoldred",
      name = "Sheoldred, the Apocalypse",
      oracle_text = "Whenever you draw a card, you gain 2 life. Whenever an opponent draws a card, they lose 2 life.",
      colors = c("B"),
      color_identity = c("B"),
      cmc = 4,
      legalities = list(commander = "legal")
    ),
    list(
      id = "raffine",
      name = "Raffine, Scheming Seer",
      oracle_text = "Flying, ward 1. Whenever you attack, target attacking creature connives X.",
      colors = c("W", "U", "B"),
      color_identity = c("W", "U", "B"),
      cmc = 3,
      legalities = list(commander = "legal")
    ),
    list(
      id = "vanilla",
      name = "Hill Giant",
      oracle_text = "",
      colors = c("R"),
      color_identity = c("R"),
      cmc = 4,
      legalities = list(commander = "legal")
    ),
    list(
      id = "forbidden-crypt",
      name = "Forbidden Crypt",
      oracle_text = "If you would draw a card, return target card from your graveyard to your hand instead.",
      colors = c("B"),
      color_identity = c("B"),
      cmc = 4,
      legalities = list(commander = "legal")
    )
  )

  payload <- list(
    card_name = "Sheoldred, the Apocalypse",
    format = "commander",
    max_results = 5
  )

  out <- mtgcodex.api:::query_synergy_find_in_catalog(payload, catalog)

  expect_true(isTRUE(out$ok))
  expect_gte(length(out$best_matches), 1)
  expect_identical(out$best_matches[[1]]$name, "Raffine, Scheming Seer")
  names_out <- vapply(out$best_matches, function(entry) entry$name, character(1))
  crypt_idx <- which(names_out == "Forbidden Crypt")
  raffine_idx <- which(names_out == "Raffine, Scheming Seer")
  expect_true(length(raffine_idx) == 1)
  if (length(crypt_idx) == 1) {
    expect_gt(crypt_idx[[1]], raffine_idx[[1]])
  } else {
    expect_true(length(crypt_idx) == 0)
  }
})
