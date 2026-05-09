#' Clamp Numeric Values to \[0, 1\]
#'
#' Clamp numeric values to the inclusive range \[0, 1\].
#'
#' @param x Numeric vector.
#'
#' @return Numeric vector with all values clamped to \[0, 1\].
#'
#' @examples
#' stopifnot(identical(clamp01(c(-1, 0.4, 3)), c(0, 0.4, 1)))
#'
#' @export
clamp01 <- function(x) {
  pmin(1, pmax(0, as.numeric(x)))
}

#' Cosine Similarity for Sparse Named Vectors
#'
#' Compute cosine similarity for sparse named numeric vectors.
#' If either vector has zero norm or if there is no overlapping feature name,
#' the result is 0.
#'
#' @param a Named numeric vector.
#' @param b Named numeric vector.
#'
#' @return Numeric scalar in \[0, 1\].
#'
#' @examples
#' a <- c(sac = 1, etb = 0.5)
#' b <- c(etb = 1, draw = 0.2)
#' cs <- cosine_similarity_sparse(a, b)
#' stopifnot(cs >= 0, cs <= 1)
#'
#' @export
cosine_similarity_sparse <- function(a, b) {
  a_vec <- .as_sparse_named_numeric(a)
  b_vec <- .as_sparse_named_numeric(b)

  if (length(a_vec) == 0L || length(b_vec) == 0L) {
    return(0)
  }

  common <- intersect(names(a_vec), names(b_vec))
  if (length(common) == 0L) {
    return(0)
  }

  dot <- sum(a_vec[common] * b_vec[common])
  norm_a <- sqrt(sum(a_vec * a_vec))
  norm_b <- sqrt(sum(b_vec * b_vec))

  if (norm_a <= 0 || norm_b <= 0) {
    return(0)
  }

  clamp01(dot / (norm_a * norm_b))
}

#' Build Feature-to-Card Index
#'
#' Build an index mapping feature names to card indices for fast candidate lookup.
#'
#' @param cards List of card objects.
#'
#' @return Named list where each entry is an integer vector of card indices.
#'
#' @examples
#' cards <- bridge_synergy_example_cards()
#' idx <- build_feature_index(cards)
#' stopifnot(is.list(idx), "sac" %in% names(idx))
#'
#' @export
build_feature_index <- function(cards) {
  .validate_cards(cards)

  nz_per_card <- lapply(seq_along(cards), function(i) {
    feats <- .card_features(cards[[i]])
    names(feats)[feats != 0]
  })

  feat_vec <- unlist(nz_per_card, use.names = FALSE)
  if (length(feat_vec) == 0L) return(list())

  idx_vec  <- rep(seq_along(cards), lengths(nz_per_card))
  groups   <- split(idx_vec, feat_vec)
  feature_index <- lapply(groups, function(idxs) sort(unique(as.integer(idxs))))
  feature_index[sort(names(feature_index))]
}

#' Candidate Card Set from Shared Features
#'
#' Build the deterministic candidate set of cards sharing at least one non-zero
#' feature with a given sparse feature vector.
#'
#' @param u_features Named numeric vector for the query card features.
#' @param feature_index Output of [build_feature_index()].
#' @param max_candidates Maximum number of candidates to keep.
#'
#' @return Integer vector of candidate card indices.
#'
#' @examples
#' cards <- bridge_synergy_example_cards()
#' idx <- build_feature_index(cards)
#' cands <- candidate_set(cards[[1]]$features, idx, max_candidates = 100L)
#' stopifnot(is.integer(cands))
#'
#' @export
candidate_set <- function(u_features, feature_index, max_candidates = 2000L) {
  feats <- .as_sparse_named_numeric(u_features)
  if (length(feats) == 0L || length(feature_index) == 0L) {
    return(integer(0))
  }

  max_candidates <- .as_count(max_candidates, default = 2000L)
  if (max_candidates <= 0L) {
    return(integer(0))
  }

  nz_feats <- names(feats)[feats != 0]
  if (length(nz_feats) == 0L) return(integer(0))

  buckets   <- Filter(function(b) length(b) > 0L, feature_index[nz_feats])
  if (length(buckets) == 0L) return(integer(0))

  candidates <- sort(unique(as.integer(unlist(buckets, use.names = FALSE))))
  if (length(candidates) > max_candidates) candidates <- candidates[seq_len(max_candidates)]
  as.integer(candidates)
}

#' Top-k Neighbor Cards for One Parent Card
#'
#' Compute top-k weighted neighbors for one card index, with deterministic tie
#' breaking by ascending card index.
#'
#' @param u_idx Integer index of the parent card in `cards`.
#' @param cards List of cards.
#' @param feature_index Output of [build_feature_index()].
#' @param top_k Maximum number of neighbors to return.
#' @param options List of options:
#' `enforce_color_identity`, `max_candidates`.
#'
#' @return List with `indices`, `weights`, and `candidates_considered`.
#'
#' @examples
#' cards <- bridge_synergy_example_cards()
#' idx <- build_feature_index(cards)
#' nn <- top_k_neighbors(1L, cards, idx, top_k = 5L, options = list(max_candidates = 100L))
#' stopifnot(is.list(nn), length(nn$indices) == length(nn$weights))
#'
#' @export
top_k_neighbors <- function(
    u_idx,
    cards,
    feature_index,
    top_k = 50L,
    options = list()) {
  .validate_cards(cards)
  opts <- .merge_bridge_options(options)
  top_k <- .as_count(top_k, default = 50L)
  if (top_k <= 0L) {
    return(list(indices = integer(0), weights = numeric(0), candidates_considered = 0L))
  }

  if (!is.numeric(u_idx) || length(u_idx) != 1L || is.na(u_idx)) {
    stop("`u_idx` must be one valid integer index.")
  }
  u_idx <- as.integer(u_idx)
  if (u_idx < 1L || u_idx > length(cards)) {
    stop("`u_idx` is out of range.")
  }

  candidates <- candidate_set(
    u_features = .card_features(cards[[u_idx]]),
    feature_index = feature_index,
    max_candidates = opts$max_candidates
  )
  if (length(candidates) == 0L) {
    return(list(indices = integer(0), weights = numeric(0), candidates_considered = 0L))
  }

  candidates <- candidates[candidates != u_idx]
  candidates <- as.integer(candidates)
  candidate_count <- length(candidates)
  if (candidate_count == 0L) {
    return(list(indices = integer(0), weights = numeric(0), candidates_considered = 0L))
  }

  u_card <- cards[[u_idx]]
  weights <- vapply(
    candidates,
    function(v_idx) {
      v_card <- cards[[v_idx]]
      legal <- .card_constraints(v_card)$legal
      if (!is.null(legal) && length(legal) > 0L && !is.na(legal[[1]]) && !isTRUE(legal[[1]])) {
        return(0)
      }
      if (isTRUE(opts$enforce_color_identity)) {
        u_colors <- .card_colors(u_card)
        v_colors <- .card_colors(v_card)
        if (length(v_colors) > 0L && !all(v_colors %in% u_colors)) {
          return(0)
        }
      }
      clamp01(cosine_similarity_sparse(.card_features(u_card), .card_features(v_card)))
    },
    numeric(1)
  )

  positive <- which(weights > 0)
  if (length(positive) == 0L) {
    return(list(
      indices = integer(0),
      weights = numeric(0),
      candidates_considered = as.integer(candidate_count)
    ))
  }

  candidates <- candidates[positive]
  weights <- weights[positive]

  ord <- order(-weights, candidates)
  candidates <- candidates[ord]
  weights <- weights[ord]

  if (length(candidates) > top_k) {
    candidates <- candidates[seq_len(top_k)]
    weights <- weights[seq_len(top_k)]
  }

  list(
    indices = as.integer(candidates),
    weights = as.numeric(weights),
    candidates_considered = as.integer(candidate_count)
  )
}
#' Propagate Hierarchical Synergy Scores from a Seed
#'
#' Expand from a seed card over `depth_N` levels. At each level, each frontier
#' node emits to its weighted top-k neighbors and contributions are damped by
#' `gamma^depth`.
#'
#' @param seed_id Seed card id.
#' @param cards List of cards.
#' @param depth_N Propagation depth (>= 1).
#' @param top_k Top-k neighbors per parent and frontier cap per level.
#' @param gamma Depth damping factor in \[0, 1\].
#' @param options List of options:
#' `enforce_color_identity`, `unique_nodes`, `max_candidates`.
#'
#' @return List with `scores`, `parents`, and `stats`.
#'
#' @examples
#' cards <- bridge_synergy_example_cards()
#' out <- propagate_scores("card_A", cards, depth_N = 2L, top_k = 5L, gamma = 0.65)
#' stopifnot(is.numeric(out$scores), is.character(out$parents))
#'
#' @export
propagate_scores <- function(
    seed_id,
    cards,
    depth_N = 3L,
    top_k = 50L,
    gamma = 0.65,
    options = list()) {
  ids <- .validate_cards(cards)
  opts <- .merge_bridge_options(options)

  if (!is.character(seed_id) || length(seed_id) != 1L || !nzchar(seed_id)) {
    stop("`seed_id` must be a non-empty character scalar.")
  }
  seed_idx <- match(seed_id, ids)
  if (is.na(seed_idx)) {
    stop("`seed_id` not found in `cards`.")
  }

  depth_N <- .as_count(depth_N, default = 3L)
  top_k <- .as_count(top_k, default = 50L)
  if (depth_N <= 0L) {
    stop("`depth_N` must be >= 1.")
  }
  if (top_k <= 0L) {
    stop("`top_k` must be >= 1.")
  }
  if (!is.numeric(gamma) || length(gamma) != 1L || is.na(gamma) || gamma < 0 || gamma > 1) {
    stop("`gamma` must be a numeric scalar in [0, 1].")
  }

  feature_index <- opts$feature_index
  if (is.null(feature_index)) {
    feature_index <- build_feature_index(cards)
  }

  n_cards <- length(cards)
  score_total <- setNames(numeric(n_cards), ids)
  score_current <- numeric(n_cards)
  score_current[seed_idx] <- 1

  parents_idx <- rep(NA_integer_, n_cards)
  visited <- rep(FALSE, n_cards)
  if (isTRUE(opts$unique_nodes)) {
    visited[seed_idx] <- TRUE
  }

  frontier <- as.integer(seed_idx)

  frontier_sizes <- integer(depth_N)
  expanded_nodes <- integer(depth_N)
  candidates_considered <- integer(depth_N)
  emitted_children <- integer(depth_N)
  level_total_scores <- numeric(depth_N)

  last_depth <- 0L
  for (depth in seq_len(depth_N)) {
    if (length(frontier) == 0L) {
      break
    }
    last_depth <- depth

    score_level <- numeric(n_cards)
    best_contrib <- rep(-Inf, n_cards)

    expanded_this <- 0L
    candidates_this <- 0L

    for (p_idx in frontier) {
      expanded_this <- expanded_this + 1L

      neigh <- top_k_neighbors(
        u_idx = p_idx,
        cards = cards,
        feature_index = feature_index,
        top_k = top_k,
        options = opts
      )
      candidates_this <- candidates_this + neigh$candidates_considered
      child_idx <- neigh$indices
      if (length(child_idx) == 0L) {
        next
      }

      contrib <- score_current[p_idx] * neigh$weights * (gamma^depth)

      if (isTRUE(opts$unique_nodes)) {
        keep <- !visited[child_idx]
        child_idx <- child_idx[keep]
        contrib <- contrib[keep]
      }
      if (length(child_idx) == 0L) {
        next
      }

      for (j in seq_along(child_idx)) {
        c_idx <- child_idx[j]
        c_val <- contrib[j]
        score_level[c_idx] <- score_level[c_idx] + c_val

        if (c_val > best_contrib[c_idx] ||
          (is.finite(c_val) && is.finite(best_contrib[c_idx]) && abs(c_val - best_contrib[c_idx]) <= 1e-12 &&
            (is.na(parents_idx[c_idx]) || p_idx < parents_idx[c_idx]))) {
          best_contrib[c_idx] <- c_val
          parents_idx[c_idx] <- p_idx
        }
      }
    }

    non_zero <- which(score_level > 0)
    emitted_children[depth] <- length(non_zero)
    level_total_scores[depth] <- sum(score_level[non_zero])
    expanded_nodes[depth] <- expanded_this
    candidates_considered[depth] <- candidates_this

    if (length(non_zero) == 0L) {
      frontier_sizes[depth] <- 0L
      break
    }

    ord <- order(-score_level[non_zero], ids[non_zero])
    next_frontier <- non_zero[ord]
    if (length(next_frontier) > top_k) {
      next_frontier <- next_frontier[seq_len(top_k)]
    }

    frontier <- as.integer(next_frontier)
    frontier_sizes[depth] <- length(frontier)

    score_current <- numeric(n_cards)
    score_current[frontier] <- score_level[frontier]
    score_total <- score_total + score_level

    if (isTRUE(opts$unique_nodes)) {
      visited[non_zero] <- TRUE
    }
  }

  score_total[seed_idx] <- 0
  keep <- which(score_total > 0)
  if (length(keep) > 0L) {
    ord_scores <- order(-score_total[keep], ids[keep])
    keep <- keep[ord_scores]
  }
  scores <- score_total[keep]
  names(scores) <- ids[keep]

  parents <- setNames(rep(NA_character_, n_cards), ids)
  known_parent <- which(!is.na(parents_idx))
  if (length(known_parent) > 0L) {
    parents[known_parent] <- ids[parents_idx[known_parent]]
  }

  list(
    scores = scores,
    parents = parents,
    stats = list(
      seed_id = seed_id,
      depth_requested = depth_N,
      depth_executed = as.integer(last_depth),
      frontier_sizes = frontier_sizes,
      expanded_nodes = expanded_nodes,
      candidates_considered = candidates_considered,
      emitted_children = emitted_children,
      level_total_scores = level_total_scores,
      unique_nodes = isTRUE(opts$unique_nodes),
      top_k = top_k,
      gamma = gamma
    )
  )
}

#' Compute Bridge Scores Between Two Seed Cards
#'
#' Run hierarchical propagation for seed A and seed B, then compute bridge scores
#' by score product (`scoreA * scoreB`).
#'
#' @param cards List of cards.
#' @param A_id Seed A id.
#' @param B_id Seed B id.
#' @param depth_N Depth for both propagations.
#' @param top_k Top-k expansion parameter.
#' @param gamma Damping factor.
#' @param topN Number of top bridges to return.
#' @param options Options list passed to propagation.
#'
#' @return List with `bridges` data.frame, `propA`, and `propB`.
#'
#' @examples
#' cards <- bridge_synergy_example_cards()
#' b <- compute_bridge(cards, "card_A", "card_B", depth_N = 3L, top_k = 6L)
#' stopifnot(is.data.frame(b$bridges))
#'
#' @export
compute_bridge <- function(
    cards,
    A_id,
    B_id,
    depth_N = 3L,
    top_k = 50L,
    gamma = 0.65,
    topN = 30L,
    options = list()) {
  .validate_cards(cards)
  topN <- .as_count(topN, default = 30L)
  if (topN <= 0L) {
    stop("`topN` must be >= 1.")
  }

  opts <- .merge_bridge_options(options)
  feature_index <- build_feature_index(cards)
  opts$feature_index <- feature_index

  propA <- propagate_scores(
    seed_id = A_id,
    cards = cards,
    depth_N = depth_N,
    top_k = top_k,
    gamma = gamma,
    options = opts
  )
  propB <- propagate_scores(
    seed_id = B_id,
    cards = cards,
    depth_N = depth_N,
    top_k = top_k,
    gamma = gamma,
    options = opts
  )

  scoreA <- propA$scores
  scoreB <- propB$scores
  all_ids <- sort(unique(c(names(scoreA), names(scoreB))))

  if (length(all_ids) == 0L) {
    bridges <- data.frame(
      id = character(0),
      bridge_score = numeric(0),
      scoreA = numeric(0),
      scoreB = numeric(0),
      stringsAsFactors = FALSE
    )
    return(list(bridges = bridges, propA = propA, propB = propB))
  }

  alignedA <- setNames(numeric(length(all_ids)), all_ids)
  alignedB <- setNames(numeric(length(all_ids)), all_ids)
  alignedA[names(scoreA)] <- scoreA
  alignedB[names(scoreB)] <- scoreB

  bridge_score <- alignedA * alignedB
  if (A_id %in% names(bridge_score)) {
    bridge_score[A_id] <- 0
  }
  if (B_id %in% names(bridge_score)) {
    bridge_score[B_id] <- 0
  }

  keep <- which(bridge_score > 0)
  if (length(keep) == 0L) {
    bridges <- data.frame(
      id = character(0),
      bridge_score = numeric(0),
      scoreA = numeric(0),
      scoreB = numeric(0),
      stringsAsFactors = FALSE
    )
    return(list(bridges = bridges, propA = propA, propB = propB))
  }

  ord <- order(-bridge_score[keep], all_ids[keep])
  keep <- keep[ord]
  if (length(keep) > topN) {
    keep <- keep[seq_len(topN)]
  }

  bridges <- data.frame(
    id = all_ids[keep],
    bridge_score = as.numeric(bridge_score[keep]),
    scoreA = as.numeric(alignedA[keep]),
    scoreB = as.numeric(alignedB[keep]),
    stringsAsFactors = FALSE
  )

  list(
    bridges = bridges,
    propA = propA,
    propB = propB
  )
}
#' Reconstruct an Explainable Seed-to-Target Chain
#'
#' Reconstruct a chain from `seed_id` to `target_id` by following parent pointers.
#' Returns an empty vector if seed is not reached, if a loop is detected, or if
#' max length is exceeded.
#'
#' @param parents_map Named character vector (id -> parent_id).
#' @param seed_id Seed id.
#' @param target_id Target id.
#' @param max_len Maximum chain length.
#'
#' @return Character vector of ids in order `seed -> ... -> target`, or empty.
#'
#' @examples
#' parents <- c(A = NA, B = "A", C = "B")
#' ch <- reconstruct_chain(parents, "A", "C", max_len = 5L)
#' stopifnot(identical(ch, c("A", "B", "C")))
#'
#' @export
reconstruct_chain <- function(parents_map, seed_id, target_id, max_len = 6L) {
  if (is.null(parents_map) || is.null(names(parents_map))) {
    stop("`parents_map` must be a named character vector.")
  }
  if (!is.character(seed_id) || length(seed_id) != 1L || !nzchar(seed_id)) {
    stop("`seed_id` must be a non-empty character scalar.")
  }
  if (!is.character(target_id) || length(target_id) != 1L || !nzchar(target_id)) {
    stop("`target_id` must be a non-empty character scalar.")
  }
  max_len <- .as_count(max_len, default = 6L)
  if (max_len <= 0L) {
    return(character(0))
  }

  current <- target_id
  chain_rev <- character(0)
  seen <- character(0)

  repeat {
    chain_rev <- c(chain_rev, current)
    if (identical(current, seed_id)) {
      return(rev(chain_rev))
    }
    if (length(chain_rev) >= max_len) {
      return(character(0))
    }
    if (current %in% seen) {
      return(character(0))
    }
    seen <- c(seen, current)

    parent <- parents_map[[current]]
    if (is.null(parent) || is.na(parent) || !nzchar(parent)) {
      return(character(0))
    }
    current <- parent
  }
}

#' Build Card Packages from Bridge Chains
#'
#' Build deck idea packages from bridge chains. For each bridge, package cards
#' include the union of `chainA` and `chainB` plus optional support cards ranked
#' by `scoreA + scoreB`.
#'
#' @param bridges Bridges data.frame (must contain `id`).
#' @param chains List of chain objects (`bridge_id`, `chainA`, `chainB`).
#' @param scoreA Named numeric scores from seed A propagation.
#' @param scoreB Named numeric scores from seed B propagation.
#' @param K Number of packages to return.
#' @param support_k Number of support cards to append.
#' @param exclude_ids Card ids that cannot be added as support cards.
#'
#' @return List of package objects.
#'
#' @examples
#' cards <- bridge_synergy_example_cards()
#' rec <- compute_bridge_recommendations(cards, "card_A", "card_B")
#' pk <- build_packages(rec$bridges, rec$chains, rec$debug$scoreA, rec$debug$scoreB, K = 2L)
#' stopifnot(is.list(pk))
#'
#' @export
build_packages <- function(
    bridges,
    chains,
    scoreA,
    scoreB,
    K = 5L,
    support_k = 2L,
    exclude_ids = character()) {
  if (!is.data.frame(bridges) || !"id" %in% colnames(bridges)) {
    stop("`bridges` must be a data.frame with column `id`.")
  }
  if (!is.list(chains)) {
    stop("`chains` must be a list.")
  }

  K <- .as_count(K, default = 5L)
  support_k <- .as_count(support_k, default = 2L)

  chain_by_bridge <- list()
  if (length(chains) > 0L) {
    for (i in seq_along(chains)) {
      item <- chains[[i]]
      bridge_id <- item$bridge_id
      if (is.character(bridge_id) && length(bridge_id) == 1L && nzchar(bridge_id)) {
        chain_by_bridge[[bridge_id]] <- item
      }
    }
  }

  score_ids <- sort(unique(c(names(scoreA), names(scoreB))))
  support_score <- setNames(numeric(length(score_ids)), score_ids)
  if (length(scoreA) > 0L) {
    support_score[names(scoreA)] <- support_score[names(scoreA)] + scoreA
  }
  if (length(scoreB) > 0L) {
    support_score[names(scoreB)] <- support_score[names(scoreB)] + scoreB
  }

  bridge_ids <- as.character(bridges$id)
  if (length(bridge_ids) > K) {
    bridge_ids <- bridge_ids[seq_len(K)]
  }

  packages <- vector("list", length(bridge_ids))
  for (i in seq_along(bridge_ids)) {
    bridge_id <- bridge_ids[i]
    chain_obj <- chain_by_bridge[[bridge_id]]
    chainA <- character(0)
    chainB <- character(0)
    if (!is.null(chain_obj)) {
      chainA <- as.character(chain_obj$chainA)
      chainB <- as.character(chain_obj$chainB)
    }

    base_cards <- unique(c(chainA, chainB))
    support_cards <- character(0)

    if (support_k > 0L && length(score_ids) > 0L) {
      excluded <- unique(c(exclude_ids, bridge_id, base_cards))
      candidates <- setdiff(score_ids, excluded)
      if (length(candidates) > 0L) {
        ord <- order(-support_score[candidates], candidates)
        ranked <- candidates[ord]
        ranked <- ranked[support_score[ranked] > 0]
        if (length(ranked) > support_k) {
          ranked <- ranked[seq_len(support_k)]
        }
        support_cards <- ranked
      }
    }

    package_cards <- unique(c(base_cards, support_cards))
    packages[[i]] <- list(
      bridge_id = bridge_id,
      cards = package_cards,
      chainA = chainA,
      chainB = chainB
    )
  }

  packages
}

#' High-level Bridge Synergy Recommendations
#'
#' Compute bridge cards, explainable chains, and package suggestions between two
#' seed cards.
#'
#' @param cards List of cards.
#' @param A_id Seed A id.
#' @param B_id Seed B id.
#' @param depth_N Propagation depth.
#' @param top_k Neighbor and frontier cap.
#' @param gamma Damping factor.
#' @param topN Number of bridge cards to keep.
#' @param topChains Number of explainable chains to reconstruct.
#' @param topPackages Number of packages to build.
#' @param options Options list. Defaults:
#' `enforce_color_identity = FALSE`, `unique_nodes = TRUE`,
#' `max_candidates = 2000L`, `max_chain_len = 6L`, `support_k = 2L`.
#'
#' @return List with `bridges`, `chains`, `packages`, and `debug`.
#'
#' @examples
#' cards <- bridge_synergy_example_cards()
#' rec <- compute_bridge_recommendations(cards, "card_A", "card_B")
#' stopifnot(is.data.frame(rec$bridges), is.list(rec$chains), is.list(rec$packages))
#'
#' @export
compute_bridge_recommendations <- function(
    cards,
    A_id,
    B_id,
    depth_N = 3L,
    top_k = 50L,
    gamma = 0.65,
    topN = 30L,
    topChains = 5L,
    topPackages = 5L,
    options = list(
      enforce_color_identity = FALSE,
      unique_nodes = TRUE,
      max_candidates = 2000L,
      max_chain_len = 6L
    )) {
  ids <- .validate_cards(cards)
  topChains <- .as_count(topChains, default = 5L)
  topPackages <- .as_count(topPackages, default = 5L)

  opts <- .merge_bridge_options(options)
  bridge_payload <- compute_bridge(
    cards = cards,
    A_id = A_id,
    B_id = B_id,
    depth_N = depth_N,
    top_k = top_k,
    gamma = gamma,
    topN = topN,
    options = opts
  )

  id_to_name <- setNames(vapply(cards, .card_name, character(1)), ids)
  bridges <- bridge_payload$bridges
  if (nrow(bridges) > 0L) {
    bridge_names <- id_to_name[bridges$id]
    bridges <- data.frame(
      id = bridges$id,
      name = as.character(bridge_names),
      bridge_score = bridges$bridge_score,
      scoreA = bridges$scoreA,
      scoreB = bridges$scoreB,
      stringsAsFactors = FALSE
    )
  } else {
    bridges <- data.frame(
      id = character(0),
      name = character(0),
      bridge_score = numeric(0),
      scoreA = numeric(0),
      scoreB = numeric(0),
      stringsAsFactors = FALSE
    )
  }

  n_chain <- min(topChains, nrow(bridges))
  chains <- vector("list", n_chain)
  for (i in seq_len(n_chain)) {
    bridge_id <- bridges$id[i]
    chains[[i]] <- list(
      bridge_id = bridge_id,
      chainA = reconstruct_chain(
        parents_map = bridge_payload$propA$parents,
        seed_id = A_id,
        target_id = bridge_id,
        max_len = opts$max_chain_len
      ),
      chainB = reconstruct_chain(
        parents_map = bridge_payload$propB$parents,
        seed_id = B_id,
        target_id = bridge_id,
        max_len = opts$max_chain_len
      )
    )
  }

  packages <- build_packages(
    bridges = bridges,
    chains = chains,
    scoreA = bridge_payload$propA$scores,
    scoreB = bridge_payload$propB$scores,
    K = topPackages,
    support_k = opts$support_k,
    exclude_ids = c(A_id, B_id)
  )

  list(
    bridges = bridges,
    chains = chains,
    packages = packages,
    debug = list(
      seedA_stats = bridge_payload$propA$stats,
      seedB_stats = bridge_payload$propB$stats,
      scoreA = bridge_payload$propA$scores,
      scoreB = bridge_payload$propB$scores,
      params = list(
        A_id = A_id,
        B_id = B_id,
        depth_N = depth_N,
        top_k = top_k,
        gamma = gamma,
        topN = topN,
        topChains = topChains,
        topPackages = topPackages,
        options = opts
      ),
      counts = list(
        cards = length(cards),
        bridges = nrow(bridges),
        chains = length(chains),
        packages = length(packages)
      )
    )
  )
}

#' Resolve A + n*k + B Bridge Equations
#'
#' Build candidate bridge packages between two seed cards, then re-rank them
#' against known synergy references such as Commander Spellbook or curated
#' Scryfall-derived packages.
#'
#' Each known reference is a list with at least a `cards` field and optional
#' metadata such as `source`, `label`, and `weight`.
#'
#' @param cards List of cards.
#' @param A_id Seed A id.
#' @param B_id Seed B id.
#' @param n Maximum number of bridge cards `k` to keep between A and B.
#' @param depth_N Propagation depth.
#' @param top_k Neighbor and frontier cap.
#' @param gamma Damping factor.
#' @param topN Number of bridge cards to keep.
#' @param known_synergies List of known synergy references. Each item should
#' contain `cards`.
#' @param reference_bonus Bonus applied to exact known matches.
#' @param near_bonus Bonus applied to near matches.
#' @param novel_penalty Mild penalty applied when no known match is found.
#' @param missing_card_penalty Penalty per missing card for near matches.
#' @param max_missing_cards Maximum missing cards allowed for a near match.
#' @param options Options forwarded to [compute_bridge_recommendations()].
#'
#' @return List with `candidates`, `references`, and the raw `bridge_payload`.
#'
#' @examples
#' cards <- bridge_synergy_example_cards()
#' refs <- list(
#'   list(
#'     label = "Known glue package",
#'     source = "spellbook",
#'     cards = c("card_A", "card_glue", "card_B"),
#'     weight = 1
#'   )
#' )
#' out <- resolve_bridge_equation(cards, "card_A", "card_B", n = 2L, known_synergies = refs)
#' stopifnot(is.data.frame(out$candidates))
#'
#' @export
resolve_bridge_equation <- function(
    cards,
    A_id,
    B_id,
    n = 2L,
    depth_N = 3L,
    top_k = 50L,
    gamma = 0.65,
    topN = 20L,
    known_synergies = list(),
    reference_bonus = 0.30,
    near_bonus = 0.18,
    novel_penalty = 0.05,
    missing_card_penalty = 0.03,
    max_missing_cards = 2L,
    options = list(
      enforce_color_identity = FALSE,
      unique_nodes = TRUE,
      max_candidates = 2000L,
      max_chain_len = 6L,
      support_k = 2L
    )) {
  ids <- .validate_cards(cards)
  if (!A_id %in% ids) {
    stop("`A_id` not found in cards.")
  }
  if (!B_id %in% ids) {
    stop("`B_id` not found in cards.")
  }

  n <- .as_count(n, default = 2L)
  max_missing_cards <- .as_count(max_missing_cards, default = 2L)
  opts <- .merge_bridge_options(options)

  top_packages <- max(10L, .as_count(topN, default = 20L))
  bridge_payload <- compute_bridge_recommendations(
    cards = cards,
    A_id = A_id,
    B_id = B_id,
    depth_N = depth_N,
    top_k = top_k,
    gamma = gamma,
    topN = topN,
    topChains = top_packages,
    topPackages = top_packages,
    options = opts
  )

  id_to_name <- setNames(vapply(cards, .card_name, character(1)), ids)
  refs <- .normalize_known_synergies(known_synergies)

  packages <- bridge_payload$packages
  if (length(packages) == 0L) {
    return(list(
      candidates = data.frame(
        seedA_id = character(0),
        seedA_name = character(0),
        seedB_id = character(0),
        seedB_name = character(0),
        bridge_id = character(0),
        bridge_name = character(0),
        bridge_cards = character(0),
        bridge_card_names = character(0),
        total_cards = character(0),
        total_card_names = character(0),
        structural_score = numeric(0),
        reference_adjustment = numeric(0),
        total_score = numeric(0),
        reference_state = character(0),
        reference_source = character(0),
        reference_label = character(0),
        missing_cards = character(0),
        missing_card_names = character(0),
        stringsAsFactors = FALSE
      ),
      references = refs,
      bridge_payload = bridge_payload
    ))
  }

  bridge_score_map <- setNames(
    bridge_payload$bridges$bridge_score,
    bridge_payload$bridges$id
  )

  rows <- vector("list", length(packages))
  row_count <- 0L
  for (pkg in packages) {
    bridge_cards <- unique(c(as.character(pkg$bridge_id), as.character(pkg$cards)))
    bridge_cards <- bridge_cards[nzchar(bridge_cards)]
    bridge_cards <- setdiff(bridge_cards, c(A_id, B_id))
    if (n > 0L && length(bridge_cards) > n) {
      bridge_cards <- bridge_cards[seq_len(n)]
    }
    total_ids <- unique(c(A_id, bridge_cards, B_id))
    bridge_id <- as.character(pkg$bridge_id[[1]])
    structural_score <- unname(bridge_score_map[[bridge_id]])
    if (!is.finite(structural_score)) {
      structural_score <- 0
    }

    ref_match <- .match_known_synergy(
      candidate_ids = total_ids,
      references = refs,
      max_missing_cards = max_missing_cards
    )

    reference_state <- ref_match$state
    reference_source <- ref_match$source
    reference_label <- ref_match$label
    missing_ids <- ref_match$missing_cards
    missing_names <- id_to_name[missing_ids]
    missing_names[is.na(missing_names)] <- missing_ids[is.na(missing_names)]

    reference_adjustment <- switch(
      reference_state,
      exact = reference_bonus * ref_match$weight,
      near = near_bonus * ref_match$weight - missing_card_penalty * length(missing_ids),
      -novel_penalty
    )
    total_score <- structural_score + reference_adjustment

    row_count <- row_count + 1L
    rows[[row_count]] <- data.frame(
      seedA_id = A_id,
      seedA_name = id_to_name[[A_id]],
      seedB_id = B_id,
      seedB_name = id_to_name[[B_id]],
      bridge_id = bridge_id,
      bridge_name = id_to_name[[bridge_id]],
      bridge_cards = paste(bridge_cards, collapse = " | "),
      bridge_card_names = paste(id_to_name[bridge_cards], collapse = " | "),
      total_cards = paste(total_ids, collapse = " | "),
      total_card_names = paste(id_to_name[total_ids], collapse = " | "),
      structural_score = as.numeric(structural_score),
      reference_adjustment = as.numeric(reference_adjustment),
      total_score = as.numeric(total_score),
      reference_state = as.character(reference_state),
      reference_source = as.character(reference_source),
      reference_label = as.character(reference_label),
      missing_cards = paste(missing_ids, collapse = " | "),
      missing_card_names = paste(missing_names, collapse = " | "),
      stringsAsFactors = FALSE
    )
  }

  candidates <- do.call(rbind, rows[seq_len(row_count)])
  ord <- order(
    -candidates$total_score,
    -candidates$structural_score,
    candidates$bridge_name,
    candidates$bridge_cards
  )
  candidates <- candidates[ord, , drop = FALSE]
  rownames(candidates) <- NULL

  list(
    candidates = candidates,
    references = refs,
    bridge_payload = bridge_payload
  )
}
#' Example Cards for Bridge Synergy
#'
#' Create a deterministic toy dataset (14 cards) where seed A and seed B share
#' few direct features and a glue card links both sides.
#'
#' @return List of cards.
#'
#' @examples
#' cards <- bridge_synergy_example_cards()
#' stopifnot(length(cards) >= 10L)
#'
#' @export
bridge_synergy_example_cards <- function() {
  list(
    .make_card(
      id = "card_A",
      name = "Seed A Aristocrat",
      features = c(sac = 1.0, etb = 0.7, token = 0.6, aristocrat = 1.0),
      constraints = list(colors = c("B", "R"), legal = TRUE, format = "commander")
    ),
    .make_card(
      id = "card_B",
      name = "Seed B Reanimator",
      features = c(graveyard = 1.0, draw = 0.8, reanimate = 1.0, discard = 0.7),
      constraints = list(colors = c("B", "G"), legal = TRUE, format = "commander")
    ),
    .make_card(
      id = "card_glue",
      name = "Glue Engine",
      features = c(etb = 0.6, graveyard = 0.8, draw = 0.6, sac = 0.4),
      constraints = list(colors = c("B"), legal = TRUE, format = "commander")
    ),
    .make_card(
      id = "card_sac_outlet",
      name = "Free Sac Outlet",
      features = c(sac = 1.0, aristocrat = 0.8),
      constraints = list(colors = c("B"), legal = TRUE, format = "commander")
    ),
    .make_card(
      id = "card_token_maker",
      name = "Token Crafter",
      features = c(token = 1.0, etb = 0.6),
      constraints = list(colors = c("R"), legal = TRUE, format = "commander")
    ),
    .make_card(
      id = "card_etb_value",
      name = "ETB Value",
      features = c(etb = 1.0, draw = 0.3),
      constraints = list(colors = c("B", "R"), legal = TRUE, format = "commander")
    ),
    .make_card(
      id = "card_death_draw",
      name = "Death Trigger Draw",
      features = c(sac = 0.7, draw = 0.9, graveyard = 0.5),
      constraints = list(colors = c("B"), legal = TRUE, format = "commander")
    ),
    .make_card(
      id = "card_reanimator",
      name = "Reanimator Piece",
      features = c(reanimate = 1.0, graveyard = 0.9, discard = 0.4),
      constraints = list(colors = c("B"), legal = TRUE, format = "commander")
    ),
    .make_card(
      id = "card_looter",
      name = "Loot and Fill",
      features = c(discard = 1.0, draw = 1.0, graveyard = 0.4),
      constraints = list(colors = c("U", "B"), legal = TRUE, format = "commander")
    ),
    .make_card(
      id = "card_recursion",
      name = "Recursion Value",
      features = c(graveyard = 0.8, etb = 0.5, reanimate = 0.7),
      constraints = list(colors = c("B", "G"), legal = TRUE, format = "commander")
    ),
    .make_card(
      id = "card_mill_engine",
      name = "Mill Engine",
      features = c(graveyard = 1.0, draw = 0.4),
      constraints = list(colors = c("U", "B"), legal = TRUE, format = "commander")
    ),
    .make_card(
      id = "card_ramp",
      name = "Mana Ramp",
      features = c(ramp = 1.0, mana = 0.9),
      constraints = list(colors = c("G"), legal = TRUE, format = "commander")
    ),
    .make_card(
      id = "card_burn",
      name = "Burn Spell",
      features = c(burn = 1.0, combat = 0.6),
      constraints = list(colors = c("R"), legal = TRUE, format = "commander")
    ),
    .make_card(
      id = "card_illegal_power",
      name = "Banned Combo Piece",
      features = c(sac = 1.0, graveyard = 1.0, draw = 1.0),
      constraints = list(colors = c("B"), legal = FALSE, format = "commander")
    )
  )
}

#' Run Self-tests for Bridge Synergy Pipeline
#'
#' Execute deterministic sanity checks with `stopifnot`.
#'
#' @return `TRUE` (invisibly) when all checks pass.
#'
#' @examples
#' stopifnot(isTRUE(run_bridge_synergy_selftest()))
#'
#' @export
run_bridge_synergy_selftest <- function() {
  cos_val <- cosine_similarity_sparse(
    c(sac = 1, etb = 0.5),
    c(etb = 1, draw = 0.3)
  )
  stopifnot(cos_val >= 0, cos_val <= 1)

  linear_cards <- list(
    .make_card(
      id = "seed",
      name = "Seed",
      features = c(core = 1),
      constraints = list(colors = c("B"), legal = TRUE)
    ),
    .make_card(
      id = "mid",
      name = "Middle",
      features = c(core = 1),
      constraints = list(colors = c("B"), legal = TRUE)
    ),
    .make_card(
      id = "end",
      name = "End",
      features = c(core = 1),
      constraints = list(colors = c("B"), legal = TRUE)
    )
  )
  linear_prop <- propagate_scores(
    seed_id = "seed",
    cards = linear_cards,
    depth_N = 2L,
    top_k = 1L,
    gamma = 0.5,
    options = list(unique_nodes = TRUE, max_candidates = 100L)
  )
  lvl <- linear_prop$stats$level_total_scores
  stopifnot(length(lvl) >= 2L)
  stopifnot(lvl[2] < lvl[1])

  cards <- bridge_synergy_example_cards()
  rec <- compute_bridge_recommendations(
    cards = cards,
    A_id = "card_A",
    B_id = "card_B",
    depth_N = 3L,
    top_k = 8L,
    gamma = 0.65,
    topN = 10L,
    topChains = 5L,
    topPackages = 5L,
    options = list(
      enforce_color_identity = FALSE,
      unique_nodes = TRUE,
      max_candidates = 2000L,
      max_chain_len = 6L,
      support_k = 2L
    )
  )
  stopifnot("card_glue" %in% head(rec$bridges$id, 5L))

  rec2 <- compute_bridge_recommendations(
    cards = cards,
    A_id = "card_A",
    B_id = "card_B",
    depth_N = 3L,
    top_k = 8L,
    gamma = 0.65,
    topN = 10L,
    topChains = 5L,
    topPackages = 5L,
    options = list(
      enforce_color_identity = FALSE,
      unique_nodes = TRUE,
      max_candidates = 2000L,
      max_chain_len = 6L,
      support_k = 2L
    )
  )
  stopifnot(identical(rec$bridges$id, rec2$bridges$id))
  stopifnot(identical(rec$chains, rec2$chains))
  stopifnot(identical(rec$packages, rec2$packages))

  eq <- resolve_bridge_equation(
    cards = cards,
    A_id = "card_A",
    B_id = "card_B",
    n = 2L,
    known_synergies = list(
      list(
        label = "Known example package",
        source = "spellbook",
        cards = c("card_A", "card_glue", "card_B"),
        weight = 1
      )
    )
  )
  stopifnot(is.data.frame(eq$candidates))
  stopifnot(nrow(eq$candidates) >= 1L)
  stopifnot(eq$candidates$reference_state[[1]] %in% c("exact", "near", "novel"))

  TRUE
}

.make_card <- function(id, name, features, constraints = list()) {
  list(
    id = as.character(id),
    name = as.character(name),
    features = .as_sparse_named_numeric(features),
    constraints = constraints
  )
}

.validate_cards <- function(cards) {
  if (!is.list(cards) || length(cards) == 0L) {
    stop("`cards` must be a non-empty list.")
  }

  ids <- vapply(
    cards,
    function(card) {
      if (!is.list(card) || is.null(card$id)) {
        stop("Each card must be a list with at least `id`.")
      }
      as.character(card$id[[1]])
    },
    character(1)
  )
  if (any(!nzchar(ids))) {
    stop("Each card `id` must be non-empty.")
  }
  if (anyDuplicated(ids) > 0L) {
    stop("Card ids must be unique.")
  }

  invisible(ids)
}

.card_name <- function(card) {
  name <- card$name
  if (is.null(name)) {
    return(as.character(card$id[[1]]))
  }
  as.character(name[[1]])
}

.card_features <- function(card) {
  .as_sparse_named_numeric(card$features)
}

.card_constraints <- function(card) {
  constraints <- card$constraints
  if (is.null(constraints) || !is.list(constraints)) {
    return(list())
  }
  constraints
}
.card_colors <- function(card) {
  constraints <- .card_constraints(card)
  colors <- constraints$colors
  if (is.null(colors)) {
    return(character(0))
  }
  vals <- toupper(trimws(as.character(colors)))
  vals <- vals[nzchar(vals)]
  unique(vals)
}

.as_sparse_named_numeric <- function(x) {
  if (is.null(x) || length(x) == 0L) {
    return(setNames(numeric(0), character(0)))
  }

  vals <- as.numeric(x)
  nms <- names(x)
  if (is.null(nms)) {
    stop("Sparse feature vectors must be named numeric vectors.")
  }

  keep <- !is.na(vals) & nzchar(nms)
  vals <- vals[keep]
  nms <- nms[keep]
  if (length(vals) == 0L) {
    return(setNames(numeric(0), character(0)))
  }

  grouped <- tapply(vals, nms, sum)
  out <- as.numeric(grouped)
  names(out) <- names(grouped)
  out
}

.as_count <- function(x, default) {
  if (is.null(x) || length(x) != 1L || is.na(x) || !is.finite(x)) {
    return(as.integer(default))
  }
  as.integer(max(0, floor(x)))
}

.merge_bridge_options <- function(options) {
  defaults <- list(
    enforce_color_identity = FALSE,
    unique_nodes = TRUE,
    max_candidates = 2000L,
    max_chain_len = 6L,
    support_k = 2L,
    feature_index = NULL
  )
  if (is.null(options)) {
    options <- list()
  }
  if (!is.list(options)) {
    stop("`options` must be a list.")
  }

  merged <- defaults
  for (nm in names(options)) {
    merged[[nm]] <- options[[nm]]
  }

  merged$enforce_color_identity <- isTRUE(merged$enforce_color_identity)
  merged$unique_nodes <- !identical(merged$unique_nodes, FALSE)
  merged$max_candidates <- .as_count(merged$max_candidates, default = 2000L)
  merged$max_chain_len <- .as_count(merged$max_chain_len, default = 6L)
  merged$support_k <- .as_count(merged$support_k, default = 2L)

  merged
}

.scalar_text <- function(value, default = "") {
  if (is.null(value)) {
    return(default)
  }
  raw <- as.character(value)
  if (length(raw) == 0L || is.na(raw[[1]])) {
    return(default)
  }
  picked <- trimws(raw[[1]])
  if (!nzchar(picked)) {
    return(default)
  }
  picked
}

.normalize_known_synergies <- function(known_synergies) {
  if (is.null(known_synergies) || length(known_synergies) == 0L) {
    return(list())
  }
  if (!is.list(known_synergies)) {
    stop("`known_synergies` must be a list.")
  }

  out <- list()
  out_count <- 0L
  for (item in known_synergies) {
    if (is.null(item$cards)) {
      next
    }
    cards <- unique(as.character(item$cards))
    cards <- cards[nzchar(cards)]
    if (length(cards) == 0L) {
      next
    }

    weight <- suppressWarnings(as.numeric(item$weight[[1]]))
    if (length(weight) == 0L || !is.finite(weight[[1]]) || weight[[1]] <= 0) {
      weight <- 1
    } else {
      weight <- weight[[1]]
    }

    out_count <- out_count + 1L
    out[[out_count]] <- list(
      cards = sort(cards),
      source = .scalar_text(item$source, default = "unknown"),
      label = .scalar_text(item$label, default = sprintf("ref_%s", out_count)),
      weight = weight
    )
  }

  out
}

.match_known_synergy <- function(candidate_ids, references, max_missing_cards = 2L) {
  candidate_ids <- sort(unique(as.character(candidate_ids)))
  candidate_ids <- candidate_ids[nzchar(candidate_ids)]
  if (length(candidate_ids) == 0L || length(references) == 0L) {
    return(list(
      state = "novel",
      source = "",
      label = "",
      missing_cards = character(0),
      weight = 1
    ))
  }

  best <- list(
    state = "novel",
    source = "",
    label = "",
    missing_cards = character(0),
    weight = 1,
    overlap = -1
  )

  for (ref in references) {
    ref_cards <- ref$cards
    if (setequal(candidate_ids, ref_cards)) {
      return(list(
        state = "exact",
        source = ref$source,
        label = ref$label,
        missing_cards = character(0),
        weight = ref$weight
      ))
    }

    missing_cards <- setdiff(ref_cards, candidate_ids)
    extra_cards <- setdiff(candidate_ids, ref_cards)
    overlap <- length(intersect(candidate_ids, ref_cards))
    if (overlap <= 0L) {
      next
    }

    if (length(missing_cards) <= max_missing_cards && length(extra_cards) == 0L) {
      if (overlap > best$overlap) {
        best <- list(
          state = "near",
          source = ref$source,
          label = ref$label,
          missing_cards = missing_cards,
          weight = ref$weight,
          overlap = overlap
        )
      }
    }
  }

  best$overlap <- NULL
  best
}
