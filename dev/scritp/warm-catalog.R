suppressMessages(devtools::load_all(".", quiet = TRUE))
cat("warming catalog (one-time normalisation of full sqlite)...\n"); flush.console()
t0 <- proc.time()[["elapsed"]]
res <- query_synergy_get_catalog()
cat(sprintf("ok=%s n=%d source=%s in %.1fs\n",
            isTRUE(res$ok), length(res$cards %||% list()),
            res$source %||% "?", proc.time()[["elapsed"]] - t0))
