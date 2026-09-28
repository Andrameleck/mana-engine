test_that("new mechanics can use annotated interfaces without an archetype whitelist", {
  seed <- list(id = "EnergySource", name = "Energy source", color_identity = character(),
    abilities = list(analysis_ability("source", "energysource", "energy", produces = list(analysis_fact("resource", "energy")))))
  payoff <- list(id = "Payoff", name = "Payoff", color_identity = character(),
    abilities = list(analysis_ability("payoff", "payoff", "energy", costs = list(analysis_fact("resource", "energy")))))
  result <- analyze_functional_synergies(seed, list(payoff), analysis_context(objective = "energy", allowed_colors = character()))
  expect_length(result$results, 1L)
  expect_identical(result$seed_id, "energysource")
})

test_that("life gain and land entry are handled without predefined deck styles", {
  card <- function(id, text, type = "") list(id = id, name = id, oracle_text = text, type_line = type, color_identity = character())
  life <- functional_relations(card("gain", "You gain 3 life."), card("payoff", "Whenever you gain life, draw a card."))
  land <- functional_relations(card("land", "", "Basic Land — Forest"), card("landfall", "Whenever a land enters the battlefield under your control, draw a card."))
  expect_true(length(life) > 0)
  expect_true(length(land) > 0)
})

test_that("zone interfaces are not restricted to creature reanimation", {
  cards <- list(
    list(id = "find", name = "Find", oracle_text = "Search your library for an artifact card, put that card into your graveyard, then shuffle.", type_line = "Sorcery"),
    list(id = "recover", name = "Recover", oracle_text = "Return target artifact card from your graveyard to your hand.", type_line = "Instant"),
    list(id = "payload", name = "Payload", oracle_text = "", type_line = "Artifact")
  )
  result <- discover_strategy_engines(cards)
  expect_length(result$results, 1L)
  expect_equal(result$results[[1]]$pattern, "library -> graveyard -> hand")
  expect_true("payload" %in% vapply(result$results[[1]]$payloads, `[[`, character(1), "card_id"))
})

test_that("unknown mechanics remain visible even with no detected relations", {
  cards <- list(list(id = "unparsed", name = "Unparsed", oracle_text = "A future mechanic with unfamiliar wording."))
  result <- analyze_functional_synergies(list(id = "seed", name = "Seed", oracle_text = "Draw a card."), cards)
  expect_length(result$results, 0L)
  expect_gt(result$coverage$incomplete_cards, 0L)
  expect_match(result$coverage$details[[2]]$unresolved_text, "future mechanic")
})

test_that("format profiles and copy exceptions are separate from mechanics", {
  expect_equal(.deck_format_rules("modern")$mainboard_size, 60L)
  expect_equal(.deck_format_rules("commander")$mainboard_size, 99L)
  expect_error(.deck_format_rules("random"), "Unsupported")
  card <- list(type_line = "Creature", legalities = '{"vintage":"restricted"}')
  expect_equal(.deck_copy_limit(card, .deck_format_rules("vintage")), 1L)
  card$oracle_text <- "A deck can have up to seven cards named Seven Dwarves."
  expect_equal(.deck_copy_limit(card, .deck_format_rules("commander")), 7L)
})
