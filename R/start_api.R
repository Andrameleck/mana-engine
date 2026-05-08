start_api <- function(
    host = "0.0.0.0",
    port = 8000L,
    swagger = TRUE,
    hide_ui_from_swagger = TRUE,
    ...) {
  if (!is.character(host) || length(host) != 1L || !nzchar(trimws(host))) {
    stop("`host` must be a non-empty character scalar.")
  }

  valid_port <- is.numeric(port) &&
    length(port) == 1L &&
    !is.na(port) &&
    port == as.integer(port) &&
    as.integer(port) >= 1L &&
    as.integer(port) <= 65535L
  if (!valid_port) {
    stop("`port` must be an integer between 1 and 65535.")
  }
  port <- as.integer(port)

  if (!requireNamespace("plumber", quietly = TRUE)) {
    stop("Package 'plumber' is required. Please install it first.")
  }

  .start_api_log("info", "Initializing mtgcodex.api API on %s:%s", host, port)

  api_file <- file.path(getwd(), "inst", "plumber", "plumber.R")
  if (!file.exists(api_file)) {
    api_file <- system.file("plumber", "plumber.R", package = "mtgcodex.api")
  }
  if (!file.exists(api_file)) {
    .start_api_log("error", "Unable to locate inst/plumber/plumber.R")
    stop("Unable to locate inst/plumber/plumber.R")
  }

  api <- tryCatch(
    plumber::plumb(api_file),
    error = function(e) {
      .start_api_log("error", "Plumbing failed: %s", e$message)
      stop(e)
    }
  )

  api <- plumber::pr_get(api, "/", function(res) {
    res$status <- 302L
    res$setHeader("Location", "/ui")
    list()
  })

  if (isTRUE(hide_ui_from_swagger)) {
    spec <- api$getApiSpec()
    if (!is.null(spec$paths) && length(spec$paths) > 0) {
      path_names <- names(spec$paths)
      keep <- !(path_names == "/" | grepl("^/ui(/|$)", path_names))
      spec$paths <- spec$paths[keep]
      api$setApiSpec(spec)
    }
  }

  .start_api_log("info", "Starting API at http://%s:%s/", host, port)
  tryCatch(
    api$run(host = host, port = port, swagger = swagger, ...),
    error = function(e) {
      .start_api_log("error", "API startup failed: %s", e$message)
      stop(e)
    }
  )

  invisible(NULL)
}

.start_api_log <- function(level, fmt, ...) {
  text <- sprintf(fmt, ...)

  if (requireNamespace("logger", quietly = TRUE)) {
    fun <- switch(
      tolower(level),
      "debug" = logger::log_debug,
      "warn" = ,
      "warning" = logger::log_warn,
      "error" = logger::log_error,
      logger::log_info
    )
    fun(text)
    return(invisible(NULL))
  }

  message(sprintf("[%s] %s", toupper(level), text))
  invisible(NULL)
}
