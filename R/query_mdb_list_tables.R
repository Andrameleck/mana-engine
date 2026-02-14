query_mdb_list_tables <- function() {
  status <- query_mdb_status()

  if (!isTRUE(status$mdb_exists)) {
    return(list(
      ok = FALSE,
      error = "Database file not found. Set MTGCODEX_DB_PATH."
    ))
  }

  if (!isTRUE(status$tools_ready)) {
    return(list(
      ok = FALSE,
      error = "Database dependencies missing (DBI/RSQLite)."
    ))
  }

  con <- NULL
  tables <- tryCatch(
    {
      con <- query_db_connect(status$mdb_path)
      DBI::dbListTables(con)
    },
    error = function(e) {
      return(list(.error = e$message))
    },
    finally = {
      query_db_disconnect(con)
    }
  )

  if (is.list(tables) && !is.null(tables$.error)) {
    return(list(ok = FALSE, error = tables$.error))
  }

  list(
    ok = TRUE,
    data = sort(tables)
  )
}
