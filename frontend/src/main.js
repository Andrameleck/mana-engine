import {
  uploadCollection,
  importCollectionCsv,
  listStoredCollections,
  getStoredCollection,
  deleteStoredCollection
} from "./api.js";
import {
  renderCollection,
  getCollectionLanguage,
  setCollectionLanguage
} from "./ui.js";

(function bootstrap() {
  const TAB_META = {
    collections: {
      title: "Collections",
      subtitle: "Creer et gerer plusieurs dossiers de collection."
    },
    decks: {
      title: "Decks",
      subtitle: "Importer et visualiser plusieurs decks."
    },
    strategy: {
      title: "Strategy",
      subtitle: "Zone reservee au module de strategies."
    }
  };

  const state = {
    activeTab: "collections",
    collections: [],
    collectionPayloadById: {},
    selectedCollectionId: null,
    decks: [],
    selectedDeckId: null
  };

  const DECK_STORAGE_KEY = "mtgcodex_ui_decks_v1";
  const MAX_STORED_DECKS = 24;
  const DECK_STATS_STATE = {
    requestToken: 0,
    metadataCache: new Map()
  };

  const nodes = {
    tabButtons: Array.from(document.querySelectorAll(".side-tab")),
    tabViews: Array.from(document.querySelectorAll(".tab-view")),
    workspaceTitle: document.getElementById("workspace-title"),
    workspaceSubtitle: document.getElementById("workspace-subtitle"),
    workspaceLower: document.getElementById("workspace-lower"),
    deckStatsPanel: document.getElementById("deck-stats-panel"),
    deckStatsContent: document.getElementById("deck-stats-content"),
    langEnButton: document.getElementById("lang-en"),
    langFrButton: document.getElementById("lang-fr"),
    collections: {
      form: document.getElementById("collection-load-form"),
      nameInput: document.getElementById("collection-name"),
      fileInput: document.getElementById("collection-source-file"),
      pickFileButton: document.getElementById("collection-pick-file"),
      list: document.getElementById("collections-list")
    },
    decks: {
      form: document.getElementById("deck-load-form"),
      nameInput: document.getElementById("deck-name"),
      fileInput: document.getElementById("deck-source-file"),
      pickFileButton: document.getElementById("deck-pick-file"),
      list: document.getElementById("decks-list")
    }
  };

  function applyLanguageButtonState(language) {
    if (!nodes.langEnButton || !nodes.langFrButton) {
      return;
    }
    nodes.langEnButton.classList.toggle("is-active", language === "en");
    nodes.langFrButton.classList.toggle("is-active", language === "fr");
  }

  function onLanguageSelect(language) {
    setCollectionLanguage(language);
    applyLanguageButtonState(language);
    if (state.activeTab === "collections" && state.selectedCollectionId) {
      loadStoredCollectionIntoTable(state.selectedCollectionId);
    }
  }

  function bindCollectionPicker() {
    nodes.collections.fileInput.accept = ".csv,.txt";
    const defaultPickLabel = "Choisir CSV";
    setCollectionPickButtonLabel(defaultPickLabel);
    nodes.collections.pickFileButton.classList.remove("has-file");
    nodes.collections.pickFileButton.addEventListener("click", () => {
      nodes.collections.fileInput.click();
    });
    nodes.collections.fileInput.addEventListener("change", () => {
      const selected = nodes.collections.fileInput.files && nodes.collections.fileInput.files[0];
      setCollectionPickButtonLabel(selected ? `CSV: ${selected.name}` : defaultPickLabel);
      nodes.collections.pickFileButton.classList.toggle("has-file", Boolean(selected));
    });
  }

  function setCollectionPickButtonLabel(label) {
    const button = nodes.collections.pickFileButton;
    if (!button) {
      return;
    }
    const text = String(label || "Choisir CSV");
    const labelNode = button.querySelector(".btn-label");
    if (labelNode) {
      labelNode.textContent = text;
      button.title = text;
      button.setAttribute("aria-label", text);
      return;
    }
    button.title = text;
    button.setAttribute("aria-label", text);
  }

  function bindDeckPicker() {
    nodes.decks.fileInput.accept = ".txt,.text,.tsv,.csv,.db,.sqlite,.sqlite3";
    const defaultPickLabel = "Choisir un fichier deck";
    setDeckPickButtonLabel(defaultPickLabel);
    nodes.decks.pickFileButton.classList.remove("has-file");
    nodes.decks.pickFileButton.addEventListener("click", () => {
      nodes.decks.fileInput.click();
    });
    nodes.decks.fileInput.addEventListener("change", () => {
      const selected = nodes.decks.fileInput.files && nodes.decks.fileInput.files[0];
      setDeckPickButtonLabel(selected ? `Deck: ${selected.name}` : defaultPickLabel);
      nodes.decks.pickFileButton.classList.toggle("has-file", Boolean(selected));
    });
  }

  function setDeckPickButtonLabel(label) {
    const button = nodes.decks.pickFileButton;
    if (!button) {
      return;
    }
    const text = String(label || "Choisir un fichier deck");
    button.title = text;
    button.setAttribute("aria-label", text);
  }

  function inferDeckSourceType(fileName) {
    const lowerName = String(fileName || "").toLowerCase();
    if (lowerName.endsWith(".db") || lowerName.endsWith(".sqlite") || lowerName.endsWith(".sqlite3")) {
      return "db";
    }
    if (lowerName.endsWith(".csv")) {
      return "csv";
    }
    return "text";
  }

  function selectTab(tabId) {
    state.activeTab = tabId;

    nodes.tabButtons.forEach((button) => {
      button.classList.toggle("is-active", button.dataset.tab === tabId);
    });
    nodes.tabViews.forEach((view) => {
      view.classList.toggle("is-active", view.id === `tab-${tabId}`);
    });

    const meta = TAB_META[tabId] || TAB_META.collections;
    nodes.workspaceTitle.textContent = meta.title;
    nodes.workspaceSubtitle.textContent = meta.subtitle;
    renderActiveTabTable();
  }

  function payloadForNamedView(payload, name, fallbackSummary, viewMode = "table") {
    if (!payload) {
      return {
        ok: false,
        table: name,
        error: "No data loaded."
      };
    }
    return {
      ...payload,
      table: payload.table || name,
      path: payload.path || fallbackSummary,
      view_mode: viewMode
    };
  }

  async function refreshCollectionsListFromApi() {
    const payload = await listStoredCollections();
    if (!payload || payload.ok !== true) {
      state.collections = [];
      state.selectedCollectionId = null;
      renderCollectionsList(payload?.error || "Impossible de charger les dossiers.");
      return false;
    }

    state.collections = Array.isArray(payload.collections) ? payload.collections : [];
    if (!state.collections.some((entry) => entry.id === state.selectedCollectionId)) {
      state.selectedCollectionId = state.collections[0]?.id || null;
    }
    renderCollectionsList("");
    return true;
  }

  function renderCollectionsList(errorMessage) {
    const list = nodes.collections.list;
    if (!list) {
      return;
    }

    if (errorMessage) {
      list.innerHTML = `<p class="muted">${escapeHtml(errorMessage)}</p>`;
      return;
    }

    if (state.collections.length === 0) {
      list.innerHTML = '<p class="muted">Aucun dossier collection pour le moment.</p>';
      return;
    }

    list.innerHTML = state.collections.map((entry) => {
      const activeClass = entry.id === state.selectedCollectionId ? "is-active" : "";
      const platform = entry.platform || "auto";
      const createdAt = entry.created_at || "";
      const rowCount = entry.row_count ?? "-";

      return `
        <article class="entity-item ${activeClass}" data-entity-id="${escapeHtml(entry.id)}">
          <div>
            <p class="entity-item-name">Dossier: ${escapeHtml(entry.name || entry.id)}</p>
            <p class="entity-item-meta">${escapeHtml(platform)} | ${escapeHtml(String(rowCount))} lignes | ${escapeHtml(createdAt)}</p>
          </div>
          <div class="entity-actions">
            <button type="button" class="entity-select" data-action="select">Ouvrir</button>
            <button type="button" class="entity-delete" data-action="delete">Supprimer</button>
          </div>
        </article>
      `;
    }).join("");
  }

  async function loadStoredCollectionIntoTable(collectionId) {
    if (!collectionId) {
      return;
    }
    const payload = await getStoredCollection(collectionId);
    state.collectionPayloadById[collectionId] = payload;
    if (state.activeTab === "collections" && state.selectedCollectionId === collectionId) {
      renderActiveTabTable();
    }
  }

  function renderDecksList() {
    const list = nodes.decks.list;
    if (!list) {
      return;
    }
    if (state.decks.length === 0) {
      list.innerHTML = '<p class="muted">Aucun deck pour le moment.</p>';
      return;
    }

    list.innerHTML = state.decks.map((entry, index) => {
      const activeClass = entry.id === state.selectedDeckId ? "is-active" : "";
      const rowCount = entry.payload?.row_count ?? "-";
      const deckName = escapeHtml(entry.name);
      const deckId = escapeHtml(entry.id);
      const glyph = escapeHtml(deckGlyph(entry.name, index + 1));
      return `
        <article class="deck-icon-item ${activeClass}" data-entity-id="${deckId}">
          <button type="button" class="deck-icon-open" data-action="select" aria-label="Ouvrir ${deckName}" title="Ouvrir ${deckName}">
            <span class="deck-icon-glyph">${glyph}</span>
          </button>
          <button type="button" class="deck-icon-delete" data-action="delete" aria-label="Supprimer ${deckName}" title="Supprimer ${deckName}">
            <svg viewBox="0 0 24 24" class="deck-icon-delete-svg" aria-hidden="true">
              <path d="M6 7h12"></path>
              <path d="M9 7V5h6v2"></path>
              <path d="M8 7l1 12h6l1-12"></path>
            </svg>
          </button>
          <p class="deck-icon-name">${deckName}</p>
          <p class="deck-icon-meta">${escapeHtml(String(rowCount))} lignes</p>
        </article>
      `;
    }).join("");
  }

  function deckGlyph(name, fallbackIndex) {
    const raw = String(name || "").trim();
    if (!raw) {
      return String(fallbackIndex || "?");
    }
    const cleaned = raw.replace(/[^A-Za-z0-9]+/g, "");
    if (!cleaned) {
      return String(fallbackIndex || "?");
    }
    return cleaned.slice(0, 2).toUpperCase();
  }

  function loadDeckStateFromStorage() {
    try {
      const raw = window.localStorage.getItem(DECK_STORAGE_KEY);
      if (!raw) {
        return;
      }
      const parsed = JSON.parse(raw);
      if (!parsed || typeof parsed !== "object") {
        return;
      }

      const savedDecks = Array.isArray(parsed.decks) ? parsed.decks : [];
      const normalizedDecks = savedDecks
        .map((entry, index) => normalizeStoredDeck(entry, index))
        .filter(Boolean);

      state.decks = normalizedDecks.slice(0, MAX_STORED_DECKS);
      const savedSelectedId = String(parsed.selectedDeckId || "");
      if (savedSelectedId && state.decks.some((entry) => entry.id === savedSelectedId)) {
        state.selectedDeckId = savedSelectedId;
      } else {
        state.selectedDeckId = state.decks[0]?.id || null;
      }
    } catch (_) {
      state.decks = [];
      state.selectedDeckId = null;
    }
  }

  function normalizeStoredDeck(entry, index) {
    if (!entry || typeof entry !== "object") {
      return null;
    }

    const payload = entry.payload;
    if (!payload || typeof payload !== "object" || payload.ok !== true) {
      return null;
    }

    const idRaw = String(entry.id || "").trim();
    const nameRaw = String(entry.name || "").trim();

    return {
      id: idRaw || uniqueId(`deck-stored-${index + 1}`),
      name: nameRaw || `Deck ${index + 1}`,
      payload
    };
  }

  function saveDeckStateToStorage() {
    try {
      const snapshot = {
        selectedDeckId: state.selectedDeckId || null,
        decks: state.decks.slice(0, MAX_STORED_DECKS).map((entry) => ({
          id: entry.id,
          name: entry.name,
          payload: entry.payload
        }))
      };
      window.localStorage.setItem(DECK_STORAGE_KEY, JSON.stringify(snapshot));
    } catch (_) {
      // ignore storage quota/permission issues without blocking UI flow
    }
  }

  function renderActiveTabTable() {
    if (state.activeTab === "collections") {
      if (!state.selectedCollectionId) {
        renderCollection({
          ok: false,
          table: "Collections",
          error: "Aucun dossier selectionne."
        });
        renderDeckStatsPanel(null);
        return;
      }

      const meta = state.collections.find((entry) => entry.id === state.selectedCollectionId);
      const payload = state.collectionPayloadById[state.selectedCollectionId];
      if (!payload) {
        renderCollection({
          ok: false,
          table: meta?.name || "Collections",
          error: "Chargement du dossier en cours..."
        });
        renderDeckStatsPanel(null);
        return;
      }

      renderCollection(payloadForNamedView(payload, meta?.name || "Collection", "collection/store", "cards"));
      renderDeckStatsPanel(null);
      return;
    }

    if (state.activeTab === "decks") {
      const selected = state.decks.find((entry) => entry.id === state.selectedDeckId);
      if (!selected) {
        renderCollection({
          ok: false,
          table: "Decks",
          error: "Aucun deck selectionne."
        });
        renderDeckStatsPanel(null);
        return;
      }
      renderCollection(payloadForNamedView(selected.payload, selected.name, "deck/local", "cards"));
      renderDeckStatsPanel(selected);
      return;
    }

    if (state.activeTab === "strategy") {
      renderCollection({
        ok: false,
        table: "Strategy",
        error: "Module Strategy en construction."
      });
      renderDeckStatsPanel(null);
      return;
    }

    renderCollection({
      ok: false,
      table: "Collections",
      error: "Selectionne un onglet disponible."
    });
    renderDeckStatsPanel(null);
  }

  function renderDeckStatsPanel(deckEntry) {
    const panel = nodes.deckStatsPanel;
    const content = nodes.deckStatsContent;
    const lower = nodes.workspaceLower;
    if (!panel || !content || !lower) {
      return;
    }

    const isDeckTab = state.activeTab === "decks";
    panel.classList.toggle("is-hidden", !isDeckTab);
    lower.classList.toggle("has-deck-stats", isDeckTab);

    if (!isDeckTab) {
      DECK_STATS_STATE.requestToken += 1;
      content.classList.add("muted");
      content.classList.remove("is-loading");
      content.innerHTML = "Selectionne un deck pour afficher ses statistiques.";
      return;
    }

    if (!deckEntry || deckEntry.payload?.ok !== true) {
      DECK_STATS_STATE.requestToken += 1;
      content.classList.add("muted");
      content.classList.remove("is-loading");
      content.innerHTML = "Aucun deck selectionne.";
      return;
    }

    const requestToken = ++DECK_STATS_STATE.requestToken;
    const deckEntries = buildDeckEntries(deckEntry.payload);
    const stats = computeDeckStats(deckEntries);

    content.classList.remove("muted");
    content.classList.remove("is-loading");
    content.innerHTML = deckStatsMarkup(stats);

    const needsMetadata = deckEntries.some((entry) => entryNeedsMetadata(entry.row));
    if (!needsMetadata) {
      return;
    }

    content.classList.add("is-loading");
    enrichDeckEntriesWithMetadata(deckEntries, requestToken)
      .then((enrichedEntries) => {
        if (!enrichedEntries || requestToken !== DECK_STATS_STATE.requestToken) {
          return;
        }
        const enrichedStats = computeDeckStats(enrichedEntries);
        content.classList.remove("is-loading");
        content.innerHTML = deckStatsMarkup(enrichedStats);
      })
      .catch(() => {
        if (requestToken !== DECK_STATS_STATE.requestToken) {
          return;
        }
        content.classList.remove("is-loading");
      });
  }

  function computeDeckStats(cards) {
    const safeCards = Array.isArray(cards) ? cards.filter((entry) => entry.quantity > 0) : [];

    const totalCards = safeCards.reduce((sum, entry) => sum + entry.quantity, 0);
    const landCards = safeCards.filter((entry) => isLandRow(entry.row));
    const nonLandCards = safeCards.filter((entry) => !isLandRow(entry.row));
    const landCount = landCards.reduce((sum, entry) => sum + entry.quantity, 0);
    const nonLandCount = Math.max(0, totalCards - landCount);

    let cmcWeightedSum = 0;
    const curveBuckets = [0, 0, 0, 0, 0, 0, 0, 0];
    let cheapSpells = 0;

    nonLandCards.forEach((entry) => {
      const cmc = readCardCmc(entry.row);
      const quantity = entry.quantity;
      cmcWeightedSum += cmc * quantity;
      if (cmc <= 2) {
        cheapSpells += quantity;
      }

      const bucketIndex = cmc >= 7 ? 7 : Math.max(0, Math.floor(cmc));
      curveBuckets[bucketIndex] += quantity;
    });

    const avgCmc = nonLandCount > 0 ? cmcWeightedSum / nonLandCount : 0;
    const landRatio = totalCards > 0 ? landCount / totalCards : 0;
    const cheapRatio = nonLandCount > 0 ? cheapSpells / nonLandCount : 0;
    const landBalance = Math.max(0, 1 - Math.min(Math.abs(landRatio - 0.38) / 0.2, 1));
    const efficiencyScore = Math.round(((cheapRatio * 0.65) + (landBalance * 0.35)) * 100);

    const synergy = computeSynergy(nonLandCards);

    return {
      totalCards,
      landCount,
      nonLandCount,
      avgCmc,
      curveBuckets,
      efficiencyScore,
      cheapRatio,
      synergyScore: synergy.score,
      manaSourceSegments: computeManaSourceSegments(landCards),
      castingCostSegments: computeCastingCostSegments(nonLandCards),
      typeSegments: computeTypeSegments(safeCards),
      colorSegments: computeColorDistributionSegments(nonLandCards)
    };
  }

  function computeSynergy(nonLandCards) {
    const TAGS = [
      { id: "draw", label: "Card draw", regex: /\bdraw\b/i },
      { id: "removal", label: "Removal", regex: /\bdestroy\b|\bexile target\b|\bcounter target\b|\bdeals? [0-9x]+ damage\b/i },
      { id: "ramp", label: "Ramp", regex: /\badd \{[wubrgc0-9x/]+\}|\bsearch your library for .* land\b|\btreasure token\b/i },
      { id: "token", label: "Tokens", regex: /\bcreate .* token\b|\bpopulate\b|\bamass\b/i },
      { id: "graveyard", label: "Graveyard", regex: /\bgraveyard\b|\bmill\b|\breturn .* from your graveyard\b/i },
      { id: "sacrifice", label: "Sacrifice", regex: /\bsacrifice\b/i },
      { id: "counters", label: "Counters", regex: /\+1\/\+1 counter\b|\bproliferate\b/i },
      { id: "lifegain", label: "Life gain", regex: /\bgain [0-9x]+ life\b|\blifelink\b/i }
    ];

    const tagHits = new Map(TAGS.map((tag) => [tag.id, 0]));
    let totalTagHits = 0;
    let taggedCards = 0;
    let nonLandCount = 0;

    nonLandCards.forEach((entry) => {
      const quantity = entry.quantity;
      nonLandCount += quantity;
      const textBlob = [
        rowValue(entry.row, ["name"]),
        rowValue(entry.row, ["type_line"]),
        rowValue(entry.row, ["oracle_text", "printed_text", "card_text", "rules_text"])
      ].join(" ");

      const matches = TAGS.filter((tag) => tag.regex.test(textBlob));
      if (matches.length === 0) {
        return;
      }

      taggedCards += quantity;
      matches.forEach((tag) => {
        const nextValue = (tagHits.get(tag.id) || 0) + quantity;
        tagHits.set(tag.id, nextValue);
        totalTagHits += quantity;
      });
    });

    if (totalTagHits <= 0 || nonLandCount <= 0) {
      return {
        score: 0,
        topTags: []
      };
    }

    const ranked = TAGS
      .map((tag) => ({
        id: tag.id,
        label: tag.label,
        value: tagHits.get(tag.id) || 0
      }))
      .filter((entry) => entry.value > 0)
      .sort((left, right) => right.value - left.value);

    const topTags = ranked.slice(0, 3);
    const topHits = topTags.reduce((sum, entry) => sum + entry.value, 0);
    const focus = topHits / totalTagHits;
    const density = taggedCards / nonLandCount;
    const score = Math.round((focus * 0.55 + density * 0.45) * 100);

    return {
      score,
      topTags
    };
  }

  function deckStatsMarkup(stats) {
    const landRatio = stats.totalCards > 0 ? (stats.landCount / stats.totalCards) : 0;

    return `
      <section class="deck-kpi-grid">
        <article class="deck-kpi-card">
          <p class="deck-kpi-label">Total cartes</p>
          <p class="deck-kpi-value">${formatCount(stats.totalCards)}</p>
        </article>
        <article class="deck-kpi-card">
          <p class="deck-kpi-label">Terrains</p>
          <p class="deck-kpi-value">${formatCount(stats.landCount)}</p>
        </article>
        <article class="deck-kpi-card">
          <p class="deck-kpi-label">Sorts</p>
          <p class="deck-kpi-value">${formatCount(stats.nonLandCount)}</p>
        </article>
        <article class="deck-kpi-card">
          <p class="deck-kpi-label">Ratio terrains</p>
          <p class="deck-kpi-value">${formatPercent(landRatio)}</p>
        </article>
      </section>

      <section class="deck-visual-section">
        <div class="deck-visual-head">
          <span class="deck-visual-icon" aria-hidden="true">i</span>
          <h4 class="deck-visual-title">Mana Sources & Casting Costs</h4>
        </div>
        ${renderDualRingChart(stats.manaSourceSegments, stats.castingCostSegments)}
      </section>

      <section class="deck-visual-section">
        <div class="deck-visual-head">
          <span class="deck-visual-icon" aria-hidden="true">i</span>
          <h4 class="deck-visual-title">Card Type Distribution</h4>
        </div>
        ${renderSingleRingChart(stats.typeSegments, "types")}
      </section>

      <section class="deck-visual-section">
        <div class="deck-visual-head">
          <span class="deck-visual-icon" aria-hidden="true">i</span>
          <h4 class="deck-visual-title">Mana Curve / Color Distribution</h4>
        </div>
        <div class="deck-mix-layout">
          ${renderCurveBars(stats.curveBuckets)}
          ${renderSingleRingChart(stats.colorSegments, "colors", true)}
        </div>
        <p class="deck-stats-note">
          CMC moyen ${formatDecimal(stats.avgCmc)} | Efficience ${stats.efficiencyScore}/100 | Synergie ${stats.synergyScore}/100
        </p>
      </section>
    `;
  }

  function renderDualRingChart(outerSegments, innerSegments) {
    const outerGradient = conicGradientFromSegments(outerSegments);
    const innerGradient = conicGradientFromSegments(innerSegments);
    return `
      <div class="ring-chart-wrap">
        <div class="ring-dual-chart">
          <div class="ring-layer ring-layer-outer" style="--ring-gradient: ${outerGradient};"></div>
          <div class="ring-layer ring-layer-inner" style="--ring-gradient: ${innerGradient};"></div>
          <div class="ring-core">
            <span class="ring-core-title">sources</span>
            <span class="ring-core-value">${formatCount(sumSegmentValues(outerSegments))}</span>
          </div>
        </div>
        <div class="ring-dual-meta">
          <div>
            <p class="ring-meta-title">Sources</p>
            ${segmentListMarkup(outerSegments)}
          </div>
          <div>
            <p class="ring-meta-title">Costs</p>
            ${segmentListMarkup(innerSegments)}
          </div>
        </div>
      </div>
    `;
  }

  function renderSingleRingChart(segments, centerLabel, compact) {
    const gradient = conicGradientFromSegments(segments);
    const compactClass = compact ? " is-compact" : "";
    return `
      <div class="ring-chart-wrap${compactClass}">
        <div class="ring-single-chart">
          <div class="ring-single-layer" style="--ring-gradient: ${gradient};"></div>
          <div class="ring-core">
            <span class="ring-core-title">${escapeHtml(centerLabel)}</span>
            <span class="ring-core-value">${formatCount(sumSegmentValues(segments))}</span>
          </div>
        </div>
        ${segmentListMarkup(segments)}
      </div>
    `;
  }

  function renderCurveBars(curveBuckets) {
    const labels = ["0", "1", "2", "3", "4", "5", "6", "7+"];
    const maxValue = Math.max(1, ...curveBuckets);
    const rows = curveBuckets
      .map((value, index) => {
        const width = Math.max(4, Math.round((value / maxValue) * 100));
        return `
          <div class="curve-bar-row">
            <span class="curve-bar-label">${labels[index]}</span>
            <div class="curve-bar-track"><span class="curve-bar-fill" style="--fill-width: ${width}%"></span></div>
            <span class="curve-bar-value">${formatCount(value)}</span>
          </div>
        `;
      })
      .join("");
    return `<div class="curve-bar-list">${rows}</div>`;
  }

  function buildDeckEntries(payload) {
    const rows = normalizeRowsFromPayload(payload);
    const entries = [];

    rows.forEach((row) => {
      const rowLine = rowValue(row, ["line", "card_line", "raw", "entry"]);
      const parsedLine = parseDeckLine(rowLine);
      if (parsedLine?.ignore) {
        return;
      }

      const explicitName = rowValue(row, ["name", "card_name", "card", "title"]).trim();
      const resolvedName = explicitName || parsedLine?.name || "";
      if (!resolvedName) {
        return;
      }

      let quantity = readCardQuantityFromRow(row);
      if (!rowHasExplicitQuantity(row) && Number.isFinite(parsedLine?.quantity) && parsedLine.quantity > 0) {
        quantity = parsedLine.quantity;
      }
      if (!Number.isFinite(quantity) || quantity <= 0) {
        return;
      }

      const normalizedRow = { ...row };
      if (!rowValue(normalizedRow, ["name"])) {
        normalizedRow.name = resolvedName;
      }
      if (!rowHasExplicitQuantity(normalizedRow)) {
        normalizedRow.quantity = quantity;
      }

      entries.push({
        row: normalizedRow,
        quantity,
        name: resolvedName
      });
    });

    return entries;
  }

  function parseDeckLine(lineText) {
    const line = String(lineText || "").trim();
    if (!line) {
      return null;
    }

    if (/^(#|\/\/)/.test(line)) {
      return { ignore: true };
    }
    if (/^(sideboard|commander|maybeboard|companion)\b/i.test(line)) {
      return { ignore: true };
    }

    const withoutPrefix = line.replace(/^SB:\s*/i, "").trim();
    const withQty = withoutPrefix.match(/^(\d+)\s*x?\s+(.+)$/i);
    if (!withQty) {
      if (/^(deck|mainboard)\b/i.test(withoutPrefix)) {
        return { ignore: true };
      }
      return {
        quantity: 1,
        name: withoutPrefix
      };
    }

    const qty = Number.parseInt(withQty[1], 10);
    let name = withQty[2].trim();
    name = name
      .replace(/\s+\([^)]+\)\s+\d+[A-Za-z]?$/u, "")
      .replace(/\s+\[[^\]]+\]\s*$/u, "")
      .trim();

    if (!name || !Number.isFinite(qty) || qty <= 0) {
      return { ignore: true };
    }

    return {
      quantity: qty,
      name
    };
  }

  function entryNeedsMetadata(row) {
    const hasType = Boolean(rowValue(row, ["type_line", "type"]).trim());
    const hasMana = Boolean(rowValue(row, ["mana_cost", "manacost", "mana"]).trim());
    const hasColors = Boolean(rowValue(row, ["color_identity", "colors"]).trim());
    return !hasType || !hasMana || !hasColors;
  }

  async function enrichDeckEntriesWithMetadata(entries, requestToken) {
    const uniqueNames = Array.from(new Set(
      entries
        .map((entry) => String(entry.name || "").trim())
        .filter(Boolean)
    )).slice(0, 90);

    const metadataByName = new Map();
    for (let i = 0; i < uniqueNames.length; i += 8) {
      if (requestToken !== DECK_STATS_STATE.requestToken) {
        return null;
      }

      const chunk = uniqueNames.slice(i, i + 8);
      const chunkData = await Promise.all(
        chunk.map((name) => fetchDeckCardMetadata(name))
      );
      chunk.forEach((name, index) => {
        if (chunkData[index]) {
          metadataByName.set(name, chunkData[index]);
        }
      });
    }

    return entries.map((entry) => {
      const metadata = metadataByName.get(entry.name);
      if (!metadata) {
        return entry;
      }

      const mergedRow = { ...entry.row };
      if (!rowValue(mergedRow, ["type_line", "type"]) && metadata.type_line) {
        mergedRow.type_line = metadata.type_line;
      }
      if (!rowValue(mergedRow, ["mana_cost", "manacost", "mana"]) && metadata.mana_cost) {
        mergedRow.mana_cost = metadata.mana_cost;
      }
      if (!rowValue(mergedRow, ["color_identity"]) && metadata.color_identity.length > 0) {
        mergedRow.color_identity = metadata.color_identity.join("");
      }
      if (!rowValue(mergedRow, ["colors"]) && metadata.colors.length > 0) {
        mergedRow.colors = metadata.colors.join("");
      }

      return {
        ...entry,
        row: mergedRow
      };
    });
  }

  async function fetchDeckCardMetadata(cardName) {
    const key = String(cardName || "").trim().toLowerCase();
    if (!key) {
      return null;
    }

    if (DECK_STATS_STATE.metadataCache.has(key)) {
      return DECK_STATS_STATE.metadataCache.get(key);
    }

    const task = resolveDeckCardMetadata(cardName).catch(() => null);
    DECK_STATS_STATE.metadataCache.set(key, task);
    return task;
  }

  async function resolveDeckCardMetadata(cardName) {
    const exactParams = new URLSearchParams({ exact: cardName });
    const exactResponse = await fetch(`https://api.scryfall.com/cards/named?${exactParams.toString()}`, {
      headers: { Accept: "application/json" }
    });
    if (exactResponse.ok) {
      const exactCard = await exactResponse.json().catch(() => null);
      const exactMeta = normalizeScryfallCardMetadata(exactCard);
      if (exactMeta) {
        return exactMeta;
      }
    }

    const fuzzyParams = new URLSearchParams({ fuzzy: cardName });
    const fuzzyResponse = await fetch(`https://api.scryfall.com/cards/named?${fuzzyParams.toString()}`, {
      headers: { Accept: "application/json" }
    });
    if (fuzzyResponse.ok) {
      const fuzzyCard = await fuzzyResponse.json().catch(() => null);
      const fuzzyMeta = normalizeScryfallCardMetadata(fuzzyCard);
      if (fuzzyMeta) {
        return fuzzyMeta;
      }
    }

    const searchParams = new URLSearchParams({
      q: cardName,
      order: "released",
      dir: "desc"
    });
    const searchResponse = await fetch(`https://api.scryfall.com/cards/search?${searchParams.toString()}`, {
      headers: { Accept: "application/json" }
    });
    if (!searchResponse.ok) {
      return null;
    }
    const searchJson = await searchResponse.json().catch(() => null);
    const firstCard = Array.isArray(searchJson?.data) ? searchJson.data[0] : null;
    return normalizeScryfallCardMetadata(firstCard);
  }

  function normalizeScryfallCardMetadata(card) {
    if (!card || card.object !== "card") {
      return null;
    }

    const faceMana = Array.isArray(card.card_faces)
      ? card.card_faces
        .map((face) => String(face?.mana_cost || "").trim())
        .filter(Boolean)
      : [];
    const mergedMana = String(card.mana_cost || "").trim() || faceMana.join(" ");

    return {
      type_line: String(card.type_line || "").trim(),
      mana_cost: mergedMana,
      color_identity: Array.isArray(card.color_identity) ? card.color_identity : [],
      colors: Array.isArray(card.colors) ? card.colors : []
    };
  }

  function normalizeRowsFromPayload(payload) {
    const rawRows = Array.isArray(payload?.rows) ? payload.rows : [];
    return rawRows.map((row) => {
      if (row && typeof row === "object" && !Array.isArray(row)) {
        return row;
      }
      if (Array.isArray(row) && row.length === 1 && row[0] && typeof row[0] === "object") {
        return row[0];
      }
      return {};
    });
  }

  function rowValue(row, columnNames) {
    if (!row || typeof row !== "object") {
      return "";
    }

    const keys = Object.keys(row);
    for (const candidate of columnNames) {
      if (Object.prototype.hasOwnProperty.call(row, candidate)) {
        return asText(row[candidate]);
      }
      const fallbackKey = keys.find((key) => key.toLowerCase() === String(candidate).toLowerCase());
      if (fallbackKey) {
        return asText(row[fallbackKey]);
      }
    }
    return "";
  }

  function asText(value) {
    if (value == null) {
      return "";
    }
    if (Array.isArray(value)) {
      return value.map(asText).filter(Boolean).join(" ");
    }
    if (typeof value === "object") {
      try {
        return JSON.stringify(value);
      } catch (_) {
        return String(value);
      }
    }
    return String(value);
  }

  function readCardQuantityFromRow(row) {
    const raw = rowValue(row, ["quantity", "qty", "count", "owned"]).trim();
    if (!raw) {
      const parsedLine = parseDeckLine(rowValue(row, ["line", "card_line", "raw", "entry"]));
      if (Number.isFinite(parsedLine?.quantity) && parsedLine.quantity > 0) {
        return parsedLine.quantity;
      }
    }
    const quantity = Number.parseInt(raw, 10);
    return Number.isFinite(quantity) && quantity > 0 ? quantity : 1;
  }

  function rowHasExplicitQuantity(row) {
    return Boolean(rowValue(row, ["quantity", "qty", "count", "owned"]).trim());
  }

  function isLandRow(row) {
    const typeLine = rowValue(row, ["type_line", "type"]).toLowerCase();
    if (/\bland\b/i.test(typeLine)) {
      return true;
    }
    const nameAndType = `${rowValue(row, ["name", "line"])} ${typeLine}`;
    return parseBasicLandColorCodes(nameAndType).length > 0;
  }

  function readCardCmc(row) {
    const cmcRaw = rowValue(row, ["cmc", "mana_value"]).replace(",", ".").trim();
    const numeric = Number.parseFloat(cmcRaw);
    if (Number.isFinite(numeric) && numeric >= 0) {
      return numeric;
    }
    return cmcFromManaCost(rowValue(row, ["mana_cost", "manacost"]));
  }

  function cmcFromManaCost(manaCostText) {
    const raw = String(manaCostText || "").trim();
    if (!raw) {
      return 0;
    }

    const symbols = raw.match(/\{([^}]+)\}/g);
    if (!symbols) {
      return 0;
    }

    let value = 0;
    symbols.forEach((symbolRaw) => {
      const token = symbolRaw.slice(1, -1).trim().toUpperCase();
      if (!token || token === "X" || token === "Y" || token === "Z") {
        return;
      }
      if (/^[0-9]+$/.test(token)) {
        value += Number.parseInt(token, 10);
        return;
      }
      value += 1;
    });

    return value;
  }

  function computeManaSourceSegments(landCards) {
    const counts = new Map([
      ["W", 0],
      ["U", 0],
      ["B", 0],
      ["R", 0],
      ["G", 0],
      ["C", 0],
      ["M", 0]
    ]);

    landCards.forEach((entry) => {
      const colors = colorCodesForRow(entry.row);
      if (colors.length === 0) {
        counts.set("C", counts.get("C") + entry.quantity);
        return;
      }
      if (colors.length > 1) {
        counts.set("M", counts.get("M") + entry.quantity);
        return;
      }
      const code = colors[0];
      counts.set(code, (counts.get(code) || 0) + entry.quantity);
    });

    return compactSegments([
      { key: "W", label: "White", color: "#ddd5bb", value: counts.get("W") || 0 },
      { key: "U", label: "Blue", color: "#5f84df", value: counts.get("U") || 0 },
      { key: "B", label: "Black", color: "#1f1b18", value: counts.get("B") || 0 },
      { key: "R", label: "Red", color: "#d62d3d", value: counts.get("R") || 0 },
      { key: "G", label: "Green", color: "#2c9958", value: counts.get("G") || 0 },
      { key: "C", label: "Colorless", color: "#7f8aa1", value: counts.get("C") || 0 },
      { key: "M", label: "Multi", color: "#d837a8", value: counts.get("M") || 0 }
    ], 5);
  }

  function computeCastingCostSegments(nonLandCards) {
    const buckets = new Map([
      ["0-1", 0],
      ["2", 0],
      ["3", 0],
      ["4+", 0]
    ]);

    nonLandCards.forEach((entry) => {
      const cmc = readCardCmc(entry.row);
      if (cmc <= 1.5) {
        buckets.set("0-1", buckets.get("0-1") + entry.quantity);
        return;
      }
      if (cmc <= 2.5) {
        buckets.set("2", buckets.get("2") + entry.quantity);
        return;
      }
      if (cmc <= 3.5) {
        buckets.set("3", buckets.get("3") + entry.quantity);
        return;
      }
      buckets.set("4+", buckets.get("4+") + entry.quantity);
    });

    return compactSegments([
      { key: "0-1", label: "0-1", color: "#e2d8ba", value: buckets.get("0-1") || 0 },
      { key: "2", label: "2", color: "#d5caab", value: buckets.get("2") || 0 },
      { key: "3", label: "3", color: "#31271f", value: buckets.get("3") || 0 },
      { key: "4+", label: "4+", color: "#af1f2b", value: buckets.get("4+") || 0 }
    ], 4);
  }

  function computeTypeSegments(cards) {
    const buckets = new Map([
      ["Creature", 0],
      ["Land", 0],
      ["Instant", 0],
      ["Sorcery", 0],
      ["Artifact", 0],
      ["Enchantment", 0],
      ["Planeswalker", 0],
      ["Battle", 0],
      ["Other", 0]
    ]);

    cards.forEach((entry) => {
      const cardType = primaryCardType(entry.row);
      buckets.set(cardType, (buckets.get(cardType) || 0) + entry.quantity);
    });

    return compactSegments([
      { key: "Creature", label: "Creature", color: "#e11d5d", value: buckets.get("Creature") || 0 },
      { key: "Land", label: "Land", color: "#5c80d7", value: buckets.get("Land") || 0 },
      { key: "Instant", label: "Instant", color: "#d53aa7", value: buckets.get("Instant") || 0 },
      { key: "Sorcery", label: "Sorcery", color: "#ff6d29", value: buckets.get("Sorcery") || 0 },
      { key: "Artifact", label: "Artifact", color: "#f5a623", value: buckets.get("Artifact") || 0 },
      { key: "Enchantment", label: "Enchant", color: "#84c643", value: buckets.get("Enchantment") || 0 },
      { key: "Planeswalker", label: "Walker", color: "#8c69ed", value: buckets.get("Planeswalker") || 0 },
      { key: "Battle", label: "Battle", color: "#1db4ad", value: buckets.get("Battle") || 0 },
      { key: "Other", label: "Other", color: "#6c768d", value: buckets.get("Other") || 0 }
    ], 6);
  }

  function computeColorDistributionSegments(nonLandCards) {
    const buckets = new Map([
      ["W", 0],
      ["U", 0],
      ["B", 0],
      ["R", 0],
      ["G", 0],
      ["C", 0],
      ["M", 0]
    ]);

    nonLandCards.forEach((entry) => {
      const colors = colorCodesForRow(entry.row);
      if (colors.length === 0) {
        buckets.set("C", buckets.get("C") + entry.quantity);
        return;
      }
      if (colors.length > 1) {
        buckets.set("M", buckets.get("M") + entry.quantity);
        return;
      }
      buckets.set(colors[0], (buckets.get(colors[0]) || 0) + entry.quantity);
    });

    return compactSegments([
      { key: "W", label: "White", color: "#ddd5bb", value: buckets.get("W") || 0 },
      { key: "U", label: "Blue", color: "#5f84df", value: buckets.get("U") || 0 },
      { key: "B", label: "Black", color: "#1f1b18", value: buckets.get("B") || 0 },
      { key: "R", label: "Red", color: "#d62d3d", value: buckets.get("R") || 0 },
      { key: "G", label: "Green", color: "#2c9958", value: buckets.get("G") || 0 },
      { key: "C", label: "Colorless", color: "#7f8aa1", value: buckets.get("C") || 0 },
      { key: "M", label: "Multi", color: "#d837a8", value: buckets.get("M") || 0 }
    ], 5);
  }

  function compactSegments(entries, maxSegments) {
    const filtered = entries
      .filter((entry) => entry.value > 0)
      .sort((left, right) => right.value - left.value);

    if (filtered.length <= maxSegments) {
      return filtered;
    }

    const head = filtered.slice(0, maxSegments - 1);
    const tail = filtered.slice(maxSegments - 1);
    const others = tail.reduce((sum, entry) => sum + entry.value, 0);
    head.push({
      key: "OTH",
      label: "Other",
      color: "#6b7388",
      value: others
    });
    return head;
  }

  function conicGradientFromSegments(segments) {
    const total = sumSegmentValues(segments);
    if (total <= 0) {
      return "conic-gradient(from -90deg, rgba(120, 140, 170, 0.28) 0 100%)";
    }

    let cursor = 0;
    const stops = segments.map((segment) => {
      const delta = (segment.value / total) * 100;
      const start = cursor.toFixed(2);
      cursor += delta;
      const end = cursor.toFixed(2);
      return `${segment.color} ${start}% ${end}%`;
    });
    return `conic-gradient(from -90deg, ${stops.join(", ")})`;
  }

  function sumSegmentValues(segments) {
    return segments.reduce((sum, segment) => sum + segment.value, 0);
  }

  function segmentListMarkup(segments) {
    if (!Array.isArray(segments) || segments.length === 0) {
      return '<p class="deck-stats-note">No data</p>';
    }
    const items = segments
      .map((segment) => `
        <li class="ring-legend-item">
          <span class="ring-legend-dot" style="--dot-color: ${segment.color};"></span>
          <span class="ring-legend-label">${escapeHtml(segment.label)}</span>
          <span class="ring-legend-value">${formatCount(segment.value)}</span>
        </li>
      `)
      .join("");
    return `<ul class="ring-legend">${items}</ul>`;
  }

  function primaryCardType(row) {
    const typeLine = rowValue(row, ["type_line", "type"]).toLowerCase();
    if (isLandRow(row)) {
      return "Land";
    }
    if (typeLine.includes("creature")) {
      return "Creature";
    }
    if (typeLine.includes("instant")) {
      return "Instant";
    }
    if (typeLine.includes("sorcery")) {
      return "Sorcery";
    }
    if (typeLine.includes("artifact")) {
      return "Artifact";
    }
    if (typeLine.includes("enchantment")) {
      return "Enchantment";
    }
    if (typeLine.includes("planeswalker")) {
      return "Planeswalker";
    }
    if (typeLine.includes("battle")) {
      return "Battle";
    }
    return "Other";
  }

  function colorCodesForRow(row) {
    const direct = parseColorCodes(rowValue(row, ["color_identity", "colors"]));
    if (direct.length > 0) {
      return direct;
    }

    const fromCost = parseManaCostColorCodes(rowValue(row, ["mana_cost", "manacost"]));
    if (fromCost.length > 0) {
      return fromCost;
    }

    return parseBasicLandColorCodes(`${rowValue(row, ["type_line"])} ${rowValue(row, ["name"])}`);
  }

  function parseColorCodes(rawValue) {
    const source = String(rawValue || "").toUpperCase();
    if (!source) {
      return [];
    }

    const found = new Set();
    if (source.includes("WHITE")) {
      found.add("W");
    }
    if (source.includes("BLUE")) {
      found.add("U");
    }
    if (source.includes("BLACK")) {
      found.add("B");
    }
    if (source.includes("RED")) {
      found.add("R");
    }
    if (source.includes("GREEN")) {
      found.add("G");
    }

    const compact = source.replace(/[^WUBRG]/g, "");
    if (compact.length > 0 && compact.length <= 8) {
      compact.split("").forEach((code) => found.add(code));
    }

    return Array.from(found).filter((code) => "WUBRG".includes(code));
  }

  function parseManaCostColorCodes(manaCostText) {
    const source = String(manaCostText || "").toUpperCase();
    if (!source) {
      return [];
    }

    const found = new Set();
    const symbols = source.match(/\{([^}]+)\}/g) || [];
    symbols.forEach((symbolRaw) => {
      const token = symbolRaw.slice(1, -1);
      for (const code of ["W", "U", "B", "R", "G"]) {
        if (token.includes(code)) {
          found.add(code);
        }
      }
    });
    return Array.from(found);
  }

  function parseBasicLandColorCodes(textBlob) {
    const source = String(textBlob || "").toLowerCase();
    if (!source) {
      return [];
    }
    const found = [];
    if (source.includes("plains")) {
      found.push("W");
    }
    if (source.includes("island")) {
      found.push("U");
    }
    if (source.includes("swamp")) {
      found.push("B");
    }
    if (source.includes("mountain")) {
      found.push("R");
    }
    if (source.includes("forest")) {
      found.push("G");
    }
    return Array.from(new Set(found));
  }

  function formatDecimal(value) {
    if (!Number.isFinite(value)) {
      return "0.0";
    }
    return value.toFixed(1);
  }

  function formatCount(value) {
    if (!Number.isFinite(value)) {
      return "0";
    }
    if (Math.abs(value - Math.round(value)) < 0.01) {
      return String(Math.round(value));
    }
    return value.toFixed(1);
  }

  function formatPercent(value) {
    if (!Number.isFinite(value)) {
      return "0%";
    }
    return `${Math.round(value * 100)}%`;
  }

  function attachCollectionListEvents() {
    nodes.collections.list.addEventListener("click", async (event) => {
      const button = event.target.closest("button[data-action]");
      const item = event.target.closest(".entity-item");
      if (!item) {
        return;
      }

      const id = item.getAttribute("data-entity-id");
      if (!id) {
        return;
      }

      const action = button?.dataset.action || "select";

      if (action === "select") {
        state.selectedCollectionId = id;
        renderCollectionsList("");
        renderActiveTabTable();
        if (!state.collectionPayloadById[id]) {
          await loadStoredCollectionIntoTable(id);
        }
        return;
      }

      if (action === "delete") {
        const out = await deleteStoredCollection(id);
        if (!out || out.ok !== true) {
          renderCollection({
            ok: false,
            table: "Collections",
            error: out?.error || "Suppression impossible"
          });
          return;
        }

        delete state.collectionPayloadById[id];
        await refreshCollectionsListFromApi();
        renderActiveTabTable();
        if (state.selectedCollectionId && !state.collectionPayloadById[state.selectedCollectionId]) {
          await loadStoredCollectionIntoTable(state.selectedCollectionId);
        }
      }
    });
  }

  function attachDeckListEvents() {
    nodes.decks.list.addEventListener("click", (event) => {
      const button = event.target.closest("button[data-action]");
      const item = event.target.closest("[data-entity-id]");
      if (!item) {
        return;
      }

      const id = item.getAttribute("data-entity-id");
      if (!id) {
        return;
      }

      const action = button?.dataset.action || "select";

      if (action === "select") {
        state.selectedDeckId = id;
        saveDeckStateToStorage();
        renderDecksList();
        renderActiveTabTable();
        return;
      }

      if (action === "delete") {
        state.decks = state.decks.filter((entry) => entry.id !== id);
        if (state.selectedDeckId === id) {
          state.selectedDeckId = state.decks[0]?.id || null;
        }
        saveDeckStateToStorage();
        renderDecksList();
        renderActiveTabTable();
      }
    });
  }

  function uniqueId(prefix) {
    return `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  }

  function escapeHtml(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;");
  }

  async function init() {
    const initialLanguage = getCollectionLanguage();
    applyLanguageButtonState(initialLanguage);

    if (nodes.langEnButton && nodes.langFrButton) {
      nodes.langEnButton.addEventListener("click", () => onLanguageSelect("en"));
      nodes.langFrButton.addEventListener("click", () => onLanguageSelect("fr"));
    }

    nodes.tabButtons.forEach((button) => {
      button.addEventListener("click", () => selectTab(button.dataset.tab || "collections"));
    });

    bindCollectionPicker();
    bindDeckPicker();
    loadDeckStateFromStorage();

    nodes.collections.form.addEventListener("submit", async (event) => {
      event.preventDefault();

      const selected = nodes.collections.fileInput.files && nodes.collections.fileInput.files[0];
      if (!selected) {
        renderCollection({
          ok: false,
          table: "Collections",
          error: "Selectionne un csv."
        });
        return;
      }

      const payload = await importCollectionCsv(
        selected,
        nodes.collections.nameInput.value.trim(),
        "auto"
      );

      if (!payload || payload.ok !== true) {
        renderCollection({
          ok: false,
          table: "Collections",
          error: payload?.error || "Import impossible"
        });
        return;
      }

      await refreshCollectionsListFromApi();
      const newId = payload.collection?.id || state.collections[0]?.id || null;
      if (newId) {
        state.selectedCollectionId = newId;
      }
      nodes.collections.nameInput.value = "";
      nodes.collections.fileInput.value = "";
      setCollectionPickButtonLabel("Choisir CSV");
      nodes.collections.pickFileButton.classList.remove("has-file");
      renderCollectionsList("");
      renderActiveTabTable();
      if (state.selectedCollectionId) {
        await loadStoredCollectionIntoTable(state.selectedCollectionId);
      }
    });

    nodes.decks.form.addEventListener("submit", async (event) => {
      event.preventDefault();
      const selected = nodes.decks.fileInput.files && nodes.decks.fileInput.files[0];
      if (!selected) {
        renderCollection({
          ok: false,
          table: "Decks",
          error: "Selectionne un fichier."
        });
        return;
      }

      const sourceType = inferDeckSourceType(selected.name);
      const payload = await uploadCollection(selected, sourceType, "");
      if (!payload || payload.ok !== true) {
        if (state.activeTab === "decks") {
          renderCollection(payload || {
            ok: false,
            error: "Impossible de charger le deck."
          });
        }
        return;
      }
      const rawName = nodes.decks.nameInput.value.trim();
      const deckName = rawName || `Deck ${state.decks.length + 1}`;
      const entry = {
        id: uniqueId("deck"),
        name: deckName,
        payload
      };
      state.decks.unshift(entry);
      if (state.decks.length > MAX_STORED_DECKS) {
        state.decks = state.decks.slice(0, MAX_STORED_DECKS);
      }
      state.selectedDeckId = entry.id;
      saveDeckStateToStorage();
      renderDecksList();
      nodes.decks.nameInput.value = "";
      nodes.decks.fileInput.value = "";
      setDeckPickButtonLabel("Choisir un fichier deck");
      nodes.decks.pickFileButton.classList.remove("has-file");
      if (state.activeTab === "decks") {
        renderActiveTabTable();
      }
    });

    attachCollectionListEvents();
    attachDeckListEvents();

    await refreshCollectionsListFromApi();
    if (state.selectedCollectionId) {
      await loadStoredCollectionIntoTable(state.selectedCollectionId);
    }
    renderDecksList();
    renderActiveTabTable();
  }

  init().catch((error) => {
    renderCollection({
      ok: false,
      error: String(error)
    });
  });
})();
