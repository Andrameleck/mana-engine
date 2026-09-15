// Regression probes: execute the repository's functions in memory, without UI/network startup.
// Run from the repository root: node docs/audit/probes-js.cjs
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const repositoryRoot = path.resolve(__dirname, '..', '..');
const exportsToInspect = [
  'buildStrategyModelFromRows', 'strategySimilarity', 'computeSynergy',
  'mapScryfallCardToStrategyRow', 'parseColorCodes', 'computeSpellbookSynergyGroups',
  'computeDeckRecommendationAnalysis', 'computeSynergyGroups', 'cmcFromManaCost',
  'computeManaSourceSegments'
];

function loadModel(file) {
  const raw = fs.readFileSync(file, 'utf8');
  const start = raw.indexOf('(function bootstrap()');
  const end = raw.lastIndexOf('  init().catch(');
  assert(start >= 0 && end > start, 'Expected bootstrap boundaries');
  const code = raw.slice(start, end) + '\n globalThis.audit = {' + exportsToInspect.join(',') + '};\n})();';
  const sandbox = {
    document: { querySelectorAll: () => [], getElementById: () => null },
    window: {}, console,
    localStorage: { getItem: () => null }
  };
  vm.runInNewContext(code, sandbox, { filename: file, timeout: 5000 });
  return sandbox.audit;
}

for (const file of ['frontend/src/main.js', 'inst/www/main.js']) {
  const m = loadModel(path.join(repositoryRoot, file));
  const rows = (name, oracle_text, extra = {}) => ({ name, oracle_text, quantity: 1, ...extra });
  const model = (data) => m.buildStrategyModelFromRows(data).cards;
  const results = {};

  const drawDeck = [{ quantity: 60, row: rows('Synthetic draw spell', 'Draw a card.') }];
  results.uniformDrawDeckSynergy = m.computeSynergy(drawDeck).score;
  assert.equal(results.uniformDrawDeckSynergy, 100);

  const record = { name: 'Synthetic draw spell', oracle_text: 'Draw a card.', printed_text: 'Piochez une carte.', keywords: [] };
  const en = model([m.mapScryfallCardToStrategyRow(record, 'en')])[0];
  const fr = model([m.mapScryfallCardToStrategyRow(record, 'fr')])[0];
  results.localizedFeatures = { en: en.features, fr: fr.features };
  assert(en.features.draw > 0);
  assert(fr.features.draw > 0);

  const faces = m.mapScryfallCardToStrategyRow({ name: 'Synthetic faces', card_faces: [{ oracle_text: 'Draw a card.', mana_cost: '{U}' }, { oracle_text: 'Create a token.', mana_cost: '{G}' }] });
  results.multifaceAnalysisText = faces.analysis_text;
  assert(faces.analysis_text.includes('Draw a card.'));
  assert(faces.analysis_text.includes('Create a token.'));

  results.namedColors = { blue: m.parseColorCodes('blue'), green: m.parseColorCodes('green'), colorless: m.parseColorCodes('colorless') };
  assert.equal(results.namedColors.blue.join(''), 'U');
  assert.equal(results.namedColors.green.join(''), 'G');
  assert.equal(results.namedColors.colorless.length, 0);

  const comboCards = model([rows('Seed', 'Draw a card.'), rows('Partner', 'Draw a card.')]);
  const seed = comboCards.find(c => c.name === 'Seed');
  const partner = comboCards.find(c => c.name === 'Partner');
  const groups = m.computeSpellbookSynergyGroups(seed, [{ card: partner, score: 0.8 }], comboCards, 3, { variants: [{ cardKeys: [seed.key, partner.key, 'missing necessary piece'], popularity: 0 }] });
  results.incompleteSpellbookGroup = groups.map(g => g.cards.map(c => c.name));
  assert.equal(groups.length, 0);

  const largeComboCards = model(Array.from({ length: 6 }, (_, index) => rows(`Piece ${index + 1}`, 'Draw a card.')));
  const largeSeed = largeComboCards[0];
  const largeKeys = largeComboCards.map(card => card.key);
  const largeGroup = m.computeSpellbookSynergyGroups(
    largeSeed,
    [],
    largeComboCards,
    1,
    { variants: [{ cardKeys: largeKeys, popularity: 0 }] }
  );
  results.largeSpellbookGroupSize = largeGroup[0]?.cards.length || 0;
  assert.equal(results.largeSpellbookGroupSize, 6);

  const falseCombo = model([rows('Generic mill', 'Target player mills two cards.'), rows('Local protection', 'Choose a color. Target creature gains protection from the chosen color.')]);
  results.genericMillProtectionSimilarity = m.strategySimilarity(falseCombo[0], falseCombo[1]);
  assert(results.genericMillProtectionSimilarity.score < 0.2);

  const primary = model([rows('A', 'Draw a card. Create a token.'), rows('Draw filler', 'Draw a card.')]);
  const secondary = model([rows('B', 'Draw a card. Create a token.'), rows('Token filler', 'Create a token.')]);
  results.identicalTextAcrossCorpora = m.strategySimilarity(primary.find(c => c.name === 'A'), secondary.find(c => c.name === 'B')).featureScore;
  assert(results.identicalTextAcrossCorpora < 0.95);

  const single = model([rows('A', 'Draw a card.', { quantity: 2 }), rows('B', 'Create a token.')]);
  const duplicate = model([rows('A', 'Draw a card.'), rows('A', 'Draw a card.'), rows('B', 'Create a token.')]);
  const candidates = model([rows('C', 'Draw a card.')]);
  const share = cards => m.computeDeckRecommendationAnalysis(cards, candidates).mechanics.find(x => x.id === 'draw').share;
  results.sameInventoryDifferentRows = { oneRow: share(single), twoRows: share(duplicate) };
  assert.equal(results.sameInventoryDifferentRows.twoRows, results.sameInventoryDifferentRows.oneRow);

  const deck = model([rows('Black draw', 'Draw a card.', { color_identity: 'B' })]);
  const offColor = model([rows('Blue draw', 'Draw a card.', { color_identity: 'U' })]);
  results.offColorUpgrade = m.computeDeckRecommendationAnalysis(deck, offColor).upgrades.map(x => x.card.name);
  assert.equal(results.offColorUpgrade.length, 0);

  const simple = model([rows('Seed', 'Draw a card.'), rows('Left', 'Draw a card.'), rows('Right', 'Draw a card.'), rows('Weak support', '')]);
  const s = simple.find(c => c.name === 'Seed');
  const direct = ['Left', 'Right'].map(name => ({card: simple.find(c => c.name === name), score: 0.5}));
  const weakGroup = m.computeSynergyGroups(s, direct, simple, 1)[0];
  results.unselectedSupportInExplanation = { cards: weakGroup.cards.map(c => c.name), lineB: weakGroup.lineB };
  assert(!weakGroup.cards.some(c => c.name === 'Weak support'));
  assert(!weakGroup.lineB.includes('Weak support'));

  results.twoBridManaValue = m.cmcFromManaCost('{2/W}{2/W}{2/W}');
  assert.equal(results.twoBridManaValue, 6);
  results.colorlessIdentityManaSource = m.computeManaSourceSegments([{ quantity: 1, row: rows('Synthetic rainbow land', '{T}: Add one mana of any color.', { type_line: 'Land', color_identity: '' }) }]);
  assert.equal(results.colorlessIdentityManaSource.find(x => x.key === 'C').value, 1);

  console.log(JSON.stringify({ file, observations: results }, null, 2));
}
