# Resolve query_* functions either from installed package namespace
# or from local R/ files during development.
query_call <- local({
  ns <- NULL
  if ("MTGCODEX" %in% loadedNamespaces()) {
    ns <- asNamespace("MTGCODEX")
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

#* @apiTitle MTGCODEX API
#* @apiDescription API routes delegate to query_* functions in R/
NULL

#* Healthcheck
#* @serializer unboxedJSON
#* @get /health
function() {
  query_call("query_health")
}

#* Check card/deck request
#* @param card_name Card name to check.
#* @param deck_name Deck name to check.
#* @serializer unboxedJSON
#* @get /collection/check
function(card_name = "", deck_name = "") {
  query_call("query_check_collection", card_name = card_name, deck_name = deck_name)
}

#* MDB connection status and tooling check
#* @serializer unboxedJSON
#* @get /mdb/status
function() {
  query_call("query_mdb_status")
}

#* List tables from MDB
#* @serializer unboxedJSON
#* @get /mdb/tables
function() {
  query_call("query_mdb_list_tables")
}

#* Preview rows from an MDB table
#* @param name Table name.
#* @param limit Maximum row count.
#* @serializer unboxedJSON
#* @get /mdb/table
function(name = "", limit = 100L) {
  query_call("query_mdb_table_preview", name = name, limit = limit)
}

#* UI entrypoint
#* @serializer contentType list(type="text/html; charset=utf-8")
#* @get /ui
function() {
  query_call("query_ui_index_html")
}

#* Static assets for Web UI
#* @param file Asset file name.
#* @serializer text
#* @get /ui/static/<file>
function(file, res) {
  query_call("query_ui_static_asset", file = file, res = res)
}
