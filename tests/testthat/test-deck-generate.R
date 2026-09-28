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
test_that("obsolete specialized settings are rejected explicitly", {
  result <- query_deck_generate(list(commander = "Leader", creature_theme = "walls"))
  expect_false(result$ok)
  expect_match(result$error, "removed")
})

test_that("basic land copies fill land slots within the available quantity", {
  basic <- list(name = "Plains", type_line = "Basic Land — Plains", slot_role = "land", score = 0, max_copies = 36L)
  spells <- lapply(seq_len(63), function(i) list(name = paste("Spell", i), type_line = "Sorcery", slot_role = "core", score = 0))
  result <- .deck_pick(c(list(basic), spells), list())
  expect_length(result, 99L)
  expect_equal(sum(vapply(result, function(x) x$name == "Plains", logical(1))), 36L)
  basic$max_copies <- 2L
  limited <- .deck_pick(c(list(basic), spells), list())
  expect_equal(sum(vapply(limited, function(x) x$name == "Plains", logical(1))), 2L)
})

test_that("configured generator accepts varied card types and returns bounded alternatives", {
  make_card <- function(name, type, colors = "W") list(
    name = name, type_line = type, color_identity = colors, oracle_text = "",
    mana_cost = "", keywords = "", legalities = '{"commander":"legal"}', edhrec_rank = 1
  )
  leader <- make_card("Leader", "Legendary Creature — Dragon")
  basic <- make_card("Plains", "Basic Land — Plains")
  walls <- lapply(seq_len(63), function(i) make_card(paste("Wall", i), "Creature — Wall"))
  local_mocked_bindings(
    .deck_reference_cards = function() c(list(leader, basic, make_card("Bird", "Creature — Bird")), walls),
    .deck_scryfall_pool = function(...) list(),
    .deck_owned_names = function(...) character(),
    .deck_owned_quantities = function(...) numeric()
  )
  out <- query_deck_generate(list(commander = "Leader", include_candidates = TRUE))
  expect_true(out$ok)
  expect_length(out$decks[[1]]$mainboard, 99L)
  names <- vapply(out$decks[[1]]$mainboard, `[[`, character(1), "name")
  expect_equal(sum(names == "Plains"), 36L)
  expect_true("Bird" %in% vapply(out$candidates, `[[`, character(1), "name"))
  expect_true(length(out$candidates) <= 219L)
  expect_identical(out$format_rules$mainboard_size, 99L)
  modern <- query_deck_generate(list(commander = "Leader", format = "modern", include_candidates = TRUE))
  expect_true(modern$ok)
  expect_false(modern$requires_commander)
  expect_length(modern$decks[[1]]$mainboard, 60L)
  expect_true("Leader" %in% vapply(modern$decks[[1]]$mainboard, `[[`, character(1), "name"))
})
