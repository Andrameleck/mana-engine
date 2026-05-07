#!/usr/bin/env bash
# Launch the Archidekt parallel deck scanner in the background (nohup).
#
# Usage:
#   bash scripts/launch-archidekt.sh [max_id] [workers] [delay]
#
# Examples:
#   bash scripts/launch-archidekt.sh                   # defaults
#   bash scripts/launch-archidekt.sh 8000000 8 0.1    # full scan
#   bash scripts/launch-archidekt.sh 8000000 4 0.2    # gentler

set -euo pipefail

MAX_ID="${1:-8000000}"
WORKERS="${2:-8}"
DELAY="${3:-0.1}"
CHUNK="${4:-50}"

OUT_DIR="inst/decks/archidekt"
DB="${OUT_DIR}/archidekt.sqlite"
LOG="${OUT_DIR}/archidekt_scan.log"
CONSOLE="${OUT_DIR}/archidekt_scan_console.log"
PID_FILE="${OUT_DIR}/archidekt_scan.pid"

mkdir -p "$OUT_DIR"

# Stop existing scan if running
if [[ -f "$PID_FILE" ]]; then
  OLD_PID=$(cat "$PID_FILE")
  if kill -0 "$OLD_PID" 2>/dev/null; then
    echo "Arrêt du scan précédent (PID $OLD_PID)..."
    kill "$OLD_PID" 2>/dev/null || true
    sleep 2
  fi
fi

echo "========================================"
echo "  Archidekt Deck Scanner"
echo "========================================"
echo "  DB        : $DB"
echo "  Max ID    : $MAX_ID"
echo "  Workers   : $WORKERS"
echo "  Délai     : ${DELAY}s / worker"
echo "  Chunk     : $CHUNK IDs / worker"
echo "  Taux ~    : $(echo "scale=0; $WORKERS / $DELAY" | bc 2>/dev/null || echo "?") req/s"
echo "  Log       : $LOG"
echo "  Console   : $CONSOLE"
echo "========================================"
echo ""

nohup env \
  ARCHIDEKT_DB_PATH="$DB" \
  ARCHIDEKT_MAX_ID="$MAX_ID" \
  ARCHIDEKT_WORKERS="$WORKERS" \
  ARCHIDEKT_DELAY="$DELAY" \
  ARCHIDEKT_CHUNK="$CHUNK" \
  Rscript scripts/scan-archidekt-decks.R \
  >> "$LOG" 2>> "$CONSOLE" &

echo $! > "$PID_FILE"

echo "Scan lancé en arrière-plan (PID $!)"
echo ""
echo "Suivre la progression :"
echo "  tail -f $LOG"
echo "  sqlite3 $DB 'SELECT COUNT(*) FROM decks;'"
echo ""
echo "Arrêter :"
echo "  kill \$(cat $PID_FILE)"
