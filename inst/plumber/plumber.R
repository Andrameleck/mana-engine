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
