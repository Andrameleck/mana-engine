# Snapshot tests locking the current behaviour of
# query_synergy_normalize_card() over a curated set of reference cards.
#
# Running these tests AFTER any refactor must produce identical snapshots,
# guaranteeing that the refactor preserves observable behaviour.

test_that("normalized card snapshots are stable", {
  cards <- load_reference_cards()

  summaries <- lapply(cards, function(card) {
    norm <- mtgcodex.api:::query_synergy_normalize_card(card)
    summarize_normalized(norm)
  })

  names(summaries) <- vapply(cards, function(c) as.character(c$name),
                              character(1))
  summaries <- summaries[order(names(summaries))]

  expect_snapshot_value(summaries, style = "json2")
})
