#!/usr/bin/env Rscript
# Find synergies for a card.
#
# Two ways to run:
#
# 1) From a shell:
#      Rscript dev/scritp/find-synergy.R "Entomb"
#      Rscript dev/scritp/find-synergy.R "Sun Titan" commander 15
#
# 2) From an R session (RStudio / VS Code / R console), edit the variables
#    in the CONFIG block below and `source()` this file:
#      source("dev/scritp/find-synergy.R")
#    Then inspect `res$matches` and `res$packages`.

suppressMessages(devtools::load_all(".", quiet = TRUE))

# ---------------------------------------------------------------------------
# CONFIG (used when running interactively / via source())
# ---------------------------------------------------------------------------
card_name   <- "Entomb"
fmt         <- "commander"
max_results <- 10L

# ---------------------------------------------------------------------------
# Override CONFIG with command-line args when run via Rscript.
# ---------------------------------------------------------------------------
.args <- commandArgs(trailingOnly = TRUE)
if (length(.args) >= 1L && nzchar(.args[[1]])) card_name <- .args[[1]]
if (length(.args) >= 2L && nzchar(.args[[2]])) fmt         <- .args[[2]]
if (length(.args) >= 3L) {
  .n <- suppressWarnings(as.integer(.args[[3]]))
  if (!is.na(.n) && .n > 0L) max_results <- .n
}

cat(sprintf("Seed       : %s\n", card_name))
cat(sprintf("Format     : %s\n", fmt))
cat(sprintf("Max results: %d\n\n", max_results))

res <- query_synergy_find_by_name(
  card_name     = card_name,
  format        = fmt,
  max_results   = max_results,
  package_top_n = 6L
)

if (!isTRUE(res$ok)) {
  message("ERROR: ", res$error %||% "(unknown)")
} else {
  cat(sprintf("Catalog: %d cards (source=%s)\n", res$catalog_size, res$source %||% "?"))
  cat(sprintf("Scored in %.2fs\n", res$elapsed_s))
  seed_name <- res$seed[["name"]] %||% card_name
  if (nzchar(seed_name)) cat(sprintf("Resolved seed: %s\n", seed_name))

  if (nrow(res$matches) == 0L) {
    cat("\n(no synergy matches found)\n")
  } else {
    cat(sprintf("\n=== Top %d synergies ===\n", nrow(res$matches)))
    print(res$matches, row.names = FALSE, right = FALSE)
    if (nrow(res$packages) > 0L) {
      cat(sprintf("\n=== Packages (%d) ===\n", nrow(res$packages)))
      print(res$packages, row.names = FALSE, right = FALSE)
    }
  }
}

# `res` is left in the global env when sourced, so callers can inspect:
#   res$matches; res$packages
invisible(res)
