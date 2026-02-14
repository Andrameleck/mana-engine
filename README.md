# MTGCODEX

MTGCODEX is being rewritten as an R package that focuses on a Plumber REST
service for Magic: The Gathering collection analytics. The package now exposes
`start_api()` to run the API entrypoint.

## Install the development snapshot

```r
devtools::install_github("FlorianRicquier/MTGCODEX")
```

During local development run `devtools::load_all()` so you can iterate while the
package structure takes shape.

## Launch the (future) Plumber service

The API router is under `inst/plumber/plumber.R`. Start it with:

```r
MTGCODEX::start_api(host = "0.0.0.0", port = 8000)
```

You can also run the router directly during development:

```r
plumber::plumb("inst/plumber/plumber.R")$run(port = 8000)
```

## Current roadmap

1. Port the standalone scripts (`import_*`, `simulate_matchup.R`, `plumber.R`)
	 into namespaced R modules.
2. Stage the Plumber router under `inst/plumber/` and provide a helper such as
	 `launch_service()`.
3. Add documentation, tests, and example data once public APIs are stable.

Status: schema and scripts exist externally; package wiring and service exports
are in progress.
