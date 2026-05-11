#!/usr/bin/env sh
set -eu

cd "${MTGCODEX_API_PROJECT_DIR:-/app}"

cache_dir="${MTGCODEX_SYNERGY_CACHE_DIR:-/data/cache/mtgcodex.api}"
db_path="${SCRYFALL_DB_PATH:-$cache_dir/all_cards.sqlite}"
bootstrap="${MTGCODEX_SCRYFALL_BOOTSTRAP:-auto}"

export MTGCODEX_SYNERGY_CACHE_DIR="$cache_dir"
export SCRYFALL_DB_PATH="$db_path"

needs_enrichment() {
  DB_PATH="$db_path" Rscript -e '
    db <- Sys.getenv("DB_PATH")
    if (!file.exists(db)) quit(status = 0)
    r_files <- list.files("R", pattern = "\\.R$", full.names = TRUE)
    for (f in r_files) suppressMessages(source(f, local = FALSE, encoding = "UTF-8"))
    status <- tryCatch(
      query_synergy_enriched_sqlite_status(db),
      error = function(e) list(available = FALSE, version_match = FALSE)
    )
    ready <- isTRUE(status$available) && isTRUE(status$version_match)
    quit(status = if (ready) 1 else 0)
  '
}

mkdir -p "$cache_dir"
lock_file="$cache_dir/.init.lock"

case "$bootstrap" in
  0|false|FALSE|off|OFF|no|NO)
    echo "[docker] Scryfall bootstrap disabled"
    ;;
  force|FORCE|1|true|TRUE|on|ON|yes|YES)
    (
      flock 9
      echo "[docker] Rebuilding Scryfall SQLite at $db_path"
      Rscript scripts/download-scryfall-library.R
      Rscript scripts/enrich-scryfall-library.R
    ) 9>"$lock_file"
    ;;
  auto|AUTO|"")
    (
      flock 9
      if needs_enrichment; then
        echo "[docker] Building Scryfall SQLite at $db_path"
        Rscript scripts/download-scryfall-library.R
        Rscript scripts/enrich-scryfall-library.R
      else
        echo "[docker] Scryfall SQLite already exists and is enriched: $db_path"
      fi
    ) 9>"$lock_file"
    ;;
  *)
    echo "[docker] Invalid MTGCODEX_SCRYFALL_BOOTSTRAP value: $bootstrap" >&2
    exit 2
    ;;
esac

exec "$@"
