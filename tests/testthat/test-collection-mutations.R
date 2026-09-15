internal <- function(name) {
  if ("mtgcodex.api" %in% loadedNamespaces()) getFromNamespace(name, "mtgcodex.api") else get(name, envir = .GlobalEnv)
}

collection_row <- function(quantity) {
  data.frame(
    scryfall_id = "card-id", name = "Card", set_code = "SET",
    set_name = "Set", collector_number = "1", foil = "normal",
    rarity = "common", quantity = quantity, manabox_id = "",
    purchase_price = NA_real_, misprint = "false", altered = "false",
    condition = "near_mint", language = "en",
    purchase_price_currency = "EUR", stringsAsFactors = FALSE
  )
}

test_that("adding an existing inventory row increments its quantity", {
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, paste(
    "CREATE TABLE collection (id INTEGER PRIMARY KEY AUTOINCREMENT,",
    "scryfall_id TEXT, name TEXT, set_code TEXT, set_name TEXT,",
    "collector_number TEXT, foil TEXT, rarity TEXT, quantity INTEGER,",
    "manabox_id TEXT, purchase_price REAL, misprint TEXT, altered TEXT,",
    "condition TEXT, language TEXT, purchase_price_currency TEXT)"
  ))

  insert <- internal("query_collection_db_insert_collection_rows")
  first <- insert(con, collection_row(2), on_duplicate = "increment")
  second <- insert(con, collection_row(3), on_duplicate = "increment")

  expect_equal(first$inserted, 1L)
  expect_equal(second$updated, 1L)
  expect_equal(DBI::dbGetQuery(con, "SELECT quantity FROM collection")$quantity, 5L)
})

test_that("a complete reference enriches an existing placeholder", {
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, paste(
    "CREATE TABLE cards (scryfall_id TEXT PRIMARY KEY, name TEXT,",
    "oracle_text TEXT, type_line TEXT, mana_cost TEXT, cmc REAL, colors TEXT,",
    "color_identity TEXT, keywords TEXT, produced_mana TEXT, power TEXT,",
    "toughness TEXT, loyalty TEXT, rarity TEXT, set_code TEXT, set_name TEXT,",
    "collector_number TEXT, lang TEXT, legalities TEXT, layout TEXT,",
    "card_faces TEXT, image_uris TEXT, prices TEXT, edhrec_rank INTEGER,",
    "released_at TEXT)"
  ))

  init <- internal("query_collection_db_init_cards_df")
  upsert <- internal("query_collection_db_insert_cards_rows")
  placeholder <- init(1L)
  placeholder$scryfall_id <- "card-id"
  placeholder$name <- "Card"
  upsert(con, placeholder)

  complete <- init(1L)
  complete$scryfall_id <- "card-id"
  complete$name <- "Card"
  complete$oracle_text <- "Draw a card."
  complete$mana_cost <- "{U}"
  upsert(con, complete)

  stored <- DBI::dbGetQuery(
    con,
    "SELECT oracle_text, mana_cost FROM cards WHERE scryfall_id = 'card-id'"
  )
  expect_equal(stored$oracle_text, "Draw a card.")
  expect_equal(stored$mana_cost, "{U}")
})
