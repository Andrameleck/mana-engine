# AGENTS.md — Refactor & Harmonization Playbook

This file directs autonomous coding agents working on the **mana-engine**
codebase. The historical design brief (mechanics-first synergy engine,
ontology rules, etc.) lives in [AGENTS_old.md](AGENTS_old.md) and remains
authoritative for *behavior*. This file governs the current refactoring
campaign and *how* code should look from now on.

> All new and refactored code MUST follow the rules below. When in doubt,
> prefer **deletion** over addition.

---

## 1. Mission

The codebase has grown organically and now exhibits two pain points:

| Layer | Symptom | Evidence |
|-------|---------|----------|
| R backend | ~20.9k LoC across 43 files, 374 top-level functions, multiple near-duplicate helpers (db connect/disconnect, row→record mappers, scryfall fetchers, normalization). | `R/` directory; largest: `synergy_normalize.R` (1987), `query_reference_lotusnoir.R` (1675), `synergy_groups.R` (1524). |
| Frontend SPA | ~20.2k LoC, monolithic `main.js` (8275 lines, 255 functions), `styles.css` (8318 lines). Inconsistent rendering of the *same* concept across tabs (card preview, status banners, color pickers, paginations, loading states). | `frontend/src/main.js`, `frontend/src/styles.css`. |

The two goals of this campaign:

1. **Factorize** — reduce LoC, eliminate redundancy, raise readability and
   debuggability, optimize using tidyverse (`dplyr`, `purrr`, `tidyr`,
   `tibble`, `stringr`) where it *simplifies* code without hurting clarity.
2. **Harmonize the UI** — keep the current high-level information
   architecture (tabs / panels / sections) but make every recurring widget
   visually and behaviorally identical, with a single shared implementation.

---

## 2. Non-negotiable working style

Before any change:

1. **Read first**. Inspect target files end-to-end. Do not refactor what you
   have not read.
2. **Plan in PR description / commit body**. State: scope, files touched,
   what was deduplicated, what was deleted, behavior preserved.
3. **Behavior-preserving by default**. Refactors MUST NOT change observable
   API responses, route shapes, JSON keys, CSS class contracts consumed by
   JS, or user-visible UI semantics. Visual harmonization is allowed and
   expected; functional regressions are not.
4. **Small, reviewable steps**. One concern per commit. Prefer 5 focused
   commits over 1 mega-commit.
5. **No speculative abstractions**. Extract a helper only when it has
   ≥ 2 real call sites (or is obviously needed by a near-term task).
6. **No dead code on the way in**. If you touch a file, delete code paths
   that are demonstrably unused (after `grep`-confirming).
7. **Tests stay green**. Run `R CMD check` / `devtools::test()` before
   declaring a task done. For the frontend run `cd frontend && npm run build`.

---

## 3. R backend — refactoring rules

### 3.1 Tidyverse, conservatively

- Use `dplyr` for data-frame transforms (filter / mutate / summarise /
  join). Avoid base R loops over rows.
- Use `purrr` (`map`, `map_*`, `pmap`, `walk`, `keep`, `compact`, `reduce`)
  instead of `for` / `lapply` chains, when it shortens code.
- Use `stringr` over base regex (`str_detect`, `str_extract`, `str_replace`).
- Use `tibble` for in-memory tabular data; keep `data.frame` only when
  required by a downstream API (DBI, jsonlite serialization).
- **Do not** introduce `tidyverse` for the sake of it. If 3 lines of base R
  are clearer, keep them.
- Avoid `%>%` and prefer the native pipe `|>` for new code. Don't mass-edit
  existing pipes unless you are already rewriting the function.

### 3.2 Mandatory consolidation targets

Create / consolidate the following shared modules. Delete duplicated
implementations once call sites migrate.

| New / canonical module | Responsibility | Replaces / absorbs |
|------------------------|----------------|--------------------|
| `R/util_db.R` | `with_db(path, fn)` helper that opens, runs, and *always* disconnects. Single `db_connect()` / `db_disconnect()`. | `query_db_connect.R`, `query_db_disconnect.R`, ad-hoc `dbConnect()` calls. |
| `R/util_records.R` | Row→record / record→row mappers, JSON column packing/unpacking, NA-safe coercions. | Helpers scattered in `query_db_rows_to_records.R`, `query_reference_*.R`. |
| `R/util_http.R` | `http_get_json()`, retry/backoff, UA header, rate limiting. Single place for `httr2`. | Per-source HTTP code in `query_reference_archidekt.R`, `_moxfield.R`, `_tappedout.R`, `_lotusnoir.R`. |
| `R/util_scryfall.R` | Scryfall id → image URL (`small`/`normal`/`art_crop`), symbol URL, type-line parsing. | Inline string concat in multiple `query_*` and `synergy_*` files. |
| `R/util_api.R` | Plumber response shaping: `api_ok()`, `api_error()`, `api_paginate()`, NULL-safe param coercion (`as_opt_int`, `as_opt_chr`). | The `""`-vs-`NULL` plumbing in `inst/plumber/plumber.R`, repeated in each handler. |
| `R/util_synergy_io.R` | Common load/save of synergy catalogs, normalized form, cache lookup. | Overlap between `synergy_catalog_sqlite.R`, `synergy_enriched_sqlite.R`, `synergy_cache.R`. |

Per-source reference modules (`query_reference_*.R`) MUST then become thin:
*URL building + per-source parsing only*, delegating IO / retries / DB
persistence to the utilities above.

### 3.3 File-level rules

- **No file > 800 LoC.** Split by concern (parsing / IO / persistence /
  formatting) when crossed.
- **No function > 80 LoC.** If exceeded, extract named helpers; do not just
  add comments to a long body.
- Every exported function: roxygen with `@title`, `@param`, `@return`, one
  `@examples` block (use `\dontrun{}` for IO).
- Internal helpers: prefix with `.` (e.g. `.coerce_int`) and `@keywords internal`.
- One `@export` per public symbol; nothing else exported.
- `NAMESPACE` is generated by roxygen — do not edit by hand.
- Use `cli::cli_abort()` / `cli::cli_warn()` for messages; no bare `stop()`
  / `warning()` in new code.

### 3.4 Performance

- Vectorize before parallelizing.
- For SQLite: parameterized queries via `DBI::dbBind()`; never paste user
  input into SQL. Reserved words quoted (`"set"`, `"order"`, etc.).
- For large joins/aggregations consider `dtplyr` or raw `data.table` only
  if profiling shows it matters. Measure with `bench::mark()` before
  claiming a speedup.

---

## 4. Frontend — refactoring rules

### 4.1 Split `main.js`

`frontend/src/main.js` (8275 LoC) MUST be broken into focused modules under
`frontend/src/`:

```
frontend/src/
  api.js               # already exists — HTTP client only
  ui.js                # already exists — keep, but absorb shared widgets (see 4.2)
  boot.js              # bootstrap / routing / tab switching
  state.js             # app state (i18n lang, current tab, selected card, filters)
  i18n.js              # translation tables + helpers
  views/
    card_explorer.js
    collection.js
    synergy_lab.js
    deck_generator.js
    references.js
  widgets/
    card_tile.js       # the .collection-card tile (single source of truth)
    card_preview.js    # the right-column .lab-preview viewer
    color_picker.js    # WUBRG buttons
    pagination.js
    status_banner.js
    autocomplete.js
  utils/
    scryfall.js        # CDN URL builder, symbol URL
    dom.js             # $('#id'), createEl(tag, props, children)
    format.js          # mana/oracle text → HTML, escapeHtml
```

Each view module exposes `{ mount(rootEl), unmount(), refresh() }` and is
imported by `boot.js`. No view module imports another view module.

### 4.2 Single source of truth per widget

Today these widgets are implemented several times with subtle differences:

| Widget | Current divergent sources | Target |
|--------|---------------------------|--------|
| Card preview (right column) | Synergy Lab `#strategy-card-preview`, Card Explorer `#cf-viewer`, deck generator preview. | `widgets/card_preview.js` exporting `renderCardPreview(targetEl, card)`. HTML uses `.lab-preview .strategy-result-preview`. |
| Card tile (grid item) | `.collection-card` in Collection, `.cf-card` in Card Explorer, deck list rows. | `widgets/card_tile.js` exporting `renderCardTile(card, opts)`. CSS class `.card-tile` with modifiers `--compact`, `--grid`, `--row`. |
| Color picker (WUBRG) | At least 2 implementations (Card Explorer `cf-color-btn`, Synergy filters). | `widgets/color_picker.js`. |
| Pagination | Duplicated in Collection and Card Explorer. | `widgets/pagination.js`. |
| Status banner (loading / empty / error) | Each view has its own `<div class="*-status">`. | `widgets/status_banner.js`, classes `.status-banner --loading --empty --error`. |
| Autocomplete | Card Explorer search uses `<datalist>`, other inputs use custom popovers. | `widgets/autocomplete.js` with a single visual style. |

Migration order: build the widget → migrate one view at a time → delete the
old implementation → confirm visual parity in the browser before next view.

### 4.3 CSS harmonization

- `styles.css` (8318 LoC) MUST be split with `@import` into files under
  `frontend/src/css/`:
  - `tokens.css` (CSS variables: colors, spacing, radii, fonts)
  - `reset.css`
  - `layout.css` (`.app-shell`, `.workspace`, `.lab-layout`, grid systems)
  - `widgets/` (one file per widget above)
  - `views/` (per-view layout only — no widget styling)
- Remove all `!important` introduced as a hack. The pattern of
  `.strategy-result-preview { background: transparent !important }` then
  re-adding it via `.lab-preview` MUST be eliminated; widget styles live in
  one place and don't fight each other.
- Tokenize: every hardcoded color/spacing in the new code must reference a
  variable in `tokens.css`.
- No new top-level selector may shadow an existing one without justification
  in a comment.

### 4.4 JS code style

- ES modules only (`import` / `export`). No globals on `window` except the
  unavoidable bootstrap.
- Native DOM (`document.createElement`, `el.append(...)`). No new framework
  is being introduced.
- `const` by default, `let` when reassigned, never `var`.
- One default export per module = the view's `mount` (for views) or the
  widget's main render function (for widgets). Helpers are named exports.
- Strict equality (`===`). Optional chaining and nullish coalescing welcome.
- Format: 2-space indent, semicolons, double quotes for JS strings.

---

## 5. Definition of done (per refactor PR)

A refactor task is complete only when ALL of the following hold:

- [ ] `R CMD check` passes with no new NOTEs/WARNINGs/ERRORs.
- [ ] `devtools::test()` passes; new helpers have unit tests under
      `tests/testthat/`.
- [ ] `cd frontend && npm run build` succeeds with no new warnings.
- [ ] Manual visual check of the affected tab(s) in the running API
      (`start_api()` → `/ui`); screenshots in PR if UI changed.
- [ ] Net LoC change is **negative** (refactors should remove more than
      they add). If not, justify in the PR description.
- [ ] No public R function signature changed without a deprecation shim.
- [ ] No JSON key or HTTP route changed.
- [ ] No new `!important`, no new `window.*` global, no new file > the
      limits in §3.3 / §4.1.
- [ ] Old/duplicated implementations are **deleted**, not left as
      "deprecated" zombies.

---

## 6. Task backlog (suggested order)

Agents should pick the next unticked item and open one PR per item.

1. [x] Introduce `R/util_db.R` (`with_db`) and migrate `query_collection_*.R`.
2. [ ] Introduce `R/util_api.R` and migrate `inst/plumber/plumber.R` (kills
       the `NULL`-vs-`""` boilerplate).
3. [ ] Introduce `R/util_http.R`; migrate `query_reference_archidekt.R`
       first, then `_moxfield.R`, `_tappedout.R`, `_lotusnoir.R`.
4. [ ] Introduce `R/util_scryfall.R`; replace inline image-URL strings.
5. [ ] Introduce `R/util_records.R`; collapse `query_db_rows_to_records.R`.
6. [ ] Split `frontend/src/main.js` into `boot.js` + `state.js` + view
       modules (no behavior change, just file moves + ES imports).
7. [ ] Extract `widgets/card_preview.js`; migrate Synergy Lab, then
       Card Explorer, then deck generator. Delete inline duplicates.
8. [ ] Extract `widgets/card_tile.js`; migrate Collection, then Card
       Explorer grid. Unify CSS to `.card-tile`.
9. [ ] Extract `widgets/color_picker.js`, `pagination.js`, `status_banner.js`,
       `autocomplete.js`. Migrate every consumer.
10. [ ] Split `styles.css` into `tokens.css` + `layout.css` + per-widget
        files. Remove the `!important` wars.
11. [ ] Audit `synergy_normalize.R`, `synergy_groups.R`, `synergy_engine.R`
        for duplicated normalization helpers; extract to `synergy_utils.R`
        (already exists — grow it).

When the backlog is empty, re-measure LoC and update §1 of this file.

---

## 7. What NOT to do

- Do not introduce React / Vue / Svelte / a bundler change. Vite stays.
- Do not introduce a new R framework (no Shiny, no plumber rewrite).
- Do not change the SQLite schema as part of a refactor PR.
- Do not rename public R functions or HTTP endpoints in a refactor PR.
  If a rename is needed, do it in a separate, isolated PR with shims.
- Do not "improve" code you did not need to touch for the current task.
- Do not silently widen scope. Stop and ask if the task grows.
