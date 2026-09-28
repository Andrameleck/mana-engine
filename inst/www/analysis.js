// Shared by the Vite application and the packaged Plumber UI.
export const array = (value) => value == null ? [] : Array.isArray(value) ? value : [value];

export function engineCard(card) {
  const row = card.row || card;
  const colors = row.color_identity;
  return {
    id: String(card.key || row.id || row.name).trim().toLowerCase().replace(/[^a-z0-9]+/g, '-'),
    name: row.name_en || card.name || row.name,
    oracle_text: row.analysis_text || row.oracle_text || '',
    type_line: row.type_line || row.type || '',
    mana_cost: row.mana_cost || '',
    ...(colors == null ? {} : { color_identity: Array.isArray(colors) ? colors : String(colors).match(/[WUBRG]/g) || [] })
  };
}

export async function engineRequest(kind, payload) {
  const response = await fetch(`/analysis/v1/${kind}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload), signal: AbortSignal.timeout(180000)
  });
  const result = await response.json();
  if (!response.ok || result.ok !== true) throw new Error(result.error || 'Moteur de calcul indisponible');
  return result;
}

export async function analyzeStrategy(seed, cards, directLimit, groupLimit) {
  const candidates = cards.map(engineCard);
  const direct = await engineRequest('synergies', { seed: engineCard(seed), candidates, limit: directLimit });
  const byId = new Map(cards.map(card => [engineCard(card).id, card]));
  byId.set(engineCard(seed).id, seed);
  const entries = array(direct.results).map(result => ({
    card: byId.get(result.candidate_id), score: result.coverage_attested,
    evidence: `${result.status} | ${array(result.explanation).join(' ; ')} | réserves : ${array(result.unknown_conditions).join(', ') || 'aucune condition supplémentaire détectée'}`
  })).filter(entry => entry.card);
  // Explicitly bound the quadratic search to the seed and the displayed candidates.
  const pool = [seed, ...entries.map(entry => entry.card)];
  const grouped = await engineRequest('groups', { cards: pool.map(engineCard), limit: groupLimit, max_pair_evaluations: 1200 });
  const groups = array(grouped.results).map(result => ({
    cards: array(result.card_ids).map(id => byId.get(id)).filter(Boolean),
    score: result.coverage_attested,
    lineA: array(result.explanation).join(' ; '),
    lineB: `${result.status} | ${array(result.unknown_conditions).join(', ')}`,
    evidence: result.status
  }));
  return { entries, groups, report: { direct, grouped }, pool: pool.map(engineCard) };
}

export async function analyzeDeck(deck, collection, stillCurrent = () => true) {
  const keys = new Set(deck.map(card => card.key));
  const knownIdentity = deck.every(card => card.row?.color_identity != null);
  const allowedColors = [...new Set(deck.flatMap(card => engineCard(card).color_identity || []))];
  const available = collection.filter(card => !keys.has(card.key));
  const candidateLimit = Math.max(1, Math.floor(1200 / Math.max(1, deck.length)));
  const candidates = available.slice(0, candidateLimit);
  const byId = new Map(candidates.map(card => [engineCard(card).id, card]));
  const found = new Map();
  // Each card is an anchor, rather than a locally guessed lexical 'core'.
  for (const seed of deck) {
    if (!stillCurrent()) throw new Error('Analyse remplacée');
    const result = await engineRequest('synergies', {
      seed: engineCard(seed), candidates: candidates.map(engineCard), limit: 20,
      context: { mode: 'deck', ...(knownIdentity ? { allowed_colors: allowedColors } : {}) }
    });
    for (const entry of array(result.results)) {
      const previous = found.get(entry.candidate_id);
      if (!previous || entry.coverage_attested > previous.improveScore) found.set(entry.candidate_id, {
        card: byId.get(entry.candidate_id), improveScore: entry.coverage_attested,
        variationScore: entry.coverage_potential,
        reason: `${entry.status} : ${array(entry.explanation).join(' ; ')}`
      });
    }
  }
  const ranked = [...found.values()].filter(entry => entry.card).sort((a, b) => b.improveScore - a.improveScore);
  return { mechanics: [], upgrades: ranked.slice(0, 10), variants: ranked.slice(10, 20),
    note: `${candidates.length}/${available.length} candidats examinés contre ${deck.length} cartes du deck ; sélection dans l’ordre de la collection. ${candidates.length < available.length ? 'Recherche partielle (budget de 1 200 paires).' : ''}` };
}

export async function aiRequest(action, body = {}) {
  const response = await fetch(`/ai/${action}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Mana-Client': '1' },
    body: JSON.stringify(body), signal: AbortSignal.timeout(action === 'build' ? 600000 : 240000)
  });
  const data = await response.json();
  if (!response.ok || data.error) throw new Error(data.error || 'Assistant indisponible');
  return data;
}

export function mountAssistant() {
  const anchor = document.getElementById('strategy-status');
  if (!anchor) return;
  const section = document.createElement('section');
  section.innerHTML = `<label>Action <select id="ai-task"><option value="synergies">Analyser les synergies</option><option value="deck">Construire un deck Commander</option></select></label>
    <label>Créatures du deck <select id="ai-creature-theme"><option value="any">Tous les types</option><option value="walls">Murs uniquement (sauf commandant)</option></select></label>
    <p>Construction : la carte choisie devient le commandant. Désactiver les cartes connues limite la liste à la collection sélectionnée. Format Commander, 100 cartes, cartes bannies exclues. Le filtre mana et Spellbook concernent l’analyse de synergies ; l’identité du commandant détermine les couleurs du deck.</p>
    <label><input id="ai-enabled" type="checkbox"> Utiliser ChatGPT avec ces réglages</label>
    <button type="button" id="ai-login">Connecter ChatGPT</button>
    <button type="button" id="ai-check">Vérifier la connexion</button>
    <button type="button" id="ai-logout">Déconnecter</button>
    <p id="ai-status" role="status">Facultatif : connexion via Codex, sans clé API. Le mode autonome reste disponible.</p>
    <p>En activant ce mode, les cartes analysées et les réglages sont envoyés à OpenAI avec votre compte. Aucun prompt à rédiger.</p>
    <div id="ai-deck-result" aria-live="polite"></div>
    <pre id="ai-result" style="white-space:pre-wrap" aria-live="polite"></pre>`;
  anchor.after(section);
  const task = section.querySelector('#ai-task');
  const updateTask = () => {
    section.querySelector('#ai-creature-theme').disabled = task.value !== 'deck';
    const button = document.getElementById('strategy-run-btn');
    if (button) button.textContent = task.value === 'deck' ? 'Construire le deck' : 'Calculer';
  };
  task.addEventListener('change', updateTask);
  updateTask();
  const status = section.querySelector('#ai-status');
  for (const [id, action] of [['ai-login', 'login'], ['ai-check', 'status'], ['ai-logout', 'logout']]) {
    section.querySelector(`#${id}`).addEventListener('click', async (event) => {
      event.target.disabled = true;
      try {
        const result = await aiRequest(action);
        status.textContent = result.connected ? 'Compte ChatGPT connecté.' : 'Compte ChatGPT non connecté.';
        if (result.authUrl) {
          const url = new URL(result.authUrl);
          if (url.protocol !== 'https:' || !['auth.openai.com', 'auth0.openai.com', 'chatgpt.com'].includes(url.hostname)) throw new Error('Adresse de connexion inattendue');
          const link = document.createElement('a');
          link.href = url.href; link.target = '_blank'; link.rel = 'noopener noreferrer';
          link.textContent = 'Ouvrir la connexion ChatGPT, puis vérifier la connexion';
          status.replaceChildren(link);
        }
      } catch (error) { status.textContent = `Assistant indisponible : ${error.message}. Utilisez le lancement local avec assistant.`; }
      finally { event.target.disabled = false; }
    });
  }
}

export async function explainWithAssistant(analysis, stillCurrent = () => true, configuration = {}) {
  const target = document.getElementById('ai-result');
  target.textContent = '';
  if (!document.getElementById('ai-enabled')?.checked) return;
  target.textContent = 'Interprétation en cours…';
  try {
    const result = await aiRequest('analyze', { cards: analysis.pool, report: analysis.report,
      configuration });
    if (stillCurrent()) target.textContent = result.text;
  } catch (error) {
    if (stillCurrent()) target.textContent = `Les calculs restent disponibles. Analyse IA indisponible : ${error.message}`;
  }
}

export function deckText(deck) {
  return `Commander\n1 ${deck.commander.name}\n\nDeck\n${deck.mainboard.map(card => `1 ${card.name}`).join('\n')}\n`;
}

export async function buildDeckFromPage(configuration, stillCurrent = () => true) {
  const target = document.getElementById('ai-deck-result');
  const status = document.getElementById('strategy-status');
  const assisted = document.getElementById('ai-enabled').checked;
  const settings = { ...configuration, format: 'commander', exclude_banned: true, variant_count: 1 };
  target.replaceChildren();
  document.getElementById('ai-result').textContent = '';
  const button = document.getElementById('strategy-run-btn');
  button.disabled = true;
  status.textContent = assisted ? 'Construction : préparation du moteur, ajustements IA puis vérification…' : 'Construction autonome à partir des réglages…';
  try {
    let result;
    if (assisted) result = await aiRequest('build', { configuration: settings });
    else {
      const response = await fetch('/synergy/deck/generate', { method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(settings), signal: AbortSignal.timeout(180000) });
      const generated = await response.json();
      if (!response.ok || !generated.ok) throw new Error(generated.error || 'Construction impossible');
      result = { deck: generated.decks[0], configuration: settings, summary: 'Liste autonome du moteur.',
        warning: 'La légalité des cartes sans métadonnées et la puissance restent à vérifier.' };
    }
    if (!stillCurrent()) return;
    const description = document.createElement('p');
    description.textContent = `${result.configuration.commander} · Commander · ${settings.collection_only ? 'collection uniquement' : 'catalogue autorisé'} · ${settings.creature_theme === 'walls' ? 'créatures Murs' : 'tous types'}. ${result.summary || ''} ${result.warning || ''}`;
    const changes = document.createElement('ul');
    for (const swap of result.swaps || []) {
      const item = document.createElement('li'); item.textContent = `${swap.out} → ${swap.in} : ${swap.reason}`; changes.append(item);
    }
    const output = document.createElement('pre'); output.textContent = deckText(result.deck);
    const download = document.createElement('button'); download.type = 'button'; download.textContent = 'Télécharger le deck (.txt)';
    download.addEventListener('click', () => {
      const url = URL.createObjectURL(new Blob([output.textContent], { type: 'text/plain;charset=utf-8' }));
      const link = document.createElement('a'); link.href = url; link.download = 'mana-engine-commander.txt'; link.click();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
    });
    target.replaceChildren(description, changes, download, output);
    if (result.report) {
      const details = document.createElement('details');
      const summary = document.createElement('summary'); summary.textContent = 'Résultats du recalcul';
      const evidence = document.createElement('pre');
      evidence.style.whiteSpace = 'pre-wrap';
      evidence.textContent = JSON.stringify(result.report, null, 2);
      details.append(summary, evidence); target.append(details);
    }
    status.textContent = `${result.deck.mainboard.length + 1} cartes proposées — ${result.assisted ? 'ajustements IA vérifiés par le moteur' : 'mode autonome'}.`;
  } catch (error) { if (stillCurrent()) status.textContent = `Construction impossible : ${error.message}`; }
  finally { button.disabled = false; }
}
