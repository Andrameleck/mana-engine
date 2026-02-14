query_mdb_status <- function() {
  db_path <- query_mdb_path()
  has_db_deps <- requireNamespace("DBI", quietly = TRUE) &&
    requireNamespace("RSQLite", quietly = TRUE)
  dbi_version <- if (requireNamespace("DBI", quietly = TRUE)) {
    as.character(utils::packageVersion("DBI"))
  } else {
    ""
  }
  rsqlite_version <- if (requireNamespace("RSQLite", quietly = TRUE)) {
    as.character(utils::packageVersion("RSQLite"))
  } else {
    ""
  }

  list(
    ok = TRUE,
    db_type = "sqlite",
    mdb_path = db_path,
    mdb_exists = file.exists(db_path),
    tools = list(
      DBI = dbi_version,
      RSQLite = rsqlite_version
    ),
    tools_ready = isTRUE(has_db_deps)
  )
}
