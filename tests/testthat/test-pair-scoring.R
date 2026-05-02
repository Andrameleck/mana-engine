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

