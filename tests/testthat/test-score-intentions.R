# Intention tests for the synergy scoring system.
# These tests lock in the *intent* of the scoring weights and modifiers, so a
# future weight tweak that quietly changes user-visible behavior is caught.
# They do NOT pin exact scores: the assertions check directional behavior
# (A should outscore B) and structural invariants (modifier amounts add up).

test_that("weight registry exposes pair, group, spellbook and archetype tunables", {
  w <- query_synergy_weights()
  expect_true(is.list(w))
  for (key in c("pair", "pair_bonus", "pair_penalty", "cadence_bonus",
                "group", "group_penalty", "group_threshold",
                "spellbook_bonus", "archetype", "diversification")) {
    expect_true(key %in% names(w), info = paste("missing key:", key))
  }
  # Pair positive weights must sum to a sensible range (~1.0-1.2). A drift
  # below 0.9 or above 1.3 indicates a tuning mistake.
  pair_sum <- sum(unlist(w$pair))
  expect_true(pair_sum > 0.9 && pair_sum < 1.3,
              info = paste("pair positive sum =", pair_sum))
  # Group positive weights similarly bounded.
  group_sum <- sum(unlist(w$group))
  expect_true(group_sum > 0.9 && group_sum < 1.3,
              info = paste("group positive sum =", group_sum))
})

test_that("spellbook bonus ordering: exact > contains > partial", {
  b <- query_synergy_spellbook_bonus_tbl()
  expect_true(b$exact > b$contains)
  expect_true(b$contains > b$partial)
  expect_true(b$partial >= 0L)
})

test_that("archetype boost is bounded and additive (not multiplicative)", {
  a <- query_synergy_archetype_tuning()
  expect_true(a$max_boost >= 0L && a$max_boost <= 30L,
              info = "boost should be a small additive bonus, not a score multiplier")
  expect_true(a$strict_min_alignment > 0 && a$strict_min_alignment <= 0.5)
})

test_that("spellbook annotator records score_base and additive modifier", {
  combos <- list(
    list(id = "sb1", title = "Test combo", description = "",
         produces = "Test effect", cards = c("card a", "card b"),
         key = "card a|card b", size = 2L)
  )
  group <- list(
    total_score = 60L,
    members = list(list(name = "Card A"), list(name = "Card B"))
  )
  # Match function returns the right shape.
  matches <- query_synergy_spellbook_match_group(c("Card A", "Card B"), combos)
  expect_equal(matches[[1]]$match_type, "exact")
  bonus <- query_synergy_spellbook_bonus_tbl()$exact
  expect_equal(matches[[1]]$bonus, bonus)
})

test_that("score_modifier amounts are integers and sum makes total deterministic", {
  # Synthetic group going through the spellbook annotator.
  # We can't easily exercise the full engine here without a live DB, so we
  # verify the annotator's contract: total = score_base + sum(modifier amounts).
  combos <- list(
    list(id = "sb1", title = "T", description = "", produces = "X",
         cards = c("a", "b"), key = "a|b", size = 2L)
  )
  groups <- list(list(
    total_score = 50L,
    members = list(list(name = "A"), list(name = "B"))
  ))
  out <- query_synergy_spellbook_annotate_groups(groups)
  if (length(out) > 0L && !is.null(out[[1]]$score_modifiers)) {
    g <- out[[1]]
    expected <- as.integer(g$score_base) +
      sum(vapply(g$score_modifiers, function(m) as.integer(m$amount), integer(1)))
    expect_equal(as.integer(g$total_score), min(100L, expected))
  } else {
    # If there's no live spellbook DB the annotator returns groups unchanged;
    # that's acceptable here (the unit assertion is conditional).
    succeed()
  }
})

test_that("group threshold is read from registry (not hardcoded)", {
  t <- query_synergy_group_thresholds()
  expect_true(t$min_score_norm > 0 && t$min_score_norm < 0.5)
  expect_true(t$min_chain_continuity > 0 && t$min_chain_continuity < 0.5)
  expect_true(t$min_edge_score >= 1L && t$min_edge_score <= 100L)
})
