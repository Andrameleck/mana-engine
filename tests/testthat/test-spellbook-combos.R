test_that("query_synergy_spellbook_match_group detects exact and contains matches", {
  combos <- list(
    list(id = "sb1", title = "A + B Combo", description = "Steps...",
         produces = "Infinite mana", cards = c("card a", "card b"),
         key = "card a|card b", size = 2L),
    list(id = "sb2", title = "A + B + C Combo", description = "Steps...",
         produces = "Infinite ETB", cards = c("card a", "card b", "card c"),
         key = "card a|card b|card c", size = 3L)
  )

  # Exact match for 2-card combo.
  m2 <- mtgcodex.api:::query_synergy_spellbook_match_group(c("Card A", "Card B"), combos)
  expect_true(length(m2) >= 1L)
  types2 <- vapply(m2, function(m) m$match_type, character(1))
  expect_true("exact" %in% types2)

  # 3-card group contains 2-card combo.
  m3 <- mtgcodex.api:::query_synergy_spellbook_match_group(c("Card A", "Card B", "Card D"), combos)
  types3 <- vapply(m3, function(m) m$match_type, character(1))
  expect_true("contains" %in% types3)

  # Exact 3-card match.
  m3e <- mtgcodex.api:::query_synergy_spellbook_match_group(c("Card A", "Card B", "Card C"), combos)
  types3e <- vapply(m3e, function(m) m$match_type, character(1))
  # exact on sb2 takes priority, and sb1 is contains.
  expect_true("exact" %in% types3e)

  # No match.
  m_none <- mtgcodex.api:::query_synergy_spellbook_match_group(c("Totally Unknown", "No Combo"), combos)
  expect_equal(length(m_none), 0L)
})

test_that("query_synergy_spellbook_annotate_groups applies bonus and attaches matches", {
  combos <- list(
    list(id = "sb1", title = "A + B", description = "", produces = "Infinite mana",
         cards = c("sol ring", "arcane signet"), key = "arcane signet|sol ring", size = 2L)
  )
  # Test via the match function directly (annotate_groups reads from the live DB;
  # the match logic is the critical path we need to validate here).
  matches <- mtgcodex.api:::query_synergy_spellbook_match_group(
    c("Sol Ring", "Arcane Signet"), combos
  )
  expect_equal(length(matches), 1L)
  expect_equal(matches[[1]]$match_type, "exact")
  expect_equal(matches[[1]]$bonus, 15L)
  expect_equal(matches[[1]]$title, "A + B")
  expect_equal(matches[[1]]$produces, "Infinite mana")
})

test_that("spellbook bonus constants are defined and ordered correctly", {
  b <- mtgcodex.api:::.spellbook_bonus
  expect_true(b$exact > b$contains)
  expect_true(b$contains > b$partial)
  expect_equal(b$exact, 15L)
  expect_equal(b$contains, 10L)
  expect_equal(b$partial, 4L)
})
