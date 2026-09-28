import { test } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { createAssistantServer, CodexSession } from '../scripts/assistant-server.mjs';
import { analyzeStrategy, engineCard } from '../frontend/src/analysis.js';

test('functional API results map canonical identifiers and preserve uncertainty', async () => {
  const previous = global.fetch;
  const calls = [];
  global.fetch = async (url, options) => {
    calls.push([url, JSON.parse(options.body)]);
    return { ok: true, json: async () => ({ ok: true, results: url.endsWith('synergies')
      ? [{ candidate_id: 'wall-of-omens', coverage_attested: 0, status: 'unknown', unknown_conditions: ['timing'] }]
      : [{ card_ids: ['arcades', 'wall-of-omens'], status: 'unknown', unknown_conditions: ['timing'] }] }) };
  };
  try {
    const result = await analyzeStrategy({ key: 'arcades', name: 'Arcades' }, [{ key: 'wall of omens', name: 'Wall of Omens' }], 12, 6);
    assert.equal(result.entries[0].card.name, 'Wall of Omens');
    assert.match(result.entries[0].evidence, /timing/);
    assert.equal(result.groups[0].cards.length, 2);
    assert.equal(calls[1][1].max_pair_evaluations, 1200);
    assert.deepEqual(calls.map(call => call[0]), ['/analysis/v1/synergies', '/analysis/v1/groups']);
  } finally { global.fetch = previous; }
});

test('no lexical fallback on API failure; unknown Oracle stays unknown', async () => {
  const previous = global.fetch;
  global.fetch = async () => ({ ok: false, json: async () => ({ error: 'offline' }) });
  try { await assert.rejects(analyzeStrategy({ name: 'Seed' }, [], 1, 1), /offline/); }
  finally { global.fetch = previous; }
  assert.equal(engineCard({ name: 'French', row: { printed_text: 'Piochez une carte.' } }).oracle_text, '');
});

test('gateway rejects other sites and proxies autonomous requests without touching Codex', async t => {
  let calls = 0;
  const upstream = http.createServer((req, res) => res.end('autonomous'));
  await new Promise(resolve => upstream.listen(0, '127.0.0.1', resolve));
  const server = createAssistantServer({ upstream: `http://127.0.0.1:${upstream.address().port}`, session: {
    status: async () => { calls++; return { connected: true }; }
  } });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => { server.closeAllConnections(); server.close(); upstream.closeAllConnections(); upstream.close(); });
  const base = `http://127.0.0.1:${server.address().port}`;
  assert.equal(await (await fetch(`${base}/health`)).text(), 'autonomous');
  assert.equal(calls, 0);
  const headers = { 'Content-Type': 'application/json', 'X-Mana-Client': '1' };
  assert.equal((await fetch(`${base}/ai/status`, { method: 'POST', headers: { ...headers, Origin: 'https://evil.example' }, body: '{}' })).status, 403);
  assert.equal((await fetch(`${base}/ai/status`, { method: 'POST', body: '{}' })).status, 403);
  assert.equal(calls, 0);
  assert.deepEqual(await (await fetch(`${base}/ai/status`, { method: 'POST', headers, body: '{}' })).json(), { connected: true });
  assert.equal(calls, 1);
});

test('Codex protocol ignores unrelated threads and refuses approval requests', () => {
  const session = new CodexSession();
  const sent = []; session.send = value => sent.push(value);
  let output;
  session.active = { threadId: 'ours', messages: [], resolve: value => { output = value; }, reject: () => assert.fail() };
  session.receive({ method: 'item/completed', params: { threadId: 'other', item: { type: 'agentMessage', text: 'wrong' } } });
  session.receive({ id: 3, method: 'item/commandExecution/requestApproval' });
  assert.equal(sent[0].error.code, -32601);
  session.receive({ method: 'item/completed', params: { threadId: 'ours', item: { type: 'agentMessage', text: 'Advice' } } });
  session.receive({ method: 'turn/completed', params: { threadId: 'ours', turn: { status: 'completed' } } });
  assert.equal(output, 'Advice');
});

test('authenticated analysis starts an isolated turn and cleans up the thread', async () => {
  const session = new CodexSession();
  session.status = async () => ({ connected: true });
  const methods = [];
  session.rpc = async (method, params) => {
    methods.push(method);
    if (method === 'thread/start') {
      assert.equal(params.ephemeral, true);
      assert.equal(params.approvalPolicy, 'never');
      assert.equal(params.sandbox, 'read-only');
      return { thread: { id: 'test' } };
    }
    if (method === 'turn/start') {
      session.receive({ method: 'item/completed', params: { threadId: 'test', item: { type: 'agentMessage', text: 'Suggestions à tester' } } });
      session.receive({ method: 'turn/completed', params: { threadId: 'test', turn: { status: 'completed' } } });
    }
    return {};
  };
  assert.deepEqual(await session.analyze({ cards: [], report: {}, objective: 'Murs' }), { text: 'Suggestions à tester' });
  assert.deepEqual(methods, ['thread/start', 'turn/start', 'thread/archive']);
  assert.equal(session.busy, false);
  session.status = async () => ({ connected: false });
  await assert.rejects(session.analyze({}), /Connectez/);
  assert.equal(session.busy, false);
});

test('both shipped interfaces use server analysis and share the same adapter', async () => {
  assert.equal(await readFile('frontend/src/analysis.js', 'utf8'), await readFile('inst/www/analysis.js', 'utf8'));
  for (const file of ['frontend/src/main.js', 'inst/www/main.js']) {
    const source = await readFile(file, 'utf8');
    assert.match(source, /await analyzeStrategy\(/);
    assert.match(source, /await analyzeDeck\(/);
    assert.doesNotMatch(source, /const synergy = computeSynergy/);
    assert.doesNotMatch(source, /const direct = computeDirectSynergies/);
  }
});
