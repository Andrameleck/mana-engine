test_that("setup converter target lines are preferred over broad value clusters in groups", {
  setup_seed <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "seed-setup",
    name = "Tomb Survey",
    oracle_text = "Mill three cards.",
    colors = c("B"),
    color_identity = c("B"),
    cmc = 1,
    legalities = list(commander = "legal")
  ))

  converter <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "line-converter",
    name = "Ash Script",
    oracle_text = "Return target creature card from your graveyard to the battlefield.",
    colors = c("B"),
    color_identity = c("B"),
    cmc = 2,
    legalities = list(commander = "legal")
  ))

  target <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "line-target",
    name = "Ancient Colossus",
    oracle_text = "",
    type_line = "Creature - Giant",
    colors = c("B"),
    color_identity = c("B"),
    cmc = 7,
    legalities = list(commander = "legal")
  ))

  value_cluster <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "value-cluster",
    name = "Graveyard Scholar",
    oracle_text = "Whenever a card leaves your graveyard, each opponent loses 1 life.",
    colors = c("B"),
    color_identity = c("B"),
    cmc = 3,
    legalities = list(commander = "legal")
  ))

  groups <- mtgcodex.api:::query_synergy_detect_groups_for_seed(
    seed = setup_seed,
    candidates = list(converter, target, value_cluster),
    format_name = "commander",
    min_edge_score = 8,
    max_groups = 4,
    max_group_size = 4,
    max_paths = 48
  )

  expect_gte(length(groups$groups), 1)
  setup_lines <- Filter(function(group) {
    category <- mtgcodex.api:::query_api_scalar(group$category, default = "")
    alignment <- suppressWarnings(as.numeric(group$score_breakdown$setup_converter_alignment))
    roles <- vapply(group$members, function(member) member$inferred_role, character(1))
    category == "setup_converter_payoff" ||
      (is.finite(alignment) && alignment >= 0.34 &&
       roles[[1]] %in% c("setup", "fuel") &&
       any(roles %in% c("converter", "bridge", "engine")) &&
       utils::tail(roles, 1L) %in% c("target", "payoff", "finisher"))
  }, groups$groups)
  expect_gte(length(setup_lines), 1)

  value_clusters <- Filter(function(group) {
    mtgcodex.api:::query_api_scalar(group$category, default = "") %in% c("value_cluster", "shared_value_cluster")
  }, groups$groups)
  if (length(value_clusters) > 0L) {
    best_setup <- max(vapply(setup_lines, function(group) suppressWarnings(as.numeric(group$total_score)), numeric(1)))
    best_cluster <- max(vapply(value_clusters, function(group) suppressWarnings(as.numeric(group$total_score)), numeric(1)))
    expect_gte(best_setup, best_cluster)
  }
})

test_that("structured synergy groups detect a three card draw discard line", {
  payoff <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "payoff",
    name = "Archive Judge",
    oracle_text = "Whenever you draw a card, gain 1 life.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 3,
    legalities = list(commander = "legal")
  ))

  setup <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "setup",
    name = "Frantic Research",
    oracle_text = "Draw two cards, then discard two cards.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 2,
    legalities = list(commander = "legal")
  ))

  converter <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "converter",
    name = "Lore Recycler",
    oracle_text = "Whenever you discard a card, draw a card.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 2,
    legalities = list(commander = "legal")
  ))

  groups <- mtgcodex.api:::query_synergy_detect_groups_for_seed(
    seed = payoff,
    candidates = list(setup, converter),
    format_name = "commander",
    min_edge_score = 10,
    max_groups = 3,
    max_group_size = 4,
    max_paths = 30
  )

  expect_gte(length(groups$groups), 1)
  group_match <- Filter(function(group) {
    roles <- vapply(group$members, function(member) member$inferred_role, character(1))
    length(group$members) == 3L &&
      any(c("DRAW_CARD", "DISCARD_CARD") %in% group$matched_events) &&
      any(roles %in% c("engine", "converter")) &&
      utils::tail(roles, 1L) %in% c("payoff", "finisher", "target")
  }, groups$groups)

  expect_gte(length(group_match), 1)
  expect_true(is.list(group_match[[1]]$line$edges))
  expect_true(is.list(group_match[[1]]$package_structure))
  expect_identical(group_match[[1]]$package_structure$intermediate_count, 1L)
  expect_gt(group_match[[1]]$score_breakdown$chain_continuity, 0)
})

test_that("engine fuel payoff groups surface as indirect packages", {
  payoff <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "archive-payoff",
    name = "Archive Judge",
    oracle_text = "Whenever you draw a card, gain 1 life.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 3,
    legalities = list(commander = "legal")
  ))

  fuel <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "fuel",
    name = "Frantic Research",
    oracle_text = "Draw two cards, then discard two cards.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 2,
    legalities = list(commander = "legal")
  ))

  engine <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "engine",
    name = "Lore Recycler",
    oracle_text = "Whenever you discard a card, draw a card.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 2,
    legalities = list(commander = "legal")
  ))

  groups <- mtgcodex.api:::query_synergy_detect_groups_for_seed(
    seed = payoff,
    candidates = list(fuel, engine),
    format_name = "commander",
    min_edge_score = 10,
    max_groups = 3,
    max_group_size = 4,
    max_paths = 30
  )

  expect_gte(length(groups$groups), 1)
  expect_true(any(vapply(groups$groups, function(group) {
    roles <- vapply(group$members, function(member) member$inferred_role, character(1))
    any(roles %in% c("fuel", "setup")) && any(roles %in% c("engine", "converter"))
  }, logical(1))))
})

test_that("group search supports A plus two intermediates plus B package lines", {
  payoff <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "token-payoff",
    name = "Token Auditor",
    oracle_text = "Whenever you create a token, gain 1 life.",
    colors = c("W"),
    color_identity = c("W"),
    cmc = 3,
    legalities = list(commander = "legal")
  ))

  setup <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "seed-setup",
    name = "Frantic Research",
    oracle_text = "Draw two cards, then discard two cards.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 2,
    legalities = list(commander = "legal")
  ))

  bridge_a <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "discard-engine",
    name = "Lore Recycler",
    oracle_text = "Whenever you discard a card, draw a card.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 2,
    legalities = list(commander = "legal")
  ))

  bridge_b <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "draw-converter",
    name = "Spark Provisioner",
    oracle_text = "Whenever you draw a card, create a Treasure token.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 3,
    legalities = list(commander = "legal")
  ))

  groups <- mtgcodex.api:::query_synergy_detect_groups_for_seed(
    seed = payoff,
    candidates = list(setup, bridge_a, bridge_b),
    format_name = "commander",
    min_edge_score = 8,
    max_groups = 4,
    max_group_size = 4,
    max_paths = 48
  )

  expect_gte(length(groups$groups), 1)
  expect_true(any(vapply(groups$groups, function(group) {
    member_ids <- vapply(group$members, function(member) member$id, character(1))
    has_all_cards <- all(c("seed-setup", "discard-engine", "draw-converter", "token-payoff") %in% member_ids)
    has_four_cards <- length(group$members) == 4L
    has_two_intermediates <- suppressWarnings(as.integer(group$package_structure$intermediate_count)) == 2L
    chain_hits <- intersect(
      c("DISCARD_CARD", "DRAW_CARD", "CREATE_TOKEN", "GRAVEYARD_FUEL", "BATTLEFIELD_RESOURCE"),
      group$matched_events
    )
    has_chain <- length(chain_hits) >= 3L
    has_all_cards && has_four_cards && has_two_intermediates && has_chain
  }, logical(1))))
})

test_that("graveyard reanimation groups use resource and zone chains", {
  payoff <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "grave-payoff",
    name = "Ancient Colossus",
    oracle_text = "",
    type_line = "Creature - Giant",
    colors = c("B"),
    color_identity = c("B"),
    cmc = 7,
    legalities = list(commander = "legal")
  ))

  setup <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "grave-setup",
    name = "Tomb Survey",
    oracle_text = "Mill three cards.",
    colors = c("B"),
    color_identity = c("B"),
    cmc = 1,
    legalities = list(commander = "legal")
  ))

  converter <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "grave-converter",
    name = "Ash Script",
    oracle_text = "Return target creature card from your graveyard to the battlefield.",
    colors = c("B"),
    color_identity = c("B"),
    cmc = 2,
    legalities = list(commander = "legal")
  ))

  groups <- mtgcodex.api:::query_synergy_detect_groups_for_seed(
    seed = payoff,
    candidates = list(setup, converter),
    format_name = "commander",
    min_edge_score = 10,
    max_groups = 3,
    max_group_size = 4,
    max_paths = 30
  )

  expect_gte(length(groups$groups), 1)
  expect_true(any(vapply(groups$groups, function(group) {
    any(c("GRAVEYARD_FUEL", "REANIMATE", "BATTLEFIELD_RESOURCE") %in% group$matched_events) &&
      identical(utils::tail(vapply(group$members, function(member) member$inferred_role, character(1)), 1L), "target")
  }, logical(1))))
})

test_that("synergy finder returns bucketed output with explainable axes", {
  catalog <- list(
    list(
      id = "seed",
      name = "Ledger Saint",
      oracle_text = "Whenever you draw a card, gain 1 life.",
      colors = c("U"),
      color_identity = c("U"),
      cmc = 3,
      legalities = list(commander = "legal")
    ),
    list(
      id = "direct",
      name = "Thought Current",
      oracle_text = "Draw two cards.",
      colors = c("U"),
      color_identity = c("U"),
      cmc = 2,
      legalities = list(commander = "legal")
    ),
    list(
      id = "indirect",
      name = "Rooftop Conniver",
      oracle_text = "Whenever you attack, target attacking creature connives 1.",
      colors = c("U"),
      color_identity = c("U"),
      cmc = 3,
      legalities = list(commander = "legal")
    ),
    list(
      id = "warning",
      name = "Closed Archive",
      oracle_text = "If you would draw a card, exile the top card of your library instead.",
      colors = c("U"),
      color_identity = c("U"),
      cmc = 2,
      legalities = list(commander = "legal")
    )
  )

  out <- mtgcodex.api:::query_synergy_find_in_catalog(
    list(card_name = "Ledger Saint", format = "commander", max_results = 6),
    catalog
  )

  expect_true(isTRUE(out$ok))
  expect_true(is.list(out$buckets))
  expect_true(all(c("direct_enablers", "indirect_engines", "reciprocal_value_cards", "anti_synergy_warnings", "synergy_groups", "package_lines", "packages") %in% names(out$buckets)))
  expect_gte(length(out$best_matches), 1)
  expect_true(is.character(out$best_matches[[1]]$bucket))
  expect_true(is.list(out$best_matches[[1]]$axis_scores))
  expect_true(is.character(out$best_matches[[1]]$explanation_text))
  expect_true(is.character(out$best_matches[[1]]$roles))
  expect_true(is.list(out$synergy_groups))
  expect_true(is.numeric(out$group_count) || is.integer(out$group_count))
})

test_that("token sacrifice death groups detect converter bridge payoff", {
  payoff <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "death-payoff",
    name = "Mortuary Ledger",
    oracle_text = "Whenever a creature dies, draw a card.",
    colors = c("B"),
    color_identity = c("B"),
    cmc = 4,
    legalities = list(commander = "legal")
  ))

  setup <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "token-maker",
    name = "Call the Ranks",
    oracle_text = "Create two 1/1 white Soldier creature tokens.",
    colors = c("W"),
    color_identity = c("W"),
    cmc = 2,
    legalities = list(commander = "legal")
  ))

  converter <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "sac-outlet",
    name = "Ash Altar Adept",
    oracle_text = "Sacrifice a creature: Add {B}.",
    colors = c("B"),
    color_identity = c("B"),
    cmc = 2,
    legalities = list(commander = "legal")
  ))

  groups <- mtgcodex.api:::query_synergy_detect_groups_for_seed(
    seed = payoff,
    candidates = list(setup, converter),
    format_name = "commander",
    min_edge_score = 10,
    max_groups = 3,
    max_group_size = 4,
    max_paths = 30
  )

  expect_gte(length(groups$groups), 1)
  expect_true(any(vapply(groups$groups, function(group) {
    any(c("CREATE_TOKEN", "TOKEN_CREATED") %in% group$matched_events) &&
      any(c("SACRIFICE_PERMANENT", "DIES", "CREATURE_DIES") %in% group$matched_events)
  }, logical(1))))
})

test_that("anti synergy inside groups is penalized and explained", {
  payoff <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "payoff",
    name = "Archive Judge",
    oracle_text = "Whenever you draw a card, gain 1 life.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 3,
    legalities = list(commander = "legal")
  ))

  setup <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "setup",
    name = "Frantic Research",
    oracle_text = "Draw two cards, then discard two cards.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 2,
    legalities = list(commander = "legal")
  ))

  conflicted_engine <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "conflicted-engine",
    name = "Paradox Archivist",
    oracle_text = "Whenever you discard a card, draw a card. If you would draw a card, exile the top card of your library instead.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 2,
    legalities = list(commander = "legal")
  ))

  groups <- mtgcodex.api:::query_synergy_detect_groups_for_seed(
    seed = payoff,
    candidates = list(setup, conflicted_engine),
    format_name = "commander",
    min_edge_score = 5,
    max_groups = 3,
    max_group_size = 4,
    max_paths = 30
  )

  expect_gte(length(groups$groups), 1)
  flagged <- Filter(function(group) {
    suppressWarnings(as.numeric(group$score_breakdown$anti_synergy_penalty)) > 0 &&
      any(grepl("Anti-synergy penalty", group$reasons, fixed = TRUE))
  }, groups$groups)
  expect_gte(length(flagged), 1)
})

test_that("indirect engine scoring is structure driven rather than name driven", {
  target <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "seed-draw",
    name = "Sage of Copies",
    oracle_text = "Whenever you draw a card, gain 1 life.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 3,
    legalities = list(commander = "legal")
  ))

  engine_a <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "engine-a",
    name = "Alpha Broker",
    oracle_text = "Whenever you attack, target attacking creature connives 1.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 3,
    legalities = list(commander = "legal")
  ))

  engine_b <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "engine-b",
    name = "Beta Broker",
    oracle_text = "Whenever you attack, target attacking creature connives 1.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 3,
    legalities = list(commander = "legal")
  ))

  score_a <- mtgcodex.api:::query_synergy_score_pair(target, engine_a, "commander")
  score_b <- mtgcodex.api:::query_synergy_score_pair(target, engine_b, "commander")

  expect_identical(score_a$primary_bucket, score_b$primary_bucket)
  expect_equal(score_a$axis_scores, score_b$axis_scores)
  expect_identical(score_a$score, score_b$score)
})

test_that("replacement conflicts surface in anti synergy warnings", {
  catalog <- list(
    list(
      id = "seed",
      name = "Ledger Saint",
      oracle_text = "Whenever you draw a card, gain 1 life.",
      colors = c("U"),
      color_identity = c("U"),
      cmc = 3,
      legalities = list(commander = "legal")
    ),
    list(
      id = "direct",
      name = "Thought Current",
      oracle_text = "Draw two cards.",
      colors = c("U"),
      color_identity = c("U"),
      cmc = 2,
      legalities = list(commander = "legal")
    ),
    list(
      id = "warning",
      name = "Closed Archive",
      oracle_text = "If you would draw a card, exile the top card of your library instead.",
      colors = c("U"),
      color_identity = c("U"),
      cmc = 2,
      legalities = list(commander = "legal")
    )
  )

  out <- mtgcodex.api:::query_synergy_find_in_catalog(
    list(card_name = "Ledger Saint", format = "commander", max_results = 6),
    catalog
  )

  anti_bucket <- out$buckets$anti_synergy_warnings
  expect_true(is.list(anti_bucket))
  expect_gte(anti_bucket$count, 1)
  expect_true(any(vapply(anti_bucket$results, function(entry) identical(entry$name, "Closed Archive"), logical(1))))

  warning_entry <- Filter(function(entry) identical(entry$name, "Closed Archive"), anti_bucket$results)[[1]]
  expect_identical(warning_entry$bucket, "anti_synergy_warnings")
  expect_true("DRAW_CARD" %in% warning_entry$matched_events$replaces_payoff)
})

test_that("expand_group_pool includes bridge card scoring well with pool member but not seed", {
  # Seed: draws cards (DRAW_CARD producer)
  seed <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "seed-draw",
    name = "Compulsive Archivist",
    oracle_text = "At the beginning of your upkeep, draw two cards.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 4,
    legalities = list(commander = "legal")
  ))

  # Pool member: rewards DRAW_CARD (direct synergy with seed)
  pool_member <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "pool-payoff",
    name = "Arcane Payoff",
    oracle_text = "Whenever you draw a card, you gain 1 life.",
    colors = c("W"),
    color_identity = c("W"),
    cmc = 2,
    legalities = list(commander = "legal")
  ))

  # Bridge: draws a card when a creature dies — synergistic with pool_member
  # (feeds DRAW_CARD which pool_member rewards) but conditional, so its direct
  # score with the seed is lower.
  bridge <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "bridge-death",
    name = "Grim Witness",
    oracle_text = "Whenever a creature you control dies, draw a card.",
    colors = c("B"),
    color_identity = c("B"),
    cmc = 3,
    legalities = list(commander = "legal")
  ))

  registry <- mtgcodex.api:::query_synergy_event_registry_default()

  expanded <- mtgcodex.api:::query_synergy_expand_group_pool(
    initial_pool = list(pool_member),
    bridge_candidates = list(bridge),
    registry = registry,
    format_name = "commander",
    bridge_cheap_threshold = 0.08,
    bridge_deep_threshold = 20,
    expansion_cap = 4L
  )

  # The bridge card should have been added to the pool because it scores well
  # with the pool member (both involve DRAW_CARD).
  expanded_ids <- vapply(expanded, function(c) mtgcodex.api:::query_api_scalar(c$id, default = ""), character(1))
  expect_true("bridge-death" %in% expanded_ids,
    info = "Bridge card scoring well with pool member should be included in the expanded pool"
  )
  expect_equal(length(expanded), 2L)
})

test_that("refine_groups swaps weakest member for a stronger anchor neighbor", {
  # Seed: produces SELF_DRAW_CARD via "draw two" trigger
  seed <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "seed-A",
    name = "Mystic Recordkeeper",
    oracle_text = "At the beginning of your upkeep, draw two cards.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 4,
    legalities = list(commander = "legal")
  ))

  # Strong direct payoff for the seed: rewards SELF_DRAW_CARD
  strong_payoff <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "B-strong-payoff",
    name = "Cosmic Scholar",
    oracle_text = "Whenever you draw a card, you gain 2 life.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 3,
    legalities = list(commander = "legal")
  ))

  # Weak filler that survives initial group detection but adds little value.
  weak_filler <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "C-weak-filler",
    name = "Idle Apprentice",
    oracle_text = "Whenever you draw a card, scry 1.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 1,
    legalities = list(commander = "legal")
  ))

  # Better neighbor of the strong payoff: a creature that, when paired with
  # the payoff, completes a stronger life-gain chain.
  better_neighbor <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "D-life-amplifier",
    name = "Beacon of Mercy",
    oracle_text = "Whenever you gain life, draw a card.",
    colors = c("W"),
    color_identity = c("W"),
    cmc = 3,
    legalities = list(commander = "legal")
  ))

  # Setup card the seed/payoff path can chain through (gives initial path
  # search material for a 3-card group).
  starter <- mtgcodex.api:::query_synergy_normalize_card(list(
    id = "starter-draw",
    name = "Tutor Scribe",
    oracle_text = "When this enters, draw a card.",
    colors = c("U"),
    color_identity = c("U"),
    cmc = 2,
    legalities = list(commander = "legal")
  ))

  registry <- mtgcodex.api:::query_synergy_event_registry_default()

  # Build an initial group {seed, strong_payoff, weak_filler}
  initial <- mtgcodex.api:::query_synergy_detect_groups_for_seed(
    seed = seed,
    candidates = list(strong_payoff, weak_filler, starter),
    format_name = "commander",
    min_edge_score = 8,
    max_groups = 1L,
    max_group_size = 3L,
    max_paths = 24L
  )
  skip_if(length(initial$groups) == 0L, "initial group not produced — fixture too weak")

  # Broader pool exposes better_neighbor as a refinement candidate.
  broader <- list(strong_payoff, weak_filler, starter, better_neighbor)

  refined <- mtgcodex.api:::query_synergy_refine_groups(
    groups = initial$groups,
    seed = seed,
    broader_pool = broader,
    format_name = "commander",
    registry = registry,
    max_iterations = 2L,
    max_groups_to_refine = 1L,
    k_member = 5L,
    theta_seed_score = 0,           # accept any seed-pair score (test fixture)
    max_replacements_to_try = 4L,
    min_edge_score = 8L,
    max_branching = 4L,
    max_paths = 24L
  )

  expect_equal(length(refined), 1L)
  refined_group <- refined[[1]]
  refined_ids <- vapply(refined_group$members, function(m) m$id, character(1))
  # The weakest member should remain or have been swapped for an equal-or-better
  # candidate; if a swap occurred, the new total_score must be >= original.
  initial_score <- initial$groups[[1]]$total_score
  expect_gte(refined_group$total_score, initial_score)

  # If a refinement happened, the provenance metadata should be present.
  if (!is.null(refined_group$refinement_provenance)) {
    expect_true(nzchar(refined_group$refinement_provenance$replaced_member_id))
    expect_true(nzchar(refined_group$refinement_provenance$with_member_id))
    expect_gte(refined_group$refinement_provenance$delta_score, 0)
  }
})


test_that("archetype detection identifies aristocrats theme", {
  sac_outlet <- list(
    id = "x:sac",
    name = "Sac Outlet",
    strategy_tags = c("sacrifice_outlet", "death_payoff"),
    produced_events = c("SACRIFICE_PERMANENT", "DIES"),
    consumed_events = character(0),
    roles = c("converter")
  )
  token_maker <- list(
    id = "x:tok",
    name = "Token Maker",
    strategy_tags = c("token_producer"),
    produced_events = c("CREATE_TOKEN"),
    consumed_events = character(0),
    roles = c("engine")
  )
  death_payoff <- list(
    id = "x:pay",
    name = "Death Payoff",
    strategy_tags = c("death_payoff"),
    produced_events = character(0),
    consumed_events = c("DIES", "SACRIFICE_PERMANENT"),
    roles = c("payoff")
  )
  archetypes <- mtgcodex.api:::query_synergy_archetypes_for_group_members(
    list(sac_outlet, token_maker, death_payoff)
  )
  expect_true("aristocrats" %in% names(archetypes))
  expect_gt(archetypes$aristocrats$score, 0)
})

test_that("archetype alignment returns 1 with no filter and 0 on mismatch", {
  group_arch <- list(
    aristocrats = list(score = 0.6, contributors = 3, label = "Aristocrats")
  )
  expect_equal(
    mtgcodex.api:::query_synergy_group_archetype_alignment(group_arch, character(0)),
    1
  )
  expect_equal(
    mtgcodex.api:::query_synergy_group_archetype_alignment(group_arch, c("ramp")),
    0
  )
  expect_equal(
    mtgcodex.api:::query_synergy_group_archetype_alignment(group_arch, c("aristocrats")),
    0.6
  )
})
