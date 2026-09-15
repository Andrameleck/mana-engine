#' Create a Functional Fact
#'
#' @param kind Fact kind such as `object_available` or `event`.
#' @param object Canonical object or event name.
#' @param zone Relevant zone.
#' @param controller Relevant controller.
#' @param qualifiers Additional exact restrictions.
#'
#' @return A functional fact list.
#' @export
analysis_fact <- function(kind,
                          object = "",
                          zone = "",
                          controller = "you",
                          qualifiers = character(0)) {
  values <- list(kind = kind, object = object, zone = zone, controller = controller)
  if (any(vapply(values, length, integer(1)) != 1L) || any(vapply(values, function(x) is.na(as.character(x)), logical(1)))) {
    stop("fact fields must be scalar strings", call. = FALSE)
  }
  list(
    kind = trimws(as.character(kind)),
    object = trimws(as.character(object)),
    zone = trimws(as.character(zone)),
    controller = trimws(as.character(controller)),
    qualifiers = sort(unique(as.character(qualifiers)))
  )
}

#' Create a Functional Ability Annotation
#'
#' @param id Stable ability identifier.
#' @param card_id Owning canonical card identifier.
#' @param family Covered functional family.
#' @param produces List of facts emitted by the ability.
#' @param requires List of facts required or observed by the ability.
#' @param costs List of facts consumed as costs.
#' @param evidence Oracle text fragment supporting the annotation.
#' @param status `verified`, `inferred`, or `unknown`.
#' @param unknown_conditions Character vector of unresolved restrictions.
#'
#' @return A validated ability list.
#' @export
analysis_ability <- function(id,
                             card_id,
                             family,
                             produces = list(),
                             requires = list(),
                             costs = list(),
                             evidence = "",
                             status = c("verified", "inferred", "unknown"),
                             unknown_conditions = character(0)) {
  status <- match.arg(status)
  family <- trimws(as.character(family))
  if (length(family) != 1L || is.na(family) || !nzchar(family)) {
    stop("family must be a non-empty scalar string", call. = FALSE)
  }
  id <- trimws(as.character(id))
  card_id <- trimws(as.character(card_id))
  if (length(id) != 1L || length(card_id) != 1L || is.na(id) || is.na(card_id) || !nzchar(id) || !nzchar(card_id)) {
    stop("ability id and card_id must be non-empty scalar strings", call. = FALSE)
  }
  structure(list(
    id = id,
    card_id = card_id,
    family = family,
    produces = produces,
    requires = requires,
    costs = costs,
    evidence = as.character(evidence),
    status = status,
    unknown_conditions = unique(as.character(unknown_conditions))
  ), class = "mtg_analysis_ability")
}

.analysis_add_ability <- function(out, card_id, family, produces = list(), requires = list(), costs = list(), evidence, suffix, unknown = character(0)) {
  out[[length(out) + 1L]] <- analysis_ability(
    id = paste(card_id, suffix, sep = ":"), card_id = card_id, family = family,
    produces = produces, requires = requires, costs = costs,
    evidence = evidence, status = "inferred", unknown_conditions = unknown
  )
  out
}

#' Extract Covered Functional Abilities
#'
#' Deterministically extracts a deliberately limited subset of Oracle wording.
#' Unrecognized text remains reported instead of being treated as evidence.
#'
#' @param card Card list containing an id or name and canonical `oracle_text`.
#'
#' @return A list with `abilities`, coverage, and unsupported text.
#' @export
extract_functional_abilities <- function(card) {
  card_id <- .analysis_card_id(card)
  text <- paste(unlist(card$oracle_text %||% "", use.names = FALSE), collapse = "\n")
  low <- tolower(text)
  abilities <- list()
  oracle <- parse_oracle_text(card)
  for (clause in oracle$clauses) {
    if (clause$status != "parsed") next
    abilities[[length(abilities) + 1L]] <- analysis_ability(
      id = clause$id, card_id = card_id, family = .analysis_oracle_family(clause),
      produces = clause$produces, requires = clause$requires, costs = clause$costs,
      evidence = clause$text, status = "inferred"
    )
  }

  type_line <- tolower(paste(unlist(card$type_line %||% "", use.names = FALSE), collapse = " "))
  spell_type <- if (grepl("instant", type_line)) "instant" else if (grepl("sorcery", type_line)) "sorcery" else if (nzchar(type_line) && !grepl("land", type_line)) "spell" else ""
  if (nzchar(spell_type)) {
    intrinsic <- list(analysis_fact("event", paste0(spell_type, "_cast"), "stack"))
    permanent_type <- if (grepl("creature", type_line)) "creature" else if (grepl("artifact", type_line)) "artifact" else if (grepl("enchantment", type_line)) "enchantment" else if (grepl("planeswalker", type_line)) "planeswalker" else ""
    if (nzchar(permanent_type)) intrinsic <- c(intrinsic, list(analysis_fact("event", paste0(permanent_type, "_enters"), "battlefield")))
    abilities <- .analysis_add_ability(abilities, card_id, "oracle_general",
      produces = intrinsic,
      evidence = type_line, suffix = "intrinsic-cast")
  }
  if (grepl("land", type_line)) {
    abilities <- .analysis_add_ability(abilities, card_id, "oracle_general",
      produces = list(analysis_fact("event", "land_enters", "battlefield")),
      evidence = type_line, suffix = "intrinsic-land-play")
  }

  list(
    card_id = card_id,
    abilities = abilities,
    coverage = if (!length(oracle$clauses)) "empty" else if (!oracle$coverage$unresolved) "complete" else if (oracle$coverage$parsed) "partial" else "unknown",
    coverage_details = oracle$coverage,
    unsupported_text = paste(oracle$unresolved_text, collapse = "\n"),
    oracle = oracle,
    extractor_version = "functional-rules-0.2.0"
  )
}
