#' Create a Typed Strategy Port
#'
#' Ports describe resources, objects, events, or states consumed, required, or
#' produced by a card action. Unknown attributes remain explicit.
#'
#' @param kind One of `object`, `event`, `resource`, or `state`.
#' @param object Canonical object or event identifier.
#' @param zone Zone in which the object exists, or an empty string.
#' @param controller `you`, `opponent`, `each`, `any`, or `unknown`.
#' @param quantity Known non-negative quantity, or `NA_real_`.
#' @param qualifiers Additional canonical restrictions.
#' @return A typed port list.
#' @export
strategy_port <- function(kind,
                          object,
                          zone = "",
                          controller = "you",
                          quantity = 1,
                          qualifiers = character(0)) {
  kind <- match.arg(kind, c("object", "event", "resource", "state"))
  scalar <- function(x, label) {
    x <- trimws(as.character(x))
    if (length(x) != 1L || is.na(x) || (label == "object" && !nzchar(x))) {
      stop(label, " must be a valid scalar string", call. = FALSE)
    }
    x
  }
  object <- scalar(object, "object")
  zone <- scalar(zone, "zone")
  controller <- match.arg(controller, c("you", "opponent", "each", "any", "unknown"))
  quantity <- as.numeric(quantity)
  if (length(quantity) != 1L || (!is.na(quantity) && (!is.finite(quantity) || quantity < 0))) {
    stop("quantity must be one non-negative number or NA", call. = FALSE)
  }
  structure(list(
    kind = kind, object = object, zone = zone, controller = controller,
    quantity = quantity, qualifiers = sort(unique(as.character(qualifiers)))
  ), class = "mtg_strategy_port")
}

#' Create a Typed Strategy Action
#'
#' @param id Stable action identifier.
#' @param card_id Canonical owning card identifier.
#' @param action_type Action family such as `zone_transfer` or `mana_production`.
#' @param consumes,requires,produces Lists of [strategy_port()] objects.
#' @param from_zone,to_zone Zones for a zone transfer.
#' @param selector Canonical object accepted by a parameterized action.
#' @param evidence Exact Oracle text supporting the action.
#' @param status `inferred`, `verified`, or `unknown`.
#' @param unknown_conditions Unresolved restrictions.
#' @return A validated strategy action.
#' @export
strategy_action <- function(id,
                            card_id,
                            action_type,
                            consumes = list(),
                            requires = list(),
                            produces = list(),
                            from_zone = "",
                            to_zone = "",
                            selector = "",
                            evidence = "",
                            status = c("inferred", "verified", "unknown"),
                            unknown_conditions = character(0)) {
  status <- match.arg(status)
  id <- trimws(as.character(id)); card_id <- trimws(as.character(card_id))
  action_type <- trimws(as.character(action_type))
  if (any(lengths(list(id, card_id, action_type)) != 1L) ||
      any(is.na(c(id, card_id, action_type))) || any(!nzchar(c(id, card_id, action_type)))) {
    stop("id, card_id, and action_type must be non-empty scalar strings", call. = FALSE)
  }
  validate_ports <- function(x, label) {
    if (!is.list(x) || any(!vapply(x, inherits, logical(1), "mtg_strategy_port"))) {
      stop(label, " must be a list of strategy ports", call. = FALSE)
    }
    x
  }
  structure(list(
    id = id, card_id = card_id, action_type = action_type,
    consumes = validate_ports(consumes, "consumes"),
    requires = validate_ports(requires, "requires"),
    produces = validate_ports(produces, "produces"),
    from_zone = as.character(from_zone), to_zone = as.character(to_zone),
    selector = as.character(selector), evidence = as.character(evidence),
    status = status, unknown_conditions = unique(as.character(unknown_conditions))
  ), class = "mtg_strategy_action")
}

.strategy_object <- function(text, default = "card") {
  low <- tolower(text)
  if (grepl("creature", low)) "creature_card"
  else if (grepl("artifact", low)) "artifact_card"
  else if (grepl("land", low)) "land_card"
  else if (grepl("permanent", low)) "permanent_card"
  else default
}

.strategy_mana_symbols <- function(cost) {
  tokens <- regmatches(toupper(as.character(cost %||% "")), gregexpr("\\{[^}]+\\}", toupper(as.character(cost %||% "")), perl = TRUE))[[1]]
  if (!length(tokens) || identical(tokens, character(0))) return(character(0))
  tokens
}

.strategy_mana_value <- function(cost) {
  symbols <- .strategy_mana_symbols(cost)
  if (!length(symbols)) return(0)
  sum(vapply(symbols, function(x) {
    value <- sub("[{}]", "", x)
    if (grepl("^[0-9]+$", value)) as.numeric(value) else if (value %in% c("X", "Y", "Z")) 0 else 1
  }, numeric(1)))
}

.strategy_add_action <- function(out, card_id, suffix, type, ..., evidence, unknown = character(0)) {
  out[[length(out) + 1L]] <- strategy_action(
    id = paste(card_id, suffix, sep = ":"), card_id = card_id,
    action_type = type, ..., evidence = evidence,
    status = if (length(unknown)) "unknown" else "inferred",
    unknown_conditions = unknown
  )
  out
}

#' Extract Strategy Actions from Oracle Text
#'
#' Extracts a conservative, typed subset used to discover composable engines.
#' Unsupported clauses are returned explicitly and are never treated as absent
#' effects.
#'
#' @param card Card list with an id or name, Oracle text, type line, and mana cost.
#' @return A versioned record containing actions and unsupported clauses.
#' @export
extract_strategy_actions <- function(card) {
  card_id <- .analysis_card_id(card)
  text <- paste(unlist(card$oracle_text %||% "", use.names = FALSE), collapse = "\n")
  clauses <- .analysis_oracle_split(text)
  actions <- list(); recognized <- logical(length(clauses))
  add <- function(i, suffix, type, ..., unknown = character(0)) {
    actions <<- .strategy_add_action(actions, card_id, paste0(suffix, "-", i), type,
      ..., evidence = clauses[[i]], unknown = unknown)
    recognized[[i]] <<- TRUE
  }
  for (i in seq_along(clauses)) {
    clause <- clauses[[i]]; low <- tolower(clause)
    if (grepl("search your library.*put (that card|them|those cards).*graveyard", low)) {
      selector <- .strategy_object(low)
      add(i, "library-graveyard", "zone_transfer", from_zone = "library", to_zone = "graveyard",
        selector = selector,
        requires = list(strategy_port("object", selector, "library")),
        produces = list(strategy_port("object", selector, "graveyard")))
    }
    if (grepl("(put|return).*creature card.*from (a|your|their) graveyard.*(onto|to) the battlefield", low) ||
        grepl("each player puts a creature card from their graveyard onto the battlefield", low)) {
      controller <- if (grepl("each player", low)) "each" else "you"
      add(i, "graveyard-battlefield", "zone_transfer", from_zone = "graveyard", to_zone = "battlefield",
        selector = "creature_card",
        requires = list(strategy_port("object", "creature_card", "graveyard", controller)),
        produces = list(
          strategy_port("object", "creature", "battlefield", controller),
          strategy_port("event", "creature_enters", "battlefield", controller)
        ), unknown = if (controller == "each") "symmetric_effect" else character(0))
    }
    if (grepl("^draw (one|two|three|[0-9]+|x|a) cards?", low)) {
      add(i, "draw", "card_selection", produces = list(strategy_port("resource", "card_in_hand", "hand", quantity = NA_real_)))
    }
    if (grepl("^add (\\{[^}]+\\})+", low, perl = TRUE)) {
      mana <- regmatches(clause, gregexpr("\\{[WUBRGC]\\}", toupper(clause), perl = TRUE))[[1]]
      add(i, "mana", "mana_production", produces = list(strategy_port("resource", "mana", quantity = length(mana), qualifiers = mana)))
    }
    if (grepl("target player reveals their hand.*discards? that card", low) ||
        grepl("^(that|target|each) (player|opponent).*discards?", low)) {
      add(i, "hand-disruption", "hand_disruption",
        requires = list(strategy_port("object", "nonland_card", "hand", "any")),
        produces = list(strategy_port("event", "card_discarded", "graveyard", "any")))
    }
    if (grepl("^(when|whenever|at)\\b", low)) {
      trigger <- .analysis_oracle_trigger_facts(sub("^((when|whenever|at)\\b[^,]*),.*$", "\\1", clause, ignore.case = TRUE, perl = TRUE))
      if (length(trigger)) {
        add(i, "trigger", "triggered_payoff",
          requires = lapply(trigger, function(x) strategy_port("event", x$object, x$zone, x$controller)),
          unknown = "effect_value_not_evaluated")
      }
    }
  }
  type_line <- tolower(paste(unlist(card$type_line %||% "", use.names = FALSE), collapse = " "))
  if (grepl("creature", type_line)) {
    actions <- .strategy_add_action(actions, card_id, "intrinsic-creature", "payload",
      requires = list(strategy_port("object", "creature_card", "library")),
      produces = list(strategy_port("object", "creature", "battlefield")),
      evidence = type_line)
  }
  list(
    card_id = card_id, actions = actions,
    unsupported_text = clauses[!recognized],
    coverage = list(total = length(clauses), recognized = sum(recognized),
      ratio = if (length(clauses)) mean(recognized) else 1),
    extractor_version = "strategy-actions-0.3.0"
  )
}

.strategy_selector_compatible <- function(output, input) {
  identical(output, input) ||
    output == "card" && input %in% c("creature_card", "artifact_card", "land_card", "permanent_card") ||
    output == "permanent_card" && input %in% c("creature_card", "artifact_card", "land_card") ||
    output == "creature_card" && input %in% c("card", "permanent_card") ||
    output %in% c("artifact_card", "land_card", "permanent_card") && input == "card"
}

.strategy_card_record <- function(card) {
  list(
    id = .analysis_card_id(card), name = as.character(card$name %||% .analysis_card_id(card)),
    type_line = paste(unlist(card$type_line %||% "", use.names = FALSE), collapse = " "),
    mana_cost = paste(unlist(card$mana_cost %||% "", use.names = FALSE), collapse = ""),
    mana_value = .strategy_mana_value(card$mana_cost %||% ""),
    oracle_text = paste(unlist(card$oracle_text %||% "", use.names = FALSE), collapse = "\n"),
    actions = extract_strategy_actions(card)
  )
}

.strategy_engine_key <- function(a, b) paste(a$from_zone, a$to_zone, b$to_zone, b$selector, sep = "|")

#' Discover Composable Strategy Engines
#'
#' Finds two-stage zone-transfer engines, their compatible payloads, and support
#' candidates. Results are structural candidates; no probability or power score
#' is invented.
#'
#' @param cards List of unique card lists.
#' @param context A validated [analysis_context()].
#' @param limit Maximum engines returned.
#' @param max_pair_evaluations Maximum ordered action pairs inspected.
#' @return A versioned result with engines, witnesses, payloads, and limitations.
#' @export
discover_strategy_engines <- function(cards,
                                      context = analysis_context(),
                                      limit = 20L,
                                      max_pair_evaluations = 50000L) {
  if (!is.list(cards)) stop("cards must be a list", call. = FALSE)
  if (!inherits(context, "mtg_analysis_context")) stop("context must come from analysis_context()", call. = FALSE)
  limit <- as.integer(limit); max_pair_evaluations <- as.integer(max_pair_evaluations)
  if (is.na(limit) || limit < 1L || is.na(max_pair_evaluations) || max_pair_evaluations < 1L) stop("limits must be positive integers", call. = FALSE)
  records <- lapply(cards, .strategy_card_record)
  ids <- vapply(records, `[[`, character(1), "id")
  if (anyDuplicated(ids)) stop("cards must have unique canonical ids", call. = FALSE)
  legal <- vapply(cards, function(x) .analysis_context_card_status(x, context)$status != "false", logical(1))
  records <- records[legal]
  record_names <- stats::setNames(vapply(records, `[[`, character(1), "name"), vapply(records, `[[`, character(1), "id"))
  transfers <- unlist(lapply(records, function(rec) Filter(function(a) a$action_type == "zone_transfer", rec$actions$actions)), recursive = FALSE)
  payloads <- Filter(function(rec) grepl("creature", tolower(rec$type_line)), records)
  support_types <- c("mana_production", "card_selection", "hand_disruption")
  support <- lapply(Filter(function(rec) any(vapply(rec$actions$actions, function(a) a$action_type %in% support_types, logical(1))), records), function(rec) {
    list(card_id = rec$id, card_name = rec$name,
      functions = sort(unique(vapply(Filter(function(a) a$action_type %in% support_types, rec$actions$actions), `[[`, character(1), "action_type"))))
  })
  engines <- list(); seen <- character(0); explored <- 0L; truncated <- FALSE
  if (length(transfers) >= 2L) for (first in transfers) for (second in transfers) {
    if (identical(first$card_id, second$card_id)) next
    explored <- explored + 1L
    if (explored > max_pair_evaluations) { truncated <- TRUE; break }
    if (!nzchar(first$to_zone) || first$to_zone != second$from_zone ||
        !.strategy_selector_compatible(first$selector, second$selector)) next
    key <- .strategy_engine_key(first, second)
    compatible <- Filter(function(rec) {
      .strategy_selector_compatible("creature_card", second$selector)
    }, payloads)
    payload_out <- lapply(compatible, function(rec) list(
      card_id = rec$id, card_name = rec$name, mana_value = rec$mana_value,
      terminal_actions = setdiff(sort(unique(vapply(rec$actions$actions, `[[`, character(1), "action_type"))), "payload"),
      status = if (length(rec$actions$unsupported_text)) "indeterminate" else "structurally_compatible",
      unsupported_text = rec$actions$unsupported_text
    ))
    unknown <- unique(c(first$unknown_conditions, second$unknown_conditions))
    setup <- list(card_id = first$card_id, card_name = unname(record_names[[first$card_id]]), action_id = first$id,
      evidence = first$evidence, unknown_conditions = first$unknown_conditions)
    executor <- list(card_id = second$card_id, card_name = unname(record_names[[second$card_id]]), action_id = second$id,
      evidence = second$evidence, unknown_conditions = second$unknown_conditions)
    existing <- match(key, seen)
    if (!is.na(existing)) {
      setup_ids <- vapply(engines[[existing]]$realizations$setup, `[[`, character(1), "action_id")
      executor_ids <- vapply(engines[[existing]]$realizations$executor, `[[`, character(1), "action_id")
      if (!setup$action_id %in% setup_ids) engines[[existing]]$realizations$setup <- c(engines[[existing]]$realizations$setup, list(setup))
      if (!executor$action_id %in% executor_ids) engines[[existing]]$realizations$executor <- c(engines[[existing]]$realizations$executor, list(executor))
      engines[[existing]]$unknown_conditions <- unique(c(engines[[existing]]$unknown_conditions, unknown))
      clean_setup <- any(vapply(engines[[existing]]$realizations$setup, function(x) !length(x$unknown_conditions), logical(1)))
      clean_executor <- any(vapply(engines[[existing]]$realizations$executor, function(x) !length(x$unknown_conditions), logical(1)))
      engines[[existing]]$feasibility_status <- if (clean_setup && clean_executor) "structural_witness_only" else "indeterminate"
    } else {
      seen <- c(seen, key)
      engines[[length(engines) + 1L]] <- list(
        engine_id = paste0("engine-", length(engines) + 1L),
        pattern = paste(first$from_zone, first$to_zone, second$to_zone, sep = " -> "),
        interface = list(input = second$selector, intermediate = first$to_zone, output = second$to_zone),
        realizations = list(setup = list(setup), executor = list(executor)),
        structural_status = "matched",
        feasibility_status = if (length(unknown)) "indeterminate" else "structural_witness_only",
        unknown_conditions = unique(c(unknown, "mana_and_timing_not_executed", "opponent_responses_not_executed")),
        payloads = payload_out,
        support_candidates = support,
        explanation = paste(first$card_id, "moves", first$selector, "from", first$from_zone, "to", first$to_zone,
          "and", second$card_id, "can continue from", second$from_zone, "to", second$to_zone)
      )
    }
  }
  list(
    ok = TRUE, model_version = "strategy-engine-0.3.0",
    extractor_version = "strategy-actions-0.3.0", data_version = context$rules_version,
    context = unclass(context), results = utils::head(engines, limit),
    search = list(pair_evaluations = explored, budget = max_pair_evaluations),
    search_truncated = truncated, display_truncated = length(engines) > limit,
    warnings = "Results prove structural composition only; execution probability and deck utility are not yet evaluated."
  )
}
