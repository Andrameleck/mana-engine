test_that("db_connect opens a valid SQLite connection", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")

  tmp <- tempfile(fileext = ".sqlite")
  on.exit(unlink(tmp), add = TRUE)

  con <- mtgcodex.api:::db_connect(tmp)
  on.exit(mtgcodex.api:::db_disconnect(con), add = TRUE)

  expect_true(DBI::dbIsValid(con))
})

test_that("db_disconnect closes a valid connection", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")

  tmp <- tempfile(fileext = ".sqlite")
  on.exit(unlink(tmp), add = TRUE)

  con <- mtgcodex.api:::db_connect(tmp)
  expect_true(DBI::dbIsValid(con))
  mtgcodex.api:::db_disconnect(con)
  expect_false(DBI::dbIsValid(con))
})

test_that("db_disconnect handles NULL without error", {
  expect_silent(mtgcodex.api:::db_disconnect(NULL))
})

test_that("with_db passes connection and always disconnects", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")

  tmp <- tempfile(fileext = ".sqlite")
  on.exit(unlink(tmp), add = TRUE)

  captured_con <- NULL
  result <- mtgcodex.api:::with_db(tmp, function(con) {
    captured_con <<- con
    DBI::dbExecute(con, "CREATE TABLE t (x INTEGER)")
    DBI::dbExecute(con, "INSERT INTO t VALUES (42)")
    DBI::dbGetQuery(con, "SELECT x FROM t")$x[[1]]
  })

  expect_equal(result, 42L)
  expect_false(DBI::dbIsValid(captured_con))
})

test_that("with_db disconnects even when fn throws", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")

  tmp <- tempfile(fileext = ".sqlite")
  on.exit(unlink(tmp), add = TRUE)

  captured_con <- NULL
  expect_error(
    mtgcodex.api:::with_db(tmp, function(con) {
      captured_con <<- con
      stop("intentional error")
    }),
    "intentional error"
  )

  expect_false(DBI::dbIsValid(captured_con))
})
