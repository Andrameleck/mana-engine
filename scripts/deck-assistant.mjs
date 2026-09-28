// The model proposes changes; only server-side catalogue records may enter a deck.
export function pageConfiguration(input) {
  if (!input || typeof input !== 'object') throw new Error('Configuration manquante');
  const commander = String(input.commander || '').trim();
  if (!commander || commander.length > 200) throw new Error('Choisissez une carte de départ.');
  const format = input.format || 'commander';
  if (!/^[a-z]{2,24}$/.test(format)) throw new Error('Format invalide');
  const collection_id = String(input.collection_id || '').trim();
  if (collection_id.length > 200) throw new Error('Collection invalide');
  if (input.collection_only === true && !collection_id) throw new Error('Choisissez une collection.');
  if (input.creature_theme && input.creature_theme !== 'any') throw new Error('Le filtre de type spécialisé a été supprimé.');
  const color_identity = input.color_identity || [];
  if (!Array.isArray(color_identity) || color_identity.some(color => !['W', 'U', 'B', 'R', 'G', 'C'].includes(color))) throw new Error('Couleurs invalides');
  return { commander, collection_id, collection_only: input.collection_only === true,
    format, exclude_banned: input.exclude_banned !== false, variant_count: 1, color_identity };
}

const key = name => String(name).trim().toLowerCase();
const list = value => value == null ? [] : Array.isArray(value) ? value : [value];
export const deckProposalSchema = {
  type: 'object', additionalProperties: false, required: ['summary', 'swaps'],
  properties: {
    summary: { type: 'string' },
    swaps: { type: 'array', maxItems: 12, items: {
      type: 'object', additionalProperties: false, required: ['out', 'in', 'reason'],
      properties: { out: { type: 'string' }, in: { type: 'string' }, reason: { type: 'string' } }
    } }
  }
};

export function applyDeckProposal(deck, candidates, proposal, configuration) {
  if (!proposal || typeof proposal.summary !== 'string' || !Array.isArray(proposal.swaps) || proposal.swaps.length > 12) throw new Error('Proposition IA invalide');
  const catalogue = new Map(candidates.map(card => [key(card.name), card]));
  const mainboard = [...deck.mainboard];
  const rules = deck.format_rules || { requires_commander: true, mainboard_size: 99, max_copies: 1 };
  const identity = new Set(rules.requires_commander ? list(deck.commander.color_identity) : configuration.color_identity?.length ? configuration.color_identity.filter(color => color !== 'C') : ['W', 'U', 'B', 'R', 'G']);
  const removed = new Set();
  for (const swap of proposal.swaps) {
    const out = key(swap.out), incoming = catalogue.get(key(swap.in));
    const index = mainboard.findIndex(card => key(card.name) === out);
    if (index < 0 || removed.has(out) || !incoming || typeof swap.reason !== 'string') throw new Error('Remplacement hors catalogue ou carte absente');
    if (list(incoming.color_identity).some(color => !identity.has(color))) throw new Error('Identité couleur incompatible');
    if (configuration.collection_only && incoming.owned !== true) throw new Error('Carte hors collection');
    if (rules.requires_commander && key(incoming.name) === key(deck.commander.name)) throw new Error('Le commandant doit rester séparé');
    // Maintain the structural role balance prepared by the deterministic builder.
    if (incoming.slot_role !== mainboard[index].slot_role) throw new Error('Le remplacement change la répartition des rôles');
    mainboard[index] = incoming;
    removed.add(out);
  }
  if (mainboard.length !== rules.mainboard_size) throw new Error('Deck incomplet');
  if (!rules.requires_commander && !mainboard.some(card => key(card.name) === key(deck.commander.name))) throw new Error('La carte de départ doit rester dans le deck');
  const counts = new Map();
  for (const card of mainboard) {
    const name = key(card.name), count = (counts.get(name) || 0) + 1;
    counts.set(name, count);
    const maximum = card.max_copies ?? rules.max_copies;
    if (count > maximum) throw new Error('Doublon ou quantité de collection dépassée');
  }
  return { ...deck, mainboard };
}

export async function buildAssistedDeck(configuration, { api, session }) {
  const settings = pageConfiguration(configuration);
  // Check login before doing potentially expensive catalogue work.
  if (!(await session.status()).connected) throw new Error('Connectez votre compte ChatGPT.');
  const generated = await api('/synergy/deck/generate', { ...settings, include_candidates: true });
  const base = generated.decks?.[0];
  if (!base || base.mainboard?.length !== (base.format_rules?.mainboard_size || 99)) throw new Error('Le moteur n’a pas produit de deck complet');
  const candidates = generated.candidates || [];
  const context = { format: settings.format, mode: 'deck', allowed_colors: generated.allowed_colors ?? (base.requires_commander !== false ? list(base.commander.color_identity) : settings.color_identity.length ? settings.color_identity.filter(color => color !== 'C') : ['W', 'U', 'B', 'R', 'G']) };
  const report = await api('/analysis/v1/synergies', { seed: base.commander, candidates: base.mainboard, context, limit: 99 });
  const data = { configuration: settings, initial_deck: base, allowed_candidates: candidates, calculator: report };
  let proposal, finalDeck, validationError;
  for (let attempt = 0; attempt < 2; attempt++) {
    let answer;
    try { answer = await session.analyze({ ...data, validation_error: validationError || null }, { deckProposal: true }); }
    catch (error) { validationError = `Assistant indisponible : ${error.message}`; break; }
    try {
      proposal = JSON.parse(answer.text);
      finalDeck = applyDeckProposal(base, candidates, proposal, settings);
      break;
    } catch (error) { validationError = error.message; }
  }
  if (!finalDeck) return { ok: true, assisted: false, configuration: settings, deck: base, report,
    warning: `Proposition IA rejetée après vérification : ${validationError}. Liste autonome conservée.`, swaps: [] };
  const finalReport = await api('/analysis/v1/synergies', { seed: finalDeck.commander, candidates: finalDeck.mainboard, context, limit: 99 });
  // Do not retain aggregate scores from the unmodified base list.
  delete finalDeck.total_score; delete finalDeck.score_base; delete finalDeck.score_modifiers;
  const owned = finalDeck.mainboard.filter(card => card.owned).length;
  finalDeck.owned_count = owned; finalDeck.missing_count = finalDeck.mainboard.length - owned;
  return { ok: true, assisted: true, configuration: settings, deck: finalDeck, report: finalReport,
    summary: proposal.summary, swaps: proposal.swaps,
    warning: 'Couleurs, quantités du format, catalogue et répartition contrôlés. Le moteur ne mesure pas la puissance ; textes non compris, sideboard et règles particulières restent à vérifier.' };
}
