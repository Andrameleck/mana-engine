test_that("lotusnoir extract_deck_urls keeps only deck pages", {
  html <- paste(
    '<a href="https://www.lotusnoir.info/magic/decks/contamination-5/">Contamination</a>',
    '<a href="/magic/decks/chromium-voltron-control/">Chromium</a>',
    '<a href="https://www.lotusnoir.info/magic/decks/feed/">Feed</a>',
    '<a href="https://www.lotusnoir.info/magic/decks/">Index</a>'
  )

  urls <- mtgcodex.api:::query_lotusnoir_extract_deck_urls(html)

  expect_equal(
    urls,
    c(
      "https://www.lotusnoir.info/magic/decks/contamination-5/",
      "https://www.lotusnoir.info/magic/decks/chromium-voltron-control/"
    )
  )
})

test_that("lotusnoir parse_deck_page extracts metadata and cards", {
  html <- paste(
    '<html><head><title>Lotus Noir : Deck Contamination</title></head><body>',
    '<h1>Deck Contamination</h1>',
    '<p>Créé par Klesd le 15 avril 2026</p>',
    '<p>Categorie : Deck Magic</p>',
    '<p>Format de Tournoi : Aucun</p>',
    '<p>Balise à copier sur le forum :</p>',
    '<div>Ce deck est légal</div>',
    '<h2>Liste</h2>',
    '<p>Créatures (3)</p>',
    '<a href="#">1 Exécration de sang 1 Bloodghast</a>',
    '<a href="#">2 Ophiomancienne 2 Ophiomancer</a>',
    '<p>Sorts (1)</p>',
    '<a href="#">4 Contamination 4 Contamination</a>',
    '<a href="#">Retour aux Decks</a>',
    '</body></html>',
    sep = "\n"
  )

  out <- mtgcodex.api:::query_lotusnoir_parse_deck_page(
    html,
    deck_url = "https://www.lotusnoir.info/magic/decks/contamination-5/"
  )

  expect_true(isTRUE(out$ok))
  expect_equal(out$title, "Contamination")
  expect_equal(out$author, "Klesd")
  expect_equal(out$date, "15 avril 2026")
  expect_equal(out$category, "Deck Magic")
  expect_equal(out$format, "Aucun")
  expect_true(isTRUE(out$deck_legal))
  expect_equal(out$card_count, 3L)
  expect_equal(out$cards$section, c("Créatures", "Créatures", "Sorts"))
  expect_equal(out$cards$quantity, c(1L, 2L, 4L))
  expect_equal(out$cards$card_name_local, c("Exécration de sang", "Ophiomancienne", "Contamination"))
  expect_equal(out$cards$card_name_english, c("Bloodghast", "Ophiomancer", "Contamination"))
})

test_that("lotusnoir extract_deck_did finds numeric deck id", {
  html <- paste(
    '<html><body>',
    '<form><input type="hidden" name="did" value="20753108"/></form>',
    '<a href="/magic/decks/?action=export&did=20753108">Exporter</a>',
    '<table id="decklist20753108"></table>',
    '</body></html>'
  )

  expect_equal(
    mtgcodex.api:::query_lotusnoir_extract_deck_did(html),
    "20753108"
  )
})

test_that("lotusnoir parse_export_text extracts main and side deck rows", {
  text <- paste(
    "// NAME: [Deck Lotus Noir] Destruction terrain",
    "// MAIN DECK (61)",
    "// Créatures (2)",
    "2 Korvold, Fae-Cursed King",
    "// Sorts (1)",
    "3 Smallpox",
    "// SIDE DECK (2)",
    "SB: 4 Village Rites",
    sep = "\n"
  )

  out <- mtgcodex.api:::query_lotusnoir_parse_export_text(
    export_text = text,
    deck_url = "https://www.lotusnoir.info/magic/decks/destruction-terrain-5/",
    title = "Destruction terrain",
    author = "Andrameleck",
    deck_date = "6 mai 2026",
    deck_category = "Deck Magic",
    deck_format = "Aucun",
    deck_legal = TRUE
  )

  expect_true(isTRUE(out$ok))
  expect_equal(out$title, "Destruction terrain")
  expect_equal(out$card_count, 3L)
  expect_equal(out$cards$section, c("Créatures", "Sorts", "SIDE DECK"))
  expect_equal(out$cards$quantity, c(2L, 3L, 4L))
  expect_equal(out$cards$card_name_english, c("Korvold, Fae-Cursed King", "Smallpox", "Village Rites"))
})

test_that("lotusnoir sqlite schema stores deck and cards", {
  skip_if_not_installed("RSQLite")

  tmp <- tempfile(fileext = ".sqlite")
  con <- mtgcodex.api:::query_lotusnoir_db_connect(tmp)
  on.exit(mtgcodex.api:::query_db_disconnect(con), add = TRUE)

  mtgcodex.api:::query_lotusnoir_db_ensure_schema(con)
  mtgcodex.api:::query_lotusnoir_db_upsert_deck_urls(
    con,
    c("https://www.lotusnoir.info/magic/decks/contamination-5/"),
    source_index_url = "https://www.lotusnoir.info/magic/decks/"
  )

  deck <- mtgcodex.api:::query_lotusnoir_parse_deck_page(
    paste(
      '<html><head><title>Lotus Noir : Deck Contamination</title></head><body>',
      '<p>Créé par Klesd le 15 avril 2026</p>',
      '<p>Categorie : Deck Magic</p>',
      '<p>Format de Tournoi : Aucun</p>',
      '<p>Balise à copier sur le forum :</p>',
      '<div>Ce deck est légal</div>',
      '<h2>Liste</h2>',
      '<p>Créatures (1)</p>',
      '<a href="#">2 Ophiomancienne 2 Ophiomancer</a>',
      '<a href="#">Retour aux Decks</a>',
      '</body></html>',
      sep = "\n"
    ),
    deck_url = "https://www.lotusnoir.info/magic/decks/contamination-5/"
  )
  stored <- mtgcodex.api:::query_lotusnoir_db_upsert_deck(con, deck)

  expect_true(isTRUE(stored$ok))
  expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM deck_urls")$n[[1]], 1)
  expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM decks")$n[[1]], 1)
  expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM deck_cards")$n[[1]], 1)
  expect_true("deck_did" %in% DBI::dbListFields(con, "deck_urls"))
  expect_true("deck_did" %in% DBI::dbListFields(con, "decks"))
  expect_equal(
    DBI::dbGetQuery(con, "SELECT normalized_name_english FROM deck_cards")$normalized_name_english[[1]],
    "ophiomancer"
  )
})

test_that("lotusnoir card_stats returns deck counts formats and cooccurrences", {
  skip_if_not_installed("RSQLite")

  tmp <- tempfile(fileext = ".sqlite")
  con <- mtgcodex.api:::query_lotusnoir_db_connect(tmp)
  on.exit(mtgcodex.api:::query_db_disconnect(con), add = TRUE)
  mtgcodex.api:::query_lotusnoir_db_ensure_schema(con)

  deck_a <- list(
    ok = TRUE,
    deck_url = "https://www.lotusnoir.info/magic/decks/a/",
    title = "Deck A",
    author = "A",
    date = "2026-05-01",
    category = "Deck Magic",
    format = "Commander (EDH)",
    deck_legal = TRUE,
    cards = data.frame(
      deck_url = rep("https://www.lotusnoir.info/magic/decks/a/", 3),
      deck_title = rep("Deck A", 3),
      deck_author = rep("A", 3),
      deck_date = rep("2026-05-01", 3),
      deck_category = rep("Deck Magic", 3),
      deck_format = rep("Commander (EDH)", 3),
      deck_legal = rep(TRUE, 3),
      section = c("Creatures", "Creatures", "Sorts"),
      quantity = c(1L, 1L, 1L),
      card_name_local = c("Sheoldred, the Apocalypse", "Raffine, Scheming Seer", "Sign in Blood"),
      card_name_english = c("Sheoldred, the Apocalypse", "Raffine, Scheming Seer", "Sign in Blood"),
      stringsAsFactors = FALSE
    )
  )
  deck_b <- deck_a
  deck_b$deck_url <- "https://www.lotusnoir.info/magic/decks/b/"
  deck_b$title <- "Deck B"
  deck_b$format <- "Standard"
  deck_b$cards$deck_url <- rep(deck_b$deck_url, 3)
  deck_b$cards$deck_title <- rep(deck_b$title, 3)
  deck_b$cards$deck_format <- rep("Standard", 3)
  deck_b$cards$card_name_local <- c("Sheoldred, the Apocalypse", "Cut Down", "Go for the Throat")
  deck_b$cards$card_name_english <- deck_b$cards$card_name_local

  mtgcodex.api:::query_lotusnoir_db_upsert_deck_urls(con, c(deck_a$deck_url, deck_b$deck_url))
  mtgcodex.api:::query_lotusnoir_db_upsert_deck(con, deck_a)
  mtgcodex.api:::query_lotusnoir_db_upsert_deck(con, deck_b)

  out <- mtgcodex.api:::query_lotusnoir_card_stats(
    card_name = "Sheoldred, the Apocalypse",
    db_path = tmp,
    top_n = 10L,
    deck_limit = 10L
  )

  expect_true(isTRUE(out$ok))
  expect_equal(out$stats$deck_count, 2L)
  expect_equal(out$stats$total_quantity, 2L)
  expect_true(all(c("Commander (EDH)", "Standard") %in% out$formats$format))
  expect_true("Raffine, Scheming Seer" %in% out$cooccurrences$card_name)
  expect_true("Cut Down" %in% out$cooccurrences$card_name)
  expect_equal(nrow(out$decks), 2L)
})
