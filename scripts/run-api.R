args <- commandArgs(trailingOnly = TRUE)

host <- Sys.getenv("MTGCODEX_API_HOST", unset = "0.0.0.0")
port_raw <- Sys.getenv("MTGCODEX_API_PORT", unset = "8010")
swagger_raw <- Sys.getenv("MTGCODEX_API_SWAGGER", unset = "true")
worker_raw <- Sys.getenv("MTGCODEX_API_WORKER", unset = "")
worker_base_port_raw <- Sys.getenv("MTGCODEX_API_WORKER_BASE_PORT", unset = "8011")
project_dir <- normalizePath(
  Sys.getenv("MTGCODEX_API_PROJECT_DIR", unset = getwd()),
  winslash = "/",
  mustWork = FALSE
)

if (!dir.exists(project_dir)) {
  stop(sprintf("Project directory does not exist: %s", project_dir))
}

# A source checkout keeps its mutable development data inside the project.
# Production deployments can still override this location explicitly.
if (!nzchar(trimws(Sys.getenv("MTGCODEX_API_DATA_DIR", unset = "")))) {
  Sys.setenv(MTGCODEX_API_DATA_DIR = file.path(project_dir, ".local-data"))
}

port <- suppressWarnings(as.integer(port_raw))
if (is.na(port) || port < 1L || port > 65535L) {
  stop(sprintf("Invalid MTGCODEX_API_PORT value: %s", port_raw))
}

worker_id <- suppressWarnings(as.integer(worker_raw))
worker_base_port <- suppressWarnings(as.integer(worker_base_port_raw))
if (!is.na(worker_id)) {
  if (worker_id < 1L) {
    stop(sprintf("Invalid MTGCODEX_API_WORKER value: %s", worker_raw))
  }
  if (is.na(worker_base_port) || worker_base_port < 1L || worker_base_port > 65535L) {
    stop(sprintf(
      "Invalid MTGCODEX_API_WORKER_BASE_PORT value: %s",
      worker_base_port_raw
    ))
  }
  port <- worker_base_port + worker_id - 1L
  host <- "127.0.0.1"
}

to_bool <- function(value, default = TRUE) {
  normalized <- tolower(trimws(as.character(value)))
  if (!nzchar(normalized)) {
    return(default)
  }
  if (normalized %in% c("1", "true", "yes", "on")) {
    return(TRUE)
  }
  if (normalized %in% c("0", "false", "no", "off")) {
    return(FALSE)
  }
  default
}

swagger <- to_bool(swagger_raw, default = TRUE)

setwd(project_dir)

# Load the package namespace before Plumber evaluates its routing file. This
# lets query_call resolve both exported analysis functions and internal query
# adapters from one versioned namespace instead of mixing sourced adapters with
# missing analysis objects in .GlobalEnv.
if (!requireNamespace("mtgcodex.api", quietly = TRUE)) {
  stop("Package 'mtgcodex.api' must be installed before starting the API")
}
loadNamespace("mtgcodex.api")

start_api_file <- file.path(project_dir, "R", "start_api.R")
if (!file.exists(start_api_file)) {
  stop(sprintf("Unable to locate %s", start_api_file))
}

query_files <- list.files(
  path = file.path(project_dir, "R"),
  pattern = "^query_.*\\.R$",
  full.names = TRUE
)
for (query_file in query_files) {
  source(query_file, local = .GlobalEnv)
}

source(start_api_file, local = .GlobalEnv)
start_api(host = host, port = port, swagger = swagger)
