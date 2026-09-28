.analysis_oracle_trim <- function(x) {
  trimws(gsub("[[:space:]]+", " ", as.character(x)))
}

.analysis_oracle_strip_reminder <- function(text) {
  # Oracle reminder text is explanatory, not an additional game instruction.
  gsub("\\([^()]*(?:\\([^()]*\\)[^()]*)*\\)", "", text, perl = TRUE)
}

.analysis_oracle_split <- function(text) {
  text <- gsub("\\r", "", as.character(text))
  lines <- unlist(strsplit(text, "\\n+", perl = TRUE), use.names = FALSE)
  out <- character(0)
  for (line in lines) {
    line <- .analysis_oracle_trim(.analysis_oracle_strip_reminder(line))
    if (!nzchar(line)) next
    # Preserve activated abilities as one clause; split independent sentences.
    pieces <- unlist(strsplit(line, "(?<=[.!?])\\s+(?=[A-Z{])", perl = TRUE), use.names = FALSE)
    out <- c(out, .analysis_oracle_trim(pieces))
  }
  out[nzchar(out)]
}

.analysis_oracle_controller <- function(text) {
  low <- tolower(text)
  if (grepl("an opponent|opponents|they control|their ", low)) "opponent"
  else if (grepl("any player|each player|a player", low)) "any"
  else "you"
}

.analysis_oracle_object <- function(text, fallback = "object") {
  low <- tolower(text)
  token <- grepl("token", low)
  base <- if (grepl("instant or sorcery", low)) "spell" else if (grepl("creature", low)) "creature" else if (grepl("artifact|treasure|clue|food|blood|map|gold", low)) "artifact" else if (grepl("enchantment", low)) "enchantment" else if (grepl("planeswalker", low)) "planeswalker" else if (grepl("land", low)) "land" else if (grepl("instant", low)) "instant" else if (grepl("sorcery", low)) "sorcery" else if (grepl("permanent", low)) "permanent" else if (grepl("spell", low)) "spell" else if (grepl("card", low)) "card" else fallback
  if (token && base == "token") "token" else if (token && base != "object") paste0(base, "_token") else base
}

.analysis_oracle_family <- function(clause) {
  objects <- vapply(c(clause$requires, clause$costs, clause$produces), `[[`, character(1), "object")
  if (any(grepl("sacrificed|_dies$|creature_token", objects)) || grepl("sacrifice", clause$text, ignore.case = TRUE)) "tokens_sacrifice_death"
  else if (any(objects %in% c("card", "creature_card")) && grepl("graveyard|mill|discard", clause$text, ignore.case = TRUE)) "graveyard_reanimation"
  else if (any(grepl("_cast$|spell_copied", objects))) "cast_copy"
  else "oracle_general"
}

.analysis_oracle_zone <- function(text, default = "") {
  low <- tolower(text)
  if (grepl("graveyard|dies", low)) "graveyard"
  else if (grepl("battlefield|enters|attacks|blocks", low)) "battlefield"
  else if (grepl("library", low)) "library"
  else if (grepl("hand", low)) "hand"
  else if (grepl("exile|exiled", low)) "exile"
  else if (grepl("stack|spell", low)) "stack"
  else default
}

.analysis_oracle_qualifiers <- function(text) {
  low <- tolower(text)
  q <- character(0)
  for (value in c("another", "nontoken", "token", "tapped", "untapped", "attacking", "blocking", "noncreature", "nonland")) {
    if (grepl(value, low, fixed = TRUE)) q <- c(q, value)
  }
  unique(q)
}

.analysis_oracle_keywords <- function(text) {
  low <- tolower(text)
  keywords <- c(
    "deathtouch", "defender", "double strike", "first strike", "flash", "flying",
    "haste", "hexproof", "indestructible", "lifelink", "menace", "reach",
    "trample", "vigilance", "ward", "affinity", "afterlife", "annihilator",
    "battle cry", "cascade", "changeling", "convoke", "crew", "devoid",
    "devour", "dredge", "embalm", "emerge", "escape", "evolve", "exalted",
    "exploit", "extort", "fabricate", "fear", "flashback", "foretell",
    "hideaway", "infect", "kicker", "landwalk", "modular", "mutate",
    "persist", "prowess", "rebound", "riot", "shadow", "shroud", "storm",
    "suspend", "toxic", "training", "transform", "undying", "unearth"
  )
  keywords[vapply(keywords, function(x) grepl(paste0("(^|[^a-z])", gsub(" ", "[ -]", x), "([^a-z]|$)"), low, perl = TRUE), logical(1))]
}

.analysis_oracle_modifiers <- function(text) {
  low <- tolower(text)
  keywords <- .analysis_oracle_keywords(text)
  out <- if (length(keywords)) paste0("keyword:", gsub(" ", "_", keywords)) else character(0)
  if (grepl("activate only (as a sorcery|once|during)", low)) out <- c(out, "activation_restriction")
  if (grepl("choose (one|two|three)|choose one or more", low)) out <- c(out, "modal_choice")
  if (grepl("this .* enters (the battlefield )?tapped", low)) out <- c(out, "enters_tapped")
  if (grepl("can't|cannot|doesn't|don't", low)) out <- c(out, "prohibition")
  unique(out)
}

.analysis_oracle_fact <- function(kind, object, text, zone = "", qualifiers = character(0)) {
  analysis_fact(kind, object, if (nzchar(zone)) zone else .analysis_oracle_zone(text),
    .analysis_oracle_controller(text), unique(c(qualifiers, .analysis_oracle_qualifiers(text))))
}

.analysis_oracle_trigger_facts <- function(text) {
  low <- tolower(text)
  out <- list()
  add <- function(kind, object, zone = "", qualifiers = character(0)) {
    out[[length(out) + 1L]] <<- .analysis_oracle_fact(kind, object, text, zone, qualifiers)
  }
  if (grepl("\\b(cast|casts)\\b", low)) add("event", paste0(.analysis_oracle_object(low, "spell"), "_cast"), "stack")
  if (grepl("\\b(copy|copies)\\b.*\\bspell|cast or copy", low)) add("event", "spell_copied", "stack")
  if (grepl("\\b(enters|enter) (the battlefield|under)", low)) add("event", paste0(.analysis_oracle_object(low, "permanent"), "_enters"), "battlefield")
  if (grepl("\\b(dies|die)\\b|put into a graveyard from the battlefield", low)) add("event", paste0(.analysis_oracle_object(low, "creature"), "_dies"), "battlefield")
  if (grepl("\\b(attacks|attack)\\b", low)) add("event", paste0(.analysis_oracle_object(low, "creature"), "_attacks"), "battlefield")
  if (grepl("\\b(blocks|block)\\b", low)) add("event", paste0(.analysis_oracle_object(low, "creature"), "_blocks"), "battlefield")
  if (grepl("landfall|a land enters", low)) add("event", "land_enters", "battlefield")
  if (grepl("gain(s|ed)? life", low)) add("event", "life_gained")
  if (grepl("lose(s|lost)? life", low)) add("event", "life_lost")
  if (grepl("draw(s|n)? (a|one or more|[a-z0-9x]+) cards?", low)) add("event", "card_drawn")
  if (grepl("discard(s|ed)? (a|one or more|[a-z0-9x]+) cards?", low)) add("event", "card_discarded")
  if (grepl("one or more counters? (are|is) put|put(s)? .* counters? on", low)) add("event", "counter_placed")
  out
}

.analysis_oracle_effect_facts <- function(text) {
  low <- tolower(text)
  out <- list()
  add <- function(kind, object, zone = "", qualifiers = character(0)) {
    out[[length(out) + 1L]] <<- .analysis_oracle_fact(kind, object, text, zone, qualifiers)
  }
  if (grepl("\\bcreate(s|d)?\\b.*\\btoken", low)) add("object_available", .analysis_oracle_object(low, "token"), "battlefield")
  if (grepl("\\bdraw(s)?\\b.*\\bcard", low)) add("event", "card_drawn", "hand")
  if (grepl("\\bdiscard(s)?\\b.*\\bcard", low)) { add("event", "card_discarded", "graveyard"); add("object_available", "card", "graveyard") }
  if (grepl("\\bmill(s)?\\b", low)) add("object_available", "card", "graveyard")
  if (grepl("\\bgain(s)?\\b.*\\blife", low)) add("event", "life_gained")
  if (grepl("\\blose(s)?\\b.*\\blife", low)) add("event", "life_lost")
  if (grepl("\\bdeals?\\b.*\\bdamage", low)) add("event", "damage_dealt")
  if (grepl("\\badd\\b[^.]*\\{?[wubrgc]\\}?|add (one|two|three|x) mana", low)) add("resource", "mana")
  if (grepl("\\bput\\b.*\\bcounters? on|\\bproliferate\\b", low)) add("event", "counter_placed", "battlefield")
  if (grepl("\\b(copy|copies)\\b.*\\bspell", low)) add("event", "spell_copied", "stack")
  if (grepl("\\buntap\\b", low)) add("state", paste0(.analysis_oracle_object(low), "_untapped"), "battlefield")
  if (grepl("\\btap\\b", low) && !grepl("untap", low)) add("state", paste0(.analysis_oracle_object(low), "_tapped"), "battlefield")
  if (grepl("return .* from .*graveyard.* (to|onto) the battlefield|put .* from .*graveyard.*onto the battlefield", low)) add("object_available", .analysis_oracle_object(low, "permanent"), "battlefield")
  if (grepl("\\bput\\b.*\\bonto the battlefield", low)) {
    entering <- .analysis_oracle_object(low, "permanent")
    add("object_available", entering, "battlefield")
    add("event", paste0(entering, "_enters"), "battlefield")
  }
  if (grepl("return .* (to|into) (its|their|your|owner's) hand", low)) add("object_available", .analysis_oracle_object(low, "card"), "hand")
  if (grepl("\\bexile\\b", low)) add("event", paste0(.analysis_oracle_object(low), "_exiled"), "exile")
  if (grepl("\\bdestroy\\b", low)) add("event", paste0(.analysis_oracle_object(low, "permanent"), "_destroyed"), "graveyard")
  if (grepl("\\bscry\\b", low)) add("event", "scry")
  if (grepl("\\bsurveil\\b", low)) { add("event", "surveil"); add("object_available", "card", "graveyard") }
  if (grepl("\\binvestigate\\b", low)) add("object_available", "artifact_token", "battlefield", "clue")
  if (grepl("\\bproliferate\\b", low)) add("event", "counter_placed", "battlefield")
  if (grepl("search your library", low)) add("object_available", .analysis_oracle_object(low, "card"), if (grepl("onto the battlefield", low)) "battlefield" else "hand")
  if (grepl("gets? [+-][0-9x*]+/[+-][0-9x*]+|\\bhave\\b|\\bgains?\\b", low) && grepl("creature", low)) add("state", "creature_modified", "battlefield")
  for (keyword in .analysis_oracle_keywords(text)) add("capability", paste0("keyword_", gsub(" ", "_", keyword)), "battlefield")
  out
}

.analysis_oracle_cost_facts <- function(text) {
  low <- tolower(text)
  out <- list()
  add <- function(kind, object, zone = "", qualifiers = character(0)) {
    out[[length(out) + 1L]] <<- .analysis_oracle_fact(kind, object, text, zone, qualifiers)
  }
  if (grepl("\\bsacrifice\\b", low)) add("object_available", .analysis_oracle_object(low, "permanent"), "battlefield")
  if (grepl("\\bdiscard\\b", low)) add("object_available", "card", "hand")
  if (grepl("\\bexile\\b.*\\bfrom (your|a) graveyard", low)) add("object_available", .analysis_oracle_object(low, "card"), "graveyard")
  if (grepl("\\bpay\\b.*\\blife", low)) add("resource", "life")
  if (grepl("(^|, )\\{t\\}", low)) add("state", "self_untapped", "battlefield")
  if (grepl("\\{[0-9xwubrgc/]+\\}", low)) add("resource", "mana")
  if (grepl("^enchant creature", low)) add("object_available", "creature", "battlefield", "target")
  if (grepl("^equip", low)) add("object_available", "creature", "battlefield")
  out
}

.analysis_oracle_requirement_facts <- function(text) {
  low <- tolower(text)
  out <- list()
  if (grepl("\\bfrom (your|a|the) graveyard", low)) {
    out[[length(out) + 1L]] <- .analysis_oracle_fact(
      "object_available", .analysis_oracle_object(low, "card"), text, "graveyard"
    )
  }
  if (grepl("cast .* from (your|a|the) (graveyard|exile)", low)) {
    out[[length(out) + 1L]] <- .analysis_oracle_fact(
      "object_available", .analysis_oracle_object(low, "card"), text,
      if (grepl("graveyard", low)) "graveyard" else "exile"
    )
  }
  out
}

#' Parse Oracle Text into a General Intermediate Representation
#'
#' Splits Oracle text into abilities and records their trigger, cost, effect,
#' normalized facts, evidence, and parser coverage. Every input clause is either
#' represented by facts or returned explicitly as unresolved.
#'
#' @param card Card list with an id or name and `oracle_text`.
#' @return A structured Oracle analysis record.
#' @export
parse_oracle_text <- function(card) {
  card_id <- .analysis_card_id(card)
  text <- paste(unlist(card$oracle_text %||% "", use.names = FALSE), collapse = "\n")
  clauses <- .analysis_oracle_split(text)
  records <- lapply(seq_along(clauses), function(i) {
    clause <- clauses[[i]]
    low <- tolower(clause)
    activated <- grepl(":", clause, fixed = TRUE)
    triggered <- grepl("^(when|whenever|at)\\b", low)
    replacement <- grepl("\\bwould\\b.*\\binstead\\b|^if .* would", low)
    parts <- if (activated) strsplit(clause, ":", fixed = TRUE)[[1]] else clause
    cost_text <- if (activated) .analysis_oracle_trim(parts[[1]]) else ""
    body <- if (activated) .analysis_oracle_trim(paste(parts[-1], collapse = ":")) else clause
    trigger_text <- if (triggered) sub("^((when|whenever|at)\\b[^,]*),.*$", "\\1", clause, ignore.case = TRUE, perl = TRUE) else ""
    effect_text <- if (triggered && grepl(",", clause, fixed = TRUE)) sub("^[^,]*,\\s*", "", clause, perl = TRUE) else body
    requires <- c(if (triggered) .analysis_oracle_trigger_facts(trigger_text) else list(),
      .analysis_oracle_requirement_facts(effect_text))
    costs <- if (activated) .analysis_oracle_cost_facts(cost_text) else list()
    if (!activated && grepl("^(enchant creature|equip)", low)) costs <- .analysis_oracle_cost_facts(clause)
    produces <- .analysis_oracle_effect_facts(effect_text)
    if (activated && grepl("\\bsacrifice\\b", tolower(cost_text))) {
      sacrificed <- .analysis_oracle_object(cost_text, "permanent")
      if (sacrificed == "creature") produces <- c(produces, list(.analysis_oracle_fact("event", "creature_dies", cost_text, "battlefield")))
      produces <- c(produces, list(.analysis_oracle_fact("event", paste0(sacrificed, "_sacrificed"), cost_text, "battlefield")))
    }
    modifiers <- .analysis_oracle_modifiers(clause)
    semantic <- length(requires) + length(costs) + length(produces) > 0L
    recognized <- semantic || length(modifiers) > 0L
    unknown <- c(
      if (triggered && !length(.analysis_oracle_trigger_facts(trigger_text))) "trigger_not_understood",
      if (activated && nzchar(cost_text) && !length(costs)) "cost_not_understood",
      if (nzchar(effect_text) && !length(produces)) "effect_not_understood",
      if (replacement) "replacement_order_not_evaluated",
      if (grepl("\\b(if|unless|only|except|instead)\\b", low)) "restriction_not_evaluated",
      if (length(.analysis_oracle_keywords(clause))) "keyword_execution_not_evaluated"
    )
    list(
      id = paste0(card_id, ":oracle-", i),
      kind = if (activated) "activated" else if (triggered) "triggered" else if (replacement) "replacement" else "static_or_spell",
      text = clause, trigger = trigger_text, cost = cost_text, effect = effect_text,
      requires = requires, costs = costs, produces = produces,
      modifiers = modifiers,
      unknown_conditions = unknown,
      semantic_status = if (semantic) "facts" else if (recognized) "syntax_only" else "unresolved",
      status = if (recognized) "parsed" else "unresolved"
    )
  })
  parsed <- if (length(records)) sum(vapply(records, function(x) x$status == "parsed", logical(1))) else 0L
  semantic <- if (length(records)) sum(vapply(records, function(x) x$semantic_status == "facts", logical(1))) else 0L
  list(
    card_id = card_id, clauses = records,
    coverage = list(total = length(records), parsed = parsed, semantic = semantic,
      syntax_only = parsed - semantic, unresolved = length(records) - parsed,
      ratio = if (length(records)) parsed / length(records) else 1,
      semantic_ratio = if (length(records)) semantic / length(records) else 1),
    unresolved_text = vapply(Filter(function(x) x$status == "unresolved", records), `[[`, character(1), "text"),
    parser_version = "oracle-ir-0.2.0"
  )
}

#' Audit Oracle Parser Coverage
#'
#' Applies [parse_oracle_text()] to a card catalogue and reports clause-level
#' coverage plus the exact unresolved wording that should drive grammar work.
#'
#' @param cards A list of card lists or a data frame with `name`, `oracle_text`,
#'   and optionally `id` or `scryfall_id`.
#' @return Coverage summary and unresolved clauses.
#' @export
audit_oracle_coverage <- function(cards) {
  if (is.data.frame(cards)) {
    cards <- lapply(seq_len(nrow(cards)), function(i) as.list(cards[i, , drop = FALSE]))
  }
  if (!is.list(cards)) stop("cards must be a list or data frame", call. = FALSE)
  parsed <- lapply(cards, parse_oracle_text)
  total <- sum(vapply(parsed, function(x) x$coverage$total, integer(1)))
  recognized <- sum(vapply(parsed, function(x) x$coverage$parsed, integer(1)))
  semantic <- sum(vapply(parsed, function(x) x$coverage$semantic, integer(1)))
  unresolved <- unlist(lapply(parsed, `[[`, "unresolved_text"), use.names = FALSE)
  list(
    cards = length(parsed), clauses = total, parsed_clauses = recognized,
    semantic_clauses = semantic, syntax_only_clauses = recognized - semantic,
    unresolved_clauses = total - recognized,
    coverage_ratio = if (total) recognized / total else 1,
    semantic_coverage_ratio = if (total) semantic / total else 1,
    cards_with_unresolved = sum(vapply(parsed, function(x) x$coverage$unresolved > 0L, logical(1))),
    unresolved_text = unresolved,
    parser_version = "oracle-ir-0.2.0"
  )
}
