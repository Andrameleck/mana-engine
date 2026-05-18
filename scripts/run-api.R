args <- commandArgs(trailingOnly = TRUE)

env_value <- function(primary, legacy, default = "") {
  value <- Sys.getenv(primary, unset = "")
  if (nzchar(value)) {
    return(value)
  }
  Sys.getenv(legacy, unset = default)
}

host <- env_value("MANA_ENGINE_API_HOST", "MTGCODEX_API_HOST", "0.0.0.0")
port_raw <- env_value("MANA_ENGINE_API_PORT", "MTGCODEX_API_PORT", "8010")
swagger_raw <- env_value("MANA_ENGINE_API_SWAGGER", "MTGCODEX_API_SWAGGER", "true")
worker_raw <- env_value("MANA_ENGINE_API_WORKER", "MTGCODEX_API_WORKER", "")
worker_base_port_raw <- env_value("MANA_ENGINE_API_WORKER_BASE_PORT", "MTGCODEX_API_WORKER_BASE_PORT", "8011")
project_dir <- normalizePath(
  env_value("MANA_ENGINE_API_PROJECT_DIR", "MTGCODEX_API_PROJECT_DIR", getwd()),
  winslash = "/",
  mustWork = FALSE
)

if (!dir.exists(project_dir)) {
  stop(sprintf("Project directory does not exist: %s", project_dir))
}

port <- suppressWarnings(as.integer(port_raw))
if (is.na(port) || port < 1L || port > 65535L) {
  stop(sprintf("Invalid MANA_ENGINE_API_PORT value: %s", port_raw))
}

worker_id <- suppressWarnings(as.integer(worker_raw))
worker_base_port <- suppressWarnings(as.integer(worker_base_port_raw))
if (!is.na(worker_id)) {
  if (worker_id < 1L) {
    stop(sprintf("Invalid MANA_ENGINE_API_WORKER value: %s", worker_raw))
  }
  if (is.na(worker_base_port) || worker_base_port < 1L || worker_base_port > 65535L) {
    stop(sprintf(
      "Invalid MANA_ENGINE_API_WORKER_BASE_PORT value: %s",
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

start_api_file <- file.path(project_dir, "R", "start_api.R")
if (!file.exists(start_api_file)) {
  stop(sprintf("Unable to locate %s", start_api_file))
}

query_files <- list.files(
  path = file.path(project_dir, "R"),
  pattern = "^(query_|synergy_).*\\.R$",
  full.names = TRUE
)
for (query_file in query_files) {
  source(query_file, local = .GlobalEnv)
}

source(start_api_file, local = .GlobalEnv)
start_api(host = host, port = port, swagger = swagger)
