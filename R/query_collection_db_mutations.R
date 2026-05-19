query_collection_db_import <- function(req,
                                       db_path = "",
                                       source_type = "",
                                       source_table = "",
                                       filename = "",
                                       dedupe = "true") {
  deps <- query_api_require_db()
  if (!isTRUE(deps)) {
    return(deps)
  }

  resolved <- query_collection_db_resolve_target_path(db_path)
  if (!isTRUE(resolved$ok)) {
    return(resolved)
  }

  extracted <- query_collection_extract_uploaded_file(req, filename = filename)
  if (!isTRUE(extracted$ok)) {
    return(extracted)
  }

  load_out <- query_collection_db_read_source_rows(
    source_path = extracted$path,
    source_name = extracted$name,
    source_type = source_type,
    source_table = source_table
  )
  if (!isTRUE(load_out$ok)) {
    return(load_out)
  }

  normalized <- query_collection_db_normalize_collection_rows(load_out$collection_rows)
  if (!isTRUE(normalized$ok)) {
    return(normalized)
  }
  rows <- normalized$rows

  dedupe_enabled <- query_api_parse_bool(dedupe, default = TRUE)

  con <- NULL
  out <- tryCatch(
    {
      con <- .query_api_db_connect(resolved$path)
      query_collection_db_ensure_indexes(con)
      DBI::dbBegin(con)

      source_cards <- query_collection_db_prepare_cards_rows(load_out$cards_rows)
      inserted_cards_from_source <- query_collection_db_insert_cards_rows(con, source_cards)

      rows <- query_collection_db_complete_collection_rows(rows, con)
      insert_out <- query_collection_db_insert_collection_rows(
        con = con,
        rows = rows,
        dedupe_enabled = dedupe_enabled
      )

      cards_from_collection <- query_collection_db_prepare_cards_rows_from_collection(rows)
      inserted_cards_from_collection <- query_collection_db_insert_cards_rows(con, cards_from_collection)

      DBI::dbCommit(con)

      list(
        ok = TRUE,
        db_path = resolved$path,
        source_file = extracted$name,
        source_type = load_out$source_type,
        source_table = load_out$source_table,
        imported_rows = nrow(rows),
        inserted_collection = insert_out$inserted,
        skipped_collection = insert_out$skipped,
        inserted_cards = inserted_cards_from_source + inserted_cards_from_collection,
        inserted_cards_from_source = inserted_cards_from_source,
        inserted_cards_from_collection = inserted_cards_from_collection,
        dedupe = dedupe_enabled
      )
    },
    error = function(e) {
      if (!is.null(con) && DBI::dbIsValid(con)) {
        try(DBI::dbRollback(con), silent = TRUE)
      }
      list(ok = FALSE, error = e$message)
    },
    finally = {
      .query_api_db_disconnect(con)
    }
  )

  out
}

query_collection_db_add_card <- function(db_path = "",
                                         name = "",
                                         quantity = "1",
                                         set_code = "",
                                         set_name = "",
                                         collector_number = "",
                                         foil = "normal",
                                         rarity = "",
                                         language = "en",
                                         scryfall_id = "",
                                         manabox_id = "",
                                         purchase_price = "",
                                         purchase_price_currency = "EUR",
                                         misprint = "false",
                                         altered = "false",
                                         condition = "near_mint",
                                         dedupe = "true") {
  deps <- query_api_require_db()
  if (!isTRUE(deps)) {
    return(deps)
  }

  resolved <- query_collection_db_resolve_target_path(db_path)
  if (!isTRUE(resolved$ok)) {
    return(resolved)
  }

  draft <- data.frame(
    name = as.character(name),
    quantity = as.character(quantity),
    set_code = as.character(set_code),
    set_name = as.character(set_name),
    collector_number = as.character(collector_number),
    foil = as.character(foil),
    rarity = as.character(rarity),
    language = as.character(language),
    scryfall_id = as.character(scryfall_id),
    manabox_id = as.character(manabox_id),
    purchase_price = as.character(purchase_price),
    purchase_price_currency = as.character(purchase_price_currency),
    misprint = as.character(misprint),
    altered = as.character(altered),
    condition = as.character(condition),
    stringsAsFactors = FALSE
  )

  normalized <- query_collection_db_normalize_collection_rows(draft)
  if (!isTRUE(normalized$ok)) {
    return(normalized)
  }

  rows <- normalized$rows
  if (!is.data.frame(rows) || nrow(rows) == 0L) {
    return(list(
      ok = FALSE,
      error = "no valid card to add"
    ))
  }
  rows <- rows[1, , drop = FALSE]

  dedupe_enabled <- query_api_parse_bool(dedupe, default = TRUE)

  con <- NULL
  out <- tryCatch(
    {
      con <- .query_api_db_connect(resolved$path)
      query_collection_db_ensure_indexes(con)
      DBI::dbBegin(con)

      rows <- query_collection_db_complete_collection_rows(rows, con)
      insert_out <- query_collection_db_insert_collection_rows(
        con = con,
        rows = rows,
        dedupe_enabled = dedupe_enabled
      )

      cards_from_collection <- query_collection_db_prepare_cards_rows_from_collection(rows)
      inserted_cards <- query_collection_db_insert_cards_rows(con, cards_from_collection)

      DBI::dbCommit(con)

      list(
        ok = TRUE,
        db_path = resolved$path,
        inserted_collection = insert_out$inserted,
        skipped_collection = insert_out$skipped,
        inserted_cards = inserted_cards,
        inserted_ids = insert_out$inserted_ids,
        dedupe = dedupe_enabled
      )
    },
    error = function(e) {
      if (!is.null(con) && DBI::dbIsValid(con)) {
        try(DBI::dbRollback(con), silent = TRUE)
      }
      list(ok = FALSE, error = e$message)
    },
    finally = {
      .query_api_db_disconnect(con)
    }
  )

  out
}

query_collection_db_delete_card <- function(db_path = "",
                                            id = "",
                                            manabox_id = "",
                                            scryfall_id = "",
                                            name = "",
                                            set_code = "",
                                            collector_number = "",
                                            foil = "",
                                            language = "",
                                            delete_all = "false") {
  deps <- query_api_require_db()
  if (!isTRUE(deps)) {
    return(deps)
  }

  resolved <- query_collection_db_resolve_target_path(db_path)
  if (!isTRUE(resolved$ok)) {
    return(resolved)
  }

  target_id <- trimws(as.character(id))
  target_manabox <- trimws(as.character(manabox_id))
  target_scryfall <- trimws(as.character(scryfall_id))
  target_name <- trimws(as.character(name))
  target_set <- trimws(as.character(set_code))
  target_collector <- trimws(as.character(collector_number))
  target_foil <- trimws(as.character(foil))
  target_lang <- trimws(as.character(language))
  delete_all_flag <- query_api_parse_bool(delete_all, default = FALSE)

  con <- NULL
  out <- tryCatch(
    {
      con <- .query_api_db_connect(resolved$path)
      DBI::dbBegin(con)

      target_ids <- integer(0)
      if (nzchar(target_id)) {
        id_value <- suppressWarnings(as.integer(target_id))
        if (is.na(id_value)) {
          return(list(ok = FALSE, error = "id must be an integer"))
        }
        target_ids <- id_value
      } else {
        clauses <- character(0)
        params <- list()

        if (nzchar(target_manabox)) {
          clauses <- c(clauses, "coalesce(manabox_id, '') = ?")
          params <- c(params, list(target_manabox))
        }
        if (nzchar(target_scryfall)) {
          clauses <- c(clauses, "lower(coalesce(scryfall_id, '')) = lower(?)")
          params <- c(params, list(target_scryfall))
        }
        if (nzchar(target_name)) {
          clauses <- c(clauses, "lower(coalesce(name, '')) = lower(?)")
          params <- c(params, list(target_name))
        }
        if (nzchar(target_set)) {
          clauses <- c(clauses, "upper(coalesce(set_code, '')) = upper(?)")
          params <- c(params, list(target_set))
        }
        if (nzchar(target_collector)) {
          clauses <- c(clauses, "coalesce(collector_number, '') = ?")
          params <- c(params, list(target_collector))
        }
        if (nzchar(target_foil)) {
          clauses <- c(clauses, "lower(coalesce(foil, '')) = lower(?)")
          params <- c(params, list(target_foil))
        }
        if (nzchar(target_lang)) {
          clauses <- c(clauses, "lower(coalesce(language, '')) = lower(?)")
          params <- c(params, list(target_lang))
        }

        if (length(clauses) == 0L) {
          return(list(
            ok = FALSE,
            error = "provide at least one selector: id, manabox_id, scryfall_id, name"
          ))
        }

        select_sql <- paste(
          "SELECT id FROM collection WHERE",
          paste(clauses, collapse = " AND "),
          "ORDER BY id DESC"
        )
        if (!delete_all_flag) {
          select_sql <- paste(select_sql, "LIMIT 1")
        }
        selected <- DBI::dbGetQuery(con, select_sql, params = params)
        if (is.data.frame(selected) && nrow(selected) > 0L) {
          target_ids <- suppressWarnings(as.integer(selected$id))
          target_ids <- target_ids[!is.na(target_ids)]
        }
      }

      if (length(target_ids) == 0L) {
        DBI::dbCommit(con)
        return(list(
          ok = TRUE,
          db_path = resolved$path,
          deleted = 0L,
          deleted_ids = integer(0)
        ))
      }

      placeholders <- query_collection_db_sql_placeholders(length(target_ids))
      delete_sql <- sprintf(
        "DELETE FROM collection WHERE id IN (%s)",
        placeholders
      )
      deleted <- DBI::dbExecute(
        con,
        delete_sql,
        params = as.list(target_ids)
      )

      DBI::dbCommit(con)
      list(
        ok = TRUE,
        db_path = resolved$path,
        deleted = as.integer(deleted),
        deleted_ids = as.integer(target_ids)
      )
    },
    error = function(e) {
      if (!is.null(con) && DBI::dbIsValid(con)) {
        try(DBI::dbRollback(con), silent = TRUE)
      }
      list(ok = FALSE, error = e$message)
    },
    finally = {
      .query_api_db_disconnect(con)
    }
  )

  out
}

query_collection_db_resolve_target_path <- function(db_path = "") {
  raw_path <- trimws(as.character(db_path))
  if (!nzchar(raw_path)) {
    raw_path <- query_collection_default_db_path()
  }
  if (!nzchar(raw_path)) {
    return(list(
      ok = FALSE,
      error = "db_path is required"
    ))
  }

  normalized <- normalizePath(raw_path, winslash = "/", mustWork = FALSE)
  if (!file.exists(normalized)) {
    return(list(
      ok = FALSE,
      error = "database file not found",
      db_path = normalized
    ))
  }

  list(ok = TRUE, path = normalized)
}

query_collection_db_read_source_rows <- function(source_path,
                                                 source_name = "",
                                                 source_type = "",
                                                 source_table = "") {
  detected_type <- tolower(trimws(as.character(source_type)))
  if (!detected_type %in% c("db", "csv", "text")) {
    detected_type <- query_collection_guess_type_from_name(source_name)
  }
  if (!detected_type %in% c("db", "csv", "text")) {
    return(list(
      ok = FALSE,
      error = "source_type must be one of: db, csv, text"
    ))
  }

  if (!file.exists(source_path)) {
    return(list(
      ok = FALSE,
      error = "source file not found"
    ))
  }

  if (detected_type %in% c("csv", "text")) {
    parsed <- query_collections_read_csv_file(source_path)
    if (!isTRUE(parsed$ok)) {
      return(parsed)
    }
    return(list(
      ok = TRUE,
      source_type = detected_type,
      source_table = "",
      collection_rows = parsed$rows,
      cards_rows = data.frame(stringsAsFactors = FALSE)
    ))
  }

  con <- NULL
  out <- tryCatch(
    {
      con <- .query_api_db_connect(source_path)
      tables <- DBI::dbListTables(con)
      if (length(tables) == 0L) {
        return(list(
          ok = FALSE,
          error = "source database has no tables"
        ))
      }

      selected_table <- query_collection_db_find_table(tables, source_table)
      if (!nzchar(selected_table)) {
        preferred <- c("collection", "collection_cards", "cards")
        preferred_matches <- vapply(
          preferred,
          function(candidate) query_collection_db_find_table(tables, candidate),
          character(1)
        )
        preferred_matches <- preferred_matches[nzchar(preferred_matches)]
        if (length(preferred_matches) > 0L) {
          selected_table <- preferred_matches[[1]]
        }
      }
      if (!nzchar(selected_table) && length(tables) > 0L) {
        selected_table <- as.character(tables)[[1]]
      }
      if (!nzchar(selected_table)) {
        return(list(
          ok = FALSE,
          error = "unable to resolve source table",
          available_tables = sort(as.character(tables))
        ))
      }

      selected_quoted <- DBI::dbQuoteIdentifier(con, selected_table)
      collection_rows <- DBI::dbGetQuery(
        con,
        sprintf("SELECT * FROM %s", as.character(selected_quoted))
      )

      cards_table <- query_collection_db_find_table(tables, "cards")
      cards_rows <- data.frame(stringsAsFactors = FALSE)
      if (nzchar(cards_table)) {
        cards_quoted <- DBI::dbQuoteIdentifier(con, cards_table)
        cards_rows <- DBI::dbGetQuery(
          con,
          sprintf("SELECT * FROM %s", as.character(cards_quoted))
        )
      }

      list(
        ok = TRUE,
        source_type = detected_type,
        source_table = selected_table,
        collection_rows = collection_rows,
        cards_rows = cards_rows
      )
    },
    error = function(e) {
      list(ok = FALSE, error = e$message)
    },
    finally = {
      .query_api_db_disconnect(con)
    }
  )

  out
}

query_collection_db_find_table <- function(tables, target) {
  table_values <- as.character(tables)
  if (length(table_values) == 0L) {
    return("")
  }
  target_lower <- tolower(trimws(as.character(target)))
  lower_tables <- tolower(table_values)
  index <- match(target_lower, lower_tables)
  if (is.na(index)) {
    return("")
  }
  table_values[[index]]
}

query_collection_db_normalize_collection_rows <- function(df) {
  if (!is.data.frame(df) || nrow(df) == 0L) {
    return(list(ok = FALSE, error = "input has no rows"))
  }

  c_name <- query_collections_find_column(
    df,
    c(
      "name",
      "card",
      "card_name",
      "cardname",
      "nom",
      "title",
      "product_name",
      "oracle_name"
    ),
    partial = TRUE
  )
  c_scryfall <- query_collections_find_column(
    df,
    c("scryfall_id", "scryfallid", "scry_fall_id", "scryfall")
  )
  if (!nzchar(c_name) && !nzchar(c_scryfall)) {
    c_name <- query_collections_guess_name_column(df)
  }
  if (!nzchar(c_name) && !nzchar(c_scryfall)) {
    return(list(
      ok = FALSE,
      error = sprintf(
        "unable to detect card columns (available: %s)",
        paste(colnames(df), collapse = ", ")
      )
    ))
  }

  c_qty <- query_collections_find_column(
    df,
    c("qty", "quantity", "count", "owned", "amount", "number_owned"),
    partial = TRUE
  )
  c_set_code <- query_collections_find_column(df, c("set_code", "set", "setcode", "edition", "extension"))
  c_set_name <- query_collections_find_column(df, c("set_name", "setname", "edition_name", "editionname", "settitle"), partial = TRUE)
  c_collector <- query_collections_find_column(df, c("collector_number", "collectorno", "number", "num", "cn"))
  c_foil <- query_collections_find_column(df, c("foil", "finish", "is_foil", "premium"))
  c_rarity <- query_collections_find_column(df, c("rarity"))
  c_manabox <- query_collections_find_column(df, c("manabox_id", "manaboxid", "manabox"))
  c_price <- query_collections_find_column(df, c("purchase_price", "purchaseprice", "price", "cost"))
  c_misprint <- query_collections_find_column(df, c("misprint"))
  c_altered <- query_collections_find_column(df, c("altered"))
  c_condition <- query_collections_find_column(df, c("condition", "state", "card_condition"))
  c_language <- query_collections_find_column(df, c("language", "lang", "locale"))
  c_currency <- query_collections_find_column(df, c("purchase_price_currency", "purchasecurrency", "currency", "price_currency"))

  rows_n <- nrow(df)
  name <- if (nzchar(c_name)) query_collections_clean_vector(df[[c_name]]) else rep("", rows_n)
  quantity <- if (nzchar(c_qty)) query_collections_parse_number(df[[c_qty]]) else rep(1, rows_n)
  quantity[is.na(quantity) | quantity <= 0] <- 1
  quantity <- as.integer(round(quantity))

  set_code <- if (nzchar(c_set_code)) query_collections_clean_vector(df[[c_set_code]]) else rep("", rows_n)
  set_name <- if (nzchar(c_set_name)) query_collections_clean_vector(df[[c_set_name]]) else rep("", rows_n)
  collector_number <- if (nzchar(c_collector)) query_collections_clean_vector(df[[c_collector]]) else rep("", rows_n)
  foil <- if (nzchar(c_foil)) query_collections_clean_vector(df[[c_foil]]) else rep("", rows_n)
  rarity <- if (nzchar(c_rarity)) query_collections_clean_vector(df[[c_rarity]]) else rep("", rows_n)
  manabox_id <- if (nzchar(c_manabox)) query_collections_clean_vector(df[[c_manabox]]) else rep("", rows_n)
  scryfall_id <- if (nzchar(c_scryfall)) query_collections_clean_vector(df[[c_scryfall]]) else rep("", rows_n)
  purchase_raw <- if (nzchar(c_price)) query_collections_clean_vector(df[[c_price]]) else rep("", rows_n)
  misprint <- if (nzchar(c_misprint)) query_collections_clean_vector(df[[c_misprint]]) else rep("", rows_n)
  altered <- if (nzchar(c_altered)) query_collections_clean_vector(df[[c_altered]]) else rep("", rows_n)
  card_condition <- if (nzchar(c_condition)) query_collections_clean_vector(df[[c_condition]]) else rep("", rows_n)
  language <- if (nzchar(c_language)) query_collections_clean_vector(df[[c_language]]) else rep("", rows_n)
  purchase_price_currency <- if (nzchar(c_currency)) query_collections_clean_vector(df[[c_currency]]) else rep("", rows_n)

  keep <- nzchar(name) | nzchar(scryfall_id)
  if (!any(keep)) {
    return(list(ok = FALSE, error = "no valid card rows found"))
  }

  foil <- tolower(trimws(foil))
  foil[foil %in% c("", "0", "false", "nonfoil")] <- "normal"
  foil[foil %in% c("1", "true")] <- "foil"

  language <- tolower(trimws(language))
  language[!nzchar(language)] <- "en"
  set_code <- toupper(trimws(set_code))
  purchase_price_currency <- toupper(trimws(purchase_price_currency))
  purchase_price_currency[!nzchar(purchase_price_currency)] <- "EUR"

  misprint <- tolower(trimws(misprint))
  altered <- tolower(trimws(altered))
  misprint[!nzchar(misprint)] <- "false"
  altered[!nzchar(altered)] <- "false"
  card_condition <- trimws(card_condition)
  card_condition[!nzchar(card_condition)] <- "near_mint"
  scryfall_id <- tolower(trimws(scryfall_id))

  purchase_price <- query_collections_parse_number(purchase_raw, default = NA_real_)

  rows <- data.frame(
    scryfall_id = scryfall_id[keep],
    name = trimws(name[keep]),
    set_code = set_code[keep],
    set_name = trimws(set_name[keep]),
    collector_number = trimws(collector_number[keep]),
    foil = foil[keep],
    rarity = tolower(trimws(rarity[keep])),
    quantity = quantity[keep],
    manabox_id = trimws(manabox_id[keep]),
    purchase_price = purchase_price[keep],
    misprint = misprint[keep],
    altered = altered[keep],
    condition = card_condition[keep],
    language = language[keep],
    purchase_price_currency = purchase_price_currency[keep],
    stringsAsFactors = FALSE
  )

  list(ok = TRUE, rows = rows)
}

query_collection_db_complete_collection_rows <- function(rows, ref_con) {
  if (!is.data.frame(rows) || nrow(rows) == 0L) {
    return(rows)
  }
  if (is.null(ref_con) || !DBI::dbIsValid(ref_con)) {
    return(rows)
  }

  for (i in seq_len(nrow(rows))) {
    if (nzchar(rows$scryfall_id[[i]])) {
      next
    }
    row_probe <- data.frame(
      name = rows$name[[i]],
      set_code = rows$set_code[[i]],
      collector_number = rows$collector_number[[i]],
      language = rows$language[[i]],
      scryfall_id = rows$scryfall_id[[i]],
      stringsAsFactors = FALSE
    )
    details <- query_collections_lookup_card_details(ref_con, row_probe)
    if (length(details) > 0L && nzchar(details$scryfall_id)) {
      rows$scryfall_id[[i]] <- details$scryfall_id
    }
  }

  sid_values <- unique(rows$scryfall_id[nzchar(rows$scryfall_id)])
  if (length(sid_values) == 0L) {
    return(rows)
  }

  placeholders <- query_collection_db_sql_placeholders(length(sid_values))
  sql <- sprintf(
    paste(
      "SELECT scryfall_id, name, rarity, set_code, set_name, collector_number,",
      "lang FROM cards WHERE scryfall_id IN (%s)"
    ),
    placeholders
  )
  hits <- DBI::dbGetQuery(
    ref_con,
    sql,
    params = as.list(sid_values)
  )
  if (!is.data.frame(hits) || nrow(hits) == 0L) {
    return(rows)
  }

  idx <- match(rows$scryfall_id, hits$scryfall_id)
  matched <- nzchar(rows$scryfall_id) & !is.na(idx)
  fill_from_hit <- function(target, source_col, transform = identity) {
    src <- transform(source_col[idx])
    needs <- matched & !nzchar(target) & !is.na(src) & nzchar(src)
    target[needs] <- src[needs]
    target
  }
  rows$name             <- fill_from_hit(rows$name, hits$name)
  rows$set_code         <- fill_from_hit(rows$set_code, hits$set_code, toupper)
  rows$set_name         <- fill_from_hit(rows$set_name, hits$set_name)
  rows$collector_number <- fill_from_hit(rows$collector_number, hits$collector_number)
  rows$rarity           <- fill_from_hit(rows$rarity, hits$rarity)
  rows$language         <- fill_from_hit(rows$language, hits$lang)

  rows
}

query_collection_db_sql_placeholders <- function(n) {
  if (!is.numeric(n) || length(n) != 1L || is.na(n) || n <= 0) {
    return("")
  }
  paste(rep("?", n), collapse = ", ")
}

query_collection_db_ensure_indexes <- function(con) {
  if (is.null(con) || !DBI::dbIsValid(con)) {
    return(invisible(FALSE))
  }

  statements <- c(
    paste(
      "CREATE INDEX IF NOT EXISTS idx_collection_manabox_id",
      "ON collection(manabox_id)"
    ),
    paste(
      "CREATE INDEX IF NOT EXISTS idx_collection_scryfall_set_collector_finish_lang",
      "ON collection(scryfall_id, set_code, collector_number, foil, language)"
    ),
    paste(
      "CREATE INDEX IF NOT EXISTS idx_collection_name_set_collector_finish_lang",
      "ON collection(name, set_code, collector_number, foil, language)"
    ),
    paste(
      "CREATE INDEX IF NOT EXISTS idx_cards_set_collector_lang",
      "ON cards(set_code, collector_number, lang)"
    ),
    paste(
      "CREATE INDEX IF NOT EXISTS idx_cards_name_set_lang_released",
      "ON cards(name, set_code, lang, released_at)"
    )
  )

  for (sql in statements) {
    DBI::dbExecute(con, sql)
  }

  invisible(TRUE)
}

query_collection_db_insert_collection_rows <- function(con, rows, dedupe_enabled = TRUE) {
  if (!is.data.frame(rows) || nrow(rows) == 0L) {
    return(list(inserted = 0L, skipped = 0L, inserted_ids = integer(0)))
  }

  insert_sql <- paste(
    "INSERT INTO collection (",
    "scryfall_id, name, set_code, set_name, collector_number,",
    "foil, rarity, quantity, manabox_id, purchase_price,",
    "misprint, altered, condition, language, purchase_price_currency",
    ") VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
  )

  inserted <- 0L
  skipped <- 0L
  inserted_ids <- integer(0)

  for (i in seq_len(nrow(rows))) {
    row <- rows[i, , drop = FALSE]
    exists <- FALSE

    if (isTRUE(dedupe_enabled)) {
      if (nzchar(row$manabox_id[[1]])) {
        existing <- DBI::dbGetQuery(
          con,
          "SELECT id FROM collection WHERE coalesce(manabox_id, '') = ? LIMIT 1",
          params = list(row$manabox_id[[1]])
        )
        exists <- is.data.frame(existing) && nrow(existing) > 0L
      } else if (nzchar(row$scryfall_id[[1]])) {
        existing <- DBI::dbGetQuery(
          con,
          paste(
            "SELECT id FROM collection",
            "WHERE lower(coalesce(scryfall_id, '')) = lower(?)",
            "AND upper(coalesce(set_code, '')) = upper(?)",
            "AND coalesce(collector_number, '') = coalesce(?, '')",
            "AND lower(coalesce(foil, '')) = lower(?)",
            "AND lower(coalesce(language, '')) = lower(?)",
            "LIMIT 1"
          ),
          params = list(
            row$scryfall_id[[1]],
            row$set_code[[1]],
            row$collector_number[[1]],
            row$foil[[1]],
            row$language[[1]]
          )
        )
        exists <- is.data.frame(existing) && nrow(existing) > 0L
      } else {
        existing <- DBI::dbGetQuery(
          con,
          paste(
            "SELECT id FROM collection",
            "WHERE lower(coalesce(name, '')) = lower(?)",
            "AND upper(coalesce(set_code, '')) = upper(?)",
            "AND coalesce(collector_number, '') = coalesce(?, '')",
            "AND lower(coalesce(foil, '')) = lower(?)",
            "AND lower(coalesce(language, '')) = lower(?)",
            "LIMIT 1"
          ),
          params = list(
            row$name[[1]],
            row$set_code[[1]],
            row$collector_number[[1]],
            row$foil[[1]],
            row$language[[1]]
          )
        )
        exists <- is.data.frame(existing) && nrow(existing) > 0L
      }
    }

    if (exists) {
      skipped <- skipped + 1L
      next
    }

    DBI::dbExecute(
      con,
      insert_sql,
      params = list(
        row$scryfall_id[[1]],
        row$name[[1]],
        row$set_code[[1]],
        row$set_name[[1]],
        row$collector_number[[1]],
        row$foil[[1]],
        row$rarity[[1]],
        as.integer(row$quantity[[1]]),
        row$manabox_id[[1]],
        if (is.na(row$purchase_price[[1]])) NA_real_ else as.numeric(row$purchase_price[[1]]),
        row$misprint[[1]],
        row$altered[[1]],
        row$condition[[1]],
        row$language[[1]],
        row$purchase_price_currency[[1]]
      )
    )
    inserted <- inserted + 1L
    inserted_ids <- c(inserted_ids, DBI::dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id[[1]])
  }

  list(
    inserted = as.integer(inserted),
    skipped = as.integer(skipped),
    inserted_ids = as.integer(inserted_ids)
  )
}

query_collection_db_prepare_cards_rows <- function(df) {
  empty <- query_collection_db_cards_df()
  if (!is.data.frame(df) || nrow(df) == 0L) {
    return(empty)
  }

  c_scryfall <- query_collections_find_column(df, c("scryfall_id", "scryfallid", "scry_fall_id", "scryfall"))
  c_name <- query_collections_find_column(df, c("name", "card_name", "card", "title"), partial = TRUE)
  c_oracle <- query_collections_find_column(df, c("oracle_text", "printed_text", "card_text", "text"))
  c_type <- query_collections_find_column(df, c("type_line", "type"))
  c_mana <- query_collections_find_column(df, c("mana_cost", "manacost", "mana"))
  c_cmc <- query_collections_find_column(df, c("cmc"))
  c_colors <- query_collections_find_column(df, c("colors", "color"))
  c_color_identity <- query_collections_find_column(df, c("color_identity", "coloridentity"))
  c_keywords <- query_collections_find_column(df, c("keywords", "keyword", "abilities"))
  c_produced_mana <- query_collections_find_column(df, c("produced_mana", "producedmana"))
  c_power <- query_collections_find_column(df, c("power"))
  c_toughness <- query_collections_find_column(df, c("toughness"))
  c_loyalty <- query_collections_find_column(df, c("loyalty"))
  c_rarity <- query_collections_find_column(df, c("rarity"))
  c_set_code <- query_collections_find_column(df, c("set_code", "set", "setcode", "edition"))
  c_set_name <- query_collections_find_column(df, c("set_name", "setname", "edition_name"), partial = TRUE)
  c_collector <- query_collections_find_column(df, c("collector_number", "collectorno", "number", "num", "cn"))
  c_lang <- query_collections_find_column(df, c("lang", "language", "locale"))
  c_legalities <- query_collections_find_column(df, c("legalities"))
  c_layout <- query_collections_find_column(df, c("layout"))
  c_faces <- query_collections_find_column(df, c("card_faces", "cardfaces"))
  c_images <- query_collections_find_column(df, c("image_uris", "imageuris"))
  c_prices <- query_collections_find_column(df, c("prices"))
  c_edhrec <- query_collections_find_column(df, c("edhrec_rank", "edhrecrank"))
  c_released <- query_collections_find_column(df, c("released_at", "releasedat", "release_date", "released"))

  rows_n <- nrow(df)
  out <- query_collection_db_cards_df(rows_n)
  out$scryfall_id <- if (nzchar(c_scryfall)) tolower(query_collections_clean_vector(df[[c_scryfall]])) else rep("", rows_n)
  out$name <- if (nzchar(c_name)) query_collections_clean_vector(df[[c_name]]) else rep("", rows_n)
  out$oracle_text <- if (nzchar(c_oracle)) query_collections_clean_vector(df[[c_oracle]]) else rep("", rows_n)
  out$type_line <- if (nzchar(c_type)) query_collections_clean_vector(df[[c_type]]) else rep("", rows_n)
  out$mana_cost <- if (nzchar(c_mana)) query_collections_clean_vector(df[[c_mana]]) else rep("", rows_n)
  out$cmc <- if (nzchar(c_cmc)) query_collections_parse_number(df[[c_cmc]], default = NA_real_) else rep(NA_real_, rows_n)
  out$colors <- if (nzchar(c_colors)) query_collections_clean_vector(df[[c_colors]]) else rep("", rows_n)
  out$color_identity <- if (nzchar(c_color_identity)) query_collections_clean_vector(df[[c_color_identity]]) else rep("", rows_n)
  out$keywords <- if (nzchar(c_keywords)) query_collections_clean_vector(df[[c_keywords]]) else rep("", rows_n)
  out$produced_mana <- if (nzchar(c_produced_mana)) query_collections_clean_vector(df[[c_produced_mana]]) else rep("", rows_n)
  out$power <- if (nzchar(c_power)) query_collections_clean_vector(df[[c_power]]) else rep("", rows_n)
  out$toughness <- if (nzchar(c_toughness)) query_collections_clean_vector(df[[c_toughness]]) else rep("", rows_n)
  out$loyalty <- if (nzchar(c_loyalty)) query_collections_clean_vector(df[[c_loyalty]]) else rep("", rows_n)
  out$rarity <- if (nzchar(c_rarity)) tolower(query_collections_clean_vector(df[[c_rarity]])) else rep("", rows_n)
  out$set_code <- if (nzchar(c_set_code)) query_collections_clean_vector(df[[c_set_code]]) else rep("", rows_n)
  out$set_name <- if (nzchar(c_set_name)) query_collections_clean_vector(df[[c_set_name]]) else rep("", rows_n)
  out$collector_number <- if (nzchar(c_collector)) query_collections_clean_vector(df[[c_collector]]) else rep("", rows_n)
  out$lang <- if (nzchar(c_lang)) tolower(query_collections_clean_vector(df[[c_lang]])) else rep("en", rows_n)
  out$legalities <- if (nzchar(c_legalities)) query_collections_clean_vector(df[[c_legalities]]) else rep("", rows_n)
  out$layout <- if (nzchar(c_layout)) query_collections_clean_vector(df[[c_layout]]) else rep("", rows_n)
  out$card_faces <- if (nzchar(c_faces)) query_collections_clean_vector(df[[c_faces]]) else rep("", rows_n)
  out$image_uris <- if (nzchar(c_images)) query_collections_clean_vector(df[[c_images]]) else rep("", rows_n)
  out$prices <- if (nzchar(c_prices)) query_collections_clean_vector(df[[c_prices]]) else rep("", rows_n)
  out$edhrec_rank <- if (nzchar(c_edhrec)) suppressWarnings(as.integer(query_collections_parse_number(df[[c_edhrec]]))) else rep(NA_integer_, rows_n)
  out$released_at <- if (nzchar(c_released)) query_collections_clean_vector(df[[c_released]]) else rep("", rows_n)

  keep <- nzchar(out$scryfall_id)
  if (!any(keep)) {
    return(empty)
  }
  out <- out[keep, , drop = FALSE]
  rownames(out) <- NULL
  out
}

query_collection_db_prepare_cards_rows_from_collection <- function(rows) {
  empty <- query_collection_db_cards_df()
  if (!is.data.frame(rows) || nrow(rows) == 0L) {
    return(empty)
  }

  keep <- nzchar(rows$scryfall_id)
  if (!any(keep)) {
    return(empty)
  }

  sub <- rows[keep, , drop = FALSE]
  out <- query_collection_db_cards_df(nrow(sub))
  out$scryfall_id <- sub$scryfall_id
  out$name <- sub$name
  out$rarity <- sub$rarity
  out$set_code <- sub$set_code
  out$set_name <- sub$set_name
  out$collector_number <- sub$collector_number
  out$lang <- sub$language
  rownames(out) <- NULL
  out
}

query_collection_db_cards_df <- function(n = 0L) {
  if (!is.numeric(n) || length(n) != 1L || is.na(n) || n <= 0) {
    n <- 0L
  }
  data.frame(
    scryfall_id = rep("", n),
    name = rep("", n),
    oracle_text = rep("", n),
    type_line = rep("", n),
    mana_cost = rep("", n),
    cmc = rep(NA_real_, n),
    colors = rep("", n),
    color_identity = rep("", n),
    keywords = rep("", n),
    produced_mana = rep("", n),
    power = rep("", n),
    toughness = rep("", n),
    loyalty = rep("", n),
    rarity = rep("", n),
    set_code = rep("", n),
    set_name = rep("", n),
    collector_number = rep("", n),
    lang = rep("en", n),
    legalities = rep("", n),
    layout = rep("", n),
    card_faces = rep("", n),
    image_uris = rep("", n),
    prices = rep("", n),
    edhrec_rank = rep(NA_integer_, n),
    released_at = rep("", n),
    stringsAsFactors = FALSE
  )
}

query_collection_db_insert_cards_rows <- function(con, rows) {
  if (!is.data.frame(rows) || nrow(rows) == 0L) {
    return(0L)
  }
  if (is.null(con) || !DBI::dbIsValid(con)) {
    return(0L)
  }

  required_cols <- colnames(query_collection_db_cards_df())
  missing_cols <- setdiff(required_cols, colnames(rows))
  if (length(missing_cols) > 0L) {
    for (col in missing_cols) {
      rows[[col]] <- NA
    }
  }
  rows <- rows[, required_cols, drop = FALSE]
  rows <- rows[nzchar(trimws(as.character(rows$scryfall_id))), , drop = FALSE]
  if (nrow(rows) == 0L) {
    return(0L)
  }

  insert_sql <- paste(
    "INSERT OR IGNORE INTO cards (",
    "scryfall_id, name, oracle_text, type_line, mana_cost, cmc,",
    "colors, color_identity, keywords, produced_mana, power, toughness,",
    "loyalty, rarity, set_code, set_name, collector_number, lang,",
    "legalities, layout, card_faces, image_uris, prices, edhrec_rank, released_at",
    ") VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
  )

  inserted <- 0L
  for (i in seq_len(nrow(rows))) {
    row <- rows[i, , drop = FALSE]
    changes <- DBI::dbExecute(
      con,
      insert_sql,
      params = list(
        row$scryfall_id[[1]],
        row$name[[1]],
        row$oracle_text[[1]],
        row$type_line[[1]],
        row$mana_cost[[1]],
        if (is.na(row$cmc[[1]])) NA_real_ else as.numeric(row$cmc[[1]]),
        row$colors[[1]],
        row$color_identity[[1]],
        row$keywords[[1]],
        row$produced_mana[[1]],
        row$power[[1]],
        row$toughness[[1]],
        row$loyalty[[1]],
        row$rarity[[1]],
        row$set_code[[1]],
        row$set_name[[1]],
        row$collector_number[[1]],
        if (nzchar(row$lang[[1]])) row$lang[[1]] else "en",
        row$legalities[[1]],
        row$layout[[1]],
        row$card_faces[[1]],
        row$image_uris[[1]],
        row$prices[[1]],
        if (is.na(row$edhrec_rank[[1]])) NA_integer_ else as.integer(row$edhrec_rank[[1]]),
        row$released_at[[1]]
      )
    )
    if (is.numeric(changes) && changes > 0) {
      inserted <- inserted + 1L
    }
  }

  as.integer(inserted)
}
