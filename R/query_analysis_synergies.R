query_analysis_synergies <- function(payload) {
  if (is.null(payload) || !is.list(payload)) {
    return(query_api_error("JSON body must be an object", status = 400L))
  }

  out <- tryCatch({
    context_in <- payload$context %||% list()
    context <- do.call(analysis_context, list(
      format = context_in$format %||% "",
      rules_version = context_in$rules_version %||% "",
      allowed_colors = context_in$allowed_colors,
      mode = context_in$mode %||% "explore",
      objective = context_in$objective %||% "",
      inventory = context_in$inventory
    ))
    analyze_functional_synergies(
      seed = payload$seed,
      candidates = payload$candidates %||% list(),
      context = context,
      limit = payload$limit %||% 20L
    )
  }, error = function(e) query_api_error(e$message, status = 400L))
  out
}

query_analysis_groups <- function(payload) {
  if (is.null(payload) || !is.list(payload)) {
    return(query_api_error("JSON body must be an object", status = 400L))
  }
  tryCatch({
    context_in <- payload$context %||% list()
    context <- do.call(analysis_context, list(
      format = context_in$format %||% "",
      rules_version = context_in$rules_version %||% "",
      allowed_colors = context_in$allowed_colors,
      mode = context_in$mode %||% "explore",
      objective = context_in$objective %||% "",
      inventory = context_in$inventory
    ))
    analyze_functional_groups(
      cards = payload$cards %||% list(), context = context,
      limit = payload$limit %||% 20L,
      max_pair_evaluations = payload$max_pair_evaluations %||% 10000L
    )
  }, error = function(e) query_api_error(e$message, status = 400L))
}

query_analysis_engines <- function(payload) {
  if (is.null(payload) || !is.list(payload)) {
    return(query_api_error("JSON body must be an object", status = 400L))
  }
  tryCatch({
    context_in <- payload$context %||% list()
    context <- do.call(analysis_context, list(
      format = context_in$format %||% "",
      rules_version = context_in$rules_version %||% "",
      allowed_colors = context_in$allowed_colors,
      mode = context_in$mode %||% "explore",
      objective = context_in$objective %||% "",
      inventory = context_in$inventory
    ))
    discover_strategy_engines(
      cards = payload$cards %||% list(), context = context,
      limit = payload$limit %||% 20L,
      max_pair_evaluations = payload$max_pair_evaluations %||% 50000L
    )
  }, error = function(e) query_api_error(e$message, status = 400L))
}

query_api_apply_status <- function(out, res) {
  if (!is.null(res) && is.list(out) && !isTRUE(out$ok)) {
    status <- suppressWarnings(as.integer(out$status %||% 500L))
    res$status <- if (length(status) == 1L && is.finite(status)) status else 500L
  }
  if (is.list(out)) out$status <- NULL
  out
}
