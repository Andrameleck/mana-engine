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

query_synergy_find_in_catalog <- function(payload = list(),
                                          catalog = list(),
                                          progress_callback = NULL) {
  if (!is.list(catalog) || length(catalog) < 3L) {
    return(query_api_error("catalog must contain at least 3 cards"))
  }

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
  color_filter <- query_synergy_parse_color_identity(payload$color_identity)

  registry <- query_synergy_event_registry_default()
  timings <- list()
  stage_start <- proc.time()[["elapsed"]]

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
    prioritized_indexes <- c(
      intersect(indexed_candidate_indexes, candidate_indexes),
      setdiff(candidate_indexes, indexed_candidate_indexes)
    )
    candidate_indexes <- prioritized_indexes[seq_len(cheap_scan_cap)]
  }
  cheap_scan_cap_used <- if (cheap_scan_cap > 0L) min(cheap_scan_cap, candidate_filter_count) else candidate_filter_count
  full_catalog_light_scan <- cheap_scan_cap <= 0L || candidate_filter_count <= cheap_scan_cap
  timings$candidate_filter_ms <- query_synergy_elapsed_ms(stage_start)
  query_synergy_emit_progress(progress_callback, 36, "Filtered candidate pool", list(
    candidates = candidate_filter_count,
    cheap_scan_candidates = length(candidate_indexes)
  ))

  stage_start <- proc.time()[["elapsed"]]
  light_scores <- vector("list", length(candidate_indexes))
  light_stride <- max(1L, ceiling(max(1L, length(candidate_indexes)) / 30L))
  for (i in seq_along(candidate_indexes)) {
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

  candidate_ord <- order(
    vapply(light_scores, function(entry) suppressWarnings(as.numeric(entry$cheap_score$score)), numeric(1)),
    decreasing = TRUE
  )
  light_scores <- light_scores[candidate_ord]
  if (length(light_scores) > top_k) {
    light_scores <- light_scores[seq_len(top_k)]
  }
  query_synergy_emit_progress(progress_callback, 62, "Selected top candidates", list(top_k = length(light_scores)))

  stage_start <- proc.time()[["elapsed"]]
  scored_all <- vector("list", length(light_scores))
  deep_stride <- max(1L, ceiling(max(1L, length(light_scores)) / 20L))
  for (i in seq_along(light_scores)) {
    entry <- light_scores[[i]]
    candidate <- precomputed$normalized[[entry$index]]
    score <- query_synergy_score_pair(target_normalized, candidate, format_name)
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
  timings$explanation_generation_ms <- timings$deep_scoring_ms

  stage_start <- proc.time()[["elapsed"]]
  ranked <- query_synergy_build_result_buckets(target_normalized, scored_all, max_results = max_results)
  timings$bucket_assembly_ms <- query_synergy_elapsed_ms(stage_start)
  query_synergy_emit_progress(progress_callback, 86, "Assembled ranked buckets")
  scored <- Filter(function(entry) {
    is.list(entry$score) && is.finite(entry$score$score) && entry$score$score > 0
  }, scored_all)

  if (length(ranked$flat) == 0L && length(scored) == 0L) {
    query_synergy_emit_progress(progress_callback, 100, "Completed", list(
      catalog_size = length(precomputed$profiles),
      deep_score_count = length(scored_all),
      package_candidate_count = 0L
    ))
    return(list(
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
        deep_score_count = length(scored_all),
        package_candidate_count = 0L,
        group_graph_node_count = 0L,
        group_graph_edge_count = 0L,
        group_path_count = 0L,
        group_graph_pair_count = 0L,
        indexed_candidate_count = indexed_candidate_count,
        cheap_scan_cap_used = cheap_scan_cap_used,
        full_catalog_light_scan = isTRUE(full_catalog_light_scan),
        top_k_used = min(top_k, length(candidate_indexes)),
        group_branching_cap_used = group_branching_cap,
        max_group_size_used = max_group_size,
        package_top_n_used = 0L
      ),
      timings = c(timings, list(total_ms = round(sum(unlist(timings), na.rm = TRUE), 1)))
    ))
  }

  ord <- order(vapply(scored, function(entry) entry$score$score, numeric(1)), decreasing = TRUE)
  scored <- scored[ord]
  scored_positive <- scored
  if (length(scored_positive) > max_results) {
    scored <- scored_positive[seq_len(max_results)]
  } else {
    scored <- scored_positive
  }

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

  package_pool <- lapply(utils::head(scored_positive, package_top_n), function(entry) entry$card)
  stage_start <- proc.time()[["elapsed"]]
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
  response_pipeline <- list(
    catalog_size = length(precomputed$profiles),
    candidate_filter_count = candidate_filter_count,
    cheap_scan_count = length(candidate_indexes),
    deep_score_count = length(scored_all),
    package_candidate_count = length(package_pool),
    group_graph_node_count = query_synergy_as_int(groups_out$meta$node_count, default = 0L, min_value = 0L, max_value = 1000L),
    group_graph_edge_count = query_synergy_as_int(groups_out$meta$edge_count, default = 0L, min_value = 0L, max_value = 10000L),
    group_path_count = query_synergy_as_int(groups_out$meta$path_count, default = 0L, min_value = 0L, max_value = 10000L),
    group_graph_pair_count = query_synergy_as_int(groups_out$meta$pair_count, default = 0L, min_value = 0L, max_value = 100000L),
    indexed_candidate_count = indexed_candidate_count,
    cheap_scan_cap_used = cheap_scan_cap_used,
    full_catalog_light_scan = isTRUE(full_catalog_light_scan),
    top_k_used = min(top_k, length(candidate_indexes)),
    group_branching_cap_used = query_synergy_as_int(groups_out$meta$branching_cap, default = group_branching_cap, min_value = 1L, max_value = 20L),
    max_group_size_used = max_group_size,
    package_top_n_used = length(package_pool)
  )
  timings$response_assembly_ms <- query_synergy_elapsed_ms(stage_start)
  timings$total_ms <- round(sum(unlist(timings), na.rm = TRUE), 1)
  query_synergy_emit_progress(progress_callback, 100, "Completed", list(
    catalog_size = length(precomputed$profiles),
    deep_score_count = length(scored_all),
    package_candidate_count = length(package_pool)
  ))

  list(
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
}

query_synergy_group_edge_key <- function(from_id, to_id) {
  sprintf(
    "%s=>%s",
    query_api_scalar(from_id, default = ""),
    query_api_scalar(to_id, default = "")
  )
}

query_synergy_group_card_summary <- function(card) {
  list(
    id = query_api_scalar(card$id, default = ""),
    name = query_api_scalar(card$name, default = "")
  )
}

query_synergy_unique_cards_by_id <- function(cards) {
  items <- query_synergy_to_list(cards)
  if (length(items) == 0L) {
    return(list())
  }

  seen <- new.env(parent = emptyenv(), hash = TRUE)
  out <- list()
  for (card in items) {
    key <- query_api_scalar(card$id, default = query_api_scalar(card$name, default = ""))
    if (!nzchar(key) || exists(key, envir = seen, inherits = FALSE)) {
      next
    }
    assign(key, TRUE, envir = seen)
    out[[length(out) + 1L]] <- card
  }

  out
}

query_synergy_resources_compatible <- function(left, right) {
  left_value <- query_api_scalar(left, default = "")
  right_value <- query_api_scalar(right, default = "")
  if (!nzchar(left_value) || !nzchar(right_value) || identical(left_value, right_value)) {
    return(TRUE)
  }

  pair_key <- paste(sort(c(left_value, right_value)), collapse = "|")
  pair_key %in% c(
    "card|permanent",
    "card|spell",
    "creature|permanent",
    "creature|token",
    "permanent|token"
  )
}

query_synergy_group_transition_key <- function(transition) {
  paste(
    query_api_scalar(transition$kind, default = ""),
    query_api_scalar(transition$via, default = ""),
    query_api_scalar(transition$resource, default = ""),
    query_api_scalar(transition$from, default = ""),
    query_api_scalar(transition$to, default = ""),
    query_api_scalar(transition$source_event, default = query_api_scalar(transition$event, default = "")),
    query_api_scalar(transition$target_event, default = query_api_scalar(transition$event, default = "")),
    sep = "|"
  )
}

query_synergy_collect_resource_transitions <- function(source,
                                                       target,
                                                       registry = query_synergy_event_registry_default()) {
  source_card <- if (is.list(source)) source else list()
  target_card <- if (is.list(target)) target else list()
  source_moves <- query_synergy_to_list(source_card$moves)
  if (length(source_moves) == 0L) {
    source_moves <- query_synergy_build_move_records(source_card$produced_events, registry)
  }
  target_moves <- query_synergy_build_move_records(target_card$consumed_events, registry)

  out <- list()
  shared_events <- intersect(
    query_synergy_to_vector(source_card$produced_events),
    query_synergy_to_vector(target_card$consumed_events)
  )
  for (event_id in shared_events) {
    event_def <- registry$events[[event_id]]
    zones <- if (is.list(event_def$zones)) event_def$zones else list()
    out[[length(out) + 1L]] <- list(
      kind = "event_bridge",
      via = event_id,
      event = event_id,
      resource = query_api_scalar(event_def$resource, default = ""),
      from = query_api_scalar(zones$from, default = ""),
      to = query_api_scalar(zones$to, default = "")
    )
  }

  for (source_move in source_moves) {
    source_to <- query_api_scalar(source_move$to, default = "")
    if (!nzchar(source_to)) {
      next
    }

    for (target_move in target_moves) {
      target_from <- query_api_scalar(target_move$from, default = "")
      if (!nzchar(target_from) || !identical(source_to, target_from)) {
        next
      }
      if (!query_synergy_resources_compatible(source_move$resource, target_move$resource)) {
        next
      }

      out[[length(out) + 1L]] <- list(
        kind = "zone_chain",
        via = source_to,
        resource = query_api_scalar(target_move$resource, default = query_api_scalar(source_move$resource, default = "")),
        from = query_api_scalar(source_move$from, default = ""),
        to = query_api_scalar(target_move$to, default = ""),
        source_event = query_api_scalar(source_move$event, default = ""),
        target_event = query_api_scalar(target_move$event, default = "")
      )
    }
  }

  if (length(out) == 0L) {
    return(list())
  }

  seen <- new.env(parent = emptyenv(), hash = TRUE)
  deduped <- list()
  for (transition in out) {
    key <- query_synergy_group_transition_key(transition)
    if (!nzchar(key) || exists(key, envir = seen, inherits = FALSE)) {
      next
    }
    assign(key, TRUE, envir = seen)
    deduped[[length(deduped) + 1L]] <- transition
  }

  deduped
}

query_synergy_build_group_edge <- function(source,
                                           target,
                                           format_name = "commander",
                                           min_edge_score = 28L,
                                           registry = query_synergy_event_registry_default()) {
  pair <- query_synergy_score_pair(target, source, format_name)
  source_moves <- query_synergy_to_list(source$moves)
  if (length(source_moves) == 0L) {
    source_moves <- query_synergy_build_move_records(source$produced_events, registry)
  }
  transitions <- query_synergy_collect_resource_transitions(source, target, registry = registry)
  bridge_links <- query_synergy_indirect_resource_bridges(source, target)
  terminal_bridge_links <- unique(vapply(Filter(function(move) {
    identical(query_api_scalar(move$to, default = ""), "battlefield")
  }, source_moves), function(move) {
    query_api_scalar(move$event, default = "")
  }, character(1)))
  if (!any(query_synergy_to_vector(target$roles) %in% c("target", "finisher", "payoff"))) {
    terminal_bridge_links <- character(0)
  }
  matched_events <- unique(c(
    query_synergy_to_vector(pair$matched_events$enabler_to_payoff),
    query_synergy_to_vector(pair$matched_events$indirect_engine),
    query_synergy_to_vector(pair$matched_events$setup_finisher),
    query_synergy_to_vector(pair$matched_events$package_links),
    bridge_links,
    terminal_bridge_links
  ))
  role_pairs <- query_synergy_to_vector(pair$matched_events$role_pairs)
  continuity_score <- min(1,
    0.45 * suppressWarnings(as.numeric(pair$score_norm)) +
      0.2 * min(1, length(matched_events) / 3) +
      0.2 * min(1, length(transitions) / 2) +
    0.1 * min(1, length(role_pairs) / 2) +
    0.025 * min(1, length(bridge_links) / 2) +
    0.025 * min(1, length(terminal_bridge_links) / 2)
  )
  if (!is.finite(continuity_score) || is.na(continuity_score)) {
    continuity_score <- 0
  }

  hard_conflict <- length(unique(c(
    query_synergy_to_vector(pair$matched_events$replaces_payoff),
    query_synergy_to_vector(pair$matched_events$prevents_payoff)
  ))) > 0L
  valid <- !hard_conflict && (
    suppressWarnings(as.integer(pair$score)) >= query_synergy_as_int(min_edge_score, default = 28L, min_value = 1L, max_value = 100L) ||
      continuity_score >= 0.34 ||
        length(bridge_links) > 0L ||
        (length(terminal_bridge_links) > 0L && suppressWarnings(as.numeric(pair$axis_scores$role_complementarity_score)) >= 0.1) ||
      (length(transitions) > 0L && suppressWarnings(as.numeric(pair$axis_scores$role_complementarity_score)) >= 0.1) ||
      length(matched_events) > 0L
  )

  list(
    id = query_synergy_group_edge_key(source$id, target$id),
    from = query_synergy_group_card_summary(source),
    to = query_synergy_group_card_summary(target),
    score = suppressWarnings(as.integer(pair$score)),
    score_norm = suppressWarnings(as.numeric(pair$score_norm)),
    continuity_score = round(continuity_score, 4),
    axis_scores = pair$axis_scores,
    bucket_scores = pair$bucket_scores,
    primary_bucket = pair$primary_bucket,
    matched_events = list(
      direct = query_synergy_to_vector(pair$matched_events$enabler_to_payoff),
      indirect = query_synergy_to_vector(pair$matched_events$indirect_engine),
      setup_finisher = query_synergy_to_vector(pair$matched_events$setup_finisher),
      package_links = query_synergy_to_vector(pair$matched_events$package_links),
      resource_bridges = bridge_links,
      terminal_bridges = terminal_bridge_links,
      role_pairs = role_pairs
    ),
    matched_resource_transitions = transitions,
    anti_conflicts = unique(c(
      query_synergy_to_vector(pair$matched_events$replaces_payoff),
      query_synergy_to_vector(pair$matched_events$prevents_payoff),
      query_synergy_to_vector(pair$matched_events$anti_conflicts)
    )),
    anti_synergy_score = suppressWarnings(as.numeric(pair$axis_scores$anti_synergy_score)),
    relation_classes = query_synergy_to_vector(pair$relation_classes),
    reasons = unique(utils::head(query_synergy_to_vector(pair$reasons), 3L)),
    directional = pair$directional,
    valid = isTRUE(valid)
  )
}

query_synergy_build_group_graph <- function(seed,
                                            candidates,
                                            format_name = "commander",
                                            min_edge_score = 28L,
                                            progress_callback = NULL,
                                            progress_range = c(88, 97),
                                            registry = query_synergy_event_registry_default()) {
  cards <- query_synergy_unique_cards_by_id(c(list(seed), query_synergy_to_list(candidates)))
  if (length(cards) < 3L) {
    return(list(
      seed_id = query_api_scalar(seed$id, default = ""),
      nodes = list(),
      adjacency = list(),
      edge_lookup = list(),
      node_count = length(cards),
      edge_count = 0L,
      pair_count = 0L
    ))
  }

  progress_start <- suppressWarnings(as.numeric(progress_range[[1]]))
  progress_end <- suppressWarnings(as.numeric(progress_range[[2]]))
  if (!is.finite(progress_start) || is.na(progress_start)) {
    progress_start <- 88
  }
  if (!is.finite(progress_end) || is.na(progress_end)) {
    progress_end <- 97
  }

  total_pairs <- length(cards) * max(0L, length(cards) - 1L)
  stride <- max(1L, ceiling(max(1L, total_pairs) / 25L))
  pair_index <- 0L
  edge_count <- 0L
  node_lookup <- list()
  adjacency <- list()
  edge_lookup <- list()

  for (card in cards) {
    node_lookup[[query_api_scalar(card$id, default = query_api_scalar(card$name, default = ""))]] <- card
  }

  for (i in seq_along(cards)) {
    source <- cards[[i]]
    source_id <- query_api_scalar(source$id, default = "")
    if (!nzchar(source_id)) {
      next
    }

    for (j in seq_along(cards)) {
      if (i == j) {
        next
      }

      pair_index <- pair_index + 1L
      if (is.function(progress_callback) && (pair_index == 1L || pair_index == total_pairs || (pair_index %% stride) == 0L)) {
        percent <- progress_start + ((pair_index / max(1L, total_pairs)) * (progress_end - progress_start))
        query_synergy_emit_progress(progress_callback, percent, "Detecting package lines", list(processed = pair_index, total = total_pairs))
      }

      edge <- query_synergy_build_group_edge(
        source = source,
        target = cards[[j]],
        format_name = format_name,
        min_edge_score = min_edge_score,
        registry = registry
      )
      edge_lookup[[query_api_scalar(edge$id, default = "")]] <- edge
      if (!isTRUE(edge$valid)) {
        next
      }

      adjacency[[source_id]] <- c(adjacency[[source_id]], list(edge))
      edge_count <- edge_count + 1L
    }
  }

  for (node_id in names(adjacency)) {
    edges <- query_synergy_to_list(adjacency[[node_id]])
    if (length(edges) == 0L) {
      next
    }
    ord <- order(vapply(edges, function(edge) {
      continuity <- suppressWarnings(as.numeric(edge$continuity_score))
      score_norm <- suppressWarnings(as.numeric(edge$score_norm))
      if (!is.finite(continuity) || is.na(continuity)) {
        continuity <- 0
      }
      if (!is.finite(score_norm) || is.na(score_norm)) {
        score_norm <- 0
      }
      (0.6 * continuity) + (0.4 * score_norm)
    }, numeric(1)), decreasing = TRUE)
    adjacency[[node_id]] <- edges[ord]
  }

  list(
    seed_id = query_api_scalar(seed$id, default = ""),
    nodes = node_lookup,
    adjacency = adjacency,
    edge_lookup = edge_lookup,
    node_count = length(cards),
    edge_count = edge_count,
    pair_count = total_pairs
  )
}

query_synergy_search_local_group_paths <- function(seed_id,
                                                   graph,
                                                   max_group_size = 4L,
                                                   max_paths = 120L,
                                                   max_outgoing_per_node = 6L) {
  node_ids <- names(graph$nodes)
  if (!nzchar(query_api_scalar(seed_id, default = "")) || length(node_ids) < 3L) {
    return(list(paths = list(), path_count = 0L))
  }

  cap <- query_synergy_as_int(max_group_size, default = 4L, min_value = 3L, max_value = 5L)
  path_budget <- query_synergy_as_int(max_paths, default = 120L, min_value = 10L, max_value = 500L)
  branch_cap <- query_synergy_as_int(max_outgoing_per_node, default = 6L, min_value = 1L, max_value = 25L)
  seen <- new.env(parent = emptyenv(), hash = TRUE)
  out <- list()
  path_count <- 0L

  explore <- function(current_id, path_ids) {
    if (path_count >= path_budget) {
      return(invisible(NULL))
    }
    if (length(path_ids) >= cap) {
      return(invisible(NULL))
    }

    edges <- graph$adjacency[[current_id]]
    if (!is.list(edges) || length(edges) == 0L) {
      return(invisible(NULL))
    }
    if (length(edges) > branch_cap) {
      edges <- edges[seq_len(branch_cap)]
    }

    for (edge in edges) {
      if (path_count >= path_budget) {
        break
      }

      next_id <- query_api_scalar(edge$to$id, default = "")
      if (!nzchar(next_id) || next_id %in% path_ids) {
        next
      }

      next_path <- c(path_ids, next_id)
      path_count <<- path_count + 1L
      if (length(next_path) >= 3L && seed_id %in% next_path) {
        key <- paste(next_path, collapse = ">")
        if (!exists(key, envir = seen, inherits = FALSE)) {
          assign(key, TRUE, envir = seen)
          out[[length(out) + 1L]] <<- next_path
        }
      }

      if (length(next_path) < cap) {
        if (!(seed_id %in% next_path) && length(next_path) >= (cap - 1L)) {
          next
        }
        explore(next_id, next_path)
      }
    }

    invisible(NULL)
  }

  for (start_id in node_ids) {
    if (path_count >= path_budget) {
      break
    }
    explore(start_id, c(start_id))
  }

  list(paths = out, path_count = path_count)
}

query_synergy_infer_group_member_role <- function(card,
                                                  position_index,
                                                  member_count,
                                                  incoming_edge = NULL,
                                                  outgoing_edge = NULL) {
  roles <- query_synergy_to_vector(card$roles)
  if (position_index >= member_count) {
    terminal_roles <- c("finisher", "payoff", "target", "engine", "bridge")
    matched <- terminal_roles[terminal_roles %in% roles]
    if (length(matched) > 0L) {
      return(matched[[1]])
    }
    return("target")
  }

  if (position_index <= 1L) {
    if ("setup" %in% roles) {
      return("setup")
    }
    if ("engine" %in% roles) {
      return("engine")
    }
    if ("producer" %in% roles && !any(roles %in% c("payoff", "finisher", "target"))) {
      return("fuel")
    }
    opening_roles <- c("bridge", "converter", "amplifier")
    matched <- opening_roles[opening_roles %in% roles]
    if (length(matched) > 0L) {
      return(matched[[1]])
    }
    return("fuel")
  }

  if ("amplifier" %in% roles) {
    return("amplifier")
  }
  if ("engine" %in% roles && isTRUE(card$cadence$repeatable)) {
    return("engine")
  }
  if ("converter" %in% roles) {
    return("converter")
  }
  if ("bridge" %in% roles) {
    return("bridge")
  }
  if ("engine" %in% roles) {
    return("engine")
  }
  if ("producer" %in% roles && length(query_synergy_to_list(outgoing_edge$matched_resource_transitions)) > 0L) {
    return("fuel")
  }
  if ("setup" %in% roles) {
    return("setup")
  }
  if ("payoff" %in% roles) {
    return("payoff")
  }
  if ("target" %in% roles) {
    return("target")
  }
  "bridge"
}

query_synergy_group_role_coverage_score <- function(member_roles) {
  roles <- query_synergy_to_vector(member_roles)
  if (length(roles) == 0L) {
    return(0)
  }

  start_ok <- roles[[1]] %in% c("setup", "fuel", "engine", "bridge", "converter")
  end_ok <- roles[[length(roles)]] %in% c("payoff", "finisher", "target")
  middle_roles <- if (length(roles) > 2L) roles[2:(length(roles) - 1L)] else character(0)
  middle_ok <- if (length(middle_roles) == 0L) {
    1
  } else {
    sum(middle_roles %in% c("engine", "converter", "bridge", "amplifier", "fuel")) / length(middle_roles)
  }
  diversity <- min(1, length(unique(roles)) / min(length(roles), 4L))

  round(min(1,
    0.3 * as.numeric(start_ok) +
      0.3 * as.numeric(end_ok) +
      0.25 * middle_ok +
      0.15 * diversity
  ), 4)
}

query_synergy_group_category <- function(member_roles,
                                         member_count,
                                         anti_synergy_penalty = 0,
                                         resource_transitions = list()) {
  roles <- query_synergy_to_vector(member_roles)
  if (anti_synergy_penalty >= 0.45) {
    return("conflicted_group")
  }
  if (member_count >= 4L) {
    return("multi_step_package_line")
  }
  if ("amplifier" %in% roles && any(c("finisher", "payoff") %in% roles)) {
    return("amplifier_finish_line")
  }
  if ("setup" %in% roles && "converter" %in% roles && any(c("payoff", "finisher", "target") %in% roles)) {
    return("setup_converter_payoff")
  }
  if ("fuel" %in% roles && "engine" %in% roles && any(c("payoff", "finisher", "target") %in% roles)) {
    return("fuel_engine_payoff")
  }
  if ("bridge" %in% roles) {
    return("bridge_line")
  }
  if (length(query_synergy_to_list(resource_transitions)) > 0L) {
    return("resource_flow_line")
  }
  "general_synergy_group"
}

query_synergy_group_pair_penalty <- function(path_ids, graph) {
  ids <- query_synergy_to_vector(path_ids)
  if (length(ids) < 2L) {
    return(list(penalty = 0, conflicts = character(0)))
  }

  anti_scores <- numeric(0)
  conflicts <- character(0)
  for (i in seq_len(length(ids) - 1L)) {
    for (j in seq.int(i + 1L, length(ids))) {
      edge_keys <- c(
        query_synergy_group_edge_key(ids[[i]], ids[[j]]),
        query_synergy_group_edge_key(ids[[j]], ids[[i]])
      )
      for (edge_key in edge_keys) {
        edge <- graph$edge_lookup[[edge_key]]
        if (!is.list(edge)) {
          next
        }
        anti_value <- suppressWarnings(as.numeric(edge$anti_synergy_score))
        if (is.finite(anti_value) && !is.na(anti_value)) {
          anti_scores <- c(anti_scores, anti_value)
        }
        conflicts <- c(conflicts, query_synergy_to_vector(edge$anti_conflicts))
      }
    }
  }

  penalty <- if (length(anti_scores) > 0L) {
    min(1, mean(anti_scores) + if (length(conflicts) > 0L) 0.18 else 0)
  } else {
    0
  }

  list(penalty = round(penalty, 4), conflicts = unique(conflicts))
}

query_synergy_group_reason_lines <- function(cards,
                                             member_roles,
                                             matched_events,
                                             resource_transitions,
                                             score_breakdown,
                                             anti_conflicts) {
  role_line <- paste(vapply(seq_along(cards), function(index) {
    sprintf(
      "%s as %s",
      query_api_scalar(cards[[index]]$name, default = sprintf("Card %s", index)),
      query_api_scalar(member_roles[[index]], default = "bridge")
    )
  }, character(1)), collapse = " -> ")

  reasons <- c(sprintf("Package line: %s", role_line))
  if (length(matched_events) > 0L) {
    reasons <- c(reasons, sprintf(
      "Chain continuity via %s",
      paste(utils::head(query_synergy_to_vector(matched_events), 5L), collapse = ", ")
    ))
  }
  if (length(query_synergy_to_list(resource_transitions)) > 0L) {
    transition_text <- paste(vapply(utils::head(query_synergy_to_list(resource_transitions), 3L), function(transition) {
      via <- query_api_scalar(transition$via, default = query_api_scalar(transition$resource, default = "resource"))
      from <- query_api_scalar(transition$from, default = "")
      to <- query_api_scalar(transition$to, default = "")
      if (nzchar(from) || nzchar(to)) {
        sprintf("%s (%s -> %s)", via, if (nzchar(from)) from else "?", if (nzchar(to)) to else "?")
      } else {
        via
      }
    }, character(1)), collapse = "; ")
    reasons <- c(reasons, sprintf("Resource flow through %s", transition_text))
  }

  strengths <- character(0)
  if (suppressWarnings(as.numeric(score_breakdown$role_coverage)) >= 0.35) {
    strengths <- c(strengths, "role coverage")
  }
  if (suppressWarnings(as.numeric(score_breakdown$strategic_coherence)) >= 0.28) {
    strengths <- c(strengths, "strategic coherence")
  }
  if (suppressWarnings(as.numeric(score_breakdown$repetition_potential)) >= 0.28) {
    strengths <- c(strengths, "repetition potential")
  }
  if (suppressWarnings(as.numeric(score_breakdown$finisher_quality)) >= 0.3) {
    strengths <- c(strengths, "finisher quality")
  }
  if (length(strengths) > 0L) {
    reasons <- c(reasons, sprintf("Scores well because of %s", paste(strengths, collapse = ", ")))
  }
  if (length(anti_conflicts) > 0L) {
    reasons <- c(reasons, sprintf(
      "Anti-synergy penalty from %s",
      paste(utils::head(query_synergy_to_vector(anti_conflicts), 4L), collapse = ", ")
    ))
  }

  unique(reasons)
}

query_synergy_build_synergy_group <- function(path_ids,
                                              seed_id,
                                              graph,
                                              registry = query_synergy_event_registry_default()) {
  ids <- query_synergy_to_vector(path_ids)
  if (length(ids) < 3L || !(seed_id %in% ids)) {
    return(NULL)
  }

  cards <- lapply(ids, function(id) graph$nodes[[id]])
  if (any(!vapply(cards, is.list, logical(1)))) {
    return(NULL)
  }

  edges <- vector("list", max(0L, length(ids) - 1L))
  for (index in seq_len(length(ids) - 1L)) {
    edge <- graph$edge_lookup[[query_synergy_group_edge_key(ids[[index]], ids[[index + 1L]])]]
    if (!is.list(edge) || !isTRUE(edge$valid)) {
      return(NULL)
    }
    edges[[index]] <- edge
  }

  member_roles <- vapply(seq_along(cards), function(index) {
    incoming_edge <- if (index > 1L) edges[[index - 1L]] else NULL
    outgoing_edge <- if (index <= length(edges)) edges[[index]] else NULL
    query_synergy_infer_group_member_role(
      cards[[index]],
      position_index = index,
      member_count = length(cards),
      incoming_edge = incoming_edge,
      outgoing_edge = outgoing_edge
    )
  }, character(1))

  if (!(member_roles[[1]] %in% c("setup", "fuel", "engine", "bridge", "converter")) ||
      !(member_roles[[length(member_roles)]] %in% c("payoff", "finisher", "target"))) {
    return(NULL)
  }

  edge_continuity <- vapply(edges, function(edge) {
    value <- suppressWarnings(as.numeric(edge$continuity_score))
    if (!is.finite(value) || is.na(value)) 0 else value
  }, numeric(1))
  edge_shared_plan <- vapply(edges, function(edge) {
    value <- suppressWarnings(as.numeric(edge$axis_scores$shared_plan_score))
    if (!is.finite(value) || is.na(value)) 0 else value
  }, numeric(1))
  cadence_values <- vapply(cards, function(card) {
    value <- suppressWarnings(as.numeric(card$cadence$strength))
    if (!is.finite(value) || is.na(value)) 0 else value
  }, numeric(1))

  resource_transitions <- unique(unlist(lapply(edges, function(edge) {
    query_synergy_to_list(edge$matched_resource_transitions)
  }), recursive = FALSE), use.names = FALSE)
  matched_events <- unique(c(
    unlist(lapply(edges, function(edge) query_synergy_to_vector(edge$matched_events$direct)), use.names = FALSE),
    unlist(lapply(edges, function(edge) query_synergy_to_vector(edge$matched_events$indirect)), use.names = FALSE),
    unlist(lapply(edges, function(edge) query_synergy_to_vector(edge$matched_events$setup_finisher)), use.names = FALSE),
    unlist(lapply(edges, function(edge) query_synergy_to_vector(edge$matched_events$package_links)), use.names = FALSE),
    unlist(lapply(edges, function(edge) query_synergy_to_vector(edge$matched_events$resource_bridges)), use.names = FALSE),
    unlist(lapply(edges, function(edge) query_synergy_to_vector(edge$matched_events$terminal_bridges)), use.names = FALSE)
  ))

  resource_flow_quality <- if (length(edges) > 0L) {
    mean(vapply(edges, function(edge) {
      event_links <- unique(c(
        query_synergy_to_vector(edge$matched_events$direct),
        query_synergy_to_vector(edge$matched_events$indirect),
        query_synergy_to_vector(edge$matched_events$setup_finisher),
        query_synergy_to_vector(edge$matched_events$resource_bridges),
        query_synergy_to_vector(edge$matched_events$terminal_bridges)
      ))
      min(1,
        0.55 * min(1, length(query_synergy_to_list(edge$matched_resource_transitions)) / 2) +
          0.45 * min(1, length(event_links) / 2)
      )
    }, numeric(1)))
  } else {
    0
  }
  chain_continuity <- if (length(edge_continuity) > 0L) {
    min(1, 0.5 * mean(edge_continuity) + 0.3 * min(edge_continuity) + 0.2 * resource_flow_quality)
  } else {
    0
  }

  strategy_tags <- lapply(cards, function(card) unique(query_synergy_to_vector(card$strategy_tags)))
  tag_union <- unique(unlist(strategy_tags, use.names = FALSE))
  tag_intersection <- if (length(strategy_tags) > 0L) Reduce(intersect, strategy_tags) else character(0)
  strategic_coherence <- min(1,
    0.65 * if (length(edge_shared_plan) > 0L) mean(edge_shared_plan) else 0 +
      0.35 * if (length(tag_union) > 0L) length(tag_intersection) / length(tag_union) else 0
  )
  role_coverage <- query_synergy_group_role_coverage_score(member_roles)
  engine_related <- member_roles %in% c("engine", "converter", "bridge", "amplifier")
  cadence_pool <- if (any(engine_related)) cadence_values[engine_related] else cadence_values
  repetition_potential <- min(1,
    if (length(cadence_pool) > 0L) mean(utils::head(sort(cadence_pool, decreasing = TRUE), 2L)) else 0 +
      min(0.15, sum(vapply(cards, function(card) isTRUE(card$cadence$repeatable), logical(1))) * 0.05)
  )
  amplification_bonus <- if ("amplifier" %in% member_roles) {
    min(1, 0.45 + 0.15 * sum(member_roles %in% c("engine", "converter", "bridge")) + 0.2 * repetition_potential)
  } else {
    0
  }
  final_edge <- if (length(edges) > 0L) edges[[length(edges)]] else NULL
  finisher_quality <- if (is.list(final_edge)) {
    min(1,
      0.45 * as.numeric(member_roles[[length(member_roles)]] %in% c("payoff", "finisher", "target")) +
        0.4 * max(0, suppressWarnings(as.numeric(final_edge$score_norm))) +
        0.15 * min(1, length(unique(c(
          query_synergy_to_vector(final_edge$matched_events$direct),
          query_synergy_to_vector(final_edge$matched_events$indirect)
        ))) / 2)
    )
  } else {
    0
  }

  pair_penalty <- query_synergy_group_pair_penalty(ids, graph)
  role_duplication <- sum(pmax(0L, as.integer(table(member_roles)) - 1L)) / max(1, length(member_roles))
  event_duplication <- {
    event_table <- table(matched_events)
    if (length(event_table) == 0L) 0 else sum(pmax(0L, as.integer(event_table) - 1L)) / max(1, length(event_table))
  }
  redundancy_penalty <- min(1, 0.65 * role_duplication + 0.35 * event_duplication)
  complexity_penalty <- min(1,
    if (length(cards) <= 3L) {
      0.04 + (1 - chain_continuity) * 0.04
    } else {
      0.12 + ((length(cards) - 4L) * 0.06) + (1 - chain_continuity) * 0.08
    }
  )

  score_breakdown <- list(
    chain_continuity = round(chain_continuity, 4),
    role_coverage = round(role_coverage, 4),
    strategic_coherence = round(strategic_coherence, 4),
    resource_flow_quality = round(resource_flow_quality, 4),
    repetition_potential = round(repetition_potential, 4),
    amplification_bonus = round(amplification_bonus, 4),
    finisher_quality = round(finisher_quality, 4),
    anti_synergy_penalty = round(pair_penalty$penalty, 4),
    redundancy_penalty = round(redundancy_penalty, 4),
    complexity_penalty = round(complexity_penalty, 4)
  )

  score_norm <-
    0.22 * score_breakdown$chain_continuity +
    0.14 * score_breakdown$role_coverage +
    0.12 * score_breakdown$strategic_coherence +
    0.14 * score_breakdown$resource_flow_quality +
    0.1 * score_breakdown$repetition_potential +
    0.08 * score_breakdown$amplification_bonus +
    0.12 * score_breakdown$finisher_quality -
    0.12 * score_breakdown$anti_synergy_penalty -
    0.08 * score_breakdown$redundancy_penalty -
    0.08 * score_breakdown$complexity_penalty
  score_norm <- max(0, min(1, score_norm))
  if (score_norm <= 0.14 || chain_continuity <= 0.16) {
    return(NULL)
  }

  category <- query_synergy_group_category(
    member_roles = member_roles,
    member_count = length(cards),
    anti_synergy_penalty = pair_penalty$penalty,
    resource_transitions = resource_transitions
  )
  bucket <- if (length(cards) >= 4L) "package_lines" else "synergy_groups"
  members <- lapply(seq_along(cards), function(index) {
    card <- cards[[index]]
    list(
      id = query_api_scalar(card$id, default = ""),
      name = query_api_scalar(card$name, default = ""),
      inferred_role = query_api_scalar(member_roles[[index]], default = "bridge"),
      roles = query_synergy_to_vector(card$roles),
      target_roles = query_synergy_to_vector(card$target_roles),
      position = index,
      is_seed = identical(query_api_scalar(card$id, default = ""), query_api_scalar(seed_id, default = ""))
    )
  })
  intermediate_members <- if (length(members) > 2L) {
    members[2:(length(members) - 1L)]
  } else {
    list()
  }
  package_structure <- list(
    start_member = members[[1]],
    end_member = members[[length(members)]],
    intermediate_members = intermediate_members,
    intermediate_count = length(intermediate_members),
    line_signature = paste(member_roles, collapse = " -> ")
  )
  reasons <- query_synergy_group_reason_lines(
    cards = cards,
    member_roles = member_roles,
    matched_events = matched_events,
    resource_transitions = resource_transitions,
    score_breakdown = score_breakdown,
    anti_conflicts = pair_penalty$conflicts
  )
  line_edges <- lapply(edges, function(edge) {
    list(
      from = edge$from,
      to = edge$to,
      score = edge$score,
      continuity_score = edge$continuity_score,
      matched_events = unique(c(
        query_synergy_to_vector(edge$matched_events$direct),
        query_synergy_to_vector(edge$matched_events$indirect),
        query_synergy_to_vector(edge$matched_events$setup_finisher),
        query_synergy_to_vector(edge$matched_events$package_links),
        query_synergy_to_vector(edge$matched_events$resource_bridges),
        query_synergy_to_vector(edge$matched_events$terminal_bridges)
      )),
      matched_resource_transitions = query_synergy_to_list(edge$matched_resource_transitions),
      relation_classes = query_synergy_to_vector(edge$relation_classes)
    )
  })

  list(
    id = paste(ids, collapse = "|"),
    group_type = if (length(cards) >= 4L) "package_line" else "synergy_group",
    bucket = bucket,
    bucket_label = query_api_scalar(query_synergy_bucket_labels()[[bucket]], default = bucket),
    package_bucket = bucket,
    category = category,
    package_category = category,
    archetype = category,
    score = as.integer(round(score_norm * 100)),
    total_score = as.integer(round(score_norm * 100)),
    score_norm = round(score_norm, 4),
    score_breakdown = score_breakdown,
    members = members,
    cards = stats::setNames(lapply(members, function(member) list(id = member$id, name = member$name)), make.unique(member_roles)),
    chain = list(
      member_ids = ids,
      member_names = vapply(cards, function(card) query_api_scalar(card$name, default = ""), character(1)),
      role_sequence = member_roles,
      edge_count = length(edges)
    ),
    edges = line_edges,
    package_structure = package_structure,
    line = list(
      member_ids = ids,
      edges = line_edges
    ),
    matched_events = matched_events,
    matched_resource_transitions = resource_transitions,
    anti_conflicts = pair_penalty$conflicts,
    reasons = reasons,
    explanation_text = paste(utils::head(reasons, 3L), collapse = " ")
  )
}

query_synergy_build_group_bucket <- function(groups, bucket_key, limit = 10L) {
  labels <- query_synergy_bucket_labels()
  pool <- query_synergy_to_list(groups)
  if (identical(bucket_key, "package_lines")) {
    pool <- Filter(function(entry) identical(query_api_scalar(entry$bucket, default = ""), "package_lines"), pool)
  }

  if (length(pool) == 0L) {
    return(list(
      key = bucket_key,
      label = query_api_scalar(labels[[bucket_key]], default = bucket_key),
      count = 0L,
      results = list()
    ))
  }

  ord <- order(
    vapply(pool, function(entry) suppressWarnings(as.numeric(entry$total_score)), numeric(1)),
    vapply(pool, function(entry) -length(query_synergy_to_vector(entry$chain$member_ids)), numeric(1)),
    decreasing = TRUE
  )
  pool <- pool[ord]
  cap <- query_synergy_as_int(limit, default = 10L, min_value = 1L, max_value = 50L)
  if (length(pool) > cap) {
    pool <- pool[seq_len(cap)]
  }

  list(
    key = bucket_key,
    label = query_api_scalar(labels[[bucket_key]], default = bucket_key),
    count = length(pool),
    results = pool
  )
}

query_synergy_detect_groups_for_seed <- function(seed,
                                                 candidates,
                                                 format_name = "commander",
                                                 max_groups = 10L,
                                                 min_edge_score = 28L,
                                                 max_group_size = 4L,
                                                 max_paths = 120L,
                                                 max_branching = 6L,
                                                 progress_callback = NULL,
                                                 progress_range = c(88, 97),
                                                 registry = query_synergy_event_registry_default()) {
  cards <- query_synergy_to_list(candidates)
  if (!is.list(seed) || length(cards) < 2L) {
    return(list(
      groups = list(),
      package_lines = list(),
      meta = list(node_count = 0L, edge_count = 0L, path_count = 0L, pair_count = 0L, branching_cap = 0L)
    ))
  }

  graph <- query_synergy_build_group_graph(
    seed = seed,
    candidates = cards,
    format_name = format_name,
    min_edge_score = min_edge_score,
    progress_callback = progress_callback,
    progress_range = progress_range,
    registry = registry
  )
  search_out <- query_synergy_search_local_group_paths(
    seed_id = query_api_scalar(seed$id, default = ""),
    graph = graph,
    max_group_size = max_group_size,
    max_paths = max_paths,
    max_outgoing_per_node = max_branching
  )

  groups <- list()
  for (path_ids in search_out$paths) {
    group <- query_synergy_build_synergy_group(
      path_ids = path_ids,
      seed_id = query_api_scalar(seed$id, default = ""),
      graph = graph,
      registry = registry
    )
    if (!is.list(group)) {
      next
    }
    groups[[length(groups) + 1L]] <- group
  }

  if (length(groups) == 0L) {
    return(list(
      groups = list(),
      package_lines = list(),
      meta = list(
        node_count = graph$node_count,
        edge_count = graph$edge_count,
        path_count = search_out$path_count,
        pair_count = graph$pair_count,
        branching_cap = query_synergy_as_int(max_branching, default = 6L, min_value = 1L, max_value = 25L)
      )
    ))
  }

  seen <- new.env(parent = emptyenv(), hash = TRUE)
  deduped <- list()
  for (group in groups) {
    key <- query_api_scalar(group$id, default = "")
    if (!nzchar(key) || exists(key, envir = seen, inherits = FALSE)) {
      next
    }
    assign(key, TRUE, envir = seen)
    deduped[[length(deduped) + 1L]] <- group
  }

  ord <- order(
    vapply(deduped, function(entry) suppressWarnings(as.numeric(entry$total_score)), numeric(1)),
    vapply(deduped, function(entry) suppressWarnings(as.numeric(entry$score_breakdown$chain_continuity)), numeric(1)),
    decreasing = TRUE
  )
  deduped <- deduped[ord]
  limit <- query_synergy_as_int(max_groups, default = 10L, min_value = 1L, max_value = 50L)
  if (length(deduped) > limit) {
    deduped <- deduped[seq_len(limit)]
  }

  list(
    groups = deduped,
    package_lines = Filter(function(entry) identical(query_api_scalar(entry$bucket, default = ""), "package_lines"), deduped),
    meta = list(
      node_count = graph$node_count,
      edge_count = graph$edge_count,
      path_count = search_out$path_count,
      pair_count = graph$pair_count,
      branching_cap = query_synergy_as_int(max_branching, default = 6L, min_value = 1L, max_value = 25L)
    )
  )
}

query_synergy_detect_packages_for_target <- function(target,
                                                     candidates,
                                                     format_name = "commander",
                                                     max_packages = 10L,
                                                     min_edge_score = 35L,
                                                     progress_callback = NULL,
                                                     progress_range = c(88, 97)) {
  group_out <- query_synergy_detect_groups_for_seed(
    seed = target,
    candidates = candidates,
    format_name = format_name,
    max_groups = max_packages,
    min_edge_score = min_edge_score,
    max_group_size = 4L,
    max_paths = max(96L, length(query_synergy_to_list(candidates)) * 12L),
    max_branching = 6L,
    progress_callback = progress_callback,
    progress_range = progress_range
  )

  query_synergy_to_list(group_out$groups)
}

query_synergy_elapsed_ms <- function(start_elapsed) {
  end_elapsed <- proc.time()[["elapsed"]]
  round(max(0, (end_elapsed - start_elapsed) * 1000), 1)
}

query_synergy_emit_progress <- function(callback, percent = 0, stage = "", meta = list()) {
  if (!is.function(callback)) {
    return(invisible(NULL))
  }

  payload <- list(
    percent = as.integer(round(max(0, min(100, suppressWarnings(as.numeric(percent)) %||% 0)))),
    stage = query_api_scalar(stage, default = ""),
    meta = if (is.list(meta)) meta else list()
  )
  tryCatch(callback(payload), error = function(e) NULL)
  invisible(payload)
}

query_synergy_precompute_version <- function() {
  "synergy_precompute_v1"
}

query_synergy_card_signature <- function(card) {
  paste(
    query_synergy_card_id(card),
    query_api_scalar(card$name, default = ""),
    query_api_scalar(card$oracle_text, default = query_api_scalar(card$printed_text, default = "")),
    query_api_scalar(card$type_line, default = ""),
    query_api_scalar(card$cmc, default = ""),
    paste(query_synergy_card_color_identity(card), collapse = ""),
    paste(query_synergy_to_vector(card$keywords), collapse = ","),
    sep = "|"
  )
}

query_synergy_catalog_fingerprint <- function(cards) {
  values <- query_synergy_to_list(cards)
  if (length(values) == 0L) {
    return("empty")
  }

  acc_a <- 0
  acc_b <- 1
  modulus <- 2147483647
  for (index in seq_along(values)) {
    chars <- utf8ToInt(query_synergy_card_signature(values[[index]]))
    if (length(chars) == 0L) {
      next
    }

    weighted_sum <- sum(chars * (((seq_along(chars) - 1L) %% 31L) + 1L))
    acc_a <- (acc_a + weighted_sum + (index * 17L)) %% modulus
    acc_b <- ((acc_b * 131) + sum(chars) + (index * 97L)) %% modulus
  }

  sprintf("%08x%08x", as.integer(round(acc_a)), as.integer(round(acc_b)))
}

query_synergy_catalog_cache_key <- function(cards, source = "", source_signature = "") {
  values <- query_synergy_to_list(cards)
  if (length(values) == 0L) {
    return("")
  }

  source_name <- query_api_scalar(source, default = "catalog")
  signature <- query_api_scalar(
    source_signature,
    default = query_api_scalar(attr(cards, "synergy_source_signature"), default = "")
  )
  if (identical(source_name, "scryfall_oracle_cards") && nzchar(signature)) {
    return(sprintf(
      "%s|%s|%s",
      query_synergy_precompute_version(),
      source_name,
      signature
    ))
  }

  ids <- vapply(values, query_synergy_card_id, character(1))
  ids <- ids[nzchar(ids)]
  first_id <- if (length(ids) > 0L) ids[[1]] else ""
  last_id <- if (length(ids) > 0L) ids[[length(ids)]] else ""
  sprintf(
    "%s|%s|%s|%s|%s",
    query_synergy_precompute_version(),
    source_name,
    length(values),
    paste(first_id, last_id, sep = "::"),
    query_synergy_catalog_fingerprint(values)
  )
}

query_synergy_file_signature <- function(path) {
  file_path <- trimws(as.character(path))
  if (!nzchar(file_path) || !file.exists(file_path)) {
    return("")
  }

  info <- file.info(file_path)
  size_value <- suppressWarnings(as.numeric(info$size[[1]]))
  mtime_value <- suppressWarnings(as.numeric(as.POSIXct(info$mtime[[1]], tz = "UTC")))
  if (!is.finite(size_value) || is.na(size_value) || !is.finite(mtime_value) || is.na(mtime_value)) {
    return("")
  }

  sprintf("%s::%s", as.integer(round(size_value)), as.integer(round(mtime_value)))
}

query_synergy_build_compact_profile <- function(card, registry = query_synergy_event_registry_default()) {
  normalized <- if (is.list(card) && identical(query_api_scalar(card$model_version, default = ""), "normalized_card_v2")) {
    card
  } else {
    query_synergy_normalize_card(card, registry = registry)
  }

  cadence_strength <- suppressWarnings(as.numeric(normalized$cadence$strength))
  if (!is.finite(cadence_strength) || is.na(cadence_strength)) {
    cadence_strength <- 0
  }

  list(
    id = query_api_scalar(normalized$id, default = ""),
    name = query_api_scalar(normalized$name, default = ""),
    produced_events = unique(query_synergy_to_vector(normalized$produced_events)),
    consumed_events = unique(query_synergy_to_vector(normalized$consumed_events)),
    replaced_events = unique(query_synergy_to_vector(normalized$replaced_events)),
    prevented_events = unique(query_synergy_to_vector(normalized$prevented_events)),
    setup_events = unique(query_synergy_to_vector(normalized$setup_events)),
    finisher_events = unique(query_synergy_to_vector(normalized$finisher_events)),
    produced_families = unique(query_synergy_event_family_keys(normalized$produced_events, registry)),
    consumed_families = unique(query_synergy_event_family_keys(normalized$consumed_events, registry)),
    strategy_tags = unique(query_synergy_to_vector(normalized$strategy_tags)),
    roles = unique(query_synergy_to_vector(normalized$roles)),
    target_roles = unique(query_synergy_to_vector(normalized$target_roles)),
    anti_tags = unique(query_synergy_to_vector(normalized$anti_tags)),
    cadence = list(
      class = query_api_scalar(normalized$cadence$class, default = "one_shot"),
      repeatable = isTRUE(normalized$cadence$repeatable),
      strength = cadence_strength
    ),
    mana_value = suppressWarnings(as.numeric(normalized$mana_value)),
    color_identity = unique(query_synergy_to_vector(normalized$color_identity)),
    legalities = normalized$legalities
  )
}

query_synergy_build_profile_index_map <- function(profiles, selector) {
  items <- query_synergy_to_list(profiles)
  index_env <- new.env(parent = emptyenv(), hash = TRUE)

  for (i in seq_along(items)) {
    values <- unique(query_synergy_to_vector(selector(items[[i]])))
    if (length(values) == 0L) {
      next
    }

    for (value in values) {
      key <- query_api_scalar(value, default = "")
      if (!nzchar(key)) {
        next
      }

      if (exists(key, envir = index_env, inherits = FALSE)) {
        assign(key, c(get(key, envir = index_env, inherits = FALSE), i), envir = index_env)
      } else {
        assign(key, i, envir = index_env)
      }
    }
  }

  out <- as.list(index_env, all.names = TRUE)
  lapply(out, function(entry) unique(as.integer(entry)))
}

query_synergy_build_profile_indexes <- function(profiles) {
  items <- query_synergy_to_list(profiles)
  if (length(items) == 0L) {
    return(list())
  }

  list(
    produced_events = query_synergy_build_profile_index_map(items, function(profile) profile$produced_events),
    consumed_events = query_synergy_build_profile_index_map(items, function(profile) profile$consumed_events),
    replaced_events = query_synergy_build_profile_index_map(items, function(profile) profile$replaced_events),
    prevented_events = query_synergy_build_profile_index_map(items, function(profile) profile$prevented_events),
    setup_events = query_synergy_build_profile_index_map(items, function(profile) profile$setup_events),
    finisher_events = query_synergy_build_profile_index_map(items, function(profile) profile$finisher_events),
    produced_families = query_synergy_build_profile_index_map(items, function(profile) profile$produced_families),
    consumed_families = query_synergy_build_profile_index_map(items, function(profile) profile$consumed_families),
    strategy_tags = query_synergy_build_profile_index_map(items, function(profile) profile$strategy_tags),
    roles = query_synergy_build_profile_index_map(items, function(profile) profile$roles),
    anti_tags = query_synergy_build_profile_index_map(items, function(profile) profile$anti_tags)
  )
}

query_synergy_index_lookup <- function(index_map, keys) {
  if (!is.list(index_map) || length(index_map) == 0L) {
    return(integer(0))
  }

  values <- unique(query_synergy_to_vector(keys))
  if (length(values) == 0L) {
    return(integer(0))
  }

  hits <- unlist(lapply(values, function(value) {
    key <- query_api_scalar(value, default = "")
    if (!nzchar(key) || is.null(index_map[[key]])) {
      return(integer(0))
    }
    as.integer(index_map[[key]])
  }), use.names = FALSE)

  unique(hits[hits > 0L])
}

query_synergy_candidate_roles_for_target <- function(target_roles = character(0), target_target_roles = character(0)) {
  target_values <- unique(query_synergy_to_vector(target_roles))
  if (length(query_synergy_to_vector(target_target_roles)) > 0L && !"target" %in% target_values) {
    target_values <- c(target_values, "target")
  }

  candidate_roles <- character(0)
  if ("payoff" %in% target_values) {
    candidate_roles <- c(candidate_roles, "producer", "engine", "converter", "bridge", "amplifier")
  }
  if ("target" %in% target_values) {
    candidate_roles <- c(candidate_roles, "producer", "engine")
  }
  if ("finisher" %in% target_values) {
    candidate_roles <- c(candidate_roles, "setup", "converter", "bridge")
  }
  if ("setup" %in% target_values) {
    candidate_roles <- c(candidate_roles, "finisher", "converter", "bridge")
  }
  if ("producer" %in% target_values) {
    candidate_roles <- c(candidate_roles, "payoff", "target", "amplifier")
  }
  if ("engine" %in% target_values) {
    candidate_roles <- c(candidate_roles, "payoff", "target", "amplifier")
  }
  if ("bridge" %in% target_values) {
    candidate_roles <- c(candidate_roles, "payoff", "finisher")
  }

  if (length(candidate_roles) == 0L) {
    candidate_roles <- c("producer", "payoff", "engine", "setup", "converter", "bridge", "amplifier", "target", "finisher")
  }

  unique(candidate_roles)
}

query_synergy_collect_indexed_candidate_indexes <- function(target,
                                                            precomputed,
                                                            top_k = 50L) {
  indexes <- if (is.list(precomputed$indexes)) precomputed$indexes else list()
  if (length(indexes) == 0L || !is.list(target)) {
    return(integer(0))
  }

  target_roles <- query_synergy_candidate_roles_for_target(target$roles, target$target_roles)
  signal_hits <- c(
    query_synergy_index_lookup(indexes$produced_events, target$consumed_events),
    query_synergy_index_lookup(indexes$produced_events, target$consumed_events),
    query_synergy_index_lookup(indexes$consumed_events, target$produced_events),
    query_synergy_index_lookup(indexes$consumed_events, target$produced_events),
    query_synergy_index_lookup(indexes$produced_families, target$consumed_families),
    query_synergy_index_lookup(indexes$consumed_families, target$produced_families),
    query_synergy_index_lookup(indexes$strategy_tags, target$strategy_tags),
    query_synergy_index_lookup(indexes$roles, target_roles),
    query_synergy_index_lookup(indexes$setup_events, target$finisher_events),
    query_synergy_index_lookup(indexes$finisher_events, target$setup_events),
    query_synergy_index_lookup(indexes$replaced_events, target$consumed_events),
    query_synergy_index_lookup(indexes$prevented_events, target$consumed_events),
    query_synergy_index_lookup(indexes$anti_tags, target$anti_tags)
  )
  signal_hits <- as.integer(signal_hits[signal_hits > 0L])
  if (length(signal_hits) == 0L) {
    return(integer(0))
  }

  ranked_counts <- sort(table(signal_hits), decreasing = TRUE)
  ranked_indexes <- as.integer(names(ranked_counts))
  keep_n <- min(length(ranked_indexes), max(384L, as.integer(top_k) * 16L))
  ranked_indexes[seq_len(keep_n)]
}

query_synergy_build_precomputed_catalog <- function(catalog,
                                                    registry = query_synergy_event_registry_default(),
                                                    progress_callback = NULL,
                                                    progress_range = c(6, 30)) {
  cards <- query_synergy_to_list(catalog)
  if (length(cards) == 0L) {
    return(list(normalized = list(), profiles = list(), indexes = list()))
  }

  progress_start <- suppressWarnings(as.numeric(progress_range[[1]]))
  progress_end <- suppressWarnings(as.numeric(progress_range[[2]]))
  if (!is.finite(progress_start) || is.na(progress_start)) {
    progress_start <- 6
  }
  if (!is.finite(progress_end) || is.na(progress_end)) {
    progress_end <- 30
  }

  normalized <- vector("list", length(cards))
  profiles <- vector("list", length(cards))
  stride <- max(1L, ceiling(max(1L, length(cards)) / 30L))
  for (i in seq_along(cards)) {
    normalized_card <- query_synergy_normalize_card_cached(cards[[i]], registry = registry)
    normalized[[i]] <- normalized_card
    profiles[[i]] <- query_synergy_build_compact_profile(normalized_card, registry = registry)
    if (is.function(progress_callback) && (i == 1L || i == length(cards) || (i %% stride) == 0L)) {
      percent <- progress_start + ((i / max(1L, length(cards))) * (progress_end - progress_start))
      query_synergy_emit_progress(progress_callback, percent, "Precomputing normalized catalog", list(processed = i, total = length(cards)))
    }
  }

  list(
    normalized = normalized,
    profiles = profiles,
    indexes = query_synergy_build_profile_indexes(profiles)
  )
}

query_synergy_get_precomputed_catalog <- function(catalog,
                                                  registry = query_synergy_event_registry_default(),
                                                  force_refresh = FALSE,
                                                  progress_callback = NULL,
                                                  cache_dir = "") {
  cards <- query_synergy_to_list(catalog)
  cache_key <- query_api_scalar(attr(catalog, "synergy_cache_key"), default = "")
  source <- query_api_scalar(attr(catalog, "synergy_source"), default = "catalog")
  cache_paths <- query_synergy_cache_paths(cache_dir)

  if (!nzchar(cache_key)) {
    cache_key <- query_synergy_catalog_cache_key(cards, source = source)
  }
  precomputed_file <- query_synergy_precomputed_cache_file(cache_paths, cache_key, source = source)

  if (!isTRUE(force_refresh) &&
      identical(cache_key, query_synergy_cache_env$precomputed_key) &&
      is.list(query_synergy_cache_env$precomputed_catalog) &&
      length(query_synergy_cache_env$precomputed_catalog$profiles) == length(cards)) {
    query_synergy_emit_progress(progress_callback, 30, "Loaded precomputed catalog from memory cache")
    return(query_synergy_cache_env$precomputed_catalog)
  }

  if (!isTRUE(force_refresh) && file.exists(precomputed_file)) {
    persisted <- tryCatch(readRDS(precomputed_file), error = function(e) NULL)
    persisted_key <- query_api_scalar(persisted$cache_key, default = "")
    persisted_version <- query_api_scalar(persisted$version, default = "")
    persisted_data <- if (is.list(persisted$data)) persisted$data else NULL
    canonical_cache_migration <- FALSE
    if (identical(source, "scryfall_oracle_cards") &&
        !identical(persisted_key, cache_key) &&
        identical(persisted_version, query_synergy_precompute_version()) &&
        is.list(persisted_data) &&
        length(persisted_data$profiles) == length(cards) &&
        file.exists(cache_paths$rds_file)) {
      raw_info <- file.info(cache_paths$rds_file)
      pre_info <- file.info(precomputed_file)
      canonical_cache_migration <- isTRUE(pre_info$mtime[[1]] >= raw_info$mtime[[1]])
    }

    if (is.list(persisted) &&
        identical(persisted_version, query_synergy_precompute_version()) &&
        (identical(persisted_key, cache_key) || canonical_cache_migration)) {
      precomputed <- persisted$data
      query_synergy_cache_env$precomputed_catalog <- precomputed
      query_synergy_cache_env$precomputed_key <- cache_key
      query_synergy_cache_env$precomputed_loaded_at <- Sys.time()
      if (canonical_cache_migration) {
        invisible(tryCatch({
          saveRDS(
            list(
              version = query_synergy_precompute_version(),
              cache_key = cache_key,
              data = precomputed
            ),
            precomputed_file
          )
          TRUE
        }, error = function(e) FALSE))
      }
      query_synergy_emit_progress(progress_callback, 30, "Loaded precomputed catalog from disk cache")
      return(precomputed)
    }
  }

  precomputed <- query_synergy_build_precomputed_catalog(
    cards,
    registry = registry,
    progress_callback = progress_callback,
    progress_range = c(6, 30)
  )
  query_synergy_cache_env$precomputed_catalog <- precomputed
  query_synergy_cache_env$precomputed_key <- cache_key
  query_synergy_cache_env$precomputed_loaded_at <- Sys.time()

  invisible(tryCatch({
    saveRDS(
      list(
        version = query_synergy_precompute_version(),
        cache_key = cache_key,
        data = precomputed
      ),
      precomputed_file
    )
    TRUE
  }, error = function(e) FALSE))

  precomputed
}

query_synergy_lightweight_overlap <- function(matches, target_events, source_events) {
  matched <- unique(query_synergy_to_vector(matches))
  target_ids <- unique(query_synergy_to_vector(target_events))
  source_ids <- unique(query_synergy_to_vector(source_events))
  if (length(matched) == 0L || length(target_ids) == 0L || length(source_ids) == 0L) {
    return(0)
  }

  recall <- length(matched) / max(1, length(target_ids))
  precision <- length(matched) / max(1, length(source_ids))
  min(1, 0.7 * recall + 0.3 * precision)
}

query_synergy_score_candidate_lightweight <- function(target,
                                                      candidate,
                                                      format_name = "commander") {
  produced_to_payoff <- intersect(candidate$produced_events, target$consumed_events)
  payoff_to_produced <- intersect(candidate$consumed_events, target$produced_events)
  produced_family_overlap <- intersect(candidate$produced_families, target$consumed_families)
  consumed_family_overlap <- intersect(candidate$consumed_families, target$produced_families)
  shared_plan <- query_synergy_shared_plan_axis(target$strategy_tags, candidate$strategy_tags)
  role_match <- query_synergy_role_complementarity(target$roles, candidate$roles)
  setup_finisher <- unique(c(
    intersect(candidate$setup_events, target$finisher_events),
    intersect(target$setup_events, candidate$finisher_events)
  ))
  replacement_conflicts <- unique(c(
    intersect(candidate$replaced_events, target$consumed_events),
    intersect(target$replaced_events, candidate$consumed_events)
  ))
  prevention_conflicts <- unique(c(
    intersect(candidate$prevented_events, target$consumed_events),
    intersect(target$prevented_events, candidate$consumed_events)
  ))

  direct_score <- query_synergy_lightweight_overlap(
    produced_to_payoff,
    target$consumed_events,
    candidate$produced_events
  )
  reciprocal_score <- query_synergy_lightweight_overlap(
    payoff_to_produced,
    target$produced_events,
    candidate$consumed_events
  )
  family_bridge_score <- max(
    query_synergy_lightweight_overlap(
      produced_family_overlap,
      target$consumed_families,
      candidate$produced_families
    ),
    query_synergy_lightweight_overlap(
      consumed_family_overlap,
      target$produced_families,
      candidate$consumed_families
    )
  )
  setup_score <- min(1, length(setup_finisher) / max(1, length(unique(c(target$setup_events, target$finisher_events, candidate$setup_events, candidate$finisher_events)))))

  cadence_strength <- suppressWarnings(as.numeric(candidate$cadence$strength))
  if (!is.finite(cadence_strength) || is.na(cadence_strength)) {
    cadence_strength <- 0
  }
  cadence_score <- min(1,
    cadence_strength * (0.4 + 0.6 * max(direct_score, family_bridge_score, shared_plan$score, role_match$score)) +
      if (isTRUE(candidate$cadence$repeatable)) 0.08 else 0
  )

  color_fit <- query_synergy_color_fit(target$color_identity, candidate$color_identity)
  format_fit <- query_synergy_format_fit(target$legalities, candidate$legalities, format_name)
  tempo_fit <- query_synergy_tempo_fit(target$mana_value, candidate$mana_value)
  anti_penalty <- query_synergy_anti_penalty(target$anti_tags, candidate$anti_tags)
  replacement_penalty <- query_synergy_event_conflict_penalty(length(replacement_conflicts), step = 0.6)
  prevention_penalty <- query_synergy_event_conflict_penalty(length(prevention_conflicts), step = 0.5)

  score_norm <- 0.3 * direct_score +
    0.15 * reciprocal_score +
    0.18 * family_bridge_score +
    0.12 * shared_plan$score +
    0.12 * role_match$score +
    0.06 * setup_score +
    0.03 * color_fit +
    0.02 * format_fit +
    0.02 * tempo_fit +
    0.1 * cadence_score -
    0.12 * anti_penalty -
    0.14 * replacement_penalty -
    0.1 * prevention_penalty
  score_norm <- max(0, min(1, score_norm))

  list(
    score = as.integer(round(score_norm * 100)),
    score_norm = round(score_norm, 4),
    direct_events = produced_to_payoff,
    reciprocal_events = payoff_to_produced,
    family_bridge = unique(c(produced_family_overlap, consumed_family_overlap)),
    replacement_conflicts = replacement_conflicts,
    prevention_conflicts = prevention_conflicts
  )
}

query_synergy_humanize_id <- function(value) {
  text <- tolower(query_api_scalar(value, default = ""))
  if (!nzchar(text)) {
    return("")
  }
  gsub("\\s+", " ", trimws(gsub("_", " ", text)))
}

query_synergy_overlap_axis_score <- function(matches, target_events, source_events) {
  matched <- unique(query_synergy_to_vector(matches))
  target_ids <- unique(query_synergy_to_vector(target_events))
  source_ids <- unique(query_synergy_to_vector(source_events))
  if (length(matched) == 0L || length(target_ids) == 0L || length(source_ids) == 0L) {
    return(0)
  }

  recall <- length(matched) / length(target_ids)
  precision <- length(matched) / length(source_ids)
  min(1, 0.65 * recall + 0.35 * precision)
}

query_synergy_plan_tag_specificity_weight <- function(tag) {
  key <- query_api_scalar(tag, default = "")
  if (!nzchar(key)) {
    return(0)
  }

  broad_tags <- c(
    "draw_discard", "graveyard", "board_engine", "card_flow",
    "tokens", "spells", "combat", "life", "value_chain"
  )
  if (key %in% broad_tags) {
    return(0.35)
  }
  if (grepl("_enabler$|_payoff$|_outlet$|_producer$|_finisher$|converter|bridge|repeatable_engine|combat_engine|graveyard_finisher|graveyard_enabler|death_payoff|targeted_play", key, perl = TRUE)) {
    return(0.95)
  }
  0.6
}

query_synergy_shared_plan_axis <- function(target_tags, candidate_tags) {
  left <- unique(query_synergy_to_vector(target_tags))
  right <- unique(query_synergy_to_vector(candidate_tags))
  shared <- intersect(left, right)
  if (length(shared) == 0L) {
    return(list(score = 0, tags = character(0), weight = 0))
  }

  union_tags <- unique(c(left, right))
  shared_weight <- sum(vapply(shared, query_synergy_plan_tag_specificity_weight, numeric(1)))
  union_weight <- sum(vapply(union_tags, query_synergy_plan_tag_specificity_weight, numeric(1)))

  list(
    score = round(min(1, if (union_weight > 0) shared_weight / union_weight else 0), 4),
    tags = shared,
    weight = shared_weight
  )
}

query_synergy_role_complementarity <- function(target_roles, candidate_roles) {
  target_values <- unique(query_synergy_to_vector(target_roles))
  candidate_values <- unique(query_synergy_to_vector(candidate_roles))
  if (length(target_values) == 0L || length(candidate_values) == 0L) {
    return(list(score = 0, pairs = character(0)))
  }

  pairs <- list(
    list(candidate = "producer", target = "payoff", weight = 1.0),
    list(candidate = "engine", target = "payoff", weight = 0.95),
    list(candidate = "engine", target = "target", weight = 0.75),
    list(candidate = "setup", target = "finisher", weight = 1.0),
    list(candidate = "converter", target = "payoff", weight = 0.95),
    list(candidate = "converter", target = "finisher", weight = 0.8),
    list(candidate = "bridge", target = "payoff", weight = 0.85),
    list(candidate = "bridge", target = "finisher", weight = 0.85),
    list(candidate = "amplifier", target = "engine", weight = 0.8),
    list(candidate = "amplifier", target = "producer", weight = 0.72),
    list(candidate = "target", target = "producer", weight = 0.7),
    list(candidate = "finisher", target = "setup", weight = 0.95)
  )

  matched <- Filter(function(pair) {
    pair$candidate %in% candidate_values && pair$target %in% target_values
  }, pairs)
  if (length(matched) == 0L) {
    return(list(score = 0, pairs = character(0)))
  }

  weights <- sort(unique(vapply(matched, function(pair) pair$weight, numeric(1))), decreasing = TRUE)
  top_weights <- weights[seq_len(min(3L, length(weights)))]

  list(
    score = round(min(1, sum(top_weights) / 2.2), 4),
    pairs = unique(vapply(matched, function(pair) sprintf("%s + %s", pair$candidate, pair$target), character(1)))
  )
}

query_synergy_event_family_keys <- function(events, registry = query_synergy_event_registry_default()) {
  event_ids <- unique(query_synergy_canonicalize_events(events, registry))
  if (length(event_ids) == 0L) {
    return(character(0))
  }

  out <- character(0)
  for (event_id in event_ids) {
    lineage <- if (is.list(registry$lineage_cache) && !is.null(registry$lineage_cache[[event_id]])) {
      query_synergy_to_vector(registry$lineage_cache[[event_id]])
    } else {
      query_synergy_build_event_lineage_for_id(event_id, registry$events)
    }
    descendants <- if (is.list(registry$family_cache) && !is.null(registry$family_cache[[event_id]])) {
      query_synergy_to_vector(registry$family_cache[[event_id]])
    } else {
      query_synergy_expand_event_family(event_id, registry)
    }
    out <- c(out, lineage, descendants)
  }

  unique(out)
}

query_synergy_find_relevant_ability <- function(card,
                                                relevant_events,
                                                effect_role = "produce",
                                                registry = query_synergy_event_registry_default()) {
  if (!is.list(card) || !is.list(card$abilities)) {
    return(list(ability = NULL, matched_events = character(0)))
  }

  relevant_ids <- unique(query_synergy_canonicalize_events(relevant_events, registry))
  relevant_family <- unique(query_synergy_event_family_keys(relevant_ids, registry))
  if (length(relevant_family) == 0L) {
    relevant_family <- relevant_ids
  }

  for (ability in card$abilities) {
    if (!is.list(ability) || !is.list(ability$effects)) {
      next
    }
    matched <- character(0)
    for (effect in ability$effects) {
      if (!is.list(effect) || !identical(query_api_scalar(effect$role, default = ""), effect_role)) {
        next
      }
      event_id <- query_api_scalar(effect$event, default = "")
      parent_id <- query_api_scalar(effect$parent, default = "")
      if (event_id %in% relevant_family || parent_id %in% relevant_family) {
        matched <- c(matched, event_id)
      }
    }
    if (length(matched) > 0L) {
      return(list(ability = ability, matched_events = unique(matched)))
    }
  }

  list(ability = NULL, matched_events = character(0))
}

query_synergy_describe_engine_source <- function(card,
                                                 relevant_events = character(0),
                                                 effect_role = "produce",
                                                 registry = query_synergy_event_registry_default()) {
  if (!is.list(card)) {
    return("through a structured ability")
  }

  match <- query_synergy_find_relevant_ability(card, relevant_events, effect_role = effect_role, registry = registry)
  cadence <- if (is.list(card$cadence)) card$cadence else list()
  contexts <- query_synergy_to_vector(cadence$contexts)
  context_phrase <- ""
  if (length(contexts) > 0L) {
    mapped <- unique(vapply(contexts, function(context) {
      switch(
        query_api_scalar(context, default = ""),
        combat = "combat-linked",
        spell = "spell-linked",
        card_flow = "card-flow",
        death = "death-linked",
        etb = "ETB-linked",
        turn_cycle = "turn-cycle",
        activated = "activated",
        query_synergy_humanize_id(context)
      )
    }, character(1)))
    mapped <- mapped[nzchar(mapped)]
    if (length(mapped) > 0L) {
      context_phrase <- paste(mapped, collapse = "/")
    }
  }

  cadence_prefix <- if (isTRUE(cadence$repeatable)) {
    "repeatable "
  } else if (isTRUE(cadence$scalable)) {
    "scalable "
  } else {
    ""
  }

  engine_phrase <- if (nzchar(context_phrase)) {
    sprintf("%s%s engine", cadence_prefix, context_phrase)
  } else if (nzchar(cadence_prefix)) {
    sprintf("%sengine", cadence_prefix)
  } else {
    "structured ability"
  }

  ability <- match$ability
  if (is.list(ability) && identical(query_api_scalar(ability$source, default = ""), "mechanic_rule") && nzchar(query_api_scalar(ability$mechanic, default = ""))) {
    mechanic_name <- query_synergy_humanize_id(query_api_scalar(ability$mechanic, default = ""))
    return(sprintf("via %s on a %s", mechanic_name, engine_phrase))
  }
  if (nzchar(engine_phrase) && !identical(engine_phrase, "structured ability")) {
    article <- if (grepl("^[aeiou]", engine_phrase, perl = TRUE)) "an" else "a"
    return(sprintf("via %s %s", article, engine_phrase))
  }
  "through a structured ability"
}

query_synergy_indirect_engine_axis <- function(target,
                                               candidate,
                                               direct_event_score,
                                               role_match,
                                               shared_plan,
                                               registry = query_synergy_event_registry_default()) {
  candidate_roles <- intersect(query_synergy_to_vector(candidate$roles), c("engine", "converter", "bridge", "amplifier"))
  direct_match <- query_synergy_find_relevant_ability(candidate, target$consumed_events, effect_role = "produce", registry = registry)
  produced_family <- unique(query_synergy_event_family_keys(candidate$produced_events, registry))
  target_family <- unique(query_synergy_event_family_keys(target$consumed_events, registry))
  family_matches <- setdiff(intersect(produced_family, target_family), query_synergy_to_vector(target$consumed_events))

  if (length(candidate_roles) == 0L && length(direct_match$matched_events) == 0L && length(family_matches) == 0L && !isTRUE(candidate$cadence$repeatable)) {
    return(list(score = 0, engine_roles = character(0), matched_events = character(0), family_matches = character(0)))
  }

  cadence_factor <- suppressWarnings(as.numeric(candidate$cadence$strength))
  if (!is.finite(cadence_factor) || is.na(cadence_factor)) {
    cadence_factor <- 0
  }
  structured_factor <- if (length(direct_match$matched_events) > 0L) {
    min(1, length(direct_match$matched_events) / max(1, length(unique(target$consumed_events))))
  } else {
    0
  }
  family_factor <- if (length(target_family) > 0L) {
    min(1, length(family_matches) / length(unique(target_family)))
  } else {
    0
  }

  score <- min(1,
    0.24 * min(1, length(candidate_roles) / 3) +
      0.24 * cadence_factor +
      0.2 * structured_factor +
      0.18 * role_match$score +
      0.08 * shared_plan$score +
      0.06 * direct_event_score +
      0.08 * family_factor
  )

  list(
    score = round(score, 4),
    engine_roles = candidate_roles,
    matched_events = unique(direct_match$matched_events),
    family_matches = unique(family_matches)
  )
}

query_synergy_package_potential_axis <- function(target, candidate, role_match) {
  setup_overlap <- unique(intersect(candidate$setup_events, target$finisher_events))
  finisher_overlap <- unique(intersect(candidate$finisher_events, target$setup_events))
  bridge_inputs <- unique(query_synergy_to_vector(candidate$consumed_events))
  bridge_factor <- if (any(query_synergy_to_vector(candidate$roles) %in% c("converter", "bridge")) && length(bridge_inputs) > 0L) {
    min(1, length(bridge_inputs) / max(1, length(unique(c(candidate$consumed_events, candidate$produced_events)))))
  } else {
    0
  }
  setup_factor <- if (length(target$finisher_events) > 0L) {
    length(setup_overlap) / length(unique(target$finisher_events))
  } else {
    0
  }
  finisher_factor <- if (length(target$setup_events) > 0L) {
    length(finisher_overlap) / length(unique(target$setup_events))
  } else {
    0
  }

  list(
    score = round(min(1, 0.35 * setup_factor + 0.25 * finisher_factor + 0.25 * bridge_factor + 0.15 * role_match$score), 4),
    links = unique(c(setup_overlap, finisher_overlap, bridge_inputs))
  )
}

query_synergy_score_pair <- function(target, candidate, format_name = "commander") {
  produced_to_payoff <- intersect(candidate$produced_events, target$consumed_events)
  payoff_to_produced <- intersect(candidate$consumed_events, target$produced_events)
  shared_plan <- query_synergy_shared_plan_axis(target$strategy_tags, candidate$strategy_tags)
  replaced_target_payoffs <- intersect(candidate$replaced_events, target$consumed_events)
  prevented_target_payoffs <- intersect(candidate$prevented_events, target$consumed_events)
  replaced_candidate_payoffs <- intersect(target$replaced_events, candidate$consumed_events)
  prevented_candidate_payoffs <- intersect(target$prevented_events, candidate$consumed_events)
  replacement_conflicts <- unique(c(replaced_target_payoffs, replaced_candidate_payoffs))
  prevention_conflicts <- unique(c(prevented_target_payoffs, prevented_candidate_payoffs))
  setup_finisher <- unique(c(
    intersect(candidate$setup_events, target$finisher_events),
    intersect(target$setup_events, candidate$finisher_events)
  ))

  color_fit <- query_synergy_color_fit(target$color_identity, candidate$color_identity)
  format_fit <- query_synergy_format_fit(target$legalities, candidate$legalities, format_name)
  tempo_fit <- query_synergy_tempo_fit(target$mana_value, candidate$mana_value)

  direct_event_score <- query_synergy_overlap_axis_score(
    produced_to_payoff,
    target$consumed_events,
    candidate$produced_events
  )
  reciprocal_value_score <- query_synergy_overlap_axis_score(
    payoff_to_produced,
    target$produced_events,
    candidate$consumed_events
  )
  role_match <- query_synergy_role_complementarity(target$roles, candidate$roles)
  indirect_engine <- query_synergy_indirect_engine_axis(
    target,
    candidate,
    direct_event_score = direct_event_score,
    role_match = role_match,
    shared_plan = shared_plan
  )
  package_potential <- query_synergy_package_potential_axis(target, candidate, role_match)

  anti_penalty <- query_synergy_anti_penalty(target$anti_tags, candidate$anti_tags)
  anti_conflicts <- query_synergy_anti_conflicts(target$anti_tags, candidate$anti_tags)
  replacement_penalty <- query_synergy_event_conflict_penalty(length(replacement_conflicts), step = 0.6)
  prevention_penalty <- query_synergy_event_conflict_penalty(length(prevention_conflicts), step = 0.5)
  incoherence_penalty <- query_synergy_strategic_incoherence_penalty(
    produced_to_payoff = produced_to_payoff,
    payoff_to_produced = payoff_to_produced,
    shared_plan = shared_plan$tags,
    setup_finisher = setup_finisher
  )
  tempo_mismatch_penalty <- query_synergy_tempo_mismatch_penalty(tempo_fit, shared_plan$tags)

  anti_synergy_score <- min(1,
    0.42 * anti_penalty +
      0.28 * replacement_penalty +
      0.18 * prevention_penalty +
      0.12 * if (length(anti_conflicts$pairs) > 0L) 1 else 0
  )
  hard_event_conflict <- length(replacement_conflicts) > 0L || length(prevention_conflicts) > 0L
  anti_warning_bucket_score <- min(1,
    anti_synergy_score +
      if (length(replacement_conflicts) > 0L) 0.4 else 0 +
      if (length(prevention_conflicts) > 0L) 0.35 else 0 +
      if (length(anti_conflicts$pairs) > 0L) 0.12 else 0
  )
  shared_plan_score <- shared_plan$score
  cadence_strength <- suppressWarnings(as.numeric(candidate$cadence$strength))
  if (!is.finite(cadence_strength) || is.na(cadence_strength)) {
    cadence_strength <- 0
  }
  cadence_score <- min(1,
    cadence_strength * (0.4 + 0.6 * max(direct_event_score, indirect_engine$score, reciprocal_value_score, package_potential$score, role_match$score)) +
      if (isTRUE(candidate$cadence$repeatable)) 0.08 else 0
  )
  role_complementarity_score <- role_match$score
  package_score <- package_potential$score

  positive_score <-
    0.24 * direct_event_score +
    0.22 * indirect_engine$score +
    0.12 * reciprocal_value_score +
    0.1 * package_score +
    0.05 * shared_plan_score +
    0.14 * cadence_score +
    0.12 * role_complementarity_score +
    0.03 * color_fit +
    0.02 * format_fit +
    0.02 * tempo_fit

  score_norm <- positive_score - 0.28 * anti_synergy_score - 0.12 * incoherence_penalty - 0.08 * tempo_mismatch_penalty
  score_norm <- max(0, min(1, score_norm))
  score_value <- as.integer(round(score_norm * 100))

  axis_scores <- list(
    direct_event_score = round(direct_event_score, 4),
    indirect_engine_score = round(indirect_engine$score, 4),
    reciprocal_value_score = round(reciprocal_value_score, 4),
    package_score = round(package_score, 4),
    anti_synergy_score = round(anti_synergy_score, 4),
    shared_plan_score = round(shared_plan_score, 4),
    cadence_score = round(cadence_score, 4),
    role_complementarity_score = round(role_complementarity_score, 4)
  )

  bucket_scores <- list(
    direct_enablers = round(min(1, 0.75 * direct_event_score + 0.15 * role_complementarity_score + 0.1 * cadence_score), 4),
    indirect_engines = round(min(1, 0.55 * indirect_engine$score + 0.2 * cadence_score + 0.15 * role_complementarity_score + 0.1 * package_score), 4),
    reciprocal_value_cards = round(min(1, 0.75 * reciprocal_value_score + 0.15 * role_complementarity_score + 0.1 * shared_plan_score), 4),
    anti_synergy_warnings = round(anti_warning_bucket_score, 4)
  )

  positive_bucket_scores <- unlist(bucket_scores[c("direct_enablers", "indirect_engines", "reciprocal_value_cards")], use.names = TRUE)
  primary_bucket <- names(which.max(positive_bucket_scores))[[1]]
  if (hard_event_conflict ||
      (bucket_scores$anti_synergy_warnings >= max(positive_bucket_scores) && bucket_scores$anti_synergy_warnings >= 0.35) ||
      (bucket_scores$anti_synergy_warnings >= 0.45 && score_norm <= 0.45)) {
    primary_bucket <- "anti_synergy_warnings"
  }

  reasons <- character(0)
  if (direct_event_score > 0) {
    reasons <- c(reasons, sprintf(
      "Produces %s %s",
      paste(produced_to_payoff, collapse = ", "),
      query_synergy_describe_engine_source(candidate, produced_to_payoff)
    ))
  }
  if (indirect_engine$score >= 0.18) {
    reasons <- c(reasons, if (isTRUE(candidate$cadence$repeatable)) {
      sprintf("Acts as an engine rather than a direct payoff, with %s cadence", query_synergy_humanize_id(candidate$cadence$class))
    } else {
      "Acts as an engine rather than a direct payoff"
    })
  }
  if (reciprocal_value_score > 0) {
    reasons <- c(reasons, sprintf(
      "Rewards %s produced by %s",
      paste(payoff_to_produced, collapse = ", "),
      target$name
    ))
  }
  if (shared_plan_score > 0) {
    reasons <- c(reasons, sprintf("Shared strategic structure: %s", paste(shared_plan$tags, collapse = ", ")))
  }
  if (package_score > 0.15) {
    reasons <- c(reasons, sprintf("Supports package assembly through %s", paste(package_potential$links, collapse = ", ")))
  }
  if (cadence_score > 0.2) {
    reasons <- c(reasons, sprintf("Scores highly because of %s cadence and strategic fit", query_synergy_humanize_id(candidate$cadence$class)))
  }
  if (role_complementarity_score > 0.2 && length(role_match$pairs) > 0L) {
    reasons <- c(reasons, sprintf("Complements the seed as %s", paste(role_match$pairs, collapse = "; ")))
  }
  if (length(replacement_conflicts) > 0L) {
    reasons <- c(reasons, sprintf(
      "Conflicts because it replaces %s the seed wants",
      paste(replacement_conflicts, collapse = ", ")
    ))
  }
  if (length(prevention_conflicts) > 0L) {
    reasons <- c(reasons, sprintf(
      "Conflicts because it prevents %s the seed wants",
      paste(prevention_conflicts, collapse = ", ")
    ))
  }
  if (length(anti_conflicts$reasons) > 0L) {
    reasons <- c(reasons, anti_conflicts$reasons)
  } else if (anti_synergy_score > 0.2) {
    reasons <- c(reasons, "Anti-synergy detected (conflicting hand or graveyard plan)")
  }
  if (incoherence_penalty > 0) {
    reasons <- c(reasons, "Strategic incoherence: no strong event bridge or shared plan")
  }
  if (tempo_mismatch_penalty > 0) {
    reasons <- c(reasons, "Tempo mismatch: mana values diverge with low strategic overlap")
  }
  if (length(reasons) == 0L) {
    reasons <- c(reasons, "Weak mechanical overlap")
  }

  classes <- character(0)
  if (direct_event_score > 0.1) {
    classes <- c(classes, "enabler_payoff")
  }
  if (reciprocal_value_score > 0.1) {
    classes <- c(classes, "payoff_enabler")
  }
  if (indirect_engine$score > 0.16) {
    classes <- c(classes, "indirect_engine")
  }
  if (package_score > 0.12) {
    classes <- c(classes, "package_candidate")
  }
  if (shared_plan_score > 0.08) {
    classes <- c(classes, "shared_plan")
  }
  if (cadence_score > 0.18) {
    classes <- c(classes, "repeatable_cadence")
  }
  if (role_complementarity_score > 0.18) {
    classes <- c(classes, "role_complementary")
  }
  if (anti_synergy_score > 0.2 || hard_event_conflict) {
    classes <- c(classes, "anti_synergy")
  }
  if (length(anti_conflicts$pairs) > 0L) {
    classes <- c(classes, "plan_conflict")
  }
  if (length(replacement_conflicts) > 0L || length(prevention_conflicts) > 0L) {
    classes <- c(classes, "event_conflict")
  }
  if (incoherence_penalty > 0) {
    classes <- c(classes, "strategic_incoherence")
  }
  if (tempo_mismatch_penalty > 0) {
    classes <- c(classes, "tempo_mismatch")
  }

  directional <- list(
    candidate_to_target = list(
      producer = candidate$name,
      payoff = target$name,
      matched_events = produced_to_payoff,
      reason = if (direct_event_score > 0) {
        sprintf("%s enables %s via %s", candidate$name, target$name, paste(produced_to_payoff, collapse = ", "))
      } else if (indirect_engine$score > 0) {
        sprintf("%s supports %s as an indirect %s", candidate$name, target$name, paste(intersect(candidate$roles, c("engine", "converter", "bridge", "amplifier")), collapse = "/"))
      } else {
        sprintf("%s does not strongly enable %s", candidate$name, target$name)
      }
    ),
    target_to_candidate = list(
      producer = target$name,
      payoff = candidate$name,
      matched_events = payoff_to_produced,
      reason = if (reciprocal_value_score > 0) {
        sprintf("%s enables %s via %s", target$name, candidate$name, paste(payoff_to_produced, collapse = ", "))
      } else {
        sprintf("%s does not strongly enable %s", target$name, candidate$name)
      }
    )
  )

  list(
    score = score_value,
    score_norm = score_norm,
    breakdown = list(
      direct_event_score = axis_scores$direct_event_score,
      indirect_engine_score = axis_scores$indirect_engine_score,
      reciprocal_value_score = axis_scores$reciprocal_value_score,
      package_score = axis_scores$package_score,
      anti_synergy_score = axis_scores$anti_synergy_score,
      shared_plan_score = axis_scores$shared_plan_score,
      cadence_score = axis_scores$cadence_score,
      role_complementarity_score = axis_scores$role_complementarity_score,
      event_production_match = axis_scores$direct_event_score,
      event_payoff_match = axis_scores$reciprocal_value_score,
      shared_plan = axis_scores$shared_plan_score,
      setup_finisher = axis_scores$package_score,
      color_fit = round(color_fit, 4),
      format_fit = round(format_fit, 4),
      tempo_fit = round(tempo_fit, 4),
      direct_bridge_bonus = round(min(1, direct_event_score * 0.35 + cadence_score * 0.1), 4),
      anti_penalty = round(anti_penalty, 4),
      replacement_penalty = round(replacement_penalty, 4),
      prevention_penalty = round(prevention_penalty, 4),
      incoherence_penalty = round(incoherence_penalty, 4),
      tempo_mismatch_penalty = round(tempo_mismatch_penalty, 4)
    ),
    axis_scores = axis_scores,
    bucket_scores = bucket_scores,
    primary_bucket = primary_bucket,
    reasons = unique(reasons),
    explanation_text = paste(utils::head(unique(reasons), 3L), collapse = " "),
    relation_classes = unique(classes),
    directional = directional,
    matched_events = list(
      enabler_to_payoff = produced_to_payoff,
      payoff_to_enabler = payoff_to_produced,
      indirect_engine = indirect_engine$matched_events,
      indirect_families = indirect_engine$family_matches,
      shared_plan = shared_plan$tags,
      setup_finisher = setup_finisher,
      package_links = package_potential$links,
      role_pairs = role_match$pairs,
      replaces_payoff = replacement_conflicts,
      prevents_payoff = prevention_conflicts,
      anti_conflicts = anti_conflicts$pairs
    )
  )
}

query_synergy_bucket_labels <- function() {
  list(
    direct_enablers = "Top direct enablers",
    indirect_engines = "Top indirect engines",
    reciprocal_value_cards = "Top reciprocal value cards",
    synergy_groups = "Top synergy groups",
    package_lines = "Top package lines",
    packages = "Top packages / groups",
    anti_synergy_warnings = "Top anti-synergy warnings"
  )
}

query_synergy_build_card_result_entry <- function(candidate, score, bucket_key = "") {
  labels <- query_synergy_bucket_labels()
  key <- query_api_scalar(bucket_key, default = query_api_scalar(score$primary_bucket, default = "direct_enablers"))
  bucket_score <- suppressWarnings(as.numeric(score$bucket_scores[[key]]))
  if (!is.finite(bucket_score) || is.na(bucket_score)) {
    bucket_score <- suppressWarnings(as.numeric(score$score_norm))
  }

  list(
    id = candidate$id,
    name = candidate$name,
    score = score$score,
    total_score = score$score,
    score_norm = score$score_norm,
    score_breakdown = score$breakdown,
    axis_scores = score$axis_scores,
    bucket_scores = score$bucket_scores,
    bucket = key,
    bucket_label = query_api_scalar(labels[[key]], default = key),
    bucket_score = round(bucket_score, 4),
    roles = query_synergy_to_vector(candidate$roles),
    cadence = candidate$cadence,
    target_roles = query_synergy_to_vector(candidate$target_roles),
    matched_events = score$matched_events,
    reasons = score$reasons,
    explanation_text = query_api_scalar(score$explanation_text, default = paste(utils::head(score$reasons, 3L), collapse = " ")),
    relation_classes = score$relation_classes,
    strategy_tags = query_synergy_to_vector(candidate$strategy_tags)
  )
}

query_synergy_result_profile_fingerprint <- function(entry) {
  role_sig <- paste(sort(intersect(query_synergy_to_vector(entry$roles), c("producer", "payoff", "engine", "setup", "converter", "amplifier", "target", "bridge", "finisher"))), collapse = "+")
  event_sig <- paste(sort(unique(c(
    query_synergy_to_vector(entry$matched_events$enabler_to_payoff),
    query_synergy_to_vector(entry$matched_events$indirect_engine),
    query_synergy_to_vector(entry$matched_events$role_pairs)
  ))), collapse = "+")
  cadence_sig <- query_api_scalar(entry$cadence$class, default = "one_shot")
  paste(query_api_scalar(entry$bucket, default = ""), role_sig, event_sig, cadence_sig, sep = "|")
}

query_synergy_diversify_entries <- function(entries, limit = 10L) {
  pool <- query_synergy_to_list(entries)
  if (length(pool) == 0L) {
    return(list())
  }

  get_profile_count <- function(fingerprint) {
    value <- profile_counts[[fingerprint]]
    if (is.null(value) || length(value) == 0L) {
      return(0L)
    }
    count <- suppressWarnings(as.integer(value))
    if (length(count) == 0L || !is.finite(count[[1]]) || is.na(count[[1]])) {
      return(0L)
    }
    count[[1]]
  }

  selected <- list()
  profile_counts <- list()
  cap <- query_synergy_as_int(limit, default = 10L, min_value = 1L, max_value = 100L)

  while (length(pool) > 0L && length(selected) < cap) {
    adjusted_scores <- vapply(pool, function(entry) {
      fingerprint <- query_synergy_result_profile_fingerprint(entry)
      seen_count <- get_profile_count(fingerprint)
      base <- suppressWarnings(as.numeric(entry$bucket_score))
      if (!is.finite(base) || is.na(base)) {
        base <- suppressWarnings(as.numeric(entry$total_score)) / 100
      }
      base - (seen_count * 0.08)
    }, numeric(1))

    ord <- order(adjusted_scores, decreasing = TRUE)
    chosen_index <- ord[[1]]
    chosen <- pool[[chosen_index]]
    selected[[length(selected) + 1L]] <- chosen

    fingerprint <- query_synergy_result_profile_fingerprint(chosen)
    current <- get_profile_count(fingerprint)
    profile_counts[[fingerprint]] <- current + 1L
    pool[[chosen_index]] <- NULL
  }

  selected
}

query_synergy_build_bucket <- function(entries, bucket_key, limit = 10L) {
  labels <- query_synergy_bucket_labels()
  pool <- query_synergy_to_list(entries)
  if (length(pool) == 0L) {
    return(list(
      key = bucket_key,
      label = query_api_scalar(labels[[bucket_key]], default = bucket_key),
      count = 0L,
      results = list()
    ))
  }

  ord <- order(
    vapply(pool, function(entry) suppressWarnings(as.numeric(entry$bucket_score)), numeric(1)),
    vapply(pool, function(entry) suppressWarnings(as.numeric(entry$total_score)), numeric(1)),
    decreasing = TRUE
  )
  pool <- pool[ord]
  selected <- query_synergy_diversify_entries(pool, limit = limit)

  list(
    key = bucket_key,
    label = query_api_scalar(labels[[bucket_key]], default = bucket_key),
    count = length(selected),
    results = selected
  )
}

query_synergy_build_result_buckets <- function(target, scored_entries, max_results = 50L) {
  entries <- query_synergy_to_list(scored_entries)
  direct_pool <- list()
  indirect_pool <- list()
  reciprocal_pool <- list()
  anti_pool <- list()
  flat_pool <- list()

  for (entry in entries) {
    if (!is.list(entry$card) || !is.list(entry$score)) {
      next
    }

    candidate <- entry$card
    score <- entry$score
    primary_entry <- query_synergy_build_card_result_entry(candidate, score, score$primary_bucket)
    if (primary_entry$bucket != "anti_synergy_warnings" && suppressWarnings(as.numeric(primary_entry$total_score)) > 0) {
      flat_pool[[length(flat_pool) + 1L]] <- primary_entry
    }

    if (suppressWarnings(as.numeric(score$bucket_scores$direct_enablers)) >= 0.16 && suppressWarnings(as.numeric(score$axis_scores$direct_event_score)) > 0.08) {
      direct_pool[[length(direct_pool) + 1L]] <- query_synergy_build_card_result_entry(candidate, score, "direct_enablers")
    }
    if (suppressWarnings(as.numeric(score$bucket_scores$indirect_engines)) >= 0.18 && suppressWarnings(as.numeric(score$axis_scores$indirect_engine_score)) > 0.12) {
      indirect_pool[[length(indirect_pool) + 1L]] <- query_synergy_build_card_result_entry(candidate, score, "indirect_engines")
    }
    if (suppressWarnings(as.numeric(score$bucket_scores$reciprocal_value_cards)) >= 0.16 && suppressWarnings(as.numeric(score$axis_scores$reciprocal_value_score)) > 0.08) {
      reciprocal_pool[[length(reciprocal_pool) + 1L]] <- query_synergy_build_card_result_entry(candidate, score, "reciprocal_value_cards")
    }
    if (score$primary_bucket == "anti_synergy_warnings" ||
        length(query_synergy_to_vector(score$matched_events$replaces_payoff)) > 0L ||
        length(query_synergy_to_vector(score$matched_events$prevents_payoff)) > 0L ||
        suppressWarnings(as.numeric(score$bucket_scores$anti_synergy_warnings)) >= 0.25) {
      anti_pool[[length(anti_pool) + 1L]] <- query_synergy_build_card_result_entry(candidate, score, "anti_synergy_warnings")
    }
  }

  flat_selected <- query_synergy_diversify_entries(flat_pool, limit = max_results)
  dedup_flat <- list()
  seen <- new.env(parent = emptyenv(), hash = TRUE)
  for (entry in flat_selected) {
    key <- query_api_scalar(entry$id, default = "")
    if (!nzchar(key) || exists(key, envir = seen, inherits = FALSE)) {
      next
    }
    assign(key, TRUE, envir = seen)
    dedup_flat[[length(dedup_flat) + 1L]] <- entry
  }

  list(
    buckets = list(
      direct_enablers = query_synergy_build_bucket(direct_pool, "direct_enablers", limit = min(10L, max_results)),
      indirect_engines = query_synergy_build_bucket(indirect_pool, "indirect_engines", limit = min(10L, max_results)),
      reciprocal_value_cards = query_synergy_build_bucket(reciprocal_pool, "reciprocal_value_cards", limit = min(10L, max_results)),
      anti_synergy_warnings = query_synergy_build_bucket(anti_pool, "anti_synergy_warnings", limit = min(10L, max_results))
    ),
    flat = dedup_flat
  )
}

query_synergy_indirect_resource_bridges <- function(setup, converter) {
  bridges <- character(0)
  setup_events <- query_synergy_to_vector(setup$produced_events)
  setup_tags <- query_synergy_to_vector(setup$strategy_tags)
  converter_tags <- query_synergy_to_vector(converter$strategy_tags)
  converter_roles <- query_synergy_to_vector(converter$roles)
  converter_events <- query_synergy_to_vector(converter$produced_events)
  converter_inputs <- query_synergy_to_vector(converter$consumed_events)

  if ((length(intersect(setup_events, c("CREATE_TOKEN", "ETB", "REANIMATE"))) > 0L || "token_producer" %in% setup_tags) &&
      (length(intersect(converter_tags, c("sacrifice_outlet", "combat_engine", "targeted_play"))) > 0L ||
       length(intersect(converter_events, c("SACRIFICE_PERMANENT", "ATTACKS", "TARGETS_CREATURE"))) > 0L ||
       "bridge" %in% converter_roles)) {
    bridges <- c(bridges, "BATTLEFIELD_RESOURCE")
  }

  if ((length(intersect(setup_events, c("MILL_CARD", "DISCARD_CARD", "GRAVEYARD_TO_HAND"))) > 0L || "graveyard_enabler" %in% setup_tags) &&
      (length(intersect(converter_tags, c("graveyard", "graveyard_finisher", "bridge_engine", "converter"))) > 0L ||
       length(intersect(converter_inputs, c("MILL_CARD", "DISCARD_CARD"))) > 0L ||
       length(intersect(converter_events, c("CAST_SPELL", "REANIMATE", "GRAVEYARD_TO_HAND"))) > 0L)) {
    bridges <- c(bridges, "GRAVEYARD_FUEL")
  }

  if ((length(intersect(setup_events, c("DRAW_CARD", "DISCARD_CARD"))) > 0L || any(c("draw_enabler", "discard_enabler") %in% setup_tags)) &&
      (length(intersect(converter_inputs, c("DRAW_CARD", "DISCARD_CARD"))) > 0L ||
       any(c("draw_payoff", "discard_payoff", "converter") %in% converter_tags))) {
    bridges <- c(bridges, "CARD_FLOW_RESOURCE")
  }

  if ((length(intersect(setup_events, c("CAST_SPELL", "NONCREATURE_SPELL_CAST"))) > 0L || "spell_enabler" %in% setup_tags) &&
      (length(intersect(converter_inputs, c("CAST_SPELL", "NONCREATURE_SPELL_CAST"))) > 0L ||
       any(c("spell_payoff", "bridge_engine", "converter") %in% converter_tags))) {
    bridges <- c(bridges, "SPELL_CHAIN_RESOURCE")
  }

  unique(bridges)
}

query_synergy_match_indirect_chain <- function(setup,
                                               converter,
                                               payoff,
                                               registry = query_synergy_event_registry_default()) {
  step1_exact <- intersect(setup$produced_events, converter$consumed_events)
  step2_exact <- intersect(converter$produced_events, payoff$consumed_events)
  step2_family <- intersect(
    query_synergy_event_family_keys(converter$produced_events, registry),
    query_synergy_event_family_keys(payoff$consumed_events, registry)
  )
  step1_bridges <- query_synergy_indirect_resource_bridges(setup, converter)
  step1_roles <- query_synergy_role_complementarity(converter$roles, setup$roles)
  step2_roles <- query_synergy_role_complementarity(payoff$roles, converter$roles)

  step1_strength <- max(
    query_synergy_overlap_axis_score(step1_exact, converter$consumed_events, setup$produced_events),
    if (length(step1_bridges) > 0L) 0.5 else 0
  )
  step2_strength <- max(
    query_synergy_overlap_axis_score(step2_exact, payoff$consumed_events, converter$produced_events),
    if (length(step2_family) > 0L) min(0.5, length(step2_family) / max(1, length(query_synergy_to_vector(payoff$consumed_events)))) else 0
  )

  cadence_factor <- suppressWarnings(as.numeric(converter$cadence$strength))
  if (!is.finite(cadence_factor) || is.na(cadence_factor)) {
    cadence_factor <- 0
  }

  is_valid <- (step1_strength > 0.18 || length(step1_bridges) > 0L) &&
    step2_strength > 0.12 &&
    (step1_roles$score > 0.15 || step2_roles$score > 0.15 || any(query_synergy_to_vector(converter$roles) %in% c("converter", "bridge", "engine")))

  chain_score <- min(1,
    0.35 * step1_strength +
      0.4 * step2_strength +
      0.1 * step1_roles$score +
      0.15 * max(step2_roles$score, cadence_factor)
  )

  list(
    valid = is_valid,
    score = round(chain_score, 4),
    step1_events = step1_exact,
    step1_bridges = step1_bridges,
    step2_events = step2_exact,
    step2_family = step2_family,
    setup_converter_roles = step1_roles$pairs,
    converter_payoff_roles = step2_roles$pairs
  )
}
query_synergy_normalize_card <- function(card,
                                         registry = query_synergy_event_registry_default(),
                                         mechanic_rules = query_synergy_mechanic_rules_default(),
                                         ability_parse_rules = query_synergy_ability_parse_rules_default(registry = registry)) {
  if (!is.list(card) || length(card) == 0L) {
    return(query_synergy_empty_normalized_card())
  }

  card_id <- query_synergy_card_id(card)
  card_name <- query_api_scalar(card$name, default = card_id)
  oracle_text <- query_api_scalar(card$oracle_text, default = query_api_scalar(card$text, default = ""))
  type_line <- query_api_scalar(card$type_line, default = query_api_scalar(card$type, default = ""))
  mana_value <- suppressWarnings(as.numeric(if (!is.null(card$cmc)) card$cmc else card$mana_value))
  if (!is.finite(mana_value) || is.na(mana_value)) {
    mana_value <- 0
  }

  keywords <- query_synergy_to_vector(card$keywords)
  mechanics_from_text <- query_synergy_detect_mechanics_from_text(oracle_text)
  mechanics <- unique(c(tolower(keywords), mechanics_from_text))

  expanded <- query_synergy_expand_mechanics(mechanics, registry = registry, rules = mechanic_rules)
  extracted <- query_synergy_extract_events_from_text(
    oracle_text,
    registry = registry,
    parse_rules = ability_parse_rules
  )

  produced <- unique(c(expanded$produced, extracted$produced))
  consumed <- unique(c(expanded$consumed, extracted$consumed))
  replaced <- unique(c(expanded$replaced, extracted$replaced))
  prevented <- unique(c(expanded$prevented, extracted$prevented))
  setup_events <- unique(c(expanded$setup, extracted$setup))
  finisher_events <- unique(c(expanded$finisher, extracted$finisher))
  reward_events <- unique(extracted$consumed)
  required_events <- unique(expanded$consumed)

  anti_tags <- unique(c(expanded$anti_tags, extracted$anti_tags))
  abilities <- query_synergy_build_ability_records(
    keywords = keywords,
    mechanics = mechanics,
    expanded_abilities = expanded$abilities,
    parsed_abilities = extracted$abilities
  )
  produces <- query_synergy_build_event_role_records(produced, "produce", registry)
  rewards <- query_synergy_build_event_role_records(reward_events, "reward", registry)
  requires <- query_synergy_build_event_role_records(required_events, "require", registry)
  replaces <- query_synergy_build_event_role_records(replaced, "replace", registry)
  prevents <- query_synergy_build_event_role_records(prevented, "prevent", registry)
  amplifies <- query_synergy_build_event_role_records(character(0), "amplify", registry)
  moves <- query_synergy_build_move_records(unique(c(produced, replaced)), registry)
  target_roles <- query_synergy_infer_target_roles(type_line, produced, consumed, replaced, prevented)
  cadence <- query_synergy_infer_card_cadence(
    abilities = abilities,
    type_line = type_line,
    oracle_text = oracle_text,
    mechanics = mechanics,
    produced = produced,
    consumed = consumed
  )
  plans <- list(
    tags = character(0),
    setup = setup_events,
    finisher = finisher_events,
    anti = anti_tags
  )
  roles <- query_synergy_infer_card_roles(
    produces = produces,
    rewards = rewards,
    requires = requires,
    replaces = replaces,
    prevents = prevents,
    moves = moves,
    setup_events = setup_events,
    finisher_events = finisher_events,
    target_roles = target_roles,
    cadence = cadence,
    produced_events = produced,
    consumed_events = consumed,
    abilities = abilities
  )
  strategy_tags <- unique(c(
    expanded$strategy_tags,
    query_synergy_strategy_tags_from_events(
      produced,
      consumed,
      setup_events,
      finisher_events,
      roles = roles,
      cadence = cadence,
      target_roles = target_roles
    )
  ))
  plans$tags <- strategy_tags

  list(
    id = card_id,
    name = card_name,
    model_version = "normalized_card_v2",
    colors = query_synergy_card_colors(card),
    color_identity = query_synergy_card_color_identity(card),
    mana_value = as.numeric(mana_value),
    type_line = type_line,
    oracle_text = oracle_text,
    abilities = abilities,
    produces = produces,
    rewards = rewards,
    requires = requires,
    replaces = replaces,
    prevents = prevents,
    amplifies = amplifies,
    moves = moves,
    target_roles = target_roles,
    plans = plans,
    roles = roles,
    cadence = cadence,
    mechanics = mechanics,
    keywords = keywords,
    produced_events = produced,
    consumed_events = consumed,
    replaced_events = replaced,
    prevented_events = prevented,
    setup_events = setup_events,
    finisher_events = finisher_events,
    strategy_tags = strategy_tags,
    anti_tags = anti_tags,
    legalities = query_synergy_card_legalities(card)
  )
}

query_synergy_empty_normalized_card <- function() {
  list(
    id = "",
    name = "",
    model_version = "normalized_card_v2",
    colors = character(0),
    color_identity = character(0),
    mana_value = 0,
    type_line = "",
    oracle_text = "",
    abilities = list(),
    produces = list(),
    rewards = list(),
    requires = list(),
    replaces = list(),
    prevents = list(),
    amplifies = list(),
    moves = list(),
    target_roles = character(0),
    plans = list(
      tags = character(0),
      setup = character(0),
      finisher = character(0),
      anti = character(0)
    ),
    roles = character(0),
    cadence = list(
      class = "one_shot",
      repeatable = FALSE,
      scalable = FALSE,
      strength = 0,
      contexts = character(0),
      sources = character(0)
    ),
    mechanics = character(0),
    keywords = character(0),
    produced_events = character(0),
    consumed_events = character(0),
    replaced_events = character(0),
    prevented_events = character(0),
    setup_events = character(0),
    finisher_events = character(0),
    strategy_tags = character(0),
    anti_tags = character(0),
    legalities = list()
  )
}

query_synergy_build_ability_records <- function(keywords,
                                                mechanics,
                                                expanded_abilities = list(),
                                                parsed_abilities = list()) {
  keyword_values <- query_synergy_to_vector(keywords)
  mechanic_values <- query_synergy_to_vector(mechanics)

  out <- list()
  if (length(keyword_values) > 0L) {
    for (value in keyword_values) {
      out[[length(out) + 1L]] <- list(
        kind = "keyword",
        id = tolower(value),
        label = value,
        source = "keyword",
        text = value,
        trigger = list(),
        effects = list(),
        references = list()
      )
    }
  }
  if (length(mechanic_values) > 0L) {
    for (value in mechanic_values) {
      out[[length(out) + 1L]] <- list(
        kind = "mechanic",
        id = tolower(value),
        label = value,
        source = "mechanic",
        text = value,
        trigger = list(),
        effects = list(),
        references = list()
      )
    }
  }

  out <- c(
    out,
    query_synergy_to_list(expanded_abilities),
    query_synergy_to_list(parsed_abilities)
  )
  query_synergy_unique_abilities(out)
}

query_synergy_unique_abilities <- function(abilities) {
  values <- query_synergy_to_list(abilities)
  if (length(values) == 0L) {
    return(list())
  }

  out <- list()
  seen <- new.env(parent = emptyenv(), hash = TRUE)
  for (ability in values) {
    if (!is.list(ability)) {
      next
    }

    ability_id <- query_api_scalar(ability$id, default = "")
    if (!nzchar(ability_id)) {
      ability_id <- sprintf("ability_%s", length(out) + 1L)
      ability$id <- ability_id
    }
    if (exists(ability_id, envir = seen, inherits = FALSE)) {
      next
    }
    assign(ability_id, TRUE, envir = seen)
    out[[length(out) + 1L]] <- ability
  }

  out
}

query_synergy_to_list <- function(value) {
  if (is.null(value)) {
    return(list())
  }
  if (is.list(value) && length(value) > 0L) {
    return(unname(value))
  }
  list()
}

query_synergy_build_event_role_records <- function(events, role, registry = query_synergy_event_registry_default()) {
  event_ids <- unique(query_synergy_canonicalize_events(events, registry))
  if (length(event_ids) == 0L) {
    return(list())
  }

  out <- vector("list", length(event_ids))
  for (i in seq_along(event_ids)) {
    event_id <- event_ids[[i]]
    event_def <- registry$events[[event_id]]
    out[[i]] <- list(
      event = event_id,
      role = query_api_scalar(role, default = ""),
      parent = query_api_scalar(event_def$parent, default = ""),
      kind = query_api_scalar(event_def$kind, default = "event"),
      scope = query_api_scalar(event_def$scope, default = "generic"),
      resource = query_api_scalar(event_def$resource, default = ""),
      tags = query_synergy_to_vector(event_def$tags)
    )
  }

  out
}

query_synergy_build_move_records <- function(events, registry = query_synergy_event_registry_default()) {
  event_ids <- unique(query_synergy_canonicalize_events(events, registry))
  if (length(event_ids) == 0L) {
    return(list())
  }

  out <- list()
  for (event_id in event_ids) {
    event_def <- registry$events[[event_id]]
    zones <- event_def$zones
    if (!is.list(zones) || length(zones) == 0L) {
      next
    }

    zone_from <- query_api_scalar(zones$from, default = "")
    zone_to <- query_api_scalar(zones$to, default = "")
    if (!nzchar(zone_from) || !nzchar(zone_to) || identical(zone_from, zone_to)) {
      next
    }

    out[[length(out) + 1L]] <- list(
      event = event_id,
      from = zone_from,
      to = zone_to,
      resource = query_api_scalar(event_def$resource, default = ""),
      kind = query_api_scalar(event_def$kind, default = "event")
    )
  }

  out
}

query_synergy_infer_target_roles <- function(type_line, produced, consumed, replaced, prevented) {
  out <- character(0)
  all_events <- unique(c(
    query_synergy_to_vector(produced),
    query_synergy_to_vector(consumed),
    query_synergy_to_vector(replaced),
    query_synergy_to_vector(prevented)
  ))

  if ("TARGETS_CREATURE" %in% all_events) {
    out <- c(out, "creature")
  }

  type_text <- tolower(query_api_scalar(type_line, default = ""))
  if (grepl("\\bartifact\\b", type_text, perl = TRUE)) {
    out <- c(out, "artifact_card")
  }
  if (grepl("\\benchantment\\b", type_text, perl = TRUE)) {
    out <- c(out, "enchantment_card")
  }
  if (grepl("\\bcreature\\b", type_text, perl = TRUE)) {
    out <- c(out, "creature_card")
  }

  unique(out)
}

query_synergy_infer_card_roles <- function(produces,
                                           rewards,
                                           requires,
                                           replaces,
                                           prevents,
                                           moves,
                                           setup_events,
                                           finisher_events,
                                           target_roles = character(0),
                                           cadence = list(),
                                           produced_events = character(0),
                                           consumed_events = character(0),
                                           abilities = list()) {
  roles <- character(0)
  cadence_repeatable <- isTRUE(cadence$repeatable)
  cadence_scalable <- isTRUE(cadence$scalable)

  role_keys <- function(records) {
    values <- query_synergy_to_list(records)
    if (length(values) == 0L) {
      return(character(0))
    }

    unique(unlist(lapply(values, function(entry) {
      if (!is.list(entry)) {
        return(character(0))
      }
      c(
        query_api_scalar(entry$event, default = ""),
        query_api_scalar(entry$parent, default = "")
      )
    }), use.names = FALSE))
  }

  produced_keys <- role_keys(produces)
  input_keys <- unique(c(role_keys(rewards), role_keys(requires)))
  amplifier_signals <- query_synergy_detect_amplifier_signals(
    abilities = abilities,
    produced_events = produced_events,
    consumed_events = consumed_events,
    cadence = cadence
  )

  if (length(produces) > 0L) {
    roles <- c(roles, "producer")
  }
  if (length(rewards) > 0L) {
    roles <- c(roles, "payoff")
  }
  if (length(requires) > 0L) {
    roles <- c(roles, "dependent")
  }
  if (length(replaces) > 0L) {
    roles <- c(roles, "replacer")
  }
  if (length(prevents) > 0L) {
    roles <- c(roles, "preventer")
  }
  if (length(moves) > 0L) {
    roles <- c(roles, "mover")
  }
  if (length(query_synergy_to_vector(setup_events)) > 0L) {
    roles <- c(roles, "setup")
  }
  if (length(query_synergy_to_vector(finisher_events)) > 0L) {
    roles <- c(roles, "finisher")
  }
  if (length(query_synergy_to_vector(target_roles)) > 0L) {
    roles <- c(roles, "target")
  }

  if (length(produced_keys) > 0L && length(input_keys) > 0L && length(setdiff(produced_keys, input_keys)) > 0L) {
    roles <- c(roles, "converter")
  }

  if (length(produces) > 0L && (length(rewards) > 0L || length(requires) > 0L || cadence_repeatable || length(query_synergy_to_vector(setup_events)) > 0L)) {
    roles <- c(roles, "engine")
  }
  if (("converter" %in% roles || "engine" %in% roles) && (length(input_keys) > 0L || cadence_repeatable)) {
    roles <- c(roles, "bridge")
  }
  if (amplifier_signals$detected || cadence_scalable) {
    roles <- c(roles, "amplifier")
  }

  unique(roles)
}

query_synergy_detect_amplifier_signals <- function(abilities = list(),
                                                   produced_events = character(0),
                                                   consumed_events = character(0),
                                                   cadence = list()) {
  texts <- unlist(lapply(query_synergy_to_list(abilities), function(ability) {
    if (!is.list(ability)) {
      return(character(0))
    }
    query_api_scalar(ability$text, default = "")
  }), use.names = FALSE)
  source <- tolower(paste(c(texts, query_synergy_to_vector(produced_events), query_synergy_to_vector(consumed_events)), collapse = " "))
  patterns <- c(
    "\\badditional\\b",
    "\\bdouble\\b",
    "\\btwice\\b",
    "\\bcopy\\b",
    "\\bproliferate\\b",
    "\\bpopulate\\b",
    "for each",
    "one or more"
  )
  detected <- any(vapply(patterns, function(pattern) grepl(pattern, source, perl = TRUE), logical(1))) || isTRUE(cadence$scalable)
  list(
    detected = detected,
    source = source
  )
}

query_synergy_card_is_permanent <- function(type_line) {
  text <- tolower(query_api_scalar(type_line, default = ""))
  grepl("\\bartifact\\b|\\bcreature\\b|\\benchantment\\b|\\bland\\b|\\bplaneswalker\\b", text, perl = TRUE)
}

query_synergy_infer_card_cadence <- function(abilities = list(),
                                             type_line = "",
                                             oracle_text = "",
                                             mechanics = character(0),
                                             produced = character(0),
                                             consumed = character(0)) {
  ability_values <- query_synergy_to_list(abilities)
  permanent <- query_synergy_card_is_permanent(type_line)
  lower_text <- tolower(query_api_scalar(oracle_text, default = ""))

  repeatable_signals <- 0
  scalable_signals <- 0
  contexts <- character(0)
  sources <- character(0)

  for (ability in ability_values) {
    if (!is.list(ability)) {
      next
    }

    kind <- query_api_scalar(ability$kind, default = "")
    sources <- c(sources, query_api_scalar(ability$source, default = ""))
    if (kind %in% c("triggered", "activated", "replacement", "static", "mechanic", "keyword_action")) {
      repeatable_signals <- repeatable_signals + 1L
    }

    ability_text <- tolower(query_api_scalar(ability$text, default = ""))
    if (grepl("\\bx\\b|for each|one or more|additional|double|twice", ability_text, perl = TRUE)) {
      scalable_signals <- scalable_signals + 1L
    }

    trigger_events <- unique(c(
      query_synergy_to_vector(ability$trigger$event),
      query_synergy_to_vector(ability$trigger$events)
    ))
    if (length(trigger_events) > 0L) {
      if (length(intersect(trigger_events, c("ATTACKS", "COMBAT_DAMAGE_TO_PLAYER"))) > 0L) {
        contexts <- c(contexts, "combat")
      }
      if (length(intersect(trigger_events, c("CAST_SPELL", "NONCREATURE_SPELL_CAST"))) > 0L) {
        contexts <- c(contexts, "spell")
      }
      if (length(intersect(trigger_events, c("DRAW_CARD", "SELF_DRAW_CARD", "OPPONENT_DRAW_CARD", "DISCARD_CARD"))) > 0L) {
        contexts <- c(contexts, "card_flow")
      }
      if (length(intersect(trigger_events, c("DIES", "SACRIFICE_PERMANENT"))) > 0L) {
        contexts <- c(contexts, "death")
      }
      if (length(intersect(trigger_events, c("ETB"))) > 0L) {
        contexts <- c(contexts, "etb")
      }
    }

    if (nzchar(query_api_scalar(ability$trigger$cost, default = ""))) {
      contexts <- c(contexts, "activated")
    }
  }

  if (grepl("whenever|at the beginning|each combat|each upkeep|during each", lower_text, perl = TRUE)) {
    repeatable_signals <- repeatable_signals + 1L
  }
  if (grepl("\\bx\\b|for each|one or more|additional|double|twice", lower_text, perl = TRUE)) {
    scalable_signals <- scalable_signals + 1L
  }
  if (grepl("attack|attacking|combat damage", lower_text, perl = TRUE)) {
    contexts <- c(contexts, "combat")
  }
  if (grepl("upkeep|end step", lower_text, perl = TRUE)) {
    contexts <- c(contexts, "turn_cycle")
  }
  if (length(intersect(query_synergy_to_vector(mechanics), c("connive", "cycling", "flashback", "escape", "blitz", "cascade", "discover", "populate", "investigate", "lifelink", "foretell"))) > 0L) {
    repeatable_signals <- repeatable_signals + 1L
  }
  if (length(intersect(query_synergy_to_vector(mechanics), c("connive", "cascade", "discover", "populate", "proliferate", "blitz"))) > 0L) {
    scalable_signals <- scalable_signals + 1L
  }

  repeatable <- (permanent && repeatable_signals > 0L) || repeatable_signals >= 2L
  scalable <- scalable_signals > 0L
  contexts <- unique(contexts)
  sources <- unique(query_synergy_to_vector(sources))

  strength <- 0
  if (repeatable) {
    strength <- strength + 0.55
  }
  if (scalable) {
    strength <- strength + 0.2
  }
  if (permanent) {
    strength <- strength + 0.1
  }
  if (length(contexts) > 0L) {
    strength <- strength + min(0.15, length(contexts) * 0.05)
  }
  if (length(intersect(query_synergy_to_vector(produced), c("DRAW_CARD", "CREATE_TOKEN", "PUT_COUNTER", "CAST_SPELL", "ADD_MANA"))) > 0L && repeatable) {
    strength <- strength + 0.1
  }

  class_id <- if (repeatable && scalable) {
    "repeatable_scalable"
  } else if (repeatable) {
    "repeatable"
  } else if (scalable) {
    "scalable"
  } else {
    "one_shot"
  }

  list(
    class = class_id,
    repeatable = repeatable,
    scalable = scalable,
    strength = round(min(1, strength), 4),
    contexts = contexts,
    sources = sources
  )
}

query_synergy_event_registry_default <- local({
  cached <- NULL

  function() {
    if (!is.null(cached)) {
      return(cached)
    }

    cached <<- query_synergy_build_event_registry(query_synergy_event_registry_seed())
    cached
  }
})

query_synergy_event_registry_seed <- function() {
  list(
    DRAW_CARD = list(
      label = "Draw card",
      description = "Card draw event",
      parent = "CARD_FLOW",
      aliases = c("DRAW"),
      kind = "resource_flow",
      scope = "generic",
      resource = "card",
      zones = list(from = "library", to = "hand"),
      tags = c("card_flow")
    ),
    SELF_DRAW_CARD = list(
      label = "Self draw",
      description = "You draw one or more cards",
      parent = "DRAW_CARD",
      aliases = c("YOU_DRAW_CARD"),
      kind = "resource_flow",
      scope = "self",
      resource = "card",
      zones = list(from = "library", to = "hand"),
      tags = c("card_flow", "self")
    ),
    OPPONENT_DRAW_CARD = list(
      label = "Opponent draw",
      description = "An opponent draws one or more cards",
      parent = "DRAW_CARD",
      aliases = character(0),
      kind = "resource_flow",
      scope = "opponent",
      resource = "card",
      zones = list(from = "library", to = "hand"),
      tags = c("card_flow", "opponent")
    ),
    DISCARD_CARD = list(
      label = "Discard card",
      description = "Card discard event",
      parent = "CARD_FLOW",
      aliases = c("CARD_DISCARDED"),
      kind = "resource_flow",
      scope = "generic",
      resource = "card",
      zones = list(from = "hand", to = "graveyard"),
      tags = c("card_flow")
    ),
    GAIN_LIFE = list(
      label = "Gain life",
      description = "Life gain event",
      parent = "LIFE_TOTAL",
      aliases = c("LIFE_GAINED"),
      kind = "resource_delta",
      scope = "generic",
      resource = "life",
      zones = list(),
      tags = c("life")
    ),
    LOSE_LIFE = list(
      label = "Lose life",
      description = "Life loss event",
      parent = "LIFE_TOTAL",
      aliases = c("LIFE_LOST"),
      kind = "resource_delta",
      scope = "generic",
      resource = "life",
      zones = list(),
      tags = c("life")
    ),
    CREATE_TOKEN = list(
      label = "Create token",
      description = "Token creation event",
      parent = "BOARD_DEVELOPMENT",
      aliases = c("TOKEN_CREATED"),
      kind = "board_delta",
      scope = "generic",
      resource = "token",
      zones = list(from = "outside_game", to = "battlefield"),
      tags = c("tokens")
    ),
    ADD_MANA = list(
      label = "Add mana",
      description = "Mana generation event",
      parent = "MANA_ENGINE",
      aliases = character(0),
      kind = "resource_delta",
      scope = "generic",
      resource = "mana",
      zones = list(),
      tags = c("mana")
    ),
    PUT_COUNTER = list(
      label = "Put counter",
      description = "Counter placement event",
      parent = "BOARD_DEVELOPMENT",
      aliases = c("COUNTER_PLACED"),
      kind = "board_delta",
      scope = "generic",
      resource = "counter",
      zones = list(),
      tags = c("counters")
    ),
    SACRIFICE_PERMANENT = list(
      label = "Sacrifice permanent",
      description = "Sacrifice event",
      parent = "GRAVEYARD_FLOW",
      aliases = character(0),
      kind = "zone_change",
      scope = "generic",
      resource = "permanent",
      zones = list(from = "battlefield", to = "graveyard"),
      tags = c("sacrifice")
    ),
    ETB = list(
      label = "Enters battlefield",
      description = "Permanent ETB event",
      parent = "BOARD_DEVELOPMENT",
      aliases = c("ENTERS_THE_BATTLEFIELD"),
      kind = "zone_change",
      scope = "generic",
      resource = "permanent",
      zones = list(from = "stack", to = "battlefield"),
      tags = c("battlefield")
    ),
    DIES = list(
      label = "Dies",
      description = "Permanent dies event",
      parent = "GRAVEYARD_FLOW",
      aliases = c("CREATURE_DIES"),
      kind = "zone_change",
      scope = "generic",
      resource = "permanent",
      zones = list(from = "battlefield", to = "graveyard"),
      tags = c("death")
    ),
    ATTACKS = list(
      label = "Attacks",
      description = "Attack event",
      parent = "COMBAT",
      aliases = c("ATTACK_DECLARED"),
      kind = "combat",
      scope = "generic",
      resource = "",
      zones = list(),
      tags = c("combat")
    ),
    CAST_SPELL = list(
      label = "Cast spell",
      description = "Spell cast event",
      parent = "STACK",
      aliases = character(0),
      kind = "stack",
      scope = "generic",
      resource = "spell",
      zones = list(from = "hand", to = "stack"),
      tags = c("casting")
    ),
    GRAVEYARD_TO_HAND = list(
      label = "GY to hand",
      description = "Recursion from graveyard to hand",
      parent = "GRAVEYARD_FLOW",
      aliases = c("RECURSION_TO_HAND"),
      kind = "zone_change",
      scope = "generic",
      resource = "card",
      zones = list(from = "graveyard", to = "hand"),
      tags = c("graveyard", "recursion")
    ),
    MILL_CARD = list(
      label = "Mill card",
      description = "Library to graveyard",
      parent = "GRAVEYARD_FLOW",
      aliases = c("SELF_MILL"),
      kind = "zone_change",
      scope = "generic",
      resource = "card",
      zones = list(from = "library", to = "graveyard"),
      tags = c("graveyard", "mill")
    ),
    REANIMATE = list(
      label = "Reanimate",
      description = "Graveyard to battlefield",
      parent = "GRAVEYARD_FLOW",
      aliases = character(0),
      kind = "zone_change",
      scope = "generic",
      resource = "permanent",
      zones = list(from = "graveyard", to = "battlefield"),
      tags = c("graveyard", "reanimate")
    ),
    NONCREATURE_SPELL_CAST = list(
      label = "Cast noncreature",
      description = "Noncreature spell cast",
      parent = "CAST_SPELL",
      aliases = character(0),
      kind = "stack",
      scope = "generic",
      resource = "spell",
      zones = list(from = "hand", to = "stack"),
      tags = c("casting", "noncreature")
    ),
    COMBAT_DAMAGE_TO_PLAYER = list(
      label = "Combat damage to player",
      description = "Combat damage connection",
      parent = "COMBAT",
      aliases = character(0),
      kind = "combat",
      scope = "generic",
      resource = "damage",
      zones = list(),
      tags = c("combat", "damage")
    ),
    TARGETS_CREATURE = list(
      label = "Targets creature",
      description = "Spell or ability targets a creature",
      parent = "STACK",
      aliases = character(0),
      kind = "targeting",
      scope = "generic",
      resource = "creature",
      zones = list(),
      tags = c("targeting")
    ),
    EXILE_CARD = list(
      label = "Exile card",
      description = "Card is exiled",
      parent = "ZONE_CHANGE",
      aliases = character(0),
      kind = "zone_change",
      scope = "generic",
      resource = "card",
      zones = list(to = "exile"),
      tags = c("exile")
    )
  )
}

query_synergy_build_event_lineage_for_id <- function(event_id, events) {
  lineage <- character(0)
  current <- query_api_scalar(event_id, default = "")
  visited <- character(0)

  while (nzchar(current) && !current %in% visited) {
    lineage <- c(lineage, current)
    visited <- c(visited, current)
    current <- query_api_scalar(events[[current]]$parent, default = "")
  }

  unique(lineage)
}

query_synergy_build_event_family_for_id <- function(event_id, children_by_parent = list()) {
  family <- character(0)
  queue <- query_synergy_to_vector(event_id)

  while (length(queue) > 0L) {
    current <- queue[[1]]
    if (length(queue) == 1L) {
      queue <- character(0)
    } else {
      queue <- queue[-1]
    }

    if (!nzchar(current) || current %in% family) {
      next
    }

    family <- c(family, current)
    children <- setdiff(query_synergy_to_vector(children_by_parent[[current]]), family)
    if (length(children) > 0L) {
      queue <- c(queue, children)
    }
  }

  unique(family)
}

query_synergy_build_event_registry <- function(events = list(), base_registry = NULL) {
  if (is.list(base_registry) && is.list(base_registry$events)) {
    merged <- base_registry$events
  } else if (is.list(base_registry) && length(base_registry) > 0L && is.null(base_registry$events)) {
    merged <- base_registry
  } else {
    merged <- list()
  }

  additions <- if (is.list(events)) events else list()
  for (name in names(additions)) {
    event_id <- query_synergy_normalize_event_id(name)
    if (!nzchar(event_id)) {
      next
    }
    merged[[event_id]] <- query_synergy_normalize_event_definition(event_id, additions[[name]])
  }

  alias_to_id <- list()
  for (event_id in names(merged)) {
    event_def <- query_synergy_normalize_event_definition(event_id, merged[[event_id]])
    merged[[event_id]] <- event_def
    aliases <- unique(c(event_id, query_synergy_to_vector(event_def$aliases)))
    for (alias in aliases) {
      alias_to_id[[query_synergy_normalize_event_id(alias)]] <- event_id
    }
  }

  children_by_parent <- list()
  for (event_id in names(merged)) {
    parent_id <- query_api_scalar(merged[[event_id]]$parent, default = "")
    if (!nzchar(parent_id)) {
      next
    }
    children_by_parent[[parent_id]] <- unique(c(query_synergy_to_vector(children_by_parent[[parent_id]]), event_id))
  }

  lineage_cache <- lapply(names(merged), function(event_id) {
    query_synergy_build_event_lineage_for_id(event_id, merged)
  })
  names(lineage_cache) <- names(merged)

  family_cache <- lapply(names(merged), function(event_id) {
    query_synergy_build_event_family_for_id(event_id, children_by_parent)
  })
  names(family_cache) <- names(merged)

  list(
    events = merged,
    alias_to_id = alias_to_id,
    children_by_parent = children_by_parent,
    lineage_cache = lineage_cache,
    family_cache = family_cache
  )
}

query_synergy_normalize_event_definition <- function(event_id, definition) {
  def <- if (is.list(definition)) definition else list()
  zones <- def$zones
  if (!is.list(zones)) {
    zones <- list()
  }

  list(
    id = query_synergy_normalize_event_id(event_id),
    label = query_api_scalar(def$label, default = query_synergy_normalize_event_id(event_id)),
    description = query_api_scalar(def$description, default = ""),
    parent = query_synergy_normalize_event_id(query_api_scalar(def$parent, default = "")),
    aliases = unique(query_synergy_to_vector(def$aliases)),
    kind = query_api_scalar(def$kind, default = "event"),
    scope = query_api_scalar(def$scope, default = "generic"),
    resource = query_api_scalar(def$resource, default = ""),
    zones = list(
      from = query_api_scalar(zones$from, default = ""),
      to = query_api_scalar(zones$to, default = "")
    ),
    tags = unique(query_synergy_to_vector(def$tags))
  )
}

query_synergy_normalize_event_id <- function(value) {
  raw <- toupper(query_api_scalar(value, default = ""))
  key <- gsub("[^A-Z0-9]+", "_", raw)
  key <- gsub("_+", "_", key)
  gsub("^_|_$", "", key)
}

query_synergy_mechanic_rules_default <- local({
  cached <- NULL

  function() {
    if (!is.null(cached)) {
      return(cached)
    }

    cached <<- query_synergy_build_mechanic_rules(list(
      connive = list(
        keywords = c("connive"),
        produced = c("DRAW_CARD", "DISCARD_CARD", "PUT_COUNTER"),
        consumed = character(0),
        replaced = character(0),
        prevented = character(0),
        setup = c("DRAW_DISCARD_ENGINE"),
        finisher = character(0),
        anti_tags = character(0),
        strategy_tags = c("draw_discard", "counter_scaling"),
        ability_templates = list(
          list(
            kind = "triggered",
            label = "Connive",
            trigger = list(event = "ATTACKS", scope = "self"),
            effects = list(
              list(role = "produce", event = "DRAW_CARD"),
              list(role = "produce", event = "DISCARD_CARD"),
              list(role = "produce", event = "PUT_COUNTER", condition = "if a nonland card is discarded")
            ),
            references = list(
              plans = c("draw_discard", "counter_scaling"),
              setup = c("DRAW_DISCARD_ENGINE")
            )
          )
        ),
        notes = "Connive decomposes to draw, discard, and conditional counter growth"
      ),
      cycling = list(
        keywords = c("cycling"),
        produced = c("DRAW_CARD", "DISCARD_CARD"),
        consumed = character(0),
        replaced = character(0),
        prevented = character(0),
        setup = c("DRAW_DISCARD_ENGINE"),
        finisher = character(0),
        anti_tags = character(0),
        strategy_tags = c("draw_discard"),
        ability_templates = list(
          list(
            kind = "activated",
            label = "Cycling",
            trigger = list(cost = "discard this card"),
            effects = list(
              list(role = "produce", event = "DISCARD_CARD"),
              list(role = "produce", event = "DRAW_CARD")
            ),
            references = list(
              plans = c("draw_discard"),
              setup = c("DRAW_DISCARD_ENGINE")
            )
          )
        ),
        notes = "Cycling is modeled as discard this card then draw"
      ),
      surveil = list(
        keywords = c("surveil"),
        produced = c("MILL_CARD"),
        consumed = character(0),
        replaced = character(0),
        prevented = character(0),
        setup = c("GRAVEYARD_SETUP"),
        finisher = character(0),
        anti_tags = character(0),
        strategy_tags = c("graveyard_setup"),
        ability_templates = list(
          list(
            kind = "keyword_action",
            label = "Surveil",
            trigger = list(),
            effects = list(
              list(role = "produce", event = "MILL_CARD")
            ),
            references = list(
              plans = c("graveyard_setup"),
              setup = c("GRAVEYARD_SETUP")
            )
          )
        ),
        notes = "Surveil sets up graveyard resources"
      ),
      exploit = list(
        keywords = c("exploit"),
        produced = c("SACRIFICE_PERMANENT"),
        consumed = c("ETB"),
        replaced = character(0),
        prevented = character(0),
        setup = c("SACRIFICE_ENGINE"),
        finisher = c("DEATH_PAYOFF"),
        anti_tags = character(0),
        strategy_tags = c("sacrifice", "death_triggers"),
        ability_templates = list(
          list(
            kind = "triggered",
            label = "Exploit",
            trigger = list(event = "ETB", scope = "self"),
            effects = list(
              list(role = "require", event = "ETB"),
              list(role = "produce", event = "SACRIFICE_PERMANENT")
            ),
            references = list(
              plans = c("sacrifice", "death_triggers"),
              setup = c("SACRIFICE_ENGINE"),
              finisher = c("DEATH_PAYOFF")
            )
          )
        ),
        notes = "Exploit consumes ETB body and enables death/sacrifice payoffs"
      ),
      reanimate = list(
        keywords = c("reanimate", "unearth"),
        produced = c("REANIMATE"),
        consumed = c("MILL_CARD"),
        replaced = character(0),
        prevented = character(0),
        setup = character(0),
        finisher = c("GRAVEYARD_SETUP"),
        anti_tags = character(0),
        strategy_tags = c("graveyard", "reanimator"),
        ability_templates = list(
          list(
            kind = "spell_effect",
            label = "Reanimate",
            trigger = list(),
            effects = list(
              list(role = "require", event = "MILL_CARD"),
              list(role = "produce", event = "REANIMATE")
            ),
            references = list(
              plans = c("graveyard", "reanimator"),
              finisher = c("GRAVEYARD_SETUP")
            )
          )
        ),
        notes = "Reanimation effects consume graveyard setup"
      ),
      dredge = list(
        keywords = c("dredge"),
        produced = c("MILL_CARD", "GRAVEYARD_TO_HAND"),
        consumed = character(0),
        replaced = c("DRAW_CARD"),
        prevented = character(0),
        setup = c("GRAVEYARD_SETUP"),
        finisher = character(0),
        anti_tags = c("REPLACES_DRAW"),
        strategy_tags = c("graveyard", "dredge"),
        ability_templates = list(
          list(
            kind = "replacement",
            label = "Dredge",
            trigger = list(condition = "if you would draw a card"),
            effects = list(
              list(role = "replace", event = "DRAW_CARD"),
              list(role = "produce", event = "MILL_CARD"),
              list(role = "produce", event = "GRAVEYARD_TO_HAND")
            ),
            references = list(
              plans = c("graveyard", "dredge"),
              setup = c("GRAVEYARD_SETUP"),
              anti = c("REPLACES_DRAW")
            )
          )
        ),
        notes = "Dredge replaces draw with self-mill and recursion to hand"
      ),
      madness = list(
        keywords = c("madness"),
        produced = c("CAST_SPELL"),
        consumed = c("DISCARD_CARD"),
        replaced = character(0),
        prevented = character(0),
        setup = c("DRAW_DISCARD_ENGINE"),
        finisher = character(0),
        anti_tags = character(0),
        strategy_tags = c("draw_discard", "madness"),
        ability_templates = list(
          list(
            kind = "replacement",
            label = "Madness",
            trigger = list(condition = "if you discard this card"),
            effects = list(
              list(role = "require", event = "DISCARD_CARD"),
              list(role = "produce", event = "CAST_SPELL")
            ),
            references = list(
              plans = c("draw_discard", "madness"),
              setup = c("DRAW_DISCARD_ENGINE")
            )
          )
        ),
        notes = "Madness turns discard into cast opportunities"
      ),
      flashback = list(
        keywords = c("flashback"),
        produced = c("CAST_SPELL"),
        consumed = c("MILL_CARD"),
        replaced = character(0),
        prevented = character(0),
        setup = character(0),
        finisher = c("GRAVEYARD_SETUP"),
        anti_tags = character(0),
        strategy_tags = c("graveyard", "flashback"),
        ability_templates = list(
          list(
            kind = "activated",
            label = "Flashback",
            trigger = list(zone = "graveyard"),
            effects = list(
              list(role = "require", event = "MILL_CARD"),
              list(role = "produce", event = "CAST_SPELL")
            ),
            references = list(
              plans = c("graveyard", "flashback"),
              finisher = c("GRAVEYARD_SETUP")
            )
          )
        ),
        notes = "Flashback consumes graveyard setup to recast spells"
      ),
      cascade = list(
        keywords = c("cascade"),
        produced = c("CAST_SPELL"),
        consumed = c("CAST_SPELL"),
        replaced = character(0),
        prevented = character(0),
        setup = character(0),
        finisher = character(0),
        anti_tags = character(0),
        strategy_tags = c("value_chain"),
        ability_templates = list(
          list(
            kind = "triggered",
            label = "Cascade",
            trigger = list(event = "CAST_SPELL", scope = "self"),
            effects = list(
              list(role = "require", event = "CAST_SPELL"),
              list(role = "produce", event = "CAST_SPELL")
            ),
            references = list(plans = c("value_chain"))
          )
        ),
        notes = "Cascade chains one cast event into additional cast value"
      ),
      discover = list(
        keywords = c("discover"),
        produced = c("CAST_SPELL"),
        consumed = c("CAST_SPELL"),
        replaced = character(0),
        prevented = character(0),
        setup = character(0),
        finisher = character(0),
        anti_tags = character(0),
        strategy_tags = c("value_chain"),
        ability_templates = list(
          list(
            kind = "triggered",
            label = "Discover",
            trigger = list(event = "CAST_SPELL", scope = "self"),
            effects = list(
              list(role = "require", event = "CAST_SPELL"),
              list(role = "produce", event = "CAST_SPELL")
            ),
            references = list(plans = c("value_chain"))
          )
        ),
        notes = "Discover is modeled as cast conversion value"
      ),
      populate = list(
        keywords = c("populate"),
        produced = c("CREATE_TOKEN"),
        consumed = c("CREATE_TOKEN"),
        replaced = character(0),
        prevented = character(0),
        setup = character(0),
        finisher = c("TOKEN_PAYOFF"),
        anti_tags = character(0),
        strategy_tags = c("tokens"),
        ability_templates = list(
          list(
            kind = "spell_effect",
            label = "Populate",
            trigger = list(),
            effects = list(
              list(role = "require", event = "CREATE_TOKEN"),
              list(role = "produce", event = "CREATE_TOKEN")
            ),
            references = list(
              plans = c("tokens"),
              finisher = c("TOKEN_PAYOFF")
            )
          )
        ),
        notes = "Populate converts token setup into additional token output"
      ),
      investigate = list(
        keywords = c("investigate"),
        produced = c("CREATE_TOKEN"),
        consumed = character(0),
        replaced = character(0),
        prevented = character(0),
        setup = character(0),
        finisher = character(0),
        anti_tags = character(0),
        strategy_tags = c("tokens", "card_flow"),
        ability_templates = list(
          list(
            kind = "keyword_action",
            label = "Investigate",
            trigger = list(),
            effects = list(
              list(role = "produce", event = "CREATE_TOKEN")
            ),
            references = list(plans = c("tokens", "card_flow"))
          )
        ),
        notes = "Investigate creates Clue token resources"
      ),
      casualty = list(
        keywords = c("casualty"),
        produced = c("SACRIFICE_PERMANENT"),
        consumed = c("CAST_SPELL"),
        replaced = character(0),
        prevented = character(0),
        setup = c("SACRIFICE_ENGINE"),
        finisher = character(0),
        anti_tags = character(0),
        strategy_tags = c("sacrifice", "spells"),
        ability_templates = list(
          list(
            kind = "replacement",
            label = "Casualty",
            trigger = list(condition = "as an additional cost to cast this spell"),
            effects = list(
              list(role = "require", event = "CAST_SPELL"),
              list(role = "produce", event = "SACRIFICE_PERMANENT")
            ),
            references = list(
              plans = c("sacrifice", "spells"),
              setup = c("SACRIFICE_ENGINE")
            )
          )
        ),
        notes = "Casualty converts casting into sacrifice pressure"
      ),
      lifelink = list(
        keywords = c("lifelink"),
        produced = c("GAIN_LIFE"),
        consumed = c("COMBAT_DAMAGE_TO_PLAYER"),
        replaced = character(0),
        prevented = character(0),
        setup = character(0),
        finisher = character(0),
        anti_tags = character(0),
        strategy_tags = c("combat", "life"),
        ability_templates = list(
          list(
            kind = "static",
            label = "Lifelink",
            trigger = list(event = "COMBAT_DAMAGE_TO_PLAYER"),
            effects = list(
              list(role = "require", event = "COMBAT_DAMAGE_TO_PLAYER"),
              list(role = "produce", event = "GAIN_LIFE")
            ),
            references = list(plans = c("combat", "life"))
          )
        ),
        notes = "Lifelink converts combat damage into life gain"
      ),
      foretell = list(
        keywords = c("foretell"),
        produced = c("CAST_SPELL"),
        consumed = c("CAST_SPELL"),
        replaced = character(0),
        prevented = character(0),
        setup = c("DEFERRED_CAST"),
        finisher = character(0),
        anti_tags = character(0),
        strategy_tags = c("tempo", "spells"),
        ability_templates = list(
          list(
            kind = "activated",
            label = "Foretell",
            trigger = list(zone = "exile"),
            effects = list(
              list(role = "require", event = "CAST_SPELL"),
              list(role = "produce", event = "CAST_SPELL")
            ),
            references = list(
              plans = c("tempo", "spells"),
              setup = c("DEFERRED_CAST")
            )
          )
        ),
        notes = "Foretell defers cast timing while preserving cast events"
      ),
      delve = list(
        keywords = c("delve"),
        produced = c("CAST_SPELL"),
        consumed = c("MILL_CARD"),
        replaced = character(0),
        prevented = character(0),
        setup = character(0),
        finisher = c("GRAVEYARD_SETUP"),
        anti_tags = c("GRAVEYARD_DEPENDENT"),
        strategy_tags = c("graveyard", "spells"),
        ability_templates = list(
          list(
            kind = "static",
            label = "Delve",
            trigger = list(cost = "exile cards from your graveyard"),
            effects = list(
              list(role = "require", event = "MILL_CARD"),
              list(role = "produce", event = "CAST_SPELL")
            ),
            references = list(
              plans = c("graveyard", "spells"),
              finisher = c("GRAVEYARD_SETUP"),
              anti = c("GRAVEYARD_DEPENDENT")
            )
          )
        ),
        notes = "Delve consumes graveyard fuel to support casting"
      ),
      escape = list(
        keywords = c("escape"),
        produced = c("CAST_SPELL"),
        consumed = c("MILL_CARD"),
        replaced = character(0),
        prevented = character(0),
        setup = character(0),
        finisher = c("GRAVEYARD_SETUP"),
        anti_tags = c("GRAVEYARD_DEPENDENT"),
        strategy_tags = c("graveyard", "escape"),
        ability_templates = list(
          list(
            kind = "activated",
            label = "Escape",
            trigger = list(zone = "graveyard"),
            effects = list(
              list(role = "require", event = "MILL_CARD"),
              list(role = "produce", event = "CAST_SPELL")
            ),
            references = list(
              plans = c("graveyard", "escape"),
              finisher = c("GRAVEYARD_SETUP"),
              anti = c("GRAVEYARD_DEPENDENT")
            )
          )
        ),
        notes = "Escape recasts from graveyard using graveyard fuel"
      ),
      blitz = list(
        keywords = c("blitz"),
        produced = c("ATTACKS", "DRAW_CARD"),
        consumed = c("CAST_SPELL"),
        replaced = character(0),
        prevented = character(0),
        setup = c("DRAW_DISCARD_ENGINE"),
        finisher = character(0),
        anti_tags = character(0),
        strategy_tags = c("combat", "draw_discard"),
        ability_templates = list(
          list(
            kind = "activated",
            label = "Blitz",
            trigger = list(condition = "when this creature dies, draw a card"),
            effects = list(
              list(role = "require", event = "CAST_SPELL"),
              list(role = "produce", event = "ATTACKS"),
              list(role = "produce", event = "DRAW_CARD")
            ),
            references = list(
              plans = c("combat", "draw_discard"),
              setup = c("DRAW_DISCARD_ENGINE")
            )
          )
        ),
        notes = "Blitz compresses cast, attack pressure, and card flow"
      ),
      offspring = list(
        keywords = c("offspring"),
        produced = c("CREATE_TOKEN"),
        consumed = c("CAST_SPELL"),
        replaced = character(0),
        prevented = character(0),
        setup = character(0),
        finisher = c("TOKEN_PAYOFF"),
        anti_tags = character(0),
        strategy_tags = c("tokens", "creatures"),
        ability_templates = list(
          list(
            kind = "triggered",
            label = "Offspring",
            trigger = list(event = "ETB", scope = "self"),
            effects = list(
              list(role = "require", event = "CAST_SPELL"),
              list(role = "produce", event = "CREATE_TOKEN")
            ),
            references = list(
              plans = c("tokens", "creatures"),
              finisher = c("TOKEN_PAYOFF")
            )
          )
        ),
        notes = "Offspring creates extra body resources from cast sequencing"
      )
    ))

    cached
  }
})

query_synergy_build_mechanic_rules <- function(rules = list(),
                                               base_rules = NULL,
                                               registry = query_synergy_event_registry_default()) {
  merged <- if (is.list(base_rules) && length(base_rules) > 0L) base_rules else list()
  additions <- if (is.list(rules)) rules else list()

  for (rule_id in names(additions)) {
    merged[[tolower(query_api_scalar(rule_id, default = ""))]] <- additions[[rule_id]]
  }

  out <- list()
  for (rule_id in names(merged)) {
    normalized_id <- tolower(query_api_scalar(rule_id, default = ""))
    if (!nzchar(normalized_id)) {
      next
    }
    out[[normalized_id]] <- query_synergy_normalize_mechanic_rule(normalized_id, merged[[rule_id]], registry = registry)
  }

  out
}

query_synergy_normalize_mechanic_rule <- function(rule_id, rule, registry = query_synergy_event_registry_default()) {
  value <- if (is.list(rule)) rule else list()
  list(
    keywords = unique(tolower(query_synergy_to_vector(value$keywords))),
    produced = query_synergy_canonicalize_events(value$produced, registry),
    consumed = query_synergy_canonicalize_events(value$consumed, registry),
    replaced = query_synergy_canonicalize_events(value$replaced, registry),
    prevented = query_synergy_canonicalize_events(value$prevented, registry),
    setup = unique(query_synergy_to_vector(value$setup)),
    finisher = unique(query_synergy_to_vector(value$finisher)),
    anti_tags = unique(query_synergy_to_vector(value$anti_tags)),
    strategy_tags = unique(query_synergy_to_vector(value$strategy_tags)),
    ability_templates = query_synergy_normalize_ability_templates(
      value$ability_templates,
      mechanic_id = rule_id,
      registry = registry
    ),
    notes = query_api_scalar(value$notes, default = "")
  )
}

query_synergy_expand_mechanics <- function(mechanics,
                                           registry = query_synergy_event_registry_default(),
                                           rules = query_synergy_mechanic_rules_default()) {
  normalized_mechanics <- tolower(query_synergy_to_vector(mechanics))

  produced <- character(0)
  consumed <- character(0)
  replaced <- character(0)
  prevented <- character(0)
  setup <- character(0)
  finisher <- character(0)
  anti_tags <- character(0)
  strategy_tags <- character(0)
  abilities <- list()

  for (rule_id in names(rules)) {
    rule <- rules[[rule_id]]
    if (length(intersect(normalized_mechanics, rule$keywords)) == 0L) {
      next
    }

    produced <- c(produced, query_synergy_canonicalize_events(rule$produced, registry))
    consumed <- c(consumed, query_synergy_canonicalize_events(rule$consumed, registry))
    replaced <- c(replaced, query_synergy_canonicalize_events(rule$replaced, registry))
    prevented <- c(prevented, query_synergy_canonicalize_events(rule$prevented, registry))
    setup <- c(setup, query_synergy_to_vector(rule$setup))
    finisher <- c(finisher, query_synergy_to_vector(rule$finisher))
    anti_tags <- c(anti_tags, query_synergy_to_vector(rule$anti_tags))
    strategy_tags <- c(strategy_tags, query_synergy_to_vector(rule$strategy_tags))
    abilities <- c(abilities, query_synergy_materialize_rule_abilities(rule$ability_templates, registry = registry))
  }

  list(
    produced = unique(produced),
    consumed = unique(consumed),
    replaced = unique(replaced),
    prevented = unique(prevented),
    setup = unique(setup),
    finisher = unique(finisher),
    anti_tags = unique(anti_tags),
    strategy_tags = unique(strategy_tags),
    abilities = query_synergy_unique_abilities(abilities)
  )
}

query_synergy_normalize_ability_templates <- function(templates,
                                                      mechanic_id = "",
                                                      registry = query_synergy_event_registry_default()) {
  values <- query_synergy_to_list(templates)
  if (length(values) == 0L) {
    return(list())
  }

  out <- list()
  for (index in seq_along(values)) {
    template <- values[[index]]
    if (!is.list(template)) {
      next
    }

    trigger <- if (is.list(template$trigger)) template$trigger else list()
    references <- if (is.list(template$references)) template$references else list()
    effects <- query_synergy_normalize_ability_effects(template$effects, registry = registry)
    template_id <- query_api_scalar(template$id, default = sprintf("%s_%s", mechanic_id, index))

    out[[length(out) + 1L]] <- list(
      id = sprintf("mechanic_rule:%s", query_synergy_normalize_event_id(template_id)),
      kind = query_api_scalar(template$kind, default = "mechanic"),
      label = query_api_scalar(template$label, default = mechanic_id),
      source = "mechanic_rule",
      mechanic = tolower(query_api_scalar(mechanic_id, default = "")),
      text = query_api_scalar(template$text, default = query_api_scalar(template$label, default = mechanic_id)),
      trigger = trigger,
      effects = effects,
      references = list(
        plans = unique(query_synergy_to_vector(references$plans)),
        setup = unique(query_synergy_to_vector(references$setup)),
        finisher = unique(query_synergy_to_vector(references$finisher)),
        anti = unique(query_synergy_to_vector(references$anti))
      )
    )
  }

  out
}

query_synergy_normalize_ability_effects <- function(effects, registry = query_synergy_event_registry_default()) {
  values <- query_synergy_to_list(effects)
  if (length(values) == 0L) {
    return(list())
  }

  out <- list()
  for (entry in values) {
    if (!is.list(entry)) {
      next
    }
    event_id <- query_synergy_canonicalize_events(entry$event, registry)
    if (length(event_id) == 0L) {
      next
    }
    out[[length(out) + 1L]] <- list(
      role = query_api_scalar(entry$role, default = ""),
      event = event_id[[1]],
      condition = query_api_scalar(entry$condition, default = ""),
      parent = query_api_scalar(registry$events[[event_id[[1]]]]$parent, default = "")
    )
  }

  out
}

query_synergy_materialize_rule_abilities <- function(templates, registry = query_synergy_event_registry_default()) {
  values <- query_synergy_to_list(templates)
  if (length(values) == 0L) {
    return(list())
  }

  out <- list()
  for (entry in values) {
    if (!is.list(entry)) {
      next
    }

    effects <- query_synergy_normalize_ability_effects(entry$effects, registry = registry)
    out[[length(out) + 1L]] <- list(
      id = query_api_scalar(entry$id, default = ""),
      kind = query_api_scalar(entry$kind, default = "mechanic"),
      label = query_api_scalar(entry$label, default = ""),
      source = query_api_scalar(entry$source, default = "mechanic_rule"),
      mechanic = query_api_scalar(entry$mechanic, default = ""),
      text = query_api_scalar(entry$text, default = ""),
      trigger = if (is.list(entry$trigger)) entry$trigger else list(),
      effects = effects,
      references = if (is.list(entry$references)) entry$references else list()
    )
  }

  out
}

query_synergy_parse_structured_abilities <- function(oracle_text,
                                                     registry = query_synergy_event_registry_default(),
                                                     parse_rules = query_synergy_ability_parse_rules_default(registry = registry)) {
  text <- query_api_scalar(oracle_text, default = "")
  if (!nzchar(text)) {
    return(list(
      abilities = list(),
      produced = character(0),
      consumed = character(0),
      replaced = character(0),
      prevented = character(0),
      setup = character(0),
      finisher = character(0),
      anti_tags = character(0)
    ))
  }

  fragments <- query_synergy_oracle_fragments(text)
  if (length(fragments) == 0L) {
    return(list(
      abilities = list(),
      produced = character(0),
      consumed = character(0),
      replaced = character(0),
      prevented = character(0),
      setup = character(0),
      finisher = character(0),
      anti_tags = character(0)
    ))
  }

  abilities <- list()
  produced <- character(0)
  consumed <- character(0)
  replaced <- character(0)
  prevented <- character(0)
  setup <- character(0)
  finisher <- character(0)
  anti_tags <- character(0)

  for (index in seq_along(fragments)) {
    fragment <- fragments[[index]]
    fragment_out <- query_synergy_parse_ability_fragment(
      fragment,
      index = index,
      registry = registry,
      parse_rules = parse_rules
    )
    if (!isTRUE(fragment_out$ok)) {
      next
    }

    abilities[[length(abilities) + 1L]] <- fragment_out$ability
    produced <- c(produced, fragment_out$produced)
    consumed <- c(consumed, fragment_out$consumed)
    replaced <- c(replaced, fragment_out$replaced)
    prevented <- c(prevented, fragment_out$prevented)
    setup <- c(setup, fragment_out$setup)
    finisher <- c(finisher, fragment_out$finisher)
    anti_tags <- c(anti_tags, fragment_out$anti_tags)
  }

  list(
    abilities = query_synergy_unique_abilities(abilities),
    produced = unique(query_synergy_canonicalize_events(produced, registry)),
    consumed = unique(query_synergy_canonicalize_events(consumed, registry)),
    replaced = unique(query_synergy_canonicalize_events(replaced, registry)),
    prevented = unique(query_synergy_canonicalize_events(prevented, registry)),
    setup = unique(setup),
    finisher = unique(finisher),
    anti_tags = unique(anti_tags)
  )
}

query_synergy_oracle_fragments <- function(oracle_text) {
  raw <- query_api_scalar(oracle_text, default = "")
  if (!nzchar(raw)) {
    return(character(0))
  }

  split <- unlist(strsplit(raw, "(\\r?\\n)+|(?<=\\.)\\s+", perl = TRUE), use.names = FALSE)
  split <- trimws(split)
  split <- split[nzchar(split)]
  unique(split)
}

query_synergy_parse_ability_fragment <- function(fragment,
                                                 index = 1L,
                                                 registry = query_synergy_event_registry_default(),
                                                 parse_rules = query_synergy_ability_parse_rules_default(registry = registry)) {
  text <- query_api_scalar(fragment, default = "")
  lower <- tolower(text)
  if (!nzchar(lower)) {
    return(list(ok = FALSE))
  }

  kind <- query_synergy_classify_ability_fragment(lower)
  events <- query_synergy_extract_events_from_fragment(lower, registry = registry, parse_rules = parse_rules)
  effects <- query_synergy_fragment_effect_records(events, registry = registry)
  trigger <- query_synergy_fragment_trigger(kind, lower, events)

  has_static_keyword <- grepl("\\b(flying|trample|vigilance|haste|deathtouch|lifelink|ward|hexproof|menace|first strike|double strike|reach)\\b", lower, perl = TRUE)
  has_signal <- length(effects) > 0L ||
    length(events$anti_tags) > 0L ||
    kind %in% c("replacement", "triggered", "activated") ||
    has_static_keyword

  if (!isTRUE(has_signal)) {
    return(list(ok = FALSE))
  }

  ability <- list(
    id = sprintf("oracle:%03d:%s", as.integer(index), query_synergy_normalize_event_id(substr(lower, 1L, min(40L, nchar(lower))))),
    kind = kind,
    label = query_synergy_fragment_label(kind, lower),
    source = "oracle_parse",
    mechanic = "",
    text = text,
    trigger = trigger,
    effects = effects,
    references = list(
      plans = unique(c(events$setup, events$finisher)),
      setup = unique(events$setup),
      finisher = unique(events$finisher),
      anti = unique(events$anti_tags)
    )
  )

  list(
    ok = TRUE,
    ability = ability,
    produced = events$produced,
    consumed = events$consumed,
    replaced = events$replaced,
    prevented = events$prevented,
    setup = events$setup,
    finisher = events$finisher,
    anti_tags = events$anti_tags
  )
}

query_synergy_classify_ability_fragment <- function(text) {
  value <- tolower(query_api_scalar(text, default = ""))
  if (!nzchar(value)) {
    return("static")
  }
  if (grepl("\\bif\\b.*\\bwould\\b.*\\binstead\\b", value, perl = TRUE) || grepl("\\binstead of\\b", value, perl = TRUE)) {
    return("replacement")
  }
  if (grepl("^whenever\\b|^when\\b|^at the beginning\\b|^at the end\\b", value, perl = TRUE)) {
    return("triggered")
  }
  if (grepl("^[^.:]+:\\s", value, perl = TRUE)) {
    return("activated")
  }
  if (grepl("\\b(flying|trample|vigilance|haste|deathtouch|lifelink|ward|hexproof|menace|first strike|double strike|reach)\\b", value, perl = TRUE)) {
    return("static")
  }
  "spell_effect"
}

query_synergy_fragment_label <- function(kind, text) {
  title <- switch(
    query_api_scalar(kind, default = "static"),
    triggered = "Triggered ability",
    replacement = "Replacement ability",
    activated = "Activated ability",
    static = "Static ability",
    "Spell effect"
  )
  if (!nzchar(query_api_scalar(text, default = ""))) {
    return(title)
  }
  title
}

query_synergy_fragment_trigger <- function(kind, text, events) {
  value <- query_api_scalar(text, default = "")
  role_events <- unique(c(events$consumed, events$replaced, events$prevented))

  if (identical(kind, "triggered")) {
    return(list(
      text = value,
      events = role_events
    ))
  }
  if (identical(kind, "replacement")) {
    return(list(
      condition = value,
      events = role_events
    ))
  }
  if (identical(kind, "activated")) {
    parts <- strsplit(value, ":", fixed = TRUE)[[1]]
    return(list(
      cost = trimws(parts[[1]]),
      events = role_events
    ))
  }

  list(events = role_events)
}

query_synergy_fragment_effect_records <- function(events, registry = query_synergy_event_registry_default()) {
  out <- list()
  mapping <- list(
    produce = events$produced,
    reward = events$consumed,
    replace = events$replaced,
    prevent = events$prevented
  )

  for (role in names(mapping)) {
    event_ids <- unique(query_synergy_canonicalize_events(mapping[[role]], registry))
    if (length(event_ids) == 0L) {
      next
    }
    for (event_id in event_ids) {
      out[[length(out) + 1L]] <- list(
        role = role,
        event = event_id,
        parent = query_api_scalar(registry$events[[event_id]]$parent, default = "")
      )
    }
  }

  out
}

query_synergy_extract_events_from_fragment <- function(text,
                                                       registry = query_synergy_event_registry_default(),
                                                       parse_rules = query_synergy_ability_parse_rules_default(registry = registry)) {
  lower <- tolower(query_api_scalar(text, default = ""))
  if (!nzchar(lower)) {
    return(list(
      produced = character(0),
      consumed = character(0),
      replaced = character(0),
      prevented = character(0),
      setup = character(0),
      finisher = character(0),
      anti_tags = character(0)
    ))
  }

  produced <- character(0)
  consumed <- character(0)
  replaced <- character(0)
  prevented <- character(0)
  setup <- character(0)
  finisher <- character(0)
  anti_tags <- character(0)

  produced_patterns <- parse_rules$produced_patterns
  consumed_patterns <- parse_rules$consumed_patterns

  for (event_name in names(produced_patterns)) {
    for (pattern in produced_patterns[[event_name]]) {
      if (grepl(pattern, lower, perl = TRUE)) {
        produced <- c(produced, event_name)
        break
      }
    }
  }

  for (event_name in names(consumed_patterns)) {
    for (pattern in consumed_patterns[[event_name]]) {
      if (grepl(pattern, lower, perl = TRUE)) {
        consumed <- c(consumed, event_name)
        break
      }
    }
  }

  event_aliases <- parse_rules$replacement_aliases
  for (event_name in names(event_aliases)) {
    aliases <- query_synergy_to_vector(event_aliases[[event_name]])
    if (length(aliases) == 0L) {
      next
    }

    has_replacement <- FALSE
    has_prevention <- FALSE
    for (alias in aliases) {
      alias_group <- sprintf("(?:%s)", alias)
      replace_would_pattern <- sprintf("if\\s+.*would\\s+%s[^.]*instead", alias_group)
      replace_instead_pattern <- sprintf("instead of\\s+%s", alias_group)
      prevent_cant_pattern <- sprintf("(?:can't|cannot)\\s+%s", alias_group)
      prevent_wont_pattern <- sprintf("%s\\s+(?:can't|cannot)", alias_group)

      if (grepl(replace_would_pattern, lower, perl = TRUE) || grepl(replace_instead_pattern, lower, perl = TRUE)) {
        has_replacement <- TRUE
      }
      if (grepl(prevent_cant_pattern, lower, perl = TRUE) || grepl(prevent_wont_pattern, lower, perl = TRUE)) {
        has_prevention <- TRUE
      }
    }

    if (has_replacement) {
      replaced <- c(replaced, event_name)
    }
    if (has_prevention) {
      prevented <- c(prevented, event_name)
    }
  }

  if (grepl("skip your draw step", lower, perl = TRUE)) {
    replaced <- c(replaced, "DRAW_CARD")
  }

  conflicting_events <- query_synergy_expand_event_family(c(replaced, prevented), registry)
  if (length(conflicting_events) > 0L) {
    produced <- setdiff(produced, conflicting_events)
    consumed <- setdiff(consumed, conflicting_events)
    anti_tags <- c(
      anti_tags,
      "EVENT_REPLACEMENT_OR_PREVENTION",
      sprintf("REPLACES_OR_PREVENTS_%s", conflicting_events)
    )
  }

  for (tag in names(parse_rules$setup_patterns)) {
    if (any(vapply(parse_rules$setup_patterns[[tag]], function(pattern) grepl(pattern, lower, perl = TRUE), logical(1)))) {
      setup <- c(setup, query_api_scalar(tag, default = ""))
    }
  }
  for (tag in names(parse_rules$finisher_patterns)) {
    if (any(vapply(parse_rules$finisher_patterns[[tag]], function(pattern) grepl(pattern, lower, perl = TRUE), logical(1)))) {
      finisher <- c(finisher, query_api_scalar(tag, default = ""))
    }
  }
  for (tag in names(parse_rules$anti_tag_patterns)) {
    if (any(vapply(parse_rules$anti_tag_patterns[[tag]], function(pattern) grepl(pattern, lower, perl = TRUE), logical(1)))) {
      anti_tags <- c(anti_tags, query_api_scalar(tag, default = ""))
    }
  }
  if ("SELF_DRAW_CARD" %in% consumed || "OPPONENT_DRAW_CARD" %in% consumed) {
    produced <- setdiff(produced, "DRAW_CARD")
    consumed <- c(consumed, "DRAW_CARD")
  }

  list(
    produced = unique(query_synergy_canonicalize_events(produced, registry)),
    consumed = unique(query_synergy_canonicalize_events(consumed, registry)),
    replaced = unique(query_synergy_canonicalize_events(replaced, registry)),
    prevented = unique(query_synergy_canonicalize_events(prevented, registry)),
    setup = unique(setup),
    finisher = unique(finisher),
    anti_tags = unique(anti_tags)
  )
}
query_synergy_extract_events_from_text <- function(oracle_text,
                                                   registry = query_synergy_event_registry_default(),
                                                   parse_rules = query_synergy_ability_parse_rules_default(registry = registry)) {
  query_synergy_parse_structured_abilities(oracle_text, registry = registry, parse_rules = parse_rules)
}

query_synergy_ability_parse_rules_default <- local({
  cached <- NULL

  function(registry = query_synergy_event_registry_default()) {
    if (!is.null(cached)) {
      return(cached)
    }

    cached <<- query_synergy_build_ability_parse_rules(
      base_rules = query_synergy_ability_parse_rules_seed(),
      registry = registry
    )
    cached
  }
})

query_synergy_ability_parse_rules_seed <- function() {
  list(
    produced_patterns = list(
      DRAW_CARD = c("draw\\s+(a|an|x|one|two|three|[0-9]+)\\s+card", "conniv"),
      DISCARD_CARD = c("discard\\s+(a|an|x|one|two|three|[0-9]+)\\s+card", "discards\\s+(a|an|x|one|two|three|[0-9]+)\\s+card", "conniv"),
      GAIN_LIFE = c("gain\\s+[0-9x]+\\s+life"),
      LOSE_LIFE = c("lose\\s+[0-9x]+\\s+life"),
      CREATE_TOKEN = c("create\\s+.*token"),
      ADD_MANA = c("add\\s*\\{"),
      PUT_COUNTER = c("put\\s+.*counter"),
      SACRIFICE_PERMANENT = c("sacrifice\\s+"),
      ETB = c("enters? the battlefield"),
      DIES = c("dies", "is put into (a|your|their) graveyard from the battlefield"),
      ATTACKS = c("whenever .* attacks", "when .* attacks", "target attacking creature"),
      CAST_SPELL = c("cast\\s+(a|an|this|that)?\\s*spell"),
      GRAVEYARD_TO_HAND = c("from your graveyard to your hand"),
      MILL_CARD = c("mill", "put the top .* of .* library into .* graveyard"),
      REANIMATE = c("from .* graveyard to the battlefield"),
      EXILE_CARD = c("exile .* card"),
      TARGETS_CREATURE = c("target .* creature")
    ),
    consumed_patterns = list(
      SELF_DRAW_CARD = c("whenever you draw", "if you draw"),
      OPPONENT_DRAW_CARD = c("whenever an opponent draws", "if an opponent draws"),
      DISCARD_CARD = c("whenever .* discards"),
      GAIN_LIFE = c("whenever you gain life", "if you gain life"),
      DIES = c("whenever .* dies", "whenever a creature dies"),
      CAST_SPELL = c("whenever you cast"),
      NONCREATURE_SPELL_CAST = c("whenever you cast a noncreature spell"),
      COMBAT_DAMAGE_TO_PLAYER = c("whenever .* deals combat damage to a player"),
      ATTACKS = c("whenever you attack", "when you attack")
    ),
    replacement_aliases = query_synergy_event_text_aliases(),
    setup_patterns = list(
      DRAW_DISCARD_ENGINE = c("whenever you draw|draw\\s+.*card|conniv"),
      GRAVEYARD_SETUP = c("surveil|mill|put the top .* library into .* graveyard")
    ),
    finisher_patterns = list(
      GRAVEYARD_SETUP = c("from .* graveyard to the battlefield|reanimate|unearth")
    ),
    anti_tag_patterns = list(
      HAND_SIZE_PAYOFF = c("no maximum hand size|for each card in your hand"),
      HAND_DISCARD_PRESSURE = c("discard your hand|each player.*discards|that player discards"),
      GRAVEYARD_HATE = c("exile all graveyards|cards in graveyards can't"),
      GRAVEYARD_DEPENDENT = c("from your graveyard")
    )
  )
}

query_synergy_build_ability_parse_rules <- function(rules = list(),
                                                    base_rules = NULL,
                                                    registry = query_synergy_event_registry_default()) {
  merged <- if (is.list(base_rules) && length(base_rules) > 0L) base_rules else query_synergy_ability_parse_rules_seed()
  additions <- if (is.list(rules)) rules else list()

  merge_event_map <- function(base_map, add_map) {
    out <- list()
    all_maps <- list(base_map, add_map)
    for (map in all_maps) {
      if (!is.list(map) || length(map) == 0L) {
        next
      }
      for (event_name in names(map)) {
        event_id <- query_synergy_canonicalize_events(event_name, registry)
        if (length(event_id) == 0L) {
          next
        }
        key <- event_id[[1]]
        out[[key]] <- unique(c(query_synergy_to_vector(out[[key]]), query_synergy_to_vector(map[[event_name]])))
      }
    }
    out
  }

  merge_tag_map <- function(base_map, add_map) {
    out <- list()
    all_maps <- list(base_map, add_map)
    for (map in all_maps) {
      if (!is.list(map) || length(map) == 0L) {
        next
      }
      for (tag_name in names(map)) {
        key <- query_api_scalar(tag_name, default = "")
        if (!nzchar(key)) {
          next
        }
        out[[key]] <- unique(c(query_synergy_to_vector(out[[key]]), query_synergy_to_vector(map[[tag_name]])))
      }
    }
    out
  }

  list(
    produced_patterns = merge_event_map(merged$produced_patterns, additions$produced_patterns),
    consumed_patterns = merge_event_map(merged$consumed_patterns, additions$consumed_patterns),
    replacement_aliases = merge_event_map(merged$replacement_aliases, additions$replacement_aliases),
    setup_patterns = merge_tag_map(merged$setup_patterns, additions$setup_patterns),
    finisher_patterns = merge_tag_map(merged$finisher_patterns, additions$finisher_patterns),
    anti_tag_patterns = merge_tag_map(merged$anti_tag_patterns, additions$anti_tag_patterns)
  )
}

query_synergy_strategy_tags_from_events <- function(produced,
                                                    consumed,
                                                    setup_events,
                                                    finisher_events,
                                                    roles = character(0),
                                                    cadence = list(),
                                                    target_roles = character(0)) {
  tags <- character(0)
  produced_events <- query_synergy_to_vector(produced)
  consumed_events <- query_synergy_to_vector(consumed)
  role_values <- query_synergy_to_vector(roles)
  target_values <- query_synergy_to_vector(target_roles)

  if (length(intersect(produced_events, c("DRAW_CARD", "DISCARD_CARD", "SELF_DRAW_CARD"))) > 0L ||
      length(intersect(consumed_events, c("DRAW_CARD", "SELF_DRAW_CARD", "DISCARD_CARD"))) > 0L) {
    tags <- c(tags, "draw_discard")
  }

  if (length(intersect(produced_events, c("MILL_CARD", "REANIMATE", "GRAVEYARD_TO_HAND"))) > 0L ||
      length(intersect(consumed_events, c("MILL_CARD", "REANIMATE", "GRAVEYARD_TO_HAND"))) > 0L ||
      length(intersect(setup_events, c("GRAVEYARD_SETUP"))) > 0L ||
      length(intersect(finisher_events, c("GRAVEYARD_SETUP"))) > 0L) {
    tags <- c(tags, "graveyard")
  }

  if (length(intersect(produced_events, c("CREATE_TOKEN", "PUT_COUNTER", "ETB", "DIES", "SACRIFICE_PERMANENT"))) > 0L) {
    tags <- c(tags, "board_engine")
  }

  if ("converter" %in% role_values) {
    tags <- c(tags, "converter")
  }
  if ("bridge" %in% role_values) {
    tags <- c(tags, "bridge_engine")
  }
  if ("engine" %in% role_values && isTRUE(cadence$repeatable)) {
    tags <- c(tags, "repeatable_engine")
  }
  if ("amplifier" %in% role_values) {
    tags <- c(tags, "amplifier")
  }
  if ("target" %in% role_values || length(target_values) > 0L) {
    tags <- c(tags, "targeted_play")
  }

  if (length(intersect(produced_events, c("DRAW_CARD", "SELF_DRAW_CARD"))) > 0L) {
    tags <- c(tags, "draw_enabler")
  }
  if (length(intersect(consumed_events, c("DRAW_CARD", "SELF_DRAW_CARD", "OPPONENT_DRAW_CARD"))) > 0L) {
    tags <- c(tags, "draw_payoff")
  }
  if (length(intersect(produced_events, c("DISCARD_CARD"))) > 0L) {
    tags <- c(tags, "discard_enabler")
  }
  if (length(intersect(consumed_events, c("DISCARD_CARD"))) > 0L) {
    tags <- c(tags, "discard_payoff")
  }
  if (length(intersect(produced_events, c("MILL_CARD"))) > 0L) {
    tags <- c(tags, "graveyard_enabler")
  }
  if (length(intersect(produced_events, c("REANIMATE", "GRAVEYARD_TO_HAND"))) > 0L || length(finisher_events) > 0L) {
    tags <- c(tags, "graveyard_finisher")
  }
  if (length(intersect(produced_events, c("CREATE_TOKEN"))) > 0L) {
    tags <- c(tags, "token_producer")
  }
  if (length(intersect(produced_events, c("SACRIFICE_PERMANENT"))) > 0L) {
    tags <- c(tags, "sacrifice_outlet")
  }
  if (length(intersect(consumed_events, c("DIES", "SACRIFICE_PERMANENT"))) > 0L) {
    tags <- c(tags, "death_payoff")
  }
  if (length(intersect(produced_events, c("CAST_SPELL", "NONCREATURE_SPELL_CAST"))) > 0L) {
    tags <- c(tags, "spell_enabler")
  }
  if (length(intersect(consumed_events, c("CAST_SPELL", "NONCREATURE_SPELL_CAST"))) > 0L) {
    tags <- c(tags, "spell_payoff")
  }
  if (length(intersect(produced_events, c("ATTACKS", "COMBAT_DAMAGE_TO_PLAYER"))) > 0L || "combat" %in% query_synergy_to_vector(cadence$contexts)) {
    tags <- c(tags, "combat_engine")
  }

  unique(tags)
}

query_synergy_event_text_aliases <- function() {
  list(
    DRAW_CARD = c("draw\\s+(?:a|an|x|one|two|three|[0-9]+)\\s+card", "draw\\s+cards?"),
    DISCARD_CARD = c("discard\\s+(?:a|an|x|one|two|three|[0-9]+)\\s+card", "discard\\s+cards?"),
    GAIN_LIFE = c("gain\\s+(?:x|[0-9]+)\\s+life"),
    LOSE_LIFE = c("lose\\s+(?:x|[0-9]+)\\s+life"),
    CREATE_TOKEN = c("create\\s+.*token"),
    SACRIFICE_PERMANENT = c("sacrifice\\s+(?:a|an|one|two|three|[0-9]+)?\\s*permanent", "sacrifice\\s+a\\s+creature")
  )
}

query_synergy_expand_event_family <- function(events, registry = query_synergy_event_registry_default()) {
  seeds <- unique(query_synergy_canonicalize_events(events, registry))
  if (length(seeds) == 0L) {
    return(character(0))
  }

  if (is.list(registry$family_cache) && length(registry$family_cache) > 0L) {
    cached <- unique(unlist(lapply(seeds, function(event_id) {
      query_synergy_to_vector(registry$family_cache[[event_id]])
    }), use.names = FALSE))
    if (length(cached) > 0L) {
      return(unique(cached))
    }
  }

  children_by_parent <- if (is.list(registry$children_by_parent)) registry$children_by_parent else list()
  family <- character(0)
  queue <- seeds

  while (length(queue) > 0L) {
    current <- queue[[1]]
    if (length(queue) == 1L) {
      queue <- character(0)
    } else {
      queue <- queue[-1]
    }

    if (!nzchar(current) || current %in% family) {
      next
    }

    family <- c(family, current)
    children <- setdiff(query_synergy_to_vector(children_by_parent[[current]]), family)
    if (length(children) > 0L) {
      queue <- c(queue, children)
    }
  }

  unique(family)
}

query_synergy_canonicalize_events <- function(events, registry = query_synergy_event_registry_default()) {
  values <- query_synergy_to_vector(events)
  if (length(values) == 0L) {
    return(character(0))
  }

  out <- character(0)
  alias_map <- registry$alias_to_id

  for (event_name in values) {
    key <- query_synergy_normalize_event_id(event_name)
    if (!nzchar(key)) {
      next
    }

    if (!is.null(alias_map[[key]])) {
      out <- c(out, alias_map[[key]])
      next
    }

    out <- c(out, key)
  }

  unique(out)
}

query_synergy_detect_mechanics_from_text <- function(oracle_text) {
  text <- tolower(query_api_scalar(oracle_text, default = ""))
  if (!nzchar(text)) {
    return(character(0))
  }

  patterns <- list(
    connive = "\\bconniv(e|es|ed|ing)\\b",
    cycling = "\\bcycl(ing|e|ed)?\\b",
    surveil = "\\bsurveil\\b",
    exploit = "\\bexploit\\b",
    reanimate = "\\breanimate\\b",
    unearth = "\\bunearth\\b",
    dredge = "\\bdredge\\b",
    madness = "\\bmadness\\b",
    flashback = "\\bflashback\\b",
    cascade = "\\bcascade\\b",
    discover = "\\bdiscover\\b",
    populate = "\\bpopulate\\b",
    mill = "\\bmill\\b",
    investigate = "\\binvestigate\\b",
    casualty = "\\bcasualty\\b",
    lifelink = "\\blifelink\\b",
    foretell = "\\bforetell\\b",
    delve = "\\bdelve\\b",
    proliferate = "\\bproliferate\\b",
    escape = "\\bescape\\b",
    blitz = "\\bblitz\\b",
    offspring = "\\boffspring\\b"
  )

  hits <- names(Filter(function(pattern) {
    grepl(pattern, text, perl = TRUE)
  }, patterns))

  unique(unlist(hits, use.names = FALSE))
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

query_synergy_cache_paths <- function(cache_dir = "") {
  base_dir <- trimws(as.character(cache_dir))
  if (!nzchar(base_dir)) {
    base_dir <- tryCatch(tools::R_user_dir("mtgcodex.api", which = "cache"), error = function(e) "")
  }
  if (!nzchar(base_dir)) {
    base_dir <- file.path(path.expand("~"), ".mtgcodex.api", "cache")
  }

  if (!dir.exists(base_dir)) {
    dir.create(base_dir, recursive = TRUE, showWarnings = FALSE)
  }

  list(
    base_dir = base_dir,
    json_file = file.path(base_dir, "scryfall_oracle_cards.json"),
    rds_file = file.path(base_dir, "scryfall_oracle_cards.rds"),
    precomputed_rds_file = file.path(base_dir, "scryfall_oracle_cards.precomputed.rds")
  )
}

query_synergy_cache_key_slug <- function(value, default = "catalog") {
  slug <- query_api_scalar(value, default = default)
  slug <- gsub("[^A-Za-z0-9._-]+", "_", slug)
  slug <- gsub("_+", "_", slug)
  slug <- gsub("^_+|_+$", "", slug)
  if (!nzchar(slug)) {
    slug <- default
  }
  if (nchar(slug) > 160L) {
    slug <- substr(slug, 1L, 160L)
  }
  slug
}

query_synergy_precomputed_cache_file <- function(cache_paths, cache_key = "", source = "") {
  source_key <- query_api_scalar(source, default = "catalog")
  if (identical(source_key, "scryfall_oracle_cards")) {
    return(cache_paths$precomputed_rds_file)
  }

  file.path(
    cache_paths$base_dir,
    sprintf("precomputed-%s.rds", query_synergy_cache_key_slug(cache_key, default = source_key))
  )
}

query_synergy_trim_card <- function(card) {
  list(
    id = query_synergy_card_id(card),
    name = query_api_scalar(card$name, default = ""),
    oracle_text = query_api_scalar(card$oracle_text, default = query_api_scalar(card$printed_text, default = "")),
    type_line = query_api_scalar(card$type_line, default = ""),
    mana_cost = query_api_scalar(card$mana_cost, default = ""),
    cmc = suppressWarnings(as.numeric(card$cmc)),
    colors = query_synergy_card_colors(card),
    color_identity = query_synergy_card_color_identity(card),
    keywords = query_synergy_to_vector(card$keywords),
    legalities = query_synergy_card_legalities(card)
  )
}

query_synergy_normalize_card_cached <- function(card, registry = query_synergy_event_registry_default()) {
  card_id <- query_synergy_card_id(card)
  key <- if (nzchar(card_id)) {
    card_id
  } else {
    paste0("name::", tolower(query_api_scalar(card$name, default = "")))
  }

  if (nzchar(key) && exists(key, envir = query_synergy_cache_env$normalized_by_id, inherits = FALSE)) {
    return(get(key, envir = query_synergy_cache_env$normalized_by_id, inherits = FALSE))
  }

  normalized <- query_synergy_normalize_card(card, registry = registry)
  if (nzchar(key)) {
    assign(key, normalized, envir = query_synergy_cache_env$normalized_by_id)
  }
  normalized
}

query_synergy_find_card_by_id_or_name <- function(catalog, lookup) {
  if (!is.list(catalog) || length(catalog) == 0L) {
    return(NULL)
  }

  raw <- trimws(as.character(lookup))
  if (!nzchar(raw)) {
    return(NULL)
  }

  needle <- tolower(raw)

  exact_id <- Filter(function(card) {
    identical(tolower(query_synergy_card_id(card)), needle)
  }, catalog)
  if (length(exact_id) > 0L) {
    return(exact_id[[1]])
  }

  exact_name <- Filter(function(card) {
    identical(tolower(query_api_scalar(card$name, default = "")), needle)
  }, catalog)
  if (length(exact_name) > 0L) {
    return(exact_name[[1]])
  }

  fuzzy_name <- Filter(function(card) {
    grepl(needle, tolower(query_api_scalar(card$name, default = "")), fixed = TRUE)
  }, catalog)
  if (length(fuzzy_name) > 0L) {
    return(fuzzy_name[[1]])
  }

  NULL
}
query_synergy_card_id <- function(card) {
  id <- query_api_scalar(card$id, default = "")
  if (nzchar(id)) {
    return(id)
  }

  oracle_id <- query_api_scalar(card$oracle_id, default = "")
  if (nzchar(oracle_id)) {
    return(oracle_id)
  }

  name <- tolower(query_api_scalar(card$name, default = ""))
  if (!nzchar(name)) {
    return("")
  }

  gsub("[^a-z0-9]+", "_", name)
}

query_synergy_card_colors <- function(card) {
  direct <- query_synergy_to_vector(card$colors)
  direct <- toupper(direct)
  direct <- direct[direct %in% c("W", "U", "B", "R", "G")]
  unique(direct)
}

query_synergy_card_color_identity <- function(card) {
  direct <- query_synergy_to_vector(card$color_identity)
  if (length(direct) == 0L) {
    direct <- query_synergy_card_colors(card)
  }
  direct <- toupper(direct)
  direct <- direct[direct %in% c("W", "U", "B", "R", "G", "C")]
  unique(direct)
}

query_synergy_card_legalities <- function(card) {
  legalities <- card$legalities
  if (!is.list(legalities) || length(legalities) == 0L) {
    return(list())
  }

  out <- list()
  keys <- names(legalities)
  if (length(keys) == 0L) {
    return(out)
  }

  for (key in keys) {
    out[[tolower(key)]] <- tolower(query_api_scalar(legalities[[key]], default = ""))
  }

  out
}

query_synergy_parse_color_identity <- function(value) {
  if (is.null(value)) {
    return(character(0))
  }

  out <- query_synergy_to_vector(value)
  out <- toupper(out)
  out <- out[out %in% c("W", "U", "B", "R", "G", "C")]
  unique(out)
}

query_synergy_to_vector <- function(value) {
  if (is.null(value)) {
    return(character(0))
  }

  flattened <- unlist(value, use.names = FALSE)
  if (length(flattened) == 0L) {
    return(character(0))
  }

  out <- trimws(as.character(flattened))
  out <- out[!is.na(out) & nzchar(out)]
  unique(out)
}

query_synergy_as_int <- function(value, default = 0L, min_value = 0L, max_value = 100L) {
  parsed <- suppressWarnings(as.integer(value))
  if (length(parsed) == 0L || any(!is.finite(parsed)) || any(is.na(parsed))) {
    parsed <- as.integer(default)
  }
  parsed <- max(as.integer(min_value), parsed)
  parsed <- min(as.integer(max_value), parsed)
  as.integer(parsed)
}

query_synergy_color_fit <- function(target_colors, candidate_colors) {
  left <- unique(query_synergy_to_vector(target_colors))
  right <- unique(query_synergy_to_vector(candidate_colors))

  if (length(left) == 0L || length(right) == 0L) {
    return(0.5)
  }

  inter <- intersect(left, right)
  union <- unique(c(left, right))
  jaccard <- if (length(union) == 0L) 0 else length(inter) / length(union)

  if (length(inter) == 0L) {
    return(0.2)
  }

  min(1, 0.65 + 0.35 * jaccard)
}

query_synergy_format_fit <- function(target_legalities, candidate_legalities, format_name = "commander") {
  format_key <- tolower(query_api_scalar(format_name, default = "commander"))
  if (!nzchar(format_key)) {
    return(0.5)
  }

  target_legality <- tolower(query_api_scalar(target_legalities[[format_key]], default = ""))
  candidate_legality <- tolower(query_api_scalar(candidate_legalities[[format_key]], default = ""))

  if (!nzchar(target_legality) || !nzchar(candidate_legality)) {
    return(0.5)
  }

  legal_values <- c("legal", "restricted")
  if (target_legality %in% legal_values && candidate_legality %in% legal_values) {
    return(1)
  }
  if (target_legality %in% legal_values || candidate_legality %in% legal_values) {
    return(0.35)
  }

  0.1
}

query_synergy_tempo_fit <- function(target_mana_value, candidate_mana_value) {
  left <- suppressWarnings(as.numeric(target_mana_value))
  right <- suppressWarnings(as.numeric(candidate_mana_value))
  if (!is.finite(left) || is.na(left) || !is.finite(right) || is.na(right)) {
    return(0.5)
  }

  distance <- abs(left - right)
  max(0, 1 - min(distance, 7) / 7)
}

query_synergy_anti_penalty <- function(target_anti_tags, candidate_anti_tags) {
  left <- unique(query_synergy_to_vector(target_anti_tags))
  right <- unique(query_synergy_to_vector(candidate_anti_tags))

  if (length(left) == 0L || length(right) == 0L) {
    return(0)
  }

  pairs <- list(
    c("HAND_SIZE_PAYOFF", "HAND_DISCARD_PRESSURE"),
    c("GRAVEYARD_DEPENDENT", "GRAVEYARD_HATE")
  )

  penalty <- 0
  for (pair in pairs) {
    if ((pair[[1]] %in% left && pair[[2]] %in% right) || (pair[[2]] %in% left && pair[[1]] %in% right)) {
      penalty <- penalty + 0.5
    }
  }

  min(1, penalty)
}

query_synergy_event_conflict_penalty <- function(conflict_count, step = 0.5) {
  n <- suppressWarnings(as.integer(conflict_count))
  if (!is.finite(n) || is.na(n) || n <= 0L) {
    return(0)
  }

  weight <- suppressWarnings(as.numeric(step))
  if (!is.finite(weight) || is.na(weight) || weight <= 0) {
    weight <- 0.5
  }

  min(1, n * weight)
}

query_synergy_anti_conflicts <- function(target_anti_tags, candidate_anti_tags) {
  left <- unique(query_synergy_to_vector(target_anti_tags))
  right <- unique(query_synergy_to_vector(candidate_anti_tags))
  if (length(left) == 0L || length(right) == 0L) {
    return(list(pairs = character(0), reasons = character(0)))
  }

  pair_map <- list(
    HAND_SIZE_PAYOFF = "HAND_DISCARD_PRESSURE",
    GRAVEYARD_DEPENDENT = "GRAVEYARD_HATE"
  )

  pairs <- character(0)
  reasons <- character(0)
  for (lhs in names(pair_map)) {
    rhs <- pair_map[[lhs]]
    if ((lhs %in% left && rhs %in% right) || (rhs %in% left && lhs %in% right)) {
      pair_id <- sprintf("%s<->%s", lhs, rhs)
      pairs <- c(pairs, pair_id)
      if (identical(pair_id, "HAND_SIZE_PAYOFF<->HAND_DISCARD_PRESSURE")) {
        reasons <- c(reasons, "Plan conflict: hand-size payoff clashes with discard pressure")
      }
      if (identical(pair_id, "GRAVEYARD_DEPENDENT<->GRAVEYARD_HATE")) {
        reasons <- c(reasons, "Plan conflict: graveyard-dependent card clashes with graveyard hate")
      }
    }
  }

  list(
    pairs = unique(pairs),
    reasons = unique(reasons)
  )
}

query_synergy_strategic_incoherence_penalty <- function(produced_to_payoff,
                                                        payoff_to_produced,
                                                        shared_plan,
                                                        setup_finisher) {
  bridge_count <- length(unique(c(
    query_synergy_to_vector(produced_to_payoff),
    query_synergy_to_vector(payoff_to_produced),
    query_synergy_to_vector(setup_finisher)
  )))
  plan_count <- length(unique(query_synergy_to_vector(shared_plan)))

  if (bridge_count == 0L && plan_count == 0L) {
    return(0.7)
  }
  if (bridge_count == 0L && plan_count <= 1L) {
    return(0.35)
  }
  0
}

query_synergy_tempo_mismatch_penalty <- function(tempo_fit, shared_plan) {
  fit <- suppressWarnings(as.numeric(tempo_fit))
  if (!is.finite(fit) || is.na(fit)) {
    return(0)
  }
  if (fit < 0.3 && length(query_synergy_to_vector(shared_plan)) == 0L) {
    return(0.6)
  }
  if (fit < 0.15) {
    return(0.8)
  }
  0
}
