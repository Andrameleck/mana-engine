# Helpers shared by snapshot tests for the synergy engine.
#
# These tests lock the current behaviour of:
#   * mtgcodex.api:::query_synergy_normalize_card()
#   * mtgcodex.api:::query_synergy_score_pair()
#
# Fixtures live in tests/testthat/fixtures/synergy_reference_cards.json
# and contain ONLY raw Scryfall fields, so snapshots remain meaningful.

# Load the reference card fixtures (raw Scryfall fields).
load_reference_cards <- function() {
  path <- testthat::test_path("fixtures", "synergy_reference_cards.json")
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}

# Project a normalized card to a stable, snapshot-friendly summary.
# We deliberately drop noisy fields (verbose abilities records) and
# sort vectors so reorderings inside the engine do not break snapshots.
summarize_normalized <- function(norm) {
  sortc <- function(x) {
    if (is.null(x) || !length(x)) return(character(0))
    sort(unique(as.character(x)))
  }
  list(
    name             = as.character(norm$name %||% ""),
    type_line        = as.character(norm$type_line %||% ""),
    mana_value       = as.numeric(norm$mana_value %||% NA_real_),
    colors           = sortc(norm$colors),
    color_identity   = sortc(norm$color_identity),
    keywords         = sortc(norm$keywords),
    mechanics        = sortc(norm$mechanics),
    roles            = sortc(norm$roles),
    target_roles     = sortc(norm$target_roles),
    strategy_tags    = sortc(norm$strategy_tags),
    produced_events  = sortc(norm$produced_events),
    consumed_events  = sortc(norm$consumed_events),
    replaced_events  = sortc(norm$replaced_events),
    prevented_events = sortc(norm$prevented_events),
    setup_events     = sortc(norm$setup_events),
    finisher_events  = sortc(norm$finisher_events),
    anti_tags        = sortc(norm$anti_tags),
    cadence_class    = as.character(norm$cadence$class %||% "")
  )
}

# Project a pair-score result to a stable summary.
summarize_pair_score <- function(pair) {
  pick_num <- function(name, default = NA_real_) {
    v <- pair[[name]]
    if (is.null(v) || !length(v)) return(default)
    round(as.numeric(v[[1]]), 4)
  }
  pick_chr <- function(name) {
    v <- pair[[name]]
    if (is.null(v) || !length(v)) return(character(0))
    sort(unique(as.character(unlist(v))))
  }
  list(
    score                       = pick_num("score"),
    direct_event_score          = pick_num("direct_event_score"),
    reciprocal_value_score      = pick_num("reciprocal_value_score"),
    role_match                  = pick_num("role_match"),
    package_potential           = pick_num("package_potential"),
    anti_synergy_score          = pick_num("anti_synergy_score"),
    produced_to_payoff          = pick_chr("produced_to_payoff"),
    payoff_to_produced          = pick_chr("payoff_to_produced"),
    setup_finisher              = pick_chr("setup_finisher"),
    replacement_conflicts       = pick_chr("replacement_conflicts"),
    prevention_conflicts        = pick_chr("prevention_conflicts")
  )
}

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1L && is.na(a))) b else a
