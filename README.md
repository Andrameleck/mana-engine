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

## Endpoints

- `GET /health`
- `GET /collection/load?type=db|csv|text&path=<file>&table=<optional>`
- `POST /collection/upload?type=db|csv|text&table=<optional>` (multipart with `file`)
- `POST /collection/upload?type=db|csv|text&table=<optional>&filename=<name>` (application/octet-stream)
- `GET /ui`
- `GET /ui/static/<file>`
