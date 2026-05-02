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

### 4.1 Role-aware bidirectional pair scoring

Synergy scoring must not be reduced to a single directional score such as
`score(target, candidate)`.

A card pair must be evaluated as a functional relationship between two cards,
computed at the **pair level**, not at the seed level. Concretely the engine
must always produce both directions and the inferred role of each card before
combining them into a final pair score:

- `candidate_feeds_seed`: candidate produces events/resources that the seed consumes, rewards, amplifies, or requires.
- `seed_feeds_candidate`: seed produces events/resources that the candidate consumes, rewards, amplifies, or requires.
- `mutual_feedback`: both cards feed each other in a meaningful loop or reinforcing pattern.
- `tool_support`: one card improves the reliability, protection, mana access, recursion, tutoring, filtering, or setup of the other without necessarily producing a directly consumed event.
- `anti_synergy`: one card prevents, replaces, competes with, or strategically undermines the other.

#### Direction-invariant role inference

The functional role of a card in a pair is a property of the card and the
relationship, not a property of which card was passed in as the seed.

For any pair `(A, B)`:

- The role inferred for `A` must be the same whether `A` is the seed or the candidate.
- The role inferred for `B` must be the same whether `B` is the seed or the candidate.
- The `final_pair_score` must be symmetric up to small, documented bonuses
  for input-context information (for example, knowing the seed's archetype
  shell). It must not change qualitatively just because the inputs were swapped.

If the engine returns very different scores for `score_pair(A, B)` and
`score_pair(B, A)`, that asymmetry is a bug to investigate, not the intended
behavior.

The final pair score must be role-aware. It should not be a naive average of
both directions.

For example, if card A is an engine and card B is a payoff:

- A may strongly feed B.
- B may not feed A.
- This should still be scored as a strong synergy if the functional role is clear.
- A must be reported as `engine / enabler` and B as `payoff / reward`
  whether the caller passed `(A, B)` or `(B, A)`.

Missing reverse synergy must not strongly penalize a specialized card.
A payoff does not need to be an engine to be synergistic with an engine.

The scorer should infer possible roles for each card in the pair, such as:

- engine / enabler
- payoff / reward
- amplifier
- fuel
- tool / support
- stabilizer
- protection
- recursion
- tutor / consistency piece
- anti-synergy piece

The final pair score should be based primarily on the strongest meaningful
functional contribution, with optional bonuses for:

- bidirectional reinforcement
- role versatility
- repeatability
- scalability
- archetype alignment
- reliability in the expected shell

The final pair score may be penalized for:

- mana or color shell dependency
- hard-to-satisfy conditions
- timing mismatch
- resource competition
- replacement/prevention conflicts
- strategic incoherence

Do not collapse the two directions into a single unexplained value.
Always preserve directional details in the explanation.

Good pair output:

- `candidate_feeds_seed_score: 71`
- `seed_feeds_candidate_score: 56`
- `dominant_role: candidate_as_payoff`
- `final_pair_score: 70`
- `reason: Seed produces SELF_DRAW_CARD via connive; candidate rewards SELF_DRAW_CARD via life gain trigger.`

Bad pair output:

- `score: 56`
- `reason: Some reciprocal synergy exists.`

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

### 5.1 Group scoring and seed-centered package analysis

For groups of three or more cards, synergy scoring must not only compare each
candidate independently against the input seed.

The system must evaluate:

1. Seed-to-card interactions
2. Card-to-seed interactions
3. Candidate-to-candidate interactions inside the proposed group
4. Multi-card lines where no single pair explains the whole synergy
5. Role coverage across the package

When a user provides a seed card and asks for synergistic groups, the engine
should compute all meaningful directional interactions involving:

- the seed card
- each candidate card
- interactions between candidates themselves

For a group `G = {seed, c1, c2, c3...}`, the engine should produce:

- pair scores between `seed` and each candidate
- pair scores between candidates when relevant
- detected package structures
- role distribution
- anti-synergy or tension inside the group
- final group score

The group score should account for both:

- direct usefulness around the seed
- internal coherence of the package

A group should score higher when the cards form an explainable line such as:

- setup -> converter -> payoff
- engine -> fuel -> payoff
- token maker -> sacrifice outlet -> death payoff
- discard outlet -> graveyard setup -> reanimation payoff
- draw engine -> life gain payoff -> life gain reward
- tutor -> combo piece -> payoff
- protection -> engine -> payoff

A group should not score highly just because every card has some isolated
relationship with the seed. The group must be mechanically coherent.

Example:

Seed:
- Raffine, Scheming Seer

Candidates:
- Sheoldred, the Apocalypse
- Morbid Opportunist
- Lilianna's Standard Bearer

The engine should evaluate:

- Raffine -> Sheoldred:
  Raffine produces SELF_DRAW_CARD via connive; Sheoldred rewards SELF_DRAW_CARD.
- Morbid Opportunist -> Sheoldred:
  Morbid Opportunist produces SELF_DRAW_CARD from CREATURE_DIES; Sheoldred rewards SELF_DRAW_CARD.
- Creature death events -> Lilianna's Standard Bearer:
  Lilianna's Standard Bearer converts prior CREATURE_DIES events into burst draw.
- Internal package:
  death/card-draw/life-gain package with multiple draw producers and one major draw payoff.

The final group explanation should include the detected line, for example:

`attack / death events -> draw events -> Sheoldred life gain payoff`

Group scoring must preserve explainability. It should expose which interactions
contributed to the final score and which cards are engines, payoffs, tools,
amplifiers, or fuel.

Role inference inside a group follows the same direction-invariant rule as
pair scoring (see § 4.1): a card's role in the group must be derived from
the card and its mechanical relationships, not from whether it happened to be
the input seed. Swapping the seed for another member of the same group must
not relabel a payoff as an engine or vice versa, and must not radically
change the final group score.

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

When returning pairwise synergy results, include:

- final_pair_score
- directional scores
- dominant functional relationship
- inferred role of the candidate relative to the seed
- inferred role of the seed relative to the candidate
- matched produced/consumed/rewarded/prevented/replaced events
- reliability and condition notes
- shell or mana dependency notes when relevant

When returning group synergy results, include:

- final_group_score
- pairwise interactions that contributed to the group score
- internal candidate-to-candidate interactions
- detected package lines
- role distribution
- anti-synergy or tension
- explanation of why the group is coherent or not coherent

Do not return only a single score for a group without showing how the score was
assembled.

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

Add regression tests for role-aware bidirectional scoring.

Required cases:

1. Engine -> payoff pair
   - If card A produces an event and card B rewards it, the pair should score
     highly even if B does not feed A.
   - The final score must not be a naive average of both directions.

2. Payoff seed -> engine candidate
   - If the seed is a payoff and the candidate is an engine, the candidate
     should be recognized as `candidate_as_engine`.

3. Engine seed -> payoff candidate
   - If the seed is an engine and the candidate is a payoff, the candidate
     should be recognized as `candidate_as_payoff`.

4. Specialized role preservation
   - A specialized payoff should not be strongly penalized for failing to act
     as an engine.
   - A specialized engine should not be strongly penalized for failing to act
     as a payoff.

5. Group scoring
   - A group with setup -> converter -> payoff should score higher than a group
     of isolated pairwise matches.
   - Candidate-to-candidate interactions must contribute to group explanations.
   - Anti-synergy inside a group must reduce or annotate the group score.

6. Regression case
   - Raffine, Scheming Seer and Sheoldred, the Apocalypse should produce a
     strong role-aware pair score because Raffine produces SELF_DRAW_CARD via
     connive and Sheoldred rewards SELF_DRAW_CARD.
   - The explanation must identify Raffine as engine/enabler and Sheoldred as
     payoff/reward.
   - These role labels and the final pair score must hold regardless of which
     of the two cards is supplied as the seed and which as the candidate.
     `score_pair(Raffine, Sheoldred)` and `score_pair(Sheoldred, Raffine)`
     must return the same role assignment for each card and must not differ
     by more than a small, documented margin in `final_pair_score`.

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