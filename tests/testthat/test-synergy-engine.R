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

test_that("pairwise scoring exposes directional explanations", {
  target <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "draw-payoff",
    name = "Scholar of Echoes",
    oracle_text = "Whenever you draw a card, gain 1 life.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 3,
    legalities = list(commander = "legal")
  ))

  candidate <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "draw-engine",
    name = "Engine of Insight",
    oracle_text = "Draw two cards, then discard a card.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 2,
    legalities = list(commander = "legal")
  ))

  score <- mtgcodex.api:::query_synergy_score_pair(target, candidate, "commander")

  expect_true(is.list(score$directional))
  expect_true("DRAW_CARD" %in% score$directional$candidate_to_target$matched_events)
  expect_true(grepl("enables", score$directional$candidate_to_target$reason, fixed = TRUE))
  expect_true(any(grepl("Produces DRAW_CARD", score$reasons, fixed = TRUE)))
})

test_that("anti synergy detection explains graveyard tension", {
  graveyard_payoff <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "graveyard-engine",
    name = "Sepulchral Scholar",
    oracle_text = "Return target card from your graveyard to your hand.",
    colors = c("B"),
    color_identity = c("B"),
    cmc = 3,
    legalities = list(commander = "legal")
  ))

  graveyard_hate <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "graveyard-hate",
    name = "Sanctified Lantern",
    oracle_text = "Exile all graveyards.",
    colors = c("W"),
    color_identity = c("W"),
    cmc = 2,
    legalities = list(commander = "legal")
  ))

  score <- mtgcodex.api:::query_synergy_score_pair(graveyard_payoff, graveyard_hate, "commander")

  expect_true("anti_synergy" %in% score$relation_classes)
  expect_true("plan_conflict" %in% score$relation_classes)
  expect_true(any(grepl("graveyard", score$reasons, ignore.case = TRUE)))
  expect_true(any(grepl("GRAVEYARD_DEPENDENT", score$matched_events$anti_conflicts, fixed = TRUE)))
})

test_that("structured synergy groups detect a three card draw discard line", {
  payoff <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "payoff",
    name = "Archive Judge",
    oracle_text = "Whenever you draw a card, gain 1 life.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 3,
    legalities = list(commander = "legal")
  ))

  setup <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "setup",
    name = "Frantic Research",
    oracle_text = "Draw two cards, then discard two cards.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 2,
    legalities = list(commander = "legal")
  ))

  converter <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "converter",
    name = "Lore Recycler",
    oracle_text = "Whenever you discard a card, draw a card.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 2,
    legalities = list(commander = "legal")
  ))

  groups <- mtgcodex.api:::query_synergy_detect_groups_for_seed(
    seed = payoff,
    candidates = list(setup, converter),
    format_name = "commander",
    min_edge_score = 10,
    max_groups = 3,
    max_group_size = 4,
    max_paths = 30
  )

  expect_gte(length(groups$groups), 1)
  group_match <- Filter(function(group) {
    roles <- vapply(group$members, function(member) member$inferred_role, character(1))
    length(group$members) == 3L &&
      any(c("DRAW_CARD", "DISCARD_CARD") %in% group$matched_events) &&
      any(roles %in% c("engine", "converter")) &&
      utils::tail(roles, 1L) %in% c("payoff", "finisher", "target")
  }, groups$groups)

  expect_gte(length(group_match), 1)
  expect_true(is.list(group_match[[1]]$line$edges))
  expect_true(is.list(group_match[[1]]$package_structure))
  expect_identical(group_match[[1]]$package_structure$intermediate_count, 1L)
  expect_gt(group_match[[1]]$score_breakdown$chain_continuity, 0)
})

test_that("engine fuel payoff groups surface as indirect packages", {
  payoff <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "archive-payoff",
    name = "Archive Judge",
    oracle_text = "Whenever you draw a card, gain 1 life.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 3,
    legalities = list(commander = "legal")
  ))

  fuel <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "fuel",
    name = "Frantic Research",
    oracle_text = "Draw two cards, then discard two cards.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 2,
    legalities = list(commander = "legal")
  ))

  engine <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "engine",
    name = "Lore Recycler",
    oracle_text = "Whenever you discard a card, draw a card.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 2,
    legalities = list(commander = "legal")
  ))

  groups <- mtgcodex.api:::query_synergy_detect_groups_for_seed(
    seed = payoff,
    candidates = list(fuel, engine),
    format_name = "commander",
    min_edge_score = 10,
    max_groups = 3,
    max_group_size = 4,
    max_paths = 30
  )

  expect_gte(length(groups$groups), 1)
  expect_true(any(vapply(groups$groups, function(group) {
    roles <- vapply(group$members, function(member) member$inferred_role, character(1))
    any(roles %in% c("fuel", "setup")) && any(roles %in% c("engine", "converter"))
  }, logical(1))))
})

test_that("group search supports A plus two intermediates plus B package lines", {
  payoff <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "token-payoff",
    name = "Token Auditor",
    oracle_text = "Whenever you create a token, gain 1 life.",
    colors = c("W"),
    color_identity = c("W"),
    cmc = 3,
    legalities = list(commander = "legal")
  ))

  setup <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "seed-setup",
    name = "Frantic Research",
    oracle_text = "Draw two cards, then discard two cards.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 2,
    legalities = list(commander = "legal")
  ))

  bridge_a <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "discard-engine",
    name = "Lore Recycler",
    oracle_text = "Whenever you discard a card, draw a card.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 2,
    legalities = list(commander = "legal")
  ))

  bridge_b <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "draw-converter",
    name = "Spark Provisioner",
    oracle_text = "Whenever you draw a card, create a Treasure token.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 3,
    legalities = list(commander = "legal")
  ))

  groups <- mtgcodex.api:::query_synergy_detect_groups_for_seed(
    seed = payoff,
    candidates = list(setup, bridge_a, bridge_b),
    format_name = "commander",
    min_edge_score = 8,
    max_groups = 4,
    max_group_size = 4,
    max_paths = 48
  )

  expect_gte(length(groups$groups), 1)
  expect_true(any(vapply(groups$groups, function(group) {
    member_ids <- vapply(group$members, function(member) member$id, character(1))
    has_all_cards <- all(c("seed-setup", "discard-engine", "draw-converter", "token-payoff") %in% member_ids)
    has_four_cards <- length(group$members) == 4L
    has_two_intermediates <- suppressWarnings(as.integer(group$package_structure$intermediate_count)) == 2L
    chain_hits <- intersect(
      c("DISCARD_CARD", "DRAW_CARD", "CREATE_TOKEN", "GRAVEYARD_FUEL", "BATTLEFIELD_RESOURCE"),
      group$matched_events
    )
    has_chain <- length(chain_hits) >= 3L
    has_all_cards && has_four_cards && has_two_intermediates && has_chain
  }, logical(1))))
})

test_that("graveyard reanimation groups use resource and zone chains", {
  payoff <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "grave-payoff",
    name = "Ancient Colossus",
    oracle_text = "",
    type_line = "Creature - Giant",
    colors = c("B"),
    color_identity = c("B"),
    cmc = 7,
    legalities = list(commander = "legal")
  ))

  setup <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "grave-setup",
    name = "Tomb Survey",
    oracle_text = "Mill three cards.",
    colors = c("B"),
    color_identity = c("B"),
    cmc = 1,
    legalities = list(commander = "legal")
  ))

  converter <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "grave-converter",
    name = "Ash Script",
    oracle_text = "Return target creature card from your graveyard to the battlefield.",
    colors = c("B"),
    color_identity = c("B"),
    cmc = 2,
    legalities = list(commander = "legal")
  ))

  groups <- mtgcodex.api:::query_synergy_detect_groups_for_seed(
    seed = payoff,
    candidates = list(setup, converter),
    format_name = "commander",
    min_edge_score = 10,
    max_groups = 3,
    max_group_size = 4,
    max_paths = 30
  )

  expect_gte(length(groups$groups), 1)
  expect_true(any(vapply(groups$groups, function(group) {
    any(c("GRAVEYARD_FUEL", "REANIMATE", "BATTLEFIELD_RESOURCE") %in% group$matched_events) &&
      identical(utils::tail(vapply(group$members, function(member) member$inferred_role, character(1)), 1L), "target")
  }, logical(1))))
})

test_that("synergy finder returns bucketed output with explainable axes", {
  catalog <- list(
    list(
      id = "seed",
      name = "Ledger Saint",
      oracle_text = "Whenever you draw a card, gain 1 life.",
      colors = c("U"),
      color_identity = c("U"),
      cmc = 3,
      legalities = list(commander = "legal")
    ),
    list(
      id = "direct",
      name = "Thought Current",
      oracle_text = "Draw two cards.",
      colors = c("U"),
      color_identity = c("U"),
      cmc = 2,
      legalities = list(commander = "legal")
    ),
    list(
      id = "indirect",
      name = "Rooftop Conniver",
      oracle_text = "Whenever you attack, target attacking creature connives 1.",
      colors = c("U"),
      color_identity = c("U"),
      cmc = 3,
      legalities = list(commander = "legal")
    ),
    list(
      id = "warning",
      name = "Closed Archive",
      oracle_text = "If you would draw a card, exile the top card of your library instead.",
      colors = c("U"),
      color_identity = c("U"),
      cmc = 2,
      legalities = list(commander = "legal")
    )
  )

  out <- mtgcodex.api:::query_synergy_find_in_catalog(
    list(card_name = "Ledger Saint", format = "commander", max_results = 6),
    catalog
  )

  expect_true(isTRUE(out$ok))
  expect_true(is.list(out$buckets))
  expect_true(all(c("direct_enablers", "indirect_engines", "reciprocal_value_cards", "anti_synergy_warnings", "synergy_groups", "package_lines", "packages") %in% names(out$buckets)))
  expect_gte(length(out$best_matches), 1)
  expect_true(is.character(out$best_matches[[1]]$bucket))
  expect_true(is.list(out$best_matches[[1]]$axis_scores))
  expect_true(is.character(out$best_matches[[1]]$explanation_text))
  expect_true(is.character(out$best_matches[[1]]$roles))
  expect_true(is.list(out$synergy_groups))
  expect_true(is.numeric(out$group_count) || is.integer(out$group_count))
})

test_that("token sacrifice death groups detect converter bridge payoff", {
  payoff <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "death-payoff",
    name = "Mortuary Ledger",
    oracle_text = "Whenever a creature dies, draw a card.",
    colors = c("B"),
    color_identity = c("B"),
    cmc = 4,
    legalities = list(commander = "legal")
  ))

  setup <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "token-maker",
    name = "Call the Ranks",
    oracle_text = "Create two 1/1 white Soldier creature tokens.",
    colors = c("W"),
    color_identity = c("W"),
    cmc = 2,
    legalities = list(commander = "legal")
  ))

  converter <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "sac-outlet",
    name = "Ash Altar Adept",
    oracle_text = "Sacrifice a creature: Add {B}.",
    colors = c("B"),
    color_identity = c("B"),
    cmc = 2,
    legalities = list(commander = "legal")
  ))

  groups <- mtgcodex.api:::query_synergy_detect_groups_for_seed(
    seed = payoff,
    candidates = list(setup, converter),
    format_name = "commander",
    min_edge_score = 10,
    max_groups = 3,
    max_group_size = 4,
    max_paths = 30
  )

  expect_gte(length(groups$groups), 1)
  expect_true(any(vapply(groups$groups, function(group) {
    any(c("CREATE_TOKEN", "TOKEN_CREATED") %in% group$matched_events) &&
      any(c("SACRIFICE_PERMANENT", "DIES", "CREATURE_DIES") %in% group$matched_events)
  }, logical(1))))
})

test_that("anti synergy inside groups is penalized and explained", {
  payoff <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "payoff",
    name = "Archive Judge",
    oracle_text = "Whenever you draw a card, gain 1 life.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 3,
    legalities = list(commander = "legal")
  ))

  setup <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "setup",
    name = "Frantic Research",
    oracle_text = "Draw two cards, then discard two cards.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 2,
    legalities = list(commander = "legal")
  ))

  conflicted_engine <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "conflicted-engine",
    name = "Paradox Archivist",
    oracle_text = "Whenever you discard a card, draw a card. If you would draw a card, exile the top card of your library instead.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 2,
    legalities = list(commander = "legal")
  ))

  groups <- mtgcodex.api:::query_synergy_detect_groups_for_seed(
    seed = payoff,
    candidates = list(setup, conflicted_engine),
    format_name = "commander",
    min_edge_score = 5,
    max_groups = 3,
    max_group_size = 4,
    max_paths = 30
  )

  expect_gte(length(groups$groups), 1)
  flagged <- Filter(function(group) {
    suppressWarnings(as.numeric(group$score_breakdown$anti_synergy_penalty)) > 0 &&
      any(grepl("Anti-synergy penalty", group$reasons, fixed = TRUE))
  }, groups$groups)
  expect_gte(length(flagged), 1)
})

test_that("indirect engine scoring is structure driven rather than name driven", {
  target <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "seed-draw",
    name = "Sage of Copies",
    oracle_text = "Whenever you draw a card, gain 1 life.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 3,
    legalities = list(commander = "legal")
  ))

  engine_a <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "engine-a",
    name = "Alpha Broker",
    oracle_text = "Whenever you attack, target attacking creature connives 1.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 3,
    legalities = list(commander = "legal")
  ))

  engine_b <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "engine-b",
    name = "Beta Broker",
    oracle_text = "Whenever you attack, target attacking creature connives 1.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 3,
    legalities = list(commander = "legal")
  ))

  score_a <- mtgcodex.api:::query_synergy_score_pair(target, engine_a, "commander")
  score_b <- mtgcodex.api:::query_synergy_score_pair(target, engine_b, "commander")

  expect_identical(score_a$primary_bucket, score_b$primary_bucket)
  expect_equal(score_a$axis_scores, score_b$axis_scores)
  expect_identical(score_a$score, score_b$score)
})

test_that("replacement conflicts surface in anti synergy warnings", {
  catalog <- list(
    list(
      id = "seed",
      name = "Ledger Saint",
      oracle_text = "Whenever you draw a card, gain 1 life.",
      colors = c("U"),
      color_identity = c("U"),
      cmc = 3,
      legalities = list(commander = "legal")
    ),
    list(
      id = "direct",
      name = "Thought Current",
      oracle_text = "Draw two cards.",
      colors = c("U"),
      color_identity = c("U"),
      cmc = 2,
      legalities = list(commander = "legal")
    ),
    list(
      id = "warning",
      name = "Closed Archive",
      oracle_text = "If you would draw a card, exile the top card of your library instead.",
      colors = c("U"),
      color_identity = c("U"),
      cmc = 2,
      legalities = list(commander = "legal")
    )
  )

  out <- mtgcodex.api:::query_synergy_find_in_catalog(
    list(card_name = "Ledger Saint", format = "commander", max_results = 6),
    catalog
  )

  anti_bucket <- out$buckets$anti_synergy_warnings
  expect_true(is.list(anti_bucket))
  expect_gte(anti_bucket$count, 1)
  expect_true(any(vapply(anti_bucket$results, function(entry) identical(entry$name, "Closed Archive"), logical(1))))

  warning_entry <- Filter(function(entry) identical(entry$name, "Closed Archive"), anti_bucket$results)[[1]]
  expect_identical(warning_entry$bucket, "anti_synergy_warnings")
  expect_true("DRAW_CARD" %in% warning_entry$matched_events$replaces_payoff)
})

test_that("catalog cache key changes when middle card content changes", {
  catalog_a <- list(
    list(id = "seed", name = "Seed", oracle_text = "Draw a card.", color_identity = c("U")),
    list(id = "middle-a", name = "Middle A", oracle_text = "Mill two cards.", color_identity = c("U")),
    list(id = "tail", name = "Tail", oracle_text = "Gain 1 life.", color_identity = c("W"))
  )
  catalog_b <- list(
    list(id = "seed", name = "Seed", oracle_text = "Draw a card.", color_identity = c("U")),
    list(id = "middle-b", name = "Middle B", oracle_text = "Create a token.", color_identity = c("W")),
    list(id = "tail", name = "Tail", oracle_text = "Gain 1 life.", color_identity = c("W"))
  )

  key_a <- mtgcodex.api:::query_synergy_catalog_cache_key(catalog_a, source = "catalog")
  key_b <- mtgcodex.api:::query_synergy_catalog_cache_key(catalog_b, source = "catalog")

  expect_false(identical(key_a, key_b))
})

test_that("canonical catalog cache key can use cheap file signatures", {
  catalog <- list(
    list(id = "seed", name = "Seed", oracle_text = "Draw a card.", color_identity = c("U")),
    list(id = "tail", name = "Tail", oracle_text = "Gain 1 life.", color_identity = c("W"))
  )

  key_a <- mtgcodex.api:::query_synergy_catalog_cache_key(
    catalog,
    source = "scryfall_oracle_cards",
    source_signature = "100::200"
  )
  key_b <- mtgcodex.api:::query_synergy_catalog_cache_key(
    catalog,
    source = "scryfall_oracle_cards",
    source_signature = "100::200"
  )
  key_c <- mtgcodex.api:::query_synergy_catalog_cache_key(
    catalog,
    source = "scryfall_oracle_cards",
    source_signature = "100::201"
  )

  expect_identical(key_a, key_b)
  expect_false(identical(key_a, key_c))
})

test_that("staged pipeline scans full catalog but deep scores only top k", {
  catalog <- c(
    list(list(
      id = "seed",
      name = "Ledger Saint",
      oracle_text = "Whenever you draw a card, gain 1 life.",
      colors = c("U"),
      color_identity = c("U"),
      cmc = 3,
      legalities = list(commander = "legal")
    )),
    lapply(seq_len(8), function(i) {
      list(
        id = paste0("noise-", i),
        name = paste("Noise", i),
        oracle_text = "",
        colors = c("G"),
        color_identity = c("G"),
        cmc = 3 + i,
        legalities = list(commander = "legal")
      )
    }),
    list(
      list(
        id = "direct",
        name = "Thought Current",
        oracle_text = "Draw two cards.",
        colors = c("U"),
        color_identity = c("U"),
        cmc = 2,
        legalities = list(commander = "legal")
      ),
      list(
        id = "indirect",
        name = "Rooftop Conniver",
        oracle_text = "Whenever you attack, target attacking creature connives 1.",
        colors = c("U"),
        color_identity = c("U"),
        cmc = 3,
        legalities = list(commander = "legal")
      ),
      list(
        id = "warning",
        name = "Closed Archive",
        oracle_text = "If you would draw a card, exile the top card of your library instead.",
        colors = c("U"),
        color_identity = c("U"),
        cmc = 2,
        legalities = list(commander = "legal")
      )
    )
  )

  out <- mtgcodex.api:::query_synergy_find_in_catalog(
    list(card_name = "Ledger Saint", format = "commander", max_results = 5, top_k = 3, package_top_n = 2),
    catalog
  )

  expect_true(isTRUE(out$ok))
  expect_identical(out$pipeline$catalog_size, length(catalog))
  expect_identical(out$pipeline$candidate_filter_count, length(catalog) - 1L)
  expect_gte(out$pipeline$candidate_filter_count, 3L)
  expect_identical(out$pipeline$cheap_scan_count, out$pipeline$candidate_filter_count)
  expect_true(isTRUE(out$pipeline$full_catalog_light_scan))
  expect_identical(out$pipeline$cheap_scan_cap_used, out$pipeline$candidate_filter_count)
  expect_identical(out$pipeline$deep_score_count, 3L)
  expect_identical(out$pipeline$top_k_used, 3L)
  expect_lte(out$pipeline$package_candidate_count, 2L)
  expect_true(all(c(
    "precompute_load_ms",
    "candidate_filter_ms",
    "cheap_scan_ms",
    "deep_scoring_ms",
    "bucket_assembly_ms",
    "package_detection_ms",
    "response_assembly_ms",
    "total_ms"
  ) %in% names(out$timings)))
})

test_that("staged candidate generation keeps indirect engine candidates alive", {
  catalog <- list(
    list(
      id = "seed",
      name = "Ledger Saint",
      oracle_text = "Whenever you draw a card, gain 1 life.",
      colors = c("U"),
      color_identity = c("U"),
      cmc = 3,
      legalities = list(commander = "legal")
    ),
    list(
      id = "direct",
      name = "Thought Current",
      oracle_text = "Draw two cards.",
      colors = c("U"),
      color_identity = c("U"),
      cmc = 2,
      legalities = list(commander = "legal")
    ),
    list(
      id = "indirect",
      name = "Rooftop Conniver",
      oracle_text = "Whenever you attack, target attacking creature connives 1.",
      colors = c("U"),
      color_identity = c("U"),
      cmc = 3,
      legalities = list(commander = "legal")
    ),
    list(
      id = "noise-a",
      name = "Timber Filler",
      oracle_text = "Target land becomes a creature until end of turn.",
      colors = c("G"),
      color_identity = c("G"),
      cmc = 3,
      legalities = list(commander = "legal")
    ),
    list(
      id = "noise-b",
      name = "Stone Filler",
      oracle_text = "Create a tapped colorless land token.",
      colors = c("C"),
      color_identity = c("C"),
      cmc = 4,
      legalities = list(commander = "legal")
    )
  )

  out <- mtgcodex.api:::query_synergy_find_in_catalog(
    list(card_name = "Ledger Saint", format = "commander", max_results = 4, top_k = 2, package_top_n = 2),
    catalog
  )

  result_names <- vapply(out$best_matches, function(entry) entry$name, character(1))
  expect_true("Rooftop Conniver" %in% result_names)
  expect_true(any(vapply(out$buckets$indirect_engines$results, function(entry) identical(entry$name, "Rooftop Conniver"), logical(1))))
})

test_that("explicit cheap scan cap limits lightweight scan breadth when requested", {
  catalog <- c(
    list(list(
      id = "seed",
      name = "Ledger Saint",
      oracle_text = "Whenever you draw a card, gain 1 life.",
      colors = c("U"),
      color_identity = c("U"),
      cmc = 3,
      legalities = list(commander = "legal")
    )),
    lapply(seq_len(24), function(i) {
      list(
        id = paste0("broad-", i),
        name = paste("Broad", i),
        oracle_text = "Gain 1 life.",
        colors = c("W"),
        color_identity = c("W"),
        cmc = 2,
        legalities = list(commander = "legal")
      )
    }),
    list(
      list(
        id = "direct",
        name = "Thought Current",
        oracle_text = "Draw two cards.",
        colors = c("U"),
        color_identity = c("U"),
        cmc = 2,
        legalities = list(commander = "legal")
      ),
      list(
        id = "indirect",
        name = "Rooftop Conniver",
        oracle_text = "Whenever you attack, target attacking creature connives 1.",
        colors = c("U"),
        color_identity = c("U"),
        cmc = 3,
        legalities = list(commander = "legal")
      )
    )
  )

  out <- mtgcodex.api:::query_synergy_find_in_catalog(
    list(
      card_name = "Ledger Saint",
      format = "commander",
      max_results = 4,
      top_k = 2,
      cheap_scan_cap = 8,
      package_top_n = 2
    ),
    catalog
  )

  result_names <- vapply(out$best_matches, function(entry) entry$name, character(1))
  expect_gt(out$pipeline$candidate_filter_count, out$pipeline$cheap_scan_count)
  expect_identical(out$pipeline$cheap_scan_count, 8L)
  expect_identical(out$pipeline$cheap_scan_cap_used, 8L)
  expect_true("Thought Current" %in% result_names)
})

test_that("group search stays constrained to the reduced local candidate graph", {
  catalog <- c(
    list(list(
      id = "seed",
      name = "Archive Judge",
      oracle_text = "Whenever you draw a card, gain 1 life.",
      colors = c("U"),
      color_identity = c("U"),
      cmc = 3,
      legalities = list(commander = "legal")
    )),
    lapply(seq_len(16), function(i) {
      list(
        id = paste0("noise-", i),
        name = paste("Noise", i),
        oracle_text = "Gain 1 life.",
        colors = c("W"),
        color_identity = c("W"),
        cmc = 2,
        legalities = list(commander = "legal")
      )
    }),
    list(
      list(
        id = "setup",
        name = "Frantic Research",
        oracle_text = "Draw two cards, then discard two cards.",
        colors = c("U"),
        color_identity = c("U"),
        cmc = 2,
        legalities = list(commander = "legal")
      ),
      list(
        id = "converter",
        name = "Lore Recycler",
        oracle_text = "Whenever you discard a card, draw a card.",
        colors = c("U"),
        color_identity = c("U"),
        cmc = 2,
        legalities = list(commander = "legal")
      ),
      list(
        id = "warning",
        name = "Closed Archive",
        oracle_text = "If you would draw a card, exile the top card of your library instead.",
        colors = c("U"),
        color_identity = c("U"),
        cmc = 2,
        legalities = list(commander = "legal")
      )
    )
  )

  out <- mtgcodex.api:::query_synergy_find_in_catalog(
    list(
      card_name = "Archive Judge",
      format = "commander",
      max_results = 6,
      top_k = 4,
      package_top_n = 4,
      max_groups = 3,
      max_group_size = 4,
      max_group_paths = 20
    ),
    catalog
  )

  expect_true(isTRUE(out$ok))
  expect_lte(out$pipeline$group_graph_node_count, out$pipeline$package_candidate_count + 1L)
  expect_lte(out$pipeline$group_path_count, 20L)
  expect_gte(out$pipeline$group_graph_edge_count, 0L)
  expect_lte(
    out$pipeline$group_graph_pair_count,
    (out$pipeline$package_candidate_count + 1L) * max(0L, out$pipeline$package_candidate_count)
  )
  expect_lt(out$pipeline$group_graph_pair_count, length(catalog) * max(0L, length(catalog) - 1L))
  expect_gte(out$pipeline$group_branching_cap_used, 1L)
})

test_that("precomputed catalog cache persists normalized profiles for canonical sources", {
  catalog <- list(
    list(
      id = "seed",
      name = "Ledger Saint",
      oracle_text = "Whenever you draw a card, gain 1 life.",
      colors = c("U"),
      color_identity = c("U"),
      cmc = 3,
      legalities = list(commander = "legal")
    ),
    list(
      id = "direct",
      name = "Thought Current",
      oracle_text = "Draw two cards.",
      colors = c("U"),
      color_identity = c("U"),
      cmc = 2,
      legalities = list(commander = "legal")
    ),
    list(
      id = "warning",
      name = "Closed Archive",
      oracle_text = "If you would draw a card, exile the top card of your library instead.",
      colors = c("U"),
      color_identity = c("U"),
      cmc = 2,
      legalities = list(commander = "legal")
    )
  )

  cache_dir <- file.path(tempdir(), paste0("synergy-precompute-", as.integer(Sys.time())))
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  attr(catalog, "synergy_source") <- "scryfall_oracle_cards"
  attr(catalog, "synergy_cache_key") <- mtgcodex.api:::query_synergy_catalog_cache_key(catalog, source = "scryfall_oracle_cards")

  precomputed <- mtgcodex.api:::query_synergy_get_precomputed_catalog(
    catalog = catalog,
    force_refresh = TRUE,
    cache_dir = cache_dir
  )

  paths <- mtgcodex.api:::query_synergy_cache_paths(cache_dir)
  expect_true(file.exists(paths$precomputed_rds_file))
  expect_identical(length(precomputed$normalized), length(catalog))
  expect_identical(length(precomputed$profiles), length(catalog))
  expect_true(is.list(precomputed$indexes))
})

test_that("progress callback reports backend-linked staged progress", {
  catalog <- list(
    list(
      id = "seed",
      name = "Ledger Saint",
      oracle_text = "Whenever you draw a card, gain 1 life.",
      colors = c("U"),
      color_identity = c("U"),
      cmc = 3,
      legalities = list(commander = "legal")
    ),
    list(
      id = "direct",
      name = "Thought Current",
      oracle_text = "Draw two cards.",
      colors = c("U"),
      color_identity = c("U"),
      cmc = 2,
      legalities = list(commander = "legal")
    ),
    list(
      id = "indirect",
      name = "Rooftop Conniver",
      oracle_text = "Whenever you attack, target attacking creature connives 1.",
      colors = c("U"),
      color_identity = c("U"),
      cmc = 3,
      legalities = list(commander = "legal")
    ),
    list(
      id = "warning",
      name = "Closed Archive",
      oracle_text = "If you would draw a card, exile the top card of your library instead.",
      colors = c("U"),
      color_identity = c("U"),
      cmc = 2,
      legalities = list(commander = "legal")
    )
  )

  progress_log <- list()
  callback <- function(progress) {
    progress_log[[length(progress_log) + 1L]] <<- progress
  }

  out <- mtgcodex.api:::query_synergy_find_in_catalog(
    list(card_name = "Ledger Saint", format = "commander", max_results = 4, top_k = 2, package_top_n = 2),
    catalog,
    progress_callback = callback
  )

  expect_true(isTRUE(out$ok))
  expect_gte(length(progress_log), 5)

  percents <- vapply(progress_log, function(entry) as.integer(round(as.numeric(entry$percent))), integer(1))
  stages <- vapply(progress_log, function(entry) as.character(entry$stage), character(1))

  expect_true(all(diff(percents) >= 0))
  expect_identical(utils::tail(percents, 1), 100L)
  expect_true(any(grepl("Scanning full catalog", stages, fixed = TRUE)))
  expect_true(any(grepl("Deep scoring top candidates", stages, fixed = TRUE)))
  expect_true(any(grepl("Detecting package lines", stages, fixed = TRUE)))
})

test_that("completed job status waits until the result payload is readable", {
  jobs_dir <- file.path(tempdir(), paste0("synergy-jobs-", as.integer(Sys.time()), "-", sample.int(9999, 1)))
  mtgcodex.api:::query_synergy_jobs_dir(base_dir = jobs_dir)

  job_id <- "job-finalizing"
  paths <- mtgcodex.api:::query_synergy_job_paths(job_id)
  mtgcodex.api:::query_synergy_write_job_json(
    paths$status_file,
    mtgcodex.api:::query_synergy_build_job_status(
      job_id = job_id,
      status = "completed",
      percent = 100,
      stage = "Completed"
    )
  )

  pending <- mtgcodex.api:::query_synergy_get_job_status(job_id)
  expect_identical(pending$status, "running")
  expect_identical(pending$progress$percent, 99L)
  expect_identical(pending$progress$stage, "Finalizing result")

  mtgcodex.api:::query_synergy_write_job_json(
    paths$result_file,
    list(ok = TRUE, best_matches = list(list(id = "card-a", name = "Card A")), synergy_groups = list())
  )

  completed <- mtgcodex.api:::query_synergy_get_job_status(job_id)
  expect_identical(completed$status, "completed")
  expect_true(is.list(completed$result))
  expect_true(isTRUE(completed$result$ok))
})
