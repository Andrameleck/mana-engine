test_that("direct synergy favors reliable realizability over shell-dependent lines", {
  target <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "life-payoff",
    name = "Life Payoff",
    oracle_text = "Whenever you draw a card, you gain 1 life.",
    colors = c("W"),
    color_identity = c("W"),
    cmc = 3
  ))
  reliable_enabler <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "steady-draw",
    name = "Steady Draw",
    oracle_text = "At the beginning of your upkeep, draw a card.",
    type_line = "Enchantment",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 3
  ))
  shell_enabler <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "combat-draw",
    name = "Combat Draw",
    oracle_text = "Whenever this creature deals combat damage to a player, draw a card.",
    type_line = "Creature",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 3
  ))

  reliable_score <- mtgcodex.api:::query_synergy_score_pair(target, reliable_enabler, "commander")
  shell_score <- mtgcodex.api:::query_synergy_score_pair(target, shell_enabler, "commander")

  expect_gt(reliable_score$axis_scores$reliability_score, shell_score$axis_scores$reliability_score)
  expect_lt(reliable_score$axis_scores$shell_dependency_score, shell_score$axis_scores$shell_dependency_score)
  expect_true("direct_enabler" %in% reliable_score$relation_classes)
})

test_that("indirect engines expose shell dependence explicitly", {
  target <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "opponent-draw-payoff",
    name = "Opponent Draw Payoff",
    oracle_text = "Whenever an opponent draws a card, that player loses 1 life.",
    colors = c("B"),
    color_identity = c("B"),
    cmc = 4
  ))
  broad_engine <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "global-draw-engine",
    name = "Global Draw Engine",
    oracle_text = "At the beginning of each player's draw step, that player draws an additional card.",
    type_line = "Enchantment",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 3
  ))
  shell_engine <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "combat-draw-engine",
    name = "Combat Draw Engine",
    oracle_text = "Whenever one or more creatures you control deal combat damage to a player, draw a card.",
    type_line = "Creature",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 3
  ))

  broad_score <- mtgcodex.api:::query_synergy_score_pair(target, broad_engine, "commander")
  shell_score <- mtgcodex.api:::query_synergy_score_pair(target, shell_engine, "commander")

  expect_gt(broad_score$axis_scores$indirect_engine_score, 0.05)
  expect_gt(shell_score$axis_scores$shell_dependency_score, broad_score$axis_scores$shell_dependency_score)
  expect_true(any(c("shell_dependent_engine", "shell_dependent") %in% shell_score$relation_classes))
})

test_that("shared value cards are not over-promoted as strong indirect engines", {
  target <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "draw-loss-payoff",
    name = "Draw Loss Payoff",
    oracle_text = "Whenever you draw a card, each opponent loses 1 life.",
    colors = c("B"),
    color_identity = c("B"),
    cmc = 4
  ))
  value_peer <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "draw-life-payoff",
    name = "Draw Life Payoff",
    oracle_text = "Whenever you draw a card, you gain 1 life.",
    colors = c("W"),
    color_identity = c("W"),
    cmc = 4
  ))

  score <- mtgcodex.api:::query_synergy_score_pair(target, value_peer, "commander")

  expect_lt(score$axis_scores$indirect_engine_score, 0.22)
  expect_false("indirect_engine" %in% score$relation_classes)
  expect_true(any(c("value_cluster", "shared_plan", "shell_dependent") %in% score$relation_classes))
})

test_that("role inference prefers mechanical function over broad setup labeling", {
  payoff_card <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "death-payoff",
    name = "Death Payoff",
    oracle_text = "Whenever a creature dies, each opponent loses 1 life.",
    type_line = "Enchantment",
    colors = c("B"),
    color_identity = c("B"),
    cmc = 3
  ))
  setup_card <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "grave-setup",
    name = "Grave Setup",
    oracle_text = "Mill three cards.",
    type_line = "Sorcery",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 1
  ))

  expect_true("payoff" %in% payoff_card$roles)
  expect_false("setup" %in% payoff_card$roles)
  expect_true(any(c("setup", "producer") %in% setup_card$roles))
})

test_that("cadence classification separates conditional, reliable, and scalable repeatability", {
  conditional <- mtgcodex.api:::query_synergy_infer_card_cadence(
    abilities = list(list(kind = "triggered", text = "Whenever this attacks, draw a card.", trigger = list(event = "ATTACKS"))),
    type_line = "Creature",
    oracle_text = "Whenever this attacks, draw a card.",
    produced = c("DRAW_CARD"),
    consumed = character(0)
  )
  reliable <- mtgcodex.api:::query_synergy_infer_card_cadence(
    abilities = list(list(kind = "triggered", text = "At the beginning of your upkeep, draw a card.", trigger = list(event = "UPKEEP_STEP"))),
    type_line = "Enchantment",
    oracle_text = "At the beginning of your upkeep, draw a card.",
    produced = c("DRAW_CARD"),
    consumed = character(0)
  )
  scalable <- mtgcodex.api:::query_synergy_infer_card_cadence(
    abilities = list(list(kind = "triggered", text = "Whenever you draw a card, create a token for each card drawn.", trigger = list(event = "DRAW_CARD"))),
    type_line = "Enchantment",
    oracle_text = "Whenever you draw a card, create a token for each card drawn.",
    produced = c("DRAW_CARD", "CREATE_TOKEN"),
    consumed = character(0)
  )

  expect_identical(conditional$class, "conditional_repeatable")
  expect_identical(reliable$class, "reliable_repeatable")
  expect_identical(scalable$class, "scalable_repeatable")
})

test_that("group classification separates value clusters from causal package lines", {
  cluster_category <- mtgcodex.api:::query_synergy_group_category(
    member_roles = c("engine", "payoff", "payoff"),
    member_count = 3L,
    anti_synergy_penalty = 0.05,
    resource_transitions = list(),
    chain_continuity = 0.2,
    resource_flow_quality = 0.12,
    strategic_coherence = 0.58,
    causal_line_quality = 0.16,
    value_cluster_penalty = 0.24
  )
  causal_category <- mtgcodex.api:::query_synergy_group_category(
    member_roles = c("setup", "converter", "payoff"),
    member_count = 3L,
    anti_synergy_penalty = 0.04,
    resource_transitions = list(list(via = "GRAVEYARD_FUEL", from = "library", to = "graveyard")),
    chain_continuity = 0.62,
    resource_flow_quality = 0.44,
    strategic_coherence = 0.42,
    causal_line_quality = 0.58,
    value_cluster_penalty = 0.02
  )

  expect_identical(cluster_category, "value_cluster")
  expect_true(causal_category %in% c("setup_converter_payoff", "causal_package"))
})
