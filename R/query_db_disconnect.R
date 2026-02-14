query_db_disconnect <- function(con) {
  if (!is.null(con) && DBI::dbIsValid(con)) {
    DBI::dbDisconnect(con)
  }
}
