# Synergy Engine

## Overview

The MVP synergy engine is symbolic and explainable:

- normalize card text/mechanics into atomic gameplay events
- expand mechanics through rule-based decomposition
- score cards from mechanical structure instead of naive text overlap
- surface indirect engines, packages, and anti-synergy as separate result classes

The engine is implemented in `R/query_synergy_engine.R` and exposed through
Plumber routes.

## Ontology

Atomic events are registered in `query_synergy_event_registry_default()`.
The vocabulary is extensible and not a closed list. Starter examples include:

- `DRAW_CARD`, `SELF_DRAW_CARD`, `OPPONENT_DRAW_CARD`
- `DISCARD_CARD`
- `GAIN_LIFE`, `LOSE_LIFE`
- `CREATE_TOKEN`, `PUT_COUNTER`
- `ADD_MANA`
- `SACRIFICE_PERMANENT`, `DIES`, `ETB`
- `CAST_SPELL`, `NONCREATURE_SPELL_CAST`
- `MILL_CARD`, `REANIMATE`, `GRAVEYARD_TO_HAND`

Aliases are canonicalized to stable IDs (`alias_to_id`).

## Normalization Process

1. Read card data (`name`, `oracle_text`, `keywords`, colors, legalities)
2. Detect mechanics from keywords and Oracle text
3. Expand mechanics through rules (`query_synergy_mechanic_rules_default()`)
4. Extract additional produced/consumed events from Oracle patterns
5. Build normalized output:

- produced events
- consumed/payoff events
- setup and finisher events
- strategy tags
- anti-synergy tags
- inferred roles (`producer`, `payoff`, `engine`, `setup`, `converter`, `amplifier`, `target`, `bridge`, `finisher`)
- cadence markers (one-shot, repeatable, scalable)

## Scoring Logic

`query_synergy_score_pair()` computes a weighted score from explicit axes:

- `direct_event_score`
- `indirect_engine_score`
- `reciprocal_value_score`
- `package_score`
- `anti_synergy_score`
- `shared_plan_score`
- `cadence_score`
- `role_complementarity_score`

Each result returns:

- numeric score (0-100)
- score breakdown by axis
- bucket scores by category
- primary bucket/category
- relation classes (`enabler_payoff`, `shared_plan`, etc.)
- human-readable reasons
- inferred roles
- matched events and package links
- directional explanations

Broad plan tags are used as supporting rerank signals only. They should not outweigh
role complementarity, cadence, or real mechanical event structure.

## Ranking Buckets

The `/synergy/find` pipeline now groups results into interpretable buckets rather than
only returning a single flat ranking. Current buckets include:

- `direct_enablers`
- `indirect_engines`
- `reciprocal_value_cards`
- `synergy_groups`
- `package_lines`
- `packages`
- `anti_synergy_warnings`

The legacy `best_matches` view can still be exposed as a compatibility layer, but it is
derived from the same bucket-aware scoring model.

## Performance Pipeline

The engine keeps full catalog coverage, but it no longer performs the most expensive work
across every card on every request.

The query pipeline is staged:

1. load or build precomputed normalized catalog data
2. run a lightweight full-catalog candidate scan over compact profiles
3. keep only the top-K candidates for deep pairwise scoring
4. run bucket assembly on the deep-scored subset
5. run package detection only on a smaller top-N subset

Current defaults are intentionally conservative:

- `top_k`: `max(64, min(120, max_results * 4))`
- `package_top_n`: `min(12, top_k)`
- `cheap_scan_cap`: `0` (scan full eligible catalog; set a positive value to cap)
- `max_group_size`: `4` (configurable)
- `group_branching_cap`: `max(4, min(8, max_group_size + 1))`

This preserves exhaustivity at the first-pass level while avoiding:

- repeated full-catalog normalization at query time
- repeated mechanic expansion for every request
- deep explanation generation on weak candidates
- package combinatorics over the full catalog

The canonical Scryfall catalog persists both the raw trimmed cards cache and a precomputed
normalized/profile cache. For ad hoc mini catalogs used in tests or local experiments, the
same precompute layer is built in memory.

`POST /synergy/find` now also returns additive pipeline metadata:

- `pipeline.catalog_size`
- `pipeline.candidate_filter_count`
- `pipeline.cheap_scan_count`
- `pipeline.deep_score_count`
- `pipeline.package_candidate_count`
- `pipeline.group_graph_pair_count`
- `pipeline.full_catalog_light_scan`
- `pipeline.top_k_used`
- `pipeline.package_top_n_used`

and stage timings in `timings`, including cheap scan, deep scoring, package detection, and
response assembly. These fields are intended to help debug bottlenecks without changing the
mechanical meaning of the engine.

For polling UIs, the engine also supports background job progress via additive routes.
Those routes expose:

- `status` (`queued`, `running`, `completed`, `error`)
- `progress.percent`
- `progress.stage`
- final `result` when the job completes

## Package Detection

Package detection is not card-specific. It uses normalized event flow and role-aware
chain validation over the local pairwise graph to identify generalized structures such as:

- setup -> converter -> payoff
- token maker -> sacrifice outlet -> death payoff
- graveyard setup -> cast/reanimation bridge -> payoff
- A -> X -> B
- A -> X -> Y -> B

Packages expose endpoints, intermediate cards, inferred role sequence, matched events,
matched resource transitions, and score breakdown to justify the package score.

## Mechanic Rule Extensions

Add or edit entries in `query_synergy_mechanic_rules_default()`.
Each rule can define:

- `keywords`
- `produced` events
- `consumed` events
- `setup` / `finisher`
- `anti_tags`
- `strategy_tags`

## API Routes

- `POST /cards/normalize`
- `POST /synergy/find`
- `POST /synergy/jobs/start`
- `GET /synergy/jobs/<job_id>`
- `GET /cards/<card_id>`
- `GET /events`
- `GET /mechanics`

## Response Shape Notes

`POST /synergy/find` should expose additive, explainable fields including:

- total score
- axis breakdown
- bucket/category
- inferred roles
- matched events
- explanation text
- grouped buckets and packages

UI consumers may inspect these grouped results directly without relying on hidden scoring
heuristics or card-specific exceptions.
