query_strategy_bridge_equation <- function(req = NULL) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    return(query_api_error("jsonlite package is required"))
  }

  payload_raw <- ""
  if (!is.null(req$postBody)) {
    payload_raw <- as.character(req$postBody)
  } else if (!is.null(req$body)) {
    payload_raw <- tryCatch(
      jsonlite::toJSON(req$body, auto_unbox = TRUE, null = "null"),
      error = function(e) ""
    )
  }
  payload_raw <- trimws(payload_raw)
  if (!nzchar(payload_raw)) {
    return(query_api_error("missing JSON payload"))
  }

  payload <- tryCatch(
    jsonlite::fromJSON(payload_raw, simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (is.null(payload) || !is.list(payload)) {
    return(query_api_error("invalid JSON payload"))
  }

  cards_raw <- payload$cards
  if (!is.list(cards_raw) || length(cards_raw) < 3L) {
    return(query_api_error("payload.cards must contain at least 3 cards"))
  }

  cards <- lapply(cards_raw, query_strategy_bridge_normalize_card)
  card_ids <- vapply(cards, function(card) card$id, character(1))
  if (any(!nzchar(card_ids)) || anyDuplicated(card_ids) > 0L) {
    return(query_api_error("payload.cards must provide unique non-empty ids"))
  }

  seed_a <- query_api_scalar(payload$seed_a, default = query_api_scalar(payload$A_id, default = ""))
  seed_b <- query_api_scalar(payload$seed_b, default = query_api_scalar(payload$B_id, default = ""))
  if (!nzchar(seed_a) || !nzchar(seed_b)) {
    return(query_api_error("seed_a and seed_b are required"))
  }
  if (!seed_a %in% card_ids) {
    return(query_api_error("seed_a not found in payload.cards"))
  }
  if (!seed_b %in% card_ids) {
    return(query_api_error("seed_b not found in payload.cards"))
  }

  known_synergies <- query_strategy_bridge_normalize_known_synergies(payload$known_synergies)

  n_value <- query_strategy_bridge_as_int(payload$n, default = 2L, min_value = 1L, max_value = 8L)
  depth_n_value <- query_strategy_bridge_as_int(payload$depth_n, default = 3L, min_value = 1L, max_value = 8L)
  top_k_value <- query_strategy_bridge_as_int(payload$top_k, default = 50L, min_value = 1L, max_value = 250L)
  top_n_value <- query_strategy_bridge_as_int(payload$top_n, default = 20L, min_value = 1L, max_value = 100L)
  max_missing_cards_value <- query_strategy_bridge_as_int(
    payload$max_missing_cards,
    default = 2L,
    min_value = 0L,
    max_value = 4L
  )
  gamma_value <- query_strategy_bridge_as_num(payload$gamma, default = 0.65, min_value = 0, max_value = 1)

  resolve_fun <- query_strategy_bridge_get_resolver()
  if (!is.function(resolve_fun)) {
    return(query_api_error("resolve_bridge_equation function unavailable"))
  }

  result <- tryCatch(
    resolve_fun(
      cards = cards,
      A_id = seed_a,
      B_id = seed_b,
      n = n_value,
      depth_N = depth_n_value,
      top_k = top_k_value,
      gamma = gamma_value,
      topN = top_n_value,
      known_synergies = known_synergies,
      max_missing_cards = max_missing_cards_value
    ),
    error = function(e) e
  )
  if (inherits(result, "error")) {
    return(query_api_error(conditionMessage(result)))
  }

  candidates_df <- result$candidates
  if (!is.data.frame(candidates_df)) {
    candidates_df <- data.frame(stringsAsFactors = FALSE)
  }

  bridge_payload <- result$bridge_payload
  if (is.null(bridge_payload) || !is.list(bridge_payload)) {
    bridge_payload <- list()
  }
  if (is.null(bridge_payload$bridges) || !is.data.frame(bridge_payload$bridges)) {
    bridge_payload$bridges <- data.frame(stringsAsFactors = FALSE)
  }
  if (is.null(bridge_payload$chains) || !is.list(bridge_payload$chains)) {
    bridge_payload$chains <- list()
  }
  if (is.null(bridge_payload$packages) || !is.list(bridge_payload$packages)) {
    bridge_payload$packages <- list()
  }

  list(
    ok = TRUE,
    seed_a = seed_a,
    seed_b = seed_b,
    count = nrow(candidates_df),
    candidates = query_db_rows_to_records(candidates_df),
    references = known_synergies,
    bridge_payload = list(
      bridges = query_db_rows_to_records(bridge_payload$bridges),
      chains = bridge_payload$chains,
      packages = bridge_payload$packages
    )
  )
}

query_strategy_bridge_get_resolver <- local({
  cached <- NULL

  function() {
    if (is.function(cached)) {
      return(cached)
    }

    if ("mtgcodex.api" %in% loadedNamespaces()) {
      ns <- asNamespace("mtgcodex.api")
      if (exists("resolve_bridge_equation", envir = ns, inherits = FALSE)) {
        cached <<- get("resolve_bridge_equation", envir = ns, inherits = FALSE)
        return(cached)
      }
    }

    if (exists("resolve_bridge_equation", mode = "function", inherits = TRUE)) {
      cached <<- get("resolve_bridge_equation", mode = "function", inherits = TRUE)
      return(cached)
    }

    bridge_candidates <- c(
      file.path(getwd(), "R", "bridge_synergy.R"),
      file.path(getwd(), "..", "R", "bridge_synergy.R")
    )
    bridge_exists <- vapply(bridge_candidates, file.exists, logical(1))
    if (any(bridge_exists)) {
      source(bridge_candidates[[which(bridge_exists)[1]]])
    }

    if (exists("resolve_bridge_equation", mode = "function", inherits = TRUE)) {
      cached <<- get("resolve_bridge_equation", mode = "function", inherits = TRUE)
      return(cached)
    }

    NULL
  }
})

query_strategy_bridge_normalize_card <- function(card) {
  if (!is.list(card)) {
    return(list(id = "", name = "", features = setNames(numeric(0), character(0)), constraints = list()))
  }

  id <- query_api_scalar(card$id, default = query_api_scalar(card$key, default = ""))
  name <- query_api_scalar(card$name, default = id)

  features <- query_strategy_bridge_normalize_features(card$features)

  constraints_in <- card$constraints
  if (!is.list(constraints_in)) {
    constraints_in <- list()
  }

  colors <- constraints_in$colors
  if (is.null(colors)) {
    colors <- card$colors
  }
  if (is.null(colors)) {
    colors <- character(0)
  }
  colors <- toupper(trimws(as.character(colors)))
  colors <- colors[nzchar(colors)]

  legal <- constraints_in$legal
  if (is.null(legal)) {
    legal <- TRUE
  }
  legal <- query_api_parse_bool(legal, default = TRUE)

  list(
    id = id,
    name = name,
    features = features,
    constraints = list(
      colors = colors,
      legal = legal,
      format = "commander"
    )
  )
}

query_strategy_bridge_normalize_features <- function(features) {
  if (is.null(features)) {
    return(setNames(numeric(0), character(0)))
  }

  if (is.list(features) && !is.null(names(features))) {
    values <- suppressWarnings(as.numeric(unlist(features, use.names = TRUE)))
    keys <- names(unlist(features, use.names = TRUE))
    keep <- !is.na(values) & nzchar(keys)
    values <- values[keep]
    keys <- keys[keep]
    if (length(values) == 0L) {
      return(setNames(numeric(0), character(0)))
    }
    grouped <- tapply(values, keys, sum)
    out <- as.numeric(grouped)
    names(out) <- names(grouped)
    return(out)
  }

  if (is.numeric(features) && !is.null(names(features))) {
    values <- suppressWarnings(as.numeric(features))
    keys <- names(features)
    keep <- !is.na(values) & nzchar(keys)
    values <- values[keep]
    keys <- keys[keep]
    if (length(values) == 0L) {
      return(setNames(numeric(0), character(0)))
    }
    grouped <- tapply(values, keys, sum)
    out <- as.numeric(grouped)
    names(out) <- names(grouped)
    return(out)
  }

  setNames(numeric(0), character(0))
}

query_strategy_bridge_normalize_known_synergies <- function(raw_synergies) {
  if (!is.list(raw_synergies) || length(raw_synergies) == 0L) {
    return(list())
  }

  out <- vector("list", length(raw_synergies))
  count <- 0L

  for (entry in raw_synergies) {
    if (!is.list(entry)) {
      next
    }
    cards <- entry$cards
    if (is.null(cards)) {
      next
    }
    cards <- as.character(cards)
    cards <- trimws(cards)
    cards <- cards[nzchar(cards)]
    cards <- unique(cards)
    if (length(cards) < 2L) {
      next
    }

    count <- count + 1L
    weight <- suppressWarnings(as.numeric(entry$weight))
    if (!is.finite(weight) || is.na(weight) || weight <= 0) {
      weight <- 1
    }
    out[[count]] <- list(
      source = query_api_scalar(entry$source, default = "reference"),
      label = query_api_scalar(entry$label, default = paste0("reference_", count)),
      cards = cards,
      weight = weight
    )
  }

  if (count == 0L) {
    return(list())
  }
  out[seq_len(count)]
}

query_strategy_bridge_as_int <- function(value, default = 0L, min_value = 0L, max_value = 100L) {
  parsed <- suppressWarnings(as.integer(value))
  if (!is.finite(parsed) || is.na(parsed)) {
    parsed <- as.integer(default)
  }
  parsed <- max(as.integer(min_value), parsed)
  parsed <- min(as.integer(max_value), parsed)
  as.integer(parsed)
}

query_strategy_bridge_as_num <- function(value, default = 0, min_value = 0, max_value = 1) {
  parsed <- suppressWarnings(as.numeric(value))
  if (!is.finite(parsed) || is.na(parsed)) {
    parsed <- as.numeric(default)
  }
  parsed <- max(as.numeric(min_value), parsed)
  parsed <- min(as.numeric(max_value), parsed)
  as.numeric(parsed)
}
