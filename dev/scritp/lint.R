suppressMessages({
  if (!requireNamespace("lintr", quietly = TRUE)) stop("lintr not installed")
})

# Light, opinionated config: focus on real bugs/code smells, not style.
linters <- lintr::linters_with_defaults(
  line_length_linter      = NULL,    # we don't care about 80 cols
  object_name_linter      = NULL,    # query_synergy_* convention is snake_case-ish
  cyclocomp_linter        = NULL,    # synergy code has many branches by design
  commented_code_linter   = NULL,
  indentation_linter      = NULL,
  object_length_linter    = NULL,
  object_usage_linter     = NULL     # too noisy with `<<-` / dynamic envs
)

res <- lintr::lint_dir("R", linters = linters)
cat(sprintf("total_issues=%d\n", length(res)))
if (length(res) > 0L) {
  by_linter <- table(vapply(res, function(x) x$linter, character(1)))
  cat("\n=== by linter ===\n")
  print(sort(by_linter, decreasing = TRUE))
  by_file <- table(vapply(res, function(x) basename(x$filename), character(1)))
  cat("\n=== by file ===\n")
  print(sort(by_file, decreasing = TRUE))
  cat("\n=== first 20 issues ===\n")
  for (i in seq_len(min(20L, length(res)))) {
    x <- res[[i]]
    cat(sprintf("%s:%d [%s] %s\n",
                basename(x$filename), x$line_number, x$linter, x$message))
  }
}
