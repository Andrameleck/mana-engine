card_fixture <- function(id, features, colors = character()) {
  list(
    id = id,
    name = id,
    features = features,
    constraints = list(colors = colors, legal = TRUE)
  )
}

test_that("cosine similarity remains stable for large finite values", {
  expect_equal(cosine_similarity_sparse(c(x = 1e200), c(x = 1e200)), 1)
  expect_error(
    cosine_similarity_sparse(c(x = Inf), c(x = 1)),
    "finite numeric values"
  )
})

test_that("visited nodes do not consume the propagation width", {
  cards <- list(
    card_fixture("seed", c(x = 1)),
    card_fixture("mid", c(x = 1)),
    card_fixture("end", c(x = 1))
  )
  result <- propagate_scores(
    "seed",
    cards,
    depth_N = 2L,
    top_k = 1L,
    gamma = 0.5,
    options = list(unique_nodes = TRUE)
  )
  expect_true("end" %in% names(result$scores))
})

test_that("damping is geometric with traversed path length", {
  cards <- list(
    card_fixture("seed", c(x = 1)),
    card_fixture("mid", c(x = 1, y = 1)),
    card_fixture("end", c(y = 1))
  )
  result <- propagate_scores("seed", cards, depth_N = 2L, top_k = 2L, gamma = 0.5)
  expect_equal(unname(result$scores["end"]), 0.5 * 0.5^2)
})

test_that("color identity is constrained by the seed for the whole search", {
  cards <- list(
    card_fixture("seed", c(x = 1), c("U", "B")),
    card_fixture("mid", c(x = 1, y = 1), "B"),
    card_fixture("end", c(y = 1), "U")
  )
  result <- propagate_scores(
    "seed",
    cards,
    depth_N = 2L,
    top_k = 2L,
    options = list(enforce_color_identity = TRUE)
  )
  expect_true("end" %in% names(result$scores))
})

test_that("packages contain their bridge without displayed chains", {
  result <- compute_bridge_recommendations(
    bridge_synergy_example_cards(),
    "card_A",
    "card_B",
    topChains = 0L,
    topPackages = 1L
  )
  expect_length(result$packages, 1L)
  expect_true(result$packages[[1]]$bridge_id %in% result$packages[[1]]$cards)
})

test_that("the propagation root never receives a parent", {
  cards <- list(
    card_fixture("seed", c(x = 1, z = 10)),
    card_fixture("mid", c(x = 1, y = 1)),
    card_fixture("end", c(y = 1))
  )
  result <- propagate_scores(
    "seed", cards, depth_N = 3L, top_k = 2L,
    options = list(unique_nodes = FALSE)
  )
  expect_true(is.na(result$parents[["seed"]]))
  chain <- reconstruct_chain(result$parents, "seed", "end")
  expect_equal(chain, c("seed", "mid", "end"))
})
