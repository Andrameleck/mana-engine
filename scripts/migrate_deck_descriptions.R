#!/usr/bin/env Rscript
# Migrate deck SQLite databases to ensure they have a description column.
#
# This is a one-time operation that adds the 'description' column to the
# 'decks' table if it doesn't exist. All existing deck downloaders will
# populate this column when metadata is available from the source API.

suppressMessages(devtools::load_all(".", quiet = TRUE))

db_paths <- c(
  file.path("inst", "decks", "archidekt.sqlite"),
  file.path("inst", "decks", "lotusnoir.sqlite"),
  file.path("inst", "decks", "moxfield.sqlite"),
  file.path("inst", "decks", "tappedout.sqlite"),
  file.path("inst", "decks", "spellbook.sqlite")
)

db_paths <- db_paths[file.exists(db_paths)]

if (length(db_paths) == 0L) {
  cat("No deck databases found to migrate.\n")
  quit(status = 0)
}

cat("=== Deck database migration ===\n")
cat(sprintf("Found %d database(s) to check.\n\n", length(db_paths)))

migrated_count <- 0L

for (db_path in db_paths) {
  cat(sprintf("Checking: %s\n", db_path))

  con <- tryCatch(
    DBI::dbConnect(RSQLite::SQLite(), db_path),
    error = function(e) NULL
  )
  if (is.null(con)) {
    cat(sprintf("  ERROR: Cannot connect to %s\n\n", db_path))
    next
  }

  on.exit(try(DBI::dbDisconnect(con), silent = TRUE), add = TRUE)

  # Check if description column exists
  schema <- DBI::dbGetQuery(con, "PRAGMA table_info(decks)")
  has_description <- "description" %in% tolower(schema$name)

  if (has_description) {
    cat("  OK: description column already exists.\n\n")
    next
  }

  # Add description column
  tryCatch({
    DBI::dbExecute(con, "ALTER TABLE decks ADD COLUMN description TEXT")
    cat("  ADDED: description column.\n\n")
    migrated_count <- migrated_count + 1L
  }, error = function(e) {
    cat(sprintf("  ERROR: %s\n\n", conditionMessage(e)))
  })
}

cat(sprintf("Migration complete — %d database(s) updated.\n", migrated_count))
