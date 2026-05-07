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

## Docker Compose

The Scryfall SQLite library is generated at container startup instead of being
stored in Git. The first launch downloads the configured Scryfall bulk dataset,
builds `/data/cache/mtgcodex.api/all_cards.sqlite`, enriches it with normalized
mechanics tables, and stores it in the persistent `mtgcodex-cache` volume.

```bash
docker compose up --build
```

Then open `http://localhost:8010/ui`.

Useful environment variables:

- `MTGCODEX_SCRYFALL_BOOTSTRAP=auto` builds the SQLite file only when missing
  or incomplete. Use `force` to rebuild it, or `false` to skip bootstrapping.
- `SCRYFALL_BULK_TYPE=oracle_cards` selects the Scryfall bulk dataset.
- `ENRICH_CHUNK=2000` controls enrichment batch size.

To rebuild the generated SQLite from the current Scryfall snapshot:

```bash
MTGCODEX_SCRYFALL_BOOTSTRAP=force docker compose up --build
```

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
- `POST /cards/normalize` (symbolic normalization for one card or a list of cards)
- `POST /synergy/find` (mechanical synergy search from atomic gameplay events)
- `POST /synergy/jobs/start` (start a background synergy computation with progress)
- `GET /synergy/jobs/<job_id>` (poll background synergy status/result)
- `GET /cards/<card_id>?include_normalized=true|false`
- `GET /events` (atomic event vocabulary)
- `GET /mechanics` (mechanic decomposition rules)
- `GET /ui`
- `GET /ui/static/<file>`

## Synergy Engine (MVP)

The mechanical synergy engine is symbolic and explainable. It does not rely on
raw Oracle text similarity alone.

- Source of truth: Scryfall `oracle_cards` bulk dataset (cached locally)
- Normalization: cards are mapped to atomic produced/consumed events
- Rule expansion: mechanics like `connive`, `cycling`, `surveil`, `exploit`
  expand into explicit event primitives
- Scoring model: combines event matching, shared plan tags, setup/finisher
  overlap, color/tempo/format fit, and anti-synergy penalties
- Performance pipeline: full-catalog lightweight scan, top-K deep scoring,
  then package detection on a smaller top-N subset
- Precompute/cache layer: normalized card profiles are cached so the engine
  preserves exhaustive catalog coverage without rebuilding the entire catalog
  on every request
- Explainability: each match returns reasons and relation classes

Implementation details are documented in
`man/synergy_engine.md`.
