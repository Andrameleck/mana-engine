# Synergy group graph: edge construction, path search, group assembly.
# Extracted from R/query_synergy_engine.R as part of the modular refactor.
# Depends on: synergy_utils, synergy_event_registry, synergy_normalize

query_synergy_group_edge_key <- function(from_id, to_id) {
  sprintf(
    "%s=>%s",
    query_api_scalar(from_id, default = ""),
    query_api_scalar(to_id, default = "")
  )
}

query_synergy_group_card_summary <- function(card) {
  list(
    id = query_api_scalar(card$id, default = ""),
    name = query_api_scalar(card$name, default = ""),
    scryfall_id = query_api_scalar(card$scryfall_id, default = ""),
    set_code = query_api_scalar(card$set_code, default = ""),
    set_name = query_api_scalar(card$set_name, default = ""),
    mana_cost = query_api_scalar(card$mana_cost, default = ""),
    oracle_text = query_api_scalar(card$oracle_text, default = ""),
    type_line = query_api_scalar(card$type_line, default = "")
  )
}

query_synergy_unique_cards_by_id <- function(cards) {
  items <- query_synergy_to_list(cards)
  if (length(items) == 0L) return(list())
  keys <- vapply(items, function(c) {
    query_api_scalar(c$id, default = query_api_scalar(c$name, default = ""))
  }, character(1))
  items[nzchar(keys) & !duplicated(keys)]
}

query_synergy_resources_compatible <- function(left, right) {
  left_value <- query_api_scalar(left, default = "")
  right_value <- query_api_scalar(right, default = "")
  if (!nzchar(left_value) || !nzchar(right_value) || identical(left_value, right_value)) {
    return(TRUE)
  }

  pair_key <- paste(sort(c(left_value, right_value)), collapse = "|")
  pair_key %in% c(
    "card|permanent",
    "card|spell",
    "creature|permanent",
    "creature|token",
    "permanent|token"
  )
}

query_synergy_group_transition_key <- function(transition) {
  paste(
    query_api_scalar(transition$kind, default = ""),
    query_api_scalar(transition$via, default = ""),
    query_api_scalar(transition$resource, default = ""),
    query_api_scalar(transition$from, default = ""),
    query_api_scalar(transition$to, default = ""),
    query_api_scalar(transition$source_event, default = query_api_scalar(transition$event, default = "")),
    query_api_scalar(transition$target_event, default = query_api_scalar(transition$event, default = "")),
    sep = "|"
  )
}

query_synergy_collect_resource_transitions <- function(source,
                                                       target,
                                                       registry = query_synergy_event_registry_default()) {
  source_card <- if (is.list(source)) source else list()
  target_card <- if (is.list(target)) target else list()
  source_moves <- query_synergy_to_list(source_card$moves)
  if (length(source_moves) == 0L) {
    source_moves <- query_synergy_build_move_records(source_card$produced_events, registry)
  }
  target_requirement_moves <- query_synergy_build_move_records(target_card$consumed_events, registry)
  target_moves <- query_synergy_to_list(target_card$moves)
  if (length(target_moves) == 0L) {
    target_moves <- query_synergy_build_move_records(
      unique(c(target_card$consumed_events, target_card$produced_events)),
      registry
    )
  }

  out <- list()
  shared_events <- intersect(
    query_synergy_to_vector(source_card$produced_events),
    query_synergy_to_vector(target_card$consumed_events)
  )
  for (event_id in shared_events) {
    event_def <- registry$events[[event_id]]
    zones <- if (is.list(event_def$zones)) event_def$zones else list()
    out[[length(out) + 1L]] <- list(
      kind = "event_bridge",
      via = event_id,
      event = event_id,
      resource = query_api_scalar(event_def$resource, default = ""),
      from = query_api_scalar(zones$from, default = ""),
      to = query_api_scalar(zones$to, default = "")
    )
  }

  for (source_move in source_moves) {
    source_to <- query_api_scalar(source_move$to, default = "")
    if (!nzchar(source_to)) {
      next
    }

    for (target_move in target_requirement_moves) {
      target_from <- query_api_scalar(target_move$from, default = "")
      if (!nzchar(target_from) || !identical(source_to, target_from)) {
        next
      }
      if (!query_synergy_resources_compatible(source_move$resource, target_move$resource)) {
        next
      }

      out[[length(out) + 1L]] <- list(
        kind = "zone_chain",
        via = source_to,
        resource = query_api_scalar(target_move$resource, default = query_api_scalar(source_move$resource, default = "")),
        from = query_api_scalar(source_move$from, default = ""),
        to = query_api_scalar(target_move$to, default = ""),
        source_event = query_api_scalar(source_move$event, default = ""),
        target_event = query_api_scalar(target_move$event, default = "")
      )
    }
  }

  for (source_move in source_moves) {
    source_to <- query_api_scalar(source_move$to, default = "")
    if (!nzchar(source_to)) {
      next
    }

    for (target_move in target_moves) {
      target_from <- query_api_scalar(target_move$from, default = "")
      target_to <- query_api_scalar(target_move$to, default = "")
      if (!nzchar(target_from) || !identical(source_to, target_from)) {
        next
      }
      if (!nzchar(target_to) || identical(target_from, target_to)) {
        next
      }
      if (!query_synergy_resources_compatible(source_move$resource, target_move$resource)) {
        next
      }

      out[[length(out) + 1L]] <- list(
        kind = "zone_transition_bridge",
        via = source_to,
        resource = query_api_scalar(target_move$resource, default = query_api_scalar(source_move$resource, default = "")),
        from = query_api_scalar(source_move$from, default = ""),
        to = target_to,
        source_event = query_api_scalar(source_move$event, default = ""),
        target_event = query_api_scalar(target_move$event, default = "")
      )
    }
  }

  if (length(out) == 0L) {
    return(list())
  }

  keys <- vapply(out, query_synergy_group_transition_key, character(1))
  out[nzchar(keys) & !duplicated(keys)]
}

query_synergy_build_group_edge <- function(source,
                                           target,
                                           format_name = "commander",
                                           min_edge_score = 28L,
                                           registry = query_synergy_event_registry_default()) {
  pair <- query_synergy_score_pair(target, source, format_name)
  source_moves <- query_synergy_to_list(source$moves)
  if (length(source_moves) == 0L) {
    source_moves <- query_synergy_build_move_records(source$produced_events, registry)
  }
  transitions <- query_synergy_collect_resource_transitions(source, target, registry = registry)
  bridge_links <- query_synergy_indirect_resource_bridges(source, target)
  terminal_bridge_links <- unique(vapply(Filter(function(move) {
    identical(query_api_scalar(move$to, default = ""), "battlefield")
  }, source_moves), function(move) {
    query_api_scalar(move$event, default = "")
  }, character(1)))
  if (!any(query_synergy_to_vector(target$roles) %in% c("target", "finisher", "payoff"))) {
    terminal_bridge_links <- character(0)
  }
  direct_events <- query_synergy_to_vector(pair$matched_events$enabler_to_payoff)
  indirect_events <- query_synergy_to_vector(pair$matched_events$indirect_engine)
  setup_finisher_events <- query_synergy_to_vector(pair$matched_events$setup_finisher)
  package_links <- query_synergy_to_vector(pair$matched_events$package_links)
  causal_events <- unique(c(
    direct_events,
    indirect_events,
    setup_finisher_events,
    bridge_links,
    terminal_bridge_links
  ))
  matched_events <- unique(c(causal_events, package_links))
  role_pairs <- query_synergy_to_vector(pair$matched_events$role_pairs)
  edge_reliability <- suppressWarnings(as.numeric(pair$axis_scores$reliability_score))
  edge_shell <- suppressWarnings(as.numeric(pair$axis_scores$shell_dependency_score))
  if (!is.finite(edge_reliability) || is.na(edge_reliability)) {
    edge_reliability <- 0
  }
  if (!is.finite(edge_shell) || is.na(edge_shell)) {
    edge_shell <- 0
  }
  continuity_score <- max(0, min(1,
    0.38 * suppressWarnings(as.numeric(pair$score_norm)) +
      0.2 * min(1, length(causal_events) / 3) +
      0.2 * min(1, length(transitions) / 2) +
    0.1 * min(1, length(role_pairs) / 2) +
    0.08 * edge_reliability -
    0.08 * edge_shell +
    0.025 * min(1, length(bridge_links) / 2) +
    0.025 * min(1, length(terminal_bridge_links) / 2)
  ))
  if (!is.finite(continuity_score) || is.na(continuity_score)) {
    continuity_score <- 0
  }
  structural_pair <- max(
    suppressWarnings(as.numeric(pair$axis_scores$direct_event_score)),
    suppressWarnings(as.numeric(pair$axis_scores$indirect_engine_score)),
    suppressWarnings(as.numeric(pair$axis_scores$package_score)),
    edge_reliability
  )
  if (!is.finite(structural_pair) || is.na(structural_pair)) {
    structural_pair <- 0
  }
  value_only_link <- length(package_links) > 0L && length(causal_events) == 0L && length(transitions) == 0L

  hard_conflict <- length(unique(c(
    query_synergy_to_vector(pair$matched_events$replaces_payoff),
    query_synergy_to_vector(pair$matched_events$prevents_payoff)
  ))) > 0L
  valid <- !hard_conflict && !value_only_link && (
    (suppressWarnings(as.integer(pair$score)) >= query_synergy_as_int(min_edge_score, default = 28L, min_value = 1L, max_value = 100L) && structural_pair >= 0.12) ||
      continuity_score >= 0.34 ||
        length(causal_events) > 0L ||
        length(bridge_links) > 0L ||
        (length(terminal_bridge_links) > 0L && suppressWarnings(as.numeric(pair$axis_scores$role_complementarity_score)) >= 0.1) ||
      (length(transitions) > 0L && suppressWarnings(as.numeric(pair$axis_scores$role_complementarity_score)) >= 0.1) ||
      (length(matched_events) > 0L && structural_pair >= 0.16)
  )

  list(
    id = query_synergy_group_edge_key(source$id, target$id),
    from = query_synergy_group_card_summary(source),
    to = query_synergy_group_card_summary(target),
    score = suppressWarnings(as.integer(pair$score)),
    score_norm = suppressWarnings(as.numeric(pair$score_norm)),
    continuity_score = round(continuity_score, 4),
    axis_scores = pair$axis_scores,
    bucket_scores = pair$bucket_scores,
    primary_bucket = pair$primary_bucket,
    matched_events = list(
      direct = direct_events,
      indirect = indirect_events,
      setup_finisher = setup_finisher_events,
      package_links = package_links,
      resource_bridges = bridge_links,
      terminal_bridges = terminal_bridge_links,
      role_pairs = role_pairs
    ),
    matched_resource_transitions = transitions,
    anti_conflicts = unique(c(
      query_synergy_to_vector(pair$matched_events$replaces_payoff),
      query_synergy_to_vector(pair$matched_events$prevents_payoff),
      query_synergy_to_vector(pair$matched_events$anti_conflicts)
    )),
    anti_synergy_score = suppressWarnings(as.numeric(pair$axis_scores$anti_synergy_score)),
    relation_classes = query_synergy_to_vector(pair$relation_classes),
    reasons = unique(utils::head(query_synergy_to_vector(pair$reasons), 3L)),
    directional = pair$directional,
    valid = isTRUE(valid)
  )
}

query_synergy_build_group_graph <- function(seed,
                                            candidates,
                                            format_name = "commander",
                                            min_edge_score = 28L,
                                            progress_callback = NULL,
                                            progress_range = c(88, 97),
                                            registry = query_synergy_event_registry_default()) {
  cards <- query_synergy_unique_cards_by_id(c(list(seed), query_synergy_to_list(candidates)))
  if (length(cards) < 3L) {
    return(list(
      seed_id = query_api_scalar(seed$id, default = ""),
      nodes = list(),
      adjacency = list(),
      edge_lookup = list(),
      node_count = length(cards),
      edge_count = 0L,
      pair_count = 0L
    ))
  }

  progress_start <- suppressWarnings(as.numeric(progress_range[[1]]))
  progress_end <- suppressWarnings(as.numeric(progress_range[[2]]))
  if (!is.finite(progress_start) || is.na(progress_start)) {
    progress_start <- 88
  }
  if (!is.finite(progress_end) || is.na(progress_end)) {
    progress_end <- 97
  }

  total_pairs <- length(cards) * max(0L, length(cards) - 1L)
  stride <- max(1L, ceiling(max(1L, total_pairs) / 25L))
  pair_index <- 0L
  edge_count <- 0L
  node_lookup <- list()
  adjacency <- list()
  edge_lookup <- list()

  for (card in cards) {
    node_lookup[[query_api_scalar(card$id, default = query_api_scalar(card$name, default = ""))]] <- card
  }

  for (i in seq_along(cards)) {
    source <- cards[[i]]
    source_id <- query_api_scalar(source$id, default = "")
    if (!nzchar(source_id)) {
      next
    }

    for (j in seq_along(cards)) {
      if (i == j) {
        next
      }

      pair_index <- pair_index + 1L
      if (is.function(progress_callback) && (pair_index == 1L || pair_index == total_pairs || (pair_index %% stride) == 0L)) {
        percent <- progress_start + ((pair_index / max(1L, total_pairs)) * (progress_end - progress_start))
        query_synergy_emit_progress(progress_callback, percent, "Detecting package lines", list(processed = pair_index, total = total_pairs))
      }

      edge <- query_synergy_build_group_edge(
        source = source,
        target = cards[[j]],
        format_name = format_name,
        min_edge_score = min_edge_score,
        registry = registry
      )
      edge_lookup[[query_api_scalar(edge$id, default = "")]] <- edge
      if (!isTRUE(edge$valid)) {
        next
      }

      adjacency[[source_id]] <- c(adjacency[[source_id]], list(edge))
      edge_count <- edge_count + 1L
    }
  }

  for (node_id in names(adjacency)) {
    edges <- query_synergy_to_list(adjacency[[node_id]])
    if (length(edges) == 0L) {
      next
    }
    ord <- order(vapply(edges, function(edge) {
      continuity <- suppressWarnings(as.numeric(edge$continuity_score))
      score_norm <- suppressWarnings(as.numeric(edge$score_norm))
      if (!is.finite(continuity) || is.na(continuity)) {
        continuity <- 0
      }
      if (!is.finite(score_norm) || is.na(score_norm)) {
        score_norm <- 0
      }
      (0.6 * continuity) + (0.4 * score_norm)
    }, numeric(1)), decreasing = TRUE)
    adjacency[[node_id]] <- edges[ord]
  }

  list(
    seed_id = query_api_scalar(seed$id, default = ""),
    nodes = node_lookup,
    adjacency = adjacency,
    edge_lookup = edge_lookup,
    node_count = length(cards),
    edge_count = edge_count,
    pair_count = total_pairs
  )
}

query_synergy_search_local_group_paths <- function(seed_id,
                                                   graph,
                                                   max_group_size = 4L,
                                                   max_paths = 120L,
                                                   max_outgoing_per_node = 6L) {
  node_ids <- names(graph$nodes)
  if (!nzchar(query_api_scalar(seed_id, default = "")) || length(node_ids) < 3L) {
    return(list(paths = list(), path_count = 0L))
  }

  cap <- query_synergy_as_int(max_group_size, default = 4L, min_value = 3L, max_value = 5L)
  path_budget <- query_synergy_as_int(max_paths, default = 120L, min_value = 10L, max_value = 500L)
  branch_cap <- query_synergy_as_int(max_outgoing_per_node, default = 6L, min_value = 1L, max_value = 25L)
  seen <- new.env(parent = emptyenv(), hash = TRUE)
  out <- list()
  path_count <- 0L

  explore <- function(current_id, path_ids) {
    if (path_count >= path_budget) {
      return(invisible(NULL))
    }
    if (length(path_ids) >= cap) {
      return(invisible(NULL))
    }

    edges <- graph$adjacency[[current_id]]
    if (!is.list(edges) || length(edges) == 0L) {
      return(invisible(NULL))
    }
    if (length(edges) > branch_cap) {
      edges <- edges[seq_len(branch_cap)]
    }

    for (edge in edges) {
      if (path_count >= path_budget) {
        break
      }

      next_id <- query_api_scalar(edge$to$id, default = "")
      if (!nzchar(next_id) || next_id %in% path_ids) {
        next
      }

      next_path <- c(path_ids, next_id)
      path_count <<- path_count + 1L
      if (length(next_path) >= 3L && seed_id %in% next_path) {
        key <- paste(next_path, collapse = ">")
        if (!exists(key, envir = seen, inherits = FALSE)) {
          assign(key, TRUE, envir = seen)
          out[[length(out) + 1L]] <<- next_path
        }
      }

      if (length(next_path) < cap) {
        if (!(seed_id %in% next_path) && length(next_path) >= (cap - 1L)) {
          next
        }
        explore(next_id, next_path)
      }
    }

    invisible(NULL)
  }

  for (start_id in node_ids) {
    if (path_count >= path_budget) {
      break
    }
    explore(start_id, c(start_id))
  }

  list(paths = out, path_count = path_count)
}

query_synergy_infer_group_member_role <- function(card,
                                                  position_index,
                                                  member_count,
                                                  incoming_edge = NULL,
                                                  outgoing_edge = NULL) {
  roles <- query_synergy_to_vector(card$roles)
  cadence_class <- query_api_scalar(card$cadence$class, default = "one_shot")
  reliable_engine <- "engine" %in% roles && cadence_class %in% c("reliable_repeatable", "scalable_repeatable", "repeatable", "repeatable_scalable")
  if (position_index >= member_count) {
    terminal_roles <- c("finisher", "payoff", "target", "engine", "bridge")
    matched <- terminal_roles[terminal_roles %in% roles]
    if (length(matched) > 0L) {
      return(matched[[1]])
    }
    return("target")
  }

  if (position_index <= 1L) {
    if (reliable_engine) {
      return("engine")
    }
    if ("setup" %in% roles && !("amplifier" %in% roles)) {
      return("setup")
    }
    opening_roles <- c("converter", "bridge", "amplifier")
    matched_open <- opening_roles[opening_roles %in% roles]
    if (length(matched_open) > 0L) {
      return(matched_open[[1]])
    }
    if ("engine" %in% roles) {
      return("engine")
    }
    if ("producer" %in% roles && !any(roles %in% c("payoff", "finisher", "target"))) {
      return("fuel")
    }
    return("fuel")
  }

  if ("amplifier" %in% roles) {
    return("amplifier")
  }
  if (reliable_engine) {
    return("engine")
  }
  if ("converter" %in% roles) {
    return("converter")
  }
  if ("bridge" %in% roles) {
    return("bridge")
  }
  if ("engine" %in% roles) {
    return("engine")
  }
  if ("producer" %in% roles && length(query_synergy_to_list(outgoing_edge$matched_resource_transitions)) > 0L) {
    return("fuel")
  }
  if ("setup" %in% roles) {
    return("setup")
  }
  if ("payoff" %in% roles) {
    return("payoff")
  }
  if ("target" %in% roles) {
    return("target")
  }
  "bridge"
}

query_synergy_group_role_coverage_score <- function(member_roles) {
  roles <- query_synergy_to_vector(member_roles)
  if (length(roles) == 0L) {
    return(0)
  }

  start_ok <- roles[[1]] %in% c("setup", "fuel", "engine", "bridge", "converter")
  end_ok <- roles[[length(roles)]] %in% c("payoff", "finisher", "target")
  middle_roles <- if (length(roles) > 2L) roles[2:(length(roles) - 1L)] else character(0)
  middle_ok <- if (length(middle_roles) == 0L) {
    1
  } else {
    sum(middle_roles %in% c("engine", "converter", "bridge", "amplifier", "fuel")) / length(middle_roles)
  }
  diversity <- min(1, length(unique(roles)) / min(length(roles), 4L))

  round(min(1,
    0.3 * as.numeric(start_ok) +
      0.3 * as.numeric(end_ok) +
      0.25 * middle_ok +
      0.15 * diversity
  ), 4)
}

query_synergy_group_category <- function(member_roles,
                                         member_count,
                                         anti_synergy_penalty = 0,
                                         resource_transitions = list(),
                                         chain_continuity = 0,
                                         resource_flow_quality = 0,
                                         strategic_coherence = 0,
                                         causal_line_quality = 0,
                                         value_cluster_penalty = 0,
                                         setup_converter_alignment = 0) {
  query_synergy_runtime_metrics_mark_call("group_category")
  roles <- query_synergy_to_vector(member_roles)
  if (anti_synergy_penalty >= 0.45) {
    return("conflicted_group")
  }
  if (setup_converter_alignment >= 0.42 &&
      "setup" %in% roles &&
      any(c("converter", "bridge", "engine") %in% roles) &&
      any(c("payoff", "finisher", "target") %in% roles)) {
    return("setup_converter_payoff")
  }
  if (value_cluster_penalty >= 0.14 && causal_line_quality < 0.3 && strategic_coherence >= 0.2) {
    return("value_cluster")
  }
  if (member_count >= 4L && causal_line_quality < 0.36 && chain_continuity >= 0.24) {
    return("multi_step_package_line")
  }
  if (causal_line_quality >= 0.36 && chain_continuity >= 0.3) {
    if ("setup" %in% roles && "converter" %in% roles && any(c("payoff", "finisher", "target") %in% roles)) {
      return("setup_converter_payoff")
    }
    if ("engine" %in% roles && "amplifier" %in% roles && any(c("finisher", "payoff", "target") %in% roles)) {
      return("engine_amplifier_finisher")
    }
    if ("fuel" %in% roles && "engine" %in% roles && any(c("payoff", "finisher", "target") %in% roles)) {
      return("fuel_engine_payoff")
    }
    if (member_count >= 4L) {
      return("causal_package")
    }
    return("causal_package")
  }
  if ("amplifier" %in% roles && any(c("finisher", "payoff") %in% roles) && resource_flow_quality >= 0.24) {
    return("amplifier_finish_line")
  }
  if ("setup" %in% roles && "converter" %in% roles && any(c("payoff", "finisher", "target") %in% roles)) {
    return("setup_converter_payoff")
  }
  if ("fuel" %in% roles && "engine" %in% roles && any(c("payoff", "finisher", "target") %in% roles)) {
    return("fuel_engine_payoff")
  }
  if ("bridge" %in% roles) {
    return("bridge_line")
  }
  if (length(query_synergy_to_list(resource_transitions)) > 0L && chain_continuity >= 0.24) {
    return("resource_flow_line")
  }
  if (strategic_coherence >= 0.22) {
    return("shared_value_cluster")
  }
  "general_synergy_group"
}

query_synergy_group_pair_penalty <- function(path_ids, graph) {
  ids <- query_synergy_to_vector(path_ids)
  if (length(ids) < 2L) {
    return(list(penalty = 0, conflicts = character(0)))
  }

  anti_scores <- numeric(0)
  conflicts <- character(0)
  for (i in seq_len(length(ids) - 1L)) {
    for (j in seq.int(i + 1L, length(ids))) {
      edge_keys <- c(
        query_synergy_group_edge_key(ids[[i]], ids[[j]]),
        query_synergy_group_edge_key(ids[[j]], ids[[i]])
      )
      for (edge_key in edge_keys) {
        edge <- graph$edge_lookup[[edge_key]]
        if (!is.list(edge)) {
          next
        }
        anti_value <- suppressWarnings(as.numeric(edge$anti_synergy_score))
        if (is.finite(anti_value) && !is.na(anti_value)) {
          anti_scores <- c(anti_scores, anti_value)
        }
        conflicts <- c(conflicts, query_synergy_to_vector(edge$anti_conflicts))
      }
    }
  }

  penalty <- if (length(anti_scores) > 0L) {
    min(1, mean(anti_scores) + if (length(conflicts) > 0L) 0.18 else 0)
  } else {
    0
  }

  list(penalty = round(penalty, 4), conflicts = unique(conflicts))
}

query_synergy_group_reason_lines <- function(cards,
                                             member_roles,
                                             matched_events,
                                             resource_transitions,
                                             score_breakdown,
                                             anti_conflicts,
                                             line_class = "",
                                             setup_converter_alignment = 0) {
  query_synergy_runtime_metrics_mark_call("group_reason_lines")
  role_line <- paste(vapply(seq_along(cards), function(index) {
    sprintf(
      "%s as %s",
      query_api_scalar(cards[[index]]$name, default = sprintf("Card %s", index)),
      query_api_scalar(member_roles[[index]], default = "bridge")
    )
  }, character(1)), collapse = " -> ")

  reasons <- c(sprintf("Package line: %s", role_line))
  if (length(matched_events) > 0L) {
    reasons <- c(reasons, sprintf(
      "Chain continuity via %s",
      paste(utils::head(query_synergy_to_vector(matched_events), 5L), collapse = ", ")
    ))
  }
  if (length(query_synergy_to_list(resource_transitions)) > 0L) {
    transition_text <- paste(vapply(utils::head(query_synergy_to_list(resource_transitions), 3L), function(transition) {
      via <- query_api_scalar(transition$via, default = query_api_scalar(transition$resource, default = "resource"))
      from <- query_api_scalar(transition$from, default = "")
      to <- query_api_scalar(transition$to, default = "")
      if (nzchar(from) || nzchar(to)) {
        sprintf("%s (%s -> %s)", via, if (nzchar(from)) from else "?", if (nzchar(to)) to else "?")
      } else {
        via
      }
    }, character(1)), collapse = "; ")
    reasons <- c(reasons, sprintf("Resource flow through %s", transition_text))
  }

  strengths <- character(0)
  if (suppressWarnings(as.numeric(score_breakdown$role_coverage)) >= 0.35) {
    strengths <- c(strengths, "role coverage")
  }
  if (suppressWarnings(as.numeric(score_breakdown$strategic_coherence)) >= 0.28) {
    strengths <- c(strengths, "strategic coherence")
  }
  if (suppressWarnings(as.numeric(score_breakdown$repetition_potential)) >= 0.28) {
    strengths <- c(strengths, "repetition potential")
  }
  if (suppressWarnings(as.numeric(score_breakdown$finisher_quality)) >= 0.3) {
    strengths <- c(strengths, "finisher quality")
  }
  if (length(strengths) > 0L) {
    reasons <- c(reasons, sprintf("Scores well because of %s", paste(strengths, collapse = ", ")))
  }
  if (suppressWarnings(as.numeric(score_breakdown$causal_line_quality)) >= 0.34) {
    reasons <- c(reasons, "Represents a causal package line with clear event hand-offs")
  } else if (suppressWarnings(as.numeric(score_breakdown$value_cluster_penalty)) >= 0.14) {
    reasons <- c(reasons, "Looks closer to a shared value cluster than a deterministic line")
  }
  if (suppressWarnings(as.numeric(setup_converter_alignment)) >= 0.35) {
    reasons <- c(reasons, "Line is aligned as setup to converter to target with explicit resource hand-offs")
  }
  if (suppressWarnings(as.numeric(score_breakdown$shell_dependency_penalty)) >= 0.26) {
    reasons <- c(reasons, "Includes shell-dependent pieces and is less generically reliable")
  }
  if (nzchar(query_api_scalar(line_class, default = ""))) {
    reasons <- c(reasons, sprintf("Line classification: %s", query_synergy_humanize_id(line_class)))
  }
  if (length(anti_conflicts) > 0L) {
    reasons <- c(reasons, sprintf(
      "Anti-synergy penalty from %s",
      paste(utils::head(query_synergy_to_vector(anti_conflicts), 4L), collapse = ", ")
    ))
  }

  unique(reasons)
}

query_synergy_build_synergy_group <- function(path_ids,
                                              seed_id,
                                              graph,
                                              registry = query_synergy_event_registry_default()) {
  ids <- query_synergy_to_vector(path_ids)
  if (length(ids) < 3L || !(seed_id %in% ids)) {
    return(NULL)
  }

  cards <- lapply(ids, function(id) graph$nodes[[id]])
  if (any(!vapply(cards, is.list, logical(1)))) {
    return(NULL)
  }

  edges <- vector("list", max(0L, length(ids) - 1L))
  for (index in seq_len(length(ids) - 1L)) {
    edge <- graph$edge_lookup[[query_synergy_group_edge_key(ids[[index]], ids[[index + 1L]])]]
    if (!is.list(edge) || !isTRUE(edge$valid)) {
      return(NULL)
    }
    edges[[index]] <- edge
  }

  member_roles <- vapply(seq_along(cards), function(index) {
    incoming_edge <- if (index > 1L) edges[[index - 1L]] else NULL
    outgoing_edge <- if (index <= length(edges)) edges[[index]] else NULL
    query_synergy_infer_group_member_role(
      cards[[index]],
      position_index = index,
      member_count = length(cards),
      incoming_edge = incoming_edge,
      outgoing_edge = outgoing_edge
    )
  }, character(1))

  if (!(member_roles[[1]] %in% c("setup", "fuel", "engine", "bridge", "converter")) ||
      !(member_roles[[length(member_roles)]] %in% c("payoff", "finisher", "target"))) {
    return(NULL)
  }

  edge_continuity  <- vapply(edges, function(edge) query_synergy_as_num(edge$continuity_score), numeric(1))
  edge_shared_plan <- vapply(edges, function(edge) query_synergy_as_num(edge$axis_scores$shared_plan_score), numeric(1))
  cadence_values   <- vapply(cards, function(card) query_synergy_as_num(card$cadence$strength), numeric(1))
  edge_direct      <- vapply(edges, function(edge) query_synergy_as_num(edge$axis_scores$direct_event_score), numeric(1))
  edge_indirect    <- vapply(edges, function(edge) query_synergy_as_num(edge$axis_scores$indirect_engine_score), numeric(1))
  edge_reliability <- vapply(edges, function(edge) query_synergy_as_num(edge$axis_scores$reliability_score), numeric(1))
  member_shell <- vapply(cards, function(card) {
    suppressWarnings(as.numeric(query_synergy_shell_dependency_axis(card)$score))
  }, numeric(1))
  member_shell[!is.finite(member_shell)] <- 0

  resource_transitions <- unique(unlist(lapply(edges, function(edge) {
    query_synergy_to_list(edge$matched_resource_transitions)
  }), recursive = FALSE), use.names = FALSE)
  matched_events <- unique(c(
    unlist(lapply(edges, function(edge) query_synergy_to_vector(edge$matched_events$direct)), use.names = FALSE),
    unlist(lapply(edges, function(edge) query_synergy_to_vector(edge$matched_events$indirect)), use.names = FALSE),
    unlist(lapply(edges, function(edge) query_synergy_to_vector(edge$matched_events$setup_finisher)), use.names = FALSE),
    unlist(lapply(edges, function(edge) query_synergy_to_vector(edge$matched_events$package_links)), use.names = FALSE),
    unlist(lapply(edges, function(edge) query_synergy_to_vector(edge$matched_events$resource_bridges)), use.names = FALSE),
    unlist(lapply(edges, function(edge) query_synergy_to_vector(edge$matched_events$terminal_bridges)), use.names = FALSE),
    unlist(lapply(cards, function(card) query_synergy_to_vector(card$produced_events)), use.names = FALSE),
    unlist(lapply(cards, function(card) query_synergy_to_vector(card$consumed_events)), use.names = FALSE),
    unlist(lapply(cards, function(card) query_synergy_to_vector(card$setup_events)), use.names = FALSE),
    unlist(lapply(cards, function(card) query_synergy_to_vector(card$finisher_events)), use.names = FALSE)
  ))

  resource_flow_quality <- if (length(edges) > 0L) {
    mean(vapply(edges, function(edge) {
      event_links <- unique(c(
        query_synergy_to_vector(edge$matched_events$direct),
        query_synergy_to_vector(edge$matched_events$indirect),
        query_synergy_to_vector(edge$matched_events$setup_finisher),
        query_synergy_to_vector(edge$matched_events$resource_bridges),
        query_synergy_to_vector(edge$matched_events$terminal_bridges)
      ))
      min(1,
        0.55 * min(1, length(query_synergy_to_list(edge$matched_resource_transitions)) / 2) +
          0.45 * min(1, length(event_links) / 2)
      )
    }, numeric(1)))
  } else {
    0
  }
  chain_continuity <- if (length(edge_continuity) > 0L) {
    min(1, 0.5 * mean(edge_continuity) + 0.3 * min(edge_continuity) + 0.2 * resource_flow_quality)
  } else {
    0
  }

  strategy_tags <- lapply(cards, function(card) unique(query_synergy_to_vector(card$strategy_tags)))
  tag_union <- unique(unlist(strategy_tags, use.names = FALSE))
  tag_intersection <- if (length(strategy_tags) > 0L) Reduce(intersect, strategy_tags) else character(0)
  strategic_coherence <- min(1,
    0.65 * if (length(edge_shared_plan) > 0L) mean(edge_shared_plan) else 0 +
      0.35 * if (length(tag_union) > 0L) length(tag_intersection) / length(tag_union) else 0
  )
  causal_line_quality <- if (length(edges) > 0L) {
    mean(vapply(seq_along(edges), function(index) {
      edge <- edges[[index]]
      transition_count <- length(query_synergy_to_list(edge$matched_resource_transitions))
      min(1,
        0.34 * edge_direct[[index]] +
          0.26 * edge_indirect[[index]] +
          0.24 * edge_reliability[[index]] +
          0.16 * min(1, transition_count / 2)
      )
    }, numeric(1)))
  } else {
    0
  }
  role_coverage <- query_synergy_group_role_coverage_score(member_roles)
  setup_converter_alignment <- {
    start_setup <- as.numeric(member_roles[[1]] %in% c("setup", "fuel"))
    second_converter <- if (length(member_roles) >= 2L) {
      as.numeric(member_roles[[2]] %in% c("converter", "bridge", "engine"))
    } else {
      0
    }
    end_target <- as.numeric(member_roles[[length(member_roles)]] %in% c("payoff", "finisher", "target"))
    transition_handoffs <- min(1, length(query_synergy_to_list(resource_transitions)) / 2)
    event_handoffs <- min(1, length(unique(c(
      matched_events,
      unlist(lapply(edges, function(edge) query_synergy_to_vector(edge$matched_events$resource_bridges)), use.names = FALSE),
      unlist(lapply(edges, function(edge) query_synergy_to_vector(edge$matched_events$terminal_bridges)), use.names = FALSE)
    ))) / 3)
    min(1,
      0.26 * start_setup +
        0.24 * second_converter +
        0.2 * end_target +
        0.15 * transition_handoffs +
        0.15 * event_handoffs
    )
  }
  seed_setup_alignment <- 0
  seed_index <- which(ids %in% query_api_scalar(seed_id, default = ""))
  if (length(seed_index) > 0L) {
    seed_pos <- seed_index[[1]]
    if (seed_pos < length(cards)) {
      seed_card <- cards[[seed_pos]]
      seed_roles <- query_synergy_to_vector(seed_card$roles)
      seed_setup <- "setup" %in% seed_roles || length(query_synergy_to_vector(seed_card$setup_events)) > 0L
      if (seed_setup) {
        next_role <- query_api_scalar(member_roles[[seed_pos + 1L]], default = "bridge")
        next_role_ok <- as.numeric(next_role %in% c("converter", "bridge", "engine"))
        seed_edge <- edges[[seed_pos]]
        seed_bridge_hits <- length(unique(c(
          query_synergy_to_vector(seed_edge$matched_events$setup_finisher),
          query_synergy_to_vector(seed_edge$matched_events$resource_bridges),
          query_synergy_to_vector(seed_edge$matched_events$terminal_bridges)
        )))
        seed_transition_hits <- length(query_synergy_to_list(seed_edge$matched_resource_transitions))
        seed_setup_alignment <- min(1,
          0.45 * next_role_ok +
            0.3 * min(1, seed_bridge_hits / 2) +
            0.25 * min(1, seed_transition_hits / 2)
        )
      }
    }
  }
  setup_converter_alignment <- min(1, 0.75 * setup_converter_alignment + 0.25 * seed_setup_alignment)
  engine_related <- member_roles %in% c("engine", "converter", "bridge", "amplifier")
  cadence_pool <- if (any(engine_related)) cadence_values[engine_related] else cadence_values
  repetition_potential <- min(1,
    if (length(cadence_pool) > 0L) mean(utils::head(sort(cadence_pool, decreasing = TRUE), 2L)) else 0 +
      min(0.15, sum(vapply(cards, function(card) isTRUE(card$cadence$repeatable), logical(1))) * 0.05)
  )
  amplification_bonus <- if ("amplifier" %in% member_roles) {
    min(1, 0.45 + 0.15 * sum(member_roles %in% c("engine", "converter", "bridge")) + 0.2 * repetition_potential)
  } else {
    0
  }
  final_edge <- if (length(edges) > 0L) edges[[length(edges)]] else NULL
  finisher_quality <- if (is.list(final_edge)) {
    min(1,
      0.45 * as.numeric(member_roles[[length(member_roles)]] %in% c("payoff", "finisher", "target")) +
        0.4 * max(0, suppressWarnings(as.numeric(final_edge$score_norm))) +
        0.15 * min(1, length(unique(c(
          query_synergy_to_vector(final_edge$matched_events$direct),
          query_synergy_to_vector(final_edge$matched_events$indirect)
        ))) / 2)
    )
  } else {
    0
  }
  value_cluster_penalty <- max(0, strategic_coherence - (0.6 * causal_line_quality + 0.4 * chain_continuity))
  shell_dependency_penalty <- min(1, mean(utils::head(sort(member_shell, decreasing = TRUE), max(1L, floor((length(member_shell) + 1L) / 2L)))))

  pair_penalty <- query_synergy_group_pair_penalty(ids, graph)
  role_duplication <- sum(pmax(0L, as.integer(table(member_roles)) - 1L)) / max(1, length(member_roles))
  event_duplication <- {
    event_table <- table(matched_events)
    if (length(event_table) == 0L) 0 else sum(pmax(0L, as.integer(event_table) - 1L)) / max(1, length(event_table))
  }
  redundancy_penalty <- min(1, 0.65 * role_duplication + 0.35 * event_duplication)
  complexity_penalty <- min(1,
    if (length(cards) <= 3L) {
      0.04 + (1 - chain_continuity) * 0.04
    } else {
      0.12 + ((length(cards) - 4L) * 0.06) + (1 - chain_continuity) * 0.08
    }
  )

  score_breakdown <- list(
    chain_continuity = round(chain_continuity, 4),
    role_coverage = round(role_coverage, 4),
    strategic_coherence = round(strategic_coherence, 4),
    causal_line_quality = round(causal_line_quality, 4),
    resource_flow_quality = round(resource_flow_quality, 4),
    repetition_potential = round(repetition_potential, 4),
    amplification_bonus = round(amplification_bonus, 4),
    finisher_quality = round(finisher_quality, 4),
    setup_converter_alignment = round(setup_converter_alignment, 4),
    anti_synergy_penalty = round(pair_penalty$penalty, 4),
    value_cluster_penalty = round(value_cluster_penalty, 4),
    shell_dependency_penalty = round(shell_dependency_penalty, 4),
    redundancy_penalty = round(redundancy_penalty, 4),
    complexity_penalty = round(complexity_penalty, 4)
  )

  .gw <- query_synergy_group_weights()
  .gp <- query_synergy_group_penalties()
  .gt <- query_synergy_group_thresholds()
  score_norm <-
    .gw$chain_continuity          * score_breakdown$chain_continuity +
    .gw$role_coverage             * score_breakdown$role_coverage +
    .gw$strategic_coherence       * score_breakdown$strategic_coherence +
    .gw$resource_flow_quality     * score_breakdown$resource_flow_quality +
    .gw$causal_line_quality       * score_breakdown$causal_line_quality +
    .gw$setup_converter_alignment * score_breakdown$setup_converter_alignment +
    .gw$repetition_potential      * score_breakdown$repetition_potential +
    .gw$amplification_bonus       * score_breakdown$amplification_bonus +
    .gw$finisher_quality          * score_breakdown$finisher_quality -
    .gp$anti_synergy     * score_breakdown$anti_synergy_penalty -
    .gp$value_cluster    * score_breakdown$value_cluster_penalty -
    .gp$shell_dependency * score_breakdown$shell_dependency_penalty -
    .gp$redundancy       * score_breakdown$redundancy_penalty -
    .gp$complexity       * score_breakdown$complexity_penalty
  score_norm <- max(0, min(1, score_norm))
  if (score_norm <= .gt$min_score_norm || chain_continuity <= .gt$min_chain_continuity) {
    return(NULL)
  }

  category <- query_synergy_group_category(
    member_roles = member_roles,
    member_count = length(cards),
    anti_synergy_penalty = pair_penalty$penalty,
    resource_transitions = resource_transitions,
    chain_continuity = chain_continuity,
    resource_flow_quality = resource_flow_quality,
    strategic_coherence = strategic_coherence,
    causal_line_quality = causal_line_quality,
    value_cluster_penalty = value_cluster_penalty,
    setup_converter_alignment = setup_converter_alignment
  )
  bucket <- if (length(cards) >= 4L) "package_lines" else "synergy_groups"
  members <- lapply(seq_along(cards), function(index) {
    card <- cards[[index]]
    list(
      id = query_api_scalar(card$id, default = ""),
      name = query_api_scalar(card$name, default = ""),
      scryfall_id = query_api_scalar(card$scryfall_id, default = ""),
      set_code = query_api_scalar(card$set_code, default = ""),
      set_name = query_api_scalar(card$set_name, default = ""),
      mana_cost = query_api_scalar(card$mana_cost, default = ""),
      oracle_text = query_api_scalar(card$oracle_text, default = ""),
      type_line = query_api_scalar(card$type_line, default = ""),
      inferred_role = query_api_scalar(member_roles[[index]], default = "bridge"),
      roles = query_synergy_to_vector(card$roles),
      target_roles = query_synergy_to_vector(card$target_roles),
      position = index,
      is_seed = identical(query_api_scalar(card$id, default = ""), query_api_scalar(seed_id, default = ""))
    )
  })
  intermediate_members <- if (length(members) > 2L) {
    members[2:(length(members) - 1L)]
  } else {
    list()
  }
  package_structure <- list(
    start_member = members[[1]],
    end_member = members[[length(members)]],
    intermediate_members = intermediate_members,
    intermediate_count = length(intermediate_members),
    line_signature = paste(member_roles, collapse = " -> ")
  )
  reasons <- query_synergy_group_reason_lines(
    cards = cards,
    member_roles = member_roles,
    matched_events = matched_events,
    resource_transitions = resource_transitions,
    score_breakdown = score_breakdown,
    anti_conflicts = pair_penalty$conflicts,
    line_class = category,
    setup_converter_alignment = setup_converter_alignment
  )
  line_edges <- lapply(edges, function(edge) {
    list(
      from = edge$from,
      to = edge$to,
      score = edge$score,
      continuity_score = edge$continuity_score,
      matched_events = unique(c(
        query_synergy_to_vector(edge$matched_events$direct),
        query_synergy_to_vector(edge$matched_events$indirect),
        query_synergy_to_vector(edge$matched_events$setup_finisher),
        query_synergy_to_vector(edge$matched_events$package_links),
        query_synergy_to_vector(edge$matched_events$resource_bridges),
        query_synergy_to_vector(edge$matched_events$terminal_bridges)
      )),
      matched_resource_transitions = query_synergy_to_list(edge$matched_resource_transitions),
      relation_classes = query_synergy_to_vector(edge$relation_classes)
    )
  })

  list(
    id = paste(ids, collapse = "|"),
    group_type = if (length(cards) >= 4L) "package_line" else "synergy_group",
    bucket = bucket,
    bucket_label = query_api_scalar(query_synergy_bucket_labels()[[bucket]], default = bucket),
    package_bucket = bucket,
    category = category,
    package_category = category,
    archetype = category,
    line_class = category,
    classification_labels = unique(c(
      category,
      if (identical(category, "value_cluster")) "value_cluster" else if (category %in% c("causal_package", "setup_converter_payoff", "engine_amplifier_finisher", "fuel_engine_payoff")) "causal_package" else "synergy_group"
    )),
    score = as.integer(round(score_norm * 100)),
    total_score = as.integer(round(score_norm * 100)),
    score_norm = round(score_norm, 4),
    score_breakdown = score_breakdown,
    members = members,
    cards = stats::setNames(lapply(members, function(member) list(id = member$id, name = member$name)), make.unique(member_roles)),
    chain = list(
      member_ids = ids,
      member_names = vapply(cards, function(card) query_api_scalar(card$name, default = ""), character(1)),
      role_sequence = member_roles,
      edge_count = length(edges)
    ),
    edges = line_edges,
    package_structure = package_structure,
    line = list(
      member_ids = ids,
      edges = line_edges
    ),
    matched_events = matched_events,
    matched_resource_transitions = resource_transitions,
    anti_conflicts = pair_penalty$conflicts,
    reasons = reasons,
    explanation_text = paste(utils::head(reasons, 3L), collapse = " "),
    archetypes = lapply(query_synergy_archetypes_for_group_members(cards), function(entry) {
      list(
        score = query_synergy_as_num(entry$score),
        contributors = query_synergy_as_int(entry$contributors, default = 0L, min_value = 0L, max_value = 50L),
        label = query_api_scalar(entry$label, default = "")
      )
    })
  )
}

query_synergy_build_group_bucket <- function(groups, bucket_key, limit = 10L) {
  labels <- query_synergy_bucket_labels()
  pool <- query_synergy_to_list(groups)
  if (identical(bucket_key, "package_lines")) {
    pool <- Filter(function(entry) identical(query_api_scalar(entry$bucket, default = ""), "package_lines"), pool)
  }

  if (length(pool) == 0L) {
    return(list(
      key = bucket_key,
      label = query_api_scalar(labels[[bucket_key]], default = bucket_key),
      count = 0L,
      results = list()
    ))
  }

  ord <- order(
    vapply(pool, function(entry) suppressWarnings(as.numeric(entry$total_score)), numeric(1)),
    vapply(pool, function(entry) -length(query_synergy_to_vector(entry$chain$member_ids)), numeric(1)),
    decreasing = TRUE
  )
  pool <- pool[ord]
  cap <- query_synergy_as_int(limit, default = 10L, min_value = 1L, max_value = 50L)
  if (length(pool) > cap) {
    pool <- pool[seq_len(cap)]
  }

  list(
    key = bucket_key,
    label = query_api_scalar(labels[[bucket_key]], default = bucket_key),
    count = length(pool),
    results = pool
  )
}

# -----------------------------------------------------------------------------
# Group refinement (member-neighborhood swap)
# -----------------------------------------------------------------------------
# Given a detected group G = {seed, m1, m2, ...}, try to improve it by
# replacing the weakest non-seed member with a card drawn from the
# top-K neighborhood of one of the OTHER non-seed members.
#
# Rationale: a card D may have a low direct score with the seed but be a
# strong neighbor of m1 or m2; once placed inside the chain
# seed -> m1 -> D, the group's chain continuity may exceed the original.
# This surfaces "bridge" cards that vanilla pool-based detection cannot
# find when ranking is dominated by raw seed-pair scores.
#
# Identifies the weakest member via its incident edge continuity
# contribution (option (b) of the formalisation).
# -----------------------------------------------------------------------------

query_synergy_group_member_weakness <- function(group) {
  edges <- query_synergy_to_list(group$edges)
  members <- query_synergy_to_list(group$members)
  if (length(members) < 3L || length(edges) == 0L) {
    return(NULL)
  }
  contrib <- vapply(seq_along(members), function(i) {
    incoming <- if (i > 1L) suppressWarnings(as.numeric(edges[[i - 1L]]$continuity_score)) else NA_real_
    outgoing <- if (i <= length(edges)) suppressWarnings(as.numeric(edges[[i]]$continuity_score)) else NA_real_
    vals <- c(incoming, outgoing)
    vals <- vals[is.finite(vals)]
    if (length(vals) == 0L) return(NA_real_)
    mean(vals)
  }, numeric(1))
  is_seed <- vapply(members, function(m) isTRUE(m$is_seed), logical(1))
  contrib[is_seed] <- NA_real_
  if (all(is.na(contrib))) {
    return(NULL)
  }
  weakest_pos <- which.min(contrib)
  list(
    position = weakest_pos,
    contribution = contrib[[weakest_pos]],
    member = members[[weakest_pos]]
  )
}

query_synergy_member_top_neighbors <- function(member,
                                               candidate_cards,
                                               format_name,
                                               registry,
                                               k = 12L,
                                               exclude_ids = character(0)) {
  if (!is.list(member) || length(candidate_cards) == 0L) {
    return(list())
  }
  member_profile <- query_synergy_build_compact_profile(member, registry = registry)
  scored <- lapply(candidate_cards, function(card) {
    cid <- query_api_scalar(card$id, default = "")
    if (!nzchar(cid) || cid %in% exclude_ids) {
      return(NULL)
    }
    profile <- query_synergy_build_compact_profile(card, registry = registry)
    s <- suppressWarnings(as.numeric(
      query_synergy_score_candidate_lightweight(member_profile, profile, format_name)$score
    ))
    if (!is.finite(s) || s <= 0) return(NULL)
    list(card = card, cheap_score = s)
  })
  scored <- Filter(Negate(is.null), scored)
  if (length(scored) == 0L) return(list())
  ord <- order(vapply(scored, function(e) e$cheap_score, numeric(1)), decreasing = TRUE)
  scored <- scored[ord]
  scored[seq_len(min(length(scored), k))]
}

query_synergy_refine_single_group <- function(group,
                                              seed,
                                              broader_pool,
                                              format_name,
                                              registry,
                                              k_member = 12L,
                                              theta_seed_score = 18,
                                              max_replacements_to_try = 6L,
                                              min_edge_score = 28L,
                                              max_branching = 6L,
                                              max_paths = 60L) {
  if (!is.list(group)) return(group)
  members <- query_synergy_to_list(group$members)
  if (length(members) < 3L) return(group)

  weakness <- query_synergy_group_member_weakness(group)
  if (is.null(weakness)) return(group)

  weakest_id <- query_api_scalar(weakness$member$id, default = "")
  group_ids <- vapply(members, function(m) query_api_scalar(m$id, default = ""), character(1))
  seed_id <- query_api_scalar(seed$id, default = "")

  anchors <- Filter(function(m) {
    mid <- query_api_scalar(m$id, default = "")
    nzchar(mid) && mid != seed_id && mid != weakest_id
  }, members)
  if (length(anchors) == 0L) return(group)

  # Resolve full normalized cards for anchors from the broader pool (members
  # in the group object are summaries, not full normalized cards).
  pool_by_id <- list()
  for (card in broader_pool) {
    cid <- query_api_scalar(card$id, default = "")
    if (nzchar(cid)) pool_by_id[[cid]] <- card
  }
  pool_by_id[[seed_id]] <- seed

  anchor_cards <- Filter(Negate(is.null), lapply(anchors, function(a) {
    pool_by_id[[query_api_scalar(a$id, default = "")]]
  }))
  weakest_card <- pool_by_id[[weakest_id]]
  if (length(anchor_cards) == 0L || is.null(weakest_card)) return(group)

  # Gather replacement candidates from each anchor's neighborhood.
  exclude <- c(seed_id, group_ids)
  replacement_pool <- list()
  for (anchor_card in anchor_cards) {
    neighbors <- query_synergy_member_top_neighbors(
      member = anchor_card,
      candidate_cards = broader_pool,
      format_name = format_name,
      registry = registry,
      k = k_member,
      exclude_ids = exclude
    )
    for (entry in neighbors) {
      cid <- query_api_scalar(entry$card$id, default = "")
      if (nzchar(cid) && is.null(replacement_pool[[cid]])) {
        replacement_pool[[cid]] <- entry$card
      }
    }
  }
  if (length(replacement_pool) == 0L) return(group)

  # Filter by a minimum score with the seed (we want acceptable, not
  # necessarily great, seed-pair quality so the chain stays anchored to A).
  candidates_with_seed_score <- list()
  for (cid in names(replacement_pool)) {
    cand <- replacement_pool[[cid]]
    fwd <- suppressWarnings(as.numeric(query_synergy_score_pair(seed, cand, format_name)$score))
    bwd <- suppressWarnings(as.numeric(query_synergy_score_pair(cand, seed, format_name)$score))
    seed_pair <- max(
      if (is.finite(fwd)) fwd else 0,
      if (is.finite(bwd)) bwd else 0
    )
    if (seed_pair >= theta_seed_score) {
      candidates_with_seed_score[[cid]] <- list(card = cand, seed_score = seed_pair)
    }
  }
  if (length(candidates_with_seed_score) == 0L) return(group)

  # Order by seed_score desc, cap.
  cand_list <- unname(candidates_with_seed_score)
  ord <- order(vapply(cand_list, function(e) e$seed_score, numeric(1)), decreasing = TRUE)
  cand_list <- cand_list[ord][seq_len(min(length(cand_list), max_replacements_to_try))]

  # For each candidate, build a small pool { remaining group members + d },
  # re-run group detection, and keep the best resulting group.
  remaining <- Filter(function(card) {
    cid <- query_api_scalar(card$id, default = "")
    nzchar(cid) && cid != weakest_id && cid != seed_id
  }, lapply(group_ids, function(gid) pool_by_id[[gid]]))
  remaining <- Filter(Negate(is.null), remaining)
  if (length(remaining) == 0L) return(group)

  group_size <- length(members)
  best_group <- group
  best_score <- suppressWarnings(as.numeric(group$total_score))
  if (!is.finite(best_score)) best_score <- 0
  refinement <- NULL

  for (entry in cand_list) {
    candidate_pool <- c(remaining, list(entry$card))
    res <- query_synergy_detect_groups_for_seed(
      seed = seed,
      candidates = candidate_pool,
      format_name = format_name,
      max_groups = 1L,
      min_edge_score = min_edge_score,
      max_group_size = group_size,
      max_paths = max_paths,
      max_branching = max_branching,
      registry = registry
    )
    new_groups <- query_synergy_to_list(res$groups)
    if (length(new_groups) == 0L) next
    new_group <- new_groups[[1]]
    new_member_ids <- vapply(
      query_synergy_to_list(new_group$members),
      function(m) query_api_scalar(m$id, default = ""),
      character(1)
    )
    cand_id <- query_api_scalar(entry$card$id, default = "")
    if (!(cand_id %in% new_member_ids)) next  # detector dropped the candidate
    new_score <- suppressWarnings(as.numeric(new_group$total_score))
    if (!is.finite(new_score)) next
    if (new_score > best_score) {
      best_score <- new_score
      best_group <- new_group
      refinement <- list(
        replaced_member_id = weakest_id,
        replaced_member_name = query_api_scalar(weakness$member$name, default = ""),
        with_member_id = cand_id,
        with_member_name = query_api_scalar(entry$card$name, default = ""),
        delta_score = round(new_score - suppressWarnings(as.numeric(group$total_score)), 2)
      )
    }
  }

  if (!is.null(refinement)) {
    best_group$refinement_provenance <- refinement
    best_group$reasons <- c(
      query_synergy_to_vector(best_group$reasons),
      sprintf(
        "Refined: replaced %s with %s (anchor neighborhood, +%.1f pts)",
        refinement$replaced_member_name,
        refinement$with_member_name,
        refinement$delta_score
      )
    )
  }

  best_group
}

query_synergy_refine_groups <- function(groups,
                                        seed,
                                        broader_pool,
                                        format_name,
                                        registry,
                                        max_iterations = 2L,
                                        max_groups_to_refine = 3L,
                                        k_member = 12L,
                                        theta_seed_score = 18,
                                        max_replacements_to_try = 6L,
                                        min_edge_score = 28L,
                                        max_branching = 6L,
                                        max_paths = 60L) {
  group_list <- query_synergy_to_list(groups)
  if (length(group_list) == 0L || max_iterations <= 0L || length(broader_pool) == 0L) {
    return(group_list)
  }

  refine_n <- min(length(group_list), max_groups_to_refine)
  for (i in seq_len(refine_n)) {
    current <- group_list[[i]]
    seen_ids <- character(0)
    for (iter in seq_len(max_iterations)) {
      group_signature <- query_api_scalar(current$id, default = "")
      if (group_signature %in% seen_ids) break
      seen_ids <- c(seen_ids, group_signature)
      refined <- query_synergy_refine_single_group(
        group = current,
        seed = seed,
        broader_pool = broader_pool,
        format_name = format_name,
        registry = registry,
        k_member = k_member,
        theta_seed_score = theta_seed_score,
        max_replacements_to_try = max_replacements_to_try,
        min_edge_score = min_edge_score,
        max_branching = max_branching,
        max_paths = max_paths
      )
      old_score <- suppressWarnings(as.numeric(current$total_score))
      new_score <- suppressWarnings(as.numeric(refined$total_score))
      if (!is.finite(new_score) || !is.finite(old_score)) break
      if (new_score <= old_score) break  # no improvement, stop iterating this group
      current <- refined
    }
    group_list[[i]] <- current
  }

  # Re-sort groups by total_score in case refinement reordered them.
  ord <- order(
    vapply(group_list, function(g) suppressWarnings(as.numeric(g$total_score)), numeric(1)),
    decreasing = TRUE
  )
  group_list[ord]
}


query_synergy_detect_groups_for_seed <- function(seed,
                                                 candidates,
                                                 format_name = "commander",
                                                 max_groups = 10L,
                                                 min_edge_score = 28L,
                                                 max_group_size = 4L,
                                                 max_paths = 120L,
                                                 max_branching = 6L,
                                                 progress_callback = NULL,
                                                 progress_range = c(88, 97),
                                                 registry = query_synergy_event_registry_default()) {
  cards <- query_synergy_to_list(candidates)
  if (!is.list(seed) || length(cards) < 2L) {
    return(list(
      groups = list(),
      package_lines = list(),
      meta = list(node_count = 0L, edge_count = 0L, path_count = 0L, pair_count = 0L, branching_cap = 0L)
    ))
  }

  graph <- query_synergy_build_group_graph(
    seed = seed,
    candidates = cards,
    format_name = format_name,
    min_edge_score = min_edge_score,
    progress_callback = progress_callback,
    progress_range = progress_range,
    registry = registry
  )
  search_out <- query_synergy_search_local_group_paths(
    seed_id = query_api_scalar(seed$id, default = ""),
    graph = graph,
    max_group_size = max_group_size,
    max_paths = max_paths,
    max_outgoing_per_node = max_branching
  )

  groups <- list()
  for (path_ids in search_out$paths) {
    group <- query_synergy_build_synergy_group(
      path_ids = path_ids,
      seed_id = query_api_scalar(seed$id, default = ""),
      graph = graph,
      registry = registry
    )
    if (!is.list(group)) {
      next
    }
    groups[[length(groups) + 1L]] <- group
  }

  if (length(groups) == 0L) {
    return(list(
      groups = list(),
      package_lines = list(),
      meta = list(
        node_count = graph$node_count,
        edge_count = graph$edge_count,
        path_count = search_out$path_count,
        pair_count = graph$pair_count,
        branching_cap = query_synergy_as_int(max_branching, default = 6L, min_value = 1L, max_value = 25L)
      )
    ))
  }

  keys <- vapply(groups, function(g) query_api_scalar(g$id, default = ""), character(1))
  deduped <- groups[nzchar(keys) & !duplicated(keys)]

  ord <- order(
    vapply(deduped, function(entry) suppressWarnings(as.numeric(entry$total_score)), numeric(1)),
    vapply(deduped, function(entry) suppressWarnings(as.numeric(entry$score_breakdown$chain_continuity)), numeric(1)),
    decreasing = TRUE
  )
  deduped <- deduped[ord]
  limit <- query_synergy_as_int(max_groups, default = 10L, min_value = 1L, max_value = 50L)
  if (length(deduped) > limit) {
    deduped <- deduped[seq_len(limit)]
  }

  list(
    groups = deduped,
    package_lines = Filter(function(entry) identical(query_api_scalar(entry$bucket, default = ""), "package_lines"), deduped),
    meta = list(
      node_count = graph$node_count,
      edge_count = graph$edge_count,
      path_count = search_out$path_count,
      pair_count = graph$pair_count,
      branching_cap = query_synergy_as_int(max_branching, default = 6L, min_value = 1L, max_value = 25L)
    )
  )
}

query_synergy_detect_packages_for_target <- function(target,
                                                     candidates,
                                                     format_name = "commander",
                                                     max_packages = 10L,
                                                     min_edge_score = 35L,
                                                     progress_callback = NULL,
                                                     progress_range = c(88, 97)) {
  group_out <- query_synergy_detect_groups_for_seed(
    seed = target,
    candidates = candidates,
    format_name = format_name,
    max_groups = max_packages,
    min_edge_score = min_edge_score,
    max_group_size = 4L,
    max_paths = max(96L, length(query_synergy_to_list(candidates)) * 12L),
    max_branching = 6L,
    progress_callback = progress_callback,
    progress_range = progress_range
  )

  query_synergy_to_list(group_out$groups)
}
