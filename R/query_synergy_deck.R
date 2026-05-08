# Deck-wide synergy recommender.
#
# Goal: take a full deck (60+ cards in Commander) and propose cards that would
# improve it, using the same role-aware mechanics-first engine as the single-
# seed `/synergy/find` endpoint, applied to the WHOLE deck instead of a single
# seed card.
#
# Strategy:
#   1. Resolve every deck card against the cached catalog.
#   2. Pick a small set of "anchor" cards that best represent the deck's
#      mechanical fingerprint (role-rich, event-rich profiles).
#   3. For each anchor, run the existing seed pipeline (`query_synergy_find_in_catalog`)
#      with groups disabled to keep cost bounded.
#   4. Aggregate per-candidate scores: keep best anchor + sum of top-3 anchor
#      contributions. Track which anchors lit up the candidate so the UI can
#      explain "why" beyond a single number.
#   5. Filter out cards already in the deck. Optionally restrict candidates
#      to a `pool` (e.g. the user's collection).
#   6. Return ranked candidates with the same `score_base + score_modifiers`
#      breakdown convention used elsewhere in the engine.

query_synergy_deck_recommend <- function(req = NULL) {
  payload <- query_synergy_parse_payload(req)
  if (!isTRUE(payload$ok)) {
    return(query_api_error(payload$error, recommendations = list()))
  }
  data <- payload$data

  deck_input <- query_synergy_to_vector(data$deck)
  deck_input <- trimws(deck_input[nzchar(deck_input)])
  if (length(deck_input) == 0L) {
    return(query_api_error("deck must contain at least one card name", recommendations = list()))
  }

  catalog_out <- query_synergy_get_catalog(force_refresh = isTRUE(data$force_refresh))
  if (!isTRUE(catalog_out$ok)) {
    return(query_api_error(catalog_out$error, recommendations = list()))
  }
  catalog <- catalog_out$cards

  format_name <- tolower(query_api_scalar(data$format, default = "commander"))
  max_results <- query_synergy_as_int(data$max_results, default = 30L, min_value = 1L, max_value = 100L)
  max_anchors <- query_synergy_as_int(data$max_anchors, default = 6L, min_value = 1L, max_value = 12L)
  per_anchor_max <- query_synergy_as_int(
    data$per_anchor_max,
    default = max(40L, max_results * 2L),
    min_value = 10L,
    max_value = 200L
  )
  archetype_filter <- character(0)
  if (!is.null(data$archetype_filter)) {
    archetype_filter <- unique(query_synergy_to_vector(data$archetype_filter))
    archetype_filter <- archetype_filter[nzchar(archetype_filter)]
  }
  archetype_filter_strict <- query_api_parse_bool(data$archetype_filter_strict, default = FALSE)
  color_filter <- query_synergy_parse_color_identity(data$color_identity)
  pool <- query_synergy_to_vector(data$pool)
  pool <- trimws(pool[nzchar(pool)])
  pool_keys <- if (length(pool) > 0L) tolower(pool) else character(0)

  # Resolve deck cards.
  resolved <- lapply(deck_input, function(name) {
    card <- query_synergy_find_card_by_id_or_name(catalog, name)
    list(input = name, card = card)
  })
  found <- Filter(function(x) !is.null(x$card), resolved)
  unresolved <- vapply(
    Filter(function(x) is.null(x$card), resolved),
    function(x) x$input,
    character(1)
  )
  if (length(found) == 0L) {
    return(query_api_error("no deck cards could be resolved against the catalog", recommendations = list()))
  }

  deck_cards <- lapply(found, function(x) x$card)
  deck_name_keys <- unique(tolower(vapply(
    deck_cards,
    function(c) query_api_scalar(c$name, default = ""),
    character(1)
  )))
  deck_id_keys <- unique(tolower(vapply(
    deck_cards,
    function(c) query_api_scalar(c$id, default = ""),
    character(1)
  )))

  # Pick anchors. Score each deck card by mechanical richness so we promote
  # cards that actually carry the strategy (multi-event payoffs, engines)
  # rather than vanilla utility / lands.
  registry <- query_synergy_event_registry_default()
  anchor_scores <- vapply(deck_cards, function(c) {
    norm <- tryCatch(
      query_synergy_normalize_card_cached(c, registry = registry),
      error = function(e) NULL
    )
    if (is.null(norm)) return(0)
    produced <- length(query_synergy_to_vector(norm$produced_events))
    consumed <- length(query_synergy_to_vector(norm$consumed_events))
    rewards  <- length(query_synergy_to_vector(norm$rewarded_events))
    roles    <- length(query_synergy_to_vector(norm$roles))
    tags     <- length(query_synergy_to_vector(norm$strategy_tags))
    type_line <- tolower(query_api_scalar(c$type_line, default = ""))
    type_penalty <- if (grepl("\\bbasic\\b.*\\bland\\b", type_line) || grepl("^basic land", type_line)) 100 else 0
    produced * 1.5 + consumed * 1.2 + rewards * 1.4 + roles * 1.0 + tags * 0.5 - type_penalty
  }, numeric(1))
  ord <- order(anchor_scores, decreasing = TRUE)
  anchor_take <- min(max_anchors, length(deck_cards))
  anchor_cards <- deck_cards[ord[seq_len(anchor_take)]]

  # Aggregator: per candidate-id, accumulate anchor contributions.
  agg <- new.env(parent = emptyenv(), hash = TRUE)
  anchor_meta <- vector("list", length(anchor_cards))

  for (i in seq_along(anchor_cards)) {
    anchor <- anchor_cards[[i]]
    anchor_payload <- list(
      card_name = query_api_scalar(anchor$id, default = query_api_scalar(anchor$name, default = "")),
      format = format_name,
      max_results = per_anchor_max,
      max_groups = 1L, # disable group exploration; we only want pair scores
      include_spellbook = FALSE,
      include_lotusnoir = FALSE,
      color_identity = color_filter,
      archetype_filter = archetype_filter,
      archetype_filter_strict = archetype_filter_strict
    )
    sub <- tryCatch(
      query_synergy_find_in_catalog(anchor_payload, catalog),
      error = function(e) list(ok = FALSE, error = conditionMessage(e))
    )
    anchor_meta[[i]] <- list(
      name = query_api_scalar(anchor$name, default = ""),
      id = query_api_scalar(anchor$id, default = ""),
      ok = isTRUE(sub$ok),
      candidate_count = if (isTRUE(sub$ok)) length(sub$best_matches) else 0L
    )
    if (!isTRUE(sub$ok)) next

    matches <- query_synergy_to_list(sub$best_matches)
    for (m in matches) {
      cid <- query_api_scalar(m$id, default = "")
      cname <- query_api_scalar(m$name, default = "")
      if (!nzchar(cid) && !nzchar(cname)) next
      key <- if (nzchar(cid)) cid else paste0("name::", tolower(cname))

      # Skip if candidate is itself a deck card.
      cname_key <- tolower(cname)
      cid_key <- tolower(cid)
      if (cname_key %in% deck_name_keys) next
      if (nzchar(cid_key) && cid_key %in% deck_id_keys) next

      # Pool restriction (collection scoping).
      if (length(pool_keys) > 0L && !(cname_key %in% pool_keys)) next

      contribution <- list(
        anchor_name = query_api_scalar(anchor$name, default = ""),
        anchor_id = query_api_scalar(anchor$id, default = ""),
        score = suppressWarnings(as.numeric(m$score)),
        bucket = query_api_scalar(m$bucket, default = ""),
        bucket_label = query_api_scalar(m$bucket_label, default = ""),
        explanation_text = query_api_scalar(m$explanation_text, default = ""),
        reasons = query_synergy_to_vector(m$reasons)
      )
      if (!is.finite(contribution$score)) contribution$score <- 0

      existing <- if (exists(key, envir = agg, inherits = FALSE)) {
        get(key, envir = agg, inherits = FALSE)
      } else {
        list(
          card = list(
            id = cid,
            name = cname,
            scryfall_id = query_api_scalar(m$scryfall_id, default = ""),
            set_code = query_api_scalar(m$set_code, default = ""),
            set_name = query_api_scalar(m$set_name, default = ""),
            mana_cost = query_api_scalar(m$mana_cost, default = ""),
            type_line = query_api_scalar(m$type_line, default = ""),
            oracle_text = query_api_scalar(m$oracle_text, default = ""),
            roles = query_synergy_to_vector(m$roles),
            strategy_tags = query_synergy_to_vector(m$strategy_tags)
          ),
          contributions = list()
        )
      }
      existing$contributions[[length(existing$contributions) + 1L]] <- contribution
      assign(key, existing, envir = agg)
    }
  }

  # Score aggregation.
  candidate_keys <- ls(agg, all.names = TRUE)
  recommendations <- lapply(candidate_keys, function(key) {
    entry <- get(key, envir = agg, inherits = FALSE)
    contribs <- entry$contributions
    scores <- vapply(contribs, function(c) suppressWarnings(as.numeric(c$score)), numeric(1))
    scores[is.na(scores) | !is.finite(scores)] <- 0
    sorted_idx <- order(scores, decreasing = TRUE)
    contribs <- contribs[sorted_idx]
    scores <- scores[sorted_idx]

    # Weighted aggregation: best anchor counts fully, second/third add diminishing
    # bonuses. Ensures one perfect engine match isn't drowned by 5 weak hits.
    weights <- c(1.0, 0.5, 0.25)
    take <- min(length(scores), length(weights))
    weighted_sum <- if (take > 0L) sum(scores[seq_len(take)] * weights[seq_len(take)]) else 0
    base_score <- as.integer(round(min(100, weighted_sum)))

    # Anchor coverage bonus: candidates that resonate with multiple deck cards
    # are more reliable picks than single-anchor matches. Cap at +10.
    coverage <- min(length(contribs), 6L)
    coverage_bonus <- as.integer(round(min(10L, max(0L, coverage - 1L) * 2L)))

    total <- min(100L, base_score + coverage_bonus)

    score_modifiers <- list()
    if (coverage_bonus > 0L) {
      score_modifiers$anchor_coverage <- list(
        amount = coverage_bonus,
        anchors_matched = length(contribs)
      )
    }

    top_anchors <- lapply(contribs[seq_len(min(3L, length(contribs)))], function(c) {
      list(
        anchor_name = c$anchor_name,
        anchor_id = c$anchor_id,
        pair_score = round(c$score, 1),
        bucket = c$bucket,
        bucket_label = c$bucket_label,
        explanation_text = c$explanation_text
      )
    })

    list(
      id = entry$card$id,
      name = entry$card$name,
      scryfall_id = entry$card$scryfall_id,
      set_code = entry$card$set_code,
      set_name = entry$card$set_name,
      mana_cost = entry$card$mana_cost,
      type_line = entry$card$type_line,
      oracle_text = entry$card$oracle_text,
      roles = entry$card$roles,
      strategy_tags = entry$card$strategy_tags,
      score = total,
      total_score = total,
      score_base = base_score,
      score_modifiers = score_modifiers,
      anchor_coverage = length(contribs),
      best_pair_score = round(scores[[1]], 1),
      top_anchors = top_anchors,
      explanation_text = if (length(top_anchors) > 0L) {
        paste0(
          "Pair with ", top_anchors[[1]]$anchor_name,
          " (", round(scores[[1]]), "/100)"
        )
      } else ""
    )
  })

  ord_final <- order(
    vapply(recommendations, function(r) suppressWarnings(as.numeric(r$total_score)), numeric(1)),
    decreasing = TRUE
  )
  recommendations <- recommendations[ord_final]
  if (length(recommendations) > max_results) {
    recommendations <- recommendations[seq_len(max_results)]
  }

  list(
    ok = TRUE,
    format = format_name,
    deck_size = length(deck_cards),
    deck_resolved = length(found),
    deck_unresolved = unresolved,
    anchors = anchor_meta,
    recommendations = recommendations,
    count = length(recommendations),
    pool_size = length(pool_keys),
    archetype_filter = archetype_filter,
    archetype_filter_strict = archetype_filter_strict,
    color_identity = color_filter
  )
}
