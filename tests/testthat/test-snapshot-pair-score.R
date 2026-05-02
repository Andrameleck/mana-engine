# Snapshot tests locking the current behaviour of
# query_synergy_score_pair() for a small set of well-known synergistic
# AND anti-synergistic pairs. These pairs cover the AGENTS.md mandates:
#
#   * graveyard setup -> reanimation -> ETB payoff line
#   * sacrifice outlet + token maker + death payoff
#   * tutor + combo piece (Entomb -> Bloodghast)
#   * direct anti-synergy via replaced_events
#
# We hand-pick pairs whose normalized inputs come from the reference
# fixtures, so snapshots stay reproducible without DB access.

PAIRS <- list(
  list(a = "Entomb",                b = "Bloodghast"),
  list(a = "Bitterblossom",         b = "Skullclamp"),
  list(a = "Dockside Extortionist", b = "Sol Ring"),
  list(a = "Yawgmoth, Thran Physician", b = "Bitterblossom"),
  list(a = "Necropotence",          b = "Smothering Tithe"),
  list(a = "Lightning Bolt",        b = "Counterspell"),
  list(a = "Reckoner Bankbuster",   b = "Skullclamp"),
  list(a = "Dark Ritual",           b = "Necropotence"),
  list(a = "Rhystic Study",         b = "Smothering Tithe"),
  list(a = "Tarmogoyf",             b = "Sol Ring")
)

normalize_by_name <- function(cards) {
  out <- lapply(cards, function(c) {
    mtgcodex.api:::query_synergy_normalize_card(c)
  })
  setNames(out, vapply(cards, function(c) as.character(c$name), character(1)))
}

test_that("pair score snapshots are stable", {
  cards <- load_reference_cards()
  needed <- unique(unlist(lapply(PAIRS, function(p) c(p$a, p$b))))
  available <- vapply(cards, function(c) as.character(c$name), character(1))
  missing <- setdiff(needed, available)
  expect_true(
    length(missing) == 0L,
    info = paste("Missing reference cards:", paste(missing, collapse = ", "))
  )

  index <- normalize_by_name(cards)

  results <- lapply(PAIRS, function(p) {
    raw <- mtgcodex.api:::query_synergy_score_pair(index[[p$a]], index[[p$b]])
    summarize_pair_score(raw)
  })
  names(results) <- vapply(PAIRS, function(p) paste0(p$a, " <-> ", p$b),
                            character(1))

  expect_snapshot_value(results, style = "json2")
})
