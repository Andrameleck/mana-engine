strategy_card <- function(id, text = "", type = "", cost = "", colors = character()) {
  list(id = id, name = id, oracle_text = text, type_line = type,
       mana_cost = cost, color_identity = colors)
}

test_that("empty Oracle wording does not create a keyword modifier", {
  out <- parse_oracle_text(strategy_card("unknown", "Unrecognized gibberish"))
  expect_equal(out$coverage$parsed, 0L)
  expect_equal(out$coverage$semantic, 0L)
  expect_equal(out$coverage$unresolved, 1L)
})

test_that("strategy extraction distinguishes zone transfers", {
  entomb <- extract_strategy_actions(strategy_card(
    "entomb", "Search your library for a card, put that card into your graveyard, then shuffle."
  ))
  reanimate <- extract_strategy_actions(strategy_card(
    "reanimate", "Put target creature card from a graveyard onto the battlefield under your control. You lose life equal to that card's mana value."
  ))
  expect_equal(entomb$actions[[1]]$from_zone, "library")
  expect_equal(entomb$actions[[1]]$to_zone, "graveyard")
  expect_equal(reanimate$actions[[1]]$from_zone, "graveyard")
  expect_equal(reanimate$actions[[1]]$to_zone, "battlefield")
  expect_true("You lose life equal to that card's mana value." %in% reanimate$unsupported_text)
})

test_that("Reanimator is discovered as an interface with alternatives", {
  cards <- list(
    strategy_card("entomb", "Search your library for a card, put that card into your graveyard, then shuffle.", "Instant", "{B}"),
    strategy_card("buried", "Search your library for up to three creature cards, put them into your graveyard, then shuffle.", "Sorcery", "{2}{B}"),
    strategy_card("reanimate", "Put target creature card from a graveyard onto the battlefield under your control. You lose life equal to that card's mana value.", "Sorcery", "{B}"),
    strategy_card("exhume", "Each player puts a creature card from their graveyard onto the battlefield.", "Sorcery", "{1}{B}"),
    strategy_card("atraxa", "When Atraxa enters the battlefield, reveal the top ten cards of your library.", "Legendary Creature", "{3}{G}{W}{U}{B}"),
    strategy_card("ritual", "Add {B}{B}{B}.", "Instant", "{B}")
  )
  out <- discover_strategy_engines(cards, analysis_context(allowed_colors = character()))
  expect_equal(out$model_version, "strategy-engine-0.3.0")
  expect_length(out$results, 1L)
  expect_equal(out$results[[1]]$pattern, "library -> graveyard -> battlefield")
  expect_setequal(vapply(out$results[[1]]$realizations$setup, `[[`, character(1), "card_id"), c("entomb", "buried"))
  expect_setequal(vapply(out$results[[1]]$realizations$executor, `[[`, character(1), "card_id"), c("reanimate", "exhume"))
  expect_true("atraxa" %in% vapply(out$results[[1]]$payloads, `[[`, character(1), "card_id"))
  expect_true("ritual" %in% vapply(out$results[[1]]$support_candidates, `[[`, character(1), "card_id"))
  expect_equal(out$results[[1]]$structural_status, "matched")
  expect_identical(out$results[[1]]$feasibility_status, "structural_witness_only")
  exhume <- Filter(function(x) identical(x$card_id, "exhume"), out$results[[1]]$realizations$executor)[[1]]
  expect_true("symmetric_effect" %in% exhume$unknown_conditions)
})

test_that("a hand-to-battlefield action does not compose with library-to-graveyard", {
  cards <- list(
    strategy_card("entomb", "Search your library for a card, put that card into your graveyard, then shuffle."),
    strategy_card("hand-cheat", "Put a creature card from your hand onto the battlefield.")
  )
  expect_length(discover_strategy_engines(cards, analysis_context(allowed_colors = character()))$results, 0L)
})

test_that("a partial pair relation reports unsupplied interfaces", {
  source <- strategy_card("source")
  source$abilities <- list(analysis_ability(
    "source:a", "source", "oracle_general",
    produces = list(analysis_fact("resource", "mana")), status = "verified"
  ))
  target <- strategy_card("target")
  target$abilities <- list(analysis_ability(
    "target:a", "target", "oracle_general",
    requires = list(analysis_fact("resource", "mana"), analysis_fact("object_available", "artifact", "battlefield")),
    status = "verified"
  ))
  out <- functional_relations(source, target, analysis_context(allowed_colors = character()))
  expect_length(out, 1L)
  expect_equal(out[[1]]$interface_coverage, 0.5)
  expect_equal(out[[1]]$feasibility_status, "indeterminate")
  expect_length(out[[1]]$unsatisfied_requirements, 1L)
})

test_that("engine API adapter validates payloads", {
  expect_false(query_analysis_engines(NULL)$ok)
  out <- query_analysis_engines(list(cards = list(), context = list(allowed_colors = list())))
  expect_true(out$ok)
  expect_equal(out$model_version, "strategy-engine-0.3.0")
})
