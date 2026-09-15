test_that("Commander generator validates its request", {
  expect_false(query_deck_generate(NULL)$ok)
  expect_false(query_deck_generate(list())$ok)
  missing_collection <- query_deck_generate(list(
    commander = "Leader", collection_only = TRUE
  ))
  expect_false(missing_collection$ok)
  expect_equal(missing_collection$status, 400L)
})

test_that("Commander legality enforces identity and singleton", {
  commander <- list(name = "Leader", color_identity = c("G", "W"))
  legal <- list(name = "Legal", color_identity = "G", legalities = "")
  illegal <- list(name = "Illegal", color_identity = "U", legalities = "")
  banned <- list(name = "Banned", color_identity = "G", legalities = '{"commander":"banned","modern":"legal"}', type_line = "Creature")
  expect_true(.deck_is_legal(legal, commander$color_identity, commander$name))
  expect_false(.deck_is_legal(illegal, commander$color_identity, commander$name))
  expect_false(.deck_is_legal(commander, commander$color_identity, commander$name))
  expect_false(.deck_is_legal(banned, commander$color_identity, commander$name, "commander", TRUE))
  expect_true(.deck_is_legal(banned, commander$color_identity, commander$name, "modern", TRUE))
  expect_true(.deck_is_legal(banned, commander$color_identity, commander$name, "commander", FALSE))
  expect_equal(.deck_legality_status(banned, "commander"), "banned")
  expect_equal(.deck_legality_status(legal, "commander"), "unknown")
})

test_that("Commander role classifier covers structural slots", {
  card <- function(type = "Instant", text = "") list(type_line = type, oracle_text = text, keywords = "", mana_cost = "{2}")
  expect_equal(.deck_role(card("Land")), "land")
  expect_equal(.deck_role(card(text = "Draw two cards.")), "card_draw")
  expect_equal(.deck_role(card(text = "Destroy target creature.")), "removal")
  expect_equal(.deck_role(card(text = "Add two mana.")), "ramp")
})
