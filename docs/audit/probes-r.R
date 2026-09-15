# Regression probes. Not executed locally during implementation: R unavailable.
# Run from the repository root: Rscript docs/audit/probes-r.R
# Assertions cover corrected behavior; printed observations retain model limitations.
source("R/bridge_synergy.R")
card <- function(id, features, colors = character()) {
  list(id = id, name = id, features = features,
       constraints = list(colors = colors, legal = TRUE))
}

# Visited nodes do not consume the next level's top-k budget.
complete <- list(card("seed", c(x = 1)), card("mid", c(x = 1)), card("end", c(x = 1)))
p <- propagate_scores("seed", complete, depth_N = 2, top_k = 1, gamma = 0.5)
stopifnot("end" %in% names(p$scores), p$stats$level_total_scores[2] > 0)
print(list(visited_top_k = p$scores))

# Every traversed edge receives one gamma factor, giving geometric damping.
chain <- list(card("seed", c(x = 1)), card("mid", c(x = 1, y = 1)), card("end", c(y = 1)))
p <- propagate_scores("seed", chain, depth_N = 2, top_k = 2, gamma = 0.5)
stopifnot(isTRUE(all.equal(unname(p$scores["end"]), 0.5 * 0.5^2)))
print(list(depth_two_score = p$scores["end"]))

# The seed/deck color identity remains the global constraint along a path.
chain[[1]]$constraints$colors <- c("U", "B")
chain[[2]]$constraints$colors <- "B"
chain[[3]]$constraints$colors <- "U"
p <- propagate_scores("seed", chain, depth_N = 2, top_k = 2,
                      options = list(enforce_color_identity = TRUE))
stopifnot("end" %in% names(p$scores))
print(list(parent_color_filter = p$scores))

# Parent pointers remain acyclic when nodes may be revisited.
cycle_cards <- list(card("seed", c(x = 1, z = 10)),
                   card("mid", c(x = 1, y = 1)), card("end", c(y = 1)))
p <- propagate_scores("seed", cycle_cards, depth_N = 3, top_k = 2,
                      options = list(unique_nodes = FALSE))
ch <- reconstruct_chain(p$parents, "seed", "end")
stopifnot(p$scores["end"] > 0, length(ch) > 0,
          identical(ch[[1]], "seed"), identical(ch[[length(ch)]], "end"),
          !anyDuplicated(ch), is.na(p$parents[["seed"]]))
print(list(cyclic_parents = p$parents, reconstructed_chain = ch))

# Candidate limiting retains the strongest candidate rather than the first index.
pool <- list(card("seed", c(x = 1)), card("weak", c(x = 1, y = 10)), card("strong", c(x = 1)))
nn <- top_k_neighbors(1, pool, build_feature_index(pool), top_k = 1,
                      options = list(max_candidates = 2))
stopifnot(identical(nn$indices, 3L))
print(list(positional_candidate = pool[[nn$indices]]$id))

# A package always contains its own bridge, even without displayed chains.
rec <- compute_bridge_recommendations(bridge_synergy_example_cards(), "card_A", "card_B",
                                      topChains = 0, topPackages = 1)
stopifnot(length(rec$packages) == 1,
          rec$packages[[1]]$bridge_id %in% rec$packages[[1]]$cards)
print(list(package_without_bridge = rec$packages[[1]]))

# Scaling keeps cosine similarity finite for very large finite vectors.
cs <- cosine_similarity_sparse(c(x = 1e200), c(x = 1e200))
stopifnot(identical(cs, 1))
print(list(overflow_cosine = cs))

# Scores sum incoming paths and are not probabilities, even with unique_nodes.
converge <- c(list(card("seed", c(x = 1))),
              lapply(1:4, function(i) card(paste0("mid", i), c(x = 1, y = 1))),
              list(card("end", c(y = 1))))
p <- propagate_scores("seed", converge, depth_N = 2, top_k = 10, gamma = 1)
stopifnot(isTRUE(all.equal(unname(p$scores["end"]), 2)))
print(list(converging_paths_score = p$scores["end"]))
