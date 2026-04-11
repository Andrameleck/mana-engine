# AGENTS.md

## Repository purpose

This repository implements a Magic: The Gathering deckbuilding API with a strong focus on
mechanical card analysis, synergy detection, and explainable recommendations.

The project goal is NOT to build a naive Oracle-text similarity engine.
The goal is to build a generalized, explainable, mechanics-first synergy engine.

## Working style

- Inspect the repository before making changes.
- Reuse the existing architecture, naming conventions, and stack.
- Prefer small, testable, incremental changes.
- Avoid speculative refactors.
- Do not rewrite unrelated modules.
- Keep code explicit, debuggable, and easy to extend.

## Before coding

Always do the following first:
1. Identify the relevant files and extension points.
2. Explain the implementation plan briefly.
3. Describe assumptions and technical risks.
4. Only then start modifying code.

For difficult or ambiguous tasks, plan first before implementation.

## Project priorities

When working on synergy features, prioritize:
1. Correctness of game-mechanical interpretation
2. Explainability of results
3. Extensibility of ontology and rules
4. Testability
5. Performance after correctness

Do not optimize prematurely if it reduces clarity.

## Core design rules

### 1. Mechanics-first modeling
Do not rely primarily on Oracle text overlap or keyword frequency.
Model cards by their mechanical behavior.

Each card should be representable through normalized structures such as:
- abilities
- produces
- rewards
- requires
- replaces
- prevents
- amplifies
- moves
- target_roles
- plans
- roles

### 2. Extensible ontology
Do not hardcode a brittle closed list of events.
Use an extensible registry/schema for gameplay events and zone/resource transitions.

Support both broad and scoped events, for example:
- DRAW_CARD
- DISCARD_CARD
- GAIN_LIFE
- LOSE_LIFE
- CREATE_TOKEN
- SACRIFICE_PERMANENT
- ETB
- DIES
- ATTACKS
- CAST_SPELL
- EXILE_CARD
- MILL_CARD
- RETURN_FROM_GRAVEYARD
- SELF_DRAW_CARD
- OPPONENT_DRAW_CARD
- CREATURE_DIES
- ARTIFACT_ETB
- ENCHANTMENT_ETB
- LAND_ENTERS
- NONCREATURE_SPELL_CAST
- TOKEN_CREATED
- CARD_DISCARDED
- COMBAT_DAMAGE_TO_PLAYER

These examples are illustrative, not exhaustive.

### 3. Mechanic expansion
Preserve both:
- official keywords/mechanics
- expanded mechanical meaning

Named mechanics must be expandable into normalized effects when relevant.
Examples include:
- connive
- cycling
- dredge
- surveil
- exploit
- madness
- flashback
- cascade
- discover
- populate
- investigate
- casualty
- lifelink
- foretell
- delve
- escape
- blitz
- offspring

The system must remain easy to extend for future mechanics.

### 4. Synergy must generalize
Do not solve for one showcase card or one archetype only.
Support:
- direct synergy
- indirect synergy
- asymmetric synergy
- package synergy
- anti-synergy
- context-sensitive synergy

### 5. Pairwise and multi-card reasoning
Do not limit the system to A <-> B card matching.
Support:
- pairwise scoring
- package / line detection for 3+ cards

Examples of package structures:
- setup + converter + payoff
- token maker + sacrifice outlet + death payoff
- tutor + combo piece + payoff
- graveyard setup + reanimation spell + premium target
- engine + fuel + amplifier

### 6. Anti-synergy is first-class
Model anti-synergy explicitly, including:
- replacement conflicts
- prevention conflicts
- contradictory resource usage
- graveyard tension
- hand-size tension
- tempo mismatch
- strategic incoherence

## Output expectations

When returning synergy results:
- always include a numeric score
- include directional reasoning when relevant
- include human-readable reasons
- include matched events or roles
- prefer explanations that help debug the engine

Bad output:
- vague “these cards seem similar”
- text-overlap-only reasoning
- hidden heuristics with no explanation

Good output:
- “Produces DRAW_CARD via connive”
- “Rewards CREATURE_DIES events”
- “Conflicts because it replaces DRAW_CARD”
- “Completes a graveyard setup -> reanimation -> ETB payoff line”

## API expectations

When adding or changing endpoints:
- keep request/response schemas explicit
- validate inputs
- preserve backward compatibility unless explicitly instructed otherwise
- document behavior changes
- return explanations, not only scores

## Testing expectations

Any meaningful logic change should include tests.

Prioritize tests for:
- ontology registration
- normalized card output
- mechanic expansion
- replacement/prevention behavior
- pairwise synergy scoring
- anti-synergy detection
- package detection
- regression tests for previously fixed cases

Add tests that prove the system is not just text similarity.

## Performance expectations

Use simple, understandable logic first.
Only optimize when a clear bottleneck appears.
If you optimize, preserve correctness and explainability.

## Documentation expectations

When behavior changes:
- update the relevant docs
- explain assumptions
- describe tradeoffs
- document how to add new mechanics/events/rules

## Do-not rules

- Do not silently change unrelated architecture.
- Do not add opaque heuristics without documenting them.
- Do not hardcode card-specific hacks unless explicitly marked as temporary.
- Do not claim a card “produces” an event if it only references, replaces, or prevents it.
- Do not collapse “produce”, “reward”, “replace”, and “prevent” into the same category.
- Do not ship scoring logic without tests.

## Preferred workflow for large tasks

1. Inspect repo
2. Propose concise plan
3. Implement in small steps
4. Run targeted tests
5. Run broader test suite if available
6. Summarize files changed, assumptions, tradeoffs, and next steps