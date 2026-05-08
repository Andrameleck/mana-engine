# Central registry of all scoring weights, bonuses, penalties and thresholds.
#
# AGENTS.md mandates explainability and tunability. Concentrating every magic
# number here serves three purposes:
#   1. Audit trail: a single file lists every constant that influences the
#      final score, with comments documenting intent.
#   2. Tunability: a future endpoint can override these for A/B testing.
#   3. Regression safety: `tests/testthat/test-score-intentions.R` snapshots
#      these to detect accidental drift.
#
# All consumers read via `query_synergy_weights()`. Do NOT inline magic numbers
# in scoring functions; if a new tunable appears, add it here first.

query_synergy_weights <- function() {
  list(
    # ----- Pair scoring (R/synergy_score_pair.R) ---------------------------
    # Positive axes (sum ~1.16, then clamped to [0,1] before scaling to 100).
    pair = list(
      direct_event           = 0.24,  # candidate produces -> seed consumes
      indirect_engine        = 0.13,  # bridged engine support
      reciprocal_value       = 0.15,  # seed produces -> candidate consumes
      bridge_resource_zone   = 0.13,  # zone transitions, resource bridges
      package_potential      = 0.07,  # setup/finisher alignment
      shared_plan            = 0.03,  # strategic tag overlap
      cadence                = 0.07,  # repeatable cadence weighting
      role_complementarity   = 0.09,  # role pair fit
      reliability            = 0.11,  # practical gameplay frequency
      color_fit              = 0.03,  # color/CI compatibility
      format_fit             = 0.02,  # format legality compatibility
      tempo_fit              = 0.02   # mana curve alignment
    ),
    # Pair bonuses (additive, capped).
    pair_bonus = list(
      enabler_payoff_cap     = 0.30,
      setup_converter_cap    = 0.18
    ),
    # Pair penalties (subtracted from positive sum).
    pair_penalty = list(
      anti_synergy           = 0.28,
      incoherence            = 0.12,
      tempo_mismatch         = 0.08,
      weak_bridge            = 0.16,
      shell_dependency       = 0.10
    ),
    # Cadence class -> bonus added to cadence_score before weighting.
    cadence_bonus = list(
      scalable_repeatable    = 0.12,
      reliable_repeatable    = 0.08,
      conditional_repeatable = 0.03,
      repeatable_scalable    = 0.10,
      repeatable             = 0.07,
      one_shot               = 0
    ),

    # ----- Group scoring (R/synergy_groups.R) ------------------------------
    group = list(
      chain_continuity          = 0.20,
      role_coverage             = 0.12,
      strategic_coherence       = 0.08,
      resource_flow_quality     = 0.13,
      causal_line_quality       = 0.11,
      setup_converter_alignment = 0.09,
      repetition_potential      = 0.10,
      amplification_bonus       = 0.07,
      finisher_quality          = 0.11
    ),
    group_penalty = list(
      anti_synergy              = 0.12,
      value_cluster             = 0.08,
      shell_dependency          = 0.08,
      redundancy                = 0.07,
      complexity                = 0.07
    ),
    # Hard filters that drop a group entirely.
    group_threshold = list(
      min_score_norm        = 0.14,
      min_chain_continuity  = 0.16,
      min_edge_score        = 28L,
      min_continuity_score  = 0.34
    ),

    # ----- Score modifiers applied AFTER group scoring ---------------------
    # Spellbook combo bonuses (added to total_score, recorded in score_modifiers).
    spellbook_bonus = list(
      exact    = 15L,  # group cards == combo cards
      contains = 10L,  # group strictly contains the combo
      partial  =  4L   # >=2 shared cards from a >=3-piece combo
    ),
    # Archetype rerank: additive boost (NOT multiplicative). A group that
    # strongly matches the user-selected archetype gets up to +archetype_boost
    # points; an unmatched group is unchanged. This avoids decimating
    # specialist groups that simply weren't tagged with the requested archetype.
    archetype = list(
      max_boost              = 12L,   # additive points at alignment=1
      strict_min_alignment   = 0.05   # below this, strict mode drops the group
    ),

    # ----- Diversification (R/synergy_buckets.R) ---------------------------
    diversification = list(
      duplicate_penalty = 0.08         # subtracted per duplicate profile
    )
  )
}

# Convenience accessors used in hot paths to avoid repeated list lookups.
query_synergy_pair_weights        <- function() query_synergy_weights()$pair
query_synergy_pair_penalties      <- function() query_synergy_weights()$pair_penalty
query_synergy_pair_bonuses        <- function() query_synergy_weights()$pair_bonus
query_synergy_cadence_bonus_table <- function() query_synergy_weights()$cadence_bonus
query_synergy_group_weights       <- function() query_synergy_weights()$group
query_synergy_group_penalties     <- function() query_synergy_weights()$group_penalty
query_synergy_group_thresholds    <- function() query_synergy_weights()$group_threshold
query_synergy_spellbook_bonus_tbl <- function() query_synergy_weights()$spellbook_bonus
query_synergy_archetype_tuning    <- function() query_synergy_weights()$archetype
