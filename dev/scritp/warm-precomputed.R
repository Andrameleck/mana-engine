suppressMessages(devtools::load_all(".", quiet = TRUE))
cat("loading catalog (cached)...\n"); flush.console()
t0 <- proc.time()[["elapsed"]]
res <- query_synergy_get_catalog()
cat(sprintf("catalog: %d cards in %.1fs\n",
            length(res$cards), proc.time()[["elapsed"]] - t0)); flush.console()

cat("\nbuilding precomputed catalog (one-time normalisation of all cards)...\n"); flush.console()
t1 <- proc.time()[["elapsed"]]
pre <- query_synergy_get_precomputed_catalog(res$cards)
cat(sprintf("precomputed: %d profiles in %.1fs\n",
            length(pre$profiles), proc.time()[["elapsed"]] - t1))
