# Catalog precompute, profile indexing, on-disk cache for normalized cards.
# Extracted from R/query_synergy_engine.R as part of the modular refactor.
# Depends on: synergy_utils, synergy_normalize, synergy_event_registry

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
      scalable = isTRUE(normalized$cadence$scalable),
      strength = cadence_strength,
      contexts = unique(query_synergy_to_vector(normalized$cadence$contexts))
    ),
    mana_value = suppressWarnings(as.numeric(normalized$mana_value)),
    color_identity = unique(query_synergy_to_vector(normalized$color_identity)),
    legalities = normalized$legalities
  )
}

query_synergy_build_profile_index_map <- function(profiles, selector) {
  items <- query_synergy_to_list(profiles)
  if (length(items) == 0L) return(list())

  keys_per_item <- lapply(items, function(item) {
    vals <- unique(query_synergy_to_vector(selector(item)))
    vapply(vals, function(v) query_api_scalar(v, default = ""), character(1))
  })
  keys_per_item <- lapply(keys_per_item, function(k) k[nzchar(k)])

  key_vec <- unlist(keys_per_item, use.names = FALSE)
  if (length(key_vec) == 0L) return(list())

  idx_vec <- rep(seq_along(items), lengths(keys_per_item))
  lapply(split(idx_vec, key_vec), function(idxs) unique(as.integer(idxs)))
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
  target_specific_tags <- query_synergy_specific_strategy_tags(target$strategy_tags, min_weight = 0.7)
  if (length(target_specific_tags) == 0L) {
    target_specific_tags <- query_synergy_to_vector(target$strategy_tags)
  }
  signal_hits <- c(
    query_synergy_index_lookup(indexes$produced_events, target$consumed_events),
    query_synergy_index_lookup(indexes$produced_events, target$consumed_events),
    query_synergy_index_lookup(indexes$consumed_events, target$produced_events),
    query_synergy_index_lookup(indexes$consumed_events, target$produced_events),
    query_synergy_index_lookup(indexes$produced_families, target$consumed_families),
    query_synergy_index_lookup(indexes$consumed_families, target$produced_families),
    query_synergy_index_lookup(indexes$strategy_tags, target_specific_tags),
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

  # Fast path: the catalog already carries normalized_card_v2 records (set by
  # query_synergy_catalog_normalized_from_sqlite when the enriched SQLite
  # tables match the current precompute_version). Skip the per-card oracle
  # parsing entirely; only the inverted indexes still need to be built.
  catalog_pre_normalized <- isTRUE(attr(catalog, "synergy_normalized"))

  normalized <- vector("list", length(cards))
  profiles <- vector("list", length(cards))
  stride <- max(1L, ceiling(max(1L, length(cards)) / 30L))
  for (i in seq_along(cards)) {
    normalized_card <- if (catalog_pre_normalized &&
        is.list(cards[[i]]) &&
        identical(query_api_scalar(cards[[i]]$model_version, default = ""), "normalized_card_v2")) {
      cards[[i]]
    } else {
      query_synergy_normalize_card_cached(cards[[i]], registry = registry)
    }
    normalized[[i]] <- normalized_card
    profiles[[i]] <- query_synergy_build_compact_profile(normalized_card, registry = registry)
    if (is.function(progress_callback) && (i == 1L || i == length(cards) || (i %% stride) == 0L)) {
      percent <- progress_start + ((i / max(1L, length(cards))) * (progress_end - progress_start))
      label <- if (catalog_pre_normalized) "Indexing precomputed catalog" else "Precomputing normalized catalog"
      query_synergy_emit_progress(progress_callback, percent, label, list(processed = i, total = length(cards)))
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


query_synergy_cache_paths <- function(cache_dir = "") {
  base_dir <- trimws(as.character(cache_dir))
  if (!nzchar(base_dir)) {
    base_dir <- trimws(Sys.getenv("MTGCODEX_SYNERGY_CACHE_DIR", unset = ""))
  }
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


query_synergy_find_card_by_id_or_name <- function(catalog, lookup) {
  if (!is.list(catalog) || length(catalog) == 0L) {
    return(NULL)
  }

  raw <- trimws(as.character(lookup))
  if (!nzchar(raw)) {
    return(NULL)
  }

  needle <- tolower(raw)

  # Reuse cached lowercase id/name vectors keyed on the catalog cache key
  # so we don't rescan the full list on every request. Falls back to a
  # one-shot vapply when no cache key is present.
  cache_key <- attr(catalog, "synergy_cache_key")
  index <- NULL
  if (is.character(cache_key) && nzchar(cache_key)) {
    cached <- query_synergy_cache_env$lookup_index
    if (is.list(cached) && identical(cached$key, cache_key)) {
      index <- cached
    }
  }

  if (is.null(index)) {
    n <- length(catalog)
    ids   <- vapply(catalog, function(card) tolower(query_synergy_card_id(card)),    character(1))
    names_ <- vapply(catalog, function(card) tolower(query_api_scalar(card$name, default = "")), character(1))
    index <- list(key = cache_key, ids = ids, names = names_)
    if (is.character(cache_key) && nzchar(cache_key)) {
      query_synergy_cache_env$lookup_index <- index
    }
  }

  hit <- which(index$ids == needle)
  if (length(hit) > 0L) return(catalog[[hit[[1]]]])

  hit <- which(index$names == needle)
  if (length(hit) > 0L) return(catalog[[hit[[1]]]])

  hit <- which(grepl(needle, index$names, fixed = TRUE))
  if (length(hit) > 0L) return(catalog[[hit[[1]]]])

  NULL
}
