suppressMessages(devtools::load_all(".", quiet = TRUE))

cat("stage=get_catalog:start\n"); flush.console()
mark <- proc.time()[["elapsed"]]
res <- query_synergy_catalog_from_sqlite(where = "lang = 'en'", limit = 5000L)
catalog_elapsed <- round(proc.time()[["elapsed"]] - mark, 2)
cat(sprintf("catalog_load_s=%s n=%d\n", catalog_elapsed, length(res))); flush.console()

cat("stage=query:start\n"); flush.console()
mark <- proc.time()[["elapsed"]]
out <- query_synergy_find_in_catalog(
  list(card_name = "Entomb", format = "commander",
       max_results = 12L, top_k = 36L,
       cheap_scan_cap = 1200L, package_top_n = 8L),
  res
)
query_elapsed <- round(proc.time()[["elapsed"]] - mark, 2)
cat(sprintf("query_s=%s ok=%s\n", query_elapsed, isTRUE(out$ok))); flush.console()

if (isTRUE(out$ok)) {
  cat(sprintf("candidate_filter=%s cheap_scan=%s deep=%s pkg=%s\n",
              out$pipeline$candidate_filter_count,
              out$pipeline$cheap_scan_count,
              out$pipeline$deep_score_count,
              out$pipeline$package_candidate_count))
  cat("timings:\n")
  for (nm in names(out$timings)) {
    cat(sprintf("  %s = %s\n", nm, out$timings[[nm]]))
  }
}

# Profile second pass with Rprof
Rprof_out <- tempfile(fileext = ".out")
Rprof(Rprof_out, interval = 0.01, line.profiling = TRUE)
out2 <- query_synergy_find_in_catalog(
  list(card_name = "Sheoldred, the Apocalypse", format = "commander",
       max_results = 12L, top_k = 36L,
       cheap_scan_cap = 1200L, package_top_n = 8L),
  res
)
Rprof(NULL)
cat("\n=== Rprof summary (top 15 by self.time) ===\n")
sm <- summaryRprof(Rprof_out)
print(utils::head(sm$by.self, 15))
cat("\n=== top 10 by total.time ===\n")
print(utils::head(sm$by.total, 10))
