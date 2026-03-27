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
        pattern = "^query_.*\\.R$",
        full.names = TRUE
      )
      for (query_file in query_files) {
        source(query_file)
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

#* @apiTitle mtgcodex.api API
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
  query_call(
    "query_collections_import_csv",
    req = req,
    name = name,
    platform = platform,
    filename = filename
  )
}

#* List stored collections
#* @serializer unboxedJSON
#* @get /collections
function() {
  query_call("query_collections_list")
}

#* Get one stored collection content
#* @param collection_id Collection identifier.
#* @serializer unboxedJSON
#* @get /collections/<collection_id>
function(collection_id = "") {
  query_call(
    "query_collections_get",
    collection_id = collection_id
  )
}

#* Delete one stored collection
#* @param collection_id Collection identifier.
#* @serializer unboxedJSON
#* @delete /collections/<collection_id>
function(collection_id = "") {
  query_call(
    "query_collections_delete",
    collection_id = collection_id
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

#* UI entrypoint
#* @serializer contentType list(type="text/html; charset=utf-8")
#* @get /ui
function() {
  query_call("query_ui_index_html")
}

#* Static assets for Web UI
#* @param file Asset file name.
#* @get /ui/static/<file>
function(file, res) {
  query_call("query_ui_static_asset", file = file, res = res)
  res
}
