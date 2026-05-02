# scripts/download-scryfall-library.R
# Download the Scryfall `oracle_cards` bulk data and store it as a local SQLite
# database at inst/collection/library_scryfall.sqlite.
#
# Usage (from repo root):
#   Rscript scripts/download-scryfall-library.R
#
# Options (env vars):
#   SCRYFALL_BULK_TYPE   default "oracle_cards"
#                        (also: "default_cards", "unique_artwork",
#                         "all_cards", "rulings")
#   SCRYFALL_DB_PATH     output sqlite path (default inst/collection/library_scryfall.sqlite)

suppressPackageStartupMessages({
  library(jsonlite)
  library(DBI)
  library(RSQLite)
})

bulk_type <- Sys.getenv("SCRYFALL_BULK_TYPE", unset = "oracle_cards")
db_path   <- Sys.getenv(
  "SCRYFALL_DB_PATH",
  unset = file.path("inst", "collection", "library_scryfall.sqlite")
)

dir.create(dirname(db_path), recursive = TRUE, showWarnings = FALSE)

message("[scryfall] querying bulk-data index ...")
bulk <- jsonlite::fromJSON("https://api.scryfall.com/bulk-data")
entry <- bulk$data[bulk$data$type == bulk_type, ]
if (nrow(entry) != 1L) {
  stop("Scryfall bulk type not found: ", bulk_type)
}

size_mb <- round(entry$size / 1024 / 1024, 1)
message(sprintf(
  "[scryfall] type=%s  size=%.1f MB  updated_at=%s",
  entry$type, size_mb, entry$updated_at
))
message("[scryfall] download_uri: ", entry$download_uri)

tmp <- tempfile(fileext = ".json")
on.exit(unlink(tmp), add = TRUE)

message("[scryfall] downloading ...")
utils::download.file(entry$download_uri, tmp, mode = "wb", quiet = FALSE)

message("[scryfall] parsing JSON ...")
cards <- jsonlite::fromJSON(tmp, flatten = TRUE, simplifyDataFrame = TRUE)
message(sprintf("[scryfall] parsed %d card rows / %d columns",
                nrow(cards), ncol(cards)))

# Flatten list-columns (arrays / nested objects) to JSON text so they survive
# the SQLite round-trip without losing information.
list_cols <- names(cards)[vapply(cards, is.list, logical(1))]
if (length(list_cols)) {
  message("[scryfall] serialising ", length(list_cols),
          " list-columns to JSON: ",
          paste(list_cols, collapse = ", "))
  for (col in list_cols) {
    cards[[col]] <- vapply(
      cards[[col]],
      function(x) {
        if (is.null(x) || (length(x) == 1L && is.na(x[[1]]))) NA_character_
        else jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", na = "null")
      },
      character(1)
    )
  }
}

message("[scryfall] writing SQLite -> ", db_path)
if (file.exists(db_path)) {
  file.copy(db_path, paste0(db_path, ".bak"), overwrite = TRUE)
  message("[scryfall] previous DB backed up to ", db_path, ".bak")
}

con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
on.exit(DBI::dbDisconnect(con), add = TRUE)

DBI::dbExecute(con, "PRAGMA journal_mode = WAL;")
DBI::dbExecute(con, "PRAGMA synchronous = NORMAL;")

DBI::dbWriteTable(con, "cards", cards, overwrite = TRUE)

# Useful indexes for lookup-heavy workloads.
mk_index <- function(name, sql) {
  tryCatch(DBI::dbExecute(con, sql),
           error = function(e) message("  [warn] index ", name, ": ", conditionMessage(e)))
}
mk_index("name",      "CREATE INDEX IF NOT EXISTS idx_cards_name      ON cards(name);")
mk_index("oracle_id", "CREATE INDEX IF NOT EXISTS idx_cards_oracle_id ON cards(oracle_id);")
mk_index("set",       "CREATE INDEX IF NOT EXISTS idx_cards_set       ON cards(\"set\");")
mk_index("type_line", "CREATE INDEX IF NOT EXISTS idx_cards_type_line ON cards(type_line);")

# Metadata table so consumers know exactly what bulk snapshot is loaded.
meta <- data.frame(
  bulk_type    = entry$type,
  bulk_id      = entry$id,
  updated_at   = entry$updated_at,
  download_uri = entry$download_uri,
  size_bytes   = as.numeric(entry$size),
  row_count    = nrow(cards),
  fetched_at   = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  stringsAsFactors = FALSE
)
DBI::dbWriteTable(con, "scryfall_meta", meta, overwrite = TRUE)

DBI::dbExecute(con, "VACUUM;")

message(sprintf(
  "[scryfall] done. %d rows in `cards` -> %s (%.1f MB on disk)",
  nrow(cards), db_path,
  file.info(db_path)$size / 1024 / 1024
))
