test_that("query_synergy_catalog_from_sqlite reads a temporary cards table", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  skip_if_not_installed("jsonlite")

  tmp <- tempfile(fileext = ".sqlite")
  on.exit(unlink(tmp), add = TRUE)

  con <- DBI::dbConnect(RSQLite::SQLite(), tmp)
  DBI::dbExecute(con, "CREATE TABLE cards_api (
    scryfall_id TEXT, name TEXT, oracle_text TEXT, type_line TEXT,
    mana_cost TEXT, cmc REAL, colors TEXT, color_identity TEXT,
    keywords TEXT, legalities TEXT
  )")
  DBI::dbExecute(
    con,
    "INSERT INTO cards_api VALUES
       ('id-1','Sheoldred','Whenever you draw a card, gain 2 life.',
        'Creature - Phyrexian','{2}{B}{B}',4,'[\"B\"]','[\"B\"]','[]',
        '{\"commander\":\"legal\"}'),
       ('id-2','Raffine','Whenever you attack, target attacking creature connives X.',
        'Creature - Sphinx','{W}{U}{B}',3,'W,U,B','W,U,B','','{\"commander\":\"legal\"}')"
  )
  DBI::dbDisconnect(con)

  cards <- query_synergy_catalog_from_sqlite(db_path = tmp)
  expect_true(is.list(cards))
  expect_equal(length(cards), 2L)
  expect_equal(cards[[1]]$name, "Sheoldred")
  expect_equal(sort(cards[[1]]$color_identity), "B")
  expect_equal(sort(cards[[2]]$color_identity), c("B", "U", "W"))
  expect_equal(cards[[1]]$legalities$commander, "legal")
  expect_true(nzchar(attr(cards, "synergy_cache_key")))
  expect_identical(attr(cards, "synergy_source"), "sqlite_cards")
})

test_that("query_synergy_catalog_from_sqlite returns an explicit error when path is missing", {
  res <- query_synergy_catalog_from_sqlite(db_path = tempfile(fileext = ".missing.sqlite"))
  expect_false(isTRUE(res$ok))
  expect_true(grepl("not found", res$error, fixed = TRUE))
})
