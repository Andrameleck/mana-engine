.deck_scalar <- function(x, default = "") {
  if (is.null(x) || !length(x)) return(default)
  value <- trimws(as.character(x[[1]]))
  if (is.na(value) || !nzchar(value)) default else value
}

.deck_json_vector <- function(x) {
  if (is.null(x) || !length(x)) return(character(0))
  if (is.list(x) && !is.data.frame(x)) return(unique(toupper(as.character(unlist(x, use.names = FALSE)))))
  raw <- .deck_scalar(x)
  parsed <- tryCatch(jsonlite::fromJSON(raw), error = function(e) NULL)
  if (!is.null(parsed)) unique(toupper(as.character(unlist(parsed, use.names = FALSE)))) else unique(strsplit(toupper(raw), "[^WUBRG]+")[[1]])
}

.deck_card_record <- function(row, owned = FALSE) {
  field <- function(name, default = "") if (name %in% names(row)) .deck_scalar(row[[name]], default) else default
  list(
    scryfall_id = field("scryfall_id"), name = field("name"), type_line = field("type_line"),
    oracle_text = field("oracle_text"), mana_cost = field("mana_cost"),
    color_identity = .deck_json_vector(row[["color_identity"]]),
    keywords = field("keywords"), legalities = field("legalities"),
    edhrec_rank = suppressWarnings(as.numeric(field("edhrec_rank", "999999"))),
    owned = isTRUE(owned)
  )
}

.deck_is_commander <- function(card) {
  type <- tolower(card$type_line %||% "")
  text <- tolower(card$oracle_text %||% "")
  grepl("legendary.*creature", type) || grepl("can be your commander", text, fixed = TRUE)
}

.deck_legality_status <- function(card, format = "commander") {
  format <- tolower(.deck_scalar(format, "commander"))
  legalities <- card$legalities
  if (is.null(legalities) || !length(legalities)) return("unknown")
  parsed <- if (is.list(legalities)) legalities else {
    raw <- .deck_scalar(legalities)
    if (!nzchar(raw)) return("unknown")
    tryCatch(jsonlite::fromJSON(raw, simplifyVector = TRUE), error = function(e) NULL)
  }
  if (is.null(parsed) || is.null(parsed[[format]])) return("unknown")
  status <- tolower(.deck_scalar(parsed[[format]]))
  if (status %in% c("legal", "restricted", "banned", "not_legal")) status else "unknown"
}

.deck_is_legal <- function(card, identity, commander_name = "", format = "commander",
                           exclude_banned = TRUE) {
  if (!nzchar(card$name) || identical(tolower(card$name), tolower(commander_name))) return(FALSE)
  if (length(setdiff(card$color_identity, identity))) return(FALSE)
  if (isTRUE(exclude_banned)) {
    status <- .deck_legality_status(card, format)
    if (status %in% c("banned", "not_legal")) return(FALSE)
  }
  !grepl("conspiracy|scheme|plane|phenomenon|vanguard", tolower(card$type_line))
}

.deck_tokens <- function(text) {
  words <- unlist(strsplit(tolower(gsub("[^a-z0-9+/-]+", " ", text)), "\\s+"), use.names = FALSE)
  stop <- c("the", "and", "that", "this", "with", "from", "your", "you", "each", "when", "whenever", "target", "card", "cards", "creature", "creatures")
  unique(words[nchar(words) >= 4L & !words %in% stop])
}

.deck_role <- function(card) {
  type <- tolower(card$type_line)
  text <- tolower(card$oracle_text)
  if (grepl("land", type)) return("land")
  if (grepl("add .*mana|search your library for .*land|treasure token", text)) return("ramp")
  if (grepl("draw .*card|investigate|impulse|exile .*you may (play|cast)", text)) return("card_draw")
  if (grepl("destroy target|exile target|counter target spell|deals? .*damage to|return target .* to (its|their) owner's hand", text)) return("removal")
  if (grepl("creature", type) && (grepl("trample|double strike|flying|menace|indestructible", paste(text, tolower(card$keywords))) || grepl("\\{[5-9]\\}", card$mana_cost))) return("threat")
  "core"
}

.deck_score <- function(card, commander, owned = FALSE) {
  commander_tokens <- .deck_tokens(paste(commander$oracle_text, commander$keywords))
  card_tokens <- .deck_tokens(paste(card$oracle_text, card$keywords, card$type_line))
  overlap <- length(intersect(commander_tokens, card_tokens))
  relation_signal <- tryCatch({
    context <- analysis_context(allowed_colors = commander$color_identity)
    relations <- c(
      functional_relations(commander, card, context),
      functional_relations(card, commander, context)
    )
    sum(vapply(relations, function(x) as.numeric(x$interface_coverage %||% 0), numeric(1)), na.rm = TRUE)
  }, error = function(e) 0)
  rank_bonus <- if (is.finite(card$edhrec_rank)) max(0, 18 - log10(max(1, card$edhrec_rank)) * 3) else 0
  as.numeric(round(20 + 8 * overlap + 14 * min(relation_signal, 2) + rank_bonus + if (owned) 12 else 0, 2))
}

.deck_reference_cards <- function() {
  path <- query_collection_default_db_path()
  if (!nzchar(path) || !file.exists(path)) return(list())
  con <- query_db_connect(path)
  on.exit(query_db_disconnect(con), add = TRUE)
  rows <- DBI::dbGetQuery(con, paste(
    "SELECT scryfall_id, name, type_line, oracle_text, mana_cost, color_identity,",
    "keywords, legalities, edhrec_rank FROM cards",
    "WHERE lower(COALESCE(lang, 'en')) = 'en' OR COALESCE(lang, '') = ''",
    "ORDER BY COALESCE(edhrec_rank, 999999), COALESCE(released_at, '') DESC"
  ))
  rows <- rows[!duplicated(tolower(rows$name)), , drop = FALSE]
  lapply(seq_len(nrow(rows)), function(i) .deck_card_record(as.list(rows[i, , drop = FALSE])))
}

.deck_scryfall_get <- function(url) {
  if (!requireNamespace("curl", quietly = TRUE)) return(NULL)
  tryCatch({
    response <- curl::curl_fetch_memory(url, handle = curl::new_handle(useragent = "Mana-Engine/0.2 deck-builder"))
    if (response$status_code < 200L || response$status_code >= 300L) return(NULL)
    body <- rawToChar(response$content)
    Encoding(body) <- "UTF-8"
    jsonlite::fromJSON(body, simplifyVector = FALSE)
  }, error = function(e) NULL)
}

.deck_scryfall_card <- function(x) {
  if (is.data.frame(x)) x <- as.list(x[1, , drop = FALSE])
  if (is.atomic(x) && !is.null(names(x))) x <- as.list(x)
  if (!is.list(x)) return(NULL)
  list(
    scryfall_id = .deck_scalar(x$id), name = .deck_scalar(x$name), type_line = .deck_scalar(x$type_line),
    oracle_text = .deck_scalar(x$oracle_text), mana_cost = .deck_scalar(x$mana_cost),
    color_identity = .deck_json_vector(x$color_identity), keywords = paste(unlist(x$keywords %||% list()), collapse = ", "),
    legalities = jsonlite::toJSON(x$legalities %||% list(), auto_unbox = TRUE),
    edhrec_rank = suppressWarnings(as.numeric(x$edhrec_rank %||% 999999)), owned = FALSE
  )
}

.deck_payload_cards <- function(x) {
  if (is.null(x) || !length(x)) return(list())
  if (is.data.frame(x)) {
    return(lapply(seq_len(nrow(x)), function(i) .deck_scryfall_card(x[i, , drop = FALSE])))
  }
  if (is.list(x) && length(x) && !is.null(names(x)) && any(c("id", "name", "type_line") %in% names(x))) {
    card <- .deck_scryfall_card(x)
    return(if (is.null(card)) list() else list(card))
  }
  cards <- lapply(x, .deck_scryfall_card)
  Filter(Negate(is.null), cards)
}

.deck_scryfall_named <- function(name) {
  payload <- .deck_scryfall_get(paste0("https://api.scryfall.com/cards/named?fuzzy=", utils::URLencode(name, reserved = TRUE)))
  if (is.null(payload) || !is.null(payload$object) && payload$object == "error") NULL else .deck_scryfall_card(payload)
}

.deck_scryfall_pool <- function(identity, format = "commander", exclude_banned = TRUE, limit = 350L) {
  identity_code <- paste0(tolower(identity), collapse = "")
  legality_query <- if (isTRUE(exclude_banned)) paste0("legal:", format) else ""
  query <- paste(legality_query, "game:paper -is:funny", if (nzchar(identity_code)) paste0("id<=", identity_code) else "id=c")
  url <- paste0("https://api.scryfall.com/cards/search?order=edhrec&unique=cards&q=", utils::URLencode(query, reserved = TRUE))
  out <- list()
  while (nzchar(url) && length(out) < limit) {
    payload <- .deck_scryfall_get(url)
    if (is.null(payload) || !length(payload$data)) break
    out <- c(out, lapply(payload$data, .deck_scryfall_card))
    url <- if (isTRUE(payload$has_more) && nzchar(.deck_scalar(payload$next_page))) .deck_scalar(payload$next_page) else ""
    if (nzchar(url)) Sys.sleep(0.1)
  }
  out[seq_len(min(length(out), limit))]
}

.deck_owned_names <- function(collection_id) {
  if (!nzchar(collection_id)) return(character(0))
  collection <- query_collections_get(collection_id)
  if (!isTRUE(collection$ok)) return(character(0))
  unique(tolower(vapply(collection$rows, function(x) .deck_scalar(x$name), character(1))))
}

.deck_pick <- function(pool, commander, variant = 1L) {
  if (!length(pool)) return(list())
  scored <- lapply(pool, function(card) {
    if (is.null(card$slot_role)) card$slot_role <- .deck_role(card)
    if (is.null(card$score)) card$score <- .deck_score(card, commander, card$owned)
    card
  })
  # Stable variants alter tie-breaking without turning generation into a lottery.
  keys <- vapply(scored, function(x) paste0(x$name, "#", variant), character(1))
  jitter <- vapply(keys, function(x) sum(utf8ToInt(x)) %% 17, numeric(1)) / 100
  for (i in seq_along(scored)) scored[[i]]$score <- scored[[i]]$score + jitter[[i]]
  quotas <- c(land = 36L, ramp = 10L, card_draw = 10L, removal = 10L, threat = 8L, core = 25L)
  selected <- list()
  used <- character(0)
  for (role in names(quotas)) {
    candidates <- Filter(function(x) x$slot_role == role && !tolower(x$name) %in% used, scored)
    candidates <- candidates[order(-vapply(candidates, `[[`, numeric(1), "score"), vapply(candidates, `[[`, character(1), "name"))]
    take <- head(candidates, quotas[[role]])
    selected <- c(selected, take)
    used <- c(used, tolower(vapply(take, `[[`, character(1), "name")))
  }
  if (length(selected) < 99L) {
    remaining <- Filter(function(x) !tolower(x$name) %in% used, scored)
    remaining <- remaining[order(-vapply(remaining, `[[`, numeric(1), "score"))]
    selected <- c(selected, head(remaining, 99L - length(selected)))
  }
  head(selected, 99L)
}

.deck_summary <- function(cards, commander, variant) {
  roles <- vapply(cards, `[[`, character(1), "slot_role")
  role_counts <- as.list(table(factor(roles, levels = c("land", "ramp", "card_draw", "removal", "threat", "core"))))
  owned <- sum(vapply(cards, `[[`, logical(1), "owned"))
  list(
    variant = variant, commander = commander, mainboard = cards,
    card_count = length(cards) + 1L, mainboard_count = length(cards),
    requires_commander = TRUE, total_score = round(mean(vapply(cards, `[[`, numeric(1), "score"))),
    score_base = round(mean(vapply(cards, `[[`, numeric(1), "score"))),
    score_modifiers = list(collection = list(amount = owned)),
    role_counts = role_counts,
    role_target = list(land = 36L, ramp = 10L, card_draw = 10L, removal = 10L, threat = 8L, core = 25L),
    curve_counts = list(), curve_target = list(), detected_combos = list(),
    owned_count = owned, missing_count = length(cards) - owned
  )
}

#' Generate Commander Decks
#' @param payload Request body containing commander, collection_id and variant_count.
#' @return API response containing legal scored deck variants.
#' @export
query_deck_generate <- function(payload) {
  if (is.null(payload) || !is.list(payload)) return(query_api_error("JSON body is required", status = 400L))
  commander_name <- .deck_scalar(payload$commander)
  if (!nzchar(commander_name)) return(query_api_error("commander is required", status = 400L))
  variants <- max(1L, min(5L, suppressWarnings(as.integer(payload$variant_count %||% 1L))))
  if (!is.finite(variants)) variants <- 1L
  collection_id <- .deck_scalar(payload$collection_id)
  collection_only <- isTRUE(payload$collection_only)
  if (collection_only && !nzchar(collection_id)) {
    return(query_api_error("collection_id is required when collection_only is enabled", status = 400L))
  }
  requested_format <- tolower(.deck_scalar(payload$format, "commander"))
  supported_formats <- c("commander", "brawl", "modern", "legacy", "vintage", "pioneer", "standard", "pauper", "historic")
  format <- if (requested_format %in% supported_formats) requested_format else "commander"
  exclude_banned <- if (is.null(payload$exclude_banned)) TRUE else isTRUE(payload$exclude_banned)

  local <- .deck_reference_cards()
  supplied_commander <- .deck_payload_cards(payload$commander_card)
  commander <- Filter(function(x) identical(tolower(x$name), tolower(commander_name)), local)
  commander <- if (length(commander)) commander[[1]] else if (length(supplied_commander)) supplied_commander[[1]] else .deck_scryfall_named(commander_name)
  if (is.null(commander)) return(query_api_error("commander not found", status = 404L))
  if (!.deck_is_commander(commander)) return(query_api_error("selected card cannot be a commander", status = 422L))
  commander_legality <- .deck_legality_status(commander, format)
  if (exclude_banned && commander_legality %in% c("banned", "not_legal")) {
    return(query_api_error(
      sprintf("selected commander is %s in %s", commander_legality, format),
      status = 422L, format = format, legality_status = commander_legality
    ))
  }
  identity <- commander$color_identity
  owned_names <- .deck_owned_names(collection_id)

  supplied <- payload$catalog_candidates
  remote <- .deck_payload_cards(supplied)
  if (!length(remote)) remote <- .deck_scryfall_pool(identity, format, exclude_banned)
  pool <- c(remote, local)
  pool <- pool[!duplicated(tolower(vapply(pool, `[[`, character(1), "name")))]
  pool_before_legality <- length(pool)
  pool <- Filter(function(x) .deck_is_legal(x, identity, commander$name, format, exclude_banned), pool)
  excluded_count <- pool_before_legality - length(pool)
  for (i in seq_along(pool)) pool[[i]]$owned <- tolower(pool[[i]]$name) %in% owned_names
  if (collection_only) pool <- Filter(function(x) isTRUE(x$owned), pool)
  for (i in seq_along(pool)) pool[[i]]$slot_role <- .deck_role(pool[[i]])
  # Keep strong candidates from every structural role before the more costly
  # functional analysis. This prevents popular spells from crowding out lands
  # or interaction while bounding response time.
  role_names <- c("land", "ramp", "card_draw", "removal", "threat", "core")
  pool <- unlist(lapply(role_names, function(role) {
    candidates <- Filter(function(x) x$slot_role == role, pool)
    candidates <- candidates[order(
      -vapply(candidates, function(x) as.integer(isTRUE(x$owned)), integer(1)),
      vapply(candidates, function(x) if (is.finite(x$edhrec_rank)) x$edhrec_rank else 999999, numeric(1))
    )]
    head(candidates, if (role == "core") 300L else 120L)
  }), recursive = FALSE)
  for (i in seq_along(pool)) pool[[i]]$score <- .deck_score(pool[[i]], commander, pool[[i]]$owned)
  decks <- lapply(seq_len(variants), function(i) .deck_summary(.deck_pick(pool, commander, i), commander, i))
  complete <- vapply(decks, function(x) length(x$mainboard) == 99L, logical(1))
  if (!all(complete)) {
    message <- if (collection_only) {
      "selected collection cannot build a complete legal 99-card mainboard"
    } else {
      "candidate pool cannot build a complete 99-card deck"
    }
    return(query_api_error(message, status = 422L, candidate_count = length(pool), collection_only = collection_only))
  }
  list(
    ok = TRUE, format = format, format_label = tools::toTitleCase(format),
    commander_name = commander$name, requires_commander = TRUE,
    legality_filter = list(
      exclude_banned = exclude_banned,
      format = format,
      commander_status = commander_legality,
      excluded_candidate_count = excluded_count,
      unknown_candidate_count = sum(vapply(pool, function(x) .deck_legality_status(x, format) == "unknown", logical(1)))
    ),
    using_collection = nzchar(collection_id), collection_only = collection_only,
    candidate_count = length(pool),
    catalog_source = if (length(remote)) "scryfall+local" else "local-cache",
    deck_count = length(decks), decks = decks,
    model_version = "commander-builder-0.2.0"
  )
}
