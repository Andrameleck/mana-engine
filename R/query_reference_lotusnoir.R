query_lotusnoir_posts <- function(q = "", limit = "120") {
  seed_query <- trimws(as.character(q))
  if (!nzchar(seed_query)) {
    return(list(
      ok = FALSE,
      error = "missing query parameter 'q'",
      results = list()
    ))
  }

  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    return(list(
      ok = FALSE,
      error = "jsonlite package is required",
      results = list()
    ))
  }

  limit_value <- suppressWarnings(as.integer(limit))
  if (!is.finite(limit_value) || is.na(limit_value)) {
    limit_value <- 120L
  }
  limit_value <- max(1L, min(120L, limit_value))

  per_page <- min(100L, limit_value)
  max_pages <- max(1L, as.integer(ceiling(limit_value / per_page)))
  all_entries <- list()
  page_count <- 0L

  for (page in seq_len(max_pages)) {
    query_string <- paste0(
      "search=", utils::URLencode(seed_query, reserved = TRUE),
      "&type=post",
      "&per_page=", as.character(per_page),
      "&page=", as.character(page)
    )
    url <- paste0("https://www.lotusnoir.info/wp-json/wp/v2/search?", query_string)

    raw_text <- tryCatch(
      paste(readLines(url, warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
      error = function(e) ""
    )
    if (!nzchar(raw_text)) {
      if (page == 1L) {
        return(list(
          ok = FALSE,
          error = "LotusNoir unavailable",
          results = list()
        ))
      }
      break
    }

    payload <- tryCatch(
      jsonlite::fromJSON(raw_text, simplifyVector = FALSE),
      error = function(e) NULL
    )
    if (is.null(payload)) {
      if (page == 1L) {
        return(list(
          ok = FALSE,
          error = "Invalid LotusNoir response",
          results = list()
        ))
      }
      break
    }

    if (is.list(payload) && !is.null(payload$code) && !is.null(payload$message)) {
      if (page == 1L) {
        return(list(
          ok = FALSE,
          error = as.character(payload$message),
          code = as.character(payload$code),
          results = list()
        ))
      }
      break
    }

    if (!is.list(payload) || length(payload) == 0L) {
      break
    }

    page_count <- page_count + 1L
    all_entries <- c(all_entries, payload)
    if (length(all_entries) >= limit_value) {
      break
    }
  }

  results <- lapply(all_entries, function(entry) {
    if (!is.list(entry)) {
      return(NULL)
    }
    post_type <- trimws(as.character(entry$type %||% ""))
    if (nzchar(post_type) && post_type != "post") {
      return(NULL)
    }
    title <- trimws(as.character(entry$title %||% ""))
    url_value <- trimws(as.character(entry$url %||% ""))
    id_value <- trimws(as.character(entry$id %||% ""))
    list(
      id = id_value,
      title = title,
      url = url_value,
      snippet = title
    )
  })
  results <- Filter(Negate(is.null), results)
  if (length(results) > limit_value) {
    results <- results[seq_len(limit_value)]
  }

  list(
    ok = TRUE,
    source = "lotusnoir_wp_search",
    query = seed_query,
    fetched_pages = page_count,
    count = length(results),
    results = results
  )
}

query_lotusnoir_read_text <- function(url) {
  target <- trimws(as.character(url))
  if (!nzchar(target)) {
    return(query_api_error("missing url"))
  }

  con <- NULL
  on.exit({
    if (!is.null(con)) {
      try(close(con), silent = TRUE)
    }
  }, add = TRUE)

  text <- tryCatch({
    con <- base::url(target, open = "rb")
    paste(readLines(con, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  }, error = function(e) "")

  if (!nzchar(text)) {
    return(query_api_error("LotusNoir unavailable", url = target))
  }

  list(
    ok = TRUE,
    url = target,
    text = text
  )
}

query_lotusnoir_html_decode <- function(text) {
  decoded <- as.character(text %||% "")
  decoded <- iconv(decoded, from = "", to = "UTF-8", sub = " ")
  replacements <- c(
    "&nbsp;" = " ",
    "&amp;" = "&",
    "&quot;" = "\"",
    "&#039;" = "'",
    "&apos;" = "'",
    "&lt;" = "<",
    "&gt;" = ">",
    "&eacute;" = "e",
    "&Eacute;" = "E",
    "&egrave;" = "e",
    "&Egrave;" = "E",
    "&ecirc;" = "e",
    "&agrave;" = "a",
    "&Agrave;" = "A",
    "&acirc;" = "a",
    "&icirc;" = "i",
    "&ocirc;" = "o",
    "&ucirc;" = "u",
    "&uuml;" = "u",
    "&ccedil;" = "c"
  )
  for (needle in names(replacements)) {
    decoded <- gsub(needle, replacements[[needle]], decoded, fixed = TRUE)
  }
  decoded
}

query_lotusnoir_strip_tags <- function(text) {
  clean <- query_lotusnoir_html_decode(text)
  clean <- gsub("<[^>]+>", " ", clean)
  trimws(gsub("\\s+", " ", clean))
}

query_lotusnoir_extract_deck_urls <- function(html,
                                              base_url = "https://www.lotusnoir.info") {
  content <- query_lotusnoir_html_decode(html)
  if (!nzchar(content)) {
    return(character(0))
  }

  matches <- regmatches(
    content,
    gregexpr("(https://www\\.lotusnoir\\.info)?/magic/decks/[^\"'<>\\s?#]+/?", content, perl = TRUE)
  )[[1]]
  if (length(matches) == 0L) {
    return(character(0))
  }

  urls <- vapply(matches, function(path) {
    if (startsWith(path, "http")) {
      return(path)
    }
    paste0(base_url, path)
  }, character(1))

  urls <- unique(urls)
  urls <- urls[
    grepl("^https://www\\.lotusnoir\\.info/magic/decks/[^/?#]+/?$", urls) &
      !grepl("/magic/decks/(feed|page)/", urls)
  ]
  urls
}

query_lotusnoir_default_index_urls <- function() {
  base <- "https://www.lotusnoir.info/magic/decks/"
  actions <- c(
    "",
    "?action=decks-du-moment",
    "?action=decks-populaires",
    "?action=decks-blancs",
    "?action=decks-bleus",
    "?action=decks-noirs",
    "?action=decks-rouges",
    "?action=decks-verts",
    "?action=decks-aggro",
    "?action=decks-controle",
    "?action=decks-aggro-controle",
    "?action=decks-combo",
    "?action=decks-ramp",
    "?action=decks-standard",
    "?action=decks-moderne",
    "?action=decks-etendu",
    "?action=decks-legacy",
    "?action=decks-vintage",
    "?action=decks-commander",
    "?action=decks-limite",
    "?action=decks-bloc",
    "?action=decks-fun",
    "?action=decks-peasant",
    "?action=decks-pauper"
  )
  paste0(base, actions)
}

#' Discover Deck URLs from LotusNoir Index Pages
#'
#' Crawls LotusNoir index pages to collect all deck page URLs.
#'
#' @param index_urls Character vector of index page URLs to crawl.
#'   Defaults to the standard LotusNoir index pages.
#' @param request_delay Numeric. Seconds to wait between HTTP requests
#'   (default `0`).
#' @param verbose Logical. Print progress messages (default `FALSE`).
#'
#' @return A list with `ok` (logical), `urls` (character vector of discovered
#'   deck URLs), and `failed` (character vector of URLs that could not be read).
#'
#' @export
query_lotusnoir_discover_deck_urls <- function(index_urls = NULL,
                                               request_delay = 0,
                                               verbose = FALSE) {
  urls_to_probe <- unique(Filter(nzchar, as.character(index_urls %||% query_lotusnoir_default_index_urls())))
  discovered <- character(0)
  failed <- character(0)

  for (index in seq_along(urls_to_probe)) {
    if (index > 1L && isTRUE(request_delay > 0)) {
      Sys.sleep(request_delay)
    }
    target <- urls_to_probe[[index]]
    if (isTRUE(verbose)) {
      message(sprintf("LotusNoir index %d/%d: %s", index, length(urls_to_probe), target))
    }
    payload <- query_lotusnoir_read_text(target)
    if (!isTRUE(payload$ok)) {
      failed <- c(failed, target)
      next
    }
    discovered <- c(discovered, query_lotusnoir_extract_deck_urls(payload$text))
  }

  list(
    ok = TRUE,
    source = "lotusnoir_html_index",
    count = length(unique(discovered)),
    urls = unique(discovered),
    failed_index_urls = unique(failed)
  )
}

query_lotusnoir_empty_cards_df <- function() {
  data.frame(
    deck_url = character(0),
    deck_title = character(0),
    deck_author = character(0),
    deck_date = character(0),
    deck_category = character(0),
    deck_format = character(0),
    deck_legal = logical(0),
    section = character(0),
    quantity = integer(0),
    card_name_local = character(0),
    card_name_english = character(0),
    stringsAsFactors = FALSE
  )
}

query_lotusnoir_extract_deck_did <- function(html = "", deck_url = "") {
  content <- query_lotusnoir_html_decode(html)
  deck_page <- query_api_scalar(deck_url, default = "")

  patterns <- c(
    "action=export&did=([0-9]+)",
    "name=\"did\" value=\"([0-9]+)\"",
    "name=\"id\" value=\"([0-9]+)\"",
    "decklist([0-9]+)",
    "/magic/decks/\\?action=view&did=([0-9]+)",
    "/magic/decks/([0-9]+)/"
  )

  for (pattern in patterns) {
    if (nzchar(content)) {
      match <- regexec(pattern, content, perl = TRUE)
      groups <- regmatches(content, match)[[1]]
      if (length(groups) >= 2L && nzchar(groups[[2]])) {
        return(groups[[2]])
      }
    }
    if (nzchar(deck_page)) {
      match <- regexec(pattern, deck_page, perl = TRUE)
      groups <- regmatches(deck_page, match)[[1]]
      if (length(groups) >= 2L && nzchar(groups[[2]])) {
        return(groups[[2]])
      }
    }
  }

  ""
}

query_lotusnoir_export_url <- function(deck_did) {
  did <- query_api_scalar(deck_did, default = "")
  if (!nzchar(did)) {
    return("")
  }
  sprintf("https://www.lotusnoir.info/magic/decks/?action=export&did=%s", did)
}

query_lotusnoir_view_url <- function(deck_did) {
  did <- query_api_scalar(deck_did, default = "")
  if (!nzchar(did)) {
    return("")
  }
  sprintf("https://www.lotusnoir.info/magic/decks/?action=view&did=%s", did)
}

query_lotusnoir_fetch_deck_export <- function(deck_did) {
  did <- query_api_scalar(deck_did, default = "")
  if (!nzchar(did)) {
    return(query_api_error("deck_did is required"))
  }

  export_url <- query_lotusnoir_export_url(did)
  payload <- query_lotusnoir_read_text(export_url)
  if (!isTRUE(payload$ok)) {
    return(payload)
  }

  list(
    ok = TRUE,
    source = "lotusnoir_deck_export",
    deck_did = did,
    export_url = export_url,
    text = query_lotusnoir_html_decode(payload$text)
  )
}

query_lotusnoir_export_is_valid <- function(export_text) {
  text <- query_lotusnoir_html_decode(export_text)
  nzchar(text) && grepl("^//\\s*NAME\\s*:", text, perl = TRUE)
}

query_lotusnoir_parse_export_text <- function(export_text,
                                              deck_url = "",
                                              title = "",
                                              author = "",
                                              deck_date = "",
                                              deck_category = "",
                                              deck_format = "",
                                              deck_legal = FALSE) {
  content <- query_lotusnoir_html_decode(export_text)
  if (!nzchar(content)) {
    return(query_api_error("missing export_text", deck_url = deck_url))
  }

  lines <- trimws(unlist(strsplit(content, "\n", fixed = TRUE)))
  lines <- lines[nzchar(lines)]
  if (length(lines) == 0L) {
    return(query_api_error("empty export_text", deck_url = deck_url))
  }

  deck_title <- query_api_scalar(title, default = "")
  if (!nzchar(deck_title)) {
    name_line <- lines[grepl("^//\\s*NAME\\s*:", lines)]
    if (length(name_line) > 0L) {
      deck_title <- trimws(sub("^//\\s*NAME\\s*:\\s*(\\[Deck Lotus Noir\\]\\s*)?", "", name_line[[1]], perl = TRUE))
    }
  }

  card_rows <- list()
  current_section <- ""
  current_block <- "MAIN DECK"
  for (line in lines) {
    if (grepl("^//\\s*NAME\\s*:", line)) {
      next
    }
    if (grepl("^//\\s*MAIN DECK", line)) {
      current_block <- "MAIN DECK"
      current_section <- "MAIN DECK"
      next
    }
    if (grepl("^//\\s*SIDE DECK", line)) {
      current_block <- "SIDE DECK"
      current_section <- "SIDE DECK"
      next
    }
    if (grepl("^//\\s*", line)) {
      section_line <- trimws(sub("^//\\s*", "", line))
      section_line <- trimws(sub("\\s*\\([0-9]+\\)\\s*$", "", section_line))
      current_section <- if (nzchar(section_line)) section_line else current_block
      next
    }

    normalized_line <- line
    is_sideboard <- grepl("^SB:\\s*", normalized_line)
    if (is_sideboard) {
      normalized_line <- trimws(sub("^SB:\\s*", "", normalized_line))
      if (!nzchar(current_section)) {
        current_section <- "SIDE DECK"
      }
    }

    match <- regexec("^([0-9]+)\\s+(.+)$", normalized_line, perl = TRUE)
    groups <- regmatches(normalized_line, match)[[1]]
    if (length(groups) < 3L) {
      next
    }

    qty <- suppressWarnings(as.integer(groups[[2]]))
    card_name <- trimws(groups[[3]])
    if (!nzchar(card_name)) {
      next
    }

    section_name <- current_section
    if (!nzchar(section_name)) {
      section_name <- if (is_sideboard || identical(current_block, "SIDE DECK")) "SIDE DECK" else "MAIN DECK"
    }

    card_rows[[length(card_rows) + 1L]] <- list(
      section = section_name,
      quantity = if (is.finite(qty) && !is.na(qty)) qty else 0L,
      card_name_local = card_name,
      card_name_english = card_name
    )
  }

  cards <- if (length(card_rows) == 0L) {
    query_lotusnoir_empty_cards_df()
  } else {
    data.frame(
      deck_url = rep.int(query_api_scalar(deck_url, default = ""), length(card_rows)),
      deck_title = rep.int(deck_title, length(card_rows)),
      deck_author = rep.int(query_api_scalar(author, default = ""), length(card_rows)),
      deck_date = rep.int(query_api_scalar(deck_date, default = ""), length(card_rows)),
      deck_category = rep.int(query_api_scalar(deck_category, default = ""), length(card_rows)),
      deck_format = rep.int(query_api_scalar(deck_format, default = ""), length(card_rows)),
      deck_legal = rep.int(isTRUE(deck_legal), length(card_rows)),
      section = vapply(card_rows, `[[`, character(1), "section"),
      quantity = vapply(card_rows, `[[`, integer(1), "quantity"),
      card_name_local = vapply(card_rows, `[[`, character(1), "card_name_local"),
      card_name_english = vapply(card_rows, `[[`, character(1), "card_name_english"),
      stringsAsFactors = FALSE
    )
  }

  list(
    ok = TRUE,
    source = "lotusnoir_deck_export",
    deck_url = query_api_scalar(deck_url, default = ""),
    title = deck_title,
    author = query_api_scalar(author, default = ""),
    date = query_api_scalar(deck_date, default = ""),
    category = query_api_scalar(deck_category, default = ""),
    format = query_api_scalar(deck_format, default = ""),
    deck_legal = isTRUE(deck_legal),
    card_count = nrow(cards),
    cards = cards
  )
}

query_lotusnoir_parse_deck_page <- function(html,
                                            deck_url = "") {
  content <- query_lotusnoir_html_decode(html)
  if (!nzchar(content)) {
    return(query_api_error("missing html", deck_url = deck_url))
  }

  content <- gsub("><", ">\n<", content, fixed = TRUE)
  lines <- trimws(unlist(strsplit(content, "\n", fixed = TRUE)))
  plain_lines <- query_lotusnoir_strip_tags(lines)
  plain_lines <- plain_lines[nzchar(plain_lines)]
  plain_text <- paste(plain_lines, collapse = " ")

  title <- ""
  title_match <- regexec("<title>\\s*Lotus Noir\\s*:\\s*Deck\\s*([^<]*)</title>", content, perl = TRUE)
  title_groups <- regmatches(content, title_match)[[1]]
  if (length(title_groups) >= 2L) {
    title <- trimws(query_lotusnoir_html_decode(title_groups[[2]]))
  }
  if (!nzchar(title)) {
    title_line <- plain_lines[grepl("^Deck\\s+", plain_lines)]
    if (length(title_line) > 0L) {
      title <- trimws(sub("^Deck\\s+", "", title_line[[1]]))
    }
  }

  author <- ""
  created_date <- ""
  created_match <- regexec("Cr\u00e9\u00e9 par\\s+(.+?)\\s+le\\s+([0-9]{1,2}\\s+[^ ]+\\s+[0-9]{4})", plain_text, perl = TRUE)
  created_groups <- regmatches(plain_text, created_match)[[1]]
  if (length(created_groups) >= 3L) {
    author <- trimws(created_groups[[2]])
    created_date <- trimws(created_groups[[3]])
  }

  category <- ""
  category_match <- regexec("Categorie\\s*:\\s*(.+?)\\s+Format de Tournoi\\s*:", plain_text, perl = TRUE)
  category_groups <- regmatches(plain_text, category_match)[[1]]
  if (length(category_groups) >= 2L) {
    category <- trimws(gsub("\\s*\u2022\\s*$", "", category_groups[[2]]))
  }

  format_name <- ""
  format_match <- regexec("Format de Tournoi\\s*:\\s*(.+?)\\s+Balise \u00e0 copier", plain_text, perl = TRUE)
  format_groups <- regmatches(plain_text, format_match)[[1]]
  if (length(format_groups) >= 2L) {
    format_name <- trimws(gsub("\\s*\u2022\\s*$", "", format_groups[[2]]))
  }

  deck_legal <- grepl("Ce deck est l\u00e9gal", plain_text, fixed = TRUE)
  list_start <- match("Liste", plain_lines)
  list_end <- if (!is.na(list_start)) {
    candidate_ends <- which(plain_lines %in% c("Retour aux Decks", "Description"))
    candidate_ends <- candidate_ends[candidate_ends > list_start]
    if (length(candidate_ends) > 0L) candidate_ends[[1]] else length(plain_lines)
  } else {
    NA_integer_
  }

  card_rows <- list()
  current_section <- ""
  if (!is.na(list_start) && !is.na(list_end) && list_end > list_start) {
    list_lines <- plain_lines[(list_start + 1L):(list_end - 1L)]
    index <- 1L
    while (index <= length(list_lines)) {
      line <- list_lines[[index]]
      if (!nzchar(line)) {
        index <- index + 1L
        next
      }
      section_match <- regexec("^(.+?)\\s*\\(([0-9]+)\\)$", line, perl = TRUE)
      section_groups <- regmatches(line, section_match)[[1]]
      if (length(section_groups) >= 3L && !grepl("^[0-9]+\\s+", line)) {
        current_section <- trimws(section_groups[[2]])
        index <- index + 1L
        next
      }

      dual_name_match <- regexec("^([0-9]+)\\s+(.+?)\\s+\\1\\s+(.+)$", line, perl = TRUE)
      dual_name_groups <- regmatches(line, dual_name_match)[[1]]
      if (length(dual_name_groups) >= 4L) {
        qty <- suppressWarnings(as.integer(dual_name_groups[[2]]))
        local_name <- trimws(dual_name_groups[[3]])
        english_name <- trimws(dual_name_groups[[4]])
        card_rows[[length(card_rows) + 1L]] <- list(
          section = current_section,
          quantity = if (is.finite(qty) && !is.na(qty)) qty else 0L,
          card_name_local = local_name,
          card_name_english = english_name
        )
        index <- index + 1L
        next
      }

      single_name_match <- regexec("^([0-9]+)\\s+(.+)$", line, perl = TRUE)
      single_name_groups <- regmatches(line, single_name_match)[[1]]
      if (length(single_name_groups) >= 3L) {
        qty <- suppressWarnings(as.integer(single_name_groups[[2]]))
        local_name <- trimws(single_name_groups[[3]])
        english_name <- local_name

        if (index < length(list_lines)) {
          next_line <- list_lines[[index + 1L]]
          next_match <- regexec("^([0-9]+)\\s+(.+)$", next_line, perl = TRUE)
          next_groups <- regmatches(next_line, next_match)[[1]]
          if (length(next_groups) >= 3L) {
            next_qty <- suppressWarnings(as.integer(next_groups[[2]]))
            next_name <- trimws(next_groups[[3]])
            if (isTRUE(identical(next_qty, qty)) && nzchar(next_name)) {
              english_name <- next_name
              index <- index + 1L
            }
          }
        }

        card_rows[[length(card_rows) + 1L]] <- list(
          section = current_section,
          quantity = if (is.finite(qty) && !is.na(qty)) qty else 0L,
          card_name_local = local_name,
          card_name_english = english_name
        )
      }
      index <- index + 1L
    }
  }

  deck_did <- query_lotusnoir_extract_deck_did(content, deck_url = deck_url)

  cards <- if (length(card_rows) == 0L) {
    query_lotusnoir_empty_cards_df()
  } else {
    data.frame(
      deck_url = rep.int(query_api_scalar(deck_url, default = ""), length(card_rows)),
      deck_title = rep.int(title, length(card_rows)),
      deck_author = rep.int(author, length(card_rows)),
      deck_date = rep.int(created_date, length(card_rows)),
      deck_category = rep.int(category, length(card_rows)),
      deck_format = rep.int(format_name, length(card_rows)),
      deck_legal = rep.int(deck_legal, length(card_rows)),
      section = vapply(card_rows, `[[`, character(1), "section"),
      quantity = vapply(card_rows, `[[`, integer(1), "quantity"),
      card_name_local = vapply(card_rows, `[[`, character(1), "card_name_local"),
      card_name_english = vapply(card_rows, `[[`, character(1), "card_name_english"),
      stringsAsFactors = FALSE
    )
  }

  list(
    ok = TRUE,
    source = "lotusnoir_deck_html",
    deck_url = query_api_scalar(deck_url, default = ""),
    title = title,
    author = author,
    date = created_date,
    category = category,
    format = format_name,
    deck_legal = deck_legal,
    deck_did = deck_did,
    card_count = nrow(cards),
    cards = cards
  )
}

#' Fetch and Parse a LotusNoir Deck
#'
#' Downloads a deck page from LotusNoir, extracts its card list and metadata.
#'
#' @param deck_url Character scalar. Full URL of the deck page.
#'
#' @return A list with `ok` (logical), `deck_did` (character identifier),
#'   `cards` (data.frame with columns `name`, `quantity`, `section`),
#'   and `url` (the original URL).
#'
#' @export
query_lotusnoir_fetch_deck <- function(deck_url) {
  target <- query_api_scalar(deck_url, default = "")
  if (!nzchar(target)) {
    return(query_api_error("deck_url is required"))
  }

  payload <- query_lotusnoir_read_text(target)
  if (!isTRUE(payload$ok)) {
    return(payload)
  }

  parsed <- query_lotusnoir_parse_deck_page(payload$text, deck_url = target)
  if (!isTRUE(parsed$ok)) {
    return(parsed)
  }

  deck_did <- query_api_scalar(parsed$deck_did, default = "")
  if (!nzchar(deck_did)) {
    return(parsed)
  }

  export_payload <- query_lotusnoir_fetch_deck_export(deck_did)
  if (!isTRUE(export_payload$ok)) {
    return(parsed)
  }

  export_parsed <- query_lotusnoir_parse_export_text(
    export_text = export_payload$text,
    deck_url = target,
    title = query_api_scalar(parsed$title, default = ""),
    author = query_api_scalar(parsed$author, default = ""),
    deck_date = query_api_scalar(parsed$date, default = ""),
    deck_category = query_api_scalar(parsed$category, default = ""),
    deck_format = query_api_scalar(parsed$format, default = ""),
    deck_legal = isTRUE(parsed$deck_legal)
  )
  if (!isTRUE(export_parsed$ok) || query_synergy_as_int(export_parsed$card_count, default = 0L, min_value = 0L, max_value = 10000L) == 0L) {
    return(parsed)
  }

  export_parsed$deck_did <- deck_did
  export_parsed$export_url <- query_api_scalar(export_payload$export_url, default = "")
  export_parsed$html_source <- "lotusnoir_deck_html"
  export_parsed
}

query_lotusnoir_default_db_path <- function() {
  installed_path <- system.file("decks", "lotusnoir.sqlite", package = "mtgcodex.api")
  if (nzchar(installed_path) && file.exists(installed_path)) {
    return(installed_path)
  }

  project_dir <- Sys.getenv("MTGCODEX_API_PROJECT_DIR", unset = "")
  candidates <- c(
    if (nzchar(project_dir)) file.path(project_dir, "inst", "decks", "lotusnoir.sqlite"),
    file.path(getwd(), "inst", "decks", "lotusnoir.sqlite"),
    file.path(getwd(), "..", "inst", "decks", "lotusnoir.sqlite")
  )
  existing <- candidates[file.exists(candidates)]
  if (length(existing) > 0L) {
    return(existing[[1]])
  }

  candidates[[1]]
}

query_lotusnoir_db_connect <- function(db_path = "") {
  deps <- query_api_require_db()
  if (!isTRUE(deps)) {
    stop(query_api_scalar(deps$error, default = "database dependencies missing"))
  }

  target <- query_api_scalar(db_path, default = query_lotusnoir_default_db_path())
  if (!nzchar(target)) {
    stop("db_path is required")
  }

  dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
  query_db_connect(target)
}

query_lotusnoir_db_ensure_schema <- function(con) {
  if (is.null(con) || !DBI::dbIsValid(con)) {
    return(invisible(FALSE))
  }

  statements <- c(
    paste(
      "CREATE TABLE IF NOT EXISTS index_pages (",
      "index_url TEXT PRIMARY KEY,",
      "last_started_at TEXT,",
      "last_finished_at TEXT,",
      "status TEXT,",
      "discovered_urls INTEGER DEFAULT 0,",
      "last_error TEXT",
      ")"
    ),
    paste(
      "CREATE TABLE IF NOT EXISTS deck_urls (",
      "deck_url TEXT PRIMARY KEY,",
      "source_index_url TEXT,",
      "deck_did TEXT,",
      "first_seen_at TEXT,",
      "last_seen_at TEXT,",
      "download_status TEXT DEFAULT 'pending',",
      "download_started_at TEXT,",
      "download_finished_at TEXT,",
      "last_error TEXT,",
      "deck_id INTEGER",
      ")"
    ),
    paste(
      "CREATE TABLE IF NOT EXISTS decks (",
      "id INTEGER PRIMARY KEY AUTOINCREMENT,",
      "deck_url TEXT NOT NULL UNIQUE,",
      "deck_did TEXT,",
      "title TEXT,",
      "author TEXT,",
      "deck_date TEXT,",
      "category TEXT,",
      "format TEXT,",
      "deck_legal INTEGER DEFAULT 0,",
      "card_rows INTEGER DEFAULT 0,",
      "scraped_at TEXT,",
      "notes TEXT",
      ")"
    ),
    paste(
      "CREATE TABLE IF NOT EXISTS deck_cards (",
      "id INTEGER PRIMARY KEY AUTOINCREMENT,",
      "deck_id INTEGER NOT NULL,",
      "deck_url TEXT NOT NULL,",
      "section TEXT,",
      "quantity INTEGER DEFAULT 0,",
      "card_name_local TEXT,",
      "card_name_english TEXT,",
      "normalized_name TEXT,",
      "normalized_name_local TEXT,",
      "normalized_name_english TEXT,",
      "FOREIGN KEY(deck_id) REFERENCES decks(id)",
      ")"
    )
  )

  indexes <- c(
    "CREATE INDEX IF NOT EXISTS idx_lotus_deck_urls_status ON deck_urls(download_status)",
    "CREATE INDEX IF NOT EXISTS idx_lotus_deck_urls_deck_id ON deck_urls(deck_id)",
    "CREATE INDEX IF NOT EXISTS idx_lotus_decks_format ON decks(format)",
    "CREATE INDEX IF NOT EXISTS idx_lotus_deck_cards_deck_id ON deck_cards(deck_id)",
    "CREATE INDEX IF NOT EXISTS idx_lotus_deck_cards_norm ON deck_cards(normalized_name)",
    "CREATE INDEX IF NOT EXISTS idx_lotus_deck_cards_norm_en ON deck_cards(normalized_name_english)"
  )

  for (sql in c(statements, indexes)) {
    DBI::dbExecute(con, sql)
  }

  deck_urls_fields <- tolower(DBI::dbListFields(con, "deck_urls"))
  if (!("deck_did" %in% deck_urls_fields)) {
    DBI::dbExecute(con, "ALTER TABLE deck_urls ADD COLUMN deck_did TEXT")
  }

  decks_fields <- tolower(DBI::dbListFields(con, "decks"))
  if (!("deck_did" %in% decks_fields)) {
    DBI::dbExecute(con, "ALTER TABLE decks ADD COLUMN deck_did TEXT")
  }

  invisible(TRUE)
}

query_lotusnoir_now_text <- function() {
  format(Sys.time(), "%Y-%m-%d %H:%M:%S")
}

query_lotusnoir_db_mark_index_page <- function(con,
                                               index_url,
                                               status = "ok",
                                               discovered_urls = 0L,
                                               last_error = "",
                                               started = FALSE) {
  target <- query_api_scalar(index_url, default = "")
  if (!nzchar(target)) {
    return(invisible(FALSE))
  }

  now_text <- query_lotusnoir_now_text()
  existing <- DBI::dbGetQuery(
    con,
    "SELECT index_url FROM index_pages WHERE index_url = ? LIMIT 1",
    params = list(target)
  )

  if (is.data.frame(existing) && nrow(existing) > 0L) {
    if (isTRUE(started)) {
      DBI::dbExecute(
        con,
        paste(
          "UPDATE index_pages",
          "SET last_started_at = ?, status = ?, last_error = ?",
          "WHERE index_url = ?"
        ),
        params = list(now_text, status, query_api_scalar(last_error, default = ""), target)
      )
    } else {
      DBI::dbExecute(
        con,
        paste(
          "UPDATE index_pages",
          "SET last_finished_at = ?, status = ?, discovered_urls = ?, last_error = ?",
          "WHERE index_url = ?"
        ),
        params = list(
          now_text,
          status,
          as.integer(discovered_urls),
          query_api_scalar(last_error, default = ""),
          target
        )
      )
    }
    return(invisible(TRUE))
  }

  DBI::dbExecute(
    con,
    paste(
      "INSERT INTO index_pages (index_url, last_started_at, last_finished_at, status, discovered_urls, last_error)",
      "VALUES (?, ?, ?, ?, ?, ?)"
    ),
    params = list(
      target,
      if (isTRUE(started)) now_text else "",
      if (isTRUE(started)) "" else now_text,
      status,
      as.integer(discovered_urls),
      query_api_scalar(last_error, default = "")
    )
  )
  invisible(TRUE)
}

query_lotusnoir_db_upsert_deck_urls <- function(con,
                                                deck_urls,
                                                source_index_url = "",
                                                deck_dids = NULL) {
  urls <- unique(Filter(nzchar, as.character(deck_urls)))
  if (length(urls) == 0L) {
    return(invisible(0L))
  }

  now_text <- query_lotusnoir_now_text()
  inserted <- 0L
  source_value <- query_api_scalar(source_index_url, default = "")
  did_map <- NULL
  if (is.list(deck_dids)) {
    did_map <- deck_dids
  } else if (!is.null(deck_dids) && length(deck_dids) == length(deck_urls)) {
    did_map <- as.list(as.character(deck_dids))
    names(did_map) <- as.character(deck_urls)
  }

  for (target in urls) {
    target_did <- if (!is.null(did_map) && !is.null(did_map[[target]])) {
      query_api_scalar(did_map[[target]], default = "")
    } else {
      ""
    }
    existing <- DBI::dbGetQuery(
      con,
      "SELECT deck_url FROM deck_urls WHERE deck_url = ? LIMIT 1",
      params = list(target)
    )
    if (is.data.frame(existing) && nrow(existing) > 0L) {
      DBI::dbExecute(
        con,
        paste(
          "UPDATE deck_urls",
          "SET last_seen_at = ?, source_index_url = CASE WHEN coalesce(source_index_url, '') = '' THEN ? ELSE source_index_url END,",
          "deck_did = CASE WHEN coalesce(deck_did, '') = '' THEN ? ELSE deck_did END",
          "WHERE deck_url = ?"
        ),
        params = list(now_text, source_value, target_did, target)
      )
      next
    }

    DBI::dbExecute(
      con,
      paste(
        "INSERT INTO deck_urls (deck_url, source_index_url, deck_did, first_seen_at, last_seen_at, download_status)",
        "VALUES (?, ?, ?, ?, ?, 'pending')"
      ),
      params = list(target, source_value, target_did, now_text, now_text)
    )
    inserted <- inserted + 1L
  }

  invisible(as.integer(inserted))
}

query_lotusnoir_db_mark_deck_download <- function(con,
                                                  deck_url,
                                                  status = "pending",
                                                  last_error = "",
                                                  deck_id = NA_integer_,
                                                  started = FALSE) {
  target <- query_api_scalar(deck_url, default = "")
  if (!nzchar(target)) {
    return(invisible(FALSE))
  }

  now_text <- query_lotusnoir_now_text()
  if (isTRUE(started)) {
    DBI::dbExecute(
      con,
      paste(
        "UPDATE deck_urls",
        "SET download_status = ?, download_started_at = ?, last_error = ?",
        "WHERE deck_url = ?"
      ),
      params = list(status, now_text, query_api_scalar(last_error, default = ""), target)
    )
  } else {
    DBI::dbExecute(
      con,
      paste(
        "UPDATE deck_urls",
        "SET download_status = ?, download_finished_at = ?, last_error = ?, deck_id = ?",
        "WHERE deck_url = ?"
      ),
      params = list(
        status,
        now_text,
        query_api_scalar(last_error, default = ""),
        if (is.na(deck_id)) NA_integer_ else as.integer(deck_id),
        target
      )
    )
  }

  invisible(TRUE)
}

query_lotusnoir_db_upsert_deck <- function(con, deck) {
  if (is.null(con) || !DBI::dbIsValid(con) || !is.list(deck) || !isTRUE(deck$ok)) {
    return(query_api_error("valid connection and parsed deck are required"))
  }

  target <- query_api_scalar(deck$deck_url, default = "")
  if (!nzchar(target)) {
    return(query_api_error("deck_url is required"))
  }

  cards <- if (is.data.frame(deck$cards)) deck$cards else data.frame()
  now_text <- query_lotusnoir_now_text()
  existing <- DBI::dbGetQuery(
    con,
    "SELECT id FROM decks WHERE deck_url = ? LIMIT 1",
    params = list(target)
  )

  if (is.data.frame(existing) && nrow(existing) > 0L) {
    deck_id <- as.integer(existing$id[[1]])
    DBI::dbExecute(
      con,
      paste(
        "UPDATE decks",
        "SET deck_did = ?, title = ?, author = ?, deck_date = ?, category = ?, format = ?, deck_legal = ?, card_rows = ?, scraped_at = ?",
        "WHERE id = ?"
      ),
      params = list(
        query_api_scalar(deck$deck_did, default = ""),
        query_api_scalar(deck$title, default = ""),
        query_api_scalar(deck$author, default = ""),
        query_api_scalar(deck$date, default = ""),
        query_api_scalar(deck$category, default = ""),
        query_api_scalar(deck$format, default = ""),
        if (isTRUE(deck$deck_legal)) 1L else 0L,
        if (is.data.frame(cards)) nrow(cards) else 0L,
        now_text,
        deck_id
      )
    )
    DBI::dbExecute(con, "DELETE FROM deck_cards WHERE deck_id = ?", params = list(deck_id))
  } else {
    DBI::dbExecute(
      con,
      paste(
        "INSERT INTO decks (deck_url, deck_did, title, author, deck_date, category, format, deck_legal, card_rows, scraped_at)",
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
      ),
      params = list(
        target,
        query_api_scalar(deck$deck_did, default = ""),
        query_api_scalar(deck$title, default = ""),
        query_api_scalar(deck$author, default = ""),
        query_api_scalar(deck$date, default = ""),
        query_api_scalar(deck$category, default = ""),
        query_api_scalar(deck$format, default = ""),
        if (isTRUE(deck$deck_legal)) 1L else 0L,
        if (is.data.frame(cards)) nrow(cards) else 0L,
        now_text
      )
    )
    deck_id <- as.integer(DBI::dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id[[1]])
  }

  if (is.data.frame(cards) && nrow(cards) > 0L) {
    for (index in seq_len(nrow(cards))) {
      row <- cards[index, , drop = FALSE]
      local_name <- query_api_scalar(row$card_name_local, default = "")
      english_name <- query_api_scalar(row$card_name_english, default = "")
      normalized_english <- query_synergy_external_key(english_name)
      normalized_local <- query_synergy_external_key(local_name)
      normalized_name <- if (nzchar(normalized_english)) normalized_english else normalized_local

      DBI::dbExecute(
        con,
        paste(
          "INSERT INTO deck_cards (deck_id, deck_url, section, quantity, card_name_local, card_name_english, normalized_name, normalized_name_local, normalized_name_english)",
          "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
        ),
        params = list(
          deck_id,
          target,
          query_api_scalar(row$section, default = ""),
          query_synergy_as_int(row$quantity, default = 0L, min_value = 0L, max_value = 1000L),
          local_name,
          english_name,
          normalized_name,
          normalized_local,
          normalized_english
        )
      )
    }
  }

  list(
    ok = TRUE,
    deck_id = deck_id,
    deck_url = target,
    deck_did = query_api_scalar(deck$deck_did, default = ""),
    card_rows = if (is.data.frame(cards)) nrow(cards) else 0L
  )
}

query_lotusnoir_probe_neighbor_dids <- function(con,
                                                radius = 5L,
                                                max_probes = 500L,
                                                request_delay = 5,
                                                verbose = TRUE) {
  radius_value <- query_synergy_as_int(radius, default = 5L, min_value = 1L, max_value = 1000L)
  probe_limit <- query_synergy_as_int(max_probes, default = 500L, min_value = 1L, max_value = 100000L)

  seeds <- DBI::dbGetQuery(
    con,
    paste(
      "SELECT DISTINCT coalesce(deck_did, '') AS deck_did",
      "FROM decks",
      "WHERE coalesce(deck_did, '') <> ''"
    )
  )
  if (!is.data.frame(seeds) || nrow(seeds) == 0L) {
    return(list(ok = TRUE, tested = 0L, hits = 0L, inserted_urls = 0L, urls = character(0)))
  }

  seed_ids <- unique(suppressWarnings(as.integer(seeds$deck_did)))
  seed_ids <- seed_ids[is.finite(seed_ids) & !is.na(seed_ids) & seed_ids > 0L]
  if (length(seed_ids) == 0L) {
    return(list(ok = TRUE, tested = 0L, hits = 0L, inserted_urls = 0L, urls = character(0)))
  }

  candidate_ids <- integer(0)
  for (seed in seed_ids) {
    candidate_ids <- c(candidate_ids, seq.int(seed - radius_value, seed + radius_value))
  }
  candidate_ids <- unique(candidate_ids[candidate_ids > 0L])
  if (length(candidate_ids) > probe_limit) {
    candidate_ids <- candidate_ids[seq_len(probe_limit)]
  }

  known <- DBI::dbGetQuery(
    con,
    "SELECT DISTINCT coalesce(deck_did, '') AS deck_did FROM deck_urls WHERE coalesce(deck_did, '') <> ''"
  )
  known_ids <- unique(Filter(nzchar, as.character(known$deck_did)))
  candidate_ids <- setdiff(as.character(candidate_ids), known_ids)

  tested <- 0L
  hits <- 0L
  inserted_urls <- 0L
  discovered_urls <- character(0)

  for (index in seq_along(candidate_ids)) {
    if (tested > 0L && isTRUE(request_delay > 0)) {
      Sys.sleep(request_delay)
    }
    did <- candidate_ids[[index]]
    if (isTRUE(verbose)) {
      message(sprintf("LotusNoir probe %d/%d: did=%s", index, length(candidate_ids), did))
    }
    tested <- tested + 1L
    export_payload <- query_lotusnoir_fetch_deck_export(did)
    if (!isTRUE(export_payload$ok) || !query_lotusnoir_export_is_valid(export_payload$text)) {
      next
    }

    hits <- hits + 1L
    view_url <- query_lotusnoir_view_url(did)
    view_payload <- query_lotusnoir_read_text(view_url)
    if (!isTRUE(view_payload$ok)) {
      next
    }
    parsed <- query_lotusnoir_parse_deck_page(view_payload$text, deck_url = view_url)
    if (!isTRUE(parsed$ok)) {
      next
    }

    target_url <- query_api_scalar(parsed$deck_url, default = view_url)
    inserted_urls <- inserted_urls + query_lotusnoir_db_upsert_deck_urls(
      con,
      deck_urls = c(target_url),
      source_index_url = "did_probe",
      deck_dids = setNames(list(did), target_url)
    )
    discovered_urls <- c(discovered_urls, target_url)
    if (isTRUE(verbose)) {
      message(sprintf("  -> hit did=%s url=%s", did, target_url))
    }
  }

  list(
    ok = TRUE,
    tested = as.integer(tested),
    hits = as.integer(hits),
    inserted_urls = as.integer(inserted_urls),
    urls = unique(discovered_urls)
  )
}

#' Download LotusNoir Decks to SQLite
#'
#' Crawls LotusNoir deck pages and stores card data in a local SQLite database.
#' Can be run incrementally: existing decks are skipped unless
#' `overwrite_existing = TRUE`.
#'
#' @param db_path Character scalar. Path to the SQLite database file.
#'   Created if it does not exist.
#' @param max_decks Integer. Maximum number of decks to download (default `100`).
#' @param request_delay Numeric. Seconds to wait between HTTP requests
#'   (default `5`).
#' @param refresh_urls Logical. If `TRUE`, clears cached URLs before
#'   re-discovering them (default `FALSE`).
#' @param probe_radius Integer. Extra index pages to probe beyond the default
#'   set (default `0`).
#' @param probe_max_dids Integer. Cap on additional deck IDs to probe
#'   (default `0`).
#' @param overwrite_existing Logical. Re-download decks already in the database
#'   (default `FALSE`).
#' @param verbose Logical. Print progress messages (default `TRUE`).
#'
#' @return A list with `ok` (logical), `n_downloaded` (integer),
#'   `n_skipped` (integer), and `db_path` (character).
#'
#' @export
query_lotusnoir_download_decks_sqlite <- function(db_path = "",
                                                  max_decks = 100L,
                                                  request_delay = 5,
                                                  refresh_urls = FALSE,
                                                  probe_radius = 0L,
                                                  probe_max_dids = 0L,
                                                  overwrite_existing = FALSE,
                                                  verbose = TRUE) {
  con <- NULL
  on.exit({
    query_db_disconnect(con)
  }, add = TRUE)

  con <- query_lotusnoir_db_connect(db_path)
  query_lotusnoir_db_ensure_schema(con)

  if (isTRUE(refresh_urls)) {
    DBI::dbExecute(con, "DELETE FROM index_pages")
    DBI::dbExecute(con, "DELETE FROM deck_urls")
  }

  known_urls <- DBI::dbGetQuery(con, "SELECT deck_url FROM deck_urls ORDER BY deck_url")
  if (!is.data.frame(known_urls) || nrow(known_urls) == 0L) {
    index_urls <- query_lotusnoir_default_index_urls()
    for (index in seq_along(index_urls)) {
      if (index > 1L && isTRUE(request_delay > 0)) {
        Sys.sleep(request_delay)
      }

      target <- index_urls[[index]]
      if (isTRUE(verbose)) {
        message(sprintf("LotusNoir index %d/%d: %s", index, length(index_urls), target))
      }

      query_lotusnoir_db_mark_index_page(con, target, status = "running", started = TRUE)
      payload <- query_lotusnoir_read_text(target)
      if (!isTRUE(payload$ok)) {
        query_lotusnoir_db_mark_index_page(con, target, status = "error", last_error = query_api_scalar(payload$error, default = "read failed"))
        next
      }

      page_urls <- query_lotusnoir_extract_deck_urls(payload$text)
      query_lotusnoir_db_upsert_deck_urls(con, page_urls, source_index_url = target)
      query_lotusnoir_db_mark_index_page(con, target, status = "ok", discovered_urls = length(page_urls))
      if (isTRUE(verbose)) {
        message(sprintf("  -> cached URLs: %d", DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM deck_urls")$n[[1]]))
      }
    }
    known_urls <- DBI::dbGetQuery(con, "SELECT deck_url FROM deck_urls ORDER BY deck_url")
  } else if (isTRUE(verbose)) {
    message(sprintf("Using cached deck URLs: %d", nrow(known_urls)))
  }

  probe_radius_value <- query_synergy_as_int(probe_radius, default = 0L, min_value = 0L, max_value = 1000L)
  probe_max_value <- query_synergy_as_int(probe_max_dids, default = 0L, min_value = 0L, max_value = 100000L)
  probe_out <- NULL
  if (probe_radius_value > 0L && probe_max_value > 0L) {
    probe_out <- query_lotusnoir_probe_neighbor_dids(
      con,
      radius = probe_radius_value,
      max_probes = probe_max_value,
      request_delay = request_delay,
      verbose = verbose
    )
    known_urls <- DBI::dbGetQuery(con, "SELECT deck_url FROM deck_urls ORDER BY deck_url")
    if (isTRUE(verbose)) {
      message(sprintf(
        "LotusNoir did probe: tested=%d hits=%d inserted_urls=%d",
        query_synergy_as_int(probe_out$tested, default = 0L, min_value = 0L, max_value = 10000000L),
        query_synergy_as_int(probe_out$hits, default = 0L, min_value = 0L, max_value = 10000000L),
        query_synergy_as_int(probe_out$inserted_urls, default = 0L, min_value = 0L, max_value = 10000000L)
      ))
    }
  }

  deck_urls <- unique(Filter(nzchar, as.character(known_urls$deck_url)))
  max_value <- suppressWarnings(as.integer(max_decks))
  if (is.finite(max_value) && !is.na(max_value) && max_value > 0L && length(deck_urls) > max_value) {
    deck_urls <- deck_urls[seq_len(max_value)]
  }

  processed <- 0L
  skipped <- 0L
  failed <- list()
  stored_rows <- 0L
  deck_request_count <- 0L

  for (index in seq_along(deck_urls)) {
    target <- deck_urls[[index]]
    if (!isTRUE(overwrite_existing)) {
      existing <- DBI::dbGetQuery(
        con,
        "SELECT id FROM decks WHERE deck_url = ? LIMIT 1",
        params = list(target)
      )
      if (is.data.frame(existing) && nrow(existing) > 0L) {
        if (isTRUE(verbose)) {
          message(sprintf("LotusNoir deck %d/%d: %s [skip: already stored]", index, length(deck_urls), target))
        }
        skipped <- skipped + 1L
        next
      }
    }

    if (deck_request_count > 0L && isTRUE(request_delay > 0)) {
      Sys.sleep(request_delay)
    }
    deck_request_count <- deck_request_count + 1L

    if (isTRUE(verbose)) {
      message(sprintf("LotusNoir deck %d/%d: %s", index, length(deck_urls), target))
    }
    query_lotusnoir_db_mark_deck_download(con, target, status = "running", started = TRUE)
    deck <- query_lotusnoir_fetch_deck(target)
    if (!isTRUE(deck$ok)) {
      query_lotusnoir_db_mark_deck_download(con, target, status = "error", last_error = query_api_scalar(deck$error, default = "fetch failed"))
      failed[[length(failed) + 1L]] <- list(deck_url = target, error = query_api_scalar(deck$error, default = "fetch failed"))
      next
    }

    stored <- query_lotusnoir_db_upsert_deck(con, deck)
    if (!isTRUE(stored$ok)) {
      query_lotusnoir_db_mark_deck_download(con, target, status = "error", last_error = query_api_scalar(stored$error, default = "store failed"))
      failed[[length(failed) + 1L]] <- list(deck_url = target, error = query_api_scalar(stored$error, default = "store failed"))
      next
    }

    query_lotusnoir_db_mark_deck_download(con, target, status = "ok", deck_id = stored$deck_id)
    if (nzchar(query_api_scalar(stored$deck_did, default = ""))) {
      DBI::dbExecute(
        con,
        "UPDATE deck_urls SET deck_did = ? WHERE deck_url = ?",
        params = list(query_api_scalar(stored$deck_did, default = ""), target)
      )
    }
    processed <- processed + 1L
    stored_rows <- stored_rows + query_synergy_as_int(stored$card_rows, default = 0L, min_value = 0L, max_value = 10000L)
  }

  list(
    ok = TRUE,
    source = "lotusnoir_sqlite",
    db_path = normalizePath(query_api_scalar(db_path, default = query_lotusnoir_default_db_path()), winslash = "/", mustWork = FALSE),
    discovered_deck_urls = length(deck_urls),
    probe = probe_out,
    processed_decks = processed,
    skipped_decks = skipped,
    stored_rows = stored_rows,
    failed = failed
  )
}

#' Card Co-occurrence Statistics from the LotusNoir Database
#'
#' Queries the local LotusNoir SQLite database for decks containing a given
#' seed card and returns co-occurrence frequency statistics for the top
#' companion cards.
#'
#' @param card_name Character scalar. Name of the seed card.
#' @param db_path Character scalar. Path to the LotusNoir SQLite database.
#'   Uses the default path if empty.
#' @param format_name Character scalar. Filter decks by format name
#'   (empty string = no filter).
#' @param top_n Integer. Number of top companion cards to return (default `25`).
#' @param deck_limit Integer. Maximum number of decks to sample (default `20`).
#'
#' @return A list with `ok` (logical), `seed` (character), `decks_sampled`
#'   (integer), and `stats` (data.frame with columns `name`, `count`,
#'   `frequency`).
#'
#' @export
query_lotusnoir_card_stats <- function(card_name,
                                       db_path = "",
                                       format_name = "",
                                       top_n = 25L,
                                       deck_limit = 20L) {
  seed_name <- query_api_scalar(card_name, default = "")
  if (!nzchar(seed_name)) {
    return(query_api_error("card_name is required"))
  }

  deps <- query_api_require_db()
  if (!isTRUE(deps)) {
    return(deps)
  }

  db_target <- query_api_scalar(db_path, default = query_lotusnoir_default_db_path())
  if (!nzchar(db_target) || !file.exists(db_target)) {
    return(query_api_error("lotusnoir sqlite database not found", db_path = db_target))
  }

  seed_key <- query_synergy_external_key(seed_name)
  if (!nzchar(seed_key)) {
    return(query_api_error("card_name normalization failed"))
  }

  format_filter <- tolower(query_api_scalar(format_name, default = ""))
  top_n_value <- query_synergy_as_int(top_n, default = 25L, min_value = 1L, max_value = 500L)
  deck_limit_value <- query_synergy_as_int(deck_limit, default = 20L, min_value = 1L, max_value = 500L)

  con <- NULL
  on.exit({
    query_db_disconnect(con)
  }, add = TRUE)

  con <- query_db_connect(db_target)
  query_lotusnoir_db_ensure_schema(con)

  filter_sql <- ""
  filter_params <- list(seed_key)
  if (nzchar(format_filter)) {
    filter_sql <- " AND lower(coalesce(d.format, '')) = lower(?)"
    filter_params <- c(filter_params, list(format_filter))
  }

  base_sql <- paste0(
    "FROM deck_cards dc ",
    "JOIN decks d ON d.id = dc.deck_id ",
    "WHERE coalesce(dc.normalized_name, '') = ?",
    filter_sql
  )

  overall <- DBI::dbGetQuery(
    con,
    paste(
      "SELECT",
      "COUNT(DISTINCT dc.deck_id) AS deck_count,",
      "COALESCE(SUM(dc.quantity), 0) AS total_quantity,",
      "COALESCE(AVG(dc.quantity), 0) AS average_quantity_per_deck",
      base_sql
    ),
    params = filter_params
  )

  formats <- DBI::dbGetQuery(
    con,
    paste(
      "SELECT",
      "coalesce(d.format, '') AS format,",
      "COUNT(DISTINCT dc.deck_id) AS deck_count,",
      "COALESCE(SUM(dc.quantity), 0) AS total_quantity",
      base_sql,
      "GROUP BY coalesce(d.format, '')",
      "ORDER BY deck_count DESC, format ASC"
    ),
    params = filter_params
  )

  cooccurrences <- DBI::dbGetQuery(
    con,
    paste0(
      "SELECT ",
      "coalesce(nullif(dc2.normalized_name_english, ''), dc2.normalized_name) AS normalized_name, ",
      "MAX(coalesce(nullif(dc2.card_name_english, ''), dc2.card_name_local)) AS card_name, ",
      "COUNT(DISTINCT dc1.deck_id) AS cooccur_deck_count, ",
      "COALESCE(SUM(dc2.quantity), 0) AS total_quantity, ",
      "COALESCE(AVG(dc2.quantity), 0) AS average_quantity_per_deck ",
      "FROM deck_cards dc1 ",
      "JOIN decks d ON d.id = dc1.deck_id ",
      "JOIN deck_cards dc2 ON dc1.deck_id = dc2.deck_id ",
      "WHERE coalesce(dc1.normalized_name, '') = ?",
      filter_sql,
      " AND coalesce(dc2.normalized_name, '') <> ? ",
      "GROUP BY coalesce(nullif(dc2.normalized_name_english, ''), dc2.normalized_name) ",
      "ORDER BY cooccur_deck_count DESC, total_quantity DESC, card_name ASC ",
      "LIMIT ", as.character(top_n_value)
    ),
    params = c(filter_params, list(seed_key))
  )

  decks <- DBI::dbGetQuery(
    con,
    paste0(
      "SELECT ",
      "d.id AS deck_id, ",
      "d.deck_url, d.title, d.author, d.deck_date, d.category, d.format, d.deck_legal, ",
      "dc.quantity AS card_quantity ",
      base_sql,
      " ORDER BY d.deck_date DESC, d.title ASC ",
      "LIMIT ", as.character(deck_limit_value)
    ),
    params = filter_params
  )

  deck_count <- if (is.data.frame(overall) && nrow(overall) > 0L) overall$deck_count[[1]] else 0L
  total_quantity <- if (is.data.frame(overall) && nrow(overall) > 0L) overall$total_quantity[[1]] else 0L

  if (is.data.frame(cooccurrences) && nrow(cooccurrences) > 0L && deck_count > 0L) {
    cooccurrences$share_of_seed_decks <- round(cooccurrences$cooccur_deck_count / deck_count, 6)
  } else if (is.data.frame(cooccurrences) && !("share_of_seed_decks" %in% names(cooccurrences))) {
    cooccurrences$share_of_seed_decks <- numeric(nrow(cooccurrences))
  }

  list(
    ok = TRUE,
    source = "lotusnoir_sqlite",
    db_path = normalizePath(db_target, winslash = "/", mustWork = FALSE),
    card_name = seed_name,
    normalized_name = seed_key,
    format_filter = format_filter,
    stats = list(
      deck_count = query_synergy_as_int(deck_count, default = 0L, min_value = 0L, max_value = 100000000L),
      total_quantity = query_synergy_as_int(total_quantity, default = 0L, min_value = 0L, max_value = 100000000L),
      average_quantity_per_deck = if (is.data.frame(overall) && nrow(overall) > 0L) round(query_synergy_as_num(overall$average_quantity_per_deck[[1]], default = 0, min_value = 0), 4) else 0
    ),
    formats = if (is.data.frame(formats)) formats else data.frame(),
    cooccurrences = if (is.data.frame(cooccurrences)) cooccurrences else data.frame(),
    decks = if (is.data.frame(decks)) decks else data.frame()
  )
}

#' Download LotusNoir Decks to CSV
#'
#' Crawls LotusNoir deck pages and appends card rows to a CSV file.
#' Suitable for a lightweight export without SQLite.
#'
#' @param output_csv Character scalar. Path to the output CSV file.
#' @param deck_urls Character vector. Specific deck URLs to download.
#'   If empty, URLs are discovered from `index_urls`.
#' @param index_urls Character vector. Index page URLs used for discovery
#'   when `deck_urls` is empty. Defaults to standard LotusNoir index pages.
#' @param max_decks Integer. Maximum number of decks to download (default `100`).
#' @param request_delay Numeric. Seconds to wait between HTTP requests
#'   (default `20`).
#' @param append Logical. Append to existing CSV file (default `TRUE`).
#' @param verbose Logical. Print progress messages (default `TRUE`).
#'
#' @return A list with `ok` (logical), `n_downloaded` (integer),
#'   `n_skipped` (integer), and `output_csv` (character).
#'
#' @export
query_lotusnoir_download_decks_csv <- function(output_csv,
                                               deck_urls = NULL,
                                               index_urls = NULL,
                                               max_decks = 100L,
                                               request_delay = 20,
                                               append = TRUE,
                                               verbose = TRUE) {
  csv_path <- query_api_scalar(output_csv, default = "")
  if (!nzchar(csv_path)) {
    return(query_api_error("output_csv is required"))
  }

  selected_urls <- unique(Filter(nzchar, as.character(deck_urls %||% character(0))))
  discovery <- NULL
  if (length(selected_urls) == 0L) {
    discovery <- query_lotusnoir_discover_deck_urls(
      index_urls = index_urls,
      request_delay = request_delay,
      verbose = verbose
    )
    selected_urls <- query_synergy_to_vector(discovery$urls)
  }

  max_value <- suppressWarnings(as.integer(max_decks))
  if (!is.finite(max_value) || is.na(max_value) || max_value < 1L) {
    max_value <- length(selected_urls)
  }
  if (length(selected_urls) > max_value) {
    selected_urls <- selected_urls[seq_len(max_value)]
  }

  existing_urls <- character(0)
  file_exists <- file.exists(csv_path)
  if (isTRUE(append) && isTRUE(file_exists)) {
    existing <- tryCatch(
      utils::read.csv(csv_path, stringsAsFactors = FALSE),
      error = function(e) NULL
    )
    if (is.data.frame(existing) && "deck_url" %in% names(existing)) {
      existing_urls <- unique(Filter(nzchar, as.character(existing$deck_url)))
    }
  }

  pending_urls <- setdiff(selected_urls, existing_urls)
  processed <- 0L
  written_rows <- 0L
  failed <- list()
  write_header <- !file_exists || !isTRUE(append)

  for (index in seq_along(pending_urls)) {
    if (index > 1L && isTRUE(request_delay > 0)) {
      Sys.sleep(request_delay)
    }
    target <- pending_urls[[index]]
    if (isTRUE(verbose)) {
      message(sprintf("LotusNoir deck %d/%d: %s", index, length(pending_urls), target))
    }
    deck <- query_lotusnoir_fetch_deck(target)
    if (!isTRUE(deck$ok) || !is.data.frame(deck$cards) || nrow(deck$cards) == 0L) {
      failed[[length(failed) + 1L]] <- list(
        deck_url = target,
        error = query_api_scalar(deck$error, default = "deck parse failed")
      )
      next
    }

    utils::write.table(
      deck$cards,
      file = csv_path,
      sep = ",",
      row.names = FALSE,
      col.names = write_header,
      append = !write_header,
      qmethod = "double"
    )
    write_header <- FALSE
    processed <- processed + 1L
    written_rows <- written_rows + nrow(deck$cards)
  }

  list(
    ok = TRUE,
    source = "lotusnoir_deck_html",
    output_csv = csv_path,
    discovered_count = length(selected_urls),
    skipped_existing = length(existing_urls),
    processed_decks = processed,
    written_rows = written_rows,
    failed = failed,
    discovered_urls = selected_urls,
    discovery = discovery
  )
}


