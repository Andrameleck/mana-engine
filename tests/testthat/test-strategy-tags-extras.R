test_that("opponent_draw_punisher tag is set when consuming OPPONENT_DRAW_CARD", {
  card <- list(
    id = "sheoldred",
    name = "Sheoldred, the Apocalypse",
    oracle_text = "Deathtouch\nWhenever you draw a card, you gain 2 life.\nWhenever an opponent draws a card, they lose 2 life.",
    type_line = "Legendary Creature - Phyrexian Praetor",
    colors = "B", color_identity = "B", cmc = 4,
    keywords = "Deathtouch"
  )
  n <- mtgcodex.api:::query_synergy_normalize_card(card)
  expect_true("OPPONENT_DRAW_CARD" %in% n$consumed_events)
  expect_true("opponent_draw_punisher" %in% n$strategy_tags)
  expect_true("life_drain_on_opponent_draw" %in% n$strategy_tags)
})

test_that("opponent_draw_punisher does not require life swing", {
  card <- list(
    id = "underworld-dreams",
    name = "Underworld Dreams",
    oracle_text = "Whenever an opponent draws a card, Underworld Dreams deals 1 damage to that player.",
    type_line = "Enchantment", colors = "B", color_identity = "B", cmc = 3
  )
  n <- mtgcodex.api:::query_synergy_normalize_card(card)
  expect_true("opponent_draw_punisher" %in% n$strategy_tags)
  # No GAIN_LIFE/LOSE_LIFE produced -> no life_drain tag.
  expect_false("life_drain_on_opponent_draw" %in% n$strategy_tags)
})

test_that("creature_count_scaling tag is set for X = number of ... templates", {
  card <- list(
    id = "raffine",
    name = "Raffine, Scheming Seer",
    oracle_text = "Whenever you attack, target attacking creature you control connives X, where X is the number of attacking creatures.",
    type_line = "Legendary Creature - Sphinx",
    colors = c("W","U","B"), color_identity = c("W","U","B"), cmc = 3,
    keywords = c("Flying","Connive")
  )
  n <- mtgcodex.api:::query_synergy_normalize_card(card)
  expect_true("creature_count_scaling" %in% n$strategy_tags)
})

test_that("plain draw payoff stays untagged as opponent_draw_punisher", {
  card <- list(
    id = "consecrated-sphinx",
    name = "Consecrated Sphinx",
    oracle_text = "Flying\nWhenever an opponent draws a card, you may draw two cards.",
    type_line = "Creature - Sphinx", colors = "U", color_identity = "U", cmc = 6,
    keywords = "Flying"
  )
  n <- mtgcodex.api:::query_synergy_normalize_card(card)
  expect_true("opponent_draw_punisher" %in% n$strategy_tags)
  expect_false("life_drain_on_opponent_draw" %in% n$strategy_tags)
})
