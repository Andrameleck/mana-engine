#' Create a Functional Analysis Context
#'
#' Validate the explicit constraints used by the functional synergy engine.
#'
#' @param format Optional format name.
#' @param rules_version Rules snapshot identifier.
#' @param allowed_colors Character vector of allowed color identity symbols, or
#'   `NULL` when the identity constraint is unknown.
#' @param mode One of `explore`, `deck`, or `sequence`.
#' @param objective Optional requested functional objective.
#' @param inventory Optional named numeric vector of available quantities.
#'
#' @return A validated context list.
#' @export
analysis_context <- function(format = "",
                             rules_version = "",
                             allowed_colors = NULL,
                             mode = c("explore", "deck", "sequence"),
                             objective = "",
                             inventory = NULL) {
  mode <- match.arg(mode)
  format <- as.character(format)
  rules_version <- as.character(rules_version)
  objective <- as.character(objective)
  if (length(format) != 1L || is.na(format) ||
      length(rules_version) != 1L || is.na(rules_version) ||
      length(objective) != 1L || is.na(objective)) {
    stop("format, rules_version, and objective must be scalar strings", call. = FALSE)
  }
  # Objectives are optional identifiers, not a closed list of deck archetypes.
  if (nchar(objective) > 200L) stop("objective must not exceed 200 characters", call. = FALSE)
  if (!is.null(allowed_colors)) {
    allowed_colors <- unique(toupper(trimws(as.character(allowed_colors))))
    allowed_colors <- allowed_colors[nzchar(allowed_colors)]
    if (any(!allowed_colors %in% c("W", "U", "B", "R", "G"))) {
      stop("allowed_colors must contain only W, U, B, R, or G", call. = FALSE)
    }
  }
  if (!is.null(inventory)) {
    inventory <- unlist(inventory, use.names = TRUE)
    inventory_names <- names(inventory)
    inventory <- as.numeric(inventory)
    names(inventory) <- inventory_names
    if (is.null(inventory_names) || any(!nzchar(inventory_names)) ||
        any(!is.finite(inventory)) || any(inventory < 0)) {
      stop("inventory must be a finite, non-negative named numeric vector", call. = FALSE)
    }
  }

  unknown <- character(0)
  if (!nzchar(trimws(format))) unknown <- c(unknown, "format")
  if (!nzchar(trimws(rules_version))) unknown <- c(unknown, "rules_version")
  if (is.null(allowed_colors)) unknown <- c(unknown, "allowed_colors")
  if (is.null(inventory)) unknown <- c(unknown, "inventory")

  structure(list(
    format = trimws(format),
    rules_version = trimws(rules_version),
    allowed_colors = allowed_colors,
    mode = mode,
    objective = trimws(objective),
    inventory = inventory,
    unknown_fields = unknown
  ), class = "mtg_analysis_context")
}

.analysis_truth_and <- function(values) {
  values <- as.character(values)
  if (any(values == "false")) return("false")
  if (length(values) == 0L || all(values == "true")) return("true")
  "unknown"
}

.analysis_normalize_colors <- function(x) {
  if (is.null(x)) return(NULL)
  raw <- unique(toupper(unlist(x, use.names = FALSE)))
  raw <- raw[nzchar(raw) & raw %in% c("W", "U", "B", "R", "G")]
  sort(raw)
}

.analysis_card_id <- function(card) {
  candidates <- c(card$oracle_id, card$id, card$scryfall_id, card$name)
  candidates <- trimws(as.character(candidates))
  candidates <- candidates[nzchar(candidates)]
  if (length(candidates) == 0L) stop("each card needs an id or name", call. = FALSE)
  gsub("[^a-z0-9]+", "-", tolower(candidates[[1]]))
}

.analysis_context_card_status <- function(card, context) {
  colors <- .analysis_normalize_colors(card$color_identity %||% card$colors)
  allowed <- context$allowed_colors
  color_status <- if (is.null(allowed) || is.null(colors)) {
    "unknown"
  } else if (all(colors %in% allowed)) {
    "true"
  } else {
    "false"
  }
  list(
    status = if (color_status == "false" || nzchar(context$format) && .deck_legality_status(card, context$format) %in% c("banned", "not_legal")) "false" else color_status,
    reasons = c(if (color_status == "false") "color_identity", if (nzchar(context$format) && .deck_legality_status(card, context$format) %in% c("banned", "not_legal")) "format_legality"),
    unknown = c(if (color_status == "unknown") "color_identity", if (nzchar(context$format) && .deck_legality_status(card, context$format) == "unknown") "format_legality")
  )
}

.analysis_filter_objective <- function(relations, context) {
  if (!nzchar(context$objective)) return(relations)
  Filter(function(relation) {
    ports <- c(relation$supplied_ports, relation$matched_requirements)
    identical(relation$family, context$objective) || any(vapply(ports, function(port) identical(port$object, context$objective), logical(1)))
  }, relations)
}

`%||%` <- function(x, y) if (is.null(x)) y else x
