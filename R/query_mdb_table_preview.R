query_mdb_table_preview <- function(name, limit = 100L) {
  table_name <- trimws(as.character(name))
  if (!nzchar(table_name)) {
    return(list(ok = FALSE, error = "name is required"))
  }

  row_limit <- suppressWarnings(as.integer(limit))
  if (is.na(row_limit) || row_limit < 1L) {
    row_limit <- 100L
  }
  row_limit <- min(row_limit, 1000L)

  status <- query_mdb_status()
  if (!isTRUE(status$mdb_exists)) {
    return(list(
      ok = FALSE,
      error = "Database file not found. Set mtgcodex.api_DB_PATH."
    ))
  }

  if (!isTRUE(status$tools_ready)) {
    return(list(
      ok = FALSE,
      error = "Database dependencies missing (DBI/RSQLite)."
    ))
  }

  con <- NULL
  rows <- tryCatch(
    {
      con <- query_db_connect(status$mdb_path)
      quoted_table <- DBI::dbQuoteIdentifier(con, table_name)
      sql <- sprintf("SELECT * FROM %s LIMIT %d", as.character(quoted_table), row_limit)
      DBI::dbGetQuery(con, sql)
    },
    error = function(e) {
      return(list(.error = e$message))
    },
    finally = {
      query_db_disconnect(con)
    }
  )

  if (is.list(rows) && !is.null(rows$.error)) {
    return(list(ok = FALSE, error = rows$.error))
  }

  list(
    ok = TRUE,
    table = table_name,
    limit = row_limit,
    rows = query_db_rows_to_records(rows),
    columns = colnames(rows),
    row_count = nrow(rows)
  )
}
