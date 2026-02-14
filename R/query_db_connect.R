query_db_connect <- function(db_path) {
  DBI::dbConnect(RSQLite::SQLite(), dbname = db_path)
}
