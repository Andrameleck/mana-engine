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

Until the source and distributed UI are fully reconciled, build output is written
to `frontend/dist-check/`. This prevents a validation build from deleting the
additional assets currently served from `inst/www/`.

## Endpoints

- `GET /health`
- `GET /collection/load?type=db|csv|text&path=<file>&table=<optional>`
- `POST /collection/upload?type=db|csv|text&table=<optional>` (multipart with `file`)
- `POST /collection/upload?type=db|csv|text&table=<optional>&filename=<name>` (application/octet-stream)
- `GET /reference/spellbook/variants?q=<card>&limit=<1-100>`
- `GET /reference/mtgjson/cards?q=<optional>&set_code=<optional>&collector_number=<optional>&uuid=<optional>&limit=<1-200>`
- `POST /analysis/v1/synergies` (JSON: `seed`, `candidates`, `context`, `limit`)
- `POST /analysis/v1/groups` (JSON: `cards`, `context`, `limit`, `max_pair_evaluations`)
- `POST /analysis/v1/engines` (JSON: `cards`, `context`, `limit`, `max_pair_evaluations`)
- `GET /ui`
- `GET /ui/static/<file>`

## Functional synergy engine (experimental)

The R engine detects directed functional relations for three initial families:
creature tokens/sacrifice/death, graveyard/reanimation, and cast/copy. It keeps
strict constraints and unknown conditions separate from ranking.

```r
seed <- list(
  id = "producer",
  name = "Producer",
  oracle_text = "Create a 1/1 creature token.",
  color_identity = "B"
)
candidate <- list(
  id = "outlet",
  name = "Outlet",
  oracle_text = "Sacrifice a creature: Draw a card.",
  color_identity = "B"
)

mtgcodex.api::analyze_functional_synergies(
  seed,
  list(candidate),
  mtgcodex.api::analysis_context(
    format = "commander",
    rules_version = "fixture",
    allowed_colors = "B",
    objective = "tokens_sacrifice_death"
  )
)
```

The extractor deliberately abstains from unsupported Oracle wording. Its score
is a coverage indicator for recognized requirements, not a win probability.

## Strategy engine discovery (experimental)

`POST /analysis/v1/engines` composes typed actions through compatible zones and
objects. It returns a shared engine interface, alternative setup/execution
cards, compatible payloads, support candidates, exact evidence, and explicit
unknown conditions. For example, Entomb or Buried Alive followed by Reanimate
or Exhume is represented as `library -> graveyard -> battlefield`.

The result is structural. `structural_witness_only` does not claim that mana,
timing, draws, opponent responses, or deck utility have been simulated. The
same engine records are also included in `/analysis/v1/groups` so existing
clients can display them while migrating to the dedicated endpoint.
# Calculateur et connexion ChatGPT

Les parcours de calcul de l’interface utilisent le moteur serveur versionné.
Le mode assisté facultatif utilise une connexion ChatGPT via Codex, sans clé API.
Voir [le guide de lancement et les limites](docs/assistant-chatgpt.md).
