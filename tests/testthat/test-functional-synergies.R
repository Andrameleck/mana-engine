functional_card <- function(id, text = "", type = "", colors = character()) {
  list(id = id, name = id, oracle_text = text, type_line = type, color_identity = colors)
}

test_that("token production supplies a creature sacrifice cost", {
  producer <- functional_card("producer", "Create a 1/1 white Soldier creature token.")
  outlet <- functional_card("outlet", "Sacrifice a creature: Draw a card.")
  out <- functional_relations(producer, outlet, analysis_context(allowed_colors = character()))
  expect_length(out, 1L)
  expect_equal(out[[1]]$relation_type, "supplies_cost")
  expect_equal(out[[1]]$supplied$object, "creature_token")
})

test_that("two consumers do not supply each other", {
  a <- functional_card("a", "Sacrifice a creature: Draw a card.")
  b <- functional_card("b", "Sacrifice another creature: Add one mana.")
  expect_length(functional_relations(a, b, analysis_context()), 0L)
})

test_that("a noncreature token is not treated as a creature", {
  clue <- functional_card("clue", "Create a Clue token.")
  outlet <- functional_card("outlet", "Sacrifice a creature: Draw a card.")
  expect_length(functional_relations(clue, outlet, analysis_context()), 0L)
})

test_that("controller and nontoken restrictions prevent false matches", {
  producer <- functional_card("producer", "Create a creature token.")
  restricted <- functional_card("restricted")
  restricted$abilities <- list(analysis_ability(
    "restricted:cost", "restricted", "tokens_sacrifice_death",
    costs = list(analysis_fact(
      "object_available", "creature", "battlefield", "you", "nontoken"
    )),
    status = "verified"
  ))
  opponent <- functional_card("opponent")
  opponent$abilities <- list(analysis_ability(
    "opponent:cost", "opponent", "tokens_sacrifice_death",
    costs = list(analysis_fact(
      "object_available", "creature", "battlefield", "opponent"
    )),
    status = "verified"
  ))
  context <- analysis_context(allowed_colors = character())
  expect_length(functional_relations(producer, restricted, context), 0L)
  expect_length(functional_relations(producer, opponent, context), 0L)
})

test_that("returning a card to hand is not reanimation", {
  regrowth <- functional_card("regrowth", "Return target card from your graveyard to your hand.")
  expect_length(extract_functional_abilities(regrowth)$abilities, 0L)
})

test_that("copying a spell does not satisfy a cast trigger", {
  copier <- functional_card("copier", "Copy target instant or sorcery spell.")
  cast_payoff <- functional_card("cast-payoff", "Whenever you cast an instant or sorcery spell, draw a card.")
  copy_payoff <- functional_card("copy-payoff", "Whenever you copy an instant or sorcery spell, draw a card.")
  context <- analysis_context()
  expect_length(functional_relations(copier, cast_payoff, context), 0L)
  expect_length(functional_relations(copier, copy_payoff, context), 1L)
})

test_that("explicit color identity is a strict pre-ranking constraint", {
  seed <- functional_card("seed", "Create a creature token.", colors = "B")
  legal <- functional_card("legal", "Sacrifice a creature: Draw a card.", colors = "B")
  illegal <- functional_card("illegal", "Sacrifice a creature: Draw a card.", colors = "U")
  out <- analyze_functional_synergies(
    seed, list(illegal, legal),
    analysis_context(format = "commander", rules_version = "fixture", allowed_colors = "B")
  )
  expect_equal(vapply(out$results, `[[`, character(1), "candidate_id"), "legal")
  expect_equal(out$exclusions[[1]]$candidate_id, "illegal")
})

test_that("unknown context stays unknown in an otherwise functional match", {
  producer <- functional_card("producer", "Create a creature token.")
  outlet <- functional_card("outlet", "Sacrifice a creature: Draw a card.")
  out <- analyze_functional_synergies(producer, list(outlet), analysis_context())
  expect_equal(out$results[[1]]$status, "unknown")
  expect_equal(out$results[[1]]$coverage_attested, 0)
  expect_equal(out$results[[1]]$coverage_potential, 1)
  expect_true("color_identity" %in% out$results[[1]]$unknown_conditions)
  expect_true("allowed_colors" %in% out$unknown_fields)
})

test_that("API adapter reports invalid bodies as client errors", {
  out <- query_analysis_synergies(NULL)
  expect_false(out$ok)
  expect_equal(out$status, 400L)
})

test_that("API adapters preserve model versions and search metadata", {
  payload <- list(
    seed = functional_card("producer", "Create a creature token."),
    candidates = list(functional_card("outlet", "Sacrifice a creature: Draw a card.")),
    context = list(
      format = "commander", rules_version = "fixture",
      allowed_colors = list(), mode = "explore",
      objective = "tokens_sacrifice_death"
    ),
    limit = 5L
  )
  pair_out <- query_analysis_synergies(payload)
  expect_true(pair_out$ok)
  expect_equal(pair_out$model_version, "functional-synergy-0.3.0")
  expect_length(pair_out$results, 1L)

  group_out <- query_analysis_groups(list(
    cards = list(
      functional_card("producer", "Create a creature token."),
      functional_card("outlet", "Sacrifice a creature: Add one mana."),
      functional_card("payoff", "Whenever a creature dies, draw a card.")
    ),
    context = payload$context,
    max_pair_evaluations = 20L
  ))
  expect_true(group_out$ok)
  expect_false(group_out$search_truncated)
  expect_length(group_out$results, 1L)
})

test_that("three-card groups preserve both directed explanations", {
  producer <- functional_card("producer", "Create a 1/1 creature token.")
  outlet <- functional_card("outlet", "Sacrifice a creature: Add one mana.")
  payoff <- functional_card("payoff", "Whenever a creature dies, draw a card.")
  out <- analyze_functional_groups(
    list(payoff, outlet, producer),
    analysis_context(allowed_colors = character())
  )
  expect_length(out$results, 1L)
  expect_equal(out$results[[1]]$card_ids, c("producer", "outlet", "payoff"))
  expect_length(out$results[[1]]$relations, 2L)
  expect_false(out$search_truncated)
})

test_that("search and display truncation are distinct", {
  cards <- list(
    functional_card("producer", "Create a creature token."),
    functional_card("outlet", "Sacrifice a creature: Add one mana."),
    functional_card("payoff", "Whenever a creature dies, draw a card.")
  )
  search_cut <- analyze_functional_groups(cards, max_pair_evaluations = 1L)
  expect_true(search_cut$search_truncated)
  expect_false(search_cut$display_truncated)
})

test_that("an explicit objective filters unrelated functional families", {
  seed <- functional_card("seed", "Create a creature token.", type = "Sorcery")
  outlet <- functional_card("outlet", "Sacrifice a creature: Draw a card.")
  cast_payoff <- functional_card("cast-payoff", "Whenever you cast a sorcery spell, draw a card.")
  out <- analyze_functional_synergies(
    seed, list(cast_payoff, outlet),
    analysis_context(objective = "tokens_sacrifice_death", allowed_colors = character())
  )
  expect_equal(vapply(out$results, `[[`, character(1), "candidate_id"), "outlet")
})

test_that("Oracle IR separates triggers, costs, and effects", {
  card <- functional_card("engine", "Whenever you draw a card, create a 1/1 colorless Construct artifact creature token.\n{2}, Sacrifice an artifact: Draw a card.")
  out <- parse_oracle_text(card)
  expect_equal(out$coverage$total, 2L)
  expect_equal(out$coverage$parsed, 2L)
  expect_equal(out$clauses[[1]]$kind, "triggered")
  expect_equal(out$clauses[[1]]$requires[[1]]$object, "card_drawn")
  expect_equal(out$clauses[[1]]$produces[[1]]$object, "creature_token")
  expect_equal(out$clauses[[2]]$kind, "activated")
  expect_true(any(vapply(out$clauses[[2]]$costs, `[[`, character(1), "object") == "artifact"))
})

test_that("general Oracle relations cover draw, life, counters, and landfall", {
  context <- analysis_context(allowed_colors = character())
  pairs <- list(
    list(functional_card("draw", "Draw two cards."), functional_card("draw-payoff", "Whenever you draw a card, create a Treasure token.")),
    list(functional_card("life", "You gain 3 life."), functional_card("life-payoff", "Whenever you gain life, put a +1/+1 counter on target creature.")),
    list(functional_card("counter", "Put a +1/+1 counter on target creature."), functional_card("counter-payoff", "Whenever one or more counters are put on a permanent you control, draw a card.")),
    list(functional_card("land", "Search your library for a basic land card, put it onto the battlefield."), functional_card("landfall", "Whenever a land enters the battlefield under your control, draw a card."))
  )
  for (pair in pairs) expect_gt(length(functional_relations(pair[[1]], pair[[2]], context)), 0L)
})

test_that("unresolved Oracle clauses are explicit", {
  out <- parse_oracle_text(functional_card("unknown", "Bands with other legendary creatures"))
  expect_equal(out$coverage$unresolved, 1L)
  expect_equal(out$unresolved_text, "Bands with other legendary creatures")
})

test_that("catalogue coverage audit counts every clause", {
  cards <- list(
    functional_card("known", "Draw a card."),
    functional_card("mixed", "Create a Treasure token.\nBands with other legendary creatures")
  )
  out <- audit_oracle_coverage(cards)
  expect_equal(out$cards, 2L)
  expect_equal(out$clauses, 3L)
  expect_equal(out$parsed_clauses, 2L)
  expect_equal(out$cards_with_unresolved, 1L)
})
