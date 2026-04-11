args <- commandArgs(trailingOnly = TRUE)

card_name <- if (length(args) >= 1L) args[[1L]] else "Entomb"
max_results <- if (length(args) >= 2L) suppressWarnings(as.integer(args[[2L]])) else 12L
top_k <- if (length(args) >= 3L) suppressWarnings(as.integer(args[[3L]])) else 36L
cheap_scan_cap <- if (length(args) >= 4L) suppressWarnings(as.integer(args[[4L]])) else max(384L, top_k * 12L)
package_top_n <- if (length(args) >= 5L) suppressWarnings(as.integer(args[[5L]])) else 8L

if (!is.finite(max_results) || is.na(max_results)) {
  max_results <- 12L
}
if (!is.finite(top_k) || is.na(top_k)) {
  top_k <- 36L
}
if (!is.finite(cheap_scan_cap) || is.na(cheap_scan_cap)) {
  cheap_scan_cap <- max(384L, top_k * 12L)
}
if (!is.finite(package_top_n) || is.na(package_top_n)) {
  package_top_n <- 8L
}

source("R/query_api_common.R")
source("R/query_synergy_engine.R")

cat("stage=get_catalog:start\n")
flush.console()
mark <- proc.time()[["elapsed"]]
catalog_info <- query_synergy_get_catalog()
catalog_elapsed <- round(proc.time()[["elapsed"]] - mark, 1)
cat(sprintf("catalog_elapsed_s=%s\n", catalog_elapsed))
flush.console()

if (!isTRUE(catalog_info$ok)) {
  stop(catalog_info$error)
}

cat("stage=query:start\n")
flush.console()
mark <- proc.time()[["elapsed"]]
result <- query_synergy_find_in_catalog(
  list(
    card_name = card_name,
    format = "commander",
    max_results = max_results,
    top_k = top_k,
    cheap_scan_cap = cheap_scan_cap,
    package_top_n = package_top_n
  ),
  catalog_info$cards
)
query_elapsed <- round(proc.time()[["elapsed"]] - mark, 1)

if (!isTRUE(result$ok)) {
  stop(query_api_scalar(result$error, default = "query failed"))
}

top_names <- if (length(result$best_matches) > 0L) {
  paste(vapply(utils::head(result$best_matches, 5L), function(entry) entry$name, character(1)), collapse = ", ")
} else {
  ""
}

cat(sprintf("card=%s\n", result$card))
cat(sprintf("query_elapsed_s=%s\n", query_elapsed))
cat(sprintf("candidate_filter_count=%s\n", result$pipeline$candidate_filter_count))
cat(sprintf("cheap_scan_count=%s\n", result$pipeline$cheap_scan_count))
cat(sprintf("cheap_scan_cap_used=%s\n", query_api_scalar(result$pipeline$cheap_scan_cap_used, default = 0L)))
cat(sprintf("deep_score_count=%s\n", result$pipeline$deep_score_count))
cat(sprintf("package_candidate_count=%s\n", result$pipeline$package_candidate_count))
cat(sprintf("timings=%s\n", paste(names(result$timings), unlist(result$timings), collapse = " | ")))
cat(sprintf("top=%s\n", top_names))
flush.console()