#' @title Open a SQLite connection
#'
#' @param db_path Character scalar. Path to the SQLite database file.
#' @return A `DBIConnection` object.
#' @examples
#' \dontrun{
#'   con <- db_connect("path/to/db.sqlite")
#'   on.exit(db_disconnect(con), add = TRUE)
#' }
#' @export
db_connect <- function(db_path) {
  DBI::dbConnect(RSQLite::SQLite(), dbname = db_path)
}

#' @title Safely close a DBI connection
#'
#' @param con A `DBIConnection` object, or `NULL`.
#' @return Invisibly `NULL`.
#' @examples
#' \dontrun{
#'   db_disconnect(con)
#' }
#' @export
db_disconnect <- function(con) {
  if (!is.null(con) && DBI::dbIsValid(con)) {
    DBI::dbDisconnect(con)
  }
  invisible(NULL)
}

#' @title Open, use, and always-disconnect a SQLite database
#'
#' @description Opens a connection to `db_path`, passes it to `fn`, and
#'   guarantees disconnection via `on.exit` — even if `fn` throws.
#'
#' @param db_path Character scalar. Path to the SQLite database file.
#' @param fn A function accepting a single `DBIConnection` argument.
#' @return The return value of `fn(con)`.
#' @examples
#' \dontrun{
#'   result <- with_db("path/to/db.sqlite", function(con) {
#'     DBI::dbGetQuery(con, "SELECT 1 AS n")
#'   })
#' }
#' @export
with_db <- function(db_path, fn) {
  con <- db_connect(db_path)
  on.exit(db_disconnect(con), add = TRUE)
  fn(con)
}
