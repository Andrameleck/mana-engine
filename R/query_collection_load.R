query_collection_load <- function(type, path, table = "") {
  source_type <- tolower(trimws(as.character(type)))
  source_path <- trimws(as.character(path))
  table_name <- trimws(as.character(table))

  if (!source_type %in% c("db", "csv", "text")) {
    return(list(
      ok = FALSE,
      error = "type must be one of: db, csv, text"
    ))
  }

  if (!nzchar(source_path) && identical(source_type, "db")) {
    source_path <- query_collection_default_db_path()
  }

  if (!nzchar(source_path)) {
    return(list(
      ok = FALSE,
      error = "path is required"
    ))
  }

  normalized_path <- normalizePath(source_path, winslash = "/", mustWork = FALSE)
  if (!file.exists(normalized_path)) {
    return(list(
      ok = FALSE,
      error = "file not found",
      path = normalized_path
    ))
  }

  payload <- switch(
    source_type,
    db = query_collection_load_db(
      db_path = normalized_path,
      table_name = table_name
    ),
    csv = query_collection_load_csv(
      csv_path = normalized_path
    ),
    text = query_collection_load_text(
      text_path = normalized_path
    )
  )

  if (!isTRUE(payload$ok)) {
    return(payload)
  }

  payload$source_type <- source_type
  payload$path <- normalized_path
  payload
}

query_collection_default_db_path <- function() {
  installed_path <- system.file("collection", "mtg.db", package = "mtgcodex.api")
  if (nzchar(installed_path) && file.exists(installed_path)) {
    return(installed_path)
  }

  candidates <- c(
    file.path(getwd(), "inst", "collection", "mtg.db"),
    file.path(getwd(), "..", "inst", "collection", "mtg.db")
  )
  existing <- candidates[file.exists(candidates)]
  if (length(existing) > 0L) {
    return(existing[[1]])
  }

  ""
}

query_collection_load_db <- function(db_path, table_name) {
  deps <- query_api_require_db()
  if (!isTRUE(deps)) {
    return(deps)
  }

  con <- NULL
  db_payload <- tryCatch(
    {
      con <- query_db_connect(db_path)
      tables <- DBI::dbListTables(con)
      if (length(tables) == 0L) {
        return(list(
          ok = FALSE,
          error = "database has no tables"
        ))
      }

      selected_table <- query_collection_resolve_table_name(tables, table_name)
      if (!nzchar(selected_table)) {
        return(list(
          ok = FALSE,
          error = "table not found",
          available_tables = sort(as.character(tables))
        ))
      }

      rows <- query_collection_load_db_rows(
        con = con,
        selected_table = selected_table,
        tables = tables
      )

      list(
        ok = TRUE,
        table = selected_table,
        available_tables = sort(as.character(tables)),
        columns = colnames(rows),
        rows = query_db_rows_to_records(rows),
        row_count = nrow(rows)
      )
    },
    error = function(e) {
      list(ok = FALSE, error = e$message)
    },
    finally = {
      query_db_disconnect(con)
    }
  )

  db_payload
}

query_collection_load_db_rows <- function(con, selected_table, tables) {
  quoted_table <- DBI::dbQuoteIdentifier(con, selected_table)
  base_sql <- sprintf("SELECT * FROM %s", as.character(quoted_table))

  selected_lower <- tolower(trimws(as.character(selected_table)))
  if (!identical(selected_lower, "collection")) {
    return(DBI::dbGetQuery(con, base_sql))
  }

  cards_table <- query_collection_find_cards_table_name(tables)
  if (!nzchar(cards_table)) {
    return(DBI::dbGetQuery(con, base_sql))
  }

  collection_fields <- as.character(DBI::dbListFields(con, selected_table))
  if (length(collection_fields) == 0L) {
    return(DBI::dbGetQuery(con, base_sql))
  }

  collection_fields_lower <- tolower(collection_fields)
  scryfall_index <- match("scryfall_id", collection_fields_lower)
  if (is.na(scryfall_index)) {
    return(DBI::dbGetQuery(con, base_sql))
  }

  enrichment_columns <- c("mana_cost", "colors", "color_identity", "type_line", "oracle_text")
  missing_columns <- enrichment_columns[!enrichment_columns %in% collection_fields_lower]
  if (length(missing_columns) == 0L) {
    return(DBI::dbGetQuery(con, base_sql))
  }

  scryfall_column <- collection_fields[[scryfall_index]]
  query_collection_load_collection_rows_with_cards(
    con = con,
    collection_table = selected_table,
    cards_table = cards_table,
    scryfall_column = scryfall_column,
    columns_to_add = missing_columns
  )
}

query_collection_find_cards_table_name <- function(tables) {
  table_values <- as.character(tables)
  if (length(table_values) == 0L) {
    return("")
  }
  lower_tables <- tolower(table_values)
  cards_index <- match("cards", lower_tables)
  if (is.na(cards_index)) {
    return("")
  }
  table_values[[cards_index]]
}

query_collection_load_collection_rows_with_cards <- function(con,
                                                             collection_table,
                                                             cards_table,
                                                             scryfall_column,
                                                             columns_to_add) {
  collection_quoted <- as.character(DBI::dbQuoteIdentifier(con, collection_table))
  cards_quoted <- as.character(DBI::dbQuoteIdentifier(con, cards_table))
  scryfall_quoted <- as.character(DBI::dbQuoteIdentifier(con, scryfall_column))

  add_select <- paste(
    vapply(
      columns_to_add,
      function(col) {
        sprintf("COALESCE(card_data.%s, '') AS %s", col, col)
      },
      character(1)
    ),
    collapse = ",\n       "
  )

  add_agg <- paste(
    vapply(
      columns_to_add,
      function(col) {
        sprintf("MAX(COALESCE(%s, '')) AS %s", col, col)
      },
      character(1)
    ),
    collapse = ",\n         "
  )

  sql <- sprintf(
    paste(
      "SELECT c.*,",
      "       %s",
      "FROM %s AS c",
      "LEFT JOIN (",
      "  SELECT lower(COALESCE(scryfall_id, '')) AS sid,",
      "         %s",
      "  FROM %s",
      "  WHERE COALESCE(scryfall_id, '') <> ''",
      "  GROUP BY lower(COALESCE(scryfall_id, ''))",
      ") AS card_data",
      "ON card_data.sid = lower(COALESCE(c.%s, ''))"
    ),
    add_select,
    collection_quoted,
    add_agg,
    cards_quoted,
    scryfall_quoted
  )

  DBI::dbGetQuery(con, sql)
}

query_collection_resolve_table_name <- function(tables, table_name) {
  table_values <- as.character(tables)
  if (nzchar(table_name)) {
    exact <- table_values[table_values == table_name]
    if (length(exact) > 0L) {
      return(exact[[1]])
    }

    lower_target <- tolower(table_name)
    lower_tables <- tolower(table_values)
    match_index <- match(lower_target, lower_tables)
    if (!is.na(match_index)) {
      return(table_values[[match_index]])
    }

    return("")
  }

  lower_tables <- tolower(table_values)
  cards_index <- match("cards", lower_tables)
  if (!is.na(cards_index)) {
    return(table_values[[cards_index]])
  }

  table_values[[1]]
}

query_collection_load_csv <- function(csv_path) {
  rows <- tryCatch(
    utils::read.csv(
      file = csv_path,
      stringsAsFactors = FALSE,
      check.names = FALSE
    ),
    error = function(e) {
      return(list(.error = e$message))
    }
  )

  if (!is.data.frame(rows) && is.list(rows) && !is.null(rows$.error)) {
    return(list(ok = FALSE, error = rows$.error))
  }

  list(
    ok = TRUE,
    table = basename(csv_path),
    columns = colnames(rows),
    rows = query_db_rows_to_records(rows),
    row_count = nrow(rows)
  )
}

query_collection_load_text <- function(text_path) {
  lines <- tryCatch(
    readLines(text_path, warn = FALSE, encoding = "UTF-8"),
    error = function(e) {
      return(list(.error = e$message))
    }
  )

  if (is.list(lines) && !is.null(lines$.error)) {
    return(list(ok = FALSE, error = lines$.error))
  }

  clean_lines <- gsub("\r$", "", lines)
  non_empty <- clean_lines[nzchar(trimws(clean_lines))]

  if (length(non_empty) == 0L) {
    rows <- data.frame(line = character(0), stringsAsFactors = FALSE)
    return(list(
      ok = TRUE,
      table = basename(text_path),
      columns = colnames(rows),
      rows = list(),
      row_count = 0L
    ))
  }

  separator <- query_collection_guess_separator(non_empty[[1]])
  if (!is.na(separator)) {
    table_payload <- query_collection_read_delimited_text(
      text_lines = non_empty,
      separator = separator
    )

    if (isTRUE(table_payload$ok)) {
      table_payload$table <- basename(text_path)
      return(table_payload)
    }
  }

  rows <- data.frame(
    line = non_empty,
    stringsAsFactors = FALSE
  )

  list(
    ok = TRUE,
    table = basename(text_path),
    columns = colnames(rows),
    rows = query_db_rows_to_records(rows),
    row_count = nrow(rows)
  )
}

query_collection_guess_separator <- function(line) {
  separators <- c("\t", ";", "|", ",")
  counts <- vapply(
    separators,
    function(sep) {
      pieces <- strsplit(line, sep, fixed = TRUE)[[1]]
      length(pieces) - 1L
    },
    integer(1)
  )

  if (all(counts == 0L)) {
    return(NA_character_)
  }

  separators[[which.max(counts)]]
}

query_collection_read_delimited_text <- function(text_lines, separator) {
  con <- textConnection(text_lines)
  on.exit(close(con), add = TRUE)

  rows <- tryCatch(
    utils::read.table(
      file = con,
      sep = separator,
      header = TRUE,
      quote = "\"",
      stringsAsFactors = FALSE,
      check.names = FALSE,
      fill = TRUE,
      comment.char = ""
    ),
    error = function(e) {
      return(list(.error = e$message))
    }
  )

  if (!is.data.frame(rows) && is.list(rows) && !is.null(rows$.error)) {
    return(list(ok = FALSE, error = rows$.error))
  }

  list(
    ok = TRUE,
    columns = colnames(rows),
    rows = query_db_rows_to_records(rows),
    row_count = nrow(rows)
  )
}
