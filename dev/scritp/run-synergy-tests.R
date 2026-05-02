Sys.setenv(NOT_CRAN = "true")
suppressMessages(devtools::load_all(".", quiet = TRUE))
testthat::set_max_fails(999L)
res <- testthat::test_dir(
  "tests/testthat",
  reporter = testthat::SilentReporter$new(),
  stop_on_failure = FALSE
)
df <- as.data.frame(res)
fails <- df[df$failed > 0 | df$error, c("file", "test", "failed", "error")]
cat("\n=== FAILED TESTS ===\n")
print(fails, row.names = FALSE)
cat(sprintf("\nTotal failed=%d errors=%d ok=%d nb=%d\n",
            sum(df$failed), sum(df$error), sum(df$nb) - sum(df$failed), sum(df$nb)))
