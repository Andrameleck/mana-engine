# Matchup analyzer.
#
# Given a generated deck (commander + mainboard with normalized cards), this
# module estimates how the deck performs against each known opposing archetype
# from `query_synergy_archetype_registry()`.
#
# The score combines two signals:
#
#   1. Base matchup matrix: a hand-tuned table reflecting the well-known meta
#      relationships between archetype families (aggro beats slow control,
#      combo loses to discard/counter, graveyard loses to graveyard hate, etc.).
#      The deck's own dominant archetypes (top-fit) drive the rows of this
#      matrix.
#
#   2. Tool adjustments: signals derived from what the mainboard actually
#      contains. A deck holding many board wipes is stronger vs aggro/tokens;
#      a deck with lots of counterspells is stronger vs combo; a deck with
#      graveyard exile is stronger vs graveyard / reanimator; and so on.
#
# The output is a per-archetype score in [-100, 100] (negative = bad matchup),
# along with the top-N strong matchups and bottom-N weak matchups, plus the
# tool signals that drove the adjustment (for explainability).

# Base matchup matrix: `our_arch -> their_arch -> integer in [-3, +3]`.
# Positive = we beat them; negative = they beat us; 0 = even.
# Only entries that meaningfully differ from neutral are listed; missing
# entries default to 0.
.matchup_base <- function() {
  list(
    aggro = list(
      aggro = 0L, midrange = -1L, control = +2L, combo = +1L,
      ramp = +2L, stax = -1L, lifegain = -2L, tokens = 0L,
      aristocrats = -1L, voltron = +1L, extra_turns = +2L
    ),
    midrange = list(
      aggro = +1L, midrange = 0L, control = -1L, combo = -1L,
      ramp = 0L, lifegain = +1L, tokens = +1L, aristocrats = 0L,
      graveyard = +1L, stax = -1L
    ),
    control = list(
      aggro = -2L, midrange = +1L, control = 0L, combo = +2L,
      ramp = +1L, spellslinger = +1L, extra_turns = +2L,
      tokens = -1L, aristocrats = -1L, lifegain = +1L
    ),
    combo = list(
      aggro = -1L, midrange = +1L, control = -2L, combo = 0L,
      stax = -2L, discard = -2L, ramp = +1L, lifegain = 0L
    ),
    ramp = list(
      aggro = -2L, midrange = 0L, control = +1L, combo = 0L,
      ramp = 0L, stax = -2L, tokens = -1L, voltron = +1L,
      extra_turns = +1L
    ),
    aristocrats = list(
      aggro = +2L, midrange = +1L, control = -1L, combo = -1L,
      tokens = +1L, voltron = +1L, lifegain = +1L, stax = -1L,
      graveyard = 0L, blink = -1L
    ),
    graveyard = list(
      aggro = 0L, midrange = +1L, control = +1L, combo = 0L,
      stax = -2L, aristocrats = +1L, lifegain = 0L,
      enchantments = -1L, artifacts = 0L
    ),
    tokens = list(
      aggro = +1L, midrange = -1L, control = -2L, combo = -1L,
      tokens = 0L, voltron = +2L, lifegain = +1L, stax = -2L,
      aristocrats = +1L
    ),
    voltron = list(
      aggro = -1L, midrange = -1L, control = -2L, combo = -1L,
      tokens = -2L, voltron = 0L, ramp = +1L, lifegain = +1L
    ),
    lifegain = list(
      aggro = +2L, midrange = +1L, control = 0L, combo = -1L,
      ramp = 0L, tokens = +1L, voltron = +1L, stax = -1L
    ),
    spellslinger = list(
      aggro = -1L, midrange = +1L, control = -1L, combo = +1L,
      spellslinger = 0L, stax = -2L, tokens = -1L,
      extra_turns = +1L
    ),
    blink = list(
      aggro = +1L, midrange = +1L, control = -1L, combo = -1L,
      stax = -2L, aristocrats = +1L, lifegain = +1L
    ),
    counters = list(
      aggro = 0L, midrange = +1L, control = -1L, combo = -1L,
      tokens = +1L, voltron = +1L
    ),
    poison = list(
      aggro = +1L, midrange = 0L, control = -1L, combo = -2L,
      lifegain = -1L, stax = -2L
    ),
    artifacts = list(
      aggro = -1L, midrange = +1L, control = 0L, combo = +1L,
      stax = -2L, ramp = +1L
    ),
    enchantments = list(
      aggro = -1L, midrange = +1L, control = +1L, combo = 0L,
      stax = +1L, graveyard = +1L
    ),
    lands = list(
      aggro = -2L, midrange = 0L, control = +1L, combo = -1L,
      ramp = +1L, stax = -1L
    ),
    tribal = list(
      aggro = +1L, midrange = 0L, control = -1L, combo = -1L,
      tokens = +1L
    ),
    stax = list(
      aggro = +1L, midrange = +1L, control = +2L, combo = +2L,
      ramp = +2L, spellslinger = +2L, graveyard = +2L,
      stax = 0L, aggro = 0L
    ),
    extra_turns = list(
      aggro = -2L, midrange = -1L, control = -2L, combo = 0L,
      stax = -2L, ramp = +1L
    ),
    wheels = list(
      aggro = -1L, midrange = +1L, control = 0L, combo = -1L,
      lifegain = -1L, stax = -2L
    ),
    discard = list(
      aggro = -1L, midrange = +1L, control = -1L, combo = +2L,
      combo = +2L, ramp = +1L, stax = -1L
    ),
    mill = list(
      aggro = -2L, midrange = 0L, control = -1L, combo = 0L,
      graveyard = -2L, ramp = +1L, lifegain = -1L
    ),
    tutors = list(
      combo = +1L, control = +1L, midrange = +1L, ramp = +1L
    )
  )
}

# Tool signals we extract from the actual mainboard. Each signal:
#   - is detected by an indicator function (via produced events or strategy tags)
#   - bumps or drops scores against specific opposing archetypes
.matchup_tool_rules <- function() {
  list(
    list(
      key = "removal",
      detect = function(card) {
        ev <- query_synergy_to_vector(card$produced_events)
        any(c("DESTROY_CREATURE", "EXILE_CREATURE", "DESTROY_PERMANENT",
              "EXILE_PERMANENT", "DAMAGE_CREATURE") %in% ev)
      },
      adjustments = c(aggro = +1, tokens = +1, voltron = +2,
                      aristocrats = +1, blink = +1)
    ),
    list(
      key = "board_wipe",
      detect = function(card) {
        ev <- query_synergy_to_vector(card$produced_events)
        any(c("BOARD_WIPE", "DESTROY_ALL_CREATURES",
              "EXILE_ALL_CREATURES") %in% ev)
      },
      adjustments = c(aggro = +2, tokens = +3, aristocrats = +2,
                      voltron = +1, tribal = +2, blink = +1, counters = +1)
    ),
    list(
      key = "lifegain",
      detect = function(card) {
        ev <- query_synergy_to_vector(card$produced_events)
        tg <- query_synergy_to_vector(card$strategy_tags)
        ("GAIN_LIFE" %in% ev) ||
          any(c("lifelink", "lifegain_payoff") %in% tg)
      },
      adjustments = c(aggro = +2, voltron = +1, tokens = +1,
                      poison = -1, lifegain = +1)
    ),
    list(
      key = "counterspell",
      detect = function(card) {
        ev <- query_synergy_to_vector(card$produced_events)
        any(c("COUNTER_SPELL", "COUNTER_ABILITY") %in% ev)
      },
      adjustments = c(combo = +3, spellslinger = +2, control = +1,
                      ramp = +1, extra_turns = +2, tutors = +2)
    ),
    list(
      key = "discard_attack",
      detect = function(card) {
        ev <- query_synergy_to_vector(card$produced_events)
        ("OPPONENT_DISCARDS" %in% ev) ||
          ("TARGETED_DISCARD" %in% ev)
      },
      adjustments = c(combo = +2, control = +1, ramp = +1,
                      tutors = +2, extra_turns = +1)
    ),
    list(
      key = "graveyard_hate",
      detect = function(card) {
        ev <- query_synergy_to_vector(card$produced_events)
        tg <- query_synergy_to_vector(card$strategy_tags)
        ("EXILE_FROM_GRAVEYARD" %in% ev) ||
          ("graveyard_hate" %in% tg)
      },
      adjustments = c(graveyard = +3, aristocrats = +1, mill = +1)
    ),
    list(
      key = "artifact_hate",
      detect = function(card) {
        ev <- query_synergy_to_vector(card$produced_events)
        any(c("DESTROY_ARTIFACT", "EXILE_ARTIFACT") %in% ev)
      },
      adjustments = c(artifacts = +2, ramp = +1, stax = +1)
    ),
    list(
      key = "enchantment_hate",
      detect = function(card) {
        ev <- query_synergy_to_vector(card$produced_events)
        any(c("DESTROY_ENCHANTMENT", "EXILE_ENCHANTMENT") %in% ev)
      },
      adjustments = c(enchantments = +2, voltron = +1, stax = +1)
    ),
    list(
      key = "tutor_density",
      detect = function(card) {
        ev <- query_synergy_to_vector(card$produced_events)
        tg <- query_synergy_to_vector(card$strategy_tags)
        ("TUTOR" %in% ev) || ("tutor" %in% tg)
      },
      adjustments = c(combo = +1, control = +1)
    ),
    list(
      key = "ramp_density",
      detect = function(card) {
        ev <- query_synergy_to_vector(card$produced_events)
        tg <- query_synergy_to_vector(card$strategy_tags)
        any(c("MANA_ROCK_ETB", "TREASURE_TOKEN") %in% ev) ||
          any(c("ramp", "mana_rock", "treasure_producer") %in% tg)
      },
      adjustments = c(control = +1, stax = +1, aggro = -1)
    )
  )
}

# Caps a tool's contribution per archetype: many copies of the same tool helps
# but we don't want 8 board wipes to dominate the entire matchup score.
.matchup_tool_cap <- function(count) {
  # Saturating curve: 1 copy = 1.0, 3 copies = 1.6, 6 copies = 2.0
  if (count <= 0L) return(0)
  min(2.5, 1 + log(count, base = 3))
}

# Detect which archetypes our deck plays (top-fit on commander + core/all).
# `user_archetypes` is the user-provided archetype filter; if non-empty it is
# treated as ground truth and added as a strong signal so a user asking for an
# "aristocrats" deck always reports aristocrats as a self-archetype.
.matchup_self_archetypes <- function(commander_norm, mainboard_norms,
                                     user_archetypes = character(0),
                                     min_fit = 0.10, top_n = 3L) {
  # Aggregate fit across commander and the top-scored cards of the deck. We
  # weight the commander 3x because it dictates the plan in Commander.
  bag <- c(list(commander_norm), mainboard_norms)
  weights <- c(3, rep(1, length(mainboard_norms)))
  totals <- list()
  for (i in seq_along(bag)) {
    fits <- tryCatch(
      query_synergy_archetypes_for_card(bag[[i]], min_fit = 0),
      error = function(e) list()
    )
    for (k in names(fits)) {
      v <- suppressWarnings(as.numeric(fits[[k]]))
      if (!is.finite(v) || v <= 0) next
      totals[[k]] <- (totals[[k]] %||% 0) + v * weights[[i]]
    }
  }
  if (length(totals) == 0L && length(user_archetypes) == 0L) {
    return(character(0))
  }
  if (length(totals) == 0L) {
    return(utils::head(user_archetypes, top_n))
  }
  sorted <- sort(unlist(totals), decreasing = TRUE)
  rel <- sorted / sorted[[1]]
  detected <- names(rel)[rel >= min_fit]
  # User-supplied archetypes go first (ground truth), then detected ones.
  combined <- unique(c(user_archetypes, detected))
  utils::head(combined, top_n)
}

# Main entry: return matchup analysis for a built deck.
#
# `commander_normalized` is the seed's normalized record.
# `mainboard_records` is a list of records each with a `$normalized` slot
# (as built by `.deck_build_mainboard`); basic land fillers are skipped.
#
# Returns: list(
#   self_archetypes  = c("aristocrats", "graveyard", ...),
#   strong_against   = list(list(archetype, label, score, reasons), ...),
#   weak_against     = list(list(archetype, label, score, reasons), ...),
#   matchup_table    = list(arch -> list(score, base, tool_bonus, signals))
# )
query_synergy_deck_matchups <- function(commander_normalized,
                                        mainboard_records,
                                        user_archetypes = character(0),
                                        top_n = 4L,
                                        strong_threshold = 8L,
                                        weak_threshold = -8L) {
  registry <- query_synergy_archetype_registry()
  base <- .matchup_base()
  rules <- .matchup_tool_rules()

  # Skip basic land fillers (no normalization).
  real_records <- Filter(function(r) {
    !isTRUE(r$is_basic_filler) && !is.null(r$normalized)
  }, mainboard_records)
  norms <- lapply(real_records, function(r) r$normalized)

  user_archetypes <- intersect(user_archetypes, names(registry))
  self_arch <- .matchup_self_archetypes(commander_normalized, norms,
                                        user_archetypes = user_archetypes,
                                        min_fit = 0.10, top_n = 3L)

  # Initialise scores for every registered archetype.
  arch_keys <- names(registry)
  scores <- setNames(rep(0, length(arch_keys)), arch_keys)
  base_part <- setNames(rep(0, length(arch_keys)), arch_keys)
  tool_part <- setNames(rep(0, length(arch_keys)), arch_keys)
  signals_per_arch <- setNames(vector("list", length(arch_keys)), arch_keys)

  # Base contribution: each opposing archetype receives the sum across our
  # detected own-archetypes of base[ours][theirs], weighted by self-arch rank.
  if (length(self_arch) > 0L) {
    self_w <- (length(self_arch):1L) / sum(seq_along(self_arch))
    for (i in seq_along(self_arch)) {
      ours <- self_arch[[i]]
      row <- base[[ours]]
      if (is.null(row)) next
      for (theirs in names(row)) {
        if (!(theirs %in% arch_keys)) next
        contrib <- as.numeric(row[[theirs]]) * self_w[[i]]
        base_part[[theirs]] <- base_part[[theirs]] + contrib
      }
    }
  }

  # Tool contribution: detect tools, accumulate count per tool, then map to
  # archetype adjustments using the saturating cap.
  tool_counts <- setNames(integer(length(rules)),
                          vapply(rules, function(r) r$key, character(1)))
  for (rec in real_records) {
    for (r_i in seq_along(rules)) {
      r <- rules[[r_i]]
      if (isTRUE(r$detect(rec$normalized))) {
        tool_counts[[r$key]] <- tool_counts[[r$key]] + 1L
      }
    }
  }
  for (r in rules) {
    n <- as.integer(tool_counts[[r$key]])
    if (n <= 0L) next
    factor <- .matchup_tool_cap(n)
    for (theirs in names(r$adjustments)) {
      if (!(theirs %in% arch_keys)) next
      delta <- as.numeric(r$adjustments[[theirs]]) * factor
      tool_part[[theirs]] <- tool_part[[theirs]] + delta
      sig <- signals_per_arch[[theirs]] %||% list()
      sig[[length(sig) + 1L]] <- list(
        tool = r$key, count = n, delta = round(delta, 1)
      )
      signals_per_arch[[theirs]] <- sig
    }
  }

  # Scale base × 12 and tool × 6 → roughly [-100, 100] per archetype.
  for (k in arch_keys) {
    sc <- base_part[[k]] * 12 + tool_part[[k]] * 6
    scores[[k]] <- max(-100, min(100, round(sc)))
  }

  # Skip our own archetypes from the strong/weak lists (a deck shouldn't
  # claim it beats its own kind by default; mirror matches are uncertain).
  ranked_keys <- setdiff(arch_keys, self_arch)
  ranked_desc <- sort(scores[ranked_keys], decreasing = TRUE)
  ranked_asc <- sort(scores[ranked_keys], decreasing = FALSE)

  # Only surface a matchup as STRONG if its score crosses the strong threshold,
  # and as WEAK only if it crosses the weak threshold. This avoids reporting
  # "weak vs Aggro" when the actual score is +20.
  strong <- ranked_desc[ranked_desc >= strong_threshold]
  strong <- utils::head(strong, top_n)
  weak <- ranked_asc[ranked_asc <= weak_threshold]
  weak <- utils::head(weak, top_n)

  pack <- function(named_vec) {
    if (length(named_vec) == 0L) return(list())
    lapply(names(named_vec), function(k) {
      reg <- registry[[k]]
      list(
        archetype = k,
        label = reg$label %||% k,
        score = as.integer(named_vec[[k]]),
        signals = signals_per_arch[[k]] %||% list()
      )
    })
  }

  list(
    self_archetypes = self_arch,
    self_archetype_labels = vapply(self_arch, function(k) {
      registry[[k]]$label %||% k
    }, character(1)),
    strong_against = pack(strong),
    weak_against = pack(weak),
    tool_counts = as.list(tool_counts)
  )
}
