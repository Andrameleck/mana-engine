test_that("query_synergy_card_legal_in_format respects format spec", {
  card_legal <- list(
    legalities = list(commander = "legal", modern = "banned", standard = "not_legal")
  )
  card_banned <- list(
    legalities = list(commander = "banned", modern = "legal")
  )
  card_unknown <- list(legalities = list())

  expect_true(mtgcodex.api:::query_synergy_card_legal_in_format(card_legal, "commander"))
  expect_false(mtgcodex.api:::query_synergy_card_legal_in_format(card_banned, "commander"))
  expect_true(mtgcodex.api:::query_synergy_card_legal_in_format(card_banned, "modern"))
  expect_false(mtgcodex.api:::query_synergy_card_legal_in_format(card_legal, "modern"))

  # allow_illegal short-circuits to TRUE.
  expect_true(mtgcodex.api:::query_synergy_card_legal_in_format(card_banned, "commander", allow_illegal = TRUE))

  # Unknown legalities default to TRUE (preserve recall on legacy catalogs).
  expect_true(mtgcodex.api:::query_synergy_card_legal_in_format(card_unknown, "commander"))

  # Unknown format key falls through to TRUE.
  expect_true(mtgcodex.api:::query_synergy_card_legal_in_format(card_legal, "no_such_format"))
})

test_that("query_synergy_format_spec exposes singleton & color identity flags", {
  cmdr <- mtgcodex.api:::query_synergy_format_spec("commander")
  expect_true(isTRUE(cmdr$singleton))
  expect_true(isTRUE(cmdr$color_identity_strict))

  modern <- mtgcodex.api:::query_synergy_format_spec("modern")
  expect_false(isTRUE(modern$singleton))
  expect_false(isTRUE(modern$color_identity_strict))

  expect_null(mtgcodex.api:::query_synergy_format_spec("unknown_format"))
})

test_that("query_synergy_formats_list returns all registered formats", {
  formats <- mtgcodex.api:::query_synergy_formats_list()
  keys <- vapply(formats, function(entry) entry$key, character(1))
  expect_true(all(c("commander", "modern", "legacy", "vintage", "pioneer",
                    "standard", "pauper", "brawl", "historic") %in% keys))
})
