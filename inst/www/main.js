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
    selectedDeckId: null,
    strategy: {
      seedName: "",
      directLimit: 12,
      groupLimit: 6,
      modelCache: new Map(),
      lastCollectionId: null
    }
  };

  const DECK_STORAGE_KEY = "mtgcodex_ui_decks_v1";
  const MAX_STORED_DECKS = 24;
  const DECK_STATS_STATE = {
    requestToken: 0,
    metadataCache: new Map()
  };
  const DECK_ANALYSIS_STATE = {
    requestToken: 0,
    activePane: "stats"
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
    },
    strategy: {
      sourceMeta: document.getElementById("strategy-source-meta"),
      seedInput: document.getElementById("strategy-seed-input"),
      seedList: document.getElementById("strategy-seed-list"),
      directLimitInput: document.getElementById("strategy-direct-limit"),
      groupLimitInput: document.getElementById("strategy-group-limit"),
      runButton: document.getElementById("strategy-run-btn"),
      status: document.getElementById("strategy-status"),
      directList: document.getElementById("strategy-direct-list"),
      groupList: document.getElementById("strategy-group-list")
    }
  };

  const STRATEGY_FEATURE_PATTERNS = [
    { id: "graveyard", weight: 1, regex: /\bgraveyard\b|\bmill\b|\bdredge\b|descend/i },
    { id: "reanimate", weight: 2, regex: /return target .*graveyard.*battlefield|return .* from your graveyard to the battlefield|\breanimate\b|\bresurrect\b/i },
    { id: "entomb_line", weight: 2, regex: /search your library .* put .* graveyard|put .* from your library .* graveyard/i },
    { id: "poison_toxic", weight: 2, regex: /\btoxic\b|\bpoison counter\b|\binfect\b|\bcorrupted\b/i },
    { id: "proliferate", weight: 2, regex: /\bproliferate\b/i },
    { id: "discard", weight: 1, regex: /\bdiscard\b|loot|connive/i },
    { id: "draw", weight: 1, regex: /\bdraw\b/i },
    { id: "sacrifice", weight: 1, regex: /\bsacrifice\b/i },
    { id: "deathtouch", weight: 1, regex: /\bdeathtouch\b/i },
    { id: "combat_evasion", weight: 1, regex: /\bflying\b|\btrample\b|\bmenace\b|can't be blocked/i },
    { id: "fight_bite", weight: 1, regex: /target creature you control deals damage|fight target/i },
    { id: "etb", weight: 1, regex: /enters the battlefield|\betb\b/i },
    { id: "token", weight: 1, regex: /\btoken\b|create .* token/i },
    { id: "removal", weight: 1, regex: /destroy target|exile target|sacrifice target|counter target/i },
    { id: "tutor", weight: 1, regex: /search your library|surveil|tutor/i },
    { id: "recursion", weight: 1, regex: /return .* from your graveyard to your hand|flashback|escape/i },
    { id: "combo_copy", weight: 2, regex: /copy target spell|copy that spell|magecraft|when you cast or copy/i },
    { id: "combo_lifeloss", weight: 1, regex: /each opponent loses|target opponent loses|opponents lose|lose life/i },
    { id: "combo_worldgorger", weight: 2, regex: /worldgorger dragon|exile all other permanents you control/i },
    { id: "combo_chain_smog", weight: 2, regex: /target player discards two cards|that player may copy this spell|you may copy this spell/i }
  ];
  const STRATEGY_FEATURE_LABELS = {
    graveyard: "Graveyard",
    reanimate: "Reanimate",
    entomb_line: "Entomb lines",
    poison_toxic: "Poison/Toxic",
    proliferate: "Proliferate",
    discard: "Discard",
    draw: "Card draw",
    sacrifice: "Sacrifice",
    deathtouch: "Deathtouch",
    combat_evasion: "Combat evasion",
    fight_bite: "Fight/Bite",
    etb: "ETB",
    token: "Tokens",
    removal: "Removal",
    tutor: "Tutor",
    recursion: "Recursion",
    combo_copy: "Copy spells",
    combo_lifeloss: "Life loss",
    combo_worldgorger: "Worldgorger line",
    combo_chain_smog: "Chain of Smog line"
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

  function bindStrategyControls() {
    const strategyNodes = nodes.strategy;
    if (!strategyNodes.seedInput || !strategyNodes.runButton) {
      return;
    }

    strategyNodes.seedInput.addEventListener("input", () => {
      state.strategy.seedName = strategyNodes.seedInput.value || "";
    });

    strategyNodes.seedInput.addEventListener("keydown", (event) => {
      if (event.key === "Enter") {
        event.preventDefault();
        runStrategyComputation();
      }
    });

    strategyNodes.directLimitInput?.addEventListener("change", () => {
      state.strategy.directLimit = clampInt(strategyNodes.directLimitInput.value, 4, 24, 12);
    });

    strategyNodes.groupLimitInput?.addEventListener("change", () => {
      state.strategy.groupLimit = clampInt(strategyNodes.groupLimitInput.value, 3, 12, 6);
    });

    strategyNodes.runButton.addEventListener("click", () => {
      runStrategyComputation();
    });
  }

  function bindDeckAnalysisControls() {
    if (!nodes.deckStatsContent) {
      return;
    }
    nodes.deckStatsContent.addEventListener("click", (event) => {
      const trigger = event.target.closest("[data-action='analyze-deck']");
      if (!trigger) {
        return;
      }
      runDeckRecommendationAnalysis();
    });
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

  function payloadForNamedView(payload, name, fallbackSummary, viewMode = "table", uiContext = "") {
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
      view_mode: viewMode,
      ui_context: uiContext || ""
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
    if (
      (state.activeTab === "collections" || state.activeTab === "strategy") &&
      state.selectedCollectionId === collectionId
    ) {
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

      renderCollection(payloadForNamedView(payload, meta?.name || "Collection", "collection/store", "cards", "collections"));
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
      renderCollection(payloadForNamedView(selected.payload, selected.name, "deck/local", "cards", "decks"));
      renderDeckStatsPanel(selected);
      return;
    }

    if (state.activeTab === "strategy") {
      const meta = state.collections.find((entry) => entry.id === state.selectedCollectionId);
      const payload = state.selectedCollectionId
        ? state.collectionPayloadById[state.selectedCollectionId]
        : null;

      if (payload && payload.ok === true) {
        renderCollection(payloadForNamedView(
          payload,
          meta?.name || "Collection",
          "collection/store",
          "cards",
          "strategy"
        ));
      } else {
        renderCollection({
          ok: false,
          table: "Strategy",
          error: "Selectionne une collection chargee pour calculer les synergies."
        });
      }
      renderStrategyPanel(payload, meta);
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
      DECK_ANALYSIS_STATE.requestToken += 1;
      content.classList.add("muted");
      content.classList.remove("is-loading");
      content.innerHTML = "Selectionne un deck pour afficher ses statistiques.";
      return;
    }

    if (!deckEntry || deckEntry.payload?.ok !== true) {
      DECK_STATS_STATE.requestToken += 1;
      DECK_ANALYSIS_STATE.requestToken += 1;
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
    initializeDeckStatsTabs(content);
    renderDeckAnalysisState(deckEntry, null);

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
        initializeDeckStatsTabs(content);
        renderDeckAnalysisState(deckEntry, null);
      })
      .catch(() => {
        if (requestToken !== DECK_STATS_STATE.requestToken) {
          return;
        }
        content.classList.remove("is-loading");
        renderDeckAnalysisState(deckEntry, null);
      });
  }

  function initializeDeckStatsTabs(container) {
    if (!container) {
      return;
    }
    container.querySelectorAll("[data-deck-pane-tab]").forEach((button) => {
      button.addEventListener("click", () => {
        const pane = String(button.dataset.deckPaneTab || "stats").toLowerCase();
        setDeckStatsPane(container, pane);
      });
    });
    setDeckStatsPane(container, DECK_ANALYSIS_STATE.activePane || "stats");
  }

  function setDeckStatsPane(container, paneName) {
    if (!container) {
      return;
    }
    const pane = paneName === "analysis" ? "analysis" : "stats";
    DECK_ANALYSIS_STATE.activePane = pane;

    container.querySelectorAll("[data-deck-pane-tab]").forEach((button) => {
      const isActive = String(button.dataset.deckPaneTab || "").toLowerCase() === pane;
      button.classList.toggle("is-active", isActive);
      button.setAttribute("aria-selected", isActive ? "true" : "false");
      button.tabIndex = isActive ? 0 : -1;
    });

    container.querySelectorAll("[data-deck-pane]").forEach((panel) => {
      const isActive = String(panel.dataset.deckPane || "").toLowerCase() === pane;
      panel.classList.toggle("is-active", isActive);
    });
  }

  function renderDeckAnalysisState(deckEntry, analysisResult) {
    const runButton = document.getElementById("deck-analyze-btn");
    const statusNode = document.getElementById("deck-analysis-status");
    const mechanicsNode = document.getElementById("deck-analysis-mechanics");
    const upgradeNode = document.getElementById("deck-analysis-upgrade");
    const variationNode = document.getElementById("deck-analysis-variation");
    if (!runButton || !statusNode || !mechanicsNode || !upgradeNode || !variationNode) {
      return;
    }

    runButton.textContent = "Analyser";
    runButton.disabled = false;

    const collectionMeta = state.collections.find((entry) => entry.id === state.selectedCollectionId) || null;
    const collectionPayload = state.selectedCollectionId
      ? state.collectionPayloadById[state.selectedCollectionId]
      : null;
    const hasCollection = Boolean(collectionPayload && collectionPayload.ok === true);

    if (!deckEntry || !deckEntry.payload || deckEntry.payload.ok !== true) {
      runButton.disabled = true;
      statusNode.textContent = "Selectionne un deck pour lancer une analyse.";
      mechanicsNode.innerHTML = "";
      upgradeNode.innerHTML = '<p class="muted">Aucune proposition.</p>';
      variationNode.innerHTML = '<p class="muted">Aucune proposition.</p>';
      return;
    }

    if (!hasCollection) {
      runButton.disabled = true;
      statusNode.textContent = "Selectionne une collection chargee pour proposer des cartes.";
      mechanicsNode.innerHTML = "";
      upgradeNode.innerHTML = '<p class="muted">Choisis une collection active.</p>';
      variationNode.innerHTML = '<p class="muted">Choisis une collection active.</p>';
      return;
    }

    if (!analysisResult) {
      const sourceName = collectionMeta?.name || "collection active";
      statusNode.textContent = `Pret pour analyse. Source recommandations: ${sourceName}.`;
      mechanicsNode.innerHTML = "";
      upgradeNode.innerHTML = '<p class="muted">Clique sur Analyser pour proposer des cartes d amelioration.</p>';
      variationNode.innerHTML = '<p class="muted">Clique sur Analyser pour proposer des cartes de variation.</p>';
      return;
    }

    const mechanicsMarkup = (analysisResult.mechanics || [])
      .map((item) => `<span class="deck-mechanic-chip">${escapeHtml(item.label)} ${Math.round(item.share * 100)}%</span>`)
      .join("");
    mechanicsNode.innerHTML = mechanicsMarkup || '<p class="muted">Aucune mecanique dominante detectee.</p>';

    renderDeckRecommendationCards(
      upgradeNode,
      analysisResult.upgrades,
      "improveScore",
      "Aucune amelioration pertinente trouvee."
    );
    renderDeckRecommendationCards(
      variationNode,
      analysisResult.variants,
      "variationScore",
      "Aucune variation pertinente trouvee."
    );

    const sourceName = collectionMeta?.name || "collection active";
    statusNode.textContent = `Analyse terminee. ${analysisResult.upgrades.length} ameliorations et ${analysisResult.variants.length} variations proposees depuis ${sourceName}.`;
  }

  function renderDeckRecommendationCards(target, entries, scoreField, emptyMessage) {
    if (!target) {
      return;
    }
    if (!Array.isArray(entries) || entries.length === 0) {
      target.innerHTML = `<p class="muted">${escapeHtml(emptyMessage)}</p>`;
      return;
    }

    target.innerHTML = "";
    const fragment = document.createDocumentFragment();
    entries.forEach((entry, index) => {
      const scoreValue = Number.isFinite(entry?.[scoreField]) ? entry[scoreField] : 0;
      const reason = String(entry?.reason || "").trim();
      const metaLine = reason
        ? `#${index + 1} | score ${formatDecimal(scoreValue)} | ${reason}`
        : `#${index + 1} | score ${formatDecimal(scoreValue)}`;
      fragment.appendChild(createStrategyCardElement(entry.card, metaLine));
    });
    target.appendChild(fragment);
  }

  async function runDeckRecommendationAnalysis() {
    const runButton = document.getElementById("deck-analyze-btn");
    const statusNode = document.getElementById("deck-analysis-status");
    if (!runButton || !statusNode) {
      return;
    }

    const deckEntry = state.decks.find((entry) => entry.id === state.selectedDeckId);
    if (!deckEntry || deckEntry.payload?.ok !== true) {
      renderDeckAnalysisState(null, null);
      return;
    }

    const collectionId = state.selectedCollectionId;
    const collectionPayload = collectionId ? state.collectionPayloadById[collectionId] : null;
    if (!collectionPayload || collectionPayload.ok !== true) {
      renderDeckAnalysisState(deckEntry, null);
      return;
    }

    const requestToken = ++DECK_ANALYSIS_STATE.requestToken;
    setDeckStatsPane(nodes.deckStatsContent, "analysis");
    runButton.disabled = true;
    runButton.textContent = "Analyse...";
    statusNode.textContent = "Analyse du deck en cours...";

    try {
      let deckEntries = buildDeckEntries(deckEntry.payload);
      if (!deckEntries.length) {
        renderDeckAnalysisState(deckEntry, {
          mechanics: [],
          upgrades: [],
          variants: []
        });
        return;
      }

      if (deckEntries.some((entry) => entryNeedsAnalysisMetadata(entry.row))) {
        const enriched = await enrichDeckEntriesForAnalysis(deckEntries, requestToken);
        if (!enriched || requestToken !== DECK_ANALYSIS_STATE.requestToken) {
          return;
        }
        deckEntries = enriched;
      }

      if (requestToken !== DECK_ANALYSIS_STATE.requestToken) {
        return;
      }

      const deckRows = deckEntries.map((entry) => ({
        ...entry.row,
        quantity: entry.quantity
      }));
      const deckModel = buildStrategyModelFromRows(deckRows);
      const collectionModel = getStrategyModelForCollection(collectionId, collectionPayload);

      const analysis = computeDeckRecommendationAnalysis(deckModel.cards, collectionModel.cards);
      if (requestToken !== DECK_ANALYSIS_STATE.requestToken) {
        return;
      }
      renderDeckAnalysisState(deckEntry, analysis);
    } catch (_) {
      if (requestToken !== DECK_ANALYSIS_STATE.requestToken) {
        return;
      }
      statusNode.textContent = "Analyse impossible pour ce deck.";
    } finally {
      if (requestToken === DECK_ANALYSIS_STATE.requestToken) {
        runButton.disabled = false;
        runButton.textContent = "Analyser";
      }
    }
  }

  function entryNeedsAnalysisMetadata(row) {
    const needsBase = entryNeedsMetadata(row);
    const hasOracle = Boolean(rowValue(row, ["oracle_text", "printed_text", "card_text", "rules_text"]).trim());
    const hasScryfall = Boolean(rowValue(row, ["scryfall_id", "scry_fall_id"]).trim());
    return needsBase || !hasOracle || !hasScryfall;
  }

  async function enrichDeckEntriesForAnalysis(entries, requestToken) {
    const uniqueNames = Array.from(new Set(
      entries
        .map((entry) => String(entry.name || "").trim())
        .filter(Boolean)
    )).slice(0, 120);

    const metadataByName = new Map();
    for (let i = 0; i < uniqueNames.length; i += 8) {
      if (requestToken !== DECK_ANALYSIS_STATE.requestToken) {
        return null;
      }
      const chunk = uniqueNames.slice(i, i + 8);
      const chunkData = await Promise.all(chunk.map((name) => fetchDeckCardMetadata(name)));
      chunk.forEach((name, index) => {
        if (chunkData[index]) {
          metadataByName.set(name, chunkData[index]);
        }
      });
    }

    if (requestToken !== DECK_ANALYSIS_STATE.requestToken) {
      return null;
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
      if (!rowValue(mergedRow, ["oracle_text", "printed_text", "card_text", "rules_text"]) && metadata.oracle_text) {
        mergedRow.oracle_text = metadata.oracle_text;
      }
      if (!rowValue(mergedRow, ["keywords", "abilities", "keyword"]) && metadata.keywords.length > 0) {
        mergedRow.keywords = metadata.keywords.join(", ");
      }
      if (!rowValue(mergedRow, ["scryfall_id", "scry_fall_id"]) && metadata.scryfall_id) {
        mergedRow.scryfall_id = metadata.scryfall_id;
      }
      if (!rowValue(mergedRow, ["set_code", "set"]) && metadata.set_code) {
        mergedRow.set_code = metadata.set_code;
      }
      if (!rowValue(mergedRow, ["collector_number"]) && metadata.collector_number) {
        mergedRow.collector_number = metadata.collector_number;
      }

      return {
        ...entry,
        row: mergedRow
      };
    });
  }

  function computeDeckRecommendationAnalysis(deckCards, collectionCards) {
    const deckPool = Array.isArray(deckCards) ? deckCards.filter((card) => card && card.key) : [];
    const collectionPool = Array.isArray(collectionCards) ? collectionCards.filter((card) => card && card.key) : [];
    if (!deckPool.length || !collectionPool.length) {
      return { mechanics: [], upgrades: [], variants: [] };
    }

    const featureProfile = {};
    deckPool.forEach((card) => {
      const quantity = Math.max(1, Number(card.quantity) || 1);
      Object.keys(card.features || {}).forEach((featureId) => {
        const value = Number(card.features[featureId] || 0);
        if (value <= 0) {
          return;
        }
        featureProfile[featureId] = (featureProfile[featureId] || 0) + (value * quantity);
      });
    });

    const totalFeatureWeight = Object.values(featureProfile).reduce((sum, value) => sum + value, 0);
    const mechanics = Object.keys(featureProfile)
      .map((featureId) => ({
        id: featureId,
        label: strategyFeatureLabel(featureId),
        value: featureProfile[featureId],
        share: totalFeatureWeight > 0 ? featureProfile[featureId] / totalFeatureWeight : 0
      }))
      .filter((entry) => entry.value > 0)
      .sort((left, right) => right.value - left.value)
      .slice(0, 8);

    const deckCore = deckPool
      .map((card) => {
        let score = 0;
        deckPool.forEach((other) => {
          if (other.key === card.key) {
            return;
          }
          const link = strategySimilarity(card, other);
          const quantityWeight = Math.min(2, Math.max(1, Number(other.quantity) || 1));
          score += link.score * quantityWeight;
        });
        return { card, score };
      })
      .sort((left, right) => {
        if (Math.abs(right.score - left.score) > 1e-9) {
          return right.score - left.score;
        }
        return left.card.name.localeCompare(right.card.name);
      });

    const coreAnchors = deckCore.slice(0, Math.min(6, deckCore.length)).map((entry) => entry.card);
    const deckKeySet = new Set(deckPool.map((card) => card.key));
    const topMechanicSet = new Set(mechanics.slice(0, 3).map((entry) => entry.id));
    const profileKeys = new Set(Object.keys(featureProfile));

    const scored = [];
    collectionPool.forEach((candidate) => {
      if (deckKeySet.has(candidate.key)) {
        return;
      }

      const profileScore = cosineSimilaritySparse(featureProfile, candidate.features || {});
      let bestLink = { score: 0, anchorName: "" };
      coreAnchors.forEach((anchorCard) => {
        const link = strategySimilarity(anchorCard, candidate);
        if (link.score > bestLink.score) {
          bestLink = { score: link.score, anchorName: anchorCard.name };
        }
      });

      const improveScore = clampScore(profileScore * 0.62 + bestLink.score * 0.38);
      if (improveScore < 0.08) {
        return;
      }

      const candidateFeatures = Object.keys(candidate.features || {})
        .filter((featureId) => (candidate.features[featureId] || 0) > 0)
        .sort((left, right) => (candidate.features[right] || 0) - (candidate.features[left] || 0));
      const dominantFeature = candidateFeatures[0] || "";
      const offplan = dominantFeature ? !topMechanicSet.has(dominantFeature) : false;
      const novelty = Math.max(0, 1 - bestLink.score);
      const variationScore = clampScore(improveScore * 0.68 + novelty * 0.24 + (offplan ? 0.08 : 0));

      const sharedFeatures = candidateFeatures
        .filter((featureId) => profileKeys.has(featureId))
        .slice(0, 2)
        .map((featureId) => strategyFeatureLabel(featureId));

      const reasonParts = [];
      if (sharedFeatures.length > 0) {
        reasonParts.push(`match ${sharedFeatures.join(" + ")}`);
      }
      if (bestLink.anchorName) {
        reasonParts.push(`lien ${bestLink.anchorName}`);
      }
      if (offplan) {
        reasonParts.push("angle alternatif");
      }

      scored.push({
        card: candidate,
        improveScore,
        variationScore,
        reason: reasonParts.join(" | ")
      });
    });

    const upgrades = scored
      .slice()
      .sort((left, right) => {
        if (Math.abs(right.improveScore - left.improveScore) > 1e-9) {
          return right.improveScore - left.improveScore;
        }
        return left.card.name.localeCompare(right.card.name);
      })
      .slice(0, 10);

    const usedKeys = new Set(upgrades.map((entry) => entry.card.key));
    const variants = scored
      .filter((entry) => !usedKeys.has(entry.card.key))
      .sort((left, right) => {
        if (Math.abs(right.variationScore - left.variationScore) > 1e-9) {
          return right.variationScore - left.variationScore;
        }
        return left.card.name.localeCompare(right.card.name);
      })
      .slice(0, 10);

    return { mechanics, upgrades, variants };
  }

  function strategyFeatureLabel(featureId) {
    const key = String(featureId || "").trim();
    if (!key) {
      return "";
    }
    if (STRATEGY_FEATURE_LABELS[key]) {
      return STRATEGY_FEATURE_LABELS[key];
    }
    return key
      .replaceAll("_", " ")
      .replace(/\b\w/g, (match) => match.toUpperCase());
  }

  function renderStrategyPanel(payload, collectionMeta) {
    const strategyNodes = nodes.strategy;
    if (!strategyNodes.sourceMeta || !strategyNodes.seedInput) {
      return;
    }

    const collectionName = collectionMeta?.name || "Collection";
    if (!payload || payload.ok !== true) {
      strategyNodes.sourceMeta.textContent = "Selectionne un dossier collection charge pour activer le calcul.";
      strategyNodes.status.textContent = "Aucune source disponible.";
      strategyNodes.directList.innerHTML = '<p class="muted">Aucun resultat.</p>';
      strategyNodes.groupList.innerHTML = '<p class="muted">Aucun resultat.</p>';
      strategyNodes.seedList.innerHTML = "";
      return;
    }

    const model = getStrategyModelForCollection(state.selectedCollectionId, payload);
    strategyNodes.sourceMeta.textContent = `${collectionName} | ${model.cards.length} cartes analysees`;

    const currentCollectionChanged = state.strategy.lastCollectionId !== state.selectedCollectionId;
    state.strategy.lastCollectionId = state.selectedCollectionId;

    if (currentCollectionChanged) {
      state.strategy.seedName = "";
      strategyNodes.seedInput.value = "";
      strategyNodes.directList.innerHTML = '<p class="muted">Lance un calcul pour voir les synergies directes.</p>';
      strategyNodes.groupList.innerHTML = '<p class="muted">Lance un calcul pour voir les groupes de cartes.</p>';
      strategyNodes.status.textContent = "Choisis une carte seed puis clique sur Calculer.";
    }

    const directLimit = clampInt(strategyNodes.directLimitInput?.value, 4, 24, 12);
    const groupLimit = clampInt(strategyNodes.groupLimitInput?.value, 3, 12, 6);
    state.strategy.directLimit = directLimit;
    state.strategy.groupLimit = groupLimit;

    if (strategyNodes.directLimitInput) {
      strategyNodes.directLimitInput.value = String(directLimit);
    }
    if (strategyNodes.groupLimitInput) {
      strategyNodes.groupLimitInput.value = String(groupLimit);
    }

    const maxOptions = 800;
    const optionsMarkup = model.cards
      .slice(0, maxOptions)
      .map((card) => `<option value="${escapeHtml(card.name)}"></option>`)
      .join("");
    strategyNodes.seedList.innerHTML = optionsMarkup;
  }

  function runStrategyComputation() {
    const strategyNodes = nodes.strategy;
    if (!strategyNodes.seedInput || !strategyNodes.status) {
      return;
    }

    const collectionId = state.selectedCollectionId;
    const payload = collectionId ? state.collectionPayloadById[collectionId] : null;
    if (!payload || payload.ok !== true) {
      strategyNodes.status.textContent = "Charge d'abord une collection pour calculer les synergies.";
      return;
    }

    const model = getStrategyModelForCollection(collectionId, payload);
    if (!model.cards.length) {
      strategyNodes.status.textContent = "Collection vide ou cartes non reconnues.";
      strategyNodes.directList.innerHTML = '<p class="muted">Aucun resultat.</p>';
      strategyNodes.groupList.innerHTML = '<p class="muted">Aucun resultat.</p>';
      return;
    }

    const rawSeed = String(strategyNodes.seedInput.value || state.strategy.seedName || "").trim();
    if (!rawSeed) {
      strategyNodes.status.textContent = "Saisis une carte seed (ex: Entomb).";
      return;
    }

    const seedCard = resolveSeedCard(rawSeed, model.cards);
    if (!seedCard) {
      strategyNodes.status.textContent = `Carte "${rawSeed}" introuvable dans la collection.`;
      return;
    }

    state.strategy.seedName = seedCard.name;
    strategyNodes.seedInput.value = seedCard.name;

    const directLimit = clampInt(strategyNodes.directLimitInput?.value, 4, 24, state.strategy.directLimit);
    const groupLimit = clampInt(strategyNodes.groupLimitInput?.value, 3, 12, state.strategy.groupLimit);
    state.strategy.directLimit = directLimit;
    state.strategy.groupLimit = groupLimit;

    const direct = computeDirectSynergies(seedCard, model.cards, directLimit);
    const groups = computeSynergyGroups(seedCard, direct, model.cards, groupLimit);

    renderDirectSynergyCards(direct, seedCard.name);
    renderGroupCards(groups, seedCard.name);

    strategyNodes.status.textContent = `${seedCard.name}: ${direct.length} synergies directes, ${groups.length} groupes construits.`;
  }

  function getStrategyModelForCollection(collectionId, payload) {
    const cache = state.strategy.modelCache;
    const cacheKey = String(collectionId || "__none__");
    if (cache.has(cacheKey)) {
      return cache.get(cacheKey);
    }

    const model = buildStrategyModelFromPayload(payload);
    cache.set(cacheKey, model);
    return model;
  }

  function buildStrategyModelFromPayload(payload) {
    const rows = normalizeRowsFromPayload(payload);
    return buildStrategyModelFromRows(rows);
  }

  function buildStrategyModelFromRows(rows) {
    const cardsByName = new Map();

    rows.forEach((row) => {
      const name = rowValue(row, ["name", "card_name", "card", "title"]).trim();
      if (!name) {
        return;
      }

      const key = normalizeStrategyName(name);
      if (!key) {
        return;
      }

      const textBlob = [
        rowValue(row, ["type_line", "type"]),
        rowValue(row, ["oracle_text", "printed_text", "card_text", "rules_text", "description"]),
        rowValue(row, ["keywords", "abilities", "keyword"])
      ].join(" ");
      const features = extractStrategyFeatureMap(textBlob);
      const semantics = extractStrategySemantics(row);
      const quantity = readCardQuantityFromRow(row);

      if (!cardsByName.has(key)) {
        cardsByName.set(key, {
          key,
          name,
          row,
          quantity: quantity > 0 ? quantity : 1,
          features,
          semantics,
          colors: colorCodesForRow(row),
          scryfallId: rowValue(row, ["scryfall_id", "scry_fall_id"]).trim()
        });
        return;
      }

      const existing = cardsByName.get(key);
      existing.quantity += quantity > 0 ? quantity : 1;
      existing.features = mergeFeatureMaps(existing.features, features);
      existing.semantics = mergeStrategySemantics(existing.semantics, semantics);
      if (!existing.scryfallId) {
        existing.scryfallId = rowValue(row, ["scryfall_id", "scry_fall_id"]).trim();
      }
    });

    const cards = Array.from(cardsByName.values());
    applyStrategyIdf(cards);
    cards.sort((left, right) => left.name.localeCompare(right.name));

    return { cards };
  }

  function extractStrategyFeatureMap(textBlob) {
    const source = String(textBlob || "").toLowerCase();
    const featureMap = {};
    STRATEGY_FEATURE_PATTERNS.forEach((entry) => {
      const hits = source.match(entry.regex);
      if (!hits || hits.length === 0) {
        return;
      }
      featureMap[entry.id] = hits.length * entry.weight;
    });
    return featureMap;
  }

  function extractStrategySemantics(row) {
    const oracleText = rowValue(
      row,
      ["oracle_text", "printed_text", "card_text", "rules_text", "description"]
    );
    const keywordText = rowValue(row, ["keywords", "abilities", "keyword"]);
    const typeText = rowValue(row, ["type_line", "type"]);
    const source = `${oracleText} ${keywordText} ${typeText}`.toLowerCase();

    return {
      toxicOut: countPatternHits(source, /\btoxic\b|\binfect\b|combat damage .* poison counter/i),
      poisonOut: countPatternHits(source, /poison counter|gets? a poison counter/i),
      proliferateOut: countPatternHits(source, /\bproliferate\b/i),
      corruptedPayoff: countPatternHits(source, /\bcorrupted\b|if an opponent has three or more poison counters/i),
      deathtouchFlag: countPatternHits(source, /\bdeathtouch\b/i),
      combatEvasion: countPatternHits(source, /\bflying\b|\btrample\b|\bmenace\b|can't be blocked/i),
      biteFightRemoval: countPatternHits(source, /target creature you control deals damage|fight target/i),
      graveyardSetup: countPatternHits(source, /search your library .*graveyard|put .* from your library .*graveyard|\bmill\b|surveil|dredge|discard/i),
      reanimate: countPatternHits(source, /return target .*graveyard.*battlefield|return .* from your graveyard to the battlefield|\breanimate\b/i),
      castFromGraveyard: countPatternHits(source, /cast .* from your graveyard|flashback|escape|jump-start|unearth/i),
      copySpell: countPatternHits(source, /copy target spell|copy that spell|copy this spell|you may copy this spell/i),
      magecraftTrigger: countPatternHits(source, /magecraft|whenever you cast or copy an instant or sorcery spell|when you cast or copy/i),
      lifeDrainOut: countPatternHits(source, /each opponent loses|target opponent loses|opponents lose/i),
      lifeLossPayoff: countPatternHits(source, /whenever an opponent loses life|if an opponent lost life this turn/i),
      tokenOut: countPatternHits(source, /create .* token/i),
      sacOutlet: countPatternHits(source, /sacrifice (another )?(creature|artifact|permanent)/i),
      diesPayoff: countPatternHits(source, /whenever .* dies|when .* dies/i),
      etbPayoff: countPatternHits(source, /when .* enters the battlefield|whenever .* enters the battlefield/i),
      instantSorceryRef: countPatternHits(source, /instant or sorcery/i),
      discardOut: countPatternHits(source, /\bdiscard\b/i),
      discardPayoff: countPatternHits(source, /whenever .* discard|if .* discarded/i),
      worldgorgerLine: countPatternHits(source, /worldgorger dragon|exile all other permanents you control/i)
    };
  }

  function mergeStrategySemantics(leftMap, rightMap) {
    const out = { ...(leftMap || {}) };
    Object.keys(rightMap || {}).forEach((key) => {
      out[key] = (out[key] || 0) + (rightMap[key] || 0);
    });
    return out;
  }

  function countPatternHits(text, regex) {
    const source = String(text || "");
    if (!source) {
      return 0;
    }
    const flags = regex.flags.includes("g") ? regex.flags : `${regex.flags}g`;
    const globalRegex = new RegExp(regex.source, flags);
    const hits = source.match(globalRegex);
    return hits ? hits.length : 0;
  }

  function mergeFeatureMaps(leftMap, rightMap) {
    const out = { ...(leftMap || {}) };
    Object.keys(rightMap || {}).forEach((key) => {
      out[key] = (out[key] || 0) + (rightMap[key] || 0);
    });
    return out;
  }

  function applyStrategyIdf(cards) {
    const n = cards.length;
    if (!n) {
      return;
    }

    const featureDocFreq = {};
    cards.forEach((card) => {
      Object.keys(card.features || {}).forEach((featureKey) => {
        if ((card.features[featureKey] || 0) <= 0) {
          return;
        }
        featureDocFreq[featureKey] = (featureDocFreq[featureKey] || 0) + 1;
      });
    });

    const idf = {};
    Object.keys(featureDocFreq).forEach((key) => {
      idf[key] = Math.log((n + 1) / (featureDocFreq[key] + 1)) + 1;
    });

    cards.forEach((card) => {
      const weighted = {};
      Object.keys(card.features || {}).forEach((key) => {
        const value = card.features[key] || 0;
        if (value <= 0) {
          return;
        }
        weighted[key] = value * (idf[key] || 1);
      });
      card.features = weighted;
    });
  }

  function resolveSeedCard(rawSeedName, cards) {
    const normalizedSeed = normalizeStrategyName(rawSeedName);
    if (!normalizedSeed) {
      return null;
    }

    const exact = cards.find((card) => card.key === normalizedSeed);
    if (exact) {
      return exact;
    }

    const startsWith = cards.find((card) => card.key.startsWith(normalizedSeed));
    if (startsWith) {
      return startsWith;
    }

    return cards.find((card) => card.key.includes(normalizedSeed)) || null;
  }

  function computeDirectSynergies(seedCard, cards, limit) {
    const results = cards
      .filter((card) => card.key !== seedCard.key)
      .map((card) => {
        const sim = strategySimilarity(seedCard, card);
        return {
          card,
          score: sim.score,
          featureScore: sim.featureScore,
          ruleScore: sim.ruleScore,
          colorScore: sim.colorScore
        };
      })
      .filter((entry) => entry.score > 0.05 && (entry.ruleScore > 0.02 || entry.featureScore > 0.08))
      .sort((left, right) => {
        if (Math.abs(right.score - left.score) > 1e-9) {
          return right.score - left.score;
        }
        return left.card.name.localeCompare(right.card.name);
      });

    return results.slice(0, Math.max(1, limit));
  }

  function computeSynergyGroups(seedCard, directEntries, allCards, groupLimit) {
    const anchors = directEntries.slice(0, Math.min(18, directEntries.length));
    if (anchors.length < 2) {
      return [];
    }

    const groups = [];
    for (let i = 0; i < anchors.length; i += 1) {
      for (let j = i + 1; j < anchors.length; j += 1) {
        const left = anchors[i];
        const right = anchors[j];
        const pairLink = strategySimilarity(left.card, right.card);

        const packageCards = [seedCard, left.card, right.card];
        const support = findBestSupportCard(packageCards, allCards);
        if (support && support.score > 0.18) {
          packageCards.push(support.card);
        }
        const split = splitGroupCoreAndSide(seedCard, packageCards);

        const groupScore = left.score + right.score + pairLink.score * 0.7 + (support ? support.score * 0.35 : 0);
        groups.push({
          cards: packageCards,
          coreCards: split.coreCards,
          sideCards: split.sideCards,
          bridgeName: left.score >= right.score ? left.card.name : right.card.name,
          score: groupScore,
          lineA: `${seedCard.name} -> ${left.card.name} -> ${right.card.name}`,
          lineB: support ? `${seedCard.name} -> ${support.card.name} -> ${left.card.name}` : `${seedCard.name} -> ${right.card.name}`
        });
      }
    }

    groups.sort((a, b) => {
      if (Math.abs(b.score - a.score) > 1e-9) {
        return b.score - a.score;
      }
      return a.bridgeName.localeCompare(b.bridgeName);
    });

    const deduped = [];
    const seen = new Set();
    for (const group of groups) {
      const key = group.cards
        .map((card) => card.key)
        .sort()
        .join("|");
      if (seen.has(key)) {
        continue;
      }
      seen.add(key);
      deduped.push(group);
      if (deduped.length >= Math.max(1, groupLimit)) {
        break;
      }
    }

    return deduped;
  }

  function splitGroupCoreAndSide(seedCard, rawCards) {
    const orderedUnique = [];
    const seen = new Set();
    (Array.isArray(rawCards) ? rawCards : []).forEach((card) => {
      if (!card || !card.key || seen.has(card.key)) {
        return;
      }
      seen.add(card.key);
      orderedUnique.push(card);
    });

    const seed = orderedUnique.find((card) => card.key === seedCard.key) || seedCard;
    const others = orderedUnique.filter((card) => card.key !== seed.key);
    if (!others.length) {
      return { coreCards: [seed], sideCards: [] };
    }

    const ranked = others
      .map((card) => {
        const seedLink = strategySimilarity(seed, card);
        let bestPeerRule = 0;
        others.forEach((peer) => {
          if (peer.key === card.key) {
            return;
          }
          const peerLink = strategySimilarity(card, peer);
          if (peerLink.ruleScore > bestPeerRule) {
            bestPeerRule = peerLink.ruleScore;
          }
        });
        const rank = seedLink.ruleScore * 0.62 + seedLink.score * 0.28 + bestPeerRule * 0.10;
        return { card, rank, seedRule: seedLink.ruleScore, bestPeerRule };
      })
      .sort((a, b) => {
        if (Math.abs(b.rank - a.rank) > 1e-9) {
          return b.rank - a.rank;
        }
        return a.card.name.localeCompare(b.card.name);
      });

    const coreCards = [seed];
    coreCards.push(ranked[0].card);

    if (ranked.length > 1) {
      const second = ranked[1];
      if (second.rank >= 0.20 || second.seedRule >= 0.24 || second.bestPeerRule >= 0.24) {
        coreCards.push(second.card);
      }
    }

    const coreKeys = new Set(coreCards.map((card) => card.key));
    const sideCards = orderedUnique.filter((card) => !coreKeys.has(card.key));
    return { coreCards, sideCards };
  }

  function findBestSupportCard(packageCards, allCards) {
    const excluded = new Set(packageCards.map((card) => card.key));
    let best = null;

    allCards.forEach((candidate) => {
      if (excluded.has(candidate.key)) {
        return;
      }

      const links = packageCards.map((baseCard) => strategySimilarity(baseCard, candidate).score);
      const avg = links.reduce((sum, value) => sum + value, 0) / links.length;
      if (!best || avg > best.score) {
        best = { card: candidate, score: avg };
      }
    });

    return best;
  }

  function strategySimilarity(cardA, cardB) {
    const featureScore = cosineSimilaritySparse(cardA.features, cardB.features);
    const ruleScore = ruleAwareSynergyScore(cardA.semantics, cardB.semantics);
    const colorScore = colorCompatibilityScore(cardA.colors, cardB.colors);
    const score = clampScore(featureScore * 0.5 + ruleScore * 0.4 + colorScore * 0.1);
    return { score, featureScore, ruleScore, colorScore };
  }

  function ruleAwareSynergyScore(semA, semB) {
    const ab = directionalRuleSynergy(semA, semB);
    const ba = directionalRuleSynergy(semB, semA);
    const shared = sharedRuleSynergy(semA, semB);
    return clampScore(Math.max(ab, ba) * 0.82 + shared);
  }

  function directionalRuleSynergy(source, target) {
    const src = source || {};
    const dst = target || {};

    let score = 0;
    score += bounded(src.toxicOut + src.poisonOut) * bounded(dst.proliferateOut) * 0.90;
    score += bounded(src.proliferateOut) * bounded(dst.toxicOut + dst.poisonOut) * 0.55;
    score += bounded(src.combatEvasion) * bounded(dst.toxicOut + dst.poisonOut) * 0.35;
    score += bounded(src.toxicOut + src.poisonOut) * bounded(dst.corruptedPayoff) * 0.60;
    score += bounded(src.deathtouchFlag) * bounded(dst.biteFightRemoval) * 0.65;
    score += bounded(src.biteFightRemoval) * bounded(dst.deathtouchFlag) * 0.30;
    score += bounded(src.graveyardSetup) * bounded(dst.reanimate + dst.castFromGraveyard) * 0.75;
    score += bounded(src.copySpell) * bounded(dst.magecraftTrigger + dst.instantSorceryRef) * 1.10;
    score += bounded(src.magecraftTrigger) * bounded(dst.copySpell) * 0.65;
    score += bounded(src.lifeDrainOut) * bounded(dst.lifeLossPayoff) * 0.80;
    score += bounded(src.tokenOut) * bounded(dst.sacOutlet) * 0.55;
    score += bounded(src.sacOutlet) * bounded(dst.diesPayoff) * 0.55;
    score += bounded(src.reanimate) * bounded(dst.etbPayoff) * 0.45;
    score += bounded(src.discardOut) * bounded(dst.discardPayoff) * 0.55;
    score += bounded(src.worldgorgerLine) * bounded(dst.reanimate) * 0.90;

    return clampScore(score);
  }

  function sharedRuleSynergy(semA, semB) {
    const a = semA || {};
    const b = semB || {};

    const graveA = bounded((a.graveyardSetup || 0) + (a.reanimate || 0) + (a.castFromGraveyard || 0));
    const graveB = bounded((b.graveyardSetup || 0) + (b.reanimate || 0) + (b.castFromGraveyard || 0));
    const spellA = bounded((a.copySpell || 0) + (a.magecraftTrigger || 0) + (a.instantSorceryRef || 0));
    const spellB = bounded((b.copySpell || 0) + (b.magecraftTrigger || 0) + (b.instantSorceryRef || 0));
    const drainA = bounded((a.lifeDrainOut || 0) + (a.lifeLossPayoff || 0));
    const drainB = bounded((b.lifeDrainOut || 0) + (b.lifeLossPayoff || 0));
    const toxicA = bounded((a.toxicOut || 0) + (a.poisonOut || 0));
    const toxicB = bounded((b.toxicOut || 0) + (b.poisonOut || 0));
    const prolifA = bounded(a.proliferateOut || 0);
    const prolifB = bounded(b.proliferateOut || 0);
    const corruptedA = bounded(a.corruptedPayoff || 0);
    const corruptedB = bounded(b.corruptedPayoff || 0);
    const biteA = bounded((a.biteFightRemoval || 0) + (a.deathtouchFlag || 0));
    const biteB = bounded((b.biteFightRemoval || 0) + (b.deathtouchFlag || 0));

    const score = Math.min(graveA, graveB) * 0.25 +
      Math.min(spellA, spellB) * 0.18 +
      Math.min(drainA, drainB) * 0.10 +
      Math.min(toxicA, toxicB) * 0.28 +
      Math.min(prolifA, prolifB) * 0.24 +
      Math.min(corruptedA, corruptedB) * 0.14 +
      Math.min(biteA, biteB) * 0.10;

    return Math.min(0.55, score);
  }

  function bounded(value) {
    return value > 0 ? 1 : 0;
  }

  function clampScore(value) {
    return Math.min(1, Math.max(0, value));
  }

  function cosineSimilaritySparse(mapA, mapB) {
    const keysA = Object.keys(mapA || {});
    const keysB = Object.keys(mapB || {});
    if (!keysA.length || !keysB.length) {
      return 0;
    }

    let dot = 0;
    let normA = 0;
    let normB = 0;

    keysA.forEach((key) => {
      const value = mapA[key] || 0;
      normA += value * value;
      if (mapB[key]) {
        dot += value * mapB[key];
      }
    });
    keysB.forEach((key) => {
      const value = mapB[key] || 0;
      normB += value * value;
    });

    if (normA <= 0 || normB <= 0) {
      return 0;
    }
    return dot / (Math.sqrt(normA) * Math.sqrt(normB));
  }

  function colorCompatibilityScore(colorsA, colorsB) {
    const setA = new Set(Array.isArray(colorsA) ? colorsA : []);
    const setB = new Set(Array.isArray(colorsB) ? colorsB : []);
    if (setA.size === 0 || setB.size === 0) {
      return 0.25;
    }
    let intersection = 0;
    setA.forEach((code) => {
      if (setB.has(code)) {
        intersection += 1;
      }
    });
    if (intersection === 0) {
      return 0;
    }
    return intersection / Math.max(setA.size, setB.size);
  }

  function renderDirectSynergyCards(directEntries, seedName) {
    const target = nodes.strategy.directList;
    if (!target) {
      return;
    }
    if (!Array.isArray(directEntries) || directEntries.length === 0) {
      target.innerHTML = `<p class="muted">Aucune synergie directe calculee pour ${escapeHtml(seedName)}.</p>`;
      return;
    }

    target.innerHTML = "";
    const fragment = document.createDocumentFragment();
    directEntries.forEach((entry, index) => {
      fragment.appendChild(
        createStrategyCardElement(
          entry.card,
          `#${index + 1} | score ${formatDecimal(entry.score)} | rules ${formatDecimal(entry.ruleScore || 0)}`
        )
      );
    });
    target.appendChild(fragment);
  }

  function renderGroupCards(groups, seedName) {
    const target = nodes.strategy.groupList;
    if (!target) {
      return;
    }
    if (!Array.isArray(groups) || groups.length === 0) {
      target.innerHTML = `<p class="muted">Aucun groupe genere pour ${escapeHtml(seedName)}.</p>`;
      return;
    }

    target.innerHTML = "";
    const fragment = document.createDocumentFragment();

    groups.forEach((group, index) => {
      const article = document.createElement("article");
      article.className = "strategy-group";

      const title = document.createElement("p");
      title.className = "strategy-group-title";
      title.textContent = `Groupe ${index + 1} | score ${formatDecimal(group.score)}`;
      article.appendChild(title);

      const packageNames = group.cards.map((card) => card.name);
      const coreCards = Array.isArray(group.coreCards) && group.coreCards.length > 0
        ? group.coreCards
        : group.cards.slice(0, Math.min(2, group.cards.length));
      const coreKeySet = new Set(coreCards.map((card) => card.key));
      const sideCards = Array.isArray(group.sideCards)
        ? group.sideCards
        : group.cards.filter((card) => !coreKeySet.has(card.key));

      const packageLine = document.createElement("p");
      packageLine.className = "strategy-group-line";
      packageLine.innerHTML = `<strong>Package:</strong> ${escapeHtml(packageNames.join(" + "))}`;
      article.appendChild(packageLine);

      const coreLine = document.createElement("p");
      coreLine.className = "strategy-group-line";
      coreLine.innerHTML = `<strong>Core:</strong> ${escapeHtml(coreCards.map((card) => card.name).join(" + "))}`;
      article.appendChild(coreLine);

      if (sideCards.length > 0) {
        const sideLine = document.createElement("p");
        sideLine.className = "strategy-group-line";
        sideLine.innerHTML = `<strong>Side:</strong> ${escapeHtml(sideCards.map((card) => card.name).join(" + "))}`;
        article.appendChild(sideLine);
      }

      const chainALine = document.createElement("p");
      chainALine.className = "strategy-group-line";
      chainALine.innerHTML = `<strong>Chaine A:</strong> ${escapeHtml(group.lineA)}`;
      article.appendChild(chainALine);

      const chainBLine = document.createElement("p");
      chainBLine.className = "strategy-group-line";
      chainBLine.innerHTML = `<strong>Chaine B:</strong> ${escapeHtml(group.lineB)}`;
      article.appendChild(chainBLine);

      const coreSection = document.createElement("div");
      coreSection.className = "strategy-group-section is-core";
      const coreSectionTitle = document.createElement("p");
      coreSectionTitle.className = "strategy-group-section-title";
      coreSectionTitle.textContent = "Core cards";
      coreSection.appendChild(coreSectionTitle);
      const coreGrid = document.createElement("div");
      coreGrid.className = "strategy-group-cards is-core";
      coreCards.forEach((card) => {
        coreGrid.appendChild(createStrategyCardElement(card, "", { compact: true, badge: "CORE", badgeTone: "core" }));
      });
      coreSection.appendChild(coreGrid);
      article.appendChild(coreSection);

      if (sideCards.length > 0) {
        const sideSection = document.createElement("div");
        sideSection.className = "strategy-group-section is-side";
        const sideSectionTitle = document.createElement("p");
        sideSectionTitle.className = "strategy-group-section-title";
        sideSectionTitle.textContent = "Side cards";
        sideSection.appendChild(sideSectionTitle);
        const sideGrid = document.createElement("div");
        sideGrid.className = "strategy-group-cards is-side";
        sideCards.forEach((card) => {
          sideGrid.appendChild(createStrategyCardElement(card, "", { compact: true, badge: "SIDE", badgeTone: "side" }));
        });
        sideSection.appendChild(sideGrid);
        article.appendChild(sideSection);
      }

      const chips = document.createElement("div");
      chips.className = "strategy-chip-row";
      coreCards.forEach((card) => {
        const chip = document.createElement("span");
        chip.className = "strategy-chip is-core";
        chip.textContent = card.name;
        chips.appendChild(chip);
      });
      sideCards.forEach((card) => {
        const chip = document.createElement("span");
        chip.className = "strategy-chip is-side";
        chip.textContent = card.name;
        chips.appendChild(chip);
      });
      article.appendChild(chips);

      fragment.appendChild(article);
    });

    target.appendChild(fragment);
  }

  function createStrategyCardElement(card, metaLine, options = {}) {
    const compact = Boolean(options.compact);
    const badge = String(options.badge || "").trim();
    const badgeTone = String(options.badgeTone || "core").toLowerCase();
    const cardNode = document.createElement("article");
    cardNode.className = compact ? "strategy-card is-compact" : "strategy-card";

    const scryfallId = card.scryfallId || "";
    const imageUrl = scryfallId
      ? `https://api.scryfall.com/cards/${encodeURIComponent(scryfallId)}?format=image&version=normal`
      : "";
    const setCode = rowValue(card.row, ["set_code", "set"]).toUpperCase();
    const collector = rowValue(card.row, ["collector_number"]);
    const setLine = [setCode, collector ? `#${collector}` : ""].filter(Boolean).join(" ");
    const manaCost = rowValue(card.row, ["mana_cost", "manacost", "mana"]);

    const art = document.createElement("div");
    art.className = "strategy-card-art";
    if (imageUrl) {
      const img = document.createElement("img");
      img.src = imageUrl;
      img.alt = card.name;
      img.loading = "lazy";
      art.appendChild(img);
    } else {
      const fallback = document.createElement("span");
      fallback.className = "strategy-card-fallback";
      fallback.textContent = card.name;
      art.appendChild(fallback);
    }
    cardNode.appendChild(art);

    const body = document.createElement("div");
    body.className = "strategy-card-body";

    const nameLine = document.createElement("p");
    nameLine.className = "strategy-card-name";
    nameLine.textContent = card.name;
    body.appendChild(nameLine);

    if (badge) {
      const badgeNode = document.createElement("span");
      badgeNode.className = `strategy-card-badge ${badgeTone === "side" ? "is-side" : "is-core"}`;
      badgeNode.textContent = badge;
      body.appendChild(badgeNode);
    }

    if (metaLine) {
      const rankingLine = document.createElement("p");
      rankingLine.className = "strategy-card-meta";
      rankingLine.textContent = metaLine;
      body.appendChild(rankingLine);
    }

    const setMetaLine = document.createElement("p");
    setMetaLine.className = "strategy-card-meta";
    setMetaLine.textContent = setLine || "No set info";
    body.appendChild(setMetaLine);

    const manaLine = document.createElement("p");
    manaLine.className = "strategy-card-mana";
    renderStrategyManaLine(manaLine, manaCost);
    body.appendChild(manaLine);

    cardNode.appendChild(body);

    if (card?.row && typeof card.row === "object") {
      cardNode.classList.add("is-interactive", "data-row");
      bindRowPreviewEvents(cardNode, card.row);
    }

    return cardNode;
  }

  function renderStrategyManaLine(target, manaCostText) {
    if (!target) {
      return;
    }
    target.innerHTML = "";
    const rawText = String(manaCostText || "").trim();
    if (!rawText) {
      target.textContent = "No mana info";
      target.classList.add("is-empty");
      return;
    }
    target.classList.remove("is-empty");
    renderManaCostCell(target, rawText);
    if (!target.childNodes.length && !String(target.textContent || "").trim()) {
      target.textContent = rawText;
    }
  }

  function normalizeStrategyName(value) {
    return String(value || "")
      .toLowerCase()
      .trim()
      .replace(/[^a-z0-9]+/g, " ")
      .replace(/\s+/g, " ")
      .trim();
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
      <div class="deck-side-tabs" role="tablist" aria-label="Deck panel tabs">
        <button type="button" class="deck-side-tab is-active" data-deck-pane-tab="stats" role="tab" aria-selected="true">Stats</button>
        <button type="button" class="deck-side-tab" data-deck-pane-tab="analysis" role="tab" aria-selected="false">Analyse</button>
      </div>

      <section class="deck-side-pane is-active" data-deck-pane="stats">
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
      </section>

      <section class="deck-side-pane" data-deck-pane="analysis">
        <section class="deck-visual-section deck-analysis-section">
          <div class="deck-analysis-head">
            <h4 class="deck-visual-title">Deck Analysis</h4>
            <button type="button" id="deck-analyze-btn" class="deck-analyze-btn" data-action="analyze-deck">Analyser</button>
          </div>
          <p id="deck-analysis-status" class="deck-stats-note muted">Choisis une collection puis clique sur Analyser.</p>
          <div id="deck-analysis-mechanics" class="deck-mechanic-chips"></div>
          <div class="deck-analysis-grid">
            <section class="deck-analysis-block">
              <p class="deck-analysis-title">Ameliorer</p>
              <div id="deck-analysis-upgrade" class="strategy-card-grid deck-analysis-card-grid">
                <p class="muted">Clique sur Analyser pour proposer des cartes d amelioration.</p>
              </div>
            </section>
            <section class="deck-analysis-block">
              <p class="deck-analysis-title">Varier</p>
              <div id="deck-analysis-variation" class="strategy-card-grid deck-analysis-card-grid">
                <p class="muted">Clique sur Analyser pour proposer des cartes de variation.</p>
              </div>
            </section>
          </div>
        </section>
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

      const explicitName = cleanDeckCardName(rowValue(row, ["name", "card_name", "card", "title"]));
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
      const fallbackName = cleanDeckCardName(withoutPrefix);
      if (!fallbackName) {
        return { ignore: true };
      }
      return {
        quantity: 1,
        name: fallbackName
      };
    }

    const qty = Number.parseInt(withQty[1], 10);
    const name = cleanDeckCardName(withQty[2]);

    if (!name || !Number.isFinite(qty) || qty <= 0) {
      return { ignore: true };
    }

    return {
      quantity: qty,
      name
    };
  }

  function cleanDeckCardName(rawName) {
    let name = String(rawName || "").trim();
    if (!name) {
      return "";
    }

    // Remove trailing collector / set chunks often present in exported decklists.
    // Examples:
    // "Card Name (MOM) 123", "Card Name (PLST) C18-238", "Card Name [SET]"
    name = name
      .replace(/\s+\([^)]+\)\s+[A-Za-z0-9-]+(?:\s*\*?[A-Za-z0-9]+)?\s*$/u, "")
      .replace(/\s+\[[^\]]+\]\s*$/u, "")
      .replace(/\s+\*\w+\s*$/u, "")
      .trim();

    return name;
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
      if (!rowValue(mergedRow, ["oracle_text", "printed_text", "card_text", "rules_text"]) && metadata.oracle_text) {
        mergedRow.oracle_text = metadata.oracle_text;
      }
      if (!rowValue(mergedRow, ["keywords", "abilities", "keyword"]) && metadata.keywords.length > 0) {
        mergedRow.keywords = metadata.keywords.join(", ");
      }
      if (!rowValue(mergedRow, ["scryfall_id", "scry_fall_id"]) && metadata.scryfall_id) {
        mergedRow.scryfall_id = metadata.scryfall_id;
      }
      if (!rowValue(mergedRow, ["set_code", "set"]) && metadata.set_code) {
        mergedRow.set_code = metadata.set_code;
      }
      if (!rowValue(mergedRow, ["collector_number"]) && metadata.collector_number) {
        mergedRow.collector_number = metadata.collector_number;
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
      colors: Array.isArray(card.colors) ? card.colors : [],
      oracle_text: String(card.oracle_text || "").trim(),
      keywords: Array.isArray(card.keywords) ? card.keywords.map((item) => String(item || "").trim()).filter(Boolean) : [],
      scryfall_id: String(card.id || "").trim(),
      set_code: String(card.set || "").trim(),
      collector_number: String(card.collector_number || "").trim()
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
      if (Array.isArray(row)) {
        if (row.length === 1) {
          return { line: asText(row[0]) };
        }
        const out = {};
        row.forEach((value, index) => {
          out[`col_${index + 1}`] = value;
        });
        return out;
      }
      if (row == null) {
        return {};
      }
      return { line: asText(row) };
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

  function clampInt(value, min, max, fallback) {
    const parsed = Number.parseInt(String(value ?? ""), 10);
    if (!Number.isFinite(parsed)) {
      return fallback;
    }
    return Math.min(max, Math.max(min, parsed));
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
    bindStrategyControls();
    bindDeckAnalysisControls();
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
