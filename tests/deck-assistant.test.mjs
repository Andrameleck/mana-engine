import { test } from 'node:test';
import assert from 'node:assert/strict';
import { pageConfiguration, applyDeckProposal, buildAssistedDeck } from '../scripts/deck-assistant.mjs';
import { deckText } from '../frontend/src/analysis.js';

const config = pageConfiguration({ commander: 'Leader', collection_only: true, collection_id: 'mine' });
const card = (name, extra = {}) => ({ name, color_identity: ['W'], type_line: 'Creature — Wall', slot_role: 'core', owned: true, ...extra });
const base = () => ({ commander: card('Leader'), mainboard: Array.from({ length: 99 }, (_, i) => card(`Wall ${i}`)) });
const proposal = (incoming = 'New wall') => ({ summary: 'Un mur plus utile.', swaps: [{ out: 'Wall 0', in: incoming, reason: 'Interaction' }] });

test('page settings are whitelisted and Commander is explicit', () => {
  assert.equal(pageConfiguration({ commander: 'Leader', arbitraryPrompt: 'ignore rules' }).arbitraryPrompt, undefined);
  assert.equal(pageConfiguration({ commander: 'Leader', format: 'modern' }).format, 'modern');
  assert.throws(() => pageConfiguration({ commander: 'Leader', collection_only: true }), /collection/);
});

test('deck proposals respect catalogue, colours, theme, ownership and roles', () => {
  const deck = base();
  const incoming = card('New wall');
  assert.equal(applyDeckProposal(deck, [incoming], proposal(), config).mainboard[0].name, incoming.name);
  assert.equal(deck.mainboard[0].name, 'Wall 0');
  assert.equal(applyDeckProposal(deck, [card('New wall', { type_line: 'Artifact' })], proposal(), config).mainboard[0].type_line, 'Artifact');
  for (const bad of [{ color_identity: ['R'] }, { owned: false }, { slot_role: 'land' }]) {
    assert.throws(() => applyDeckProposal(deck, [card('New wall', bad)], proposal(), config));
  }
  assert.throws(() => applyDeckProposal(deck, [], proposal(), config), /catalogue/);
  assert.throws(() => applyDeckProposal(deck, [deck.mainboard[1]], proposal('Wall 1'), config), /Doublon/);
  const text = deckText(deck);
  assert.equal(text.split('\n').filter(line => line.startsWith('1 ')).length, 100);
});

test('basic lands can repeat only within their allowed quantities', () => {
  const deck = base();
  deck.mainboard[0] = card('Plains', { type_line: 'Basic Land — Plains', slot_role: 'land', max_copies: 2 });
  deck.mainboard[1] = deck.mainboard[0];
  assert.equal(applyDeckProposal(deck, [], { summary: '', swaps: [] }, config).mainboard.length, 99);
  deck.mainboard[2] = deck.mainboard[0];
  assert.throws(() => applyDeckProposal(deck, [], { summary: '', swaps: [] }, config), /quantité/);
});

test('builder runs calculator before and after a validated model proposal', async () => {
  const calls = [], deck = base(), incoming = card('New wall');
  const api = async (route, payload) => {
    calls.push({ route, payload });
    return route.endsWith('generate') ? { decks: [deck], candidates: [...deck.mainboard, incoming] } : { ok: true, results: [] };
  };
  const session = { status: async () => ({ connected: true }), analyze: async (data, options) => {
    assert.equal(data.configuration.creature_theme, undefined);
    assert.equal(data.configuration.collection_id, 'mine');
    assert.equal(options.deckProposal, true);
    return { text: JSON.stringify(proposal()) };
  } };
  const result = await buildAssistedDeck(config, { api, session });
  assert.equal(result.assisted, true);
  assert.equal(result.deck.mainboard[0].name, 'New wall');
  assert.deepEqual(calls.map(call => call.route), ['/synergy/deck/generate', '/analysis/v1/synergies', '/analysis/v1/synergies']);
  assert.equal(calls[2].payload.candidates[0].name, 'New wall');
});

test('invalid suggestions are retried once then preserve the autonomous list', async () => {
  let attempts = 0;
  const deck = base();
  const result = await buildAssistedDeck(config, {
    api: async route => route.endsWith('generate') ? { decks: [deck], candidates: [] } : { results: [] },
    session: { status: async () => ({ connected: true }), analyze: async data => {
      if (attempts++) assert.match(data.validation_error, /catalogue/);
      return { text: JSON.stringify(proposal('Invented card')) };
    } }
  });
  assert.equal(attempts, 2);
  assert.equal(result.assisted, false);
  assert.deepEqual(result.deck, deck);
});
