#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="mtgcodex-api.service"
WORKER_SERVICE_NAME="mtgcodex-api@.service"
PROJECT_DIR="/home/debian/git/mtgcodex.api"
WORKER_SERVICE_SRC="$PROJECT_DIR/deploy/$WORKER_SERVICE_NAME"
WORKER_SERVICE_DEST="/etc/systemd/system/$WORKER_SERVICE_NAME"
NGINX_SRC="$PROJECT_DIR/deploy/nginx-mtgcodex-api.conf"
NGINX_DEST="/etc/nginx/sites-available/mtgcodex-api"
NGINX_ENABLED="/etc/nginx/sites-enabled/mtgcodex-api"
ENV_DIR="/etc/mtgcodex"
ENV_FILE="$ENV_DIR/mtgcodex-api.env"

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

HOST_IP="${MTGCODEX_API_HOST:-$(hostname -I | awk '{print $1}')}"
PORT="${MTGCODEX_API_PORT:-8010}"
SWAGGER="${MTGCODEX_API_SWAGGER:-true}"
WORKER_COUNT="${MTGCODEX_API_WORKER_COUNT:-2}"
WORKER_BASE_PORT="${MTGCODEX_API_WORKER_BASE_PORT:-8011}"

install -d -m 0755 "$ENV_DIR"
cat > "$ENV_FILE" <<EOF
MTGCODEX_API_PROJECT_DIR=$PROJECT_DIR
MTGCODEX_API_HOST=$HOST_IP
MTGCODEX_API_PORT=$PORT
MTGCODEX_API_SWAGGER=$SWAGGER
MTGCODEX_API_WORKER_COUNT=$WORKER_COUNT
MTGCODEX_API_WORKER_BASE_PORT=$WORKER_BASE_PORT
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

for worker in $(seq 1 "$WORKER_COUNT"); do
  systemctl enable --now "mtgcodex-api@${worker}.service"
  systemctl restart "mtgcodex-api@${worker}.service"
done

nginx -t
systemctl enable --now nginx
systemctl restart nginx

echo "Service installed."
echo "API URL: http://$HOST_IP:$PORT/"
echo "UI URL:  http://$HOST_IP:$PORT/ui"
echo "Workers: $WORKER_COUNT"
