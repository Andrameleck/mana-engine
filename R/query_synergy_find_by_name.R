#' Find synergies for a card by name
#'
#' Convenience wrapper around `query_synergy_find_in_catalog()` that loads the
#' default catalog (sqlite-backed) on first call, runs the synergy pipeline for
#' the requested seed card, and returns the result as tidy data.frames suitable
#' for inspection in the R console or further processing.
#'
#' @param card_name Character scalar. Name of the seed card.
#' @param format Character scalar. Format used for legality / format-fit axis
#'   (default `"commander"`).
#' @param max_results Integer. Number of best matches to return (default `10`).
#' @param package_top_n Integer. Number of packages to return (default `6`).
#' @param top_k Integer. Internal candidate cap forwarded to the engine
#'   (default `max(24, max_results * 3)`).
#' @param cheap_scan_cap Integer. Cheap pre-filter cap forwarded to the engine
#'   (default `1500`).
#' @param cards Optional pre-loaded catalog (list of normalized cards). When
#'   `NULL` (default) the function calls `query_synergy_get_catalog()`.
#'
#' @return A list with the following entries:
#'   \describe{
#'     \item{`ok`}{Logical scalar.}
#'     \item{`seed`}{Named character vector: `name`, `id`.}
#'     \item{`source`}{Catalog source label (e.g. `"sqlite_cards"`).}
#'     \item{`catalog_size`}{Integer.}
#'     \item{`elapsed_s`}{Numeric, seconds spent scoring.}
#'     \item{`matches`}{Data.frame with columns `rank`, `name`, `score`,
#'       `reasons` (semicolon-joined character).}
#'     \item{`packages`}{Data.frame with columns `rank`, `score`, `members`
#'       (` + `-joined character).}
#'   }
#'   On error returns `list(ok = FALSE, error = <message>)`.
#'
#' @examples
#' \dontrun{
#' res <- query_synergy_find_by_name("Entomb")
#' res$matches
#' res$packages
#' }
#' @export
query_synergy_find_by_name <- function(card_name,
                                       format = "commander",
                                       max_results = 10L,
                                       package_top_n = 6L,
                                       top_k = NULL,
                                       cheap_scan_cap = 1500L,
                                       cards = NULL) {
  if (!is.character(card_name) || length(card_name) != 1L || !nzchar(card_name)) {
    return(list(ok = FALSE, error = "card_name must be a non-empty character scalar"))
  }
  max_results   <- as.integer(max_results)
  package_top_n <- as.integer(package_top_n)
  if (is.null(top_k)) top_k <- max(24L, max_results * 3L)
  top_k <- as.integer(top_k)
  cheap_scan_cap <- as.integer(cheap_scan_cap)

  source_label <- NA_character_
  if (is.null(cards)) {
    cat <- query_synergy_get_catalog()
    if (!isTRUE(cat$ok)) {
      return(list(ok = FALSE, error = paste0("catalog load failed: ", cat$error %||% "unknown")))
    }
    cards <- cat$cards
    source_label <- cat$source %||% NA_character_
  }

  t0 <- proc.time()[["elapsed"]]
  res <- query_synergy_find_in_catalog(
    list(
      card_name      = card_name,
      format         = format,
      max_results    = max_results,
      top_k          = top_k,
      cheap_scan_cap = cheap_scan_cap,
      package_top_n  = package_top_n
    ),
    cards
  )
  elapsed <- proc.time()[["elapsed"]] - t0

  if (!isTRUE(res$ok)) {
    return(list(ok = FALSE, error = res$error %||% "engine returned ok=FALSE"))
  }

  matches_df  <- .synergy_matches_to_df(res$best_matches %||% list())
  packages_df <- .synergy_packages_to_df(res$packages %||% list())

  seed <- res$seed %||% list()
  seed_vec <- c(
    name = as.character(seed$name %||% card_name),
    id   = as.character(seed$id   %||% seed$scryfall_id %||% NA_character_)
  )

  list(
    ok           = TRUE,
    seed         = seed_vec,
    source       = source_label,
    catalog_size = length(cards),
    elapsed_s    = round(elapsed, 3),
    matches      = matches_df,
    packages     = packages_df
  )
}

# Internal: convert best_matches list -> data.frame.
.synergy_matches_to_df <- function(matches) {
  if (length(matches) == 0L) {
    return(data.frame(
      rank    = integer(0),
      name    = character(0),
      score   = numeric(0),
      reasons = character(0),
      stringsAsFactors = FALSE
    ))
  }
  rows <- lapply(seq_along(matches), function(i) {
    e <- matches[[i]]
    reasons <- e$reasons %||% e$why %||% character(0)
    if (is.list(reasons)) {
      reasons <- vapply(reasons, function(r) {
        if (is.list(r)) as.character(r$text %||% r$reason %||% "") else as.character(r)
      }, character(1))
    }
    reasons <- reasons[nzchar(reasons)]
    data.frame(
      rank    = i,
      name    = as.character(e$name %||% NA_character_),
      score   = suppressWarnings(as.numeric(e$score %||% e$total %||% NA)),
      reasons = paste(reasons, collapse = "; "),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

# Internal: convert packages list -> data.frame.
.synergy_packages_to_df <- function(packages) {
  if (length(packages) == 0L) {
    return(data.frame(
      rank    = integer(0),
      score   = numeric(0),
      size    = integer(0),
      members = character(0),
      stringsAsFactors = FALSE
    ))
  }
  rows <- lapply(seq_along(packages), function(i) {
    p <- packages[[i]]
    members <- p$members %||% p$cards %||% character(0)
    if (is.list(members)) {
      members <- vapply(members, function(m) as.character(m$name %||% m), character(1))
    }
    data.frame(
      rank    = i,
      score   = suppressWarnings(as.numeric(p$score %||% p$total %||% NA)),
      size    = length(members),
      members = paste(members, collapse = " + "),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}
