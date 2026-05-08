test_that("query_synergy_cooccurrence_count counts decks containing every card", {
  skip_if_not_installed("RSQLite")
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con, "CREATE TABLE deck_cards (deck_id TEXT, section TEXT, quantity INTEGER, card_name TEXT, scryfall_id TEXT)")
  DBI::dbExecute(con, "CREATE TABLE decks (id TEXT, title TEXT)")
  rows <- data.frame(
    deck_id = c("d1", "d1", "d1", "d2", "d2", "d3", "d3", "d3", "d4"),
    section = "main",
    quantity = 1L,
    card_name = c("Sol Ring", "Sheoldred, the Apocalypse", "Raffine, Scheming Seer",
                  "Sheoldred, the Apocalypse", "Raffine, Scheming Seer",
                  "Sheoldred, the Apocalypse", "Raffine, Scheming Seer", "Sol Ring",
                  "Sol Ring"),
    scryfall_id = "",
    stringsAsFactors = FALSE
  )
  DBI::dbWriteTable(con, "deck_cards", rows, append = TRUE)
  DBI::dbWriteTable(con, "decks", data.frame(id = c("d1", "d2", "d3", "d4"), title = ""), append = TRUE)

  # Pair query: 3 decks contain both Sheoldred + Raffine.
  expect_equal(
    mtgcodex.api:::query_synergy_cooccurrence_count(con, c("Sheoldred, the Apocalypse", "Raffine, Scheming Seer")),
    3L
  )
  # Triple query: 2 decks contain Sheoldred + Raffine + Sol Ring.
  expect_equal(
    mtgcodex.api:::query_synergy_cooccurrence_count(con, c("Sheoldred, the Apocalypse", "Raffine, Scheming Seer", "Sol Ring")),
    2L
  )
  # Case-insensitive matching.
  expect_equal(
    mtgcodex.api:::query_synergy_cooccurrence_count(con, c("sol ring", "SHELDOOOO")),
    0L
  )
  # Single card -> all 4 decks contain Sol Ring? d1, d3, d4 = 3.
  expect_equal(
    mtgcodex.api:::query_synergy_cooccurrence_count(con, c("Sol Ring")),
    3L
  )
  # Empty input -> 0.
  expect_equal(mtgcodex.api:::query_synergy_cooccurrence_count(con, character(0)), 0L)
})

test_that("query_synergy_cooccurrence_annotate_groups gracefully handles missing DBs", {
  # When neither archidekt nor spellbook DBs are reachable, groups pass through
  # untouched (no $cooccurrence field added).
  withr::with_envvar(c(MTGCODEX_API_PROJECT_DIR = tempfile()), {
    out <- mtgcodex.api:::query_synergy_cooccurrence_annotate_groups(list(
      list(members = list(list(name = "X"), list(name = "Y")))
    ))
    expect_length(out, 1L)
  })
})
