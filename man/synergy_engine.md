# Synergy Engine

## Overview

The MVP synergy engine is symbolic and explainable:

- normalize card text/mechanics into atomic gameplay events
- expand mechanics through rule-based decomposition
- score cards from event interactions instead of naive text overlap

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

## Scoring Logic

`query_synergy_score_pair()` computes a weighted score from:

- event production match (candidate enabler -> target payoff)
- event payoff match (candidate payoff <- target production)
- shared plan tags
- setup/finisher overlap
- color fit
- format fit
- tempo fit (mana value distance)
- anti-synergy penalty

Each result returns:

- numeric score (0-100)
- score breakdown
- relation classes (`enabler_payoff`, `shared_plan`, etc.)
- human-readable reasons

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
- `GET /cards/<card_id>`
- `GET /events`
- `GET /mechanics`
