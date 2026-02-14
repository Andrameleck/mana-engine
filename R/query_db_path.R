query_db_path <- function() {
  env_path <- Sys.getenv("MTGCODEX_DB_PATH", unset = "")
  if (nzchar(env_path)) {
    return(normalizePath(env_path, winslash = "/", mustWork = FALSE))
  }

  legacy_env_path <- Sys.getenv("MTGCODEX_MDB_PATH", unset = "")
  if (nzchar(legacy_env_path)) {
    return(normalizePath(legacy_env_path, winslash = "/", mustWork = FALSE))
  }

  installed_path <- system.file("collection", "mtg.db", package = "MTGCODEX")
  if (nzchar(installed_path)) {
    return(normalizePath(installed_path, winslash = "/", mustWork = FALSE))
  }

  normalizePath(
    file.path(getwd(), "inst", "collection", "mtg.db"),
    winslash = "/",
    mustWork = FALSE
  )
}
