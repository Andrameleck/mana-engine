# Deck generator.
#
# Goal: from a format + color identity + archetype tags (and optionally a
# user-provided commander), build one or more complete deck lists that respect
# format constraints (size, singleton, color identity, max-copies), have a
# sensible role distribution (lands / ramp / draw / removal / threats / core
# synergy), a reasonable mana curve, and surface any Spellbook combos detected
# in the generated list.
#
# Pipeline:
#   1. Resolve the commander (Commander/Brawl) or the seed (60-card formats).
#      - User can override; otherwise pick the top legal candidate matching
#        colors + archetypes by mechanical richness.
#   2. Score the full legal pool against the seed using the existing pair
#      scorer (`query_synergy_find_in_catalog` with groups disabled).
#   3. Greedy fill:
#        a. Always include format-required basics / lands first.
#        b. Fill role quotas (ramp, draw, removal, threats, core) by score.
#        c. Bias selection toward the target mana curve.
#   4. Detect Spellbook combos in the final list.
#   5. Optionally generate up to N variants by excluding top picks from prior
#      decks (forces diversification).

# Role classifier ---------------------------------------------------------

.deck_card_roles <- function(card, normalized) {
  type_line <- tolower(query_api_scalar(card$type_line, default = ""))
  text <- tolower(query_api_scalar(card$oracle_text, default = ""))
  produced <- query_synergy_to_vector(normalized$produced_events)
  rewards <- query_synergy_to_vector(normalized$rewarded_events)
  finishers <- query_synergy_to_vector(normalized$finisher_events)
  tags <- query_synergy_to_vector(normalized$strategy_tags)
  cmc <- suppressWarnings(as.numeric(normalized$mana_value))
  if (!is.finite(cmc)) cmc <- 0

  roles <- character(0)

  if (grepl("\\bland\\b", type_line, perl = TRUE)) {
    roles <- c(roles, "land")
    if (grepl("\\bbasic\\b", type_line, perl = TRUE)) {
      roles <- c(roles, "basic_land")
    }
    return(roles)
  }

  # Ramp: produces mana, searches lands, mana rocks <= 3 cmc.
  is_ramp <- FALSE
  if (any(c("ramp", "mana_rock", "treasure_producer") %in% tags)) is_ramp <- TRUE
  if (grepl("\\b(add\\s+\\{[wubrgc0-9/x]+\\}|search your library for .* land|put .* land .* onto the battlefield)\\b",
            text, perl = TRUE) && cmc <= 4) {
    is_ramp <- TRUE
  }
  if (grepl("\\bcreate .* treasure token\\b", text, perl = TRUE) && cmc <= 4) is_ramp <- TRUE
  if (is_ramp) roles <- c(roles, "ramp")

  # Card draw: produces SELF_DRAW_CARD or DRAW_CARD.
  if (any(c("SELF_DRAW_CARD", "DRAW_CARD") %in% produced) ||
      any(c("draw_engine", "card_flow", "card_selection", "loot") %in% tags) ||
      grepl("\\bdraw .* cards?\\b", text, perl = TRUE)) {
    roles <- c(roles, "card_draw")
  }

  # Removal / interaction.
  is_removal <- FALSE
  if (grepl("\\b(destroy|exile)\\s+(target|all|each)\\b", text, perl = TRUE)) is_removal <- TRUE
  if (grepl("\\bcounter target\\b", text, perl = TRUE)) is_removal <- TRUE
  if (grepl("\\bdeal[s]?\\s+\\d+\\s+damage to (target|any)\\b", text, perl = TRUE)) is_removal <- TRUE
  if (is_removal) roles <- c(roles, "removal")

  # Threats: creatures + finishers / impactful payoffs.
  is_creature <- grepl("\\bcreature\\b", type_line, perl = TRUE)
  is_threat <- FALSE
  if (is_creature && (length(finishers) > 0 || cmc >= 5)) is_threat <- TRUE
  if (any(c("graveyard_finisher", "combat_engine") %in% tags)) is_threat <- TRUE
  if (is_threat) roles <- c(roles, "threat")

  # Core: anything carrying meaningful synergy tags / events.
  is_core <- FALSE
  if (length(produced) > 0 || length(rewards) > 0) is_core <- TRUE
  if (length(tags) > 0) is_core <- TRUE
  if (is_core) roles <- c(roles, "core")

  # Fallback: if no role assigned, treat as a role-less filler (low priority).
  if (length(roles) == 0L) roles <- "filler"

  unique(roles)
}

# Format spec: deck size, singleton, role quotas, curve target ------------

.deck_generator_format_spec <- function(format_name) {
  fname <- tolower(query_api_scalar(format_name, default = "commander"))
  base <- query_synergy_format_spec(fname)
  if (is.null(base)) base <- list(label = fname, singleton = FALSE, color_identity_strict = FALSE)

  if (fname %in% c("commander", "brawl")) {
    list(
      key = fname,
      label = query_api_scalar(base$label, default = fname),
      deck_size = if (fname == "brawl") 60L else 100L, # includes commander
      mainboard_size = if (fname == "brawl") 59L else 99L,
      singleton = TRUE,
      color_identity_strict = TRUE,
      max_copies = 1L,
      requires_commander = TRUE,
      target = list(
        land = 36L,
        ramp = 10L,
        card_draw = 10L,
        removal = 8L,
        threat = 12L,
        core = 23L
      ),
      curve_target = c("0-1" = 6L, "2" = 12L, "3" = 14L, "4" = 14L, "5" = 9L, "6+" = 8L)
    )
  } else {
    list(
      key = fname,
      label = query_api_scalar(base$label, default = fname),
      deck_size = 60L,
      mainboard_size = 60L,
      singleton = FALSE,
      color_identity_strict = FALSE,
      max_copies = 4L,
      requires_commander = FALSE,
      target = list(
        land = 24L,
        ramp = 4L,
        card_draw = 6L,
        removal = 8L,
        threat = 10L,
        core = 8L
      ),
      curve_target = c("0-1" = 8L, "2" = 12L, "3" = 12L, "4" = 8L, "5" = 4L, "6+" = 2L)
    )
  }
}

.deck_curve_bucket <- function(cmc) {
  cmc <- suppressWarnings(as.numeric(cmc))
  if (!is.finite(cmc)) cmc <- 0
  if (cmc <= 1) return("0-1")
  if (cmc == 2) return("2")
  if (cmc == 3) return("3")
  if (cmc == 4) return("4")
  if (cmc == 5) return("5")
  return("6+")
}

# Commander selection -----------------------------------------------------

.deck_pick_commander <- function(catalog, format_spec, color_filter,
                                 archetype_filter, registry) {
  # Filter to legal commanders: legendary creatures (or planeswalkers explicitly
  # allowed as commanders, which we ignore in this v1).
  pool <- Filter(function(c) {
    tline <- tolower(query_api_scalar(c$type_line, default = ""))
    if (!grepl("legendary", tline, perl = TRUE)) return(FALSE)
    if (!grepl("creature", tline, perl = TRUE)) return(FALSE)
    if (!query_synergy_card_legal_in_format(c, format_spec$key, FALSE)) return(FALSE)
    if (length(color_filter) > 0L) {
      ci <- query_synergy_to_vector(c$color_identity)
      # Commander color identity must be a SUBSET of the chosen colors.
      if (length(setdiff(ci, color_filter)) > 0L) return(FALSE)
    }
    TRUE
  }, catalog)

  if (length(pool) == 0L) return(NULL)

  # Score by mechanical richness + archetype match.
  scores <- vapply(pool, function(c) {
    norm <- tryCatch(
      query_synergy_normalize_card_cached(c, registry = registry),
      error = function(e) NULL
    )
    if (is.null(norm)) return(0)
    produced <- length(query_synergy_to_vector(norm$produced_events))
    consumed <- length(query_synergy_to_vector(norm$consumed_events))
    rewards <- length(query_synergy_to_vector(norm$rewarded_events))
    roles <- length(query_synergy_to_vector(norm$roles))
    tags <- query_synergy_to_vector(norm$strategy_tags)
    arch_match <- 0
    if (length(archetype_filter) > 0L) {
      fits <- tryCatch(
        query_synergy_archetypes_for_card(norm, min_fit = 0),
        error = function(e) list()
      )
      for (akey in archetype_filter) {
        a_score <- suppressWarnings(as.numeric(fits[[akey]]))
        if (is.finite(a_score)) arch_match <- arch_match + a_score
      }
    }
    produced * 1.5 + consumed * 1.2 + rewards * 1.4 + roles * 1.0 +
      length(tags) * 0.5 + arch_match * 6
  }, numeric(1))

  ord <- order(scores, decreasing = TRUE)
  pool[[ord[[1]]]]
}

# Build mainboard from scored candidates ---------------------------------

.deck_build_mainboard <- function(seed, scored_candidates, format_spec,
                                  excluded_ids = character(0),
                                  variant_seed = 0L,
                                  collection_copy_cap = NULL) {
  target <- format_spec$target
  curve_target <- format_spec$curve_target
  max_copies <- format_spec$max_copies
  mainboard_size <- format_spec$mainboard_size
  has_cap <- is.list(collection_copy_cap) && length(collection_copy_cap) > 0L

  # Build per-card record with role + curve bucket. Exclude seed/commander
  # itself (it goes in the command zone).
  seed_id <- tolower(query_api_scalar(seed$id, default = ""))
  excl <- tolower(excluded_ids)

  records <- lapply(scored_candidates, function(s) {
    card <- s$card
    cid <- tolower(query_api_scalar(card$id, default = ""))
    if (nzchar(cid) && (identical(cid, seed_id) || cid %in% excl)) return(NULL)
    norm <- s$normalized
    list(
      id = card$id,
      name = card$name,
      cmc = suppressWarnings(as.numeric(norm$mana_value)),
      type_line = card$type_line,
      mana_cost = card$mana_cost,
      colors = query_synergy_to_vector(card$colors),
      color_identity = query_synergy_to_vector(card$color_identity),
      score = suppressWarnings(as.numeric(s$score)),
      pair_score = suppressWarnings(as.numeric(s$pair_score %||% NA_real_)),
      coherence_score = suppressWarnings(as.numeric(s$coherence_score %||% NA_real_)),
      is_core = isTRUE(s$is_core),
      roles = .deck_card_roles(card, norm),
      curve_bucket = .deck_curve_bucket(norm$mana_value),
      strategy_tags = query_synergy_to_vector(norm$strategy_tags),
      card = card,
      normalized = norm
    )
  })
  records <- Filter(Negate(is.null), records)

  # Deterministic but variant-able shuffling at score ties.
  if (variant_seed > 0L) {
    set.seed(variant_seed)
    jitter <- stats::runif(length(records), 0, 0.5)
    for (i in seq_along(records)) {
      records[[i]]$score <- (records[[i]]$score %||% 0) + jitter[[i]]
    }
  }
  scores_v <- vapply(records, function(r) suppressWarnings(as.numeric(r$score)), numeric(1))
  scores_v[is.na(scores_v) | !is.finite(scores_v)] <- 0
  records <- records[order(scores_v, decreasing = TRUE)]

  # In non-singleton formats (Standard, Modern, Pioneer, ...), the deck may
  # play up to `max_copies` of each card. We model this by replicating each
  # record `max_copies` times before the greedy fill so the same record can
  # be "re-picked" multiple times. The per-name `copy_counts` cap below
  # still enforces the legal copy limit.
  if (!isTRUE(format_spec$singleton) && max_copies > 1L) {
    records <- rep(records, each = as.integer(max_copies))
  }

  # Filled deck: list of cards with role tagging.
  picked <- list()
  picked_ids <- character(0)
  picked_names <- character(0)
  role_counts <- list(land = 0L, ramp = 0L, card_draw = 0L,
                      removal = 0L, threat = 0L, core = 0L, filler = 0L)
  curve_counts <- setNames(integer(length(curve_target)), names(curve_target))
  copy_counts <- new.env(parent = emptyenv(), hash = TRUE)

  current_copies <- function(rec) {
    nm_key <- tolower(rec$name %||% "")
    if (!nzchar(nm_key)) return(0L)
    if (exists(nm_key, envir = copy_counts, inherits = FALSE)) {
      as.integer(get(nm_key, envir = copy_counts, inherits = FALSE))
    } else 0L
  }

  # Per-card effective copy limit: if a collection_copy_cap is provided, the
  # limit is min(format max_copies, owned_quantity). This ensures we never
  # include more copies than the player owns.
  effective_max_copies <- function(rec) {
    if (!has_cap) return(max_copies)
    nm_key <- tolower(rec$name %||% "")
    owned <- collection_copy_cap[[nm_key]] %||% max_copies
    min(max_copies, as.integer(owned))
  }

  add_card <- function(rec, slot_role) {
    nm_key <- tolower(rec$name %||% "")
    cnt <- if (exists(nm_key, envir = copy_counts, inherits = FALSE)) {
      get(nm_key, envir = copy_counts, inherits = FALSE)
    } else 0L
    emax <- effective_max_copies(rec)
    if (cnt >= emax) return(FALSE)
    if (format_spec$singleton && cnt >= 1L) return(FALSE)
    assign(nm_key, cnt + 1L, envir = copy_counts)
    rec$slot_role <- slot_role
    picked[[length(picked) + 1L]] <<- rec
    picked_ids <<- c(picked_ids, rec$id)
    picked_names <<- c(picked_names, rec$name)
    role_counts[[slot_role]] <<- (role_counts[[slot_role]] %||% 0L) + 1L
    cb <- rec$curve_bucket
    if (!is.null(cb) && cb %in% names(curve_counts)) {
      curve_counts[[cb]] <<- curve_counts[[cb]] + 1L
    }
    TRUE
  }

  # 1. Lands first: target$land slots, but cap at remaining size.
  non_basic_lands <- Filter(function(r) "land" %in% r$roles && !("basic_land" %in% r$roles), records)
  for (rec in non_basic_lands) {
    if (length(picked) >= mainboard_size) break
    if (role_counts$land >= target$land) break
    add_card(rec, "land")
  }

  # Reserve remaining land slots so non-land roles can't overrun them.
  # `non_land_cap` is the max number of non-land slots we'll fill before
  # topping up with basic lands.
  non_land_cap <- mainboard_size - target$land
  non_land_picked <- function() length(picked) - role_counts$land

  # Greedy quota-respecting fill for non-land roles.
  ordered_roles <- c("ramp", "card_draw", "removal", "threat", "core")
  for (role in ordered_roles) {
    quota <- target[[role]] %||% 0L
    if (non_land_picked() >= non_land_cap) break
    if (quota <= 0L) next
    pool <- Filter(function(r) {
      if (isTRUE(format_spec$singleton) && r$id %in% picked_ids) return(FALSE)
      if (current_copies(r) >= effective_max_copies(r)) return(FALSE)
      if ("land" %in% r$roles) return(FALSE)
      role %in% r$roles
    }, records)
    biased <- lapply(pool, function(r) {
      cb <- r$curve_bucket
      tgt <- if (!is.null(cb) && cb %in% names(curve_target)) curve_target[[cb]] else 5L
      cur <- if (!is.null(cb) && cb %in% names(curve_counts)) curve_counts[[cb]] else 0L
      penalty <- max(0, cur - tgt) * 4
      r$adjusted_score <- (r$score %||% 0) - penalty
      r
    })
    biased <- biased[order(vapply(biased, function(r) r$adjusted_score, numeric(1)),
                           decreasing = TRUE)]
    for (rec in biased) {
      if (non_land_picked() >= non_land_cap) break
      if (role_counts[[role]] >= quota) break
      add_card(rec, role)
    }
  }

  # Top-up: any remaining non-land slots (under cap) with the highest-scoring
  # unused non-land cards (categorised under "core").
  if (non_land_picked() < non_land_cap) {
    leftover <- Filter(function(r) {
      if (isTRUE(format_spec$singleton) && r$id %in% picked_ids) return(FALSE)
      if (current_copies(r) >= effective_max_copies(r)) return(FALSE)
      if ("land" %in% r$roles) return(FALSE)
      TRUE
    }, records)
    for (rec in leftover) {
      if (non_land_picked() >= non_land_cap) break
      add_card(rec, "core")
    }
  }

  # Land top-up: if we couldn't reach target$land via non-basic lands, fill
  # with basic lands of the seed/commander color identity. We require basics
  # to be present in the catalog; if absent, leave the slot empty (UI shows it).
  if (length(picked) < mainboard_size) {
    ci <- query_synergy_to_vector(seed$color_identity)
    basic_map <- list(W = "Plains", U = "Island", B = "Swamp", R = "Mountain", G = "Forest")
    basics <- if (length(ci) > 0L) unique(unlist(basic_map[ci])) else character(0)
    if (length(basics) == 0L) basics <- "Wastes"
    while (length(picked) < mainboard_size) {
      basic_name <- basics[[((length(picked) - target$land + 1L) %% length(basics)) + 1L]]
      basic_card <- list(
        id = paste0("basic::", tolower(basic_name)),
        name = basic_name,
        type_line = paste("Basic Land", "--", sub("s$", "", basic_name)),
        cmc = 0,
        score = 0,
        roles = c("land", "basic_land"),
        slot_role = "land",
        curve_bucket = "0-1",
        is_basic_filler = TRUE
      )
      picked[[length(picked) + 1L]] <- basic_card
      role_counts$land <- role_counts$land + 1L
      curve_counts[["0-1"]] <- (curve_counts[["0-1"]] %||% 0L) + 1L
    }
  }

  list(
    cards = picked,
    role_counts = role_counts,
    curve_counts = as.list(curve_counts),
    curve_target = as.list(curve_target),
    role_target = target
  )
}

# Spellbook combo detection on a deck list -------------------------------

.deck_detect_combos <- function(card_names) {
  names_v <- unique(tolower(trimws(as.character(card_names))))
  names_v <- names_v[nzchar(names_v)]
  if (length(names_v) < 2L) return(list())

  combos <- tryCatch(
    query_synergy_spellbook_combos_load(),
    error = function(e) list()
  )
  if (length(combos) == 0L) return(list())

  detected <- list()
  for (combo in combos) {
    combo_cards <- tolower(query_synergy_to_vector(combo$cards))
    combo_cards <- combo_cards[nzchar(combo_cards)]
    if (length(combo_cards) < 2L) next
    if (all(combo_cards %in% names_v)) {
      detected[[length(detected) + 1L]] <- list(
        id = query_api_scalar(combo$id, default = ""),
        title = query_api_scalar(combo$title, default = ""),
        produces = query_api_scalar(combo$produces, default = ""),
        cards = combo_cards,
        size = length(combo_cards)
      )
    }
  }
  detected
}

# Score the assembled deck -----------------------------------------------

.deck_score_assembly <- function(deck, format_spec, archetype_filter) {
  cards <- deck$cards
  if (length(cards) == 0L) return(list(total_score = 0L, score_base = 0L, score_modifiers = list()))

  # Average pair score of non-land, non-basic cards as the synergy backbone.
  scores <- vapply(cards, function(c) suppressWarnings(as.numeric(c$score %||% 0)), numeric(1))
  is_land <- vapply(cards, function(c) isTRUE("land" %in% c$roles), logical(1))
  syn_scores <- scores[!is_land]
  syn_scores <- syn_scores[is.finite(syn_scores) & syn_scores > 0]
  base <- if (length(syn_scores) > 0L) round(mean(syn_scores)) else 0
  base <- as.integer(min(100L, max(0L, base)))

  modifiers <- list()
  # Role coverage bonus.
  rc <- deck$role_counts
  tgt <- deck$role_target
  coverage_pct <- mean(vapply(names(tgt), function(k) {
    target_v <- tgt[[k]] %||% 0L
    actual <- rc[[k]] %||% 0L
    if (target_v <= 0L) return(1)
    min(1, actual / target_v)
  }, numeric(1)))
  if (coverage_pct > 0) {
    modifiers$role_coverage <- list(
      amount = as.integer(round(coverage_pct * 8)),
      coverage_pct = round(coverage_pct, 2)
    )
  }
  # Curve fit.
  curve_diff <- 0
  for (bucket in names(deck$curve_target)) {
    diff <- abs((deck$curve_counts[[bucket]] %||% 0L) - (deck$curve_target[[bucket]] %||% 0L))
    curve_diff <- curve_diff + diff
  }
  # Lower curve_diff = better. Penalty up to -10.
  curve_pen <- max(-10L, -as.integer(round(curve_diff / 2)))
  if (curve_pen != 0L) {
    modifiers$curve_fit <- list(amount = curve_pen, total_diff = as.integer(curve_diff))
  }

  total <- base + sum(vapply(modifiers, function(m) as.integer(m$amount), integer(1)))
  total <- as.integer(max(0L, min(100L, total)))
  list(score_base = base, score_modifiers = modifiers, total_score = total)
}

# Coherence: pick a "core" of cards that share a clear game plan with the
# commander, build a DNA fingerprint of the produced/consumed/rewarded events
# and tags, then rescore every candidate by how strongly it supports that DNA
# (rather than how well it just pairs with the commander). This is what turns
# the deck from "agglomerate of synergies with the commander" into "a single
# coherent strategy".

.deck_pick_core <- function(seed, scored_candidates, registry,
                            archetype_filter = character(0),
                            core_size = 8L) {
  # Score each candidate as: pair score with seed x archetype fit.
  # We require non-trivial mechanical content: at least one produced or
  # consumed event so that the picked card actually drives a game plan.
  if (length(scored_candidates) == 0L) return(integer(0))
  pair_scores <- vapply(scored_candidates, function(s) {
    suppressWarnings(as.numeric(s$score %||% 0))
  }, numeric(1))
  pair_scores[!is.finite(pair_scores)] <- 0
  arch_fit <- vapply(scored_candidates, function(s) {
    n <- s$normalized
    produced <- length(query_synergy_to_vector(n$produced_events))
    consumed <- length(query_synergy_to_vector(n$consumed_events))
    rewards  <- length(query_synergy_to_vector(n$rewarded_events))
    if ((produced + consumed + rewards) == 0L) return(-Inf)
    if (length(archetype_filter) == 0L) return(0)
    fits <- tryCatch(
      query_synergy_archetypes_for_card(n, min_fit = 0),
      error = function(e) list()
    )
    sum(vapply(archetype_filter, function(k) {
      v <- suppressWarnings(as.numeric(fits[[k]]))
      if (is.finite(v)) v else 0
    }, numeric(1)))
  }, numeric(1))
  composite <- pair_scores + arch_fit * 40
  ord <- order(composite, decreasing = TRUE)
  ord[seq_len(min(length(ord), as.integer(core_size)))]
}

.deck_build_dna <- function(seed_normalized, core_normalized_list) {
  # Aggregate event/tag/role counts. Higher counts = more central to the deck.
  bag <- function(vs) {
    out <- list(produced = character(0), consumed = character(0),
                rewarded = character(0), tags = character(0), roles = character(0))
    for (v in vs) {
      out$produced <- c(out$produced, query_synergy_to_vector(v$produced_events))
      out$consumed <- c(out$consumed, query_synergy_to_vector(v$consumed_events))
      out$rewarded <- c(out$rewarded, query_synergy_to_vector(v$rewarded_events))
      out$tags     <- c(out$tags,     query_synergy_to_vector(v$strategy_tags))
      out$roles    <- c(out$roles,    query_synergy_to_vector(v$roles))
    }
    lapply(out, function(x) {
      if (length(x) == 0L) return(integer(0))
      tab <- table(x)
      setNames(as.integer(tab), names(tab))
    })
  }
  bag(c(list(seed_normalized), core_normalized_list))
}

.deck_coherence_score <- function(card_normalized, dna) {
  # Score a candidate's contribution to the deck DNA.
  # - Produces an event the deck CONSUMES or REWARDS = strong fuel/feeder.
  # - Consumes an event the deck PRODUCES = strong payoff/converter.
  # - Rewards an event the deck PRODUCES = strong payoff/reward.
  # - Shares strategy tags or roles with the deck = thematic alignment.
  # Bonus per match is proportional to how central that event is in the DNA.
  produced <- query_synergy_to_vector(card_normalized$produced_events)
  consumed <- query_synergy_to_vector(card_normalized$consumed_events)
  rewarded <- query_synergy_to_vector(card_normalized$rewarded_events)
  tags     <- query_synergy_to_vector(card_normalized$strategy_tags)
  roles    <- query_synergy_to_vector(card_normalized$roles)

  weight <- function(event_v, dna_bag, factor) {
    if (length(event_v) == 0L || length(dna_bag) == 0L) return(0)
    sum(vapply(event_v, function(e) {
      cnt <- as.integer(dna_bag[e])
      if (is.na(cnt) || cnt <= 0L) return(0)
      # log-ish dampening so that one event repeated many times does not
      # dominate; sqrt is sufficient for our small DNA bags.
      sqrt(cnt) * factor
    }, numeric(1)))
  }

  s_feed     <- weight(produced, dna$consumed, 6)   # I produce what deck eats
  s_feed_rew <- weight(produced, dna$rewarded, 7)   # I produce what deck rewards
  s_payoff   <- weight(consumed, dna$produced, 6)   # I eat what deck produces
  s_reward   <- weight(rewarded, dna$produced, 7)   # I reward what deck produces
  s_tag      <- weight(tags,     dna$tags,     2.5) # shared theme tags
  s_role     <- weight(roles,    dna$roles,    1.5) # shared functional roles

  s_feed + s_feed_rew + s_payoff + s_reward + s_tag + s_role
}

.deck_rescore_for_coherence <- function(seed, scored_candidates, registry,
                                        archetype_filter = character(0),
                                        core_size = 8L,
                                        pair_weight = 0.4,
                                        coherence_weight = 0.6) {
  if (length(scored_candidates) == 0L) {
    return(list(scored = scored_candidates, core_ids = character(0)))
  }
  seed_norm <- tryCatch(
    query_synergy_normalize_card_cached(seed, registry = registry),
    error = function(e) NULL
  )
  if (is.null(seed_norm)) {
    return(list(scored = scored_candidates, core_ids = character(0)))
  }

  core_idx <- .deck_pick_core(seed, scored_candidates, registry,
                              archetype_filter = archetype_filter,
                              core_size = core_size)
  if (length(core_idx) == 0L) {
    return(list(scored = scored_candidates, core_ids = character(0)))
  }
  core_normalized <- lapply(core_idx, function(i) scored_candidates[[i]]$normalized)
  core_ids <- vapply(core_idx, function(i) {
    query_api_scalar(scored_candidates[[i]]$card$id, default = "")
  }, character(1))

  dna <- .deck_build_dna(seed_norm, core_normalized)

  # Compute coherence score per candidate.
  coh <- vapply(scored_candidates, function(s) {
    .deck_coherence_score(s$normalized, dna)
  }, numeric(1))
  # Normalise coherence to ~[0, 100] so it shares a scale with pair scores.
  if (any(is.finite(coh)) && max(coh, na.rm = TRUE) > 0) {
    coh_norm <- coh / max(coh, na.rm = TRUE) * 100
  } else {
    coh_norm <- coh
  }

  rescored <- lapply(seq_along(scored_candidates), function(i) {
    s <- scored_candidates[[i]]
    pair <- suppressWarnings(as.numeric(s$score %||% 0))
    if (!is.finite(pair)) pair <- 0
    coh_v <- suppressWarnings(as.numeric(coh_norm[[i]] %||% 0))
    if (!is.finite(coh_v)) coh_v <- 0
    s$pair_score <- pair
    s$coherence_score <- coh_v
    s$score <- pair * pair_weight + coh_v * coherence_weight
    # Boost for cards that are part of the core: they ARE the plan.
    if (query_api_scalar(s$card$id, default = "") %in% core_ids) {
      s$score <- s$score + 15
      s$is_core <- TRUE
    } else {
      s$is_core <- FALSE
    }
    s
  })

  list(scored = rescored, core_ids = core_ids, dna = dna)
}

# Random config helpers ---------------------------------------------------

.GENERATOR_RANDOM_FORMATS <- c("commander", "standard", "modern", "pioneer", "legacy")

.deck_random_format <- function() {
  sample(.GENERATOR_RANDOM_FORMATS, 1L)
}

# Returns a random non-empty color subset, weighted toward 2-3 colors.
.deck_random_colors <- function() {
  all_colors <- c("W", "U", "B", "R", "G")
  n <- sample(c(1L, 2L, 3L, 4L), 1L, prob = c(0.20, 0.40, 0.30, 0.10))
  sort(sample(all_colors, n))
}

# Returns 1 random archetype key from the registry.
.deck_random_archetype <- function(arch_keys) {
  if (length(arch_keys) == 0L) return(character(0))
  sample(arch_keys, 1L)
}

# Single-deck resolve+score+build helper ----------------------------------
#
# Resolves a seed card, scores the catalog against it, runs coherence
# rescoring, builds ONE deck, and returns a ready-to-serialise deck object
# (without the `variant` index, which the caller sets).
#
# Returns list(ok=TRUE, deck=..., core_ids, core_names, candidate_count)
# or      list(ok=FALSE, error=...)
.deck_resolve_and_build <- function(
  catalog,
  format_spec,
  color_filter,
  archetype_filter,
  user_commander = "",
  collection_copy_cap = NULL,
  registry,
  pool_keys = character(0),
  variant_seed = 1L,
  progress_callback = NULL,
  progress_min = 0,
  progress_max = 100
) {
  .emit <- function(pct, stage) {
    p <- progress_min + pct / 100 * (progress_max - progress_min)
    query_synergy_emit_progress(progress_callback, p, stage)
  }
  # Wrap scoring callback so its 0-100 maps to [progress_min+5%, progress_min+80%] of our slice.
  scoring_cb <- if (is.function(progress_callback)) {
    function(progress) {
      inner_pct <- suppressWarnings(as.numeric(progress$percent %||% 0))
      mapped <- progress_min + (5 + inner_pct * 0.75) / 100 * (progress_max - progress_min)
      progress$percent <- as.integer(round(mapped))
      progress_callback(progress)
    }
  } else NULL

  # 1. Resolve seed card.
  .emit(2, "Resolving seed card")
  seed_card <- NULL
  if (nzchar(user_commander)) {
    seed_card <- query_synergy_find_card_by_id_or_name(catalog, user_commander)
    if (is.null(seed_card)) {
      return(list(ok = FALSE, error = sprintf("commander '%s' not found in catalog", user_commander)))
    }
  } else if (isTRUE(format_spec$requires_commander)) {
    seed_card <- .deck_pick_commander(catalog, format_spec, color_filter, archetype_filter, registry)
    if (is.null(seed_card)) {
      return(list(ok = FALSE, error = "no legal commander candidate matches the requested colors / archetypes"))
    }
  } else {
    pseudo <- .deck_pick_commander(catalog, format_spec, color_filter, archetype_filter, registry)
    if (!is.null(pseudo)) seed_card <- pseudo
  }
  if (is.null(seed_card)) {
    return(list(ok = FALSE, error = "no seed card resolved"))
  }

  # 2. Score.
  anchor_payload <- list(
    card_name = query_api_scalar(seed_card$id, default = query_api_scalar(seed_card$name, default = "")),
    format = format_spec$key,
    max_results = 500L,
    max_groups = 1L,
    include_spellbook = FALSE,
    include_lotusnoir = FALSE,
    color_identity = color_filter,
    archetype_filter = archetype_filter,
    archetype_filter_strict = FALSE
  )
  scoring <- tryCatch(
    query_synergy_find_in_catalog(anchor_payload, catalog, progress_callback = scoring_cb),
    error = function(e) list(ok = FALSE, error = conditionMessage(e))
  )
  if (!isTRUE(scoring$ok)) {
    return(list(ok = FALSE, error = scoring$error %||% "scoring failed"))
  }

  # 3. Build candidate records.
  matches <- query_synergy_to_list(scoring$best_matches)
  cat_by_id <- new.env(parent = emptyenv(), hash = TRUE)
  for (c in catalog) {
    cid <- query_api_scalar(c$id, default = "")
    if (nzchar(cid)) assign(cid, c, envir = cat_by_id)
  }
  scored_candidates <- lapply(matches, function(m) {
    cid   <- query_api_scalar(m$id, default = "")
    cname <- query_api_scalar(m$name, default = "")
    if (length(pool_keys) > 0L && !(tolower(cname) %in% pool_keys)) return(NULL)
    full_card <- if (nzchar(cid) && exists(cid, envir = cat_by_id, inherits = FALSE)) {
      get(cid, envir = cat_by_id, inherits = FALSE)
    } else {
      m
    }
    norm <- tryCatch(
      query_synergy_normalize_card_cached(full_card, registry = registry),
      error = function(e) NULL
    )
    if (is.null(norm)) return(NULL)
    list(card = full_card, normalized = norm, score = suppressWarnings(as.numeric(m$score)))
  })
  scored_candidates <- Filter(Negate(is.null), scored_candidates)

  # 4. Supplement with utility roles (ramp, removal, draw, land).
  scored_ids <- vapply(scored_candidates,
    function(s) query_api_scalar(s$card$id, default = ""), character(1))
  scored_id_env <- new.env(parent = emptyenv(), hash = TRUE)
  for (sid in scored_ids) if (nzchar(sid)) assign(sid, TRUE, envir = scored_id_env)

  needs_role      <- c("land", "ramp", "card_draw", "removal")
  supplement_seen <- new.env(parent = emptyenv(), hash = TRUE)
  for (c in catalog) {
    cid <- query_api_scalar(c$id, default = "")
    if (!nzchar(cid)) next
    if (exists(cid, envir = scored_id_env,  inherits = FALSE)) next
    if (exists(cid, envir = supplement_seen, inherits = FALSE)) next
    if (length(color_filter) > 0L) {
      ci <- query_synergy_to_vector(c$color_identity)
      if (length(setdiff(ci, color_filter)) > 0L) next
    }
    if (!query_synergy_card_legal_in_format(c, format_spec$key, FALSE)) next
    norm <- tryCatch(
      query_synergy_normalize_card_cached(c, registry = registry),
      error = function(e) NULL
    )
    if (is.null(norm)) next
    roles <- .deck_card_roles(c, norm)
    if (!any(needs_role %in% roles)) next
    if ("basic_land" %in% roles) next
    assign(cid, TRUE, envir = supplement_seen)
    scored_candidates[[length(scored_candidates) + 1L]] <- list(
      card = c, normalized = norm, score = 0
    )
  }

  if (length(scored_candidates) < format_spec$mainboard_size / 2L) {
    return(list(
      ok = FALSE,
      error = sprintf(
        "only %d candidates after filtering (need ~%d); try different colors or archetype",
        length(scored_candidates), format_spec$mainboard_size
      )
    ))
  }

  # 5. Coherence rescoring.
  rescore <- .deck_rescore_for_coherence(
    seed = seed_card,
    scored_candidates = scored_candidates,
    registry = registry,
    archetype_filter = archetype_filter,
    core_size = 8L
  )
  scored_candidates <- rescore$scored
  core_ids   <- rescore$core_ids %||% character(0)
  core_names <- vapply(core_ids, function(cid) {
    if (!nzchar(cid)) return("")
    hit <- Filter(function(s) identical(
      query_api_scalar(s$card$id, default = ""), cid), scored_candidates)
    if (length(hit) == 0L) return("")
    query_api_scalar(hit[[1]]$card$name, default = "")
  }, character(1))
  core_names <- core_names[nzchar(core_names)]

  # 6. Normalise seed for matchup analysis.
  seed_norm_matchups <- tryCatch(
    query_synergy_normalize_card_cached(seed_card, registry = registry),
    error = function(e) NULL
  )

  # 7. Build deck (one deck, no exclusion diversification).
  .emit(83, "Building mainboard")
  deck <- .deck_build_mainboard(
    seed = seed_card,
    scored_candidates = scored_candidates,
    format_spec = format_spec,
    excluded_ids = character(0),
    variant_seed = variant_seed,
    collection_copy_cap = collection_copy_cap
  )

  # 8. Combo detection.
  .emit(90, "Detecting combos")
  card_names_for_combo <- vapply(deck$cards, function(c) c$name %||% "", character(1))
  if (isTRUE(format_spec$requires_commander)) {
    card_names_for_combo <- c(card_names_for_combo,
                               query_api_scalar(seed_card$name, default = ""))
  }
  combos <- .deck_detect_combos(card_names_for_combo)

  # 9. Score assembly.
  .emit(95, "Scoring assembly")
  score_info <- .deck_score_assembly(deck, format_spec, archetype_filter)
  if (length(combos) > 0L) {
    score_info$score_modifiers$spellbook_combos <- list(
      amount = as.integer(min(15L, length(combos) * 5L)),
      combo_count = length(combos)
    )
    score_info$total_score <- as.integer(min(100L, score_info$score_base +
      sum(vapply(score_info$score_modifiers,
                 function(m) as.integer(m$amount), integer(1)))))
  }

  # 10. Matchup analysis.
  matchups <- tryCatch(
    query_synergy_deck_matchups(
      commander_normalized = seed_norm_matchups,
      mainboard_records    = deck$cards,
      user_archetypes      = archetype_filter,
      top_n = 4L
    ),
    error = function(e) list(
      self_archetypes       = character(0),
      self_archetype_labels = character(0),
      strong_against        = list(),
      weak_against          = list(),
      tool_counts           = list()
    )
  )

  list(
    ok               = TRUE,
    seed_card        = seed_card,
    core_ids         = core_ids,
    core_names       = core_names,
    candidate_count  = length(scored_candidates),
    deck = list(
      commander = list(
        id             = seed_card$id,
        name           = seed_card$name,
        type_line      = seed_card$type_line,
        mana_cost      = seed_card$mana_cost,
        oracle_text    = seed_card$oracle_text,
        color_identity = query_synergy_to_vector(seed_card$color_identity),
        scryfall_id    = query_api_scalar(seed_card$scryfall_id, default = "")
      ),
      mainboard = lapply(deck$cards, function(c) {
        list(
          id              = c$id,
          name            = c$name,
          type_line       = c$type_line,
          mana_cost       = c$mana_cost,
          cmc             = c$cmc,
          slot_role       = c$slot_role,
          score           = round(suppressWarnings(as.numeric(c$score       %||% 0)), 1),
          pair_score      = round(suppressWarnings(as.numeric(c$pair_score  %||% 0)), 1),
          coherence_score = round(suppressWarnings(as.numeric(c$coherence_score %||% 0)), 1),
          is_core         = isTRUE(c$is_core),
          curve_bucket    = c$curve_bucket,
          is_basic_filler = isTRUE(c$is_basic_filler)
        )
      }),
      role_counts     = deck$role_counts,
      role_target     = deck$role_target,
      curve_counts    = deck$curve_counts,
      curve_target    = deck$curve_target,
      detected_combos = combos,
      matchups        = matchups,
      score_base      = score_info$score_base,
      score_modifiers = score_info$score_modifiers,
      total_score     = score_info$total_score,
      score           = score_info$total_score
    )
  )
}

# Main entry point -------------------------------------------------------

query_synergy_deck_generate <- function(req = NULL) {
  # Top-level guard: any uncaught error is turned into a structured JSON
  # error response so the HTTP layer never returns a generic 500.
  tryCatch(
    .query_synergy_deck_generate_impl(req = req),
    error = function(e) {
      msg <- tryCatch(conditionMessage(e), error = function(e2) "unknown error")
      query_api_error(
        sprintf("deck generation failed: %s", msg),
        decks = list()
      )
    }
  )
}

.query_synergy_deck_generate_impl <- function(req = NULL, data_override = NULL, progress_callback = NULL) {
  .emit <- function(pct, stage) {
    query_synergy_emit_progress(progress_callback, pct, stage)
  }
  payload <- if (!is.null(data_override)) {
    list(ok = TRUE, data = data_override)
  } else {
    query_synergy_parse_payload(req)
  }
  if (!isTRUE(payload$ok)) {
    return(query_api_error(payload$error, decks = list()))
  }
  .emit(1, "Parsing request")
  data <- payload$data

  format_name <- tolower(query_api_scalar(data$format, default = "commander"))
  format_spec <- .deck_generator_format_spec(format_name)
  color_filter <- query_synergy_parse_color_identity(data$color_identity)
  archetype_filter <- character(0)
  if (!is.null(data$archetype_filter)) {
    archetype_filter <- unique(query_synergy_to_vector(data$archetype_filter))
    archetype_filter <- archetype_filter[nzchar(archetype_filter)]
  }
  variant_count <- query_synergy_as_int(data$variant_count, default = 3L, min_value = 1L, max_value = 5L)
  pool_names <- query_synergy_to_vector(data$pool)
  pool_names <- trimws(pool_names[nzchar(pool_names)])
  pool_keys <- if (length(pool_names) > 0L) tolower(pool_names) else character(0)
  user_commander <- query_api_scalar(data$commander, default = "")
  collection_id <- query_api_scalar(data$collection_id, default = "")
  client_id <- query_api_scalar(data$client_id, default = "")

  .emit(3, "Loading card catalog")
  catalog_out <- query_synergy_get_catalog(force_refresh = isTRUE(data$force_refresh))
  if (!isTRUE(catalog_out$ok)) {
    return(query_api_error(catalog_out$error, decks = list()))
  }
  catalog <- catalog_out$cards
  .emit(10, "Catalog ready")
  registry <- query_synergy_event_registry_default()

  # Collection filter: when a collection_id is supplied, restrict the catalog
  # to only cards the user owns. The owned quantity per name is stored and used
  # as the per-card copy cap (so a player who owns 3 copies can include at most
  # 3, regardless of format max_copies). The commander/anchor card is always
  # allowed even if not in the collection (so the user can build around a card
  # they don't own yet).
  collection_copy_cap <- NULL  # NULL = use format default
  using_collection <- FALSE
  if (nzchar(collection_id)) {
    coll_out <- tryCatch(
      query_collections_get(collection_id = collection_id, client_id = client_id),
      error = function(e) list(ok = FALSE, error = e$message)
    )
    if (!isTRUE(coll_out$ok)) {
      return(query_api_error(
        sprintf("collection '%s' not found or inaccessible: %s",
                collection_id, coll_out$error %||% "unknown error"),
        decks = list()
      ))
    }
    # Build a name -> total_quantity map (case-insensitive).
    coll_rows <- coll_out$rows %||% list()
    coll_qty <- list()
    for (row in coll_rows) {
      nm <- tolower(trimws(as.character(row$name %||% "")))
      if (!nzchar(nm)) next
      qty <- suppressWarnings(as.integer(row$quantity %||% 1L))
      if (!is.finite(qty) || qty < 1L) qty <- 1L
      coll_qty[[nm]] <- (coll_qty[[nm]] %||% 0L) + qty
    }
    coll_names <- names(coll_qty)
    if (length(coll_names) == 0L) {
      return(query_api_error(
        sprintf("collection '%s' is empty", collection_id),
        decks = list()
      ))
    }
    # Filter catalog to owned cards only (commander override applied later).
    catalog <- Filter(function(c) {
      nm <- tolower(trimws(as.character(c$name %||% "")))
      nm %in% coll_names
    }, catalog)
    # Store the per-name quantity cap; the mainboard builder will consult it.
    collection_copy_cap <- coll_qty
    using_collection <- TRUE
  }

  # Per-deck random config -------------------------------------------------
  #
  # When format, colors, or archetypes are left unconfigured, each deck gets
  # an independently drawn random configuration instead of being a variant of
  # a single shared build.  Format "random" triggers format randomisation;
  # empty colors trigger random color combo; empty archetypes trigger random
  # archetype selection.  A user-supplied commander overrides color/archetype
  # draws because the commander already constrains those dimensions.

  format_is_free     <- format_name == "random"
  colors_are_free    <- length(color_filter) == 0L && !nzchar(user_commander)
  archetypes_are_free <- length(archetype_filter) == 0L
  any_free           <- format_is_free || colors_are_free || archetypes_are_free

  if (any_free) {
    arch_keys <- names(query_synergy_archetype_registry())

    rand_decks <- list()
    for (i in seq_len(variant_count)) {
      var_format_name <- if (format_is_free) .deck_random_format() else format_name
      var_format_spec <- .deck_generator_format_spec(var_format_name)
      var_colors      <- if (colors_are_free) .deck_random_colors() else color_filter
      var_archetypes  <- if (archetypes_are_free) .deck_random_archetype(arch_keys) else archetype_filter

      result <- tryCatch(
        .deck_resolve_and_build(
          catalog            = catalog,
          format_spec        = var_format_spec,
          color_filter       = var_colors,
          archetype_filter   = var_archetypes,
          user_commander     = user_commander,
          collection_copy_cap = collection_copy_cap,
          registry           = registry,
          pool_keys          = pool_keys,
          variant_seed       = i * 17L,
          progress_callback  = progress_callback,
          progress_min       = 10 + (i - 1) * 85 / variant_count,
          progress_max       = 10 + i * 85 / variant_count
        ),
        error = function(e) list(ok = FALSE, error = conditionMessage(e))
      )
      if (!isTRUE(result$ok)) next

      d <- result$deck
      d$variant                 <- i
      d$variant_format          <- var_format_name
      d$variant_format_label    <- var_format_spec$label
      d$variant_colors          <- var_colors
      d$variant_archetypes      <- var_archetypes
      d$requires_commander      <- isTRUE(var_format_spec$requires_commander)
      d$core_card_names         <- result$core_names
      rand_decks[[length(rand_decks) + 1L]] <- d
    }

    if (length(rand_decks) == 0L) {
      return(query_api_error(
        "no deck could be generated for any of the drawn configurations; try specifying at least one constraint",
        decks = list()
      ))
    }

    rand_decks <- rand_decks[order(
      vapply(rand_decks, function(d) suppressWarnings(as.numeric(d$total_score)), numeric(1)),
      decreasing = TRUE
    )]

    return(list(
      ok                = TRUE,
      randomized        = TRUE,
      format            = format_name,
      format_label      = if (format_is_free) "Al\u00e9atoire" else format_spec$label,
      requires_commander = any(vapply(rand_decks, function(d) isTRUE(d$requires_commander), logical(1))),
      using_collection  = using_collection,
      collection_id     = if (using_collection) collection_id else NULL,
      color_identity    = color_filter,
      archetype_filter  = archetype_filter,
      commander_name    = "",
      commander_id      = "",
      core_card_ids     = character(0),
      core_card_names   = character(0),
      decks             = rand_decks,
      deck_count        = length(rand_decks),
      pool_size         = length(pool_keys),
      candidate_count   = 0L
    ))
  }

  # Resolve commander/seed.
  .emit(11, "Resolving seed card")
  seed_card <- NULL
  if (nzchar(user_commander)) {
    seed_card <- query_synergy_find_card_by_id_or_name(catalog, user_commander)
    if (is.null(seed_card)) {
      return(query_api_error(
        sprintf("commander '%s' not found in catalog", user_commander),
        decks = list()
      ))
    }
  } else if (format_spec$requires_commander) {
    seed_card <- .deck_pick_commander(catalog, format_spec, color_filter,
                                      archetype_filter, registry)
    if (is.null(seed_card)) {
      return(query_api_error(
        "no legal commander candidate matches the requested colors / archetypes",
        decks = list()
      ))
    }
  } else {
    # 60-card formats: pick a top legendary or top archetype-matching anchor.
    pseudo <- .deck_pick_commander(catalog, format_spec, color_filter,
                                   archetype_filter, registry)
    if (!is.null(pseudo)) seed_card <- pseudo
  }
  if (is.null(seed_card)) {
    return(query_api_error("no seed card resolved", decks = list()))
  }

  # Score the catalog vs the seed using the existing pair scorer.
  .emit(14, "Scoring catalog")
  fixed_scoring_cb <- if (is.function(progress_callback)) {
    function(progress) {
      inner_pct <- suppressWarnings(as.numeric(progress$percent %||% 0))
      mapped <- 14 + inner_pct * 0.60
      progress$percent <- as.integer(round(mapped))
      progress_callback(progress)
    }
  } else NULL
  anchor_payload <- list(
    card_name = query_api_scalar(seed_card$id, default = query_api_scalar(seed_card$name, default = "")),
    format = format_name,
    max_results = 500L,
    max_groups = 1L,
    include_spellbook = FALSE,
    include_lotusnoir = FALSE,
    color_identity = color_filter,
    archetype_filter = archetype_filter,
    archetype_filter_strict = FALSE
  )
  scoring <- tryCatch(
    query_synergy_find_in_catalog(anchor_payload, catalog, progress_callback = fixed_scoring_cb),
    error = function(e) list(ok = FALSE, error = conditionMessage(e))
  )
  if (!isTRUE(scoring$ok)) {
    return(query_api_error(scoring$error %||% "scoring failed", decks = list()))
  }

  matches <- query_synergy_to_list(scoring$best_matches)

  # Build candidate records: {card, normalized, score}. We need to look up
  # the catalog card by id to access full normalization.
  cat_by_id <- new.env(parent = emptyenv(), hash = TRUE)
  for (c in catalog) {
    cid <- query_api_scalar(c$id, default = "")
    if (nzchar(cid)) assign(cid, c, envir = cat_by_id)
  }
  scored_candidates <- lapply(matches, function(m) {
    cid <- query_api_scalar(m$id, default = "")
    cname <- query_api_scalar(m$name, default = "")
    cname_key <- tolower(cname)
    if (length(pool_keys) > 0L && !(cname_key %in% pool_keys)) return(NULL)
    full_card <- if (nzchar(cid) && exists(cid, envir = cat_by_id, inherits = FALSE)) {
      get(cid, envir = cat_by_id, inherits = FALSE)
    } else {
      m
    }
    norm <- tryCatch(
      query_synergy_normalize_card_cached(full_card, registry = registry),
      error = function(e) NULL
    )
    if (is.null(norm)) return(NULL)
    # Color identity filter for singleton/strict formats already applied by the
    # find pipeline, but pool restriction may have removed entries.
    list(card = full_card, normalized = norm, score = suppressWarnings(as.numeric(m$score)))
  })
  scored_candidates <- Filter(Negate(is.null), scored_candidates)

  # Supplement: the synergy pipeline caps at ~200 results so utility roles
  # (ramp, removal, draw, non-basic lands) are often underrepresented. Sweep
  # the catalog for format-legal, color-legal cards that fit those roles and
  # add them with score 0; the greedy builder will pick them when the synergy
  # pool runs out for that role.
  scored_ids <- vapply(scored_candidates, function(s) query_api_scalar(s$card$id, default = ""), character(1))
  scored_id_env <- new.env(parent = emptyenv(), hash = TRUE)
  for (sid in scored_ids) if (nzchar(sid)) assign(sid, TRUE, envir = scored_id_env)

  needs_role <- c("land", "ramp", "card_draw", "removal")
  supplement_seen <- new.env(parent = emptyenv(), hash = TRUE)
  for (c in catalog) {
    cid <- query_api_scalar(c$id, default = "")
    if (!nzchar(cid)) next
    if (exists(cid, envir = scored_id_env, inherits = FALSE)) next
    if (exists(cid, envir = supplement_seen, inherits = FALSE)) next
    # Color identity check (subset of requested colors).
    if (length(color_filter) > 0L) {
      ci <- query_synergy_to_vector(c$color_identity)
      if (length(setdiff(ci, color_filter)) > 0L) next
    }
    # Format legality (lenient: only honour format if helper exists).
    if (!query_synergy_card_legal_in_format(c, format_spec$key, FALSE)) next
    norm <- tryCatch(
      query_synergy_normalize_card_cached(c, registry = registry),
      error = function(e) NULL
    )
    if (is.null(norm)) next
    roles <- .deck_card_roles(c, norm)
    if (!any(needs_role %in% roles)) next
    # Skip basic lands here; they're added as filler at the end if needed.
    if ("basic_land" %in% roles) next
    assign(cid, TRUE, envir = supplement_seen)
    scored_candidates[[length(scored_candidates) + 1L]] <- list(
      card = c,
      normalized = norm,
      score = 0
    )
  }

  if (length(scored_candidates) < format_spec$mainboard_size / 2L) {
    return(query_api_error(
      sprintf(
        "only %d candidates after filtering (need ~%d for a coherent build); broaden the color or archetype filter",
        length(scored_candidates), format_spec$mainboard_size
      ),
      decks = list()
    ))
  }

  # Coherence rescoring: instead of building from raw pair scores (which
  # produce an agglomerate of cards that each individually pair with the
  # commander), pick a small "core" of cards that align with both the
  # commander and the requested archetypes, derive the deck DNA from that
  # core, and re-score every candidate by how well it FEEDS / EATS / REWARDS
  # the deck DNA. This forces the build to revolve around a single coherent
  # game plan rather than scattered synergies.
  rescore <- .deck_rescore_for_coherence(
    seed = seed_card,
    scored_candidates = scored_candidates,
    registry = registry,
    archetype_filter = archetype_filter,
    core_size = 8L
  )
  scored_candidates <- rescore$scored
  core_ids <- rescore$core_ids %||% character(0)
  core_names <- vapply(core_ids, function(cid) {
    if (!nzchar(cid)) return("")
    hit <- Filter(function(s) identical(query_api_scalar(s$card$id, default = ""), cid), scored_candidates)
    if (length(hit) == 0L) return("")
    query_api_scalar(hit[[1]]$card$name, default = "")
  }, character(1))
  core_names <- core_names[nzchar(core_names)]

  # Normalize the commander once for downstream matchup analysis (we need
  # a normalized record to detect the deck's own archetype mix).
  seed_normalized_for_matchups <- tryCatch(
    query_synergy_normalize_card_cached(seed_card, registry = registry),
    error = function(e) NULL
  )

  # Build N variants. Each variant excludes a few top picks from prior decks
  # to force diversification.
  decks <- list()
  excluded_ids <- character(0)
  for (i in seq_len(variant_count)) {
    pct_build_start <- as.integer(round(76 + (i - 1) * 20 / variant_count))
    pct_combo       <- as.integer(round(76 + (i - 0.6) * 20 / variant_count))
    pct_score       <- as.integer(round(76 + (i - 0.3) * 20 / variant_count))
    .emit(pct_build_start, sprintf("Building variant %d/%d", i, variant_count))
    deck <- .deck_build_mainboard(
      seed = seed_card,
      scored_candidates = scored_candidates,
      format_spec = format_spec,
      excluded_ids = excluded_ids,
      variant_seed = i * 17L,
      collection_copy_cap = collection_copy_cap
    )

    card_names_for_combo <- vapply(deck$cards, function(c) c$name %||% "", character(1))
    if (format_spec$requires_commander) {
      card_names_for_combo <- c(card_names_for_combo, query_api_scalar(seed_card$name, default = ""))
    }
    .emit(pct_combo, sprintf("Detecting combos for variant %d", i))
    combos <- .deck_detect_combos(card_names_for_combo)

    .emit(pct_score, sprintf("Scoring variant %d", i))
    score_info <- .deck_score_assembly(deck, format_spec, archetype_filter)
    if (length(combos) > 0L) {
      score_info$score_modifiers$spellbook_combos <- list(
        amount = as.integer(min(15L, length(combos) * 5L)),
        combo_count = length(combos)
      )
      score_info$total_score <- as.integer(min(100L, score_info$score_base +
        sum(vapply(score_info$score_modifiers, function(m) as.integer(m$amount), integer(1)))))
    }

    # Matchup analysis: how this assembled deck fares vs each known archetype.
    matchups <- tryCatch(
      query_synergy_deck_matchups(
        commander_normalized = seed_normalized_for_matchups,
        mainboard_records = deck$cards,
        user_archetypes = archetype_filter,
        top_n = 4L
      ),
      error = function(e) {
        list(
          self_archetypes = character(0),
          self_archetype_labels = character(0),
          strong_against = list(),
          weak_against = list(),
          tool_counts = list()
        )
      }
    )

    decks[[length(decks) + 1L]] <- list(
      variant = i,
      commander = list(
        id = seed_card$id,
        name = seed_card$name,
        type_line = seed_card$type_line,
        mana_cost = seed_card$mana_cost,
        oracle_text = seed_card$oracle_text,
        color_identity = query_synergy_to_vector(seed_card$color_identity),
        scryfall_id = query_api_scalar(seed_card$scryfall_id, default = "")
      ),
      mainboard = lapply(deck$cards, function(c) {
        list(
          id = c$id,
          name = c$name,
          type_line = c$type_line,
          mana_cost = c$mana_cost,
          cmc = c$cmc,
          slot_role = c$slot_role,
          score = round(suppressWarnings(as.numeric(c$score %||% 0)), 1),
          pair_score = round(suppressWarnings(as.numeric(c$pair_score %||% 0)), 1),
          coherence_score = round(suppressWarnings(as.numeric(c$coherence_score %||% 0)), 1),
          is_core = isTRUE(c$is_core),
          curve_bucket = c$curve_bucket,
          is_basic_filler = isTRUE(c$is_basic_filler)
        )
      }),
      role_counts = deck$role_counts,
      role_target = deck$role_target,
      curve_counts = deck$curve_counts,
      curve_target = deck$curve_target,
      detected_combos = combos,
      matchups = matchups,
      score_base = score_info$score_base,
      score_modifiers = score_info$score_modifiers,
      total_score = score_info$total_score,
      score = score_info$total_score
    )

    # For next variant: exclude top 8 high-impact picks from this deck so the
    # next build cannot reuse them and must explore alternatives.
    nonland <- Filter(function(c) !isTRUE("land" %in% c$roles) && !isTRUE(c$is_basic_filler), deck$cards)
    nonland <- nonland[order(
      vapply(nonland, function(c) suppressWarnings(as.numeric(c$score %||% 0)), numeric(1)),
      decreasing = TRUE
    )]
    top_picks <- vapply(utils::head(nonland, 8L), function(c) c$id %||% "", character(1))
    excluded_ids <- unique(c(excluded_ids, top_picks))
  }

  # Sort decks by total_score (best first).
  decks <- decks[order(
    vapply(decks, function(d) suppressWarnings(as.numeric(d$total_score)), numeric(1)),
    decreasing = TRUE
  )]

  list(
    ok = TRUE,
    format = format_name,
    format_label = format_spec$label,
    requires_commander = isTRUE(format_spec$requires_commander),
    using_collection = using_collection,
    collection_id = if (using_collection) collection_id else NULL,
    color_identity = color_filter,
    archetype_filter = archetype_filter,
    commander_name = query_api_scalar(seed_card$name, default = ""),
    commander_id = query_api_scalar(seed_card$id, default = ""),
    core_card_ids = core_ids,
    core_card_names = core_names,
    decks = decks,
    deck_count = length(decks),
    pool_size = length(pool_keys),
    candidate_count = length(scored_candidates)
  )
}

# Exposed for background job runner: parse already-decoded payload list,
# run the generator with a progress_callback.
query_synergy_deck_generate_from_payload <- function(payload = list(),
                                                     progress_callback = NULL) {
  tryCatch(
    .query_synergy_deck_generate_impl(
      req           = NULL,
      data_override = payload,
      progress_callback = progress_callback
    ),
    error = function(e) {
      query_api_error(
        sprintf("deck generation failed: %s", conditionMessage(e)),
        decks = list()
      )
    }
  )
}

# Async job entry point ---------------------------------------------------
#
# Parses the request payload, writes it to disk, spawns a background Rscript
# process that runs run_deck_gen_job.R, and immediately returns a job_id so
# the frontend can poll GET /synergy/jobs/<job_id> for progress.

query_synergy_deck_generate_job <- function(req = NULL) {
  payload_out <- query_synergy_parse_payload(req)
  if (!isTRUE(payload_out$ok)) {
    return(query_api_error(payload_out$error))
  }
  data <- payload_out$data

  runner_path <- .deck_gen_job_runner_path()
  if (!nzchar(runner_path) || !file.exists(runner_path)) {
    return(query_api_error("deck generation job runner script unavailable"))
  }

  rscript_path <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  if (!file.exists(rscript_path)) {
    return(query_api_error("Rscript executable unavailable"))
  }

  job_id <- query_synergy_new_job_id()
  paths <- query_synergy_job_paths(job_id)
  repo_root <- query_synergy_detect_repo_root(runner_path, fallback_dir = getwd())

  query_synergy_write_job_json(paths$payload_file, data)
  query_synergy_write_job_json(
    paths$status_file,
    query_synergy_build_job_status(job_id = job_id, status = "queued", percent = 0L, stage = "Queued")
  )

  args <- c(
    normalizePath(runner_path, winslash = "/", mustWork = TRUE),
    "--job-id",  job_id,
    "--payload", normalizePath(paths$payload_file, winslash = "/", mustWork = TRUE),
    "--status",  normalizePath(paths$status_file,  winslash = "/", mustWork = TRUE),
    "--result",  normalizePath(paths$result_file,  winslash = "/", mustWork = FALSE),
    "--repo",    repo_root
  )

  spawn_ok <- tryCatch({
    system2(
      command  = normalizePath(rscript_path, winslash = "/", mustWork = TRUE),
      args     = args,
      wait     = FALSE,
      stdout   = FALSE,
      stderr   = FALSE
    )
    TRUE
  }, error = function(e) FALSE)

  if (!isTRUE(spawn_ok)) {
    return(query_api_error("unable to start deck generation background job"))
  }

  status_payload <- query_synergy_read_job_json(paths$status_file)
  if (!is.list(status_payload)) {
    status_payload <- query_synergy_build_job_status(job_id, status = "queued", percent = 0L, stage = "Queued")
  }
  status_payload
}

.deck_gen_job_runner_path <- function() {
  candidates <- c(
    file.path(getwd(), "inst", "jobs", "run_deck_gen_job.R"),
    file.path(getwd(), "..", "inst", "jobs", "run_deck_gen_job.R")
  )
  existing <- candidates[file.exists(candidates)]
  if (length(existing) > 0L) {
    return(normalizePath(existing[[1]], winslash = "/", mustWork = TRUE))
  }
  installed <- tryCatch(
    system.file("jobs", "run_deck_gen_job.R", package = "mtgcodex.api"),
    error = function(e) ""
  )
  if (nzchar(installed) && file.exists(installed)) {
    return(normalizePath(installed, winslash = "/", mustWork = TRUE))
  }
  ""
}
