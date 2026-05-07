#!/usr/bin/env Rscript
# scan-lotusnoir-dids.R
#
# Scan les DIDs lotusnoir.info en ORDRE DÉCROISSANT (du plus récent au plus ancien).
# Parallèle via mclapply. Sauvegarde uniquement les hits (VALID / EMPTY).
# Survit à la fermeture du terminal si lancé avec nohup (voir launch-scan.sh).
# Reprend automatiquement si le fichier de sortie existe déjà.
#
# Variables d'environnement :
#   LOTUSNOIR_SCAN_MAX_DID    borne haute   (défaut: 20500000)
#   LOTUSNOIR_SCAN_MIN_DID    borne basse   (défaut: 1)
#   LOTUSNOIR_SCAN_DELAY      délai par worker en secondes (défaut: 0.15)
#   LOTUSNOIR_SCAN_WORKERS    workers parallèles (défaut: 15)
#   LOTUSNOIR_SCAN_CHUNK      DIDs par chunk (défaut: 100)
#   LOTUSNOIR_SCAN_OUT        fichier de résultats
#   LOTUSNOIR_SCAN_LOG        fichier de log

if (!requireNamespace("parallel", quietly = TRUE)) stop("'parallel' requis")
suppressMessages(devtools::load_all(".", quiet = TRUE))

# ── paramètres ───────────────────────────────────────────────────────────────
p <- function(name, default) {
  v <- Sys.getenv(name, unset = "")
  if (!nzchar(v)) return(default)
  v
}
max_did   <- max(1L, as.integer(p("LOTUSNOIR_SCAN_MAX_DID", "20500000")))
min_did   <- max(1L, as.integer(p("LOTUSNOIR_SCAN_MIN_DID", "1")))
delay     <- max(0,  as.numeric(p("LOTUSNOIR_SCAN_DELAY",   "0.15")))
n_workers <- max(1L, min(as.integer(p("LOTUSNOIR_SCAN_WORKERS", "15")),
                         parallel::detectCores(logical = TRUE)))
chunk_sz  <- max(1L, as.integer(p("LOTUSNOIR_SCAN_CHUNK", "100")))
out_path  <- p("LOTUSNOIR_SCAN_OUT", file.path("inst", "decks", "lotusnoir_did_scan.txt"))
log_path  <- p("LOTUSNOIR_SCAN_LOG", file.path("inst", "decks", "lotusnoir_did_scan.log"))

dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(log_path), recursive = TRUE, showWarnings = FALSE)

ts   <- function() format(Sys.time(), "%Y-%m-%d %H:%M:%S")
logf <- function(...) {
  line <- sprintf("[%s] %s", ts(), sprintf(...))
  cat(line, "\n", sep = "")
  cat(line, "\n", sep = "", file = log_path, append = TRUE)
}

# ── reprise : trouver le plus petit DID déjà scanné (ordre décroissant) ──────
already_min <- max_did + 1L
if (file.exists(out_path)) {
  prev <- tryCatch(readLines(out_path, warn = FALSE), error = function(e) character(0))
  ckpt <- suppressWarnings(as.integer(sub("^# SCANNED_DOWN_TO=([0-9]+).*", "\\1",
           grep("^# SCANNED_DOWN_TO=", prev, value = TRUE))))
  hits <- suppressWarnings(as.integer(sub("^did=([0-9]+).*", "\\1",
           grep("^did=[0-9]+", prev, value = TRUE))))
  all_seen <- c(ckpt, hits)
  all_seen <- all_seen[is.finite(all_seen) & !is.na(all_seen)]
  if (length(all_seen) > 0L) already_min <- min(all_seen)
}
effective_max <- min(max_did, already_min - 1L)

if (effective_max < min_did) {
  cat(sprintf("Rien à scanner : déjà complété jusqu'à did=%d\n", already_min))
  quit(status = 0)
}

# ── worker : pur base R, pas de devtools ─────────────────────────────────────
scan_chunk <- function(dids, delay) {
  hits <- list()
  for (did in dids) {
    if (delay > 0) Sys.sleep(delay)
    url <- sprintf("https://www.lotusnoir.info/magic/decks/?action=export&did=%d", as.integer(did))
    txt <- tryCatch(paste(readLines(url, warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
                    error = function(e) "")
    if (!nzchar(txt) || grepl("Introuvable", txt, fixed = TRUE)) next
    if (grepl("^//\\s*NAME\\s*:", txt, perl = TRUE)) {
      nm  <- regmatches(txt, regexpr("//\\s*NAME\\s*:[^\n]+", txt))
      nm  <- if (length(nm)) trimws(sub("^//\\s*NAME\\s*:\\s*", "", nm)) else ""
      hits <- c(hits, list(list(did = did, status = "VALID", name = nm)))
    } else if (grepl("aucune carte", txt, fixed = TRUE)) {
      hits <- c(hits, list(list(did = did, status = "EMPTY", name = "")))
    }
  }
  hits
}

# ── construction des chunks (ordre décroissant) ───────────────────────────────
all_dids   <- seq.int(effective_max, min_did)          # décroissant
chunk_list <- split(all_dids, ceiling(seq_along(all_dids) / chunk_sz))
n_chunks   <- length(chunk_list)
total_dids <- length(all_dids)

# durée estimée : total_dids / (n_workers / delay)
rate_est   <- n_workers / max(delay, 0.001)
eta_min    <- round(total_dids / rate_est / 60)

# ── en-tête fichier ───────────────────────────────────────────────────────────
if (already_min > max_did) {
  writeLines(c(
    "# LotusNoir DID scan — VALID uniquement",
    sprintf("# Démarré     : %s", ts()),
    sprintf("# Plage       : %d .. %d  (ordre décroissant)", max_did, min_did),
    sprintf("# Workers     : %d  |  Delay : %.2fs  |  Taux ~%.0f req/s", n_workers, delay, rate_est),
    sprintf("# ETA         : ~%d min", eta_min),
    "# Format      : did=<N>  status=VALID  name=<titre>",
    "#"
  ), con = out_path)
} else {
  cat(sprintf("# --- REPRISE depuis did=%d  (%s) ---\n", effective_max, ts()),
      file = out_path, append = TRUE)
}

logf("Démarrage — plage %d..%d  workers=%d  delay=%.2fs  chunks=%d  ETA~%dmin",
     effective_max, min_did, n_workers, delay, n_chunks, eta_min)

# ── boucle parallèle ─────────────────────────────────────────────────────────
total_valid <- 0L
total_empty <- 0L
chunks_done <- 0L
t0          <- proc.time()[["elapsed"]]

for (batch_i in seq(1L, n_chunks, by = n_workers)) {
  batch_end    <- min(batch_i + n_workers - 1L, n_chunks)
  batch_chunks <- chunk_list[seq.int(batch_i, batch_end)]

  results <- parallel::mclapply(
    batch_chunks,
    FUN      = function(dids) scan_chunk(dids, delay),
    mc.cores = length(batch_chunks)
  )

  # écriture immédiate des hits
  for (chunk_hits in results) {
    for (hit in chunk_hits) {
      if (hit$status == "VALID") {
        total_valid <- total_valid + 1L
        line <- sprintf("did=%-10d  status=VALID  name=%s", hit$did, hit$name)
        cat("  [VALID]", line, "\n")
        cat(line, "\n", file = out_path, append = TRUE, sep = "")
      } else {
        total_empty <- total_empty + 1L
      }
    }
  }

  chunks_done  <- chunks_done + length(batch_chunks)
  last_did     <- min(unlist(batch_chunks))          # plus petit DID du batch (décroissant)
  elapsed      <- proc.time()[["elapsed"]] - t0
  actual_rate  <- if (elapsed > 0) (chunks_done * chunk_sz) / elapsed else 0
  pct          <- round(100 * chunks_done / n_chunks, 1)
  remaining    <- if (actual_rate > 0) round((n_chunks - chunks_done) * chunk_sz / actual_rate / 60) else NA

  # checkpoint pour reprise
  cat(sprintf("# SCANNED_DOWN_TO=%d\n", last_did), file = out_path, append = TRUE)
  logf("%.1f%%  did_down_to=%-10d  valid=%d  empty=%d  rate=%.0f req/s  reste~%s min",
       pct, last_did, total_valid, total_empty, actual_rate,
       if (is.na(remaining)) "?" else as.character(remaining))
}

# ── résumé ────────────────────────────────────────────────────────────────────
elapsed_total <- proc.time()[["elapsed"]] - t0
summary_lines <- c(
  "#",
  "# === SCAN TERMINÉ ===",
  sprintf("# Plage    : %d .. %d  (%d DIDs)", effective_max, min_did, total_dids),
  sprintf("# Valid    : %d  (decklists réelles)", total_valid),
  sprintf("# Empty    : %d  (enregistrement sans cartes)", total_empty),
  sprintf("# Workers  : %d  |  Elapsed : %.1f s", n_workers, elapsed_total),
  sprintf("# Terminé  : %s", ts())
)
cat(paste(summary_lines, collapse = "\n"), "\n", file = out_path, append = TRUE)
for (l in summary_lines) cat(l, "\n")
logf("Scan terminé. valid=%d  elapsed=%.1fs", total_valid, elapsed_total)
