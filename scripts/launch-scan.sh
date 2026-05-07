#!/usr/bin/env bash
# launch-scan.sh — Lance le scan DID en arrière-plan avec nohup
# Survit à la fermeture du terminal.
#
# Usage :
#   bash scripts/launch-scan.sh [max_did] [workers] [delay]
#
# Exemples :
#   bash scripts/launch-scan.sh                    # 20.5M → 1, 15 workers, 0.15s
#   bash scripts/launch-scan.sh 100000             # 100k → 1 seulement
#   bash scripts/launch-scan.sh 20500000 15 0.1    # max vitesse

cd "$(dirname "$0")/.." || exit 1

MAX_DID="${1:-20500000}"
WORKERS="${2:-15}"
DELAY="${3:-0.15}"

OUT="inst/decks/lotusnoir_did_scan.txt"
LOG="inst/decks/lotusnoir_did_scan.log"
CONSOLE="inst/decks/lotusnoir_did_scan_console.log"
PID_FILE="inst/decks/lotusnoir_scan.pid"

mkdir -p inst/decks

# Tuer un éventuel scan précédent
if [[ -f "$PID_FILE" ]]; then
  OLD_PID=$(cat "$PID_FILE")
  if kill -0 "$OLD_PID" 2>/dev/null; then
    echo "Arrêt du scan précédent (PID $OLD_PID)..."
    kill "$OLD_PID"
    sleep 2
  fi
fi

# Calcul ETA
TOTAL=$(( MAX_DID ))
RATE=$(echo "$WORKERS $DELAY" | awk '{printf "%.0f", $1 / $2}')
ETA_MIN=$(echo "$TOTAL $RATE" | awk '{printf "%.0f", $1 / $2 / 60}')

echo "========================================"
echo "  LotusNoir DID Scanner"
echo "========================================"
echo "  Plage    : $MAX_DID → 1  (ordre décroissant)"
echo "  Workers  : $WORKERS"
echo "  Délai    : ${DELAY}s / worker"
echo "  Taux ~   : ${RATE} req/s"
echo "  ETA ~    : ${ETA_MIN} min"
echo "  Résultats: $OUT"
echo "  Log      : $LOG"
echo "  Console  : $CONSOLE"
echo "========================================"
echo ""

nohup env \
  LOTUSNOIR_SCAN_MAX_DID="$MAX_DID" \
  LOTUSNOIR_SCAN_WORKERS="$WORKERS" \
  LOTUSNOIR_SCAN_DELAY="$DELAY" \
  LOTUSNOIR_SCAN_CHUNK="100" \
  LOTUSNOIR_SCAN_OUT="$OUT" \
  LOTUSNOIR_SCAN_LOG="$LOG" \
  Rscript scripts/scan-lotusnoir-dids.R \
  > "$CONSOLE" 2>&1 &

SCAN_PID=$!
echo "$SCAN_PID" > "$PID_FILE"
echo "Scan lancé en arrière-plan (PID $SCAN_PID)"
echo ""
echo "Suivre la progression :"
echo "  tail -f $LOG"
echo "  grep -c 'status=VALID' $OUT"
echo ""
echo "Arrêter :"
echo "  kill $SCAN_PID"
echo "  # ou : bash scripts/launch-scan.sh stop"
