#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="mana-engine-api.service"
WORKER_SERVICE_NAME="mana-engine-api@.service"
PROJECT_DIR="/home/debian/git/mtgcodex.api"
WORKER_SERVICE_SRC="$PROJECT_DIR/deploy/$WORKER_SERVICE_NAME"
WORKER_SERVICE_DEST="/etc/systemd/system/$WORKER_SERVICE_NAME"
NGINX_SRC="$PROJECT_DIR/deploy/nginx-mana-engine-api.conf"
NGINX_DEST="/etc/nginx/sites-available/mana-engine-api"
NGINX_ENABLED="/etc/nginx/sites-enabled/mana-engine-api"
ENV_DIR="/etc/mana-engine"
ENV_FILE="$ENV_DIR/mana-engine-api.env"

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run this script with sudo."
  exit 1
fi

if [[ ! -f "$WORKER_SERVICE_SRC" ]]; then
  echo "Service file not found: $WORKER_SERVICE_SRC"
  exit 1
fi

if [[ ! -f "$NGINX_SRC" ]]; then
  echo "Nginx config file not found: $NGINX_SRC"
  exit 1
fi

HOST_IP="${MANA_ENGINE_API_HOST:-${MTGCODEX_API_HOST:-$(hostname -I | awk '{print $1}')}}"
PORT="${MANA_ENGINE_API_PORT:-${MTGCODEX_API_PORT:-8010}}"
SWAGGER="${MANA_ENGINE_API_SWAGGER:-${MTGCODEX_API_SWAGGER:-true}}"
WORKER_COUNT="${MANA_ENGINE_API_WORKER_COUNT:-${MTGCODEX_API_WORKER_COUNT:-2}}"
WORKER_BASE_PORT="${MANA_ENGINE_API_WORKER_BASE_PORT:-${MTGCODEX_API_WORKER_BASE_PORT:-8011}}"

install -d -m 0755 "$ENV_DIR"
cat > "$ENV_FILE" <<EOF
MANA_ENGINE_API_PROJECT_DIR=$PROJECT_DIR
MANA_ENGINE_API_HOST=$HOST_IP
MANA_ENGINE_API_PORT=$PORT
MANA_ENGINE_API_SWAGGER=$SWAGGER
MANA_ENGINE_API_WORKER_COUNT=$WORKER_COUNT
MANA_ENGINE_API_WORKER_BASE_PORT=$WORKER_BASE_PORT
EOF

apt-get update
apt-get install -y nginx

install -m 0644 "$WORKER_SERVICE_SRC" "$WORKER_SERVICE_DEST"

sed \
  -e "s/51.38.230.244/$HOST_IP/g" \
  -e "s/8010/$PORT/g" \
  -e "s/8011/$WORKER_BASE_PORT/g" \
  -e "s/8012/$((WORKER_BASE_PORT + 1))/g" \
  "$NGINX_SRC" > "$NGINX_DEST"

rm -f "$NGINX_ENABLED"
ln -sf "$NGINX_DEST" "$NGINX_ENABLED"
rm -f /etc/nginx/sites-enabled/default

systemctl daemon-reload
systemctl stop mtgcodex-api.service 2>/dev/null || true
systemctl disable mtgcodex-api.service 2>/dev/null || true
systemctl stop mana-engine-api.service 2>/dev/null || true
systemctl disable mana-engine-api.service 2>/dev/null || true

for worker in $(seq 1 "$WORKER_COUNT"); do
  systemctl enable --now "mana-engine-api@${worker}.service"
  systemctl restart "mana-engine-api@${worker}.service"
done

nginx -t
systemctl enable --now nginx
systemctl restart nginx

echo "Service installed."
echo "API URL: http://$HOST_IP:$PORT/"
echo "UI URL:  http://$HOST_IP:$PORT/ui"
echo "Workers: $WORKER_COUNT"
