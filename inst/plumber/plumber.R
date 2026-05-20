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
        pattern = "^(query_|synergy_|bridge_|util_).*\\.R$",
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
#* @apiVersion 0.0.0.9000
#* @apiDescription A mechanics-first synergy engine for Magic: The Gathering.
#*
#* Models cards through normalized mechanical behaviour (produces, rewards,
#* requires, replaces, prevents, amplifies) to identify synergies, score pairs
#* bidirectionally, detect packages and combos, and generate decks.
#* A browser-based UI is available at `/ui/`.
#*
#* Source code and issue tracker:
#* [github.com/Andrameleck/mana-engine](https://github.com/Andrameleck/mana-engine)
#*
#* @apiTag System Health checks and server diagnostics
#* @apiTag Cards Card search, lookup, and mechanical normalization
#* @apiTag Collections Collection management — import, store, and track owned cards
#* @apiTag Synergy Synergy scoring, deck analysis, and deck generation
#* @apiTag Ontology Registered events, mechanics, archetypes, and formats
#* @apiTag Reference External data sources (Scryfall, MTGJSON, Spellbook, LotusNoir)
#* @apiTag Strategy Advanced deck strategy analysis (bridge equations)
NULL

#* Server health check
#*
#* Returns `{"ok": true, "status": "healthy"}` when the API is running correctly.
#* @tag System
#* @serializer unboxedJSON
#* @get /health
function() {
  query_call("query_health")
}

#* Submit user feedback
#*
#* Stores feedback (bug reports, suggestions, etc.) to a local NDJSON file and
#* optionally sends an email notification if SMTP env vars are configured.
#*
#* **JSON body fields:**
#* - `type` (string) — `"bug"`, `"suggestion"`, or `"other"` (default `"other"`)
#* - `message` (string, required) — feedback text
#* - `email` (string, optional) — reply-to address
#* - `client_id` (string, optional) — client identifier
#* @tag System
#* @serializer unboxedJSON
#* @post /feedback
function(req, res) {
  body <- tryCatch(
    jsonlite::fromJSON(req$postBody, simplifyVector = FALSE),
    error = function(e) list()
  )
  query_call(
    "query_feedback_submit",
    type      = body$type      %||% "",
    message   = body$message   %||% "",
    email     = body$email     %||% "",
    client_id = body$client_id %||% query_req_client_id(req)
  )
}

#* Load a collection from a source file (legacy)
#*
#* Parses a collection file from disk and returns the card records. Prefer
#* the `/collections` store endpoints for persistent collections.
#* @param type:[string] Source type: `db`, `csv`, or `text`.
#* @param path:[string] Absolute path to the source file on the server.
#* @param table:[string] Table name (only used when `type=db`).
#* @tag Collections
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

#* Upload and parse a collection file (legacy)
#*
#* Accepts a multipart form upload or raw `application/octet-stream` body.
#* Parses the file and returns the card records. Prefer `/collections/import_csv`
#* for persistent storage.
#* @param type:[string] Source type: `db`, `csv`, or `text`.
#* @param table:[string] Table name (only when `type=db`).
#* @param filename:[string] Optional hint for the file name.
#* @parser multi
#* @parser octet
#* @tag Collections
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

#* Import a CSV collection into the internal store
#*
#* Uploads a CSV file (ManaBox, Moxfield export, or generic format) and
#* stores it as a named collection in the local database. The collection is
#* then accessible via `/collections`.
#* @param name:[string] Display name for the collection.
#* @param platform:[string] Source platform hint: `manabox`, `moxfield`, `generic`, or `auto`.
#* @param filename:[string] Optional file name hint (for `application/octet-stream` uploads).
#* @parser multi
#* @parser octet
#* @tag Collections
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

#* List all stored collections
#*
#* Returns a summary list of all collections belonging to the current client,
#* including name, card count, and creation date.
#* @tag Collections
#* @serializer unboxedJSON
#* @get /collections
function(req) {
  query_call("query_collections_list", client_id = query_req_client_id(req))
}

#* Get one stored collection
#*
#* Returns the full card list of a stored collection. Each card record
#* includes name, quantity, set code, finish, and condition fields.
#* @param collection_id:[string] Collection identifier (UUID).
#* @tag Collections
#* @serializer unboxedJSON
#* @get /collections/<collection_id>
function(req, collection_id = "") {
  query_call(
    "query_collections_get",
    collection_id = collection_id,
    client_id = query_req_client_id(req)
  )
}

#* Delete a stored collection
#*
#* Permanently deletes a collection and all its card records from the store.
#* This operation cannot be undone.
#* @param collection_id:[string] Collection identifier (UUID).
#* @tag Collections
#* @serializer unboxedJSON
#* @delete /collections/<collection_id>
function(req, collection_id = "") {
  query_call(
    "query_collections_delete",
    collection_id = collection_id,
    client_id = query_req_client_id(req)
  )
}

#* Add a card to a stored collection
#*
#* Increases the quantity of a named card in the collection by `quantity`
#* (default 1). Creates a new card record if no matching row exists.
#* @param collection_id:[string] Collection identifier (UUID).
#* @param name:[string] Exact card name.
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
#* @param notes:[string] Optional freeform notes.
#* @tag Collections
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

#* Remove a card from a stored collection
#*
#* Decreases the quantity of a named card in the collection by `quantity`
#* (default 1). Deletes the row when quantity reaches zero.
#* @param collection_id:[string] Collection identifier (UUID).
#* @param name:[string] Exact card name.
#* @param quantity Quantity delta (default 1).
#* @param set_code Optional set code selector.
#* @param collector_number Optional collector number selector.
#* @param language Optional language code.
#* @param finish Optional finish selector.
#* @param card_condition Optional condition selector.
#* @param scryfall_id Optional Scryfall UUID.
#* @param notes:[string] Optional freeform notes.
#* @tag Collections
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

#* Import cards into the SQLite collection DB (low-level)
#*
#* Accepts a multipart or raw file upload and writes the parsed card records
#* into the SQLite collection database. Supports CSV and SQLite source files.
#* @param db_path:[string] Optional absolute path to the target SQLite file.
#* @param source_type:[string] Source type: `db`, `csv`, `text`, or `auto`.
#* @param source_table:[string] Table name when source is an SQLite DB.
#* @param filename:[string] File name hint (for `application/octet-stream` uploads).
#* @param dedupe:[boolean] Enable row deduplication (default `true`).
#* @parser multi
#* @parser octet
#* @tag Collections
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
#* @param dedupe:[boolean] Enable row deduplication (default `true`).
#* @tag Collections
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

#* Delete card(s) from the SQLite collection DB (low-level)
#*
#* Removes matching card records from the local SQLite database.
#* Supports filtering by name, set, Scryfall ID, or ManaBox ID.
#* @param db_path:[string] Optional path to the SQLite file (default: package DB).
#* @param id Optional collection row id.
#* @param manabox_id Optional ManaBox ID selector.
#* @param scryfall_id Optional Scryfall ID selector.
#* @param name Optional card name selector.
#* @param set_code Optional set code selector.
#* @param collector_number Optional collector number selector.
#* @param foil Optional foil selector.
#* @param language Optional language selector.
#* @param delete_all:[boolean] Delete all matching rows (default `false` — deletes only first match).
#* @tag Collections
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

#* Search combo variants from Commander Spellbook
#*
#* Queries the Commander Spellbook public database for known combo variants
#* that include the specified card. Returns combo steps, prerequisites, and
#* result descriptions.
#* @param q:[string] Card name seed (e.g. `Thassa's Oracle`).
#* @param limit:[integer] Maximum number of combo variants to return (1–100, default 40).
#* @tag Reference
#* @serializer unboxedJSON
#* @get /reference/spellbook/variants
function(q = "", limit = "40") {
  query_call(
    "query_spellbook_variants",
    q = q,
    limit = limit
  )
}

#* Search cards from MTGJSON
#*
#* Looks up card data from the local MTGJSON dataset. Useful for finding
#* printing-specific data (set codes, collector numbers, legalities, rulings).
#* @param q:[string] Partial card name search.
#* @param set_code:[string] Three-letter set code (e.g. `MH3`, `OTJ`).
#* @param collector_number:[string] Exact collector number within the set.
#* @param uuid:[string] MTGJSON UUID for direct card lookup.
#* @param limit:[integer] Maximum cards to return (1–200, default 40).
#* @tag Reference
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

#* Search LotusNoir deck articles
#*
#* Queries the LotusNoir.fr WordPress site for deck articles and guides
#* matching the search term. Returns post titles, URLs, and excerpts.
#* @param q:[string] Search query (card name or archetype, e.g. `Raffine`).
#* @param limit:[integer] Maximum posts to fetch (1–120, default 120).
#* @tag Reference
#* @serializer unboxedJSON
#* @get /reference/lotusnoir/posts
function(q = "", limit = "120") {
  query_call(
    "query_lotusnoir_posts",
    q = q,
    limit = limit
  )
}

#* Resolve a bridge equation A + n×k + B
#*
#* Analyses a pair of anchor cards A and B to find bridge cards k that
#* efficiently connect their mechanical profiles. The n multiplier controls
#* how many bridge copies to include.
#*
#* **JSON body fields:**
#* - `card_a` (string) — name of anchor card A
#* - `card_b` (string) — name of anchor card B
#* - `n` (integer, optional) — number of bridge slots (default 1)
#* - `limit` (integer, optional) — maximum candidates to return (default 20)
#* - `client_id` (string, optional) — client identifier for collection filtering
#* @tag Strategy
#* @serializer unboxedJSON
#* @post /strategy/bridge_equation
function(req, res) {
  query_call(
    "query_strategy_bridge_equation",
    req = req
  )
}

#* Normalize cards into atomic mechanics and events
#*
#* Parses one or more card oracle texts and returns their full normalized
#* mechanical profile: produced/consumed events, abilities, roles, cadence,
#* and strategy tags.
#*
#* **JSON body fields:**
#* - `cards` (array of objects) — each object must have `name` (string) and
#*   optionally `oracle_text`, `type_line`, `keywords`, `cmc`
#* - `card_names` (array of strings) — alternative: resolve by name from the
#*   local Scryfall oracle
#* @tag Cards
#* @serializer unboxedJSON
#* @post /cards/normalize
function(req, res) {
  query_call(
    "query_synergy_normalize_cards",
    req = req
  )
}

#* Find mechanical synergies for a target card
#*
#* Scores all cards in the synergy catalog against the target card and
#* returns the top matches ranked by bidirectional synergy score. Results
#* include the event overlap detail and role analysis.
#*
#* **JSON body fields:**
#* - `card_name` (string) — name of the target card
#* - `limit` (integer, optional) — max results to return (default 20)
#* - `collection_only` (boolean, optional) — restrict to owned cards
#* - `client_id` (string, optional) — client identifier for collection access
#* - `colors` (array of strings, optional) — filter by color identity
#* - `format` (string, optional) — legality filter (e.g. `commander`)
#* @tag Synergy
#* @serializer unboxedJSON
#* @post /synergy/find
function(req, res) {
  query_call(
    "query_synergy_find",
    req = req
  )
}

#* Recommend cards to improve a deck
#*
#* Analyses the mechanical profile of an entire deck and suggests cards that
#* best complement its existing synergy structure. Weights recommendations
#* by how many cards in the deck they interact with.
#*
#* **JSON body fields:**
#* - `deck` (array of strings or objects) — current deck card names
#* - `limit` (integer, optional) — max recommendations to return (default 20)
#* - `collection_only` (boolean, optional) — restrict to owned cards
#* - `client_id` (string, optional) — client identifier
#* - `colors` (array of strings, optional) — color identity filter
#* - `format` (string, optional) — legality filter (e.g. `commander`)
#* @tag Synergy
#* @serializer unboxedJSON
#* @post /synergy/deck/recommend
function(req, res) {
  query_call(
    "query_synergy_deck_recommend",
    req = req
  )
}

#* Generate a complete deck list
#*
#* Builds a full deck from scratch using the synergy engine, guided by
#* format, color identity, and archetype preferences. Returns a ranked
#* card list with slot assignments and synergy justifications.
#*
#* **JSON body fields:**
#* - `format` (string) — target format, e.g. `commander`, `modern`, `standard`
#* - `colors` (array of strings) — color identity, e.g. `["W","U","B"]`
#* - `archetypes` (array of strings, optional) — strategic archetypes,
#*   e.g. `["graveyard", "tokens"]`
#* - `commander` (string, optional) — Commander card name
#* - `collection_only` (boolean, optional) — use only owned cards
#* - `client_id` (string, optional) — client identifier
#* - `limit` (integer, optional) — max cards in the deck (default: format minimum)
#* @tag Synergy
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

#* Start an async deck generation job
#*
#* Identical parameters to `POST /synergy/deck/generate` but runs the
#* generation asynchronously. Returns a `job_id` immediately. Poll
#* `GET /synergy/jobs/<job_id>` for status and results.
#*
#* **JSON body fields:** same as `POST /synergy/deck/generate`.
#* @tag Synergy
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

#* Start an async synergy find job
#*
#* Identical parameters to `POST /synergy/find` but runs asynchronously.
#* Returns a `job_id` immediately. Poll `GET /synergy/jobs/<job_id>` for
#* progress and results.
#*
#* **JSON body fields:** same as `POST /synergy/find`.
#* @tag Synergy
#* @serializer unboxedJSON
#* @post /synergy/jobs/start
function(req, res) {
  query_call(
    "query_synergy_start_job",
    req = req
  )
}

#* Get a background job status and results
#*
#* Polls the status of an async synergy or deck generation job. Returns
#* `status` (`pending`, `running`, `done`, or `error`), a progress
#* percentage, and — when `status=done` — the full result payload.
#* @param job_id:[string] Job identifier returned by a `jobs/start` endpoint.
#* @tag Synergy
#* @serializer unboxedJSON
#* @get /synergy/jobs/<job_id>
function(job_id = "") {
  query_call(
    "query_synergy_get_job_status",
    job_id = job_id
  )
}

#* Search cards from the local Scryfall oracle library
#*
#* Full-text and filtered search against the local Scryfall oracle database.
#* Supports pagination via `limit` and `offset`.
#* @param q:[string] Free-text search on card name and oracle text.
#* @param colors:[string] Required color identity — comma-separated codes, e.g. `W,U`.
#* @param cmc_min:[integer] Minimum converted mana cost.
#* @param cmc_max:[integer] Maximum converted mana cost.
#* @param type_line:[string] Partial match on type line, e.g. `Creature`, `Instant`.
#* @param keywords:[string] Partial match on keyword abilities, e.g. `Flying`, `Lifelink`.
#* @param collection_only:[boolean] Restrict results to cards present in the client's collection.
#* @param limit:[integer] Maximum results to return (default 60, max 200).
#* @param offset:[integer] Pagination offset (default 0).
#* @tag Cards
#* @serializer unboxedJSON
#* @get /cards/search
function(q = "", colors = "", cmc_min = "", cmc_max = "",
         type_line = "", keywords = "", collection_only = "",
         limit = "60", offset = "0") {
  query_call(
    "query_card_search",
    q                = q,
    colors           = colors,
    cmc_min          = cmc_min,
    cmc_max          = cmc_max,
    type_line        = type_line,
    keywords         = keywords,
    collection_only  = collection_only,
    limit            = limit,
    offset           = offset
  )
}

#* Get a single card from the Scryfall oracle catalog
#*
#* Returns full oracle data for a card identified by its Scryfall UUID or
#* exact name. Optionally includes the full normalized mechanical profile.
#* @param card_id:[string] Scryfall UUID or exact card name (e.g. `Lightning Bolt`).
#* @param include_normalized:[boolean] Include the normalized mechanical payload (default `true`).
#* @tag Cards
#* @serializer unboxedJSON
#* @get /cards/<card_id>
function(card_id = "", include_normalized = "true") {
  query_call(
    "query_synergy_get_card",
    card_id = card_id,
    include_normalized = include_normalized
  )
}

#* List all registered atomic gameplay events
#*
#* Returns the full event ontology: every atomic mechanic event the engine
#* understands (e.g. `DRAW_CARD`, `CREATE_TOKEN`, `ETB`, `DIES`), with
#* parent–child hierarchy, aliases, and tags.
#* @tag Ontology
#* @serializer unboxedJSON
#* @get /events
function() {
  query_call("query_synergy_list_events")
}

#* List all mechanic decomposition rules
#*
#* Returns the full set of keyword-to-event expansion rules. Each entry
#* shows which events a mechanic produces, consumes, or replaces, and
#* which strategy tags it carries (e.g. `cycling` → produces `DRAW_CARD` +
#* `DISCARD_CARD`).
#* @tag Ontology
#* @serializer unboxedJSON
#* @get /mechanics
function() {
  query_call("query_synergy_list_mechanics")
}

#* List all registered strategic archetypes
#*
#* Returns the catalogue of supported deck archetypes (e.g. `graveyard`,
#* `tokens`, `spellslinger`, `ramp`) with their defining event profiles
#* and strategy tag sets.
#* @tag Ontology
#* @serializer unboxedJSON
#* @get /archetypes
function() {
  query_call("query_synergy_list_archetypes")
}

#* List all supported play formats
#*
#* Returns the formats the engine can filter legality by
#* (e.g. `commander`, `modern`, `standard`, `legacy`).
#* @tag Ontology
#* @serializer unboxedJSON
#* @get /formats
function() {
  query_call("query_synergy_list_formats")
}

#* Load a synergy catalog from a local SQLite database
#*
#* Reads pre-computed synergy records from a SQLite database (typically the
#* `cards_api` table produced by a bulk normalization run). Useful for
#* inspecting or exporting the engine's catalog.
#* @param db_path:[string] Absolute path to the SQLite file (default: package DB).
#* @param table:[string] Table name to read (default: `cards_api`).
#* @param where:[string] Optional SQL WHERE clause (without the `WHERE` keyword).
#* @param limit:[integer] Maximum rows to return.
#* @tag Synergy
#* @serializer unboxedJSON
#* @get /synergy/catalog/sqlite
function(db_path = "", table = "cards_api", where = "", limit = "") {
  res <- query_call(
    "query_synergy_catalog_from_sqlite",
    db_path = if (nzchar(db_path)) db_path else NULL,
    table = table,
    where = if (nzchar(where)) where else NULL,
    limit = if (nzchar(limit)) as.integer(limit) else NULL
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
