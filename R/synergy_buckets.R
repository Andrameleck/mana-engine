# Result bucket assembly: labels, card result entries, diversification, bucket builders.
# Extracted from R/query_synergy_engine.R as part of the modular refactor.
# Depends on: synergy_utils, synergy_score_pair

query_synergy_bucket_labels <- function() {
  list(
    direct_enablers = "Top direct enablers",
    indirect_engines = "Top indirect engines",
    reciprocal_value_cards = "Top reciprocal value cards",
    synergy_groups = "Top synergy groups",
    package_lines = "Top package lines",
    packages = "Top packages / groups",
    anti_synergy_warnings = "Top anti-synergy warnings"
  )
}

query_synergy_build_card_result_entry <- function(candidate, score, bucket_key = "") {
  labels <- query_synergy_bucket_labels()
  key <- query_api_scalar(bucket_key, default = query_api_scalar(score$primary_bucket, default = "direct_enablers"))
  bucket_score <- suppressWarnings(as.numeric(score$bucket_scores[[key]]))
  if (!is.finite(bucket_score) || is.na(bucket_score)) {
    bucket_score <- suppressWarnings(as.numeric(score$score_norm))
  }

  list(
    id = candidate$id,
    name = candidate$name,
    scryfall_id = query_api_scalar(candidate$scryfall_id, default = ""),
    set_code = query_api_scalar(candidate$set_code, default = ""),
    set_name = query_api_scalar(candidate$set_name, default = ""),
    mana_cost = query_api_scalar(candidate$mana_cost, default = ""),
    oracle_text = query_api_scalar(candidate$oracle_text, default = ""),
    type_line = query_api_scalar(candidate$type_line, default = ""),
    score = score$score,
    total_score = score$score,
    score_norm = score$score_norm,
    score_breakdown = score$breakdown,
    axis_scores = score$axis_scores,
    bucket_scores = score$bucket_scores,
    bucket = key,
    bucket_label = query_api_scalar(labels[[key]], default = key),
    bucket_score = round(bucket_score, 4),
    roles = query_synergy_to_vector(candidate$roles),
    cadence = candidate$cadence,
    target_roles = query_synergy_to_vector(candidate$target_roles),
    matched_events = score$matched_events,
    reasons = score$reasons,
    explanation_text = query_api_scalar(score$explanation_text, default = paste(utils::head(score$reasons, 3L), collapse = " ")),
    relation_classes = score$relation_classes,
    strategy_tags = query_synergy_to_vector(candidate$strategy_tags)
  )
}

query_synergy_result_profile_fingerprint <- function(entry) {
  role_sig <- paste(sort(intersect(query_synergy_to_vector(entry$roles), c("producer", "payoff", "engine", "setup", "converter", "amplifier", "target", "bridge", "finisher"))), collapse = "+")
  event_sig <- paste(sort(unique(c(
    query_synergy_to_vector(entry$matched_events$enabler_to_payoff),
    query_synergy_to_vector(entry$matched_events$indirect_engine),
    query_synergy_to_vector(entry$matched_events$role_pairs)
  ))), collapse = "+")
  cadence_sig <- query_api_scalar(entry$cadence$class, default = "one_shot")
  paste(query_api_scalar(entry$bucket, default = ""), role_sig, event_sig, cadence_sig, sep = "|")
}

query_synergy_diversify_entries <- function(entries, limit = 10L) {
  pool <- query_synergy_to_list(entries)
  if (length(pool) == 0L) {
    return(list())
  }

  get_profile_count <- function(fingerprint) {
    value <- profile_counts[[fingerprint]]
    if (is.null(value) || length(value) == 0L) {
      return(0L)
    }
    count <- suppressWarnings(as.integer(value))
    if (length(count) == 0L || !is.finite(count[[1]]) || is.na(count[[1]])) {
      return(0L)
    }
    count[[1]]
  }

  selected <- list()
  profile_counts <- list()
  cap <- query_synergy_as_int(limit, default = 10L, min_value = 1L, max_value = 100L)

  while (length(pool) > 0L && length(selected) < cap) {
    adjusted_scores <- vapply(pool, function(entry) {
      fingerprint <- query_synergy_result_profile_fingerprint(entry)
      seen_count <- get_profile_count(fingerprint)
      base <- suppressWarnings(as.numeric(entry$bucket_score))
      if (!is.finite(base) || is.na(base)) {
        base <- suppressWarnings(as.numeric(entry$total_score)) / 100
      }
      base - (seen_count * 0.08)
    }, numeric(1))

    ord <- order(adjusted_scores, decreasing = TRUE)
    chosen_index <- ord[[1]]
    chosen <- pool[[chosen_index]]
    selected[[length(selected) + 1L]] <- chosen

    fingerprint <- query_synergy_result_profile_fingerprint(chosen)
    current <- get_profile_count(fingerprint)
    profile_counts[[fingerprint]] <- current + 1L
    pool[[chosen_index]] <- NULL
  }

  selected
}

query_synergy_build_bucket <- function(entries, bucket_key, limit = 10L) {
  labels <- query_synergy_bucket_labels()
  pool <- query_synergy_to_list(entries)
  if (length(pool) == 0L) {
    return(list(
      key = bucket_key,
      label = query_api_scalar(labels[[bucket_key]], default = bucket_key),
      count = 0L,
      results = list()
    ))
  }

  ord <- order(
    vapply(pool, function(entry) suppressWarnings(as.numeric(entry$bucket_score)), numeric(1)),
    vapply(pool, function(entry) suppressWarnings(as.numeric(entry$total_score)), numeric(1)),
    decreasing = TRUE
  )
  pool <- pool[ord]
  selected <- query_synergy_diversify_entries(pool, limit = limit)

  list(
    key = bucket_key,
    label = query_api_scalar(labels[[bucket_key]], default = bucket_key),
    count = length(selected),
    results = selected
  )
}

query_synergy_build_result_buckets <- function(target, scored_entries, max_results = 50L) {
  entries <- query_synergy_to_list(scored_entries)
  direct_pool <- list()
  indirect_pool <- list()
  reciprocal_pool <- list()
  anti_pool <- list()
  flat_pool <- list()

  for (entry in entries) {
    if (!is.list(entry$card) || !is.list(entry$score)) {
      next
    }

    candidate <- entry$card
    score <- entry$score
    direct_axis <- suppressWarnings(as.numeric(score$axis_scores$direct_event_score))
    payoff_axis <- suppressWarnings(as.numeric(score$axis_scores$payoff_bridge_score))
    resource_axis <- suppressWarnings(as.numeric(score$axis_scores$resource_bridge_score))
    zone_axis <- suppressWarnings(as.numeric(score$axis_scores$zone_transition_bridge_score))
    setup_converter_axis <- suppressWarnings(as.numeric(score$axis_scores$setup_converter_score))
    strong_bridge_axis <- suppressWarnings(as.numeric(score$axis_scores$strong_bridge_score))
    weak_bridge_axis <- suppressWarnings(as.numeric(score$axis_scores$weak_bridge_penalty))
    if (length(direct_axis) == 0L || !is.finite(direct_axis[[1]]) || is.na(direct_axis[[1]])) {
      direct_axis <- 0
    } else {
      direct_axis <- direct_axis[[1]]
    }
    if (length(payoff_axis) == 0L || !is.finite(payoff_axis[[1]]) || is.na(payoff_axis[[1]])) {
      payoff_axis <- 0
    } else {
      payoff_axis <- payoff_axis[[1]]
    }
    if (length(resource_axis) == 0L || !is.finite(resource_axis[[1]]) || is.na(resource_axis[[1]])) {
      resource_axis <- 0
    } else {
      resource_axis <- resource_axis[[1]]
    }
    if (length(zone_axis) == 0L || !is.finite(zone_axis[[1]]) || is.na(zone_axis[[1]])) {
      zone_axis <- 0
    } else {
      zone_axis <- zone_axis[[1]]
    }
    if (length(setup_converter_axis) == 0L || !is.finite(setup_converter_axis[[1]]) || is.na(setup_converter_axis[[1]])) {
      setup_converter_axis <- 0
    } else {
      setup_converter_axis <- setup_converter_axis[[1]]
    }
    if (length(strong_bridge_axis) == 0L || !is.finite(strong_bridge_axis[[1]]) || is.na(strong_bridge_axis[[1]])) {
      strong_bridge_axis <- 0
    } else {
      strong_bridge_axis <- strong_bridge_axis[[1]]
    }
    if (length(weak_bridge_axis) == 0L || !is.finite(weak_bridge_axis[[1]]) || is.na(weak_bridge_axis[[1]])) {
      weak_bridge_axis <- 0
    } else {
      weak_bridge_axis <- weak_bridge_axis[[1]]
    }
    has_strong_bridge <- strong_bridge_axis >= 0.16 ||
      direct_axis >= 0.1 ||
      payoff_axis >= 0.1 ||
      resource_axis >= 0.2 ||
      zone_axis >= 0.2 ||
      setup_converter_axis >= 0.22
    direct_bridge_gate <- zone_axis >= 0.3 ||
      direct_axis >= 0.05 ||
      payoff_axis >= 0.05

    primary_entry <- query_synergy_build_card_result_entry(candidate, score, score$primary_bucket)
    if (primary_entry$bucket != "anti_synergy_warnings" && suppressWarnings(as.numeric(primary_entry$total_score)) > 0) {
      flat_pool[[length(flat_pool) + 1L]] <- primary_entry
    }

    if (suppressWarnings(as.numeric(score$bucket_scores$direct_enablers)) >= 0.16 &&
        direct_bridge_gate &&
        has_strong_bridge &&
        weak_bridge_axis < 0.34) {
      direct_pool[[length(direct_pool) + 1L]] <- query_synergy_build_card_result_entry(candidate, score, "direct_enablers")
    }
    if (suppressWarnings(as.numeric(score$bucket_scores$indirect_engines)) >= 0.18 &&
      suppressWarnings(as.numeric(score$axis_scores$indirect_engine_score)) > 0.12 &&
      suppressWarnings(as.numeric(score$axis_scores$reliability_score)) >= 0.24) {
      indirect_pool[[length(indirect_pool) + 1L]] <- query_synergy_build_card_result_entry(candidate, score, "indirect_engines")
    }
    if (suppressWarnings(as.numeric(score$bucket_scores$reciprocal_value_cards)) >= 0.16 && suppressWarnings(as.numeric(score$axis_scores$reciprocal_value_score)) > 0.08) {
      reciprocal_pool[[length(reciprocal_pool) + 1L]] <- query_synergy_build_card_result_entry(candidate, score, "reciprocal_value_cards")
    }
    if (score$primary_bucket == "anti_synergy_warnings" ||
        length(query_synergy_to_vector(score$matched_events$replaces_payoff)) > 0L ||
        length(query_synergy_to_vector(score$matched_events$prevents_payoff)) > 0L ||
        suppressWarnings(as.numeric(score$bucket_scores$anti_synergy_warnings)) >= 0.25) {
      anti_pool[[length(anti_pool) + 1L]] <- query_synergy_build_card_result_entry(candidate, score, "anti_synergy_warnings")
    }
  }

  flat_selected <- query_synergy_diversify_entries(flat_pool, limit = max_results)
  dedup_flat <- list()
  seen <- new.env(parent = emptyenv(), hash = TRUE)
  for (entry in flat_selected) {
    key <- query_api_scalar(entry$id, default = "")
    if (!nzchar(key) || exists(key, envir = seen, inherits = FALSE)) {
      next
    }
    assign(key, TRUE, envir = seen)
    dedup_flat[[length(dedup_flat) + 1L]] <- entry
  }

  list(
    buckets = list(
      direct_enablers = query_synergy_build_bucket(direct_pool, "direct_enablers", limit = min(10L, max_results)),
      indirect_engines = query_synergy_build_bucket(indirect_pool, "indirect_engines", limit = min(10L, max_results)),
      reciprocal_value_cards = query_synergy_build_bucket(reciprocal_pool, "reciprocal_value_cards", limit = min(10L, max_results)),
      anti_synergy_warnings = query_synergy_build_bucket(anti_pool, "anti_synergy_warnings", limit = min(10L, max_results))
    ),
    flat = dedup_flat
  )
}
