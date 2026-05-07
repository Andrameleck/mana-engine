query_synergy_external_key <- function(value) {
  text <- tolower(trimws(as.character(value)))
  if (!nzchar(text)) {
    return("")
  }
  text <- gsub("[^a-z0-9]+", " ", text)
  trimws(gsub("\\s+", " ", text))
}

query_synergy_external_clamp01 <- function(value) {
  x <- suppressWarnings(as.numeric(value))
  if (length(x) == 0L || !is.finite(x[[1]]) || is.na(x[[1]])) {
    return(0)
  }
  min(1, max(0, x[[1]]))
}

query_synergy_external_name_from_entry <- function(entry) {
  if (is.null(entry)) {
    return("")
  }
  if (is.character(entry) && length(entry) > 0L) {
    return(trimws(as.character(entry[[1]])))
  }
  if (!is.list(entry)) {
    return("")
  }

  query_api_scalar(
    entry$name,
    default = query_api_scalar(
      entry$id,
      default = query_api_scalar(entry$card_name, default = "")
    )
  )
}

query_synergy_external_group_member_names <- function(entry) {
  if (is.null(entry) || !is.list(entry)) {
    return(character(0))
  }

  members <- query_synergy_to_list(entry$members)
  if (length(members) > 0L) {
    return(unique(Filter(nzchar, vapply(members, function(member) {
      query_api_scalar(member$name, default = query_api_scalar(member$id, default = ""))
    }, character(1)))))
  }

  cards <- query_synergy_to_list(entry$cards)
  if (length(cards) > 0L) {
    return(unique(Filter(nzchar, vapply(cards, function(card) {
      query_api_scalar(card$name, default = query_api_scalar(card$id, default = ""))
    }, character(1)))))
  }

  chain_names <- query_synergy_to_vector(entry$chain$member_names)
  if (length(chain_names) > 0L) {
    return(chain_names)
  }

  character(0)
}

query_synergy_spellbook_variant_card_names <- function(variant) {
  if (is.null(variant) || !is.list(variant)) {
    return(character(0))
  }

  uses <- query_synergy_to_list(variant$uses)
  if (length(uses) > 0L) {
    return(unique(Filter(nzchar, vapply(uses, function(entry) {
      query_api_scalar(entry$card$name, default = "")
    }, character(1)))))
  }

  cards <- query_synergy_to_list(variant$cards)
  if (length(cards) > 0L) {
    return(unique(Filter(nzchar, vapply(cards, function(entry) {
      query_api_scalar(entry$name, default = query_api_scalar(entry$card$name, default = ""))
    }, character(1)))))
  }

  query_synergy_to_vector(variant$card_names)
}

query_synergy_lotusnoir_post_text <- function(post) {
  if (is.null(post) || !is.list(post)) {
    return("")
  }

  parts <- c(
    query_api_scalar(post$title, default = ""),
    query_api_scalar(post$snippet, default = ""),
    query_api_scalar(post$content, default = ""),
    query_api_scalar(post$url, default = "")
  )
  trimws(paste(parts[nzchar(parts)], collapse = " "))
}

query_synergy_external_contains_key <- function(text, key) {
  haystack <- paste0(" ", query_synergy_external_key(text), " ")
  needle <- paste0(" ", query_synergy_external_key(key), " ")
  nzchar(needle) && grepl(needle, haystack, fixed = TRUE)
}

query_synergy_external_group_match_counts <- function(seed_key,
                                                      member_keys,
                                                      item_key_sets) {
  required_keys <- unique(Filter(nzchar, c(seed_key, member_keys)))
  if (length(required_keys) == 0L) {
    return(list(
      full_match_refs = 0L,
      partial_match_refs = 0L,
      matched_popularity = 0
    ))
  }

  partial_threshold <- min(length(required_keys), 2L)
  full_refs <- 0L
  partial_refs <- 0L

  for (key_set in item_key_sets) {
    hit_count <- sum(required_keys %in% key_set)
    if (hit_count >= partial_threshold) {
      partial_refs <- partial_refs + 1L
    }
    if (hit_count >= length(required_keys)) {
      full_refs <- full_refs + 1L
    }
  }

  list(
    full_match_refs = as.integer(full_refs),
    partial_match_refs = as.integer(partial_refs)
  )
}

query_synergy_validate_spellbook <- function(seed_name,
                                             entries = list(),
                                             groups = list(),
                                             variants = NULL,
                                             limit = 40L) {
  seed <- query_api_scalar(seed_name, default = "")
  if (!nzchar(seed)) {
    return(query_api_error("seed_name is required", entries = list(), groups = list()))
  }

  payload <- NULL
  if (is.null(variants)) {
    payload <- query_spellbook_variants(q = seed, limit = as.character(limit))
    if (!isTRUE(payload$ok)) {
      return(query_api_error(
        payload$error,
        source = "commander_spellbook",
        entries = list(),
        groups = list()
      ))
    }
    variants <- query_synergy_to_list(payload$results)
  } else {
    variants <- query_synergy_to_list(variants)
  }

  seed_key <- query_synergy_external_key(seed)
  if (!nzchar(seed_key)) {
    return(query_api_error("seed_name normalization failed", entries = list(), groups = list()))
  }

  variant_keys <- lapply(variants, function(variant) {
    unique(vapply(
      query_synergy_spellbook_variant_card_names(variant),
      query_synergy_external_key,
      character(1)
    ))
  })
  keep <- vapply(variant_keys, function(keys) seed_key %in% keys, logical(1))
  variants <- variants[keep]
  variant_keys <- variant_keys[keep]
  variant_count <- length(variants)

  entry_out <- lapply(query_synergy_to_list(entries), function(entry) {
    name <- query_synergy_external_name_from_entry(entry)
    candidate_key <- query_synergy_external_key(name)
    if (!nzchar(candidate_key)) {
      return(NULL)
    }

    refs <- 0L
    popularity_sum <- 0
    for (index in seq_along(variant_keys)) {
      if (!(candidate_key %in% variant_keys[[index]])) {
        next
      }
      refs <- refs + 1L
      popularity_sum <- popularity_sum + query_synergy_as_num(variants[[index]]$popularity, default = 0, min_value = 0)
    }

    ref_ratio <- if (variant_count > 0L) refs / variant_count else 0
    popularity_norm <- if (popularity_sum > 0) {
      min(1, log10(popularity_sum + 1) / 5)
    } else {
      0
    }

    list(
      name = name,
      key = candidate_key,
      score = query_synergy_external_clamp01((ref_ratio * 0.75) + (popularity_norm * 0.25)),
      refs = as.integer(refs),
      variant_count = as.integer(variant_count),
      matched_popularity = round(popularity_sum, 4),
      cooccurs_with_seed = refs > 0L
    )
  })
  entry_out <- Filter(Negate(is.null), entry_out)

  group_out <- lapply(query_synergy_to_list(groups), function(group) {
    member_names <- query_synergy_external_group_member_names(group)
    member_keys <- unique(Filter(function(key) nzchar(key) && !identical(key, seed_key), vapply(
      member_names,
      query_synergy_external_key,
      character(1)
    )))
    if (length(member_keys) == 0L) {
      return(NULL)
    }

    match_counts <- query_synergy_external_group_match_counts(
      seed_key = seed_key,
      member_keys = member_keys,
      item_key_sets = variant_keys
    )
    full_ratio <- if (variant_count > 0L) match_counts$full_match_refs / variant_count else 0
    partial_ratio <- if (variant_count > 0L) match_counts$partial_match_refs / variant_count else 0

    list(
      id = query_api_scalar(group$id, default = paste(member_keys, collapse = "|")),
      score = query_synergy_external_clamp01((full_ratio * 0.7) + (partial_ratio * 0.3)),
      full_match_refs = match_counts$full_match_refs,
      partial_match_refs = match_counts$partial_match_refs,
      variant_count = as.integer(variant_count),
      member_names = member_names
    )
  })
  group_out <- Filter(Negate(is.null), group_out)

  list(
    ok = TRUE,
    source = "commander_spellbook",
    seed = seed,
    variant_count = as.integer(variant_count),
    entries = entry_out,
    groups = group_out
  )
}

query_synergy_validate_lotusnoir <- function(seed_name,
                                             entries = list(),
                                             groups = list(),
                                             posts = NULL,
                                             limit = 120L) {
  seed <- query_api_scalar(seed_name, default = "")
  if (!nzchar(seed)) {
    return(query_api_error("seed_name is required", entries = list(), groups = list()))
  }

  payload <- NULL
  if (is.null(posts)) {
    payload <- query_lotusnoir_posts(q = seed, limit = as.character(limit))
    if (!isTRUE(payload$ok)) {
      return(query_api_error(
        payload$error,
        source = "lotusnoir_wp_search",
        entries = list(),
        groups = list()
      ))
    }
    posts <- query_synergy_to_list(payload$results)
  } else {
    posts <- query_synergy_to_list(posts)
  }

  seed_key <- query_synergy_external_key(seed)
  if (!nzchar(seed_key)) {
    return(query_api_error("seed_name normalization failed", entries = list(), groups = list()))
  }

  post_texts <- vapply(posts, query_synergy_lotusnoir_post_text, character(1))
  keep <- vapply(post_texts, query_synergy_external_contains_key, logical(1), key = seed_key)
  posts <- posts[keep]
  post_texts <- post_texts[keep]
  post_count <- length(post_texts)

  entry_out <- lapply(query_synergy_to_list(entries), function(entry) {
    name <- query_synergy_external_name_from_entry(entry)
    candidate_key <- query_synergy_external_key(name)
    if (!nzchar(candidate_key)) {
      return(NULL)
    }

    refs <- sum(vapply(post_texts, query_synergy_external_contains_key, logical(1), key = candidate_key))
    list(
      name = name,
      key = candidate_key,
      score = query_synergy_external_clamp01(if (post_count > 0L) refs / post_count else 0),
      refs = as.integer(refs),
      post_count = as.integer(post_count),
      cooccurs_with_seed = refs > 0L
    )
  })
  entry_out <- Filter(Negate(is.null), entry_out)

  group_out <- lapply(query_synergy_to_list(groups), function(group) {
    member_names <- query_synergy_external_group_member_names(group)
    member_keys <- unique(Filter(function(key) nzchar(key) && !identical(key, seed_key), vapply(
      member_names,
      query_synergy_external_key,
      character(1)
    )))
    if (length(member_keys) == 0L) {
      return(NULL)
    }

    full_refs <- 0L
    partial_refs <- 0L
    partial_threshold <- min(length(unique(c(seed_key, member_keys))), 2L)
    for (text in post_texts) {
      hit_count <- as.integer(query_synergy_external_contains_key(text, seed_key))
      for (member_key in member_keys) {
        hit_count <- hit_count + as.integer(query_synergy_external_contains_key(text, member_key))
      }
      if (hit_count >= partial_threshold) {
        partial_refs <- partial_refs + 1L
      }
      if (hit_count >= length(unique(c(seed_key, member_keys)))) {
        full_refs <- full_refs + 1L
      }
    }
    list(
      id = query_api_scalar(group$id, default = paste(member_keys, collapse = "|")),
      score = query_synergy_external_clamp01(((if (post_count > 0L) full_refs / post_count else 0) * 0.7) + ((if (post_count > 0L) partial_refs / post_count else 0) * 0.3)),
      full_match_refs = as.integer(full_refs),
      partial_match_refs = as.integer(partial_refs),
      post_count = as.integer(post_count),
      member_names = member_names
    )
  })
  group_out <- Filter(Negate(is.null), group_out)

  list(
    ok = TRUE,
    source = "lotusnoir_wp_search",
    seed = seed,
    post_count = as.integer(post_count),
    entries = entry_out,
    groups = group_out
  )
}

query_synergy_attach_external_validations <- function(result,
                                                      seed_name = "",
                                                      include_spellbook = FALSE,
                                                      include_lotusnoir = FALSE,
                                                      spellbook_variants = NULL,
                                                      lotusnoir_posts = NULL,
                                                      spellbook_limit = 40L,
                                                      lotusnoir_limit = 120L) {
  if (is.null(result) || !is.list(result)) {
    return(list(
      result = result,
      external_validation = list(
        requested = list(
          spellbook = isTRUE(include_spellbook) || is.list(spellbook_variants),
          lotusnoir = isTRUE(include_lotusnoir) || is.list(lotusnoir_posts)
        )
      )
    ))
  }

  seed <- query_api_scalar(seed_name, default = query_api_scalar(result$card, default = ""))
  requested_spellbook <- isTRUE(include_spellbook) || is.list(spellbook_variants)
  requested_lotus <- isTRUE(include_lotusnoir) || is.list(lotusnoir_posts)

  direct_entries <- query_synergy_to_list(result$best_matches)
  group_entries <- unique(unlist(list(
    query_synergy_to_list(result$synergy_groups),
    query_synergy_to_list(result$package_lines),
    query_synergy_to_list(result$packages)
  ), recursive = FALSE), use.names = FALSE)

  spellbook_validation <- if (requested_spellbook) {
    query_synergy_validate_spellbook(
      seed_name = seed,
      entries = direct_entries,
      groups = group_entries,
      variants = spellbook_variants,
      limit = spellbook_limit
    )
  } else {
    NULL
  }

  lotus_validation <- if (requested_lotus) {
    query_synergy_validate_lotusnoir(
      seed_name = seed,
      entries = direct_entries,
      groups = group_entries,
      posts = lotusnoir_posts,
      limit = lotusnoir_limit
    )
  } else {
    NULL
  }

  spellbook_entry_map <- new.env(parent = emptyenv(), hash = TRUE)
  lotus_entry_map <- new.env(parent = emptyenv(), hash = TRUE)
  spellbook_group_map <- new.env(parent = emptyenv(), hash = TRUE)
  lotus_group_map <- new.env(parent = emptyenv(), hash = TRUE)

  for (entry in query_synergy_to_list(spellbook_validation$entries)) {
    assign(query_synergy_external_key(entry$key), entry, envir = spellbook_entry_map)
  }
  for (entry in query_synergy_to_list(lotus_validation$entries)) {
    assign(query_synergy_external_key(entry$key), entry, envir = lotus_entry_map)
  }
  for (entry in query_synergy_to_list(spellbook_validation$groups)) {
    assign(query_api_scalar(entry$id, default = ""), entry, envir = spellbook_group_map)
  }
  for (entry in query_synergy_to_list(lotus_validation$groups)) {
    assign(query_api_scalar(entry$id, default = ""), entry, envir = lotus_group_map)
  }

  annotate_direct_entry <- function(entry) {
    if (!is.list(entry)) {
      return(entry)
    }
    name_key <- query_synergy_external_key(query_synergy_external_name_from_entry(entry))
    spellbook <- if (nzchar(name_key) && exists(name_key, envir = spellbook_entry_map, inherits = FALSE)) {
      get(name_key, envir = spellbook_entry_map, inherits = FALSE)
    } else {
      list(score = 0, refs = 0L, variant_count = 0L, matched_popularity = 0, cooccurs_with_seed = FALSE)
    }
    lotus <- if (nzchar(name_key) && exists(name_key, envir = lotus_entry_map, inherits = FALSE)) {
      get(name_key, envir = lotus_entry_map, inherits = FALSE)
    } else {
      list(score = 0, refs = 0L, post_count = 0L, cooccurs_with_seed = FALSE)
    }

    entry$external_validation <- list(
      spellbook = spellbook,
      lotusnoir = lotus
    )
    entry$provenance_tags <- unique(c(
      "heuristic",
      if (query_synergy_as_int(spellbook$refs, default = 0L, min_value = 0L, max_value = 100000L) > 0L) "spellbook" else character(0),
      if (query_synergy_as_int(lotus$refs, default = 0L, min_value = 0L, max_value = 100000L) > 0L) "lotus_noir" else character(0)
    ))
    entry
  }

  annotate_group_entry <- function(entry) {
    if (!is.list(entry)) {
      return(entry)
    }
    group_id <- query_api_scalar(entry$id, default = "")
    spellbook <- if (nzchar(group_id) && exists(group_id, envir = spellbook_group_map, inherits = FALSE)) {
      get(group_id, envir = spellbook_group_map, inherits = FALSE)
    } else {
      list(score = 0, full_match_refs = 0L, partial_match_refs = 0L, variant_count = 0L)
    }
    lotus <- if (nzchar(group_id) && exists(group_id, envir = lotus_group_map, inherits = FALSE)) {
      get(group_id, envir = lotus_group_map, inherits = FALSE)
    } else {
      list(score = 0, full_match_refs = 0L, partial_match_refs = 0L, post_count = 0L)
    }

    entry$external_validation <- list(
      spellbook = spellbook,
      lotusnoir = lotus
    )
    entry$provenance_tags <- unique(c(
      "heuristic",
      if (query_synergy_as_int(spellbook$partial_match_refs, default = 0L, min_value = 0L, max_value = 100000L) > 0L) "spellbook" else character(0),
      if (query_synergy_as_int(lotus$partial_match_refs, default = 0L, min_value = 0L, max_value = 100000L) > 0L) "lotus_noir" else character(0)
    ))
    entry
  }

  result$best_matches <- lapply(query_synergy_to_list(result$best_matches), annotate_direct_entry)
  result$legacy_best_matches <- lapply(query_synergy_to_list(result$legacy_best_matches), annotate_direct_entry)

  if (is.list(result$buckets)) {
    for (bucket_name in names(result$buckets)) {
      bucket <- result$buckets[[bucket_name]]
      if (!is.list(bucket) || !is.list(bucket$results)) {
        next
      }
      bucket$results <- if (bucket_name %in% c("synergy_groups", "package_lines", "packages")) {
        lapply(query_synergy_to_list(bucket$results), annotate_group_entry)
      } else {
        lapply(query_synergy_to_list(bucket$results), annotate_direct_entry)
      }
      result$buckets[[bucket_name]] <- bucket
    }
  }

  result$synergy_groups <- lapply(query_synergy_to_list(result$synergy_groups), annotate_group_entry)
  result$package_lines <- lapply(query_synergy_to_list(result$package_lines), annotate_group_entry)
  result$packages <- lapply(query_synergy_to_list(result$packages), annotate_group_entry)
  result$external_validation <- list(
    requested = list(
      spellbook = requested_spellbook,
      lotusnoir = requested_lotus
    ),
    spellbook = spellbook_validation,
    lotusnoir = lotus_validation
  )

  list(
    result = result,
    external_validation = result$external_validation
  )
}
