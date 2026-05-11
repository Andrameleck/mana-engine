query_synergy_cache_env <- local({
  env <- new.env(parent = emptyenv())
  env$catalog <- NULL
  env$catalog_loaded_at <- as.POSIXct(NA)
  env$catalog_source <- ""
  env$normalized_by_id <- new.env(parent = emptyenv(), hash = TRUE)
  env$catalog_cache_key <- ""
  env$precomputed_catalog <- NULL
  env$precomputed_loaded_at <- as.POSIXct(NA)
  env$precomputed_key <- ""
  env
})

query_synergy_jobs_env <- local({
  env <- new.env(parent = emptyenv())
  env$jobs_dir <- ""
  env
})

query_synergy_runtime_metrics_env <- local({
  env <- new.env(parent = emptyenv())
  env$stage <- "idle"
  env$stage_counts <- new.env(parent = emptyenv(), hash = TRUE)
  env$global_counts <- new.env(parent = emptyenv(), hash = TRUE)
  env
})

query_synergy_runtime_metrics_reset <- function() {
  env <- query_synergy_runtime_metrics_env
  env$stage <- "idle"
  if (is.environment(env$stage_counts)) {
    rm(list = ls(env$stage_counts, all.names = TRUE), envir = env$stage_counts)
  }
  if (is.environment(env$global_counts)) {
    rm(list = ls(env$global_counts, all.names = TRUE), envir = env$global_counts)
  }
  invisible(NULL)
}

query_synergy_runtime_metrics_set_stage <- function(stage = "") {
  query_synergy_runtime_metrics_env$stage <- query_api_scalar(stage, default = "unknown")
  invisible(NULL)
}

query_synergy_runtime_metrics_add <- function(metric, by = 1L, stage = NULL) {
  metric_key <- query_api_scalar(metric, default = "")
  if (!nzchar(metric_key)) {
    return(invisible(NULL))
  }

  increment <- suppressWarnings(as.integer(by))
  if (!is.finite(increment) || is.na(increment)) {
    increment <- 1L
  }
  if (increment == 0L) {
    return(invisible(NULL))
  }

  env <- query_synergy_runtime_metrics_env
  stage_key <- if (is.null(stage)) {
    query_api_scalar(env$stage, default = "unknown")
  } else {
    query_api_scalar(stage, default = "unknown")
  }

  stage_metric_key <- paste(stage_key, metric_key, sep = "::")
  stage_value <- if (exists(stage_metric_key, envir = env$stage_counts, inherits = FALSE)) {
    suppressWarnings(as.integer(get(stage_metric_key, envir = env$stage_counts, inherits = FALSE)))
  } else {
    0L
  }
  if (!is.finite(stage_value) || is.na(stage_value)) {
    stage_value <- 0L
  }
  assign(stage_metric_key, stage_value + increment, envir = env$stage_counts)

  global_value <- if (exists(metric_key, envir = env$global_counts, inherits = FALSE)) {
    suppressWarnings(as.integer(get(metric_key, envir = env$global_counts, inherits = FALSE)))
  } else {
    0L
  }
  if (!is.finite(global_value) || is.na(global_value)) {
    global_value <- 0L
  }
  assign(metric_key, global_value + increment, envir = env$global_counts)
  invisible(NULL)
}

query_synergy_runtime_metrics_mark_call <- function(metric) {
  query_synergy_runtime_metrics_add(paste0(query_api_scalar(metric, default = "metric"), "_calls"), by = 1L)
}

query_synergy_runtime_metrics_snapshot <- function() {
  env <- query_synergy_runtime_metrics_env
  stage_keys <- if (is.environment(env$stage_counts)) ls(env$stage_counts, all.names = TRUE) else character(0)
  stage_counts <- list()
  for (key in stage_keys) {
    value <- suppressWarnings(as.integer(get(key, envir = env$stage_counts, inherits = FALSE)))
    if (!is.finite(value) || is.na(value)) {
      value <- 0L
    }

    parts <- strsplit(key, "::", fixed = TRUE)[[1]]
    if (length(parts) < 2L) {
      next
    }
    stage_key <- parts[[1]]
    metric_key <- paste(parts[-1], collapse = "::")
    stage_bucket <- stage_counts[[stage_key]]
    if (!is.list(stage_bucket)) {
      stage_bucket <- list()
    }
    stage_bucket[[metric_key]] <- value
    stage_counts[[stage_key]] <- stage_bucket
  }

  list(
    current_stage = query_api_scalar(env$stage, default = "idle"),
    stage_counts = stage_counts,
    global_counts = as.list(env$global_counts, all.names = TRUE)
  )
}

query_synergy_find <- function(req = NULL) {
  payload <- query_synergy_parse_payload(req)
  if (!isTRUE(payload$ok)) {
    return(query_api_error(payload$error, best_matches = list()))
  }

  load_start <- proc.time()[["elapsed"]]
  catalog <- if (is.list(payload$data$cards) && length(payload$data$cards) > 0L) {
    payload$data$cards
  } else {
    catalog_out <- query_synergy_get_catalog(force_refresh = isTRUE(payload$data$force_refresh))
    if (!isTRUE(catalog_out$ok)) {
      return(query_api_error(catalog_out$error, best_matches = list()))
    }
    catalog_out$cards
  }
  data_loading_ms <- query_synergy_elapsed_ms(load_start)

  result <- query_synergy_find_in_catalog(payload$data, catalog)
  if (!isTRUE(result$ok)) {
    return(query_api_error(result$error, best_matches = list()))
  }

  result$timings$data_loading_ms <- data_loading_ms
  result$timings$total_ms <- round(sum(unlist(result$timings), na.rm = TRUE), 1)

  result
}

query_synergy_jobs_dir <- function(base_dir = "") {
  root <- trimws(as.character(base_dir))
  if (!nzchar(root)) {
    root <- query_synergy_jobs_env$jobs_dir
  }
  if (!nzchar(root)) {
    root <- file.path(tempdir(), "mtgcodex_synergy_jobs")
  }
  if (!dir.exists(root)) {
    dir.create(root, recursive = TRUE, showWarnings = FALSE)
  }
  query_synergy_jobs_env$jobs_dir <- root
  root
}

query_synergy_job_paths <- function(job_id, base_dir = "") {
  safe_id <- gsub("[^A-Za-z0-9_-]", "", trimws(as.character(job_id)))
  root <- query_synergy_jobs_dir(base_dir)
  job_dir <- file.path(root, safe_id)
  if (!dir.exists(job_dir)) {
    dir.create(job_dir, recursive = TRUE, showWarnings = FALSE)
  }
  list(
    root_dir = root,
    job_dir = job_dir,
    payload_file = file.path(job_dir, "payload.json"),
    status_file = file.path(job_dir, "status.json"),
    result_file = file.path(job_dir, "result.json")
  )
}

query_synergy_new_job_id <- function() {
  paste0(
    format(Sys.time(), "%Y%m%d%H%M%S"),
    "-",
    substr(paste(sample(c(letters, LETTERS, 0:9), size = 12L, replace = TRUE), collapse = ""), 1L, 12L)
  )
}

query_synergy_job_runner_path <- function() {
  candidates <- c(
    file.path(getwd(), "inst", "jobs", "run_synergy_job.R"),
    file.path(getwd(), "..", "inst", "jobs", "run_synergy_job.R")
  )
  existing <- candidates[file.exists(candidates)]
  if (length(existing) > 0L) {
    return(normalizePath(existing[[1]], winslash = "/", mustWork = TRUE))
  }

  installed <- tryCatch(system.file("jobs", "run_synergy_job.R", package = "mtgcodex.api"), error = function(e) "")
  if (nzchar(installed) && file.exists(installed)) {
    return(normalizePath(installed, winslash = "/", mustWork = TRUE))
  }

  ""
}

query_synergy_detect_repo_root <- function(hint_path = "", fallback_dir = "") {
  hint <- trimws(as.character(hint_path))
  fallback <- trimws(as.character(fallback_dir))
  if (!nzchar(fallback)) {
    fallback <- getwd()
  }

  candidates <- c(
    fallback,
    getwd(),
    file.path(getwd(), "..")
  )

  if (nzchar(hint)) {
    hint_root <- normalizePath(hint, winslash = "/", mustWork = FALSE)
    candidates <- c(
      dirname(dirname(dirname(hint_root))),
      dirname(dirname(hint_root)),
      dirname(hint_root),
      candidates
    )
  }

  candidates <- unique(Filter(function(path) nzchar(trimws(as.character(path))), candidates))
  for (candidate in candidates) {
    root <- normalizePath(candidate, winslash = "/", mustWork = FALSE)
    if (dir.exists(file.path(root, "R")) && file.exists(file.path(root, "inst", "jobs", "run_synergy_job.R"))) {
      return(root)
    }
  }

  normalizePath(fallback, winslash = "/", mustWork = FALSE)
}

query_synergy_write_job_json <- function(path, payload) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp")
  jsonlite::write_json(payload, path = tmp, auto_unbox = TRUE, pretty = FALSE, null = "null")
  if (file.exists(path)) {
    unlink(path)
  }
  file.rename(tmp, path)
  invisible(path)
}

query_synergy_read_job_json <- function(path) {
  if (!file.exists(path)) {
    return(NULL)
  }
  tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE), error = function(e) NULL)
}

query_synergy_build_job_status <- function(job_id,
                                           status = "queued",
                                           percent = 0,
                                           stage = "",
                                           error = "",
                                           meta = list()) {
  list(
    ok = TRUE,
    job_id = query_api_scalar(job_id, default = ""),
    status = query_api_scalar(status, default = "queued"),
    error = query_api_scalar(error, default = ""),
    progress = list(
      percent = as.integer(round(max(0, min(100, suppressWarnings(as.numeric(percent)) %||% 0)))),
      stage = query_api_scalar(stage, default = ""),
      updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      meta = if (is.list(meta)) meta else list()
    )
  )
}

query_synergy_start_job <- function(req = NULL) {
  payload <- query_synergy_parse_payload(req)
  if (!isTRUE(payload$ok)) {
    return(query_api_error(payload$error))
  }

  data <- payload$data
  card_name <- query_api_scalar(data$card_name, default = query_api_scalar(data$card_id, default = ""))
  if (!nzchar(card_name)) {
    return(query_api_error("card_name is required"))
  }

  runner_path <- query_synergy_job_runner_path()
  if (!nzchar(runner_path) || !file.exists(runner_path)) {
    return(query_api_error("synergy job runner script unavailable"))
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
    query_synergy_build_job_status(
      job_id = job_id,
      status = "queued",
      percent = 0,
      stage = "Queued"
    )
  )

  args <- c(
    normalizePath(runner_path, winslash = "/", mustWork = TRUE),
    "--job-id", job_id,
    "--payload", normalizePath(paths$payload_file, winslash = "/", mustWork = TRUE),
    "--status", normalizePath(paths$status_file, winslash = "/", mustWork = TRUE),
    "--result", normalizePath(paths$result_file, winslash = "/", mustWork = FALSE),
    "--repo", repo_root
  )

  spawn_ok <- tryCatch({
    system2(
      command = normalizePath(rscript_path, winslash = "/", mustWork = TRUE),
      args = args,
      wait = FALSE,
      stdout = FALSE,
      stderr = FALSE
    )
    TRUE
  }, error = function(e) FALSE)

  if (!isTRUE(spawn_ok)) {
    return(query_api_error("unable to start synergy background job"))
  }

  status_payload <- query_synergy_read_job_json(paths$status_file)
  if (!is.list(status_payload)) {
    status_payload <- query_synergy_build_job_status(job_id, status = "queued", percent = 0, stage = "Queued")
  }

  status_payload
}

query_synergy_get_job_status <- function(job_id = "") {
  lookup <- trimws(as.character(job_id))
  if (!nzchar(lookup)) {
    return(query_api_error("job_id is required"))
  }

  paths <- query_synergy_job_paths(lookup)
  status_payload <- query_synergy_read_job_json(paths$status_file)
  if (!is.list(status_payload)) {
    return(query_api_error("synergy job not found"))
  }

  if (identical(query_api_scalar(status_payload$status, default = ""), "completed")) {
    result_payload <- query_synergy_read_job_json(paths$result_file)
    if (is.list(result_payload)) {
      status_payload$result <- result_payload
    } else {
      status_payload$status <- "running"
      if (!is.list(status_payload$progress)) {
        status_payload$progress <- list()
      }
      status_payload$progress$percent <- 99L
      status_payload$progress$stage <- "Finalizing result"
    }
  }

  status_payload
}

query_synergy_normalize_cards <- function(req = NULL) {
  payload <- query_synergy_parse_payload(req)
  if (!isTRUE(payload$ok)) {
    return(query_api_error(payload$error, cards = list()))
  }

  data <- payload$data
  cards <- data$cards
  if (!is.list(cards) || length(cards) == 0L) {
    single <- data$card
    if (is.list(single) && length(single) > 0L) {
      cards <- list(single)
    }
  }

  if (!is.list(cards) || length(cards) == 0L) {
    return(query_api_error("payload must contain card or cards", cards = list()))
  }

  registry <- query_synergy_event_registry_default()
  normalized <- lapply(cards, function(card) {
    query_synergy_normalize_card(card, registry = registry)
  })

  list(
    ok = TRUE,
    count = length(normalized),
    cards = normalized
  )
}

query_synergy_get_card <- function(card_id = "", include_normalized = "true") {
  lookup <- trimws(as.character(card_id))
  if (!nzchar(lookup)) {
    return(query_api_error("missing card id"))
  }

  catalog_out <- query_synergy_get_catalog(force_refresh = FALSE)
  if (!isTRUE(catalog_out$ok)) {
    return(query_api_error(catalog_out$error))
  }

  card <- query_synergy_find_card_by_id_or_name(catalog_out$cards, lookup)
  if (is.null(card)) {
    return(query_api_error("card not found in Scryfall catalog"))
  }

  include_norm <- query_api_parse_bool(include_normalized, default = TRUE)
  out <- list(
    ok = TRUE,
    source = "scryfall_oracle_cards",
    card = card
  )

  if (include_norm) {
    out$normalized <- query_synergy_normalize_card(card, query_synergy_event_registry_default())
  }

  out
}

query_synergy_list_events <- function() {
  registry <- query_synergy_event_registry_default()
  events <- lapply(names(registry$events), function(event_id) {
    event <- registry$events[[event_id]]
    list(
      id = event_id,
      label = event$label,
      description = event$description,
      parent = event$parent,
      aliases = event$aliases
    )
  })

  list(
    ok = TRUE,
    count = length(events),
    events = events
  )
}

query_synergy_list_mechanics <- function() {
  rules <- query_synergy_mechanic_rules_default()
  mechanics <- lapply(names(rules), function(rule_id) {
    rule <- rules[[rule_id]]
    list(
      id = rule_id,
      keywords = rule$keywords,
      produced_events = rule$produced,
      consumed_events = rule$consumed,
      replaced_events = rule$replaced,
      prevented_events = rule$prevented,
      setup_events = rule$setup,
      finisher_events = rule$finisher,
      anti_tags = rule$anti_tags,
      strategy_tags = rule$strategy_tags,
      notes = rule$notes
    )
  })

  list(
    ok = TRUE,
    count = length(mechanics),
    mechanics = mechanics
  )
}

# List the registered strategic archetypes (Aggro, Aristocrats, etc.) used
# to filter and annotate group results.
query_synergy_list_archetypes <- function() {
  archetypes <- tryCatch(
    query_synergy_archetypes_list(),
    error = function(e) list()
  )
  if (is.null(archetypes)) archetypes <- list()
  list(
    ok = TRUE,
    count = length(archetypes),
    archetypes = archetypes
  )
}

# List the supported play formats and their key behavioural flags
# (singleton, color identity strictness).
query_synergy_list_formats <- function() {
  formats <- query_synergy_formats_list()
  list(
    ok = TRUE,
    count = length(formats),
    formats = formats
  )
}

# Expand the group pool with "bridge" candidates: cards that score weakly
# with the seed but strongly with at least one card already in the initial
# pool.  This allows the group detector to find paths such as
#   seed -> pool_member_A -> bridge_card -> pool_member_B
# where bridge_card would never appear if we restricted the pool to the
# top-N direct seed scores.
#
# Two-phase filtering keeps the cost bounded:
#   Phase 1 – cheap scan (compact profile dot-product) to pre-rank
#              bridge_candidates against pool members.
#   Phase 2 – full pair scoring only for the top cheap scorers.
#
# Returns the expanded pool (initial_pool + up to expansion_cap bridges).
query_synergy_expand_group_pool <- function(
  initial_pool,
  bridge_candidates,
  registry,
  format_name,
  bridge_cheap_threshold = 0.12,
  bridge_deep_threshold = 30,
  expansion_cap = 8L
) {
  if (expansion_cap <= 0L || length(initial_pool) == 0L || length(bridge_candidates) == 0L) {
    return(initial_pool)
  }

  pool_profiles <- lapply(initial_pool, function(card) {
    query_synergy_build_compact_profile(card, registry = registry)
  })

  # Phase 1: cheap pre-filter — score each bridge candidate against every
  # pool member profile, keep its best cheap score.
  cheap_scores <- vapply(bridge_candidates, function(bridge_card) {
    bridge_profile <- query_synergy_build_compact_profile(bridge_card, registry = registry)
    best <- 0
    for (pool_profile in pool_profiles) {
      s <- suppressWarnings(as.numeric(
        query_synergy_score_candidate_lightweight(pool_profile, bridge_profile, format_name)$score
      ))
      if (is.finite(s) && s > best) best <- s
    }
    best
  }, numeric(1))

  cheap_ord <- order(cheap_scores, decreasing = TRUE)
  n_deep <- min(length(bridge_candidates), expansion_cap * 2L)
  deep_candidates_idx <- cheap_ord[seq_len(n_deep)]
  deep_candidates_idx <- deep_candidates_idx[cheap_scores[deep_candidates_idx] >= bridge_cheap_threshold]
  if (length(deep_candidates_idx) == 0L) {
    return(initial_pool)
  }

  # Phase 2: full bidirectional pair score for cheap-filtered bridges.
  deep_scores <- vapply(deep_candidates_idx, function(i) {
    bridge_card <- bridge_candidates[[i]]
    best <- 0
    for (pool_card in initial_pool) {
      fwd <- suppressWarnings(as.numeric(
        query_synergy_score_pair(bridge_card, pool_card, format_name)$score
      ))
      bwd <- suppressWarnings(as.numeric(
        query_synergy_score_pair(pool_card, bridge_card, format_name)$score
      ))
      s <- max(
        if (is.finite(fwd)) fwd else 0,
        if (is.finite(bwd)) bwd else 0
      )
      if (s > best) best <- s
    }
    best
  }, numeric(1))

  eligible_mask <- deep_scores >= bridge_deep_threshold
  if (!any(eligible_mask)) {
    return(initial_pool)
  }

  eligible_idx <- deep_candidates_idx[eligible_mask]
  eligible_idx <- eligible_idx[order(deep_scores[eligible_mask], decreasing = TRUE)]
  eligible_idx <- eligible_idx[seq_len(min(length(eligible_idx), expansion_cap))]

  expanded_cards <- lapply(eligible_idx, function(i) bridge_candidates[[i]])
  c(initial_pool, expanded_cards)
}

query_synergy_find_in_catalog <- function(payload = list(),
                                          catalog = list(),
                                          progress_callback = NULL) {
  if (!is.list(catalog) || length(catalog) < 3L) {
    return(query_api_error("catalog must contain at least 3 cards"))
  }

  query_synergy_runtime_metrics_reset()
  query_synergy_runtime_metrics_set_stage("request_validation")

  query_synergy_emit_progress(progress_callback, 1, "Validating request")

  card_name <- query_api_scalar(payload$card_name, default = query_api_scalar(payload$card_id, default = ""))
  if (!nzchar(card_name)) {
    return(query_api_error("card_name is required"))
  }

  target_card <- query_synergy_find_card_by_id_or_name(catalog, card_name)
  if (is.null(target_card)) {
    return(query_api_error("target card not found"))
  }
  query_synergy_emit_progress(progress_callback, 3, "Resolving target card")

  format_name <- tolower(query_api_scalar(payload$format, default = "commander"))
  max_results <- query_synergy_as_int(payload$max_results, default = 50L, min_value = 1L, max_value = 200L)
  top_k <- query_synergy_as_int(payload$top_k, default = max(64L, min(120L, max_results * 4L)), min_value = 1L, max_value = 2000L)
  cheap_scan_cap <- query_synergy_as_int(payload$cheap_scan_cap, default = 0L, min_value = 0L, max_value = 50000L)
  package_top_n <- query_synergy_as_int(payload$package_top_n, default = min(12L, top_k), min_value = 2L, max_value = 200L)
  max_groups <- query_synergy_as_int(payload$max_groups, default = min(10L, max_results), min_value = 1L, max_value = 50L)
  max_group_size <- query_synergy_as_int(payload$max_group_size, default = 4L, min_value = 3L, max_value = 5L)
  max_group_paths <- query_synergy_as_int(payload$max_group_paths, default = max(96L, package_top_n * max_group_size * 4L), min_value = 10L, max_value = 500L)
  group_branching_cap <- query_synergy_as_int(
    payload$group_branching_cap,
    default = max(4L, min(8L, max_group_size + 1L)),
    min_value = 2L,
    max_value = 20L
  )
  include_spellbook <- query_api_parse_bool(payload$include_spellbook, default = FALSE)
  include_lotusnoir <- query_api_parse_bool(payload$include_lotusnoir, default = FALSE)
  spellbook_variants_override <- if (is.list(payload$spellbook_variants)) payload$spellbook_variants else NULL
  lotusnoir_posts_override <- if (is.list(payload$lotusnoir_posts)) payload$lotusnoir_posts else NULL
  color_filter <- query_synergy_parse_color_identity(payload$color_identity)

  # Format-driven filtering. The format spec controls:
  #   * which legality status is accepted on candidates (e.g. commander -> "legal")
  #   * whether color identity should be enforced (Commander/Brawl only)
  # `allow_illegal = TRUE` opts out of legality filtering for exploratory work.
  # The color filter is always honoured: in Commander/Brawl it means color identity;
  # in other formats it filters by the candidate's card colors.
  format_spec <- query_synergy_format_spec(format_name)
  allow_illegal <- query_api_parse_bool(payload$allow_illegal, default = FALSE)

  # Archetype filter: payload$archetype_filter may be a character vector of
  # archetype keys (e.g. c("aristocrats", "graveyard")). When empty or all
  # archetypes are selected, no filter is applied. Strict mode drops groups
  # that don't match any selected archetype; soft mode just penalises them.
  archetype_filter <- character(0)
  if (!is.null(payload$archetype_filter)) {
    archetype_filter <- unique(query_synergy_to_vector(payload$archetype_filter))
    archetype_filter <- archetype_filter[nzchar(archetype_filter)]
  }
  archetype_filter_strict <- query_api_parse_bool(payload$archetype_filter_strict, default = FALSE)

  registry <- query_synergy_event_registry_default()
  timings <- list()
  stage_start <- proc.time()[["elapsed"]]

  query_synergy_runtime_metrics_set_stage("precompute_load")
  precomputed <- query_synergy_get_precomputed_catalog(
    catalog = catalog,
    registry = registry,
    force_refresh = isTRUE(payload$force_refresh),
    progress_callback = progress_callback
  )
  timings$precompute_load_ms <- query_synergy_elapsed_ms(stage_start)

  target_normalized <- query_synergy_normalize_card_cached(target_card, registry = registry)
  target_profile <- query_synergy_build_compact_profile(target_normalized, registry = registry)
  query_synergy_emit_progress(progress_callback, 32, "Prepared normalized target")

  stage_start <- proc.time()[["elapsed"]]
  query_synergy_runtime_metrics_set_stage("candidate_filter")
  indexed_candidate_indexes <- query_synergy_collect_indexed_candidate_indexes(
    target = target_profile,
    precomputed = precomputed,
    top_k = top_k
  )
  eligible_candidate_indexes <- Filter(function(index) {
    profile <- precomputed$profiles[[index]]
    candidate_id <- query_api_scalar(profile$id, default = "")
    if (!nzchar(candidate_id) || identical(candidate_id, target_normalized$id)) {
      return(FALSE)
    }

    if (!query_synergy_card_legal_in_format(profile, format_name, allow_illegal)) {
      return(FALSE)
    }

    if (length(color_filter) == 0L) {
      return(TRUE)
    }

    candidate_colors <- query_synergy_to_vector(profile$color_identity)
    length(intersect(candidate_colors, color_filter)) > 0L
  }, seq_along(precomputed$profiles))
  indexed_candidate_count <- length(intersect(indexed_candidate_indexes, eligible_candidate_indexes))
  candidate_filter_count <- length(eligible_candidate_indexes)
  candidate_indexes <- eligible_candidate_indexes
  if (cheap_scan_cap > 0L && length(candidate_indexes) > cheap_scan_cap) {
    # All indexed candidates (already bounded by query_synergy_collect_indexed_
    # candidate_indexes -> max(384, top_k * 16)) survive the cheap-scan cut.
    # Truncating the indexed slice would silently drop role-aware reverse
    # synergy matches whose signal-count rank happens to exceed the cap
    # (e.g. payoff seeds whose engines sit far down the table()-sorted index).
    # cheap_scan_cap therefore only limits the non-indexed residue.
    indexed_keep <- intersect(indexed_candidate_indexes, candidate_indexes)
    extras <- setdiff(candidate_indexes, indexed_candidate_indexes)
    remaining_cap <- max(0L, cheap_scan_cap - length(indexed_keep))
    if (remaining_cap > 0L && length(extras) > 0L) {
      extras <- extras[seq_len(min(length(extras), remaining_cap))]
    } else {
      extras <- integer(0)
    }
    candidate_indexes <- c(indexed_keep, extras)
  }
  cheap_scan_cap_used <- length(candidate_indexes)
  full_catalog_light_scan <- cheap_scan_cap <= 0L ||
    candidate_filter_count <= cheap_scan_cap ||
    length(candidate_indexes) >= candidate_filter_count
  timings$candidate_filter_ms <- query_synergy_elapsed_ms(stage_start)
  query_synergy_emit_progress(progress_callback, 36, "Filtered candidate pool", list(
    candidates = candidate_filter_count,
    cheap_scan_candidates = length(candidate_indexes)
  ))
  query_synergy_runtime_metrics_add("candidate_filter_count", candidate_filter_count, stage = "candidate_filter")
  query_synergy_runtime_metrics_add("cheap_scan_candidate_count", length(candidate_indexes), stage = "candidate_filter")

  stage_start <- proc.time()[["elapsed"]]
  query_synergy_runtime_metrics_set_stage("cheap_scan")
  light_scores <- vector("list", length(candidate_indexes))
  light_stride <- max(1L, ceiling(max(1L, length(candidate_indexes)) / 30L))
  for (i in seq_along(candidate_indexes)) {
    query_synergy_runtime_metrics_add("cards_scanned", 1L)
    index <- candidate_indexes[[i]]
    profile <- precomputed$profiles[[index]]
    light_scores[[i]] <- list(
      index = index,
      profile = profile,
      cheap_score = query_synergy_score_candidate_lightweight(
        target = target_profile,
        candidate = profile,
        format_name = format_name
      )
    )
    if (is.function(progress_callback) && (i == 1L || i == length(candidate_indexes) || (i %% light_stride) == 0L)) {
      percent <- 36 + ((i / max(1L, length(candidate_indexes))) * 24)
      query_synergy_emit_progress(progress_callback, percent, "Scanning full catalog", list(processed = i, total = length(candidate_indexes)))
    }
  }
  timings$cheap_scan_ms <- query_synergy_elapsed_ms(stage_start)

  stage_start <- proc.time()[["elapsed"]]
  query_synergy_runtime_metrics_set_stage("top_k_selection")
  candidate_ord <- order(
    vapply(light_scores, function(entry) suppressWarnings(as.numeric(entry$cheap_score$score)), numeric(1)),
    decreasing = TRUE
  )
  light_scores <- light_scores[candidate_ord]

  # AGENTS.md § 4.1: the cheap scorer is a coarse heuristic and routinely
  # under-ranks generalist cards whose mechanical fit is real but diluted
  # (e.g. Raffine, Scheming Seer producing SELF_DRAW_CARD among 9 other
  # events vs. Sheoldred, the Apocalypse). The inverted-index slice
  # (`indexed_candidate_indexes`) is the engine's mechanics-first relevance
  # filter; those candidates must reach deep scoring even when their cheap
  # rank lands outside the top_k window. Otherwise role-aware reverse-
  # synergy matches are silently dropped before they can be evaluated.
  #
  # Strategy: keep the top_k cheap-ranked candidates AND force-include the
  # indexed slice (sorted by cheap score, capped at deep_score_indexed_cap
  # to bound deep-scoring cost). The final result list is still trimmed by
  # max_results downstream, so widening the deep slot count only adds work
  # to the deep stage; correctness wins per AGENTS.md priority order.
  is_indexed_entry <- vapply(
    light_scores,
    function(entry) isTRUE(entry$index %in% indexed_candidate_indexes),
    logical(1)
  )
  deep_score_indexed_cap <- min(length(light_scores), max(as.integer(top_k), 600L))
  indexed_entries <- light_scores[is_indexed_entry]
  extra_entries <- light_scores[!is_indexed_entry]
  if (length(indexed_entries) > deep_score_indexed_cap) {
    indexed_entries <- indexed_entries[seq_len(deep_score_indexed_cap)]
  }
  remaining_extras <- max(0L, as.integer(top_k) - length(indexed_entries))
  extras_take <- if (remaining_extras > 0L && length(extra_entries) > 0L) {
    extra_entries[seq_len(min(remaining_extras, length(extra_entries)))]
  } else {
    list()
  }
  light_scores <- c(indexed_entries, extras_take)
  timings$top_k_selection_ms <- query_synergy_elapsed_ms(stage_start)
  query_synergy_runtime_metrics_add("top_k_count", length(light_scores))
  query_synergy_runtime_metrics_add("top_k_indexed_count", length(indexed_entries))
  query_synergy_runtime_metrics_add("top_k_extras_count", length(extras_take))
  query_synergy_emit_progress(progress_callback, 62, "Selected top candidates", list(top_k = length(light_scores)))

  stage_start <- proc.time()[["elapsed"]]
  query_synergy_runtime_metrics_set_stage("deep_scoring")
  scored_all <- vector("list", length(light_scores))
  deep_stride <- max(1L, ceiling(max(1L, length(light_scores)) / 20L))
  for (i in seq_along(light_scores)) {
    query_synergy_runtime_metrics_add("cards_scored", 1L)
    entry <- light_scores[[i]]
    candidate <- precomputed$normalized[[entry$index]]
    # AGENTS.md § 4.1: pair scoring must be direction-invariant. Compute both
    # orientations and keep the stronger one so a payoff seed paired with an
    # engine candidate gets the same score as the inverse pairing. This
    # doubles the per-pair cost; the existing top-K filter keeps it bounded.
    forward_score <- query_synergy_score_pair(target_normalized, candidate, format_name)
    backward_score <- query_synergy_score_pair(candidate, target_normalized, format_name)
    score <- if (isTRUE(backward_score$score > forward_score$score)) backward_score else forward_score
    scored_all[[i]] <- list(
      card = candidate,
      score = score,
      cheap_score = entry$cheap_score
    )
    if (is.function(progress_callback) && (i == 1L || i == length(light_scores) || (i %% deep_stride) == 0L)) {
      percent <- 64 + ((i / max(1L, length(light_scores))) * 20)
      query_synergy_emit_progress(progress_callback, percent, "Deep scoring top candidates", list(processed = i, total = length(light_scores)))
    }
  }
  timings$deep_scoring_ms <- query_synergy_elapsed_ms(stage_start)

  stage_start <- proc.time()[["elapsed"]]
  query_synergy_runtime_metrics_set_stage("bucket_assembly")
  ranked <- query_synergy_build_result_buckets(target_normalized, scored_all, max_results = max_results)
  timings$bucket_assembly_ms <- query_synergy_elapsed_ms(stage_start)
  query_synergy_emit_progress(progress_callback, 86, "Assembled ranked buckets")
  scored <- Filter(function(entry) {
    is.list(entry$score) && is.finite(entry$score$score) && entry$score$score > 0
  }, scored_all)

  if (length(ranked$flat) == 0L && length(scored) == 0L) {
    timings$explanation_assembly_ms <- 0
    timings$explanation_generation_ms <- timings$explanation_assembly_ms
    timings$package_detection_ms <- 0
    timings$response_assembly_ms <- 0
    metrics_snapshot <- query_synergy_runtime_metrics_snapshot()
    query_synergy_emit_progress(progress_callback, 100, "Completed", list(
      catalog_size = length(precomputed$profiles),
      deep_score_count = length(scored_all),
      package_candidate_count = 0L
    ))
    response <- list(
      ok = TRUE,
      card = target_normalized$name,
      card_id = target_normalized$id,
      count = 0,
      format = format_name,
      color_identity = color_filter,
      best_matches = list(),
      buckets = ranked$buckets,
      synergy_groups = list(),
      group_count = 0L,
      package_lines = list(),
      package_line_count = 0L,
      packages = list(),
      package_count = 0L,
      pipeline = list(
        catalog_size = length(precomputed$profiles),
        candidate_filter_count = candidate_filter_count,
        cheap_scan_count = length(candidate_indexes),
        full_catalog_scanned_count = length(candidate_indexes),
        deep_score_count = length(scored_all),
        deep_scored_count = length(scored_all),
        package_candidate_count = 0L,
        group_graph_node_count = 0L,
        group_graph_edge_count = 0L,
        group_path_count = 0L,
        group_graph_pair_count = 0L,
        indexed_candidate_count = indexed_candidate_count,
        cheap_scan_cap_used = cheap_scan_cap_used,
        full_catalog_light_scan = isTRUE(full_catalog_light_scan),
        top_k_used = min(top_k, length(candidate_indexes)),
        promoted_to_deep_count = length(light_scores),
        group_branching_cap_used = group_branching_cap,
        max_group_size_used = max_group_size,
        package_top_n_used = 0L,
        package_eval_count = 0L,
        stage_metrics = metrics_snapshot$stage_counts
      ),
      timings = c(timings, list(total_ms = round(sum(unlist(timings), na.rm = TRUE), 1)))
    )
    if (isTRUE(include_spellbook) || isTRUE(include_lotusnoir) || is.list(spellbook_variants_override) || is.list(lotusnoir_posts_override)) {
      response <- query_synergy_attach_external_validations(
        result = response,
        seed_name = target_normalized$name,
        include_spellbook = include_spellbook,
        include_lotusnoir = include_lotusnoir,
        spellbook_variants = spellbook_variants_override,
        lotusnoir_posts = lotusnoir_posts_override
      )$result
    }
    return(response)
  }

  ord <- order(vapply(scored, function(entry) entry$score$score, numeric(1)), decreasing = TRUE)
  scored <- scored[ord]
  scored_positive <- scored
  if (length(scored_positive) > max_results) {
    scored <- scored_positive[seq_len(max_results)]
  } else {
    scored <- scored_positive
  }

  stage_start <- proc.time()[["elapsed"]]
  query_synergy_runtime_metrics_set_stage("explanation_assembly")
  matches <- lapply(scored, function(entry) {
    candidate <- entry$card
    score <- entry$score
    list(
      id = candidate$id,
      name = candidate$name,
      score = score$score,
      score_breakdown = score$breakdown,
      reasons = score$reasons,
      relation_classes = score$relation_classes,
      matched_events = score$matched_events
    )
  })
  timings$explanation_assembly_ms <- query_synergy_elapsed_ms(stage_start)
  timings$explanation_generation_ms <- timings$explanation_assembly_ms

  package_pool <- lapply(utils::head(scored_positive, package_top_n), function(entry) entry$card)

  # Bridge expansion: cards ranked just below the initial pool that score
  # strongly with at least one pool member are added as group candidates.
  # This surfaces multi-hop combos (seed -> pool_member -> bridge) that
  # would be missed if we only look at direct seed scores.
  expansion_bridge_n <- query_synergy_as_int(
    payload$expansion_bridge_n,
    default = 8L, min_value = 0L, max_value = 20L
  )
  if (expansion_bridge_n > 0L && length(scored_positive) > package_top_n) {
    pool_ids <- vapply(package_pool, function(c) query_api_scalar(c$id, default = ""), character(1))
    bridge_tier <- Filter(function(entry) {
      cid <- query_api_scalar(entry$card$id, default = "")
      nzchar(cid) && !(cid %in% pool_ids)
    }, utils::head(scored_positive, package_top_n + expansion_bridge_n * 3L))
    bridge_cards <- lapply(bridge_tier, function(entry) entry$card)
    if (length(bridge_cards) > 0L) {
      package_pool <- query_synergy_expand_group_pool(
        initial_pool = package_pool,
        bridge_candidates = bridge_cards,
        registry = registry,
        format_name = format_name,
        expansion_cap = expansion_bridge_n
      )
    }
  }

  stage_start <- proc.time()[["elapsed"]]
  query_synergy_runtime_metrics_set_stage("package_detection")
  query_synergy_runtime_metrics_add("package_candidates", length(package_pool))
  groups_out <- query_synergy_detect_groups_for_seed(
    seed = target_normalized,
    candidates = package_pool,
    format_name = format_name,
    max_groups = max_groups,
    max_group_size = max_group_size,
    max_paths = max_group_paths,
    max_branching = group_branching_cap,
    progress_callback = progress_callback,
    progress_range = c(88, 97)
  )
  timings$package_detection_ms <- query_synergy_elapsed_ms(stage_start)

  # Group refinement: for each top group, try replacing the weakest non-seed
  # member with a card drawn from the top-K neighborhood of one of the OTHER
  # group members.  This surfaces cards that score weakly with the seed but
  # strongly with a group peer — exactly the "bridge through B or C" pattern.
  group_refine_iters <- query_synergy_as_int(
    payload$group_refine_iterations,
    default = 2L, min_value = 0L, max_value = 4L
  )
  group_refine_top_n <- query_synergy_as_int(
    payload$group_refine_top_n,
    default = 3L, min_value = 0L, max_value = 10L
  )
  if (group_refine_iters > 0L && group_refine_top_n > 0L && length(groups_out$groups) > 0L) {
    stage_start <- proc.time()[["elapsed"]]
    query_synergy_runtime_metrics_set_stage("group_refinement")
    # Broader pool used for member-neighborhood lookup: top-100 direct
    # synergies (configurable). Wider than package_pool so cards that score
    # weakly with the seed but strongly with a peer can surface as bridges.
    refine_broader_n <- query_synergy_as_int(
      payload$group_refine_broader_n,
      default = 100L, min_value = 20L, max_value = 500L
    )
    refine_broader_pool <- lapply(
      utils::head(scored_positive, refine_broader_n),
      function(entry) entry$card
    )
    refined_groups <- query_synergy_refine_groups(
      groups = groups_out$groups,
      seed = target_normalized,
      broader_pool = refine_broader_pool,
      format_name = format_name,
      registry = registry,
      max_iterations = group_refine_iters,
      max_groups_to_refine = group_refine_top_n,
      max_branching = group_branching_cap,
      max_paths = max_group_paths
    )
    groups_out$groups <- refined_groups
    groups_out$package_lines <- Filter(function(g) {
      identical(query_api_scalar(g$bucket, default = ""), "package_lines")
    }, refined_groups)
    timings$group_refinement_ms <- query_synergy_elapsed_ms(stage_start)
  } else {
    timings$group_refinement_ms <- 0
  }

  # Archetype-based group reordering / filtering.
  # AGENTS.md § 4: synergy must remain explainable. We expose the alignment
  # score per group AND apply an ADDITIVE boost (not multiplicative) so a
  # specialist group that happens not to match the requested archetype is
  # not silently decimated. Strict mode is the explicit opt-in for hard
  # filtering: it drops groups whose alignment falls below a small threshold.
  if (length(archetype_filter) > 0L && length(groups_out$groups) > 0L) {
    arch_cfg <- query_synergy_archetype_tuning()
    aligned_groups <- lapply(groups_out$groups, function(g) {
      alignment <- query_synergy_group_archetype_alignment(g$archetypes, archetype_filter)
      g$archetype_alignment <- round(alignment, 3)
      # Record the additive score modifier so the breakdown stays auditable.
      boost <- as.integer(round(arch_cfg$max_boost * min(1, max(0, alignment))))
      base <- if (!is.null(g$score_base)) as.integer(g$score_base) else
        as.integer(round(suppressWarnings(as.numeric(g$total_score))))
      if (is.null(g$score_base)) g$score_base <- base
      modifiers <- if (is.list(g$score_modifiers)) g$score_modifiers else list()
      modifiers$archetype <- list(
        amount = boost,
        alignment = round(alignment, 3),
        archetypes = archetype_filter
      )
      g$score_modifiers <- modifiers
      g$total_score <- min(100L, base + sum(vapply(modifiers,
        function(m) as.integer(m$amount %||% 0L), integer(1))))
      g
    })
    if (isTRUE(archetype_filter_strict)) {
      aligned_groups <- Filter(function(g) {
        suppressWarnings(as.numeric(g$archetype_alignment)) >= arch_cfg$strict_min_alignment
      }, aligned_groups)
    }
    if (length(aligned_groups) > 0L) {
      ord <- order(
        vapply(aligned_groups, function(g) suppressWarnings(as.numeric(g$total_score)), numeric(1)),
        decreasing = TRUE
      )
      aligned_groups <- aligned_groups[ord]
    }
    groups_out$groups <- aligned_groups
    groups_out$package_lines <- Filter(function(g) {
      identical(query_api_scalar(g$bucket, default = ""), "package_lines")
    }, aligned_groups)
  }

  # Annotate groups with deck co-occurrence counts (Archidekt + Spellbook).
  # We only need the top-N groups that will actually surface in the response.
  cooc_limit <- min(max_groups, max_results)
  if (length(groups_out$groups) > 0L) {
    head_groups <- utils::head(groups_out$groups, cooc_limit)
    tail_groups <- if (length(groups_out$groups) > cooc_limit) {
      utils::tail(groups_out$groups, length(groups_out$groups) - cooc_limit)
    } else {
      list()
    }
    annotated_head <- query_synergy_cooccurrence_annotate_groups(head_groups)
    # Apply Spellbook combo match bonus + attach match details.
    annotated_head <- query_synergy_spellbook_annotate_groups(annotated_head)
    groups_out$groups <- c(annotated_head, tail_groups)
    groups_out$package_lines <- Filter(function(g) {
      identical(query_api_scalar(g$bucket, default = ""), "package_lines")
    }, groups_out$groups)
  }

  packages <- query_synergy_to_list(groups_out$groups)
  synergy_groups <- query_synergy_to_list(groups_out$groups)
  package_lines <- query_synergy_to_list(groups_out$package_lines)
  ranked$buckets$synergy_groups <- query_synergy_build_group_bucket(
    synergy_groups,
    "synergy_groups",
    limit = min(max_groups, max_results)
  )
  ranked$buckets$package_lines <- query_synergy_build_group_bucket(
    package_lines,
    "package_lines",
    limit = min(max_groups, max_results)
  )
  ranked$buckets$packages <- list(
    key = "packages",
    label = query_synergy_bucket_labels()$packages,
    count = length(packages),
    results = packages
  )

  stage_start <- proc.time()[["elapsed"]]
  query_synergy_runtime_metrics_set_stage("response_assembly")
  response_pipeline <- list(
    catalog_size = length(precomputed$profiles),
    candidate_filter_count = candidate_filter_count,
    cheap_scan_count = length(candidate_indexes),
    full_catalog_scanned_count = length(candidate_indexes),
    deep_score_count = length(scored_all),
    deep_scored_count = length(scored_all),
    package_candidate_count = length(package_pool),
    group_graph_node_count = query_synergy_as_int(groups_out$meta$node_count, default = 0L, min_value = 0L, max_value = 1000L),
    group_graph_edge_count = query_synergy_as_int(groups_out$meta$edge_count, default = 0L, min_value = 0L, max_value = 10000L),
    group_path_count = query_synergy_as_int(groups_out$meta$path_count, default = 0L, min_value = 0L, max_value = 10000L),
    group_graph_pair_count = query_synergy_as_int(groups_out$meta$pair_count, default = 0L, min_value = 0L, max_value = 100000L),
    indexed_candidate_count = indexed_candidate_count,
    cheap_scan_cap_used = cheap_scan_cap_used,
    full_catalog_light_scan = isTRUE(full_catalog_light_scan),
    top_k_used = min(top_k, length(candidate_indexes)),
    promoted_to_deep_count = length(light_scores),
    group_branching_cap_used = query_synergy_as_int(groups_out$meta$branching_cap, default = group_branching_cap, min_value = 1L, max_value = 20L),
    max_group_size_used = max_group_size,
    package_top_n_used = length(package_pool),
    package_eval_count = length(package_pool)
  )
  metrics_snapshot <- query_synergy_runtime_metrics_snapshot()
  response_pipeline$stage_metrics <- metrics_snapshot$stage_counts
  timings$response_assembly_ms <- query_synergy_elapsed_ms(stage_start)
  timings$total_ms <- round(sum(unlist(timings), na.rm = TRUE), 1)
  query_synergy_emit_progress(progress_callback, 100, "Completed", list(
    catalog_size = length(precomputed$profiles),
    deep_score_count = length(scored_all),
    package_candidate_count = length(package_pool)
  ))

  response <- list(
    ok = TRUE,
    card = target_normalized$name,
    card_id = target_normalized$id,
    count = length(ranked$flat),
    format = format_name,
    color_identity = color_filter,
    normalized_target = target_normalized,
    best_matches = ranked$flat,
    legacy_best_matches = matches,
    buckets = ranked$buckets,
    synergy_groups = synergy_groups,
    group_count = length(synergy_groups),
    package_lines = package_lines,
    package_line_count = length(package_lines),
    packages = packages,
    package_count = length(packages),
    pipeline = response_pipeline,
    timings = timings
  )

  if (isTRUE(include_spellbook) || isTRUE(include_lotusnoir) || is.list(spellbook_variants_override) || is.list(lotusnoir_posts_override)) {
    response <- query_synergy_attach_external_validations(
      result = response,
      seed_name = target_normalized$name,
      include_spellbook = include_spellbook,
      include_lotusnoir = include_lotusnoir,
      spellbook_variants = spellbook_variants_override,
      lotusnoir_posts = lotusnoir_posts_override
    )$result
  }

  response
}


query_synergy_parse_payload <- function(req = NULL) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    return(list(ok = FALSE, error = "jsonlite package is required"))
  }

  if (is.null(req)) {
    return(list(ok = FALSE, error = "missing request"))
  }

  payload_raw <- ""
  if (!is.null(req$postBody)) {
    payload_raw <- as.character(req$postBody)
  } else if (!is.null(req$body)) {
    payload_raw <- tryCatch(
      jsonlite::toJSON(req$body, auto_unbox = TRUE, null = "null"),
      error = function(e) ""
    )
  }

  payload_raw <- trimws(payload_raw)
  if (!nzchar(payload_raw)) {
    return(list(ok = FALSE, error = "missing JSON payload"))
  }

  payload <- tryCatch(
    jsonlite::fromJSON(payload_raw, simplifyVector = FALSE),
    error = function(e) NULL
  )

  if (is.null(payload) || !is.list(payload)) {
    return(list(ok = FALSE, error = "invalid JSON payload"))
  }

  list(ok = TRUE, data = payload)
}
query_synergy_get_catalog <- function(force_refresh = FALSE, cache_hours = 24L, cache_dir = "") {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    return(list(ok = FALSE, error = "jsonlite package is required"))
  }

  now <- Sys.time()
  max_age <- as.numeric(cache_hours) * 3600
  if (!is.finite(max_age) || max_age <= 0) {
    max_age <- 24 * 3600
  }

  if (!isTRUE(force_refresh) && is.list(query_synergy_cache_env$catalog) && length(query_synergy_cache_env$catalog) > 0L) {
    age <- as.numeric(difftime(now, query_synergy_cache_env$catalog_loaded_at, units = "secs"))
    if (is.finite(age) && age <= max_age) {
      return(list(ok = TRUE, source = query_synergy_cache_env$catalog_source, cards = query_synergy_cache_env$catalog))
    }
  }

  paths <- query_synergy_cache_paths(cache_dir)

  # Allow an explicit SQLite path via env var (takes priority over all_cards.sqlite).
  env_sqlite <- trimws(Sys.getenv("MTGCODEX_SQLITE_PATH", unset = ""))
  # Prefer the locally enriched SQLite catalog (all_cards.sqlite) when present.
  # Skipped on `force_refresh = TRUE` so callers can still trigger a Scryfall
  # bulk download.
  sqlite_path <- if (nzchar(env_sqlite)) env_sqlite else file.path(paths$base_dir, "all_cards.sqlite")
  sqlite_rds  <- file.path(paths$base_dir, "all_cards-normalized.rds")
  if (!isTRUE(force_refresh) && file.exists(sqlite_path)) {
    # Best path: the SQLite already contains version-matching `cards_enriched`
    # (built by scripts/enrich-scryfall-library.R). Loading these skips the
    # per-card oracle parsing entirely.
    enriched_status <- tryCatch(
      query_synergy_enriched_sqlite_status(sqlite_path),
      error = function(e) list(available = FALSE, version_match = FALSE)
    )
    if (isTRUE(enriched_status$available) && isTRUE(enriched_status$version_match)) {
      enriched_cards <- tryCatch(
        query_synergy_catalog_normalized_from_sqlite(db_path = sqlite_path),
        error = function(e) NULL
      )
      if (is.list(enriched_cards) && length(enriched_cards) > 0L && !isFALSE(enriched_cards$ok)) {
        query_synergy_cache_env$catalog <- enriched_cards
        query_synergy_cache_env$catalog_loaded_at <- now
        query_synergy_cache_env$catalog_source <- attr(enriched_cards, "synergy_source") %||% "enriched_sqlite"
        query_synergy_cache_env$catalog_cache_key <- attr(enriched_cards, "synergy_cache_key") %||% ""
        return(list(
          ok = TRUE,
          source = query_synergy_cache_env$catalog_source,
          cards = enriched_cards
        ))
      }
    }
    # Fallback: parsed-RDS cache built from cards_api. Skips per-row Scryfall
    # field reshaping but still requires the precompute step downstream.
    sqlite_cards <- NULL
    if (file.exists(sqlite_rds)) {
      sqlite_mtime <- file.info(sqlite_path)$mtime
      rds_mtime    <- file.info(sqlite_rds)$mtime
      if (is.finite(rds_mtime) && rds_mtime >= sqlite_mtime) {
        sqlite_cards <- tryCatch(readRDS(sqlite_rds), error = function(e) NULL)
      }
    }
    if (is.null(sqlite_cards)) {
      sqlite_cards <- tryCatch(
        query_synergy_catalog_from_sqlite(db_path = sqlite_path),
        error = function(e) NULL
      )
      if (is.list(sqlite_cards) && length(sqlite_cards) > 0L) {
        tryCatch(saveRDS(sqlite_cards, sqlite_rds), error = function(e) NULL)
      }
    }
    if (is.list(sqlite_cards) && length(sqlite_cards) > 0L && !isFALSE(sqlite_cards$ok)) {
      query_synergy_cache_env$catalog <- sqlite_cards
      query_synergy_cache_env$catalog_loaded_at <- now
      query_synergy_cache_env$catalog_source <- attr(sqlite_cards, "synergy_source") %||% "sqlite_cards"
      query_synergy_cache_env$catalog_cache_key <- attr(sqlite_cards, "synergy_cache_key") %||% ""
      return(list(
        ok = TRUE,
        source = query_synergy_cache_env$catalog_source,
        cards = sqlite_cards
      ))
    }
  }

  if (!isTRUE(force_refresh) && file.exists(paths$rds_file)) {
    info <- file.info(paths$rds_file)
    age <- as.numeric(difftime(now, info$mtime, units = "secs"))
    if (is.finite(age) && age <= max_age) {
      cards <- tryCatch(readRDS(paths$rds_file), error = function(e) NULL)
      if (is.list(cards) && length(cards) > 0L) {
        attr(cards, "synergy_source") <- "scryfall_oracle_cards"
        attr(cards, "synergy_source_signature") <- query_synergy_file_signature(paths$rds_file)
        attr(cards, "synergy_cache_key") <- query_synergy_catalog_cache_key(
          cards,
          source = "scryfall_oracle_cards",
          source_signature = attr(cards, "synergy_source_signature")
        )
        query_synergy_cache_env$catalog <- cards
        query_synergy_cache_env$catalog_loaded_at <- now
        query_synergy_cache_env$catalog_source <- "scryfall_oracle_cards"
        query_synergy_cache_env$catalog_cache_key <- attr(cards, "synergy_cache_key")
        return(list(ok = TRUE, source = "scryfall_oracle_cards", cards = cards))
      }
    }
  }

  bulk_meta_raw <- tryCatch(
    paste(readLines("https://api.scryfall.com/bulk-data", warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
    error = function(e) ""
  )
  if (!nzchar(bulk_meta_raw)) {
    return(list(ok = FALSE, error = "Scryfall bulk metadata unavailable"))
  }

  bulk_meta <- tryCatch(jsonlite::fromJSON(bulk_meta_raw, simplifyVector = FALSE), error = function(e) NULL)
  if (!is.list(bulk_meta) || !is.list(bulk_meta$data)) {
    return(list(ok = FALSE, error = "Invalid Scryfall bulk metadata"))
  }

  oracle_entry <- NULL
  for (entry in bulk_meta$data) {
    if (is.list(entry) && identical(entry$type, "oracle_cards") && nzchar(query_api_scalar(entry$download_uri, default = ""))) {
      oracle_entry <- entry
      break
    }
  }

  if (is.null(oracle_entry)) {
    return(list(ok = FALSE, error = "oracle_cards dataset not found in Scryfall bulk metadata"))
  }

  download_uri <- query_api_scalar(oracle_entry$download_uri, default = "")
  if (!nzchar(download_uri)) {
    return(list(ok = FALSE, error = "missing oracle_cards download uri"))
  }

  tmp_file <- paste0(paths$json_file, ".download")
  unlink(tmp_file)

  dl_ok <- tryCatch({
    utils::download.file(download_uri, destfile = tmp_file, mode = "wb", quiet = TRUE)
    TRUE
  }, error = function(e) FALSE)

  if (!isTRUE(dl_ok) || !file.exists(tmp_file)) {
    return(list(ok = FALSE, error = "failed to download Scryfall oracle_cards dataset"))
  }

  ok_rename <- tryCatch({
    if (file.exists(paths$json_file)) {
      unlink(paths$json_file)
    }
    file.rename(tmp_file, paths$json_file)
  }, error = function(e) FALSE)

  if (!isTRUE(ok_rename) || !file.exists(paths$json_file)) {
    return(list(ok = FALSE, error = "unable to persist downloaded oracle_cards dataset"))
  }

  raw_cards <- tryCatch(jsonlite::fromJSON(paths$json_file, simplifyVector = FALSE), error = function(e) NULL)
  if (!is.list(raw_cards) || length(raw_cards) == 0L) {
    return(list(ok = FALSE, error = "invalid oracle_cards dataset"))
  }

  cards <- lapply(raw_cards, query_synergy_trim_card)
  cards <- Filter(function(card) nzchar(query_synergy_card_id(card)) && nzchar(query_api_scalar(card$name, default = "")), cards)

  if (length(cards) == 0L) {
    return(list(ok = FALSE, error = "oracle_cards dataset is empty after normalization"))
  }

  save_ok <- tryCatch({
    saveRDS(cards, paths$rds_file)
    TRUE
  }, error = function(e) FALSE)
  if (!isTRUE(save_ok)) {
    return(list(ok = FALSE, error = "failed to cache normalized Scryfall cards"))
  }

  query_synergy_cache_env$catalog <- cards
  query_synergy_cache_env$catalog_loaded_at <- now
  query_synergy_cache_env$catalog_source <- "scryfall_oracle_cards"
  attr(query_synergy_cache_env$catalog, "synergy_source") <- "scryfall_oracle_cards"
  attr(query_synergy_cache_env$catalog, "synergy_source_signature") <- query_synergy_file_signature(paths$rds_file)
  attr(query_synergy_cache_env$catalog, "synergy_cache_key") <- query_synergy_catalog_cache_key(
    cards,
    source = "scryfall_oracle_cards",
    source_signature = attr(query_synergy_cache_env$catalog, "synergy_source_signature")
  )
  query_synergy_cache_env$catalog_cache_key <- attr(query_synergy_cache_env$catalog, "synergy_cache_key")

  list(ok = TRUE, source = "scryfall_oracle_cards", cards = query_synergy_cache_env$catalog)
}
