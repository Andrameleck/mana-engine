query_collections_import_csv <- function(req, name = "", platform = "auto", filename = "") {
  deps <- query_api_require_db()
  if (!isTRUE(deps)) {
    return(deps)
  }

  file_info <- query_collection_extract_uploaded_file(req, filename = filename)
  if (!isTRUE(file_info$ok)) {
    return(file_info)
  }

  parsed <- tryCatch(
    query_collections_read_csv_file(file_info$path),
    error = function(e) {
      list(ok = FALSE, error = e$message)
    }
  )
  if (!isTRUE(parsed$ok)) {
    return(parsed)
  }

  normalized <- tryCatch(
    query_collections_normalize_rows(parsed$rows),
    error = function(e) {
      list(ok = FALSE, error = e$message)
    }
  )
  if (!isTRUE(normalized$ok)) {
    return(normalized)
  }

  row_df <- normalized$rows
  if (!is.data.frame(row_df) || nrow(row_df) == 0L) {
    return(list(
      ok = FALSE,
      error = "no valid rows detected in csv"
    ))
  }

  collection_name <- trimws(as.character(name))
  if (!nzchar(collection_name)) {
    collection_name <- tools::file_path_sans_ext(basename(file_info$name))
  }
  if (!nzchar(collection_name)) {
    collection_name <- sprintf("Collection %s", format(Sys.time(), "%Y%m%d-%H%M%S"))
  }

  platform_value <- query_collections_clean_text(platform, fallback = "auto")
  created_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  collection_id <- query_collections_make_id(collection_name)
  store_path <- query_collections_store_path()

  con <- NULL
  out <- tryCatch(
    {
      con <- query_collections_connect(store_path)
      DBI::dbBegin(con)

      DBI::dbExecute(
        con,
        paste(
          "INSERT INTO collections",
          "(collection_id, name, platform, source_file, created_at, row_count)",
          "VALUES (?, ?, ?, ?, ?, ?)"
        ),
        params = list(
          collection_id,
          collection_name,
          platform_value,
          file_info$name,
          created_at,
          as.integer(nrow(row_df))
        )
      )

      row_df$collection_id <- collection_id
      row_df <- row_df[, c(
        "collection_id",
        "row_index",
        "quantity",
        "name",
        "set_code",
        "collector_number",
        "mana_cost",
        "oracle_text",
        "keywords",
        "language",
        "finish",
        "card_condition",
        "scryfall_id",
        "notes"
      )]

      DBI::dbWriteTable(
        con = con,
        name = "collection_cards",
        value = row_df,
        append = TRUE,
        row.names = FALSE
      )

      DBI::dbCommit(con)

      list(
        ok = TRUE,
        collection = list(
          id = collection_id,
          name = collection_name,
          platform = platform_value,
          source_file = file_info$name,
          created_at = created_at,
          row_count = as.integer(nrow(row_df))
        )
      )
    },
    error = function(e) {
      if (!is.null(con) && DBI::dbIsValid(con)) {
        try(DBI::dbRollback(con), silent = TRUE)
      }
      list(
        ok = FALSE,
        error = e$message
      )
    },
    finally = {
      query_db_disconnect(con)
    }
  )

  out
}

query_collections_list <- function() {
  deps <- query_api_require_db()
  if (!isTRUE(deps)) {
    return(deps)
  }

  store_path <- query_collections_store_path()
  if (!file.exists(store_path)) {
    return(list(
      ok = TRUE,
      collections = list(),
      path = store_path
    ))
  }

  con <- NULL
  out <- tryCatch(
    {
      con <- query_collections_connect(store_path)
      rows <- DBI::dbGetQuery(
        con,
        paste(
          "SELECT collection_id AS id, name, platform, source_file, created_at, row_count",
          "FROM collections",
          "ORDER BY datetime(created_at) DESC, name ASC"
        )
      )

      list(
        ok = TRUE,
        collections = query_db_rows_to_records(rows),
        path = store_path
      )
    },
    error = function(e) {
      list(ok = FALSE, error = e$message)
    },
    finally = {
      query_db_disconnect(con)
    }
  )

  out
}

query_collections_get <- function(collection_id = "") {
  deps <- query_api_require_db()
  if (!isTRUE(deps)) {
    return(deps)
  }

  id <- trimws(as.character(collection_id))
  if (!nzchar(id)) {
    return(list(
      ok = FALSE,
      error = "collection_id is required"
    ))
  }

  store_path <- query_collections_store_path()
  if (!file.exists(store_path)) {
    return(list(
      ok = FALSE,
      error = "collections store not initialized",
      path = store_path
    ))
  }

  con <- NULL
  out <- tryCatch(
    {
      con <- query_collections_connect(store_path)

      meta <- DBI::dbGetQuery(
        con,
        paste(
          "SELECT collection_id, name, platform, source_file, created_at, row_count",
          "FROM collections WHERE collection_id = ?"
        ),
        params = list(id)
      )
      if (nrow(meta) == 0L) {
        return(list(
          ok = FALSE,
          error = "collection not found"
        ))
      }

      rows <- DBI::dbGetQuery(
        con,
        paste(
          "SELECT",
          "SUM(COALESCE(quantity, 1)) AS quantity,",
          "name, set_code, collector_number, language,",
          "MAX(COALESCE(mana_cost, '')) AS mana_cost,",
          "MAX(COALESCE(oracle_text, '')) AS oracle_text,",
          "MAX(COALESCE(keywords, '')) AS keywords,",
          "finish, card_condition AS card_condition, scryfall_id, notes",
          "FROM collection_cards",
          "WHERE collection_id = ?",
          "GROUP BY name, set_code, collector_number, language, finish, card_condition, scryfall_id, notes",
          "ORDER BY name ASC, set_code ASC, collector_number ASC"
        ),
        params = list(id)
      )
      rows <- query_collections_enrich_rows(rows)

      list(
        ok = TRUE,
        table = as.character(meta$name[[1]]),
        columns = colnames(rows),
        rows = query_db_rows_to_records(rows),
        row_count = nrow(rows),
        source_type = "collection_store",
        path = store_path,
        collection = query_db_rows_to_records(meta)[[1]]
      )
    },
    error = function(e) {
      list(ok = FALSE, error = e$message)
    },
    finally = {
      query_db_disconnect(con)
    }
  )

  out
}

query_collections_delete <- function(collection_id = "") {
  deps <- query_api_require_db()
  if (!isTRUE(deps)) {
    return(deps)
  }

  id <- trimws(as.character(collection_id))
  if (!nzchar(id)) {
    return(list(
      ok = FALSE,
      error = "collection_id is required"
    ))
  }

  store_path <- query_collections_store_path()
  if (!file.exists(store_path)) {
    return(list(ok = TRUE, deleted = FALSE))
  }

  con <- NULL
  out <- tryCatch(
    {
      con <- query_collections_connect(store_path)
      DBI::dbBegin(con)

      deleted_cards <- DBI::dbExecute(
        con,
        "DELETE FROM collection_cards WHERE collection_id = ?",
        params = list(id)
      )

      deleted_collections <- DBI::dbExecute(
        con,
        "DELETE FROM collections WHERE collection_id = ?",
        params = list(id)
      )

      DBI::dbCommit(con)
      list(
        ok = TRUE,
        deleted = as.integer(deleted_collections) > 0L || as.integer(deleted_cards) > 0L
      )
    },
    error = function(e) {
      if (!is.null(con) && DBI::dbIsValid(con)) {
        try(DBI::dbRollback(con), silent = TRUE)
      }
      list(ok = FALSE, error = e$message)
    },
    finally = {
      query_db_disconnect(con)
    }
  )

  out
}

query_collections_store_path <- function() {
  base_dir <- tryCatch(
    tools::R_user_dir("mtgcodex.api", which = "data"),
    error = function(e) {
      file.path(tempdir(), "mtgcodex.api-data")
    }
  )
  dir.create(base_dir, recursive = TRUE, showWarnings = FALSE)
  file.path(base_dir, "collections.sqlite")
}

query_collections_connect <- function(db_path) {
  con <- query_db_connect(db_path)
  query_collections_ensure_schema(con)
  con
}

query_collections_ensure_schema <- function(con) {
  DBI::dbExecute(
    con,
    paste(
      "CREATE TABLE IF NOT EXISTS collections (",
      "collection_id TEXT PRIMARY KEY,",
      "name TEXT NOT NULL,",
      "platform TEXT NOT NULL,",
      "source_file TEXT NOT NULL,",
      "created_at TEXT NOT NULL,",
      "row_count INTEGER NOT NULL",
      ")"
    )
  )

  DBI::dbExecute(
    con,
    paste(
      "CREATE TABLE IF NOT EXISTS collection_cards (",
      "id INTEGER PRIMARY KEY AUTOINCREMENT,",
      "collection_id TEXT NOT NULL,",
      "row_index INTEGER NOT NULL,",
      "quantity REAL NOT NULL,",
      "name TEXT NOT NULL,",
      "set_code TEXT,",
      "collector_number TEXT,",
      "mana_cost TEXT,",
      "oracle_text TEXT,",
      "keywords TEXT,",
      "language TEXT,",
      "finish TEXT,",
      "card_condition TEXT,",
      "scryfall_id TEXT,",
      "notes TEXT,",
      "FOREIGN KEY(collection_id) REFERENCES collections(collection_id)",
      ")"
    )
  )

  DBI::dbExecute(
    con,
    "CREATE INDEX IF NOT EXISTS idx_collection_cards_collection_id ON collection_cards(collection_id)"
  )
  DBI::dbExecute(
    con,
    "CREATE INDEX IF NOT EXISTS idx_collection_cards_name ON collection_cards(name)"
  )

  query_collections_ensure_column(con, "collection_cards", "mana_cost", "TEXT")
  query_collections_ensure_column(con, "collection_cards", "oracle_text", "TEXT")
  query_collections_ensure_column(con, "collection_cards", "keywords", "TEXT")
}

query_collections_make_id <- function(collection_name) {
  slug <- tolower(gsub("[^a-z0-9]+", "-", trimws(collection_name)))
  slug <- gsub("(^-+|-+$)", "", slug)
  if (!nzchar(slug)) {
    slug <- "collection"
  }
  paste0(slug, "-", as.integer(as.numeric(Sys.time())), "-", sample(1000:9999, size = 1L))
}

query_collections_read_csv_file <- function(path) {
  lines <- tryCatch(
    readLines(path, warn = FALSE, encoding = "UTF-8"),
    error = function(e) {
      return(list(.error = e$message))
    }
  )

  if (is.list(lines) && !is.null(lines$.error)) {
    return(list(ok = FALSE, error = lines$.error))
  }

  non_empty <- lines[nzchar(trimws(lines))]
  if (length(non_empty) == 0L) {
    return(list(ok = FALSE, error = "csv is empty"))
  }

  separator <- query_collection_guess_separator(non_empty[[1]])
  if (is.na(separator)) {
    separator <- ","
  }

  rows <- tryCatch(
    utils::read.table(
      file = path,
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

  list(ok = TRUE, rows = rows)
}

query_collections_normalize_rows <- function(df) {
  if (!is.data.frame(df) || nrow(df) == 0L) {
    return(list(ok = FALSE, error = "csv has no rows"))
  }

  c_name <- query_collections_find_column(
    df,
    c(
      "name",
      "card",
      "card_name",
      "card_name_en",
      "cardname",
      "cardtitle",
      "title",
      "product_name",
      "oracle_name",
      "item_name",
      "nom",
      "nomcarte"
    ),
    partial = TRUE
  )
  if (!nzchar(c_name)) {
    c_name <- query_collections_guess_name_column(df)
  }
  if (!nzchar(c_name)) {
    return(list(
      ok = FALSE,
      error = sprintf(
        "unable to detect card name column (available columns: %s)",
        paste(colnames(df), collapse = ", ")
      )
    ))
  }

  c_qty <- query_collections_find_column(
    df,
    c(
      "qty",
      "quantity",
      "count",
      "qte",
      "owned",
      "amount",
      "qty_owned",
      "quantity_owned",
      "owned_qty",
      "count_owned",
      "number_owned"
    ),
    partial = TRUE
  )
  c_set <- query_collections_find_column(df, c("set", "set_code", "edition", "extension", "setcode"))
  c_collector <- query_collections_find_column(df, c("collector_number", "number", "num", "collectorno", "cn"))
  c_mana <- query_collections_find_column(df, c("mana_cost", "manacost", "mana"))
  c_text <- query_collections_find_column(df, c("oracle_text", "card_text", "text", "rules_text", "printed_text"))
  c_keywords <- query_collections_find_column(df, c("keywords", "keyword", "abilities", "ability", "skills", "competences", "competence"))
  c_lang <- query_collections_find_column(df, c("lang", "language", "locale"))
  c_finish <- query_collections_find_column(df, c("foil", "finish", "is_foil", "premium"))
  c_condition <- query_collections_find_column(df, c("condition", "state", "card_condition"))
  c_scryfall <- query_collections_find_column(df, c("scryfall_id", "scry_fall_id", "scryfallid"))
  c_notes <- query_collections_find_column(df, c("notes", "comment", "comments", "remark"))

  quantity <- if (nzchar(c_qty)) query_collections_parse_number(df[[c_qty]]) else rep(1, nrow(df))
  quantity[is.na(quantity) | quantity <= 0] <- 1

  name <- query_collections_clean_vector(df[[c_name]])
  set_code <- if (nzchar(c_set)) query_collections_clean_vector(df[[c_set]]) else rep("", nrow(df))
  collector_number <- if (nzchar(c_collector)) query_collections_clean_vector(df[[c_collector]]) else rep("", nrow(df))
  mana_cost <- if (nzchar(c_mana)) query_collections_clean_vector(df[[c_mana]]) else rep("", nrow(df))
  oracle_text <- if (nzchar(c_text)) query_collections_clean_vector(df[[c_text]]) else rep("", nrow(df))
  keywords <- if (nzchar(c_keywords)) query_collections_clean_vector(df[[c_keywords]]) else rep("", nrow(df))
  language <- if (nzchar(c_lang)) query_collections_clean_vector(df[[c_lang]]) else rep("", nrow(df))
  finish <- if (nzchar(c_finish)) query_collections_clean_vector(df[[c_finish]]) else rep("", nrow(df))
  card_condition <- if (nzchar(c_condition)) query_collections_clean_vector(df[[c_condition]]) else rep("", nrow(df))
  scryfall_id <- if (nzchar(c_scryfall)) query_collections_clean_vector(df[[c_scryfall]]) else rep("", nrow(df))
  notes <- if (nzchar(c_notes)) query_collections_clean_vector(df[[c_notes]]) else rep("", nrow(df))

  keep <- nzchar(name)
  if (!any(keep)) {
    return(list(ok = FALSE, error = "no valid card names found"))
  }

  rows <- data.frame(
    row_index = seq_len(sum(keep)),
    quantity = quantity[keep],
    name = name[keep],
    set_code = set_code[keep],
    collector_number = collector_number[keep],
    mana_cost = mana_cost[keep],
    oracle_text = oracle_text[keep],
    keywords = keywords[keep],
    language = language[keep],
    finish = finish[keep],
    card_condition = card_condition[keep],
    scryfall_id = scryfall_id[keep],
    notes = notes[keep],
    stringsAsFactors = FALSE
  )

  list(ok = TRUE, rows = rows)
}

query_collections_clean_header <- function(x) {
  raw <- as.character(x)
  raw[is.na(raw)] <- ""
  raw <- trimws(raw)
  bom <- intToUtf8(65279L)
  has_bom <- substr(raw, 1L, 1L) == bom
  if (any(has_bom)) {
    raw[has_bom] <- substring(raw[has_bom], 2L)
  }
  raw <- tolower(raw)
  gsub("[^a-z0-9]+", "", raw)
}

query_collections_find_column <- function(df, candidates, partial = FALSE) {
  if (!is.data.frame(df) || length(candidates) == 0L) {
    return("")
  }

  original_names <- colnames(df)
  clean_names <- query_collections_clean_header(original_names)
  candidate_keys <- unique(query_collections_clean_header(candidates))

  for (key in candidate_keys) {
    matched <- which(clean_names == key)
    if (length(matched) > 0L) {
      col <- as.character(original_names[[matched[[1]]]])
      if (nzchar(col)) {
        return(col)
      }
    }
  }

  if (isTRUE(partial)) {
    partial_keys <- candidate_keys[nchar(candidate_keys) >= 5L]
    for (key in partial_keys) {
      matched <- which(grepl(key, clean_names, fixed = TRUE))
      if (length(matched) > 0L) {
        col <- as.character(original_names[[matched[[1]]]])
        if (nzchar(col)) {
          return(col)
        }
      }
    }
  }

  ""
}

query_collections_guess_name_column <- function(df) {
  if (!is.data.frame(df) || ncol(df) == 0L) {
    return("")
  }

  original_names <- colnames(df)
  clean_names <- query_collections_clean_header(original_names)
  blocked_patterns <- c(
    "qty",
    "quantity",
    "count",
    "set",
    "edition",
    "collector",
    "number",
    "lang",
    "language",
    "foil",
    "finish",
    "condition",
    "scryfall",
    "note",
    "comment",
    "price",
    "cost"
  )
  positive_patterns <- c("name", "card", "title", "product", "oracle")

  best_col <- ""
  best_score <- -Inf

  for (idx in seq_along(original_names)) {
    key <- clean_names[[idx]]
    if (!nzchar(key)) {
      next
    }

    if (any(grepl(paste(blocked_patterns, collapse = "|"), key))) {
      next
    }

    values <- query_collections_clean_vector(df[[idx]])
    values <- values[nzchar(values)]
    if (length(values) == 0L) {
      next
    }

    has_alpha <- grepl("[[:alpha:]]", values)
    alpha_ratio <- mean(has_alpha)
    if (is.na(alpha_ratio) || alpha_ratio < 0.3) {
      next
    }

    numeric_like <- !is.na(suppressWarnings(as.numeric(gsub(",", ".", values, fixed = TRUE))))
    numeric_ratio <- mean(numeric_like)
    avg_len <- mean(nchar(values))
    unique_ratio <- length(unique(values)) / length(values)

    score <- (2 * alpha_ratio) - (1.5 * numeric_ratio) + min(avg_len / 12, 1) + unique_ratio
    if (any(grepl(paste(positive_patterns, collapse = "|"), key))) {
      score <- score + 2
    }

    if (is.finite(score) && score > best_score) {
      best_score <- score
      best_col <- as.character(original_names[[idx]])
    }
  }

  best_col
}

query_collections_clean_vector <- function(x) {
  y <- as.character(x)
  y[is.na(y)] <- ""
  trimws(y)
}

query_collections_parse_number <- function(x) {
  y <- as.character(x)
  y[is.na(y)] <- "1"
  y <- gsub(",", ".", y, fixed = TRUE)
  out <- suppressWarnings(as.numeric(y))
  out
}

query_collections_clean_text <- function(x, fallback = "") {
  value <- trimws(as.character(x))
  if (!nzchar(value)) {
    return(fallback)
  }
  value
}

query_collections_ensure_column <- function(con, table_name, column_name, column_type) {
  if (is.null(con) || !DBI::dbIsValid(con)) {
    return(invisible(FALSE))
  }

  fields <- tryCatch(
    DBI::dbListFields(con, table_name),
    error = function(e) character(0)
  )
  if (column_name %in% fields) {
    return(invisible(TRUE))
  }

  sql <- sprintf(
    "ALTER TABLE %s ADD COLUMN %s %s",
    table_name,
    column_name,
    column_type
  )
  DBI::dbExecute(con, sql)
  invisible(TRUE)
}

query_collections_enrich_rows <- function(rows) {
  if (!is.data.frame(rows) || nrow(rows) == 0L) {
    return(rows)
  }

  if (!"mana_cost" %in% colnames(rows)) {
    rows$mana_cost <- rep("", nrow(rows))
  }
  if (!"oracle_text" %in% colnames(rows)) {
    rows$oracle_text <- rep("", nrow(rows))
  }
  if (!"keywords" %in% colnames(rows)) {
    rows$keywords <- rep("", nrow(rows))
  }
  if (!"scryfall_id" %in% colnames(rows)) {
    rows$scryfall_id <- rep("", nrow(rows))
  }
  if (!"language" %in% colnames(rows)) {
    rows$language <- rep("", nrow(rows))
  }
  if (!"set_code" %in% colnames(rows)) {
    rows$set_code <- rep("", nrow(rows))
  }
  if (!"collector_number" %in% colnames(rows)) {
    rows$collector_number <- rep("", nrow(rows))
  }

  rows$mana_cost <- query_collections_clean_vector(rows$mana_cost)
  rows$oracle_text <- query_collections_clean_vector(rows$oracle_text)
  rows$keywords <- query_collections_clean_vector(rows$keywords)
  rows$scryfall_id <- query_collections_clean_vector(rows$scryfall_id)
  rows$language <- query_collections_clean_vector(rows$language)
  rows$set_code <- query_collections_clean_vector(rows$set_code)
  rows$collector_number <- query_collections_clean_vector(rows$collector_number)

  ref_path <- query_collection_default_db_path()
  if (!nzchar(ref_path) || !file.exists(ref_path)) {
    rows$abilities <- rows$keywords
    return(rows)
  }

  ref_con <- NULL
  rows <- tryCatch(
    {
      ref_con <- query_db_connect(ref_path)
      for (i in seq_len(nrow(rows))) {
        has_mana <- nzchar(rows$mana_cost[[i]])
        has_text <- nzchar(rows$oracle_text[[i]])
        has_keywords <- nzchar(rows$keywords[[i]])
        if (has_mana && has_text && has_keywords) {
          next
        }

        card_details <- query_collections_lookup_card_details(ref_con, rows[i, , drop = FALSE])
        if (length(card_details) == 0L) {
          next
        }

        if (!has_mana && nzchar(card_details$mana_cost)) {
          rows$mana_cost[[i]] <- card_details$mana_cost
        }
        if (!has_text && nzchar(card_details$oracle_text)) {
          rows$oracle_text[[i]] <- card_details$oracle_text
        }
        if (!has_keywords && nzchar(card_details$keywords)) {
          rows$keywords[[i]] <- card_details$keywords
        }
        if (!nzchar(rows$scryfall_id[[i]]) && nzchar(card_details$scryfall_id)) {
          rows$scryfall_id[[i]] <- card_details$scryfall_id
        }
      }
      rows
    },
    error = function(e) {
      rows
    },
    finally = {
      query_db_disconnect(ref_con)
    }
  )

  rows$abilities <- rows$keywords
  rows
}

query_collections_lookup_card_details <- function(ref_con, row_df) {
  if (is.null(ref_con) || !DBI::dbIsValid(ref_con)) {
    return(list())
  }
  if (!is.data.frame(row_df) || nrow(row_df) == 0L) {
    return(list())
  }

  row <- as.list(row_df[1, , drop = FALSE])
  name <- query_collections_clean_text(row$name, fallback = "")
  set_code <- tolower(query_collections_clean_text(row$set_code, fallback = ""))
  collector_number <- query_collections_clean_text(row$collector_number, fallback = "")
  language <- tolower(query_collections_clean_text(row$language, fallback = ""))
  scryfall_id <- query_collections_clean_text(row$scryfall_id, fallback = "")

  read_one <- function(sql, params = list()) {
    out <- DBI::dbGetQuery(ref_con, sql, params = params)
    if (!is.data.frame(out) || nrow(out) == 0L) {
      return(NULL)
    }
    out[1, , drop = FALSE]
  }

  hit <- NULL
  if (nzchar(scryfall_id)) {
    hit <- read_one(
      paste(
        "SELECT scryfall_id, mana_cost, oracle_text, keywords",
        "FROM cards WHERE scryfall_id = ? LIMIT 1"
      ),
      params = list(scryfall_id)
    )
  }

  if (is.null(hit) && nzchar(set_code) && nzchar(collector_number)) {
    hit <- read_one(
      paste(
        "SELECT scryfall_id, mana_cost, oracle_text, keywords",
        "FROM cards",
        "WHERE lower(COALESCE(set_code, '')) = ?",
        "AND COALESCE(collector_number, '') = ?",
        "ORDER BY",
        "CASE",
        "WHEN lower(COALESCE(lang, '')) = ? THEN 0",
        "WHEN lower(COALESCE(lang, '')) = 'en' THEN 1",
        "ELSE 2",
        "END",
        "LIMIT 1"
      ),
      params = list(set_code, collector_number, language)
    )
  }

  if (is.null(hit) && nzchar(name)) {
    hit <- read_one(
      paste(
        "SELECT scryfall_id, mana_cost, oracle_text, keywords",
        "FROM cards",
        "WHERE lower(COALESCE(name, '')) = ?",
        "AND (? = '' OR lower(COALESCE(set_code, '')) = ?)",
        "ORDER BY",
        "CASE",
        "WHEN lower(COALESCE(lang, '')) = ? THEN 0",
        "WHEN lower(COALESCE(lang, '')) = 'en' THEN 1",
        "ELSE 2",
        "END,",
        "COALESCE(released_at, '') DESC",
        "LIMIT 1"
      ),
      params = list(tolower(name), set_code, set_code, language)
    )
  }

  if (is.null(hit) && nzchar(name)) {
    hit <- read_one(
      paste(
        "SELECT scryfall_id, mana_cost, oracle_text, keywords",
        "FROM cards",
        "WHERE lower(COALESCE(name, '')) = ?",
        "ORDER BY",
        "CASE",
        "WHEN lower(COALESCE(lang, '')) = ? THEN 0",
        "WHEN lower(COALESCE(lang, '')) = 'en' THEN 1",
        "ELSE 2",
        "END,",
        "COALESCE(released_at, '') DESC",
        "LIMIT 1"
      ),
      params = list(tolower(name), language)
    )
  }

  if (is.null(hit)) {
    return(list())
  }

  list(
    scryfall_id = query_collections_clean_text(hit$scryfall_id[[1]], fallback = ""),
    mana_cost = query_collections_clean_text(hit$mana_cost[[1]], fallback = ""),
    oracle_text = query_collections_clean_text(hit$oracle_text[[1]], fallback = ""),
    keywords = query_collections_clean_text(hit$keywords[[1]], fallback = "")
  )
}
