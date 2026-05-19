#!/usr/bin/env bash
set -euo pipefail

WORKER_SERVICE_NAME="mana-engine-api@.service"
PROJECT_DIR="${MANA_ENGINE_API_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
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
TLS_DOMAINS="${MANA_ENGINE_TLS_DOMAINS:-}"
TLS_EMAIL="${MANA_ENGINE_TLS_EMAIL:-}"
PUBLIC_SERVER_NAMES="${MANA_ENGINE_SERVER_NAMES:-${TLS_DOMAINS//,/ }}"
if [[ -z "$(echo "$PUBLIC_SERVER_NAMES" | xargs)" ]]; then
  PUBLIC_SERVER_NAMES="_"
fi

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
apt-get install -y nginx certbot python3-certbot-nginx

install -m 0644 "$WORKER_SERVICE_SRC" "$WORKER_SERVICE_DEST"

sed \
  -e "s/server_name example.org www.example.org;/server_name $PUBLIC_SERVER_NAMES;/g" \
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

if [[ -n "$TLS_DOMAINS" ]]; then
  IFS=',' read -r -a TLS_DOMAIN_LIST <<< "$TLS_DOMAINS"
  certbot_args=(--nginx -n --agree-tos --redirect)

  if [[ -n "$TLS_EMAIL" ]]; then
    certbot_args+=(--email "$TLS_EMAIL")
  else
    certbot_args+=(--register-unsafely-without-email)
  fi

  for domain in "${TLS_DOMAIN_LIST[@]}"; do
    domain="$(echo "$domain" | xargs)"
    if [[ -n "$domain" ]]; then
      certbot_args+=(-d "$domain")
    fi
  done

  if [[ "${#certbot_args[@]}" -gt 6 ]]; then
    certbot "${certbot_args[@]}"
    nginx -t
    systemctl reload nginx
  fi
fi

echo "Service installed."
if [[ -n "$TLS_DOMAINS" ]]; then
  FIRST_DOMAIN="${TLS_DOMAINS%%,*}"
  echo "API URL: https://$FIRST_DOMAIN/"
  echo "UI URL:  https://$FIRST_DOMAIN/ui"
else
  echo "API URL: http://$HOST_IP:$PORT/"
  echo "UI URL:  http://$HOST_IP:$PORT/ui"
fi
echo "Workers: $WORKER_COUNT"
