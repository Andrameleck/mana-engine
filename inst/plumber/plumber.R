# Resolve query_* functions either from installed package namespace
# or from local R/ files during development.
query_call <- local({
  ns <- NULL
  if ("mtgcodex.api" %in% loadedNamespaces()) {
    ns <- asNamespace("mtgcodex.api")
  }

  if (is.null(ns)) {
    query_dir_candidates <- c(
      file.path(getwd(), "R"),
      file.path(getwd(), "..", "R")
    )
    query_dir_exists <- vapply(query_dir_candidates, dir.exists, logical(1))
    if (any(query_dir_exists)) {
      query_dir <- query_dir_candidates[which(query_dir_exists)[1]]
      query_files <- list.files(
        path = query_dir,
        pattern = "^(query_|synergy_).*\\.R$",
        full.names = TRUE
      )
      for (query_file in query_files) {
        source(query_file, local = .GlobalEnv)
      }
    }
  }

  function(fun_name, ...) {
    if (!is.null(ns)) {
      fun <- get(fun_name, envir = ns, inherits = FALSE)
      return(fun(...))
    }
    fun <- get(fun_name, mode = "function", inherits = TRUE)
    fun(...)
  }
})

query_req_scalar <- function(req, key, default = "") {
  query_call(
    "query_api_scalar_arg",
    req = req,
    key = key,
    default = default
  )
}

query_req_client_id <- function(req) {
  from_query <- query_req_scalar(req, "client_id", "")
  if (nzchar(from_query)) {
    return(from_query)
  }

  from_header <- trimws(as.character(req$HTTP_X_MANA_ENGINE_CLIENT_ID %||% ""))
  if (nzchar(from_header)) {
    return(from_header)
  }

  from_header <- trimws(as.character(req$HTTP_X_MTGCODEX_CLIENT_ID %||% ""))
  if (nzchar(from_header)) {
    return(from_header)
  }

  "anon"
}

`%||%` <- function(left, right) {
  if (is.null(left) || length(left) == 0L) {
    return(right)
  }
  left
}

#* @apiTitle Mana-Engine API
#* @apiDescription API routes delegate to query_* functions in R/
NULL

#* Healthcheck
#* @serializer unboxedJSON
#* @get /health
function() {
  query_call("query_health")
}

#* Load collection from a source file
#* @param type Source type: db, csv, or text.
#* @param path Source file path.
#* @param table Table name when `type=db`.
#* @serializer unboxedJSON
#* @get /collection/load
function(type = "", path = "", table = "") {
  query_call(
    "query_collection_load",
    type = type,
    path = path,
    table = table
  )
}

#* Upload and load a collection file
#* @param type Source type: db, csv, or text.
#* @param table Table name when `type=db`.
#* @param filename Optional file name when sending application/octet-stream.
#* @parser multi
#* @parser octet
#* @serializer unboxedJSON
#* @post /collection/upload
function(req, res, type = "", table = "", filename = "") {
  query_call(
    "query_collection_upload",
    req = req,
    type = type,
    table = table,
    filename = filename
  )
}

#* Import a public CSV collection into internal DB store
#* @param name Collection display name.
#* @param platform Optional source platform name.
#* @param filename Optional file name when sending application/octet-stream.
#* @parser multi
#* @parser octet
#* @serializer unboxedJSON
#* @post /collections/import_csv
function(req, res, name = "", platform = "auto", filename = "") {
  client_id <- query_req_client_id(req)
  query_call(
    "query_collections_import_csv",
    req = req,
    name = name,
    platform = platform,
    filename = filename,
    client_id = client_id
  )
}

#* List stored collections
#* @serializer unboxedJSON
#* @get /collections
function(req) {
  query_call("query_collections_list", client_id = query_req_client_id(req))
}

#* Get one stored collection content
#* @param collection_id Collection identifier.
#* @serializer unboxedJSON
#* @get /collections/<collection_id>
function(req, collection_id = "") {
  query_call(
    "query_collections_get",
    collection_id = collection_id,
    client_id = query_req_client_id(req)
  )
}

#* Delete one stored collection
#* @param collection_id Collection identifier.
#* @serializer unboxedJSON
#* @delete /collections/<collection_id>
function(req, collection_id = "") {
  query_call(
    "query_collections_delete",
    collection_id = collection_id,
    client_id = query_req_client_id(req)
  )
}

#* Add one card quantity to a stored collection
#* @param collection_id Collection identifier.
#* @param name Card name.
#* @param quantity Quantity delta (default 1).
#* @param set_code Optional set code selector.
#* @param collector_number Optional collector number selector.
#* @param mana_cost Optional mana cost for inserted cards.
#* @param oracle_text Optional oracle text for inserted cards.
#* @param keywords Optional keywords for inserted cards.
#* @param language Optional language code.
#* @param finish Optional finish selector.
#* @param card_condition Optional condition selector.
#* @param scryfall_id Optional Scryfall UUID.
#* @param notes Optional notes selector.
#* @serializer unboxedJSON
#* @post /collections/<collection_id>/cards/add
function(req,
         collection_id = "",
         name = "",
         quantity = "1",
         set_code = "",
         collector_number = "",
         mana_cost = "",
         oracle_text = "",
         keywords = "",
         language = "en",
         finish = "",
         card_condition = "",
         scryfall_id = "",
         notes = "") {
  query_call(
    "query_collections_add_card",
    collection_id = collection_id,
    client_id = query_req_client_id(req),
    name = name,
    quantity = quantity,
    set_code = set_code,
    collector_number = collector_number,
    mana_cost = mana_cost,
    oracle_text = oracle_text,
    keywords = keywords,
    language = language,
    finish = finish,
    card_condition = card_condition,
    scryfall_id = scryfall_id,
    notes = notes
  )
}

#* Remove one card quantity from a stored collection
#* @param collection_id Collection identifier.
#* @param name Card name.
#* @param quantity Quantity delta (default 1).
#* @param set_code Optional set code selector.
#* @param collector_number Optional collector number selector.
#* @param language Optional language code.
#* @param finish Optional finish selector.
#* @param card_condition Optional condition selector.
#* @param scryfall_id Optional Scryfall UUID.
#* @param notes Optional notes selector.
#* @serializer unboxedJSON
#* @post /collections/<collection_id>/cards/remove
function(req,
         collection_id = "",
         name = "",
         quantity = "1",
         set_code = "",
         collector_number = "",
         language = "en",
         finish = "",
         card_condition = "",
         scryfall_id = "",
         notes = "") {
  query_call(
    "query_collections_remove_card",
    collection_id = collection_id,
    client_id = query_req_client_id(req),
    name = name,
    quantity = quantity,
    set_code = set_code,
    collector_number = collector_number,
    language = language,
    finish = finish,
    card_condition = card_condition,
    scryfall_id = scryfall_id,
    notes = notes
  )
}

#* Import cards into SQLite collection DB (source file can be CSV or DB)
#* @param db_path Optional target sqlite path (default: package mtg.db).
#* @param source_type Optional source type: db, csv, text, or auto.
#* @param source_table Optional source table name when source is db.
#* @param filename Optional file name when sending application/octet-stream.
#* @param dedupe Enable deduplication (true/false).
#* @parser multi
#* @parser octet
#* @serializer unboxedJSON
#* @post /collection/db/import
function(req, res) {
  db_path <- query_req_scalar(req, "db_path", "")
  source_type <- query_req_scalar(req, "source_type", "")
  source_table <- query_req_scalar(req, "source_table", "")
  filename <- query_req_scalar(req, "filename", "")
  dedupe <- query_req_scalar(req, "dedupe", "true")

  query_call(
    "query_collection_db_import",
    req = req,
    db_path = db_path,
    source_type = source_type,
    source_table = source_table,
    filename = filename,
    dedupe = dedupe
  )
}

#* Add one card into SQLite collection DB
#* @param db_path Optional target sqlite path (default: package mtg.db).
#* @param name Card name.
#* @param quantity Quantity (default 1).
#* @param set_code Set code.
#* @param set_name Set name.
#* @param collector_number Collector number.
#* @param foil Foil/finish (normal or foil).
#* @param rarity Rarity.
#* @param language Language code (default en).
#* @param scryfall_id Scryfall UUID.
#* @param manabox_id Optional ManaBox ID.
#* @param purchase_price Optional purchase price.
#* @param purchase_price_currency Optional currency code (default EUR).
#* @param misprint Misprint flag.
#* @param altered Altered flag.
#* @param condition Card condition.
#* @param dedupe Enable deduplication (true/false).
#* @serializer unboxedJSON
#* @post /collection/db/add_card
function(db_path = "",
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
  query_call(
    "query_collection_db_add_card",
    db_path = db_path,
    name = name,
    quantity = quantity,
    set_code = set_code,
    set_name = set_name,
    collector_number = collector_number,
    foil = foil,
    rarity = rarity,
    language = language,
    scryfall_id = scryfall_id,
    manabox_id = manabox_id,
    purchase_price = purchase_price,
    purchase_price_currency = purchase_price_currency,
    misprint = misprint,
    altered = altered,
    condition = condition,
    dedupe = dedupe
  )
}

#* Delete card(s) from SQLite collection DB
#* @param db_path Optional target sqlite path (default: package mtg.db).
#* @param id Optional collection row id.
#* @param manabox_id Optional ManaBox ID selector.
#* @param scryfall_id Optional Scryfall ID selector.
#* @param name Optional card name selector.
#* @param set_code Optional set code selector.
#* @param collector_number Optional collector number selector.
#* @param foil Optional foil selector.
#* @param language Optional language selector.
#* @param delete_all Delete all matching rows (true/false).
#* @serializer unboxedJSON
#* @delete /collection/db/delete_card
function(db_path = "",
         id = "",
         manabox_id = "",
         scryfall_id = "",
         name = "",
         set_code = "",
         collector_number = "",
         foil = "",
         language = "",
         delete_all = "false") {
  query_call(
    "query_collection_db_delete_card",
    db_path = db_path,
    id = id,
    manabox_id = manabox_id,
    scryfall_id = scryfall_id,
    name = name,
    set_code = set_code,
    collector_number = collector_number,
    foil = foil,
    language = language,
    delete_all = delete_all
  )
}

#* Search combo references from Commander Spellbook
#* @param q Card seed query.
#* @param limit Max combo variants to fetch (1-100).
#* @serializer unboxedJSON
#* @get /reference/spellbook/variants
function(q = "", limit = "40") {
  query_call(
    "query_spellbook_variants",
    q = q,
    limit = limit
  )
}

#* Search card references from MTGJSON
#* @param q Card name query (optional).
#* @param set_code Set code (recommended for set lookups).
#* @param collector_number Exact collector number (optional).
#* @param uuid MTGJSON card UUID (direct lookup).
#* @param limit Max cards to return (1-200).
#* @serializer unboxedJSON
#* @get /reference/mtgjson/cards
function(q = "", set_code = "", collector_number = "", uuid = "", limit = "40") {
  query_call(
    "query_mtgjson_cards",
    q = q,
    set_code = set_code,
    collector_number = collector_number,
    uuid = uuid,
    limit = limit
  )
}

#* Search LotusNoir public posts (WordPress search endpoint)
#* @param q Search query.
#* @param limit Max posts to fetch (1-120).
#* @serializer unboxedJSON
#* @get /reference/lotusnoir/posts
function(q = "", limit = "120") {
  query_call(
    "query_lotusnoir_posts",
    q = q,
    limit = limit
  )
}

#* Resolve bridge equation A + n*k + B from strategy cards
#* @serializer unboxedJSON
#* @post /strategy/bridge_equation
function(req, res) {
  query_call(
    "query_strategy_bridge_equation",
    req = req
  )
}

#* Normalize one or more cards into atomic mechanics/events
#* @serializer unboxedJSON
#* @post /cards/normalize
function(req, res) {
  query_call(
    "query_synergy_normalize_cards",
    req = req
  )
}

#* Find mechanical synergies for one target card
#* @serializer unboxedJSON
#* @post /synergy/find
function(req, res) {
  query_call(
    "query_synergy_find",
    req = req
  )
}

#* Recommend cards to improve a whole deck (deck-wide synergy analysis)
#* @serializer unboxedJSON
#* @post /synergy/deck/recommend
function(req, res) {
  query_call(
    "query_synergy_deck_recommend",
    req = req
  )
}

#* Generate complete deck lists from format + colors + archetypes
#* @serializer unboxedJSON
#* @post /synergy/deck/generate
function(req, res) {
  # Inject client_id from the request header into the parsed body so the
  # deck generator can authenticate collection access transparently.
  client_id <- query_req_client_id(req)
  if (nzchar(client_id)) {
    body <- tryCatch(jsonlite::fromJSON(req$postBody, simplifyVector = FALSE), error = function(e) list())
    if (!nzchar(body$client_id %||% "")) {
      body$client_id <- client_id
      req$postBody <- jsonlite::toJSON(body, auto_unbox = TRUE)
    }
  }
  query_call(
    "query_synergy_deck_generate",
    req = req
  )
}

#* Start an async background deck generation job with progress reporting
#* @serializer unboxedJSON
#* @post /synergy/deck/jobs/start
function(req, res) {
  client_id <- query_req_client_id(req)
  if (nzchar(client_id)) {
    body <- tryCatch(jsonlite::fromJSON(req$postBody, simplifyVector = FALSE), error = function(e) list())
    if (!nzchar(body$client_id %||% "")) {
      body$client_id <- client_id
      req$postBody <- jsonlite::toJSON(body, auto_unbox = TRUE)
    }
  }
  query_call(
    "query_synergy_deck_generate_job",
    req = req
  )
}

#* Start a background mechanical synergy job with progress reporting
#* @serializer unboxedJSON
#* @post /synergy/jobs/start
function(req, res) {
  query_call(
    "query_synergy_start_job",
    req = req
  )
}

#* Fetch one background mechanical synergy job status
#* @param job_id Job identifier.
#* @serializer unboxedJSON
#* @get /synergy/jobs/<job_id>
function(job_id = "") {
  query_call(
    "query_synergy_get_job_status",
    job_id = job_id
  )
}

#* Fetch one card from the Scryfall oracle catalog
#* @param card_id Card UUID or card name.
#* @param include_normalized Include normalized payload (true/false).
#* @serializer unboxedJSON
#* @get /cards/<card_id>
function(card_id = "", include_normalized = "true") {
  query_call(
    "query_synergy_get_card",
    card_id = card_id,
    include_normalized = include_normalized
  )
}

#* List registered atomic gameplay events
#* @serializer unboxedJSON
#* @get /events
function() {
  query_call("query_synergy_list_events")
}

#* List mechanic decomposition rules
#* @serializer unboxedJSON
#* @get /mechanics
function() {
  query_call("query_synergy_list_mechanics")
}

#* List registered strategic archetypes
#* @serializer unboxedJSON
#* @get /archetypes
function() {
  query_call("query_synergy_list_archetypes")
}

#* List supported play formats
#* @serializer unboxedJSON
#* @get /formats
function() {
  query_call("query_synergy_list_formats")
}

#* Load a synergy catalog from a local SQLite database (cards_api table)
#* @param db_path Optional absolute path to the SQLite file.
#* @param table Optional table name (default: cards_api).
#* @param where Optional WHERE clause without the keyword.
#* @param limit Optional integer cap on rows returned.
#* @serializer unboxedJSON
#* @get /synergy/catalog/sqlite
function(db_path = NULL, table = "cards_api", where = NULL, limit = NULL) {
  res <- query_call(
    "query_synergy_catalog_from_sqlite",
    db_path = db_path,
    table = table,
    where = where,
    limit = limit
  )
  if (is.list(res) && isFALSE(res$ok) && nzchar(query_api_scalar(res$error, default = ""))) {
    return(res)
  }
  list(
    ok = TRUE,
    source = attr(res, "synergy_source") %||% "sqlite_cards",
    cache_key = attr(res, "synergy_cache_key") %||% "",
    count = length(res)
  )
}

#* UI entrypoint
#* @serializer contentType list(type="text/html; charset=utf-8")
#* @get /ui
function(res) {
  query_call("query_ui_index_html", res = res)
}

#* Static assets for Web UI
#* @param file Asset file name.
#* @get /ui/static/<file>
function(file, res) {
  query_call("query_ui_static_asset", file = file, res = res)
  res
}
