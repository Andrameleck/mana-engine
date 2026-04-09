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
