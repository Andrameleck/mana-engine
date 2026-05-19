# Archidekt deck reference integration
#
# Archidekt exposes a public JSON REST API for individual decks.
# No authentication required for public decks.
#
# API endpoint:
#   GET https://archidekt.com/api/decks/{id}/       -- full deck with cards
#   GET https://archidekt.com/api/decks/{id}/small/ -- metadata only (faster)
#
# deckFormat codes (not exhaustive):
#   1 = Standard, 2 = Modern, 3 = Commander / EDH, 4 = Legacy
#   5 = Vintage, 6 = Pauper, 7 = Limited, 8 = Frontier
#   9 = Future Standard, 10 = Penny Dreadful, 11 = 1v1 Commander
#   13 = Oathbreaker, 14 = Historic, 17 = Pioneer
#
# Deck IDs are sequential integers starting at 1. Upper bound is currently
# in the low-8-million range (as of 2026).

# \u2500\u2500 helpers \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

archidekt_fetch_json <- function(url) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    return(list(ok = FALSE, error = "jsonlite package required"))
  }
  raw <- tryCatch(
    paste(readLines(url, warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
    error = function(e) ""
  )
  if (!nzchar(raw)) {
    return(list(ok = FALSE, error = "archidekt unavailable", url = url))
  }
  payload <- tryCatch(
    jsonlite::fromJSON(raw, simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (is.null(payload)) {
    return(list(ok = FALSE, error = "invalid JSON response", url = url))
  }
  list(ok = TRUE, payload = payload, url = url)
}

archidekt_deck_format_label <- function(code) {
  labels <- c(
    "1"  = "Standard",
    "2"  = "Modern",
    "3"  = "Commander",
    "4"  = "Legacy",
    "5"  = "Vintage",
    "6"  = "Pauper",
    "7"  = "Limited",
    "8"  = "Frontier",
    "9"  = "Future Standard",
    "10" = "Penny Dreadful",
    "11" = "1v1 Commander",
    "13" = "Oathbreaker",
    "14" = "Historic",
    "17" = "Pioneer"
  )
  key <- as.character(code %||% "")
  unname(labels[key] %||% key)
}

archidekt_empty_cards_df <- function() {
  data.frame(
    deck_id      = integer(0),
    deck_url     = character(0),
    deck_title   = character(0),
    deck_author  = character(0),
    deck_format  = character(0),
    deck_date    = character(0),
    section      = character(0),
    quantity     = integer(0),
    card_name    = character(0),
    scryfall_id  = character(0),
    stringsAsFactors = FALSE
  )
}

# \u2500\u2500 public functions \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

#' Fetch a full Archidekt deck with its card list
#'
#' @param deck_id Integer or string deck ID.
#' @return List with ok, source, deck_id, deck_url, title, format, owner,
#'   updated_at, card_count, cards (data.frame).
query_archidekt_fetch_deck <- function(deck_id) {
  id <- suppressWarnings(as.integer(deck_id))
  if (is.na(id) || id < 1L) {
    return(query_api_error("deck_id must be a positive integer"))
  }

  url <- sprintf("https://archidekt.com/api/decks/%d/?format=json", id)
  result <- archidekt_fetch_json(url)
  if (!isTRUE(result$ok)) {
    return(result)
  }

  p <- result$payload
  if (!is.null(p$error)) {
    return(query_api_error(as.character(p$error), deck_id = id))
  }

  deck_title  <- trimws(as.character(p$name %||% ""))
  deck_format <- archidekt_deck_format_label(p$deckFormat)
  deck_owner  <- trimws(as.character((p$owner %||% list())$username %||% ""))
  deck_date   <- trimws(as.character(p$updatedAt %||% ""))
  deck_url    <- sprintf("https://archidekt.com/decks/%d", id)

  cards_raw <- p$cards %||% list()

  card_rows <- lapply(cards_raw, function(entry) {
    qty <- suppressWarnings(as.integer(entry$quantity %||% 1L))
    if (is.na(qty) || qty < 1L) qty <- 1L

    card        <- entry$card %||% list()
    oracle_card <- card$oracleCard %||% list()
    card_name   <- trimws(as.character(oracle_card$name %||% card$displayName %||% ""))
    scryfall_id <- trimws(as.character(card$uid %||% oracle_card$uid %||% ""))

    categories <- entry$categories %||% list()
    section <- if (length(categories) > 0L) {
      trimws(as.character(categories[[1L]]))
    } else {
      "Main"
    }

    if (!nzchar(card_name)) return(NULL)

    list(
      section     = section,
      quantity    = qty,
      card_name   = card_name,
      scryfall_id = scryfall_id
    )
  })
  card_rows <- Filter(Negate(is.null), card_rows)

  cards <- if (length(card_rows) == 0L) {
    archidekt_empty_cards_df()
  } else {
    n <- length(card_rows)
    data.frame(
      deck_id     = rep.int(id,          n),
      deck_url    = rep.int(deck_url,    n),
      deck_title  = rep.int(deck_title,  n),
      deck_author = rep.int(deck_owner,  n),
      deck_format = rep.int(deck_format, n),
      deck_date   = rep.int(deck_date,   n),
      section     = vapply(card_rows, `[[`, character(1), "section"),
      quantity    = vapply(card_rows, `[[`, integer(1),   "quantity"),
      card_name   = vapply(card_rows, `[[`, character(1), "card_name"),
      scryfall_id = vapply(card_rows, `[[`, character(1), "scryfall_id"),
      stringsAsFactors = FALSE
    )
  }

  list(
    ok         = TRUE,
    source     = "archidekt_deck",
    deck_id    = id,
    deck_url   = deck_url,
    title      = deck_title,
    format     = deck_format,
    owner      = deck_owner,
    updated_at = deck_date,
    private    = isTRUE(p$private),
    card_count = nrow(cards),
    cards      = cards
  )
}

