# Round-trip test for the enriched-SQLite fast path: normalise a card,
# write the resulting structure into the same schema produced by
# scripts/enrich-scryfall-library.R, then load it back via
# query_synergy_catalog_normalized_from_sqlite() and check that the
# precomputed catalog skips re-normalisation.

build_enriched_db <- function(path, cards, precompute_version) {
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con, "CREATE TABLE enrichment_meta (
    enriched_at TEXT, normalizer_version TEXT, precompute_version TEXT,
    oracle_ids INTEGER, face_rows INTEGER, source_table TEXT
  )")
  DBI::dbExecute(
    con,
    sprintf(
      "INSERT INTO enrichment_meta VALUES ('now','normalized_card_v2','%s',%d,%d,'cards')",
      precompute_version, length(cards), length(cards)
    )
  )

  DBI::dbExecute(con, "CREATE TABLE cards_enriched (
    oracle_id TEXT, face_index INTEGER, face_name TEXT, name TEXT,
    scryfall_id TEXT, layout TEXT, set_code TEXT, set_name TEXT, rarity TEXT,
    edhrec_rank INTEGER, mana_cost TEXT, mana_value REAL, cmc REAL,
    type_line TEXT, oracle_text TEXT, power TEXT, toughness TEXT, loyalty TEXT,
    colors TEXT, color_identity TEXT, produced_mana TEXT,
    keywords TEXT, mechanics TEXT, roles TEXT, target_roles TEXT,
    strategy_tags TEXT, produced_events TEXT, consumed_events TEXT,
    replaced_events TEXT, prevented_events TEXT, setup_events TEXT,
    finisher_events TEXT, anti_tags TEXT,
    cadence_class TEXT, cadence_repeatable INTEGER, cadence_scalable INTEGER,
    cadence_strength REAL,
    cadence_contexts_json TEXT, cadence_sources_json TEXT,
    abilities_json TEXT, produces_json TEXT, rewards_json TEXT,
    requires_json TEXT, replaces_json TEXT, prevents_json TEXT,
    amplifies_json TEXT, moves_json TEXT, plans_json TEXT, legalities_json TEXT
  )")

  collapse_chr <- function(x) {
    v <- as.character(x)
    v <- v[!is.na(v) & nzchar(v)]
    if (!length(v)) NA_character_ else paste(unique(v), collapse = ";")
  }
  encode_json <- function(x) {
    if (is.null(x) || (is.atomic(x) && !length(x))) return(NA_character_)
    jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", na = "null")
  }

  for (i in seq_along(cards)) {
    norm <- cards[[i]]
    cad <- norm$cadence %||% list()
    DBI::dbExecute(
      con,
      "INSERT INTO cards_enriched VALUES (
        $oracle_id,$face_index,$face_name,$name,$scryfall_id,$layout,
        $set_code,$set_name,$rarity,$edhrec_rank,$mana_cost,$mana_value,$cmc,
        $type_line,$oracle_text,$power,$toughness,$loyalty,$colors,
        $color_identity,$produced_mana,$keywords,$mechanics,$roles,
        $target_roles,$strategy_tags,$produced_events,$consumed_events,
        $replaced_events,$prevented_events,$setup_events,$finisher_events,
        $anti_tags,$cadence_class,$cadence_repeatable,$cadence_scalable,
        $cadence_strength,$cadence_contexts_json,$cadence_sources_json,
        $abilities_json,$produces_json,$rewards_json,$requires_json,
        $replaces_json,$prevents_json,$amplifies_json,$moves_json,
        $plans_json,$legalities_json)",
      params = list(
        oracle_id = norm$id, face_index = 0L, face_name = norm$name,
        name = norm$name, scryfall_id = norm$id, layout = NA_character_,
        set_code = NA_character_, set_name = NA_character_, rarity = NA_character_,
        edhrec_rank = NA_integer_, mana_cost = NA_character_,
        mana_value = norm$mana_value, cmc = norm$mana_value,
        type_line = norm$type_line, oracle_text = norm$oracle_text,
        power = NA_character_, toughness = NA_character_, loyalty = NA_character_,
        colors = collapse_chr(norm$colors),
        color_identity = collapse_chr(norm$color_identity),
        produced_mana = NA_character_,
        keywords = collapse_chr(norm$keywords),
        mechanics = collapse_chr(norm$mechanics),
        roles = collapse_chr(norm$roles),
        target_roles = collapse_chr(norm$target_roles),
        strategy_tags = collapse_chr(norm$strategy_tags),
        produced_events = collapse_chr(norm$produced_events),
        consumed_events = collapse_chr(norm$consumed_events),
        replaced_events = collapse_chr(norm$replaced_events),
        prevented_events = collapse_chr(norm$prevented_events),
        setup_events = collapse_chr(norm$setup_events),
        finisher_events = collapse_chr(norm$finisher_events),
        anti_tags = collapse_chr(norm$anti_tags),
        cadence_class = cad$class %||% "one_shot",
        cadence_repeatable = as.integer(isTRUE(cad$repeatable)),
        cadence_scalable = as.integer(isTRUE(cad$scalable)),
        cadence_strength = as.numeric(cad$strength %||% 0),
        cadence_contexts_json = encode_json(cad$contexts),
        cadence_sources_json = encode_json(cad$sources),
        abilities_json = encode_json(norm$abilities),
        produces_json = encode_json(norm$produces),
        rewards_json = encode_json(norm$rewards),
        requires_json = encode_json(norm$requires),
        replaces_json = encode_json(norm$replaces),
        prevents_json = encode_json(norm$prevents),
        amplifies_json = encode_json(norm$amplifies),
        moves_json = encode_json(norm$moves),
        plans_json = encode_json(norm$plans),
        legalities_json = encode_json(norm$legalities)
      )
    )
  }
  invisible(path)
}

test_that("query_synergy_catalog_normalized_from_sqlite reconstructs normalized cards", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  skip_if_not_installed("jsonlite")

  raw <- list(
    list(id = "id-a", name = "Token Maker", type_line = "Creature - Elf",
         oracle_text = "When this creature enters, create a 1/1 green Elf token.",
         cmc = 2, colors = "G", color_identity = "G", keywords = character()),
    list(id = "id-b", name = "Death Payoff", type_line = "Enchantment",
         oracle_text = "Whenever a creature dies, draw a card.",
         cmc = 3, colors = "B", color_identity = "B", keywords = character())
  )
  registry <- query_synergy_event_registry_default()
  normalized <- lapply(raw, function(c) query_synergy_normalize_card(c, registry = registry))

  tmp <- tempfile(fileext = ".sqlite")
  on.exit(unlink(tmp), add = TRUE)
  build_enriched_db(tmp, normalized, query_synergy_precompute_version())

  status <- query_synergy_enriched_sqlite_status(tmp)
  expect_true(status$available)
  expect_true(status$version_match)
  expect_equal(status$rows, 2L)

  loaded <- query_synergy_catalog_normalized_from_sqlite(db_path = tmp)
  expect_true(is.list(loaded))
  expect_equal(length(loaded), 2L)
  expect_true(isTRUE(attr(loaded, "synergy_normalized")))
  expect_identical(attr(loaded, "synergy_source"), "enriched_sqlite")

  # Round-trip preserves model_version + key event vectors.
  expect_identical(loaded[[1]]$model_version, "normalized_card_v2")
  expect_identical(sort(loaded[[1]]$produced_events), sort(normalized[[1]]$produced_events))
  expect_identical(sort(loaded[[2]]$consumed_events), sort(normalized[[2]]$consumed_events))
  expect_identical(sort(loaded[[2]]$produced_events), sort(normalized[[2]]$produced_events))
})

test_that("precomputed-catalog build skips normalisation for pre-normalized input", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  skip_if_not_installed("jsonlite")

  raw <- list(list(
    id = "id-c", name = "Sample", type_line = "Creature",
    oracle_text = "Whenever a creature you control dies, draw a card.",
    cmc = 4, colors = "B", color_identity = "B", keywords = character()
  ))
  registry <- query_synergy_event_registry_default()
  normalized <- lapply(raw, function(c) query_synergy_normalize_card(c, registry = registry))

  tmp <- tempfile(fileext = ".sqlite")
  on.exit(unlink(tmp), add = TRUE)
  build_enriched_db(tmp, normalized, query_synergy_precompute_version())

  loaded <- query_synergy_catalog_normalized_from_sqlite(db_path = tmp)
  expect_true(isTRUE(attr(loaded, "synergy_normalized")))

  # Verify the build-precomputed step accepts already-normalized input and
  # produces a usable indexes structure.
  precomp <- query_synergy_build_precomputed_catalog(loaded, registry = registry)
  expect_equal(length(precomp$normalized), 1L)
  expect_equal(length(precomp$profiles), 1L)
  expect_true(is.list(precomp$indexes))
  # The normalized card stored in the precomputed bundle must be the loaded
  # record itself (i.e. we did not re-run normalize).
  expect_identical(precomp$normalized[[1]]$id, "id-c")
  expect_identical(precomp$normalized[[1]]$model_version, "normalized_card_v2")
})

test_that("precompute_version mismatch is reported as an error", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  skip_if_not_installed("jsonlite")

  raw <- list(list(id = "id-d", name = "X", type_line = "Land",
                   oracle_text = "{T}: Add {C}.", cmc = 0,
                   colors = character(), color_identity = character(), keywords = character()))
  registry <- query_synergy_event_registry_default()
  normalized <- lapply(raw, function(c) query_synergy_normalize_card(c, registry = registry))

  tmp <- tempfile(fileext = ".sqlite")
  on.exit(unlink(tmp), add = TRUE)
  build_enriched_db(tmp, normalized, "synergy_precompute_v_OLD")

  res <- query_synergy_catalog_normalized_from_sqlite(db_path = tmp)
  expect_false(isTRUE(res$ok))
  expect_true(grepl("precompute_version mismatch", res$error, fixed = TRUE))
})
