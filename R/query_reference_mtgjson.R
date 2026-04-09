query_mtgjson_cards <- function(
  q = "",
  set_code = "",
  collector_number = "",
  uuid = "",
  limit = "40"
) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    return(list(
      ok = FALSE,
      error = "jsonlite package is required",
      results = list()
    ))
  }

  query_name <- tolower(trimws(as.character(q)))
  set_code_value <- toupper(trimws(as.character(set_code)))
  collector_value <- trimws(as.character(collector_number))
  uuid_value <- trimws(as.character(uuid))

  limit_value <- suppressWarnings(as.integer(limit))
  if (!is.finite(limit_value) || is.na(limit_value)) {
    limit_value <- 40L
  }
  limit_value <- max(1L, min(200L, limit_value))

  if (!nzchar(uuid_value) && !nzchar(set_code_value)) {
    return(list(
      ok = FALSE,
      error = "set_code or uuid is required for MTGJSON lookup",
      results = list()
    ))
  }

  fetch <- if (nzchar(uuid_value)) {
    query_mtgjson_fetch_payload(
      sprintf(
        "https://api.mtgjson.com/v5/cards/%s.json",
        utils::URLencode(uuid_value, reserved = TRUE)
      )
    )
  } else {
    query_mtgjson_fetch_payload(
      sprintf(
        "https://api.mtgjson.com/v5/%s.json",
        utils::URLencode(set_code_value, reserved = TRUE)
      )
    )
  }

  if (!isTRUE(fetch$ok)) {
    return(list(
      ok = FALSE,
      error = fetch$error,
      results = list()
    ))
  }

  payload <- fetch$payload
  source_url <- fetch$url

  cards <- list()
  set_name <- ""

  if (nzchar(uuid_value)) {
    card <- payload$data
    if (is.list(card) && length(card) > 0L) {
      cards <- list(card)
      set_name <- query_mtgjson_clean_text(card$setName, fallback = "")
      if (!nzchar(set_code_value)) {
        set_code_value <- toupper(query_mtgjson_clean_text(card$setCode, fallback = ""))
      }
    }
  } else {
    set_data <- payload$data
    if (is.list(set_data) && length(set_data) > 0L) {
      set_name <- query_mtgjson_clean_text(set_data$name, fallback = "")
      if (!nzchar(set_code_value)) {
        set_code_value <- toupper(query_mtgjson_clean_text(set_data$code, fallback = ""))
      }
      cards <- set_data$cards
      if (is.null(cards)) {
        cards <- list()
      }
    }
  }

  if (!is.list(cards)) {
    cards <- list()
  }

  if (nzchar(query_name)) {
    cards <- Filter(
      function(card) {
        card_name <- tolower(query_mtgjson_clean_text(card$name, fallback = ""))
        nzchar(card_name) && grepl(query_name, card_name, fixed = TRUE)
      },
      cards
    )
  }

  if (nzchar(collector_value)) {
    cards <- Filter(
      function(card) {
        number_value <- query_mtgjson_clean_text(card$number, fallback = "")
        identical(number_value, collector_value)
      },
      cards
    )
  }

  if (length(cards) > limit_value) {
    cards <- cards[seq_len(limit_value)]
  }

  results <- lapply(
    cards,
    function(card) {
      query_mtgjson_normalize_card(
        card = card,
        fallback_set_code = set_code_value,
        fallback_set_name = set_name
      )
    }
  )

  list(
    ok = TRUE,
    source = "mtgjson",
    source_url = source_url,
    query = list(
      q = query_name,
      set_code = set_code_value,
      collector_number = collector_value,
      uuid = uuid_value,
      limit = limit_value
    ),
    count = length(results),
    results = results
  )
}

query_mtgjson_fetch_payload <- function(url) {
  raw_text <- tryCatch(
    paste(readLines(url, warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
    error = function(e) ""
  )

  if (!nzchar(raw_text)) {
    return(list(
      ok = FALSE,
      error = "MTGJSON unavailable or resource not found",
      url = url
    ))
  }

  payload <- tryCatch(
    jsonlite::fromJSON(raw_text, simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (is.null(payload) || !is.list(payload)) {
    return(list(
      ok = FALSE,
      error = "Invalid MTGJSON response",
      url = url
    ))
  }

  list(
    ok = TRUE,
    payload = payload,
    url = url
  )
}

query_mtgjson_normalize_card <- function(card, fallback_set_code = "", fallback_set_name = "") {
  identifiers <- card$identifiers
  scryfall_id <- ""
  if (is.list(identifiers) && !is.null(identifiers$scryfallId)) {
    scryfall_id <- query_mtgjson_clean_text(identifiers$scryfallId, fallback = "")
  }

  keyword_values <- query_mtgjson_to_vector(card$keywords)

  list(
    uuid = query_mtgjson_clean_text(card$uuid, fallback = ""),
    scryfall_id = scryfall_id,
    name = query_mtgjson_clean_text(card$name, fallback = ""),
    mana_cost = query_mtgjson_clean_text(card$manaCost, fallback = ""),
    oracle_text = query_mtgjson_clean_text(card$text, fallback = ""),
    type_line = query_mtgjson_clean_text(card$type, fallback = ""),
    keywords = keyword_values,
    set_code = toupper(query_mtgjson_clean_text(card$setCode, fallback = fallback_set_code)),
    set_name = query_mtgjson_clean_text(card$setName, fallback = fallback_set_name),
    collector_number = query_mtgjson_clean_text(card$number, fallback = ""),
    rarity = query_mtgjson_clean_text(card$rarity, fallback = ""),
    language = query_mtgjson_clean_text(card$language, fallback = ""),
    converted_mana_cost = suppressWarnings(as.numeric(card$manaValue))
  )
}

query_mtgjson_clean_text <- function(x, fallback = "") {
  value <- trimws(as.character(x))
  if (length(value) == 0L) {
    return(fallback)
  }
  value[is.na(value)] <- ""
  value <- trimws(value[[1]])
  if (!nzchar(value)) {
    return(fallback)
  }
  value
}

query_mtgjson_to_vector <- function(x) {
  if (is.null(x)) {
    return(character(0))
  }
  value <- unlist(x, use.names = FALSE)
  value <- trimws(as.character(value))
  value <- value[!is.na(value) & nzchar(value)]
  unique(value)
}
