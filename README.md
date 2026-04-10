# mtgcodex.api

Minimal Plumber API + UI for loading and displaying a collection from:
- SQLite database (`db`)
- CSV (`csv`)
- text file (`text`)

## Run

```r
mtgcodex.api::start_api(host = "0.0.0.0", port = 8000)
```

Then open `http://localhost:8000/ui`.

## Systemd service on a VM

The repository includes a `systemd` + Nginx deployment that starts both the
API and the web UI through `mtgcodex.api::start_api()`.

Default service settings:

- host: first IP returned by `hostname -I`
- port: `8010`
- workers: `2`
- UI: `http://<vm-ip>:8010/ui`

Install and start it with:

```bash
cd /home/debian/git/mtgcodex.api
sudo ./scripts/install-systemd-service.sh
```

Override host or port during install if needed:

```bash
sudo MTGCODEX_API_HOST=51.38.230.244 MTGCODEX_API_PORT=8010 ./scripts/install-systemd-service.sh
```

The generated runtime environment is stored in
`/etc/mtgcodex/mtgcodex-api.env`.

Worker processes listen on loopback ports starting at `8011`, and Nginx
publishes the public endpoint on port `8010`.

## Frontend (Vite)

The web UI is now structured as a Vite app in `frontend/`.

### Dev server

```bash
cd frontend
npm install
npm run dev
```

### Production build served by Plumber

```bash
cd frontend
npm run build
```

Build output is written to `inst/www/`, which is what `/ui` and `/ui/static/<file>` serve.

## Endpoints

- `GET /health`
- `GET /collection/load?type=db|csv|text&path=<file>&table=<optional>`
- `POST /collection/upload?type=db|csv|text&table=<optional>` (multipart with `file`)
- `POST /collection/upload?type=db|csv|text&table=<optional>&filename=<name>` (application/octet-stream)
- `GET /reference/spellbook/variants?q=<card>&limit=<1-100>`
- `GET /reference/mtgjson/cards?q=<optional>&set_code=<optional>&collector_number=<optional>&uuid=<optional>&limit=<1-200>`
- `GET /ui`
- `GET /ui/static/<file>`
