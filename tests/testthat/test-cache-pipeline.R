test_that("catalog cache key changes when middle card content changes", {
  catalog_a <- list(
    list(id = "seed", name = "Seed", oracle_text = "Draw a card.", color_identity = c("U")),
    list(id = "middle-a", name = "Middle A", oracle_text = "Mill two cards.", color_identity = c("U")),
    list(id = "tail", name = "Tail", oracle_text = "Gain 1 life.", color_identity = c("W"))
  )
  catalog_b <- list(
    list(id = "seed", name = "Seed", oracle_text = "Draw a card.", color_identity = c("U")),
    list(id = "middle-b", name = "Middle B", oracle_text = "Create a token.", color_identity = c("W")),
    list(id = "tail", name = "Tail", oracle_text = "Gain 1 life.", color_identity = c("W"))
  )

  key_a <- mtgcodex.api:::query_synergy_catalog_cache_key(catalog_a, source = "catalog")
  key_b <- mtgcodex.api:::query_synergy_catalog_cache_key(catalog_b, source = "catalog")

  expect_false(identical(key_a, key_b))
})

test_that("canonical catalog cache key can use cheap file signatures", {
  catalog <- list(
    list(id = "seed", name = "Seed", oracle_text = "Draw a card.", color_identity = c("U")),
    list(id = "tail", name = "Tail", oracle_text = "Gain 1 life.", color_identity = c("W"))
  )

  key_a <- mtgcodex.api:::query_synergy_catalog_cache_key(
    catalog,
    source = "scryfall_oracle_cards",
    source_signature = "100::200"
  )
  key_b <- mtgcodex.api:::query_synergy_catalog_cache_key(
    catalog,
    source = "scryfall_oracle_cards",
    source_signature = "100::200"
  )
  key_c <- mtgcodex.api:::query_synergy_catalog_cache_key(
    catalog,
    source = "scryfall_oracle_cards",
    source_signature = "100::201"
  )

  expect_identical(key_a, key_b)
  expect_false(identical(key_a, key_c))
})

test_that("staged pipeline scans full catalog but deep scores only top k", {
  catalog <- c(
    list(list(
      id = "seed",
      name = "Ledger Saint",
      oracle_text = "Whenever you draw a card, gain 1 life.",
      colors = c("U"),
      color_identity = c("U"),
      cmc = 3,
      legalities = list(commander = "legal")
    )),
    lapply(seq_len(8), function(i) {
      list(
        id = paste0("noise-", i),
        name = paste("Noise", i),
        oracle_text = "",
        colors = c("G"),
        color_identity = c("G"),
        cmc = 3 + i,
        legalities = list(commander = "legal")
      )
    }),
    list(
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
  )

  out <- mtgcodex.api:::query_synergy_find_in_catalog(
    list(card_name = "Ledger Saint", format = "commander", max_results = 5, top_k = 3, package_top_n = 2),
    catalog
  )

  expect_true(isTRUE(out$ok))
  expect_identical(out$pipeline$catalog_size, length(catalog))
  expect_identical(out$pipeline$candidate_filter_count, length(catalog) - 1L)
  expect_gte(out$pipeline$candidate_filter_count, 3L)
  expect_identical(out$pipeline$cheap_scan_count, out$pipeline$candidate_filter_count)
  expect_true(isTRUE(out$pipeline$full_catalog_light_scan))
  expect_identical(out$pipeline$cheap_scan_cap_used, out$pipeline$candidate_filter_count)
  expect_identical(out$pipeline$deep_score_count, 3L)
  expect_identical(out$pipeline$top_k_used, 3L)
  expect_lte(out$pipeline$package_candidate_count, 2L)
  expect_identical(out$pipeline$package_eval_count, out$pipeline$package_candidate_count)
  expect_true(all(c(
    "precompute_load_ms",
    "candidate_filter_ms",
    "cheap_scan_ms",
    "top_k_selection_ms",
    "deep_scoring_ms",
    "explanation_assembly_ms",
    "bucket_assembly_ms",
    "package_detection_ms",
    "response_assembly_ms",
    "total_ms"
  ) %in% names(out$timings)))
  expect_true(is.list(out$pipeline$stage_metrics))
})

test_that("staged candidate generation keeps indirect engine candidates alive", {
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
      id = "noise-a",
      name = "Timber Filler",
      oracle_text = "Target land becomes a creature until end of turn.",
      colors = c("G"),
      color_identity = c("G"),
      cmc = 3,
      legalities = list(commander = "legal")
    ),
    list(
      id = "noise-b",
      name = "Stone Filler",
      oracle_text = "Create a tapped colorless land token.",
      colors = c("C"),
      color_identity = c("C"),
      cmc = 4,
      legalities = list(commander = "legal")
    )
  )

  out <- mtgcodex.api:::query_synergy_find_in_catalog(
    list(card_name = "Ledger Saint", format = "commander", max_results = 4, top_k = 2, package_top_n = 2),
    catalog
  )

  result_names <- vapply(out$best_matches, function(entry) entry$name, character(1))
  expect_true("Rooftop Conniver" %in% result_names)
  expect_true(any(vapply(out$buckets$indirect_engines$results, function(entry) identical(entry$name, "Rooftop Conniver"), logical(1))))
})

test_that("expensive quality axes are not executed during cheap full-catalog scan", {
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
      id = "noise",
      name = "Grey Noise",
      oracle_text = "Gain 1 life.",
      colors = c("W"),
      color_identity = c("W"),
      cmc = 2,
      legalities = list(commander = "legal")
    )
  )

  out <- mtgcodex.api:::query_synergy_find_in_catalog(
    list(card_name = "Ledger Saint", format = "commander", max_results = 4, top_k = 2, package_top_n = 2),
    catalog
  )

  stage_metrics <- out$pipeline$stage_metrics
  metric_value <- function(stage_key, metric_key) {
    stage_bucket <- stage_metrics[[stage_key]]
    if (!is.list(stage_bucket)) {
      return(0L)
    }
    raw <- stage_bucket[[metric_key]]
    if (is.null(raw) || length(raw) == 0L) {
      return(0L)
    }
    value <- suppressWarnings(as.integer(raw))
    if (length(value) == 0L || !is.finite(value) || is.na(value)) {
      return(0L)
    }
    value
  }

  expect_identical(metric_value("cheap_scan", "shell_dependency_axis_calls"), 0L)
  expect_identical(metric_value("cheap_scan", "reliability_axis_calls"), 0L)
  expect_gte(metric_value("deep_scoring", "shell_dependency_axis_calls"), 1L)
  expect_gte(metric_value("deep_scoring", "reliability_axis_calls"), 1L)
})

test_that("explicit cheap scan cap limits lightweight scan breadth when requested", {
  catalog <- c(
    list(list(
      id = "seed",
      name = "Ledger Saint",
      oracle_text = "Whenever you draw a card, gain 1 life.",
      colors = c("U"),
      color_identity = c("U"),
      cmc = 3,
      legalities = list(commander = "legal")
    )),
    lapply(seq_len(24), function(i) {
      list(
        id = paste0("broad-", i),
        name = paste("Broad", i),
        oracle_text = "Gain 1 life.",
        colors = c("W"),
        color_identity = c("W"),
        cmc = 2,
        legalities = list(commander = "legal")
      )
    }),
    list(
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
      )
    )
  )

  out <- mtgcodex.api:::query_synergy_find_in_catalog(
    list(
      card_name = "Ledger Saint",
      format = "commander",
      max_results = 4,
      top_k = 2,
      cheap_scan_cap = 8,
      package_top_n = 2
    ),
    catalog
  )

  result_names <- vapply(out$best_matches, function(entry) entry$name, character(1))
  # New contract: cheap_scan_cap only truncates the non-indexed residue;
  # indexed candidates always survive so role-aware reverse synergy matches
  # are never silently dropped (see query_synergy_engine.R).
  expect_lte(out$pipeline$cheap_scan_count, out$pipeline$candidate_filter_count)
  expect_identical(out$pipeline$cheap_scan_count, out$pipeline$cheap_scan_cap_used)
  expect_true("Thought Current" %in% result_names)
})

test_that("group search stays constrained to the reduced local candidate graph", {
  catalog <- c(
    list(list(
      id = "seed",
      name = "Archive Judge",
      oracle_text = "Whenever you draw a card, gain 1 life.",
      colors = c("U"),
      color_identity = c("U"),
      cmc = 3,
      legalities = list(commander = "legal")
    )),
    lapply(seq_len(16), function(i) {
      list(
        id = paste0("noise-", i),
        name = paste("Noise", i),
        oracle_text = "Gain 1 life.",
        colors = c("W"),
        color_identity = c("W"),
        cmc = 2,
        legalities = list(commander = "legal")
      )
    }),
    list(
      list(
        id = "setup",
        name = "Frantic Research",
        oracle_text = "Draw two cards, then discard two cards.",
        colors = c("U"),
        color_identity = c("U"),
        cmc = 2,
        legalities = list(commander = "legal")
      ),
      list(
        id = "converter",
        name = "Lore Recycler",
        oracle_text = "Whenever you discard a card, draw a card.",
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
  )

  out <- mtgcodex.api:::query_synergy_find_in_catalog(
    list(
      card_name = "Archive Judge",
      format = "commander",
      max_results = 6,
      top_k = 4,
      package_top_n = 4,
      max_groups = 3,
      max_group_size = 4,
      max_group_paths = 20
    ),
    catalog
  )

  expect_true(isTRUE(out$ok))
  expect_lte(out$pipeline$package_eval_count, 4L)
  expect_lte(out$pipeline$group_graph_node_count, out$pipeline$package_candidate_count + 1L)
  expect_lte(out$pipeline$group_path_count, 20L)
  expect_gte(out$pipeline$group_graph_edge_count, 0L)
  expect_lte(
    out$pipeline$group_graph_pair_count,
    (out$pipeline$package_candidate_count + 1L) * max(0L, out$pipeline$package_candidate_count)
  )
  expect_lt(out$pipeline$group_graph_pair_count, length(catalog) * max(0L, length(catalog) - 1L))
  expect_gte(out$pipeline$group_branching_cap_used, 1L)
})

test_that("precomputed catalog cache persists normalized profiles for canonical sources", {
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

  cache_dir <- file.path(tempdir(), paste0("synergy-precompute-", as.integer(Sys.time())))
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  attr(catalog, "synergy_source") <- "scryfall_oracle_cards"
  attr(catalog, "synergy_cache_key") <- mtgcodex.api:::query_synergy_catalog_cache_key(catalog, source = "scryfall_oracle_cards")

  precomputed <- mtgcodex.api:::query_synergy_get_precomputed_catalog(
    catalog = catalog,
    force_refresh = TRUE,
    cache_dir = cache_dir
  )

  paths <- mtgcodex.api:::query_synergy_cache_paths(cache_dir)
  expect_true(file.exists(paths$precomputed_rds_file))
  expect_identical(length(precomputed$normalized), length(catalog))
  expect_identical(length(precomputed$profiles), length(catalog))
  expect_true(is.list(precomputed$indexes))
})

test_that("progress callback reports backend-linked staged progress", {
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

  progress_log <- list()
  callback <- function(progress) {
    progress_log[[length(progress_log) + 1L]] <<- progress
  }

  out <- mtgcodex.api:::query_synergy_find_in_catalog(
    list(card_name = "Ledger Saint", format = "commander", max_results = 4, top_k = 2, package_top_n = 2),
    catalog,
    progress_callback = callback
  )

  expect_true(isTRUE(out$ok))
  expect_gte(length(progress_log), 5)

  percents <- vapply(progress_log, function(entry) as.integer(round(as.numeric(entry$percent))), integer(1))
  stages <- vapply(progress_log, function(entry) as.character(entry$stage), character(1))

  expect_true(all(diff(percents) >= 0))
  expect_identical(utils::tail(percents, 1), 100L)
  expect_true(any(grepl("Scanning full catalog", stages, fixed = TRUE)))
  expect_true(any(grepl("Deep scoring top candidates", stages, fixed = TRUE)))
  expect_true(any(grepl("Detecting package lines", stages, fixed = TRUE)))
})

test_that("completed job status waits until the result payload is readable", {
  jobs_dir <- file.path(tempdir(), paste0("synergy-jobs-", as.integer(Sys.time()), "-", sample.int(9999, 1)))
  mtgcodex.api:::query_synergy_jobs_dir(base_dir = jobs_dir)

  job_id <- "job-finalizing"
  paths <- mtgcodex.api:::query_synergy_job_paths(job_id)
  mtgcodex.api:::query_synergy_write_job_json(
    paths$status_file,
    mtgcodex.api:::query_synergy_build_job_status(
      job_id = job_id,
      status = "completed",
      percent = 100,
      stage = "Completed"
    )
  )

  pending <- mtgcodex.api:::query_synergy_get_job_status(job_id)
  expect_identical(pending$status, "running")
  expect_identical(pending$progress$percent, 99L)
  expect_identical(pending$progress$stage, "Finalizing result")

  mtgcodex.api:::query_synergy_write_job_json(
    paths$result_file,
    list(ok = TRUE, best_matches = list(list(id = "card-a", name = "Card A")), synergy_groups = list())
  )

  completed <- mtgcodex.api:::query_synergy_get_job_status(job_id)
  expect_identical(completed$status, "completed")
  expect_true(is.list(completed$result))
  expect_true(isTRUE(completed$result$ok))
})

