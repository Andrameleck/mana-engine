test_that("deck generation does not reward mere repeated words or popularity", {
  commander <- list(id = "leader", name = "Leader", color_identity = "W",
    oracle_text = "Draw a card.", type_line = "Legendary Creature")
  card <- list(id = "other", name = "Other", color_identity = "W",
    oracle_text = "Draw a card.", type_line = "Sorcery", edhrec_rank = 1)
  result <- analyze_functional_synergies(commander, list(card), analysis_context(allowed_colors = "W"))
  expected <- if (length(result$results)) 2 * result$results[[1]]$coverage_attested + result$results[[1]]$coverage_potential else 0
  expect_equal(.deck_score(card, commander), expected)
  card$edhrec_rank <- 999999
  expect_equal(.deck_score(card, commander, owned = TRUE), expected)
})
