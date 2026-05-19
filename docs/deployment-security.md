# Deployment Security

Mana-Engine is intended to keep its API and package code public, while keeping
production infrastructure private.

## Public Repository

Keep these files public:

- R package and Plumber API code.
- Frontend source and built static assets.
- Generic Docker, nginx, and systemd examples.
- `.env.example`-style documentation with placeholder values only.

Do not commit these values:

- Real domains, IP allowlists, or server-specific paths.
- API keys, deploy tokens, webhook secrets, or private SSH material.
- Real nginx files from `/etc/nginx/sites-available`.
- Certbot or TLS material from `/etc/letsencrypt`.
- Production `.env` files.

## Private Infra Repository

Keep production-only deployment material in a private repository, for example
`mana-engine-infra`:

- `nginx/mana-engine-api.conf`
- `docker-compose.prod.yml`
- systemd units or deployment scripts
- environment file templates for `/etc/mana-engine`
- operational notes for the server

Runtime secrets should still live outside Git, typically in
`/etc/mana-engine/mana-engine-api.env`, with mode `0600` when possible.

## Frontend Visibility

Making the frontend source private does not make the deployed UI secret. HTML,
CSS, and JavaScript are delivered to browsers and can be inspected by users.
Protect sensitive features with server-side controls such as authentication,
authorization, IP restrictions, or separate public/admin API routes.
