test_that("setup seeds prioritize direct converter bridges over vague indirect engines", {
  catalog <- list(
    list(
      id = "seed",
      name = "Tomb Survey",
      oracle_text = "Mill three cards.",
      colors = c("B"),
      color_identity = c("B"),
      cmc = 1,
      legalities = list(commander = "legal")
    ),
    list(
      id = "converter",
      name = "Ash Script",
      oracle_text = "Return target creature card from your graveyard to the battlefield.",
      colors = c("B"),
      color_identity = c("B"),
      cmc = 2,
      legalities = list(commander = "legal")
    ),
    list(
      id = "indirect",
      name = "Skirmish Conniver",
      oracle_text = "Whenever you attack, target attacking creature connives 1.",
      colors = c("B"),
      color_identity = c("B"),
      cmc = 3,
      legalities = list(commander = "legal")
    ),
    list(
      id = "cluster",
      name = "Graveyard Scholar",
      oracle_text = "Whenever a card leaves your graveyard, each opponent loses 1 life.",
      colors = c("B"),
      color_identity = c("B"),
      cmc = 3,
      legalities = list(commander = "legal")
    )
  )

  out <- mtgcodex.api:::query_synergy_find_in_catalog(
    list(card_name = "Tomb Survey", format = "commander", max_results = 4, top_k = 4, package_top_n = 3),
    catalog
  )

  result_names <- vapply(out$best_matches, function(entry) entry$name, character(1))
  expect_true("Ash Script" %in% result_names)
  expect_true("Skirmish Conniver" %in% result_names)
  expect_lt(which(result_names == "Ash Script")[[1]], which(result_names == "Skirmish Conniver")[[1]])

  direct_names <- vapply(out$buckets$direct_enablers$results, function(entry) entry$name, character(1))
  expect_true("Ash Script" %in% direct_names)
  expect_false("Skirmish Conniver" %in% direct_names)
})

test_that("library to graveyard setup text is modeled as setup resource production", {
  setup_seed <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "seed-library-graveyard",
    name = "Buried Search",
    oracle_text = "Search your library for a creature card, put that card into your graveyard, then shuffle.",
    colors = c("B"),
    color_identity = c("B"),
    cmc = 1,
    legalities = list(commander = "legal")
  ))

  move_pairs <- vapply(setup_seed$moves, function(move) {
    paste(
      mtgcodex.api:::query_api_scalar(move$from, default = ""),
      mtgcodex.api:::query_api_scalar(move$to, default = ""),
      sep = "->"
    )
  }, character(1))

  expect_true("MILL_CARD" %in% setup_seed$produced_events)
  expect_true("GRAVEYARD_SETUP" %in% setup_seed$setup_events)
  expect_true("library->graveyard" %in% move_pairs)
  expect_true("setup" %in% setup_seed$roles)
})

test_that("setup seeds with resource bridges do not collapse to zero direct and group results", {
  catalog <- list(
    list(
      id = "seed-library-graveyard",
      name = "Buried Search",
      oracle_text = "Search your library for a creature card, put that card into your graveyard, then shuffle.",
      colors = c("B"),
      color_identity = c("B"),
      cmc = 1,
      legalities = list(commander = "legal")
    ),
    list(
      id = "converter-reanimate",
      name = "Ash Revival",
      oracle_text = "Return target creature card from your graveyard to the battlefield.",
      colors = c("B"),
      color_identity = c("B"),
      cmc = 2,
      legalities = list(commander = "legal")
    ),
    list(
      id = "target-big",
      name = "Ancient Colossus",
      oracle_text = "",
      type_line = "Creature - Giant",
      colors = c("B"),
      color_identity = c("B"),
      cmc = 7,
      legalities = list(commander = "legal")
    ),
    list(
      id = "indirect-neighbor",
      name = "Skirmish Conniver",
      oracle_text = "Whenever you attack, target attacking creature connives 1.",
      colors = c("B"),
      color_identity = c("B"),
      cmc = 3,
      legalities = list(commander = "legal")
    )
  )

  out <- mtgcodex.api:::query_synergy_find_in_catalog(
    list(
      card_name = "Buried Search",
      format = "commander",
      max_results = 6,
      top_k = 4,
      package_top_n = 3,
      max_groups = 4,
      max_group_size = 4
    ),
    catalog
  )

  expect_true(isTRUE(out$ok))
  expect_gte(out$count, 1)
  expect_gte(length(out$best_matches), 1)

  result_names <- vapply(out$best_matches, function(entry) entry$name, character(1))
  expect_true("Ash Revival" %in% result_names)

  direct_names <- vapply(out$buckets$direct_enablers$results, function(entry) entry$name, character(1))
  expect_true("Ash Revival" %in% direct_names)

  converter_entry <- Filter(function(entry) identical(entry$name, "Ash Revival"), out$best_matches)
  expect_gte(length(converter_entry), 1)
  converter_entry <- converter_entry[[1]]

  expect_true(any(c("resource_bridge", "zone_transition_bridge", "setup_converter_bridge") %in% converter_entry$matched_events$bridge_types))
  expect_true(
    suppressWarnings(as.numeric(converter_entry$score_breakdown$setup_converter_match)) > 0 ||
      suppressWarnings(as.numeric(converter_entry$score_breakdown$resource_bridge_match)) > 0 ||
      suppressWarnings(as.numeric(converter_entry$score_breakdown$zone_transition_bridge_match)) > 0
  )

  expect_gte(out$group_count, 1)
  expect_true(any(vapply(out$synergy_groups, function(group) {
    member_names <- vapply(group$members, function(member) member$name, character(1))
    category <- mtgcodex.api:::query_api_scalar(group$category, default = "")
    "Ash Revival" %in% member_names &&
      ("Ancient Colossus" %in% member_names || identical(category, "setup_converter_payoff"))
  }, logical(1))))
})

test_that("pairwise output exposes bridge debug axes and bridge types", {
  setup_seed <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "seed",
    name = "Tomb Survey",
    oracle_text = "Mill three cards.",
    colors = c("B"),
    color_identity = c("B"),
    cmc = 1,
    legalities = list(commander = "legal")
  ))

  converter <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "converter",
    name = "Ash Script",
    oracle_text = "Return target creature card from your graveyard to the battlefield.",
    colors = c("B"),
    color_identity = c("B"),
    cmc = 2,
    legalities = list(commander = "legal")
  ))

  indirect <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "indirect",
    name = "Skirmish Conniver",
    oracle_text = "Whenever you attack, target attacking creature connives 1.",
    colors = c("B"),
    color_identity = c("B"),
    cmc = 3,
    legalities = list(commander = "legal")
  ))

  converter_score <- mtgcodex.api:::query_synergy_score_pair(setup_seed, converter, "commander")
  indirect_score <- mtgcodex.api:::query_synergy_score_pair(setup_seed, indirect, "commander")

  expect_true(all(c(
    "event_bridge_match",
    "payoff_bridge_match",
    "resource_bridge_match",
    "zone_transition_bridge_match",
    "strong_bridge_score",
    "weak_bridge_penalty"
  ) %in% names(converter_score$breakdown)))
  expect_true(length(converter_score$matched_events$bridge_types) >= 1L)
  expect_true(any(c("resource_bridge", "zone_transition_bridge", "payoff_bridge") %in% converter_score$matched_events$bridge_types))
  expect_true(suppressWarnings(as.numeric(indirect_score$breakdown$weak_bridge_penalty)) >= suppressWarnings(as.numeric(converter_score$breakdown$weak_bridge_penalty)))
})

test_that("role inference distinguishes setup and converter for graveyard lines", {
  setup_seed <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "seed",
    name = "Tomb Survey",
    oracle_text = "Mill three cards.",
    colors = c("B"),
    color_identity = c("B"),
    cmc = 1,
    legalities = list(commander = "legal")
  ))

  converter <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "converter",
    name = "Ash Script",
    oracle_text = "Return target creature card from your graveyard to the battlefield.",
    colors = c("B"),
    color_identity = c("B"),
    cmc = 2,
    legalities = list(commander = "legal")
  ))

  expect_true("setup" %in% setup_seed$roles)
  expect_true(any(c("converter", "bridge") %in% converter$roles))
  expect_false("setup" %in% converter$roles)
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

