test_that("stored collection card quantity mutations update rows and totals", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")

  tmp <- tempfile(fileext = ".sqlite")
  on.exit(unlink(tmp), add = TRUE)

  con <- mtgcodex.api:::query_collections_connect(tmp)
  on.exit(mtgcodex.api:::db_disconnect(con), add = TRUE)

  DBI::dbExecute(
    con,
    paste(
      "INSERT INTO collections",
      "(collection_id, owner_id, name, platform, source_file, created_at, row_count)",
      "VALUES (?, ?, ?, ?, ?, ?, ?)"
    ),
    params = list("collection-1", "anon", "Test", "auto", "cards.csv", "2026-05-09T12:00:00Z", 2L)
  )

  DBI::dbExecute(
    con,
    paste(
      "INSERT INTO collection_cards",
      "(collection_id, row_index, quantity, name, set_code, collector_number, mana_cost, oracle_text, keywords, language, finish, card_condition, scryfall_id, notes)",
      "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
    ),
    params = list(
      "collection-1", 1L, 2, "A Little Chat", "SNC", "1", "{U}", "", "", "en", "", "", "card-1", ""
    )
  )

  selector <- list(
    name = "A Little Chat",
    set_code = "SNC",
    collector_number = "1",
    language = "en",
    finish = "",
    card_condition = "",
    scryfall_id = "card-1",
    notes = ""
  )

  inc <- mtgcodex.api:::query_collections_increment_card_row(con, "collection-1", selector, 1)
  expect_true(isTRUE(inc$ok))

  total_after_inc <- mtgcodex.api:::query_collections_update_row_count(con, "collection-1")
  expect_equal(total_after_inc, 3L)

  qty_after_inc <- DBI::dbGetQuery(
    con,
    "SELECT quantity FROM collection_cards WHERE collection_id = 'collection-1' AND name = 'A Little Chat'"
  )
  expect_equal(qty_after_inc$quantity[[1]], 3)

  dec <- mtgcodex.api:::query_collections_decrement_card_rows(con, "collection-1", selector, 2)
  expect_true(isTRUE(dec$ok))

  total_after_dec <- mtgcodex.api:::query_collections_update_row_count(con, "collection-1")
  expect_equal(total_after_dec, 1L)

  qty_after_dec <- DBI::dbGetQuery(
    con,
    "SELECT quantity FROM collection_cards WHERE collection_id = 'collection-1' AND name = 'A Little Chat'"
  )
  expect_equal(qty_after_dec$quantity[[1]], 1)

  remove_last <- mtgcodex.api:::query_collections_decrement_card_rows(con, "collection-1", selector, 1)
  expect_true(isTRUE(remove_last$ok))

  total_after_delete <- mtgcodex.api:::query_collections_update_row_count(con, "collection-1")
  expect_equal(total_after_delete, 0L)

  remaining <- DBI::dbGetQuery(
    con,
    "SELECT COUNT(*) AS n FROM collection_cards WHERE collection_id = 'collection-1'"
  )
  expect_equal(remaining$n[[1]], 0)
})
