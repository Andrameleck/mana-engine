internal <- function(name) {
  if ("mtgcodex.api" %in% loadedNamespaces()) getFromNamespace(name, "mtgcodex.api") else get(name, envir = .GlobalEnv)
}

test_that("source paths are confined to configured directories", {
  allowed_dir <- tempfile("allowed-")
  outside_dir <- tempfile("outside-")
  dir.create(allowed_dir)
  dir.create(outside_dir)
  on.exit(unlink(c(allowed_dir, outside_dir), recursive = TRUE), add = TRUE)

  allowed_file <- file.path(allowed_dir, "collection.csv")
  outside_file <- file.path(outside_dir, "private.txt")
  writeLines("name\nAllowed", allowed_file)
  writeLines("private", outside_file)

  old_value <- Sys.getenv("MTGCODEX_API_ALLOWED_SOURCE_DIRS", unset = NA_character_)
  on.exit({
    if (is.na(old_value)) {
      Sys.unsetenv("MTGCODEX_API_ALLOWED_SOURCE_DIRS")
    } else {
      Sys.setenv(MTGCODEX_API_ALLOWED_SOURCE_DIRS = old_value)
    }
  }, add = TRUE)
  Sys.setenv(MTGCODEX_API_ALLOWED_SOURCE_DIRS = allowed_dir)

  resolve <- internal("query_api_resolve_source_path")
  expect_true(resolve(allowed_file)$ok)
  expect_false(resolve(outside_file)$ok)
  expect_match(resolve(outside_file)$error, "outside configured")
})
