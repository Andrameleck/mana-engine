test_that("feedback submissions are persisted and can be listed", {
  project_orig <- Sys.getenv("MANA_ENGINE_API_PROJECT_DIR", unset = NA_character_)
  token_orig <- Sys.getenv("FEEDBACK_ADMIN_TOKEN", unset = NA_character_)
  on.exit({
    if (is.na(project_orig)) Sys.unsetenv("MANA_ENGINE_API_PROJECT_DIR") else Sys.setenv(MANA_ENGINE_API_PROJECT_DIR = project_orig)
    if (is.na(token_orig)) Sys.unsetenv("FEEDBACK_ADMIN_TOKEN") else Sys.setenv(FEEDBACK_ADMIN_TOKEN = token_orig)
  }, add = TRUE)

  Sys.unsetenv("FEEDBACK_ADMIN_TOKEN")

  tmp_root <- tempfile("feedback-root-")
  dir.create(file.path(tmp_root, "inst", "feedback"), recursive = TRUE, showWarnings = FALSE)
  Sys.setenv(MANA_ENGINE_API_PROJECT_DIR = tmp_root)
  on.exit(unlink(tmp_root, recursive = TRUE, force = TRUE), add = TRUE)

  first <- mtgcodex.api:::query_feedback_submit(
    type = "bug",
    message = "First feedback",
    email = "",
    client_id = "client-a"
  )
  second <- mtgcodex.api:::query_feedback_submit(
    type = "suggestion",
    message = "Second feedback",
    email = "dev@example.com",
    client_id = "client-b"
  )

  expect_true(isTRUE(first$ok))
  expect_true(isTRUE(second$ok))

  listed <- mtgcodex.api:::query_feedback_list(limit = "10")
  expect_true(isTRUE(listed$ok))
  expect_equal(listed$count, 2L)
  expect_length(listed$items, 2L)
  expect_equal(vapply(listed$items, function(x) x$message, character(1)), c("Second feedback", "First feedback"))

  only_bug <- mtgcodex.api:::query_feedback_list(limit = "10", type = "bug")
  expect_true(isTRUE(only_bug$ok))
  expect_equal(only_bug$count, 1L)
  expect_equal(only_bug$items[[1]]$type, "bug")
})

test_that("feedback list requires token when FEEDBACK_ADMIN_TOKEN is set", {
  project_orig <- Sys.getenv("MANA_ENGINE_API_PROJECT_DIR", unset = NA_character_)
  token_orig <- Sys.getenv("FEEDBACK_ADMIN_TOKEN", unset = NA_character_)
  on.exit({
    if (is.na(project_orig)) Sys.unsetenv("MANA_ENGINE_API_PROJECT_DIR") else Sys.setenv(MANA_ENGINE_API_PROJECT_DIR = project_orig)
    if (is.na(token_orig)) Sys.unsetenv("FEEDBACK_ADMIN_TOKEN") else Sys.setenv(FEEDBACK_ADMIN_TOKEN = token_orig)
  }, add = TRUE)

  tmp_root <- tempfile("feedback-root-")
  dir.create(file.path(tmp_root, "inst", "feedback"), recursive = TRUE, showWarnings = FALSE)
  Sys.setenv(MANA_ENGINE_API_PROJECT_DIR = tmp_root)
  Sys.setenv(FEEDBACK_ADMIN_TOKEN = "secret-token")
  on.exit(unlink(tmp_root, recursive = TRUE, force = TRUE), add = TRUE)

  mtgcodex.api:::query_feedback_submit(
    type = "other",
    message = "Protected feedback",
    email = "",
    client_id = "client-a"
  )

  denied <- mtgcodex.api:::query_feedback_list(limit = "10", token = "wrong")
  expect_false(isTRUE(denied$ok))
  denied_error <- if (!is.null(denied$error)) as.character(denied$error) else ""
  expect_match(denied_error, "Unauthorized", fixed = TRUE)

  allowed <- mtgcodex.api:::query_feedback_list(limit = "10", token = "secret-token")
  expect_true(isTRUE(allowed$ok))
  expect_equal(allowed$count, 1L)
})