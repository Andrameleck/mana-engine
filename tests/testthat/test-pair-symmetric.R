# Regression tests for AGENTS.md § 4.1 direction-invariant pair scoring.
# Validates query_synergy_score_pair_symmetric() against the Raffine /
# Sheoldred case (and a generic engine -> payoff swap).

normalize <- function(card) mtgcodex.api:::query_synergy_normalize_card(card)

raffine <- normalize(list(
  id = "raffine",
  name = "Raffine, Scheming Seer",
  oracle_text = "Flying, ward {1}\nWhenever you attack, target attacking creature you control connives X, where X is the number of attacking creatures.",
  type_line = "Legendary Creature - Sphinx",
  cmc = 3, colors = c("W","U","B"), color_identity = c("W","U","B"),
  keywords = c("Flying","Ward","Connive")
))

sheoldred <- normalize(list(
  id = "sheoldred",
  name = "Sheoldred, the Apocalypse",
  oracle_text = "Deathtouch\nWhenever you draw a card, you gain 2 life.\nWhenever an opponent draws a card, they lose 2 life.",
  type_line = "Legendary Creature - Phyrexian Praetor",
  cmc = 4, colors = "B", color_identity = "B",
  keywords = "Deathtouch"
))

test_that("symmetric pair scoring is direction-invariant for Raffine + Sheoldred", {
  ab <- mtgcodex.api::query_synergy_score_pair_symmetric(raffine, sheoldred)
  ba <- mtgcodex.api::query_synergy_score_pair_symmetric(sheoldred, raffine)

  # Final score: identical, since both wrappers internally call score_pair in
  # both directions and recombine the same numbers.
  expect_equal(ab$final_pair_score, ba$final_pair_score)

  # Role of each card must be the same regardless of input order.
  # (We compare by card name so we don't conflate card_a / card_b labels.)
  ab_roles <- setNames(c(ab$card_a_role, ab$card_b_role), c("Raffine", "Sheoldred"))
  ba_roles <- setNames(c(ba$card_a_role, ba$card_b_role), c("Sheoldred", "Raffine"))
  expect_identical(ab_roles[["Raffine"]], ba_roles[["Raffine"]])
  expect_identical(ab_roles[["Sheoldred"]], ba_roles[["Sheoldred"]])
})

test_that("Raffine is engine/enabler and Sheoldred is payoff/reward", {
  res <- mtgcodex.api::query_synergy_score_pair_symmetric(raffine, sheoldred)
  # card_a = raffine, card_b = sheoldred in this call.
  expect_identical(res$card_a_role, "engine/enabler")
  expect_identical(res$card_b_role, "payoff/reward")

  # The directional event match must surface SELF_DRAW_CARD.
  expect_true("SELF_DRAW_CARD" %in% res$a_feeds_b_events)
  # Sheoldred does not feed Raffine.
  expect_length(res$b_feeds_a_events, 0L)
  expect_identical(res$dominant_relationship, "a_feeds_b")
})

test_that("final_pair_score is a strong score for the engine -> payoff line", {
  res <- mtgcodex.api::query_synergy_score_pair_symmetric(raffine, sheoldred)
  # Stronger of the two directional scores plus optional reciprocity bonus.
  # Should be at least the max of the two directional scores returned by the
  # underlying score_pair (here ~71 in the Sheoldred-as-target direction).
  expect_gte(res$final_pair_score, 65L)
  expect_lte(res$final_pair_score, 100L)
  # NOT the naive average of the two directional scores.
  naive_avg <- as.integer(round((res$a_feeds_b_score + res$b_feeds_a_score) / 2))
  expect_gt(res$final_pair_score, naive_avg)
})

test_that("a specialized payoff is not relabeled as engine when it cannot feed back", {
  # Sheoldred alone, with a generic non-engine creature. Sheoldred should
  # still be reported as payoff/reward (its consumed_events drive the role),
  # not as engine just because the partner is even less synergistic.
  vanilla <- normalize(list(
    id = "vanilla",
    name = "Grizzly Bears",
    oracle_text = "",
    type_line = "Creature - Bear",
    cmc = 2, colors = "G", color_identity = "G", keywords = character()
  ))
  res <- mtgcodex.api::query_synergy_score_pair_symmetric(sheoldred, vanilla)
  expect_identical(res$card_a_role, "payoff/reward")
})
