args <- commandArgs(trailingOnly = TRUE)

arg_value <- function(flag, default = "") {
  index <- match(flag, args)
  if (is.na(index) || index >= length(args)) {
    return(default)
  }
  trimws(as.character(args[[index + 1L]]))
}

job_id       <- arg_value("--job-id",  "")
payload_path <- arg_value("--payload", "")
status_path  <- arg_value("--status",  "")
result_path  <- arg_value("--result",  "")
repo_path    <- arg_value("--repo",    "")

if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("jsonlite package is required")
}

write_job_json <- function(path, payload) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp")
  jsonlite::write_json(payload, path = tmp, auto_unbox = TRUE, pretty = FALSE, null = "null")
  if (file.exists(path)) {
    unlink(path)
  }
  file.rename(tmp, path)
  invisible(path)
}

build_status <- function(status = "queued", percent = 0, stage = "", error = "", meta = list()) {
  list(
    ok      = TRUE,
    job_id  = job_id,
    status  = status,
    error   = error,
    progress = list(
      percent    = as.integer(round(max(0, min(100, suppressWarnings(as.numeric(percent)) %||% 0)))),
      stage      = stage,
      updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      meta       = if (is.list(meta)) meta else list()
    )
  )
}

`%||%` <- function(left, right) {
  if (is.null(left) || length(left) == 0L) return(right)
  left
}

call_query <- local({
  ns        <- NULL
  repo_root <- trimws(as.character(repo_path))
  if (!nzchar(repo_root)) repo_root <- getwd()
  query_dir <- file.path(repo_root, "R")

  if (dir.exists(query_dir)) {
    query_files <- list.files(
      query_dir,
      pattern    = "^(query_|synergy_|bridge_|util_).*\\.R$",
      full.names = TRUE
    )
    for (query_file in query_files) {
      source(query_file, local = .GlobalEnv)
    }
  } else if (requireNamespace("mtgcodex.api", quietly = TRUE)) {
    ns <- asNamespace("mtgcodex.api")
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

status_state <- new.env(parent = emptyenv())
status_state$last_percent <- -1
status_state$last_at      <- as.numeric(Sys.time()) - 10

progress_callback <- function(progress) {
  now_value <- as.numeric(Sys.time())
  percent   <- as.integer(round(suppressWarnings(as.numeric(progress$percent %||% 0))))
  stage     <- trimws(as.character(progress$stage %||% "Running"))
  should_write <- percent >= 100L ||
    percent <= 0L ||
    (percent - status_state$last_percent) >= 1L ||
    (now_value - status_state$last_at) >= 0.75
  if (!isTRUE(should_write)) return(invisible(NULL))

  status_state$last_percent <- percent
  status_state$last_at      <- now_value
  write_job_json(
    status_path,
    build_status(
      status  = if (percent >= 100L) "completed" else "running",
      percent = percent,
      stage   = stage,
      meta    = progress$meta
    )
  )
  invisible(NULL)
}

tryCatch({
  payload <- jsonlite::fromJSON(payload_path, simplifyVector = FALSE)
  write_job_json(status_path, build_status(status = "running", percent = 1, stage = "Starting deck generation job"))

  result <- call_query(
    "query_synergy_deck_generate_from_payload",
    payload           = payload,
    progress_callback = progress_callback
  )

  write_job_json(result_path, result)
  write_job_json(status_path, build_status(status = "completed", percent = 100, stage = "Completed"))
}, error = function(e) {
  message_text <- conditionMessage(e)
  write_job_json(status_path, build_status(
    status  = "error",
    percent = max(0L, status_state$last_percent),
    stage   = "Failed",
    error   = message_text
  ))
  quit(status = 1L)
})
