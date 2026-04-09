import {
  uploadCollection,
  loadCollectionFromDb,
  importCollectionCsv,
  importIntoCollectionDb,
  addCardToCollectionDb,
  deleteCardFromCollectionDb,
  listStoredCollections,
  getStoredCollection,
  deleteStoredCollection,
  fetchSpellbookVariants
} from "./api.js";
import {
  renderCollection,
  getCollectionLanguage,
  setCollectionLanguage,
  bindRowPreviewEvents,
  renderManaCostCell
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
    },
    spellbook: {
      title: "Spellbook",
      subtitle: "Interroger Commander Spellbook par nom de carte."
    }
  };

  const state = {
    activeTab: "collections",
    collections: [],
    collectionPayloadById: {},
    selectedCollectionId: null,
    dbCollectionPayload: null,
    decks: [],
    selectedDeckId: null,
    strategy: {
      seedName: "",
      directLimit: 12,
      groupLimit: 6,
      manaFilter: {
        W: false,
        U: false,
        B: false,
        R: false,
        G: false,
        C: false
      },
      modelCache: new Map(),
      lastCollectionId: null,
      includeKnownCards: false,
      includeSpellbookCombos: false,
      knownCardsModel: null,
      knownCardsModelKey: "",
      knownCardsModelPromise: null,
      knownCardsModelPromiseKey: "",
      knownCardsError: "",
      spellbookCache: new Map(),
      spellbookPromiseCache: new Map(),
      spellbookError: "",
      runToken: 0
    },
    spellbook: {
      cardName: "",
      limit: 20,
      loading: false,
      error: "",
      payload: null,
      runToken: 0
    }
  };

  const DECK_STORAGE_KEY = "mtgcodex_ui_decks_v1";
  const MAX_STORED_DECKS = 24;
  const COLLECTION_SOURCE_PREF_KEY = "mtgcodex_ui_collection_source_pref_v1";
  const COLLECTION_SELECTED_ID_KEY = "mtgcodex_ui_collection_selected_id_v1";
  const COLLECTION_DB_SOURCES_KEY = "mtgcodex_ui_collection_db_sources_v1";
  const DECK_STATS_STATE = {
    requestToken: 0,
    metadataCache: new Map()
  };
  const DECK_ANALYSIS_STATE = {
    requestToken: 0,
    activePane: "stats"
  };
  const ADD_CARD_MODAL_STATE = {
    root: null,
    nameInput: null,
    qtyInput: null,
    finishSelect: null,
    suggestionsWrap: null,
    printsWrap: null,
    statusNode: null,
    addButton: null,
    importButton: null,
    cancelButton: null,
    closeButton: null,
    suggestions: [],
    selectedPrintId: "",
    printsById: new Map(),
    autocompleteTimer: null,
    autocompleteSeq: 0,
    printsSeq: 0
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
      includeKnownInput: document.getElementById("strategy-include-known"),
      includeSpellbookInput: document.getElementById("strategy-include-spellbook"),
      manaFilterInputs: Array.from(document.querySelectorAll("input[data-strategy-mana]")),
      runButton: document.getElementById("strategy-run-btn"),
      status: document.getElementById("strategy-status"),
      directList: document.getElementById("strategy-direct-list"),
      groupList: document.getElementById("strategy-group-list")
    },
    spellbook: {
      form: document.getElementById("spellbook-form"),
      cardInput: document.getElementById("spellbook-card-input"),
      limitInput: document.getElementById("spellbook-limit-input"),
      runButton: document.getElementById("spellbook-run-btn"),
      status: document.getElementById("spellbook-status"),
      results: document.getElementById("spellbook-results")
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
  const STRATEGY_FEATURE_SCRYFALL_QUERY = {
    graveyard: "(oracle:graveyard OR oracle:mill OR oracle:dredge OR oracle:surveil)",
    reanimate: "(oracle:\"from your graveyard to the battlefield\" OR oracle:reanimate OR oracle:unearth)",
    entomb_line: "(oracle:\"search your library\" oracle:graveyard)",
    poison_toxic: "(oracle:toxic OR oracle:infect OR oracle:\"poison counter\" OR oracle:corrupted)",
    proliferate: "oracle:proliferate",
    discard: "(oracle:discard OR oracle:connive OR oracle:loot)",
    draw: "oracle:\"draw a card\"",
    sacrifice: "oracle:sacrifice",
    deathtouch: "keyword:deathtouch",
    combat_evasion: "(keyword:flying OR keyword:trample OR keyword:menace OR oracle:\"can't be blocked\")",
    fight_bite: "(oracle:fight OR oracle:\"deals damage equal to\")",
    etb: "oracle:\"enters the battlefield\"",
    token: "oracle:token",
    removal: "(oracle:\"destroy target\" OR oracle:\"exile target\" OR oracle:\"counter target\")",
    tutor: "oracle:\"search your library\"",
    recursion: "(oracle:flashback OR oracle:escape OR oracle:\"from your graveyard to your hand\")",
    combo_copy: "(oracle:\"copy target spell\" OR oracle:magecraft OR oracle:\"cast or copy\")",
    combo_lifeloss: "(oracle:\"each opponent loses\" OR oracle:\"target opponent loses\")",
    combo_worldgorger: "(oracle:\"Worldgorger Dragon\" OR oracle:\"exile all other permanents you control\")",
    combo_chain_smog: "(oracle:\"discard two cards\" OR oracle:\"you may copy this spell\")"
  };
  const STRATEGY_SEED_QUERY_OVERRIDES = {
    grindstone: [
      "(name:\"Painter's Servant\" OR (oracle:\"choose a color\" oracle:\"chosen color\"))",
      "(oracle:\"untap target artifact\" OR oracle:\"untap all artifacts\")",
      "(oracle:\"puts the top\" oracle:\"library\" oracle:\"graveyard\" OR oracle:\"mill\")"
    ]
  };
  const STRATEGY_KNOWN_COMBO_PAIRS = [
    { a: "grindstone", b: "painter s servant", boost: 0.95 },
    { a: "entomb", b: "reanimate", boost: 0.65 },
    { a: "entomb", b: "animate dead", boost: 0.62 },
    { a: "entomb", b: "dance of the dead", boost: 0.60 },
    { a: "chain of smog", b: "witherbloom apprentice", boost: 0.92 }
  ];

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
    resetStrategyKnownCardsCache();
    if (state.activeTab === "collections" && state.selectedCollectionId) {
      loadStoredCollectionIntoTable(state.selectedCollectionId);
    }
    if (state.activeTab === "strategy") {
      const collectionId = state.selectedCollectionId;
      const payload = collectionId ? state.collectionPayloadById[collectionId] : null;
      const meta = state.collections.find((entry) => entry.id === collectionId);
      renderStrategyPanel(payload, meta);
    }
  }

  function bindCollectionPicker() {
    nodes.collections.fileInput.accept = ".csv,.txt,.db,.sqlite,.sqlite3";
    const defaultPickLabel = "Choisir fichier collection";
    setCollectionPickButtonLabel(defaultPickLabel);
    nodes.collections.pickFileButton.classList.remove("has-file");
    nodes.collections.pickFileButton.addEventListener("click", () => {
      nodes.collections.fileInput.click();
    });
    nodes.collections.fileInput.addEventListener("change", () => {
      const selected = nodes.collections.fileInput.files && nodes.collections.fileInput.files[0];
      setCollectionPickButtonLabel(selected ? `Collection: ${selected.name}` : defaultPickLabel);
      nodes.collections.pickFileButton.classList.toggle("has-file", Boolean(selected));
      if (!selected) {
        return;
      }
      if (nodes.collections.form && typeof nodes.collections.form.requestSubmit === "function") {
        nodes.collections.form.requestSubmit();
      } else if (nodes.collections.form) {
        nodes.collections.form.dispatchEvent(new Event("submit", { cancelable: true }));
      }
    });
  }

  function setCollectionPickButtonLabel(label) {
    const button = nodes.collections.pickFileButton;
    if (!button) {
      return;
    }
    const text = String(label || "Choisir fichier collection");
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
      if (!selected) {
        return;
      }
      if (nodes.decks.form && typeof nodes.decks.form.requestSubmit === "function") {
        nodes.decks.form.requestSubmit();
      } else if (nodes.decks.form) {
        nodes.decks.form.dispatchEvent(new Event("submit", { cancelable: true }));
      }
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

    if (strategyNodes.includeKnownInput) {
      strategyNodes.includeKnownInput.checked = isStrategyIncludeKnownEnabled();
      strategyNodes.includeKnownInput.addEventListener("change", () => {
        state.strategy.includeKnownCards = strategyNodes.includeKnownInput.checked === true;
        resetStrategyKnownCardsCache();
        const collectionId = state.selectedCollectionId;
        const payload = collectionId ? state.collectionPayloadById[collectionId] : null;
        const meta = state.collections.find((entry) => entry.id === collectionId);
        renderStrategyPanel(payload, meta);
      });
    }
    if (strategyNodes.includeSpellbookInput) {
      strategyNodes.includeSpellbookInput.checked = isStrategyIncludeSpellbookEnabled();
      strategyNodes.includeSpellbookInput.addEventListener("change", () => {
        state.strategy.includeSpellbookCombos = strategyNodes.includeSpellbookInput.checked === true;
        resetStrategySpellbookCache();
        const collectionId = state.selectedCollectionId;
        const payload = collectionId ? state.collectionPayloadById[collectionId] : null;
        const meta = state.collections.find((entry) => entry.id === collectionId);
        renderStrategyPanel(payload, meta);
      });
    }

    if (Array.isArray(strategyNodes.manaFilterInputs) && strategyNodes.manaFilterInputs.length > 0) {
      strategyNodes.manaFilterInputs.forEach((inputNode) => {
        const code = String(inputNode?.dataset?.strategyMana || "").toUpperCase();
        if (!"WUBRGC".includes(code)) {
          return;
        }
        inputNode.checked = state.strategy.manaFilter[code] === true;
        inputNode.addEventListener("change", () => {
          state.strategy.manaFilter[code] = inputNode.checked === true;
        });
      });
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

  function bindSpellbookControls() {
    const spellbookNodes = nodes.spellbook;
    if (!spellbookNodes.form || !spellbookNodes.cardInput || !spellbookNodes.status || !spellbookNodes.results) {
      return;
    }

    const safeLimit = clampInt(spellbookNodes.limitInput?.value, 1, 100, state.spellbook.limit);
    state.spellbook.limit = safeLimit;
    if (spellbookNodes.limitInput) {
      spellbookNodes.limitInput.value = String(safeLimit);
    }

    spellbookNodes.cardInput.addEventListener("input", () => {
      state.spellbook.cardName = String(spellbookNodes.cardInput.value || "").trim();
    });

    spellbookNodes.limitInput?.addEventListener("change", () => {
      const value = clampInt(spellbookNodes.limitInput.value, 1, 100, state.spellbook.limit);
      state.spellbook.limit = value;
      spellbookNodes.limitInput.value = String(value);
    });

    spellbookNodes.form.addEventListener("submit", (event) => {
      event.preventDefault();
      runSpellbookLookup();
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

  function inferDeckNameFromFile(fileName) {
    const rawName = String(fileName || "").trim();
    if (!rawName) {
      return "";
    }
    const normalized = rawName.replace(/\\/g, "/");
    const baseName = normalized.includes("/") ? normalized.split("/").pop() : normalized;
    const withoutExt = String(baseName || "").replace(/\.[^./\\]+$/, "").trim();
    if (!withoutExt) {
      return "";
    }
    return withoutExt.replace(/[_-]+/g, " ").replace(/\s+/g, " ").trim();
  }

  function inferCollectionSourceType(fileName) {
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
    const savedId = getSavedSelectedCollectionId();
    const savedExists = savedId && state.collections.some((entry) => entry.id === savedId);
    if (savedExists) {
      state.selectedCollectionId = savedId;
    } else if (!state.collections.some((entry) => entry.id === state.selectedCollectionId)) {
      state.selectedCollectionId = state.collections[0]?.id || null;
    }
    setSavedSelectedCollectionId(state.selectedCollectionId);
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

    const dbEntries = buildDbCollectionListEntries();
    if (state.collections.length === 0 && dbEntries.length === 0) {
      list.innerHTML = '<p class="muted">Aucun dossier collection pour le moment.</p>';
      return;
    }

    const storeMarkup = state.collections.map((entry) => {
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

    const dbMarkup = dbEntries.map((entry) => {
      const deleteButton = entry.canDelete
        ? '<button type="button" class="entity-delete" data-action="delete">Supprimer</button>'
        : "";
      const activeClass = entry.active ? "is-active" : "";
      return `
        <article class="entity-item ${activeClass}" data-entity-kind="db" data-entity-id="${escapeHtml(entry.id)}" data-db-path="${escapeHtml(entry.path)}">
          <div>
            <p class="entity-item-name">${escapeHtml(entry.title)}</p>
            <p class="entity-item-meta">${escapeHtml(entry.meta)}</p>
          </div>
          <div class="entity-actions">
            <button type="button" class="entity-select" data-action="select">Ouvrir</button>
            ${deleteButton}
          </div>
        </article>
      `;
    }).join("");

    list.innerHTML = `${dbMarkup}${storeMarkup}`;
  }

  function buildDbCollectionListEntries() {
    const pref = getCollectionSourcePreference();
    const configuredPath = getConfiguredCollectionDbPath();
    const payloadPath = String(state.dbCollectionPayload?.path || "").trim();
    const activePath = payloadPath || configuredPath;

    const mergedPaths = [];
    if (activePath) {
      mergedPaths.push(activePath);
    }
    getSavedDbSources().forEach((savedPath) => {
      mergedPaths.push(savedPath);
    });

    const uniquePaths = [];
    mergedPaths.forEach((candidate) => {
      const pathValue = String(candidate || "").trim();
      if (!pathValue) {
        return;
      }
      if (!uniquePaths.some((knownPath) => dbPathEquals(knownPath, pathValue))) {
        uniquePaths.push(pathValue);
      }
    });

    if (uniquePaths.length === 0 && pref !== "db") {
      return [];
    }

    if (uniquePaths.length === 0 && pref === "db") {
      return [{
        id: "__db_default__",
        path: "",
        title: "DB active: mtg.db",
        meta: `${String(state.dbCollectionPayload?.row_count ?? "-")} lignes | chemin par defaut serveur`,
        active: true,
        canDelete: false
      }];
    }

    return uniquePaths.map((pathValue, index) => {
      const fileName = String(pathValue).split(/[\\/]/).pop() || `db-${index + 1}`;
      const isActive = pref === "db" && dbPathEquals(activePath, pathValue);
      const rowCount = isActive ? (state.dbCollectionPayload?.row_count ?? "-") : "-";
      return {
        id: `__db_${index + 1}`,
        path: pathValue,
        title: `DB: ${fileName}`,
        meta: `${String(rowCount)} lignes | ${pathValue}`,
        active: isActive,
        canDelete: true
      };
    });
  }

  function dbPathEquals(leftPath, rightPath) {
    return String(leftPath || "").trim().toLowerCase() === String(rightPath || "").trim().toLowerCase();
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
      const sourceType = String(entry.payload?.source_type || "").toLowerCase();
      const sourceLabel = sourceType === "db"
        ? "DB"
        : (sourceType === "csv" ? "CSV" : "TXT");
      return `
        <article class="deck-entry-item ${activeClass}" data-entity-id="${deckId}">
          <button type="button" class="deck-entry-open" data-action="select" aria-label="Ouvrir ${deckName}" title="Ouvrir ${deckName}">
            <span class="deck-entry-glyph" aria-hidden="true">${glyph}</span>
            <span class="deck-entry-main">
              <span class="deck-entry-name">${deckName}</span>
              <span class="deck-entry-meta">${escapeHtml(String(rowCount))} lignes</span>
            </span>
            <span class="deck-entry-source">${sourceLabel}</span>
          </button>
          <button type="button" class="deck-entry-delete" data-action="delete" aria-label="Supprimer ${deckName}" title="Supprimer ${deckName}">
            <svg viewBox="0 0 24 24" class="deck-entry-delete-svg" aria-hidden="true">
              <path d="M6 7h12"></path>
              <path d="M9 7V5h6v2"></path>
              <path d="M8 7l1 12h6l1-12"></path>
            </svg>
          </button>
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

  function setWorkspaceLowerHidden(hidden) {
    const lower = nodes.workspaceLower;
    if (!lower) {
      return;
    }
    lower.classList.toggle("is-hidden", hidden === true);
  }

  function renderActiveTabTable() {
    if (state.activeTab === "collections") {
      setWorkspaceLowerHidden(false);
      if (getCollectionSourcePreference() === "db") {
        if (state.dbCollectionPayload && state.dbCollectionPayload.ok === true) {
          renderCollection(state.dbCollectionPayload);
        } else {
          void loadDefaultDbCollectionIntoTable();
        }
        renderDeckStatsPanel(null);
        return;
      }
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
      setWorkspaceLowerHidden(false);
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
      setWorkspaceLowerHidden(false);
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

    if (state.activeTab === "spellbook") {
      setWorkspaceLowerHidden(true);
      renderDeckStatsPanel(null);
      renderSpellbookPanel();
      return;
    }

    setWorkspaceLowerHidden(false);
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
    const includeKnown = isStrategyIncludeKnownEnabled();
    if (includeKnown) {
      const knownCount = Array.isArray(state.strategy.knownCardsModel?.cards)
        ? state.strategy.knownCardsModel.cards.length
        : 0;
      if (knownCount > 0) {
        strategyNodes.sourceMeta.textContent = `${collectionName} | ${model.cards.length} cartes collection + ${knownCount} cartes via Scryfall (seed libre)`;
      } else if (state.strategy.knownCardsError) {
        strategyNodes.sourceMeta.textContent = `${collectionName} | ${model.cards.length} cartes collection (Scryfall indisponible)`;
      } else {
        strategyNodes.sourceMeta.textContent = `${collectionName} | ${model.cards.length} cartes collection (+ seed/cartes via Scryfall au calcul)`;
      }
    } else {
      strategyNodes.sourceMeta.textContent = `${collectionName} | ${model.cards.length} cartes analysees`;
    }
    if (isStrategyIncludeSpellbookEnabled()) {
      const spellbookHint = state.strategy.spellbookError
        ? " | Spellbook indisponible"
        : " | + reference combos Commander Spellbook";
      strategyNodes.sourceMeta.textContent += spellbookHint;
    }

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

  function renderSpellbookPanel() {
    const spellbookNodes = nodes.spellbook;
    if (!spellbookNodes.cardInput || !spellbookNodes.status || !spellbookNodes.results) {
      return;
    }

    spellbookNodes.cardInput.value = state.spellbook.cardName || "";
    if (spellbookNodes.limitInput) {
      spellbookNodes.limitInput.value = String(clampInt(state.spellbook.limit, 1, 100, 20));
    }

    if (state.spellbook.loading) {
      spellbookNodes.status.textContent = `Recherche Spellbook en cours pour "${state.spellbook.cardName}"...`;
      return;
    }

    if (state.spellbook.error) {
      spellbookNodes.status.textContent = `Erreur: ${state.spellbook.error}`;
      return;
    }

    const variants = Array.isArray(state.spellbook.payload?.results) ? state.spellbook.payload.results : [];
    if (!state.spellbook.cardName) {
      spellbookNodes.status.textContent = "Saisis une carte pour interroger Commander Spellbook.";
      spellbookNodes.results.innerHTML = '<p class="muted">Aucun resultat.</p>';
      return;
    }

    spellbookNodes.status.textContent = `${variants.length} variant(s) retournee(s) pour "${state.spellbook.cardName}".`;
    spellbookNodes.results.innerHTML = renderSpellbookVariants(variants);
  }

  async function runSpellbookLookup() {
    const spellbookNodes = nodes.spellbook;
    if (!spellbookNodes.cardInput || !spellbookNodes.status || !spellbookNodes.results) {
      return;
    }

    const cardName = String(spellbookNodes.cardInput.value || "").trim();
    const limitValue = clampInt(spellbookNodes.limitInput?.value, 1, 100, state.spellbook.limit);
    state.spellbook.cardName = cardName;
    state.spellbook.limit = limitValue;

    if (spellbookNodes.limitInput) {
      spellbookNodes.limitInput.value = String(limitValue);
    }

    if (!cardName) {
      state.spellbook.error = "";
      state.spellbook.payload = null;
      spellbookNodes.status.textContent = "Saisis un nom de carte.";
      spellbookNodes.results.innerHTML = '<p class="muted">Aucun resultat.</p>';
      return;
    }

    const runToken = ++state.spellbook.runToken;
    state.spellbook.loading = true;
    state.spellbook.error = "";
    spellbookNodes.status.textContent = `Recherche Spellbook en cours pour "${cardName}"...`;
    spellbookNodes.results.innerHTML = '<p class="muted">Chargement...</p>';

    try {
      const payload = await fetchSpellbookVariants(cardName, limitValue);
      if (runToken !== state.spellbook.runToken) {
        return;
      }

      if (!payload || payload.ok !== true) {
        state.spellbook.payload = null;
        state.spellbook.error = String(payload?.error || "Spellbook indisponible");
        spellbookNodes.status.textContent = `Erreur: ${state.spellbook.error}`;
        spellbookNodes.results.innerHTML = '<p class="muted">Aucun resultat.</p>';
        return;
      }

      state.spellbook.payload = payload;
      state.spellbook.error = "";
      const variants = Array.isArray(payload.results) ? payload.results : [];
      spellbookNodes.status.textContent = `${variants.length} variant(s) retournee(s) pour "${cardName}".`;
      spellbookNodes.results.innerHTML = renderSpellbookVariants(variants);
    } catch (error) {
      if (runToken !== state.spellbook.runToken) {
        return;
      }
      state.spellbook.payload = null;
      state.spellbook.error = String(error?.message || error || "Spellbook indisponible");
      spellbookNodes.status.textContent = `Erreur: ${state.spellbook.error}`;
      spellbookNodes.results.innerHTML = '<p class="muted">Aucun resultat.</p>';
    } finally {
      if (runToken === state.spellbook.runToken) {
        state.spellbook.loading = false;
      }
    }
  }

  function renderSpellbookVariants(variants) {
    const safeVariants = Array.isArray(variants) ? variants : [];
    if (safeVariants.length === 0) {
      return '<p class="muted">Aucun combo trouve.</p>';
    }

    return safeVariants.map((variant, index) => {
      const status = String(variant?.status || "").trim() || "UNKNOWN";
      const variantId = String(variant?.id || "").trim() || String(index + 1);
      const statusClass = status === "OK" ? "is-ok" : "is-other";
      const popularity = Number(variant?.popularity);
      const popularityText = Number.isFinite(popularity) ? popularity.toLocaleString("fr-FR") : "-";
      const cards = spellbookEntryNames(variant?.uses, ["card", "name"]);
      const requires = spellbookEntryNames(variant?.requires, ["feature", "name"]);
      const produces = spellbookEntryNames(variant?.produces, ["feature", "name"]);
      const description = spellbookNormalizeText(spellbookDescription(variant));
      const steps = spellbookStepList(description);
      const explicitText = spellbookExplicitText(cards, requires, produces, description);
      const stepsMarkup = spellbookActionTreeMarkup(cards, steps);
      const cardsMarkup = spellbookCardRibbonMarkup(cards);
      const detailMarkup = spellbookDetailsMarkup(steps, description);

      return `
        <article class="spellbook-variant-card">
          <div class="spellbook-variant-head">
            <h4>Variant ${escapeHtml(String(index + 1))}</h4>
            <div class="spellbook-head-badges">
              <span class="spellbook-head-badge ${statusClass}">${escapeHtml(status)}</span>
              <span class="spellbook-head-badge">Popularite ${escapeHtml(popularityText)}</span>
              <span class="spellbook-head-badge">ID ${escapeHtml(variantId)}</span>
            </div>
          </div>
          <div class="spellbook-variant-content">
            <section class="spellbook-summary-row">
              <p class="spellbook-column-title">Resume rapide</p>
              <p class="spellbook-explicit-text">${escapeHtml(explicitText)}</p>
            </section>
            <section class="spellbook-card-ribbon-wrap">
              <p class="spellbook-column-title">Cartes du combo</p>
              ${cardsMarkup}
            </section>
            <section class="spellbook-action-block">
              <p class="spellbook-column-title">Arbre d'actions</p>
              ${stepsMarkup}
            </section>
            ${detailMarkup}
          </div>
        </article>
      `;
    }).join("");
  }

  function spellbookExplicitText(cards, requires, produces, description) {
    const cardPart = cards.length > 0
      ? `${cards.length} cartes, moteur centre sur ${cards[0]}.`
      : "Nombre de cartes non precise.";
    const requiresPart = requires.length > 0
      ? `Prerequis: ${requires[0]}${requires.length > 1 ? " +" : ""}.`
      : "Sans prerequis explicite.";
    const producesPart = produces.length > 0
      ? `Sortie principale: ${produces[0]}${produces.length > 1 ? " +" : ""}.`
      : "Sortie non detaillee.";
    return [cardPart, requiresPart, producesPart].join(" ");
  }

  function spellbookNormalizeText(value) {
    return String(value || "").replace(/\s+/g, " ").trim();
  }

  function spellbookStepList(value) {
    const text = spellbookNormalizeText(value);
    if (!text) {
      return [];
    }

    const seed = text
      .replace(/\b(?:conditions?|resultats?|results?|details?|description)\s*:/gi, ". ")
      .replace(/\s*[|]\s*/g, ". ");

    const candidates = seed
      .split(/(?<=[.!?])\s+|\s*;\s+/g)
      .map((step) => step.replace(/^\d+[\).\-\s]*/, "").trim())
      .map((step) => step.replace(/\s+/g, " "))
      .filter((step) => step.length >= 14);

    const seen = new Set();
    const deduped = [];
    candidates.forEach((step) => {
      const key = normalizeStrategyName(step).replace(/[^a-z0-9]+/g, " ").trim();
      if (!key || key.length < 12) {
        return;
      }
      if (seen.has(key)) {
        return;
      }
      seen.add(key);
      deduped.push(step);
    });

    return deduped.slice(0, 16);
  }

  function spellbookCardRibbonMarkup(cards) {
    const safeCards = Array.isArray(cards)
      ? cards.map((item) => String(item || "").trim()).filter(Boolean)
      : [];
    if (safeCards.length === 0) {
      return '<p class="muted">Cartes non precisees.</p>';
    }

    const maxCards = 12;
    const visible = safeCards.slice(0, maxCards);
    const hidden = Math.max(0, safeCards.length - visible.length);

    return `
      <div class="spellbook-card-ribbon">
        ${visible.map((cardName) => `
          <article class="spellbook-card-mini">
            <img
              class="spellbook-card-mini-image"
              src="${escapeHtml(spellbookCardImageUrl(cardName))}"
              alt="${escapeHtml(cardName)}"
              loading="lazy"
              decoding="async"
            >
            <p class="spellbook-card-mini-name">${escapeHtml(cardName)}</p>
          </article>
        `).join("")}
        ${hidden > 0 ? `<div class="spellbook-card-mini spellbook-card-mini-more">+${escapeHtml(String(hidden))}</div>` : ""}
      </div>
    `;
  }

  function spellbookActionListMarkup(cards, steps) {
    const safeCards = Array.isArray(cards)
      ? cards.map((item) => String(item || "").trim()).filter(Boolean)
      : [];
    const safeSteps = Array.isArray(steps)
      ? steps.map((step) => spellbookNormalizeText(step)).filter(Boolean)
      : [];
    if (safeSteps.length === 0) {
      return '<p class="muted spellbook-empty">Aucune sequence structurée disponible.</p>';
    }

    return `
      <ol class="spellbook-action-list">
        ${safeSteps.slice(0, 10).map((step, stepIndex) => {
          const stepCards = spellbookStepCards(step, safeCards);
          const stepKind = spellbookStepKind(step);
          const stepKindLabel = spellbookStepKindLabel(stepKind);
          const preview = spellbookStepPreview(step);
          const tooltip = escapeHtml(step);
          const chips = stepCards.length > 0
            ? stepCards.map((cardName) => `<span class="spellbook-action-chip" data-tooltip="${tooltip}">${escapeHtml(cardName)}</span>`).join("")
            : `<span class="spellbook-action-chip is-generic" data-tooltip="${tooltip}">${escapeHtml(stepKindLabel)}</span>`;

          return `
            <li class="spellbook-action-item is-${escapeHtml(stepKind)}">
              <span class="spellbook-action-dot"></span>
              <div class="spellbook-action-main">
                <p class="spellbook-action-headline">
                  <span class="spellbook-action-step">Etape ${escapeHtml(String(stepIndex + 1))}</span>
                  <span class="spellbook-action-kind-tag">${escapeHtml(stepKindLabel)}</span>
                </p>
                <p class="spellbook-action-text">${escapeHtml(preview)}</p>
                <div class="spellbook-action-chip-row">${chips}</div>
              </div>
            </li>
          `;
        }).join("")}
      </ol>
    `;
  }

  function spellbookActionTreeMarkup(cards, steps) {
    const safeCards = Array.isArray(cards)
      ? cards.map((item) => String(item || "").trim()).filter(Boolean)
      : [];
    const safeSteps = Array.isArray(steps)
      ? steps.map((step) => spellbookNormalizeText(step)).filter(Boolean)
      : [];

    if (safeSteps.length === 0) {
      return '<p class="muted spellbook-empty">Aucune sequence structurée disponible.</p>';
    }

    const visibleSteps = safeSteps.slice(0, 8);

    return `
      <div class="spellbook-flow" style="--flow-count:${escapeHtml(String(visibleSteps.length))}">
        ${visibleSteps.map((step, stepIndex) => {
          const stepCards = spellbookStepCards(step, safeCards);
          const stepKind = spellbookStepKind(step);
          const stepKindLabel = spellbookStepKindLabel(stepKind);
          const preview = spellbookStepPreview(step, 68);
          const tooltip = escapeHtml(step);
          const cardsMarkup = stepCards.length > 0
            ? stepCards.map((cardName) => `
              <span class="spellbook-action-card" data-tooltip="${tooltip}">${escapeHtml(cardName)}</span>
            `).join("")
            : `<span class="spellbook-action-card is-generic" data-tooltip="${tooltip}">${escapeHtml(stepKindLabel)}</span>`;

          return `
            <article class="spellbook-flow-node is-${escapeHtml(stepKind)}" title="${tooltip}">
              <div class="spellbook-flow-head">
                <span class="spellbook-flow-index">${escapeHtml(String(stepIndex + 1))}</span>
                <span class="spellbook-flow-kind">${escapeHtml(stepKindLabel)}</span>
              </div>
              <p class="spellbook-flow-preview">${escapeHtml(preview)}</p>
              <div class="spellbook-action-cards">${cardsMarkup}</div>
            </article>
          `;
        }).join("")}
      </div>
    `;
  }

  function spellbookStepCards(step, cards) {
    const normalizedStep = normalizeStrategyName(step);
    if (!normalizedStep) {
      return [];
    }

    const matches = [];
    (Array.isArray(cards) ? cards : []).forEach((cardName) => {
      const normalizedCard = normalizeStrategyName(cardName);
      if (!normalizedCard) {
        return;
      }
      if (normalizedStep.includes(normalizedCard)) {
        matches.push(String(cardName || "").trim());
      }
    });

    return Array.from(new Set(matches)).slice(0, 3);
  }

  function spellbookStepKind(step) {
    const text = normalizeStrategyName(step);
    if (!text) {
      return "generic";
    }
    if (/\b(cast|play)\b/.test(text)) {
      return "cast";
    }
    if (/\b(tutor|search)\b/.test(text)) {
      return "tutor";
    }
    if (/\b(sacrifice)\b/.test(text)) {
      return "sacrifice";
    }
    if (/\b(return|reanimate|unearth)\b/.test(text)) {
      return "recursion";
    }
    if (/\b(create|token|copy)\b/.test(text)) {
      return "token";
    }
    if (/\b(resolve|trigger|pay)\b/.test(text)) {
      return "trigger";
    }
    return "generic";
  }

  function spellbookStepKindLabel(kind) {
    const key = String(kind || "").trim();
    if (key === "cast") {
      return "Cast";
    }
    if (key === "tutor") {
      return "Tutor";
    }
    if (key === "sacrifice") {
      return "Sacrifice";
    }
    if (key === "recursion") {
      return "Recursion";
    }
    if (key === "token") {
      return "Token";
    }
    if (key === "trigger") {
      return "Trigger";
    }
    return "Action";
  }

  function spellbookStepPreview(step, maxLength = 88) {
    const text = spellbookNormalizeText(step);
    if (!text) {
      return "Action";
    }
    const safeMax = Number.isFinite(Number(maxLength)) ? Math.max(24, Number(maxLength)) : 88;
    const compact = text.length > safeMax ? `${text.slice(0, safeMax).trimEnd()}...` : text;
    return compact;
  }

  function spellbookDetailsMarkup(steps, description) {
    const safeSteps = Array.isArray(steps)
      ? steps.map((step) => spellbookNormalizeText(step)).filter(Boolean)
      : [];
    if (safeSteps.length > 0) {
      return `
        <details class="spellbook-details">
          <summary>Voir les details complets</summary>
          <ol class="spellbook-detail-list">
            ${safeSteps.slice(0, 18).map((step) => `<li>${escapeHtml(step)}</li>`).join("")}
          </ol>
        </details>
      `;
    }

    const text = spellbookNormalizeText(description);
    if (!text) {
      return '<p class="muted spellbook-empty">Aucun detail supplementaire.</p>';
    }
    const compact = text.length > 900 ? `${text.slice(0, 900).trimEnd()}...` : text;
    return `
      <details class="spellbook-details">
        <summary>Voir les details complets</summary>
        <p>${escapeHtml(compact)}</p>
      </details>
    `;
  }

  function spellbookCardImageUrl(cardName) {
    const name = String(cardName || "").trim();
    if (!name) {
      return "";
    }
    const params = new URLSearchParams({
      exact: name,
      format: "image",
      version: "normal"
    });
    return `https://api.scryfall.com/cards/named?${params.toString()}`;
  }

  function spellbookEntryNames(entries, objectPath) {
    if (!Array.isArray(entries) || entries.length === 0) {
      return [];
    }

    const names = [];
    entries.forEach((entry) => {
      const nested = entry && objectPath && objectPath.length >= 2
        ? entry?.[objectPath[0]]?.[objectPath[1]]
        : "";
      const direct = entry?.name;
      const raw = String(nested || direct || "").trim();
      if (raw) {
        names.push(raw);
      }
    });

    return Array.from(new Set(names));
  }

  function spellbookDescription(variant) {
    const options = [
      variant?.description,
      variant?.notes,
      variant?.result,
      variant?.mana_needed
    ];
    for (const value of options) {
      const text = String(value || "").trim();
      if (text) {
        return text;
      }
    }
    return "";
  }

  function runStrategyComputation() {
    const strategyNodes = nodes.strategy;
    if (!strategyNodes.seedInput || !strategyNodes.status) {
      return;
    }
    const runToken = ++state.strategy.runToken;

    const collectionId = state.selectedCollectionId;
    const payload = collectionId ? state.collectionPayloadById[collectionId] : null;
    if (!payload || payload.ok !== true) {
      strategyNodes.status.textContent = "Charge d'abord une collection pour calculer les synergies.";
      return;
    }

    const model = getStrategyModelForCollection(collectionId, payload);
    const includeKnown = isStrategyIncludeKnownEnabled();
    executeStrategyComputation(strategyNodes, model, rawSeedFromUi(strategyNodes), includeKnown, runToken)
      .catch((error) => {
        if (runToken !== state.strategy.runToken) {
          return;
        }
        strategyNodes.status.textContent = `Erreur pendant le calcul: ${String(error?.message || error || "inconnue")}`;
      });
  }

  function rawSeedFromUi(strategyNodes) {
    return String(strategyNodes.seedInput.value || state.strategy.seedName || "").trim();
  }

  async function executeStrategyComputation(strategyNodes, model, rawSeed, includeKnown, runToken) {
    if (runToken !== state.strategy.runToken) {
      return;
    }
    if (!model.cards.length) {
      strategyNodes.status.textContent = "Collection vide ou cartes non reconnues.";
      strategyNodes.directList.innerHTML = '<p class="muted">Aucun resultat.</p>';
      strategyNodes.groupList.innerHTML = '<p class="muted">Aucun resultat.</p>';
      return;
    }

    if (!rawSeed) {
      strategyNodes.status.textContent = "Saisis une carte seed (ex: Entomb).";
      return;
    }

    const strategyLanguage = normalizeStrategyLanguage(getCollectionLanguage());
    let seedCard = resolveSeedCard(rawSeed, model.cards);
    if (!seedCard && includeKnown) {
      strategyNodes.status.textContent = `Recherche de la seed "${rawSeed}" via Scryfall...`;
      seedCard = await resolveStrategySeedFromScryfall(rawSeed, strategyLanguage);
      if (runToken !== state.strategy.runToken) {
        return;
      }
    }
    if (!seedCard) {
      strategyNodes.status.textContent = includeKnown
        ? `Carte "${rawSeed}" introuvable (collection et Scryfall).`
        : `Carte "${rawSeed}" introuvable dans la collection.`;
      return;
    }

    let activeModel = model;
    if (includeKnown) {
      strategyNodes.status.textContent = `Recherche Scryfall en cours pour ${seedCard.name}...`;
      const knownModel = await getKnownCardsStrategyModel(seedCard, strategyLanguage).catch(() => ({ cards: [] }));
      if (runToken !== state.strategy.runToken) {
        return;
      }
      if (knownModel.cards.length > 0) {
        activeModel = mergeStrategyModels(model, knownModel);
      } else if (state.strategy.knownCardsError) {
        strategyNodes.status.textContent = "Scryfall indisponible, calcul sur la collection uniquement.";
      }
    }

    if (seedCard.source === "scryfall") {
      activeModel = mergeStrategyModels(activeModel, { cards: [seedCard] });
    }
    const scryfallAddedCount = Math.max(0, activeModel.cards.length - model.cards.length);

    const manaFilterCodes = getActiveStrategyManaFilterCodes();
    const colorFilteredCards = filterStrategyCardsByMana(activeModel.cards, manaFilterCodes, seedCard?.key);
    if (colorFilteredCards.length <= 1) {
      renderDirectSynergyCards([], seedCard.name);
      renderGroupCards([], seedCard.name);
      strategyNodes.status.textContent = `${seedCard.name}: aucun candidat apres filtre mana ${formatStrategyManaFilter(manaFilterCodes)}.`;
      return;
    }
    activeModel = { cards: colorFilteredCards };

    state.strategy.seedName = seedCard.name;
    strategyNodes.seedInput.value = seedCard.name;

    const directLimit = clampInt(strategyNodes.directLimitInput?.value, 4, 24, state.strategy.directLimit);
    const groupLimit = clampInt(strategyNodes.groupLimitInput?.value, 3, 12, state.strategy.groupLimit);
    state.strategy.directLimit = directLimit;
    state.strategy.groupLimit = groupLimit;

    const resolvedSeed = resolveSeedCard(seedCard.name, activeModel.cards) || seedCard;
    let spellbookContext = {
      boostByKey: new Map(),
      variantCount: 0,
      variants: []
    };
    if (isStrategyIncludeSpellbookEnabled()) {
      strategyNodes.status.textContent = `Analyse Commander Spellbook en cours pour ${resolvedSeed.name}...`;
      spellbookContext = await getStrategySpellbookContext(resolvedSeed);
      if (runToken !== state.strategy.runToken) {
        return;
      }
    }

    const direct = computeDirectSynergies(
      resolvedSeed,
      activeModel.cards,
      directLimit,
      spellbookContext.boostByKey
    );
    const spellbookGroups = isStrategyIncludeSpellbookEnabled()
      ? computeSpellbookSynergyGroups(resolvedSeed, direct, activeModel.cards, groupLimit, spellbookContext)
      : [];
    const fallbackGroups = computeSynergyGroups(resolvedSeed, direct, activeModel.cards, groupLimit);
    const groups = mergeStrategyGroups(spellbookGroups, fallbackGroups, groupLimit);

    renderDirectSynergyCards(direct, resolvedSeed.name);
    renderGroupCards(groups, resolvedSeed.name);

    const suffix = includeKnown && scryfallAddedCount > 0
      ? ` (incluant ${scryfallAddedCount} cartes Scryfall)`
      : "";
    const manaSuffix = manaFilterCodes.length > 0 ? ` | filtre mana ${formatStrategyManaFilter(manaFilterCodes)}` : "";
    const spellbookSuffix = isStrategyIncludeSpellbookEnabled()
      ? (
        spellbookContext.variantCount > 0
          ? ` | Spellbook ${spellbookContext.variantCount} combos`
          : (state.strategy.spellbookError ? " | Spellbook indisponible" : "")
      )
      : "";
    strategyNodes.status.textContent = `${resolvedSeed.name}: ${direct.length} synergies directes, ${groups.length} groupes construits.${suffix}${manaSuffix}${spellbookSuffix}`;
  }

  function isStrategyIncludeKnownEnabled() {
    return state.strategy.includeKnownCards === true;
  }

  function isStrategyIncludeSpellbookEnabled() {
    return state.strategy.includeSpellbookCombos === true;
  }

  function getActiveStrategyManaFilterCodes() {
    const filter = state.strategy?.manaFilter || {};
    return ["W", "U", "B", "R", "G", "C"].filter((code) => filter[code] === true);
  }

  function formatStrategyManaFilter(codes) {
    const safe = Array.isArray(codes) ? codes.filter((code) => "WUBRGC".includes(String(code))) : [];
    if (safe.length === 0) {
      return "aucun";
    }
    return safe.join("/");
  }

  function filterStrategyCardsByMana(cards, selectedCodes, seedKey = "") {
    const safeCards = Array.isArray(cards) ? cards : [];
    const selected = new Set(Array.isArray(selectedCodes) ? selectedCodes : []);
    if (selected.size === 0) {
      return safeCards;
    }
    const normalizedSeedKey = normalizeStrategyName(seedKey);
    return safeCards.filter((card) => {
      if (normalizedSeedKey && normalizeStrategyName(card?.key) === normalizedSeedKey) {
        return true;
      }
      const cardColors = Array.isArray(card?.colors) ? card.colors.filter((code) => "WUBRG".includes(code)) : [];
      if (cardColors.length === 0) {
        return selected.has("C");
      }
      return cardColors.every((code) => selected.has(code));
    });
  }

  function resetStrategyKnownCardsCache() {
    state.strategy.knownCardsModel = null;
    state.strategy.knownCardsModelKey = "";
    state.strategy.knownCardsModelPromise = null;
    state.strategy.knownCardsModelPromiseKey = "";
    state.strategy.knownCardsError = "";
  }

  function resetStrategySpellbookCache() {
    state.strategy.spellbookCache = new Map();
    state.strategy.spellbookPromiseCache = new Map();
    state.strategy.spellbookError = "";
  }

  async function getStrategySpellbookContext(seedCard) {
    const seedKey = normalizeStrategyName(seedCard?.key || seedCard?.name || "");
    if (!seedKey) {
      return { boostByKey: new Map(), variantCount: 0, variants: [] };
    }
    if (state.strategy.spellbookCache.has(seedKey)) {
      return state.strategy.spellbookCache.get(seedKey);
    }
    if (state.strategy.spellbookPromiseCache.has(seedKey)) {
      return state.strategy.spellbookPromiseCache.get(seedKey);
    }

    const task = fetchStrategySpellbookContext(seedCard)
      .then((context) => {
        state.strategy.spellbookCache.set(seedKey, context);
        state.strategy.spellbookError = "";
        return context;
      })
      .catch((error) => {
        state.strategy.spellbookError = String(error?.message || "Spellbook indisponible");
        const fallback = { boostByKey: new Map(), variantCount: 0, variants: [] };
        state.strategy.spellbookCache.set(seedKey, fallback);
        return fallback;
      })
      .finally(() => {
        state.strategy.spellbookPromiseCache.delete(seedKey);
      });

    state.strategy.spellbookPromiseCache.set(seedKey, task);
    return task;
  }

  async function fetchStrategySpellbookContext(seedCard) {
    const seedName = String(seedCard?.name || "").trim();
    if (!seedName) {
      return { boostByKey: new Map(), variantCount: 0, variants: [] };
    }

    const payload = await fetchSpellbookVariants(seedName, 40);
    if (!payload || payload.ok === false || payload?.results == null) {
      throw new Error(payload?.error || payload?.detail || payload?.details || "Spellbook HTTP error");
    }

    const variants = Array.isArray(payload.results) ? payload.results : [];
    const seedKey = normalizeStrategyName(seedCard?.key || seedName);
    const boostByKey = new Map();
    const variantCards = [];
    let variantCount = 0;

    variants.forEach((variant) => {
      const uses = Array.isArray(variant?.uses) ? variant.uses : [];
      const status = String(variant?.status || "").toUpperCase();
      if (uses.length === 0) {
        return;
      }
      if (status && status !== "OK") {
        return;
      }

      const normalizedNames = uses
        .map((entry) => normalizeStrategyName(entry?.card?.name || ""))
        .filter(Boolean);
      if (!normalizedNames.includes(seedKey)) {
        return;
      }

      variantCount += 1;
      const popularity = Number(variant?.popularity) || 0;
      const popularityFactor = Math.min(1, Math.log10(popularity + 1) / 4);
      const baseBoost = 0.28 + popularityFactor * 0.32;

      normalizedNames.forEach((nameKey) => {
        if (!nameKey || nameKey === seedKey) {
          return;
        }
        const previous = boostByKey.get(nameKey) || 0;
        boostByKey.set(nameKey, Math.min(1.2, previous + baseBoost));
      });

      variantCards.push({
        cardKeys: normalizedNames,
        popularity
      });
    });

    return { boostByKey, variantCount, variants: variantCards };
  }

  async function getKnownCardsStrategyModel(seedCard, strategyLanguage = "en") {
    const seedKey = String(seedCard?.key || "").trim();
    const language = normalizeStrategyLanguage(strategyLanguage);
    const cacheKey = `${seedKey}::${language}`;
    if (!seedKey) {
      return { cards: [] };
    }
    if (state.strategy.knownCardsModel && state.strategy.knownCardsModelKey === cacheKey) {
      return state.strategy.knownCardsModel;
    }
    if (state.strategy.knownCardsModelPromise && state.strategy.knownCardsModelPromiseKey === cacheKey) {
      return state.strategy.knownCardsModelPromise;
    }

    state.strategy.knownCardsModelPromiseKey = cacheKey;
    state.strategy.knownCardsModelPromise = fetchKnownCardsFromScryfall(seedCard, language)
      .then((rows) => {
        const model = buildStrategyModelFromRows(rows);
        state.strategy.knownCardsModel = model;
        state.strategy.knownCardsModelKey = cacheKey;
        state.strategy.knownCardsError = "";
        return model;
      })
      .catch((error) => {
        state.strategy.knownCardsError = String(error?.message || "Scryfall indisponible");
        state.strategy.knownCardsModel = { cards: [] };
        state.strategy.knownCardsModelKey = cacheKey;
        return state.strategy.knownCardsModel;
      })
      .finally(() => {
        state.strategy.knownCardsModelPromise = null;
        state.strategy.knownCardsModelPromiseKey = "";
      });

    return state.strategy.knownCardsModelPromise;
  }

  function scryfallQueriesForSeed(seedCard) {
    const seedKey = normalizeStrategyName(seedCard?.name || seedCard?.key || "");
    const overrideQueries = STRATEGY_SEED_QUERY_OVERRIDES[seedKey] || [];
    const featureEntries = Object.entries(seedCard?.features || {})
      .map(([id, score]) => ({ id, score: Number(score) || 0 }))
      .filter((entry) => entry.score > 0 && STRATEGY_FEATURE_SCRYFALL_QUERY[entry.id])
      .sort((left, right) => right.score - left.score)
      .slice(0, 3);

    const queries = [
      ...overrideQueries,
      ...featureEntries.map((entry) => STRATEGY_FEATURE_SCRYFALL_QUERY[entry.id])
    ];
    const seedName = String(seedCard?.name || "").trim();
    if (seedName) {
      queries.push(`(oracle:\"${seedName}\" OR oracle:\"from your graveyard\" OR oracle:proliferate OR oracle:\"poison counter\")`);
    }
    return Array.from(new Set(queries)).slice(0, 4);
  }

  function normalizeStrategyLanguage(language) {
    return String(language || "").toLowerCase() === "fr" ? "fr" : "en";
  }

  async function resolveStrategySeedFromScryfall(rawSeedName, strategyLanguage = "en") {
    const seedName = String(rawSeedName || "").trim();
    if (!seedName) {
      return null;
    }

    const record = await fetchScryfallNamedCardRecord(seedName, strategyLanguage);
    if (!record) {
      return null;
    }

    const rows = [mapScryfallCardToStrategyRow(record, strategyLanguage)];
    const model = buildStrategyModelFromRows(rows);
    return Array.isArray(model.cards) && model.cards.length > 0 ? model.cards[0] : null;
  }

  async function fetchScryfallNamedCardRecord(cardName, strategyLanguage = "en") {
    const seedName = String(cardName || "").trim();
    if (!seedName) {
      return null;
    }
    const baseCard = await fetchScryfallNamedCard(seedName);
    if (!baseCard) {
      return null;
    }
    return fetchScryfallLocalizedCard(baseCard, strategyLanguage);
  }

  async function fetchScryfallNamedCard(cardName) {
    const exactUrl = `https://api.scryfall.com/cards/named?${new URLSearchParams({ exact: cardName }).toString()}`;
    const exactCard = await fetchScryfallJson(exactUrl);
    if (exactCard && exactCard.object === "card") {
      return exactCard;
    }

    const fuzzyUrl = `https://api.scryfall.com/cards/named?${new URLSearchParams({ fuzzy: cardName }).toString()}`;
    const fuzzyCard = await fetchScryfallJson(fuzzyUrl);
    if (fuzzyCard && fuzzyCard.object === "card") {
      return fuzzyCard;
    }
    return null;
  }

  async function fetchScryfallLocalizedCard(card, strategyLanguage = "en") {
    if (!card || card.object !== "card") {
      return null;
    }
    const language = normalizeStrategyLanguage(strategyLanguage);
    if (language === "en" || String(card.lang || "").toLowerCase() === language) {
      return card;
    }

    const cardId = String(card.id || "").trim();
    if (!cardId) {
      return card;
    }

    const localizedUrl = `https://api.scryfall.com/cards/${encodeURIComponent(cardId)}/${language}`;
    const localized = await fetchScryfallJson(localizedUrl);
    if (localized && localized.object === "card") {
      return localized;
    }
    return card;
  }

  async function fetchScryfallJson(url) {
    const response = await fetch(url, {
      method: "GET",
      headers: { Accept: "application/json" }
    });
    const payload = await response.json().catch(() => null);
    if (!response.ok || payload?.object === "error") {
      return null;
    }
    return payload;
  }

  function scryfallDisplayName(card, strategyLanguage = "en") {
    const language = normalizeStrategyLanguage(strategyLanguage);
    const printed = String(card?.printed_name || "").trim();
    const named = String(card?.name || "").trim();
    if (language === "fr") {
      return printed || named;
    }
    return named || printed;
  }

  function scryfallDisplayTypeLine(card, strategyLanguage = "en") {
    const language = normalizeStrategyLanguage(strategyLanguage);
    const printed = String(card?.printed_type_line || "").trim();
    const canonical = String(card?.type_line || "").trim();
    if (language === "fr") {
      return printed || canonical;
    }
    return canonical || printed;
  }

  function scryfallDisplayOracleText(card, strategyLanguage = "en") {
    const language = normalizeStrategyLanguage(strategyLanguage);
    const printed = String(card?.printed_text || "").trim();
    const canonical = String(card?.oracle_text || "").trim();
    if (language === "fr") {
      return printed || canonical;
    }
    return canonical || printed;
  }

  function scryfallManaCost(card) {
    const base = String(card?.mana_cost || "").trim();
    if (base) {
      return base;
    }
    if (!Array.isArray(card?.card_faces)) {
      return "";
    }
    return card.card_faces
      .map((face) => String(face?.mana_cost || "").trim())
      .filter(Boolean)
      .join(" ");
  }

  function mapScryfallCardToStrategyRow(card, strategyLanguage = "en") {
    const displayName = scryfallDisplayName(card, strategyLanguage);
    return {
      name: displayName || String(card?.name || "").trim(),
      name_en: String(card?.name || "").trim(),
      mana_cost: scryfallManaCost(card),
      oracle_text: scryfallDisplayOracleText(card, strategyLanguage),
      keywords: Array.isArray(card?.keywords) ? card.keywords.join(", ") : "",
      type_line: scryfallDisplayTypeLine(card, strategyLanguage),
      colors: Array.isArray(card?.colors) ? card.colors.join("") : "",
      color_identity: Array.isArray(card?.color_identity) ? card.color_identity.join("") : "",
      scryfall_id: String(card?.id || "").trim(),
      set_code: String(card?.set || "").trim(),
      collector_number: String(card?.collector_number || "").trim(),
      language: String(card?.lang || normalizeStrategyLanguage(strategyLanguage)).trim(),
      source: "scryfall"
    };
  }

  async function fetchScryfallSearchCards(query, maxCards, strategyLanguage = "en") {
    const language = normalizeStrategyLanguage(strategyLanguage);
    const queryBase = String(query || "").trim();
    if (!queryBase) {
      return [];
    }

    const hardLimit = Math.max(40, Number(maxCards) || 180);
    const langQuery = /\blang:(en|fr)\b/i.test(queryBase) ? queryBase : `(${queryBase}) lang:${language}`;

    async function runSearch(searchQuery) {
      const collected = [];
      let nextUrl = `https://api.scryfall.com/cards/search?${new URLSearchParams({
        q: searchQuery,
        unique: "cards",
        order: "edhrec",
        include_multilingual: "true"
      }).toString()}`;

      while (nextUrl && collected.length < hardLimit) {
        const response = await fetch(nextUrl, {
          method: "GET",
          headers: { Accept: "application/json" }
        });
        const payload = await response.json().catch(() => ({}));
        if (!response.ok || payload.object === "error") {
          throw new Error(payload?.details || `Scryfall HTTP ${response.status}`);
        }
        const batch = Array.isArray(payload.data) ? payload.data : [];
        for (const card of batch) {
          collected.push(card);
          if (collected.length >= hardLimit) {
            break;
          }
        }
        nextUrl = payload.has_more && payload.next_page ? payload.next_page : "";
      }
      return collected;
    }

    let collected = await runSearch(langQuery);
    if (collected.length === 0 && language !== "en") {
      collected = await runSearch(queryBase);
    }
    return collected;
  }

  function strategySourceFromRow(row) {
    const explicit = rowValue(row, ["source", "card_source", "source_api", "source_origin"]).toLowerCase();
    if (explicit.includes("scryfall")) {
      return "scryfall";
    }
    return "collection";
  }

  function strategySourceBadgeText(sourceType) {
    if (sourceType !== "scryfall") {
      return "";
    }
    return getCollectionLanguage() === "fr" ? "Source: Scryfall" : "Source: Scryfall";
  }

  function appendStrategyCardBadge(container, label, toneClass) {
    if (!container) {
      return;
    }
    const text = String(label || "").trim();
    if (!text) {
      return;
    }
    const badgeNode = document.createElement("span");
    badgeNode.className = `strategy-card-badge ${toneClass}`;
    badgeNode.textContent = text;
    container.appendChild(badgeNode);
  }

  async function localizeScryfallCards(cards, strategyLanguage = "en") {
    const language = normalizeStrategyLanguage(strategyLanguage);
    if (language === "en" || !Array.isArray(cards) || cards.length === 0) {
      return Array.isArray(cards) ? cards : [];
    }

    const collected = [];
    for (let i = 0; i < cards.length; i += 8) {
      const chunk = cards.slice(i, i + 8);
      const localizedChunk = await Promise.all(
        chunk.map((card) => fetchScryfallLocalizedCard(card, language).catch(() => card))
      );
      localizedChunk.forEach((item, index) => {
        if (item && item.object === "card") {
          collected.push(item);
          return;
        }
        if (chunk[index]) {
          collected.push(chunk[index]);
        }
      });
    }
    return collected;
  }

  async function fetchScryfallSearchCardsLocalized(query, maxCards, strategyLanguage = "en") {
    const base = await fetchScryfallSearchCards(query, maxCards, strategyLanguage);
    const language = normalizeStrategyLanguage(strategyLanguage);
    if (language === "en") {
      return base;
    }
    const hasWrongLanguage = base.some((card) => String(card?.lang || "").toLowerCase() !== language);
    if (!hasWrongLanguage) {
      return base;
    }
    return localizeScryfallCards(base, language);
  }

  async function fetchKnownCardsFromScryfall(seedCard, strategyLanguage = "en") {
    const language = normalizeStrategyLanguage(strategyLanguage);
    const queries = scryfallQueriesForSeed(seedCard);
    if (queries.length === 0) {
      const onlySeed = await fetchScryfallNamedCardRecord(seedCard?.name || "", language);
      return onlySeed ? [mapScryfallCardToStrategyRow(onlySeed, language)] : [];
    }

    const allCards = [];
    const seedRecord = await fetchScryfallNamedCardRecord(seedCard?.name || "", language);
    if (seedRecord) {
      allCards.push(seedRecord);
    }
    for (const query of queries) {
      const cards = await fetchScryfallSearchCardsLocalized(query, 180, language);
      allCards.push(...cards);
    }

    const uniqueByName = new Map();
    allCards.forEach((card) => {
      const row = mapScryfallCardToStrategyRow(card, language);
      const key = normalizeStrategyName(row.name || row.name_en);
      if (!key || uniqueByName.has(key)) {
        return;
      }
      uniqueByName.set(key, row);
    });

    return Array.from(uniqueByName.values());
  }

  function mergeStrategyModels(primaryModel, secondaryModel) {
    const primaryCards = Array.isArray(primaryModel?.cards) ? primaryModel.cards : [];
    const secondaryCards = Array.isArray(secondaryModel?.cards) ? secondaryModel.cards : [];
    if (!secondaryCards.length) {
      return { cards: primaryCards };
    }

    const byKey = new Map();
    primaryCards.forEach((card) => {
      if (card?.key) {
        byKey.set(card.key, card);
      }
    });
    secondaryCards.forEach((card) => {
      if (!card?.key || byKey.has(card.key)) {
        return;
      }
      byKey.set(card.key, card);
    });
    return { cards: Array.from(byKey.values()) };
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
      const displayName = rowValue(row, ["name", "card_name", "card", "title"]).trim();
      const canonicalName = rowValue(row, ["name_en", "name", "card_name", "card", "title"]).trim();
      const name = displayName || canonicalName;
      if (!name && !canonicalName) {
        return;
      }

      const key = normalizeStrategyName(canonicalName || name);
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
          scryfallId: rowValue(row, ["scryfall_id", "scry_fall_id"]).trim(),
          source: strategySourceFromRow(row)
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
      if (existing.source !== "collection") {
        existing.source = strategySourceFromRow(row);
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
      worldgorgerLine: countPatternHits(source, /worldgorger dragon|exile all other permanents you control/i),
      libraryMillOut: countPatternHits(source, /puts? the top .* cards? of .* library into .* graveyard|\bmill\b|target player mills/i),
      chooseColorGlobal: countPatternHits(source, /choose a color|all cards that aren't on the battlefield.*chosen color|are the chosen color/i),
      untapArtifactOut: countPatternHits(source, /untap target artifact|untap all artifacts/i),
      activatedArtifactRef: countPatternHits(source, /activated abilities of artifacts|\{[^}]+\}:\s|activate only/i),
      artifactTutor: countPatternHits(source, /search your library .* artifact/i),
      grindstoneClause: countPatternHits(source, /three cards .* share a color/i),
      painterClause: countPatternHits(source, /as .* enters.* choose a color|cards? that aren't on the battlefield/i)
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

  function computeDirectSynergies(seedCard, cards, limit, spellbookBoostByKey = new Map()) {
    const results = cards
      .filter((card) => card.key !== seedCard.key)
      .map((card) => {
        const sim = strategySimilarity(seedCard, card);
        const spellbookRaw = Number(spellbookBoostByKey?.get?.(card.key) || 0);
        const spellbookBoost = Math.max(0, spellbookRaw);
        const externalBoost = Math.min(0.45, spellbookBoost * 0.55);
        const score = clampScore(sim.score + externalBoost);
        return {
          card,
          score,
          featureScore: sim.featureScore,
          ruleScore: sim.ruleScore,
          colorScore: sim.colorScore,
          comboBoost: sim.comboBoost,
          spellbookBoost
        };
      })
      .filter((entry) => entry.score > 0.05 && (
        entry.ruleScore > 0.02 ||
        entry.featureScore > 0.08 ||
        entry.comboBoost > 0 ||
        entry.spellbookBoost > 0.12
      ))
      .sort((left, right) => {
        if (Math.abs(right.score - left.score) > 1e-9) {
          return right.score - left.score;
        }
        if (Math.abs((right.spellbookBoost || 0) - (left.spellbookBoost || 0)) > 1e-9) {
          return (right.spellbookBoost || 0) - (left.spellbookBoost || 0);
        }
        if (Math.abs((right.comboBoost || 0) - (left.comboBoost || 0)) > 1e-9) {
          return (right.comboBoost || 0) - (left.comboBoost || 0);
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

  function computeSpellbookSynergyGroups(seedCard, directEntries, allCards, groupLimit, spellbookContext) {
    const variants = Array.isArray(spellbookContext?.variants) ? spellbookContext.variants : [];
    if (variants.length === 0) {
      return [];
    }

    const cardsByKey = new Map((Array.isArray(allCards) ? allCards : []).map((card) => [card.key, card]));
    const directByKey = new Map((Array.isArray(directEntries) ? directEntries : []).map((entry) => [entry.card.key, entry]));
    const directKeys = new Set(directByKey.keys());
    const seedKey = seedCard.key;

    const groups = [];
    const seen = new Set();

    variants.forEach((variant) => {
      const rawKeys = Array.isArray(variant?.cardKeys) ? variant.cardKeys : [];
      if (!rawKeys.includes(seedKey)) {
        return;
      }

      const partnerKeys = rawKeys
        .filter((key) => key && key !== seedKey && cardsByKey.has(key) && directKeys.has(key))
        .map((key) => ({
          key,
          score: Number(directByKey.get(key)?.score || 0)
        }))
        .sort((left, right) => right.score - left.score)
        .slice(0, 4);

      if (partnerKeys.length === 0) {
        return;
      }

      const packageCards = [seedCard].concat(partnerKeys.map((item) => cardsByKey.get(item.key)));
      const signature = packageCards.map((card) => card.key).sort().join("|");
      if (seen.has(signature)) {
        return;
      }
      seen.add(signature);

      const split = splitGroupCoreAndSide(seedCard, packageCards);
      const popularity = Number(variant?.popularity) || 0;
      const popularityFactor = Math.min(1, Math.log10(popularity + 1) / 4);
      const avgDirectScore = partnerKeys.reduce((sum, item) => sum + item.score, 0) / partnerKeys.length;
      const groupScore = clampScore(avgDirectScore * 0.8 + popularityFactor * 0.2);

      const orderedNames = partnerKeys
        .map((item) => cardsByKey.get(item.key)?.name)
        .filter(Boolean);
      const bridgeName = orderedNames[0] || seedCard.name;
      const lineA = orderedNames.length > 0
        ? `${seedCard.name} -> ${orderedNames.join(" -> ")}`
        : seedCard.name;
      const lineB = orderedNames.length > 1
        ? `${seedCard.name} -> ${orderedNames.slice().reverse().join(" -> ")}`
        : lineA;

      groups.push({
        cards: packageCards,
        coreCards: split.coreCards,
        sideCards: split.sideCards,
        bridgeName,
        score: groupScore,
        lineA,
        lineB
      });
    });

    groups.sort((a, b) => {
      if (Math.abs(b.score - a.score) > 1e-9) {
        return b.score - a.score;
      }
      return a.bridgeName.localeCompare(b.bridgeName);
    });

    return groups.slice(0, Math.max(1, groupLimit));
  }

  function mergeStrategyGroups(primaryGroups, fallbackGroups, limit) {
    const cap = Math.max(1, Number(limit) || 1);
    const out = [];
    const seen = new Set();

    function pushUnique(groups) {
      (Array.isArray(groups) ? groups : []).forEach((group) => {
        if (!group || !Array.isArray(group.cards)) {
          return;
        }
        const key = group.cards.map((card) => card.key).sort().join("|");
        if (seen.has(key)) {
          return;
        }
        seen.add(key);
        out.push(group);
      });
    }

    pushUnique(primaryGroups);
    if (out.length < cap) {
      pushUnique(fallbackGroups);
    }
    return out.slice(0, cap);
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
    const comboBoost = comboKnowledgeBoost(cardA, cardB);
    const score = clampScore(featureScore * 0.5 + ruleScore * 0.4 + colorScore * 0.1 + comboBoost);
    return { score, featureScore, ruleScore, colorScore, comboBoost };
  }

  function comboKnowledgeBoost(cardA, cardB) {
    const keyA = normalizeStrategyName(cardA?.key || cardA?.name || "");
    const keyB = normalizeStrategyName(cardB?.key || cardB?.name || "");
    if (!keyA || !keyB) {
      return 0;
    }

    let boost = 0;
    STRATEGY_KNOWN_COMBO_PAIRS.forEach((pair) => {
      const left = normalizeStrategyName(pair.a);
      const right = normalizeStrategyName(pair.b);
      const hit = (keyA === left && keyB === right) || (keyA === right && keyB === left);
      if (hit) {
        boost = Math.max(boost, Number(pair.boost) || 0);
      }
    });

    const semA = cardA?.semantics || {};
    const semB = cardB?.semantics || {};
    const logicalRoleBoost = grindstoneRoleBoost(semA, semB);
    return clampScore(Math.max(boost, logicalRoleBoost));
  }

  function grindstoneRoleBoost(semA, semB) {
    const aMill = bounded((semA.libraryMillOut || 0) + (semA.grindstoneClause || 0));
    const bMill = bounded((semB.libraryMillOut || 0) + (semB.grindstoneClause || 0));
    const aColor = bounded((semA.chooseColorGlobal || 0) + (semA.painterClause || 0));
    const bColor = bounded((semB.chooseColorGlobal || 0) + (semB.painterClause || 0));
    const aUntap = bounded((semA.untapArtifactOut || 0) + (semA.activatedArtifactRef || 0));
    const bUntap = bounded((semB.untapArtifactOut || 0) + (semB.activatedArtifactRef || 0));

    let boost = 0;
    if (aMill && bColor) {
      boost = Math.max(boost, 0.72);
    }
    if (bMill && aColor) {
      boost = Math.max(boost, 0.72);
    }
    if (aMill && bUntap) {
      boost = Math.max(boost, 0.24);
    }
    if (bMill && aUntap) {
      boost = Math.max(boost, 0.24);
    }
    return boost;
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
    score += bounded(src.libraryMillOut + src.grindstoneClause) * bounded(dst.chooseColorGlobal + dst.painterClause) * 1.25;
    score += bounded(src.chooseColorGlobal + src.painterClause) * bounded(dst.libraryMillOut + dst.grindstoneClause) * 1.25;
    score += bounded(src.libraryMillOut + src.grindstoneClause) * bounded(dst.untapArtifactOut + dst.activatedArtifactRef) * 0.50;
    score += bounded(src.artifactTutor) * bounded(dst.libraryMillOut + dst.chooseColorGlobal + dst.painterClause) * 0.35;

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
    const millA = bounded((a.libraryMillOut || 0) + (a.grindstoneClause || 0));
    const millB = bounded((b.libraryMillOut || 0) + (b.grindstoneClause || 0));
    const colorA = bounded((a.chooseColorGlobal || 0) + (a.painterClause || 0));
    const colorB = bounded((b.chooseColorGlobal || 0) + (b.painterClause || 0));

    const score = Math.min(graveA, graveB) * 0.25 +
      Math.min(spellA, spellB) * 0.18 +
      Math.min(drainA, drainB) * 0.10 +
      Math.min(toxicA, toxicB) * 0.28 +
      Math.min(prolifA, prolifB) * 0.24 +
      Math.min(corruptedA, corruptedB) * 0.14 +
      Math.min(biteA, biteB) * 0.10 +
      Math.min(millA, millB) * 0.14 +
      Math.min(colorA, colorB) * 0.18;

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
      const comboPart = entry.comboBoost > 0 ? ` | combo ${formatDecimal(entry.comboBoost)}` : "";
      const spellbookPart = entry.spellbookBoost > 0 ? ` | sb ${formatDecimal(entry.spellbookBoost)}` : "";
      fragment.appendChild(
        createStrategyCardElement(
          entry.card,
          `#${index + 1} | score ${formatDecimal(entry.score)} | rules ${formatDecimal(entry.ruleScore || 0)}${comboPart}${spellbookPart}`
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

    const badgesLine = document.createElement("div");
    badgesLine.className = "strategy-card-badges";
    if (badge) {
      appendStrategyCardBadge(
        badgesLine,
        badge,
        badgeTone === "side" ? "is-side" : "is-core"
      );
    }
    const sourceBadge = strategySourceBadgeText(card?.source || "collection");
    if (sourceBadge) {
      appendStrategyCardBadge(badgesLine, sourceBadge, "is-source-scryfall");
    }
    if (badgesLine.childNodes.length > 0) {
      body.appendChild(badgesLine);
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
      const kind = String(item.getAttribute("data-entity-kind") || "store").toLowerCase();
      const dbPath = String(item.getAttribute("data-db-path") || "").trim();

      const action = button?.dataset.action || "select";

      if (kind === "db") {
        if (action === "select") {
          if (dbPath) {
            const currentPath = String(state.dbCollectionPayload?.path || getConfiguredCollectionDbPath() || "").trim();
            if (!dbPathEquals(currentPath, dbPath)) {
              state.dbCollectionPayload = null;
            }
            setConfiguredCollectionDbPath(dbPath);
          }
          setCollectionSourcePreference("db");
          renderCollectionsList("");
          renderActiveTabTable();
          if (!state.dbCollectionPayload) {
            await loadDefaultDbCollectionIntoTable(dbPath);
          }
          return;
        }
        if (action === "delete" && dbPath) {
          removeSavedDbSource(dbPath);
          if (dbPathEquals(getConfiguredCollectionDbPath(), dbPath)) {
            setConfiguredCollectionDbPath("");
            state.dbCollectionPayload = null;
            if (getCollectionSourcePreference() === "db") {
              setCollectionSourcePreference("store");
            }
          }
          renderCollectionsList("");
          renderActiveTabTable();
        }
        return;
      }

      if (action === "select") {
        state.selectedCollectionId = id;
        setSavedSelectedCollectionId(id);
        setCollectionSourcePreference("store");
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
        setSavedSelectedCollectionId(state.selectedCollectionId);
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

  function readRowField(row, candidates = []) {
    if (!row || typeof row !== "object") {
      return "";
    }
    const map = {};
    Object.keys(row).forEach((key) => {
      map[String(key).toLowerCase()] = row[key];
    });
    for (const candidate of candidates) {
      const value = map[String(candidate).toLowerCase()];
      if (value == null) {
        continue;
      }
      const text = String(value).trim();
      if (text) {
        return text;
      }
    }
    return "";
  }

  function isDbActionViewKey(viewKeyValue) {
    const viewKey = String(viewKeyValue || "").toLowerCase();
    if (!viewKey.startsWith("collections::")) {
      return false;
    }
    return viewKey.includes(".db") || viewKey.includes("collection/db");
  }

  function getCollectionSourcePreference() {
    const raw = String(window.localStorage.getItem(COLLECTION_SOURCE_PREF_KEY) || "").trim().toLowerCase();
    if (raw === "db" || raw === "store") {
      return raw;
    }
    return "store";
  }

  function setCollectionSourcePreference(value) {
    const normalized = String(value || "").trim().toLowerCase();
    if (normalized !== "db" && normalized !== "store") {
      return;
    }
    window.localStorage.setItem(COLLECTION_SOURCE_PREF_KEY, normalized);
  }

  function getSavedSelectedCollectionId() {
    return String(window.localStorage.getItem(COLLECTION_SELECTED_ID_KEY) || "").trim();
  }

  function setSavedSelectedCollectionId(collectionId) {
    const value = String(collectionId || "").trim();
    if (value) {
      window.localStorage.setItem(COLLECTION_SELECTED_ID_KEY, value);
    } else {
      window.localStorage.removeItem(COLLECTION_SELECTED_ID_KEY);
    }
  }

  function getSavedDbSources() {
    try {
      const raw = window.localStorage.getItem(COLLECTION_DB_SOURCES_KEY);
      if (!raw) {
        return [];
      }
      const parsed = JSON.parse(raw);
      if (!Array.isArray(parsed)) {
        return [];
      }
      const unique = [];
      parsed.forEach((entry) => {
        const pathValue = String(entry || "").trim();
        if (!pathValue) {
          return;
        }
        if (!unique.some((knownPath) => dbPathEquals(knownPath, pathValue))) {
          unique.push(pathValue);
        }
      });
      return unique;
    } catch (_) {
      return [];
    }
  }

  function setSavedDbSources(paths) {
    const source = Array.isArray(paths) ? paths : [];
    const clean = [];
    source.forEach((entry) => {
      const pathValue = String(entry || "").trim();
      if (!pathValue) {
        return;
      }
      if (!clean.some((knownPath) => dbPathEquals(knownPath, pathValue))) {
        clean.push(pathValue);
      }
    });
    window.localStorage.setItem(COLLECTION_DB_SOURCES_KEY, JSON.stringify(clean.slice(0, 24)));
  }

  function rememberDbSource(dbPath) {
    const value = String(dbPath || "").trim();
    if (!value) {
      return;
    }
    const current = getSavedDbSources();
    const next = [value, ...current.filter((entry) => !dbPathEquals(entry, value))];
    setSavedDbSources(next);
  }

  function removeSavedDbSource(dbPath) {
    const value = String(dbPath || "").trim();
    if (!value) {
      return;
    }
    const current = getSavedDbSources();
    setSavedDbSources(current.filter((entry) => !dbPathEquals(entry, value)));
  }

  function getConfiguredCollectionDbPath() {
    return String(window.localStorage.getItem("mtgcodex_collection_db_path") || "").trim();
  }

  function setConfiguredCollectionDbPath(pathValue) {
    const value = String(pathValue || "").trim();
    window.localStorage.setItem("mtgcodex_collection_db_path", value);
    return value;
  }

  function pickFileForDbImport() {
    return new Promise((resolve) => {
      const input = document.createElement("input");
      input.type = "file";
      input.accept = ".csv,.db,.sqlite,.sqlite3,.txt";
      input.style.position = "fixed";
      input.style.left = "-9999px";
      document.body.appendChild(input);
      input.addEventListener("change", () => {
        const file = input.files && input.files[0] ? input.files[0] : null;
        input.remove();
        resolve(file);
      }, { once: true });
      input.click();
    });
  }

  async function loadDefaultDbCollectionIntoTable(dbPath = "") {
    const effectiveDbPath = String(dbPath || getConfiguredCollectionDbPath() || "").trim();
    const payload = await loadCollectionFromDb(effectiveDbPath, "collection");
    if (!payload || payload.ok !== true) {
      state.dbCollectionPayload = null;
      renderCollection({
        ok: false,
        table: "mtg.db / collection",
        error: payload?.error || "Impossible de charger la collection DB"
      });
      return false;
    }
    const persistedPath = payload.path
      ? setConfiguredCollectionDbPath(payload.path)
      : (effectiveDbPath ? setConfiguredCollectionDbPath(effectiveDbPath) : "");
    if (persistedPath) {
      rememberDbSource(persistedPath);
    }
    const dbViewPayload = payloadForNamedView(
      payload,
      "mtg.db / collection",
      payload.path || "collection/db",
      "cards",
      "collections"
    );
    state.dbCollectionPayload = dbViewPayload;
    renderCollection(dbViewPayload);
    setCollectionSourcePreference("db");
    renderCollectionsList("");
    return true;
  }

  async function runDbImportFlow() {
    const configuredPath = getConfiguredCollectionDbPath();
    const chosenPath = window.prompt(
      "Chemin DB cible (vide = mtg.db par defaut serveur):",
      configuredPath
    );
    if (chosenPath == null) {
      return { ok: false, canceled: true };
    }
    const effectiveDbPath = setConfiguredCollectionDbPath(chosenPath);

    const file = await pickFileForDbImport();
    if (!file) {
      return { ok: false, canceled: true };
    }
    const sourceType = inferCollectionSourceType(file.name);
    const out = await importIntoCollectionDb(file, effectiveDbPath, sourceType, "", true);
    if (!out || out.ok !== true) {
      return {
        ok: false,
        error: out?.error || "Import DB impossible"
      };
    }

    await loadDefaultDbCollectionIntoTable(effectiveDbPath);
    return {
      ok: true,
      dbPath: effectiveDbPath
    };
  }

  async function handleDeleteCardRowRequest(event) {
    const detail = event?.detail || {};
    const viewKey = String(detail.viewKey || "").toLowerCase();
    if (!isDbActionViewKey(viewKey)) {
      return;
    }

    const row = detail.row || null;
    const id = readRowField(row, ["id"]);
    const manaboxId = readRowField(row, ["manabox_id", "manabox id"]);
    const name = readRowField(row, ["name"]);
    const setCode = readRowField(row, ["set_code", "set"]);
    const collector = readRowField(row, ["collector_number", "number"]);
    const scryfallId = readRowField(row, ["scryfall_id", "scry_fall_id"]);

    let selector = {};
    if (id) {
      const confirmed = window.confirm(`Supprimer la ligne #${id} (${name || "carte"}) ?`);
      if (!confirmed) {
        return;
      }
      selector = { id };
    } else if (manaboxId) {
      const confirmed = window.confirm(`Supprimer ${name || "cette carte"} (ManaBox ID ${manaboxId}) ?`);
      if (!confirmed) {
        return;
      }
      selector = { manabox_id: manaboxId };
    } else if (scryfallId) {
      const confirmed = window.confirm(`Supprimer ${name || "cette carte"} (${setCode || "set?"} ${collector || ""}) ?`);
      if (!confirmed) {
        return;
      }
      selector = {
        scryfall_id: scryfallId,
        name,
        set_code: setCode,
        collector_number: collector
      };
    } else {
      renderCollection({
        ok: false,
        table: "mtg.db delete",
        error: "Impossible d'identifier la carte a supprimer."
      });
      return;
    }

    const out = await deleteCardFromCollectionDb(selector, getConfiguredCollectionDbPath(), false);
    if (!out || out.ok !== true) {
      renderCollection({
        ok: false,
        table: "mtg.db delete",
        error: out?.error || "Suppression impossible"
      });
      return;
    }
    await loadDefaultDbCollectionIntoTable();
  }

  async function handleDbActionRequest(event) {
    const detail = event?.detail || {};
    const action = String(detail.action || "").toLowerCase();
    const viewKey = String(detail.viewKey || "").toLowerCase();
    if (!action) {
      return;
    }
    if (!isDbActionViewKey(viewKey)) {
      renderCollection({
        ok: false,
        table: "DB actions",
        error: "Ces actions sont disponibles depuis la vue collection."
      });
      return;
    }

    if (action === "import") {
      const out = await runDbImportFlow();
      if (out?.canceled) {
        return;
      }
      if (!out || out.ok !== true) {
        renderCollection({
          ok: false,
          table: "mtg.db import",
          error: out?.error || "Import DB impossible"
        });
      }
      return;
    }

    if (action === "add") {
      openAddCardModal(detail.row || null);
      return;
    }

    if (action === "delete") {
      const row = detail.row || null;
      const id = readRowField(row, ["id"]);
      const manaboxId = readRowField(row, ["manabox_id", "manabox id"]);
      const name = readRowField(row, ["name"]);
      const setCode = readRowField(row, ["set_code", "set"]);
      const collector = readRowField(row, ["collector_number", "number"]);
      const scryfallId = readRowField(row, ["scryfall_id", "scry_fall_id"]);

      let selector = {};
      if (id) {
        const confirmed = window.confirm(`Supprimer la ligne #${id} (${name || "carte"}) ?`);
        if (!confirmed) {
          return;
        }
        selector = { id };
      } else if (manaboxId) {
        const confirmed = window.confirm(`Supprimer ${name || "cette carte"} (ManaBox ID ${manaboxId}) ?`);
        if (!confirmed) {
          return;
        }
        selector = { manabox_id: manaboxId };
      } else {
        const manual = window.prompt("ID de ligne, ManaBox ID ou Scryfall ID a supprimer :", scryfallId || "");
        if (manual == null || !String(manual).trim()) {
          return;
        }
        const value = String(manual).trim();
        if (/^[0-9]+$/.test(value)) {
          if (value.length >= 6) {
            selector = { manabox_id: value };
          } else {
            selector = { id: value };
          }
        } else if (/^[0-9a-f-]{20,}$/i.test(value)) {
          selector = {
            scryfall_id: value,
            name,
            set_code: setCode,
            collector_number: collector
          };
        } else {
          selector = { manabox_id: value };
        }
      }

      const out = await deleteCardFromCollectionDb(selector, getConfiguredCollectionDbPath(), false);
      if (!out || out.ok !== true) {
        renderCollection({
          ok: false,
          table: "mtg.db delete",
          error: out?.error || "Suppression impossible"
        });
        return;
      }
      await loadDefaultDbCollectionIntoTable();
    }
  }

  function attachDbActionEvents() {
    window.addEventListener("mtgcodex:db-action", handleDbActionRequest);
    window.addEventListener("mtgcodex:add-card-workflow", handleAddCardWorkflowRequest);
    window.addEventListener("mtgcodex:delete-card-row", handleDeleteCardRowRequest);
  }

  function handleAddCardWorkflowRequest(event) {
    const detail = event?.detail || {};
    const viewKey = String(detail.viewKey || "").toLowerCase();
    if (!isDbActionViewKey(viewKey)) {
      renderCollection({
        ok: false,
        table: "Add card",
        error: "Ajout disponible depuis la vue collection."
      });
      return;
    }
    openAddCardModal(detail.row || null);
  }

  function ensureAddCardModal() {
    if (ADD_CARD_MODAL_STATE.root && document.body.contains(ADD_CARD_MODAL_STATE.root)) {
      return ADD_CARD_MODAL_STATE;
    }

    const root = document.createElement("div");
    root.className = "card-add-modal hidden";
    root.innerHTML = `
      <div class="card-add-dialog" role="dialog" aria-modal="true" aria-label="Ajouter une carte">
        <div class="card-add-head">
          <h3>Ajouter une carte</h3>
          <button type="button" class="card-add-close" aria-label="Fermer">x</button>
        </div>
        <div class="card-add-body">
          <label class="card-add-field">
            Nom de carte
            <input type="search" class="card-add-name" placeholder="Entomb">
          </label>
          <div class="card-add-suggestions"></div>
          <div class="card-add-prints">
            <p class="muted">Choisis une extension/edition:</p>
            <div class="card-add-print-list"></div>
          </div>
          <div class="card-add-inline">
            <label class="card-add-field">
              Finish
              <select class="card-add-finish">
                <option value="normal">normal</option>
                <option value="foil">foil</option>
              </select>
            </label>
            <label class="card-add-field">
              Quantite
              <input type="number" class="card-add-qty" min="1" step="1" value="1">
            </label>
          </div>
          <p class="card-add-status muted">Commence par taper un nom de carte.</p>
        </div>
        <div class="card-add-actions">
          <button type="button" class="card-add-import">Importer...</button>
          <button type="button" class="card-add-cancel">Annuler</button>
          <button type="button" class="card-add-submit" disabled>Ajouter</button>
        </div>
      </div>
    `;
    document.body.appendChild(root);

    ADD_CARD_MODAL_STATE.root = root;
    ADD_CARD_MODAL_STATE.nameInput = root.querySelector(".card-add-name");
    ADD_CARD_MODAL_STATE.qtyInput = root.querySelector(".card-add-qty");
    ADD_CARD_MODAL_STATE.finishSelect = root.querySelector(".card-add-finish");
    ADD_CARD_MODAL_STATE.suggestionsWrap = root.querySelector(".card-add-suggestions");
    ADD_CARD_MODAL_STATE.printsWrap = root.querySelector(".card-add-print-list");
    ADD_CARD_MODAL_STATE.statusNode = root.querySelector(".card-add-status");
    ADD_CARD_MODAL_STATE.addButton = root.querySelector(".card-add-submit");
    ADD_CARD_MODAL_STATE.importButton = root.querySelector(".card-add-import");
    ADD_CARD_MODAL_STATE.cancelButton = root.querySelector(".card-add-cancel");
    ADD_CARD_MODAL_STATE.closeButton = root.querySelector(".card-add-close");

    ADD_CARD_MODAL_STATE.closeButton?.addEventListener("click", closeAddCardModal);
    ADD_CARD_MODAL_STATE.cancelButton?.addEventListener("click", closeAddCardModal);
    root.addEventListener("click", (event) => {
      if (event.target === root) {
        closeAddCardModal();
      }
    });

    ADD_CARD_MODAL_STATE.nameInput?.addEventListener("input", () => {
      scheduleAddCardAutocomplete();
    });

    ADD_CARD_MODAL_STATE.nameInput?.addEventListener("keydown", (event) => {
      if (event.key === "Enter") {
        event.preventDefault();
        const first = ADD_CARD_MODAL_STATE.suggestions[0];
        if (first) {
          ADD_CARD_MODAL_STATE.nameInput.value = first;
          ADD_CARD_MODAL_STATE.suggestions = [];
          renderAddCardSuggestions();
          loadAddCardPrintsByName(first);
        } else {
          const typed = String(ADD_CARD_MODAL_STATE.nameInput.value || "").trim();
          if (typed) {
            loadAddCardPrintsByName(typed);
          }
        }
      }
    });

    ADD_CARD_MODAL_STATE.suggestionsWrap?.addEventListener("click", (event) => {
      const button = event.target.closest("button[data-card-name]");
      if (!button) {
        return;
      }
      const cardName = String(button.dataset.cardName || "").trim();
      if (!cardName) {
        return;
      }
      ADD_CARD_MODAL_STATE.nameInput.value = cardName;
      ADD_CARD_MODAL_STATE.suggestions = [];
      renderAddCardSuggestions();
      loadAddCardPrintsByName(cardName);
    });

    ADD_CARD_MODAL_STATE.printsWrap?.addEventListener("click", (event) => {
      const button = event.target.closest("button[data-print-id]");
      if (!button) {
        return;
      }
      const printId = String(button.dataset.printId || "").trim();
      if (!printId || !ADD_CARD_MODAL_STATE.printsById.has(printId)) {
        return;
      }
      ADD_CARD_MODAL_STATE.selectedPrintId = printId;
      renderAddCardPrints();
      syncAddCardFinishOptions();
    });

    ADD_CARD_MODAL_STATE.addButton?.addEventListener("click", async () => {
      await submitAddCardFromModal();
    });

    ADD_CARD_MODAL_STATE.importButton?.addEventListener("click", async () => {
      const out = await runDbImportFlow();
      if (out?.canceled) {
        return;
      }
      if (!out || out.ok !== true) {
        setAddCardStatus(out?.error || "Import impossible.", true);
        return;
      }
      setAddCardStatus("Import termine.");
      closeAddCardModal();
    });

    window.addEventListener("keydown", (event) => {
      if (event.key === "Escape" && ADD_CARD_MODAL_STATE.root && !ADD_CARD_MODAL_STATE.root.classList.contains("hidden")) {
        closeAddCardModal();
      }
    });

    return ADD_CARD_MODAL_STATE;
  }

  function openAddCardModal(seedRow = null) {
    ensureAddCardModal();
    ADD_CARD_MODAL_STATE.root.classList.remove("hidden");
    ADD_CARD_MODAL_STATE.selectedPrintId = "";
    ADD_CARD_MODAL_STATE.printsById = new Map();
    ADD_CARD_MODAL_STATE.suggestions = [];
    renderAddCardSuggestions();
    renderAddCardPrints();
    setAddCardStatus("Tape un nom, puis choisis une extension.");
    ADD_CARD_MODAL_STATE.addButton.disabled = true;
    ADD_CARD_MODAL_STATE.qtyInput.value = "1";

    const seededName = seedRow ? readRowField(seedRow, ["name"]) : "";
    if (seededName) {
      ADD_CARD_MODAL_STATE.nameInput.value = seededName;
      loadAddCardPrintsByName(seededName);
    } else {
      ADD_CARD_MODAL_STATE.nameInput.value = "";
      ADD_CARD_MODAL_STATE.nameInput.focus();
      ADD_CARD_MODAL_STATE.nameInput.select();
    }
  }

  function closeAddCardModal() {
    if (!ADD_CARD_MODAL_STATE.root) {
      return;
    }
    ADD_CARD_MODAL_STATE.root.classList.add("hidden");
  }

  function setAddCardStatus(text, isError = false) {
    if (!ADD_CARD_MODAL_STATE.statusNode) {
      return;
    }
    ADD_CARD_MODAL_STATE.statusNode.textContent = String(text || "");
    ADD_CARD_MODAL_STATE.statusNode.classList.toggle("is-error", isError === true);
  }

  function scheduleAddCardAutocomplete() {
    if (ADD_CARD_MODAL_STATE.autocompleteTimer) {
      window.clearTimeout(ADD_CARD_MODAL_STATE.autocompleteTimer);
    }
    ADD_CARD_MODAL_STATE.autocompleteTimer = window.setTimeout(() => {
      runAddCardAutocomplete();
    }, 220);
  }

  async function fetchJsonSafe(url) {
    const response = await fetch(url, {
      headers: {
        Accept: "application/json"
      }
    });
    if (!response.ok) {
      return null;
    }
    return response.json().catch(() => null);
  }

  async function runAddCardAutocomplete() {
    const query = String(ADD_CARD_MODAL_STATE.nameInput?.value || "").trim();
    if (query.length < 2) {
      ADD_CARD_MODAL_STATE.suggestions = [];
      renderAddCardSuggestions();
      return;
    }

    const seq = ++ADD_CARD_MODAL_STATE.autocompleteSeq;
    const payload = await fetchJsonSafe(
      `https://api.scryfall.com/cards/autocomplete?q=${encodeURIComponent(query)}`
    );
    if (seq !== ADD_CARD_MODAL_STATE.autocompleteSeq) {
      return;
    }

    ADD_CARD_MODAL_STATE.suggestions = Array.isArray(payload?.data)
      ? payload.data.slice(0, 10)
      : [];
    renderAddCardSuggestions();
  }

  function renderAddCardSuggestions() {
    const wrap = ADD_CARD_MODAL_STATE.suggestionsWrap;
    if (!wrap) {
      return;
    }
    const items = Array.isArray(ADD_CARD_MODAL_STATE.suggestions)
      ? ADD_CARD_MODAL_STATE.suggestions
      : [];
    if (items.length === 0) {
      wrap.innerHTML = "";
      return;
    }
    wrap.innerHTML = `
      <div class="card-add-suggestion-list">
        ${items.map((item) => (
          `<button type="button" class="card-add-suggestion" data-card-name="${escapeHtml(String(item))}">${escapeHtml(String(item))}</button>`
        )).join("")}
      </div>
    `;
  }

  function normalizeScryfallPrint(card) {
    if (!card || card.object !== "card" || !card.id) {
      return null;
    }
    const setCode = String(card.set || "").toUpperCase();
    return {
      id: String(card.id),
      name: String(card.name || ""),
      setCode,
      setName: String(card.set_name || ""),
      collectorNumber: String(card.collector_number || ""),
      rarity: String(card.rarity || ""),
      language: String(card.lang || "en"),
      releasedAt: String(card.released_at || ""),
      finishes: Array.isArray(card.finishes) ? card.finishes.slice() : [],
      iconUrl: setCode ? `https://svgs.scryfall.io/sets/${encodeURIComponent(setCode.toLowerCase())}.svg` : "",
      imageUrl: card?.image_uris?.small || card?.image_uris?.normal || ""
    };
  }

  async function loadAddCardPrintsByName(cardName) {
    const name = String(cardName || "").trim();
    if (!name) {
      ADD_CARD_MODAL_STATE.printsById = new Map();
      ADD_CARD_MODAL_STATE.selectedPrintId = "";
      renderAddCardPrints();
      setAddCardStatus("Entre un nom de carte.");
      return;
    }

    const seq = ++ADD_CARD_MODAL_STATE.printsSeq;
    setAddCardStatus(`Recherche des editions pour "${name}"...`);
    ADD_CARD_MODAL_STATE.addButton.disabled = true;

    const escapedName = name.replace(/"/g, "\\\"");
    const query = `!"${escapedName}"`;
    const payload = await fetchJsonSafe(
      `https://api.scryfall.com/cards/search?q=${encodeURIComponent(query)}&unique=prints&order=released&dir=desc`
    );
    if (seq !== ADD_CARD_MODAL_STATE.printsSeq) {
      return;
    }
    if (!payload || !Array.isArray(payload.data)) {
      ADD_CARD_MODAL_STATE.printsById = new Map();
      ADD_CARD_MODAL_STATE.selectedPrintId = "";
      renderAddCardPrints();
      setAddCardStatus("Scryfall indisponible ou aucune edition trouvee.", true);
      ADD_CARD_MODAL_STATE.addButton.disabled = true;
      return;
    }

    const cards = payload.data;
    const map = new Map();
    cards.forEach((card) => {
      const normalized = normalizeScryfallPrint(card);
      if (!normalized) {
        return;
      }
      if (!map.has(normalized.id)) {
        map.set(normalized.id, normalized);
      }
    });

    ADD_CARD_MODAL_STATE.printsById = map;
    const first = map.keys().next();
    ADD_CARD_MODAL_STATE.selectedPrintId = first && !first.done ? String(first.value) : "";

    renderAddCardPrints();
    syncAddCardFinishOptions();
    if (map.size === 0) {
      setAddCardStatus("Aucune edition trouvee.", true);
      ADD_CARD_MODAL_STATE.addButton.disabled = true;
    } else {
      setAddCardStatus(`${map.size} editions trouvees. Choisis une extension.`);
      ADD_CARD_MODAL_STATE.addButton.disabled = false;
    }
  }

  function renderAddCardPrints() {
    const wrap = ADD_CARD_MODAL_STATE.printsWrap;
    if (!wrap) {
      return;
    }
    const prints = Array.from(ADD_CARD_MODAL_STATE.printsById.values());
    if (prints.length === 0) {
      wrap.innerHTML = '<p class="muted">Aucune edition chargee pour le moment.</p>';
      return;
    }

    wrap.innerHTML = prints.map((print) => {
      const active = print.id === ADD_CARD_MODAL_STATE.selectedPrintId ? "is-active" : "";
      const subtitle = `${print.setName} (${print.setCode}) #${print.collectorNumber} | ${print.language.toUpperCase()} | ${print.rarity}`;
      return `
        <button type="button" class="card-add-print-option ${active}" data-print-id="${escapeHtml(print.id)}">
          <span class="card-add-print-icon-wrap">
            ${print.iconUrl ? `<img class="card-add-print-icon" src="${escapeHtml(print.iconUrl)}" alt="${escapeHtml(print.setCode)}">` : `<span class="card-add-print-icon-fallback">${escapeHtml(print.setCode || "?")}</span>`}
          </span>
          <span class="card-add-print-meta">
            <span class="card-add-print-name">${escapeHtml(print.name)}</span>
            <span class="card-add-print-line">${escapeHtml(subtitle)}</span>
          </span>
        </button>
      `;
    }).join("");
  }

  function syncAddCardFinishOptions() {
    const select = ADD_CARD_MODAL_STATE.finishSelect;
    if (!select) {
      return;
    }
    const selected = ADD_CARD_MODAL_STATE.printsById.get(ADD_CARD_MODAL_STATE.selectedPrintId);
    const finishes = Array.isArray(selected?.finishes) ? selected.finishes : [];
    const hasNormal = finishes.includes("nonfoil") || finishes.length === 0;
    const hasFoil = finishes.includes("foil");
    const options = [];
    if (hasNormal) {
      options.push("normal");
    }
    if (hasFoil) {
      options.push("foil");
    }
    if (options.length === 0) {
      options.push("normal");
    }
    select.innerHTML = options.map((value) => (
      `<option value="${value}">${value}</option>`
    )).join("");
  }

  async function submitAddCardFromModal() {
    const selected = ADD_CARD_MODAL_STATE.printsById.get(ADD_CARD_MODAL_STATE.selectedPrintId);
    if (!selected) {
      setAddCardStatus("Choisis une extension avant d'ajouter.", true);
      return;
    }

    const quantityRaw = String(ADD_CARD_MODAL_STATE.qtyInput?.value || "1").trim();
    const quantityNum = Number.parseInt(quantityRaw, 10);
    const quantity = Number.isFinite(quantityNum) && quantityNum > 0 ? quantityNum : 1;
    const finish = String(ADD_CARD_MODAL_STATE.finishSelect?.value || "normal").trim() || "normal";

    ADD_CARD_MODAL_STATE.addButton.disabled = true;
    setAddCardStatus("Ajout en cours...");
    const out = await addCardToCollectionDb({
      name: selected.name,
      quantity: String(quantity),
      set_code: selected.setCode,
      set_name: selected.setName,
      collector_number: selected.collectorNumber,
      rarity: selected.rarity,
      language: selected.language,
      scryfall_id: selected.id,
      foil: finish
    }, getConfiguredCollectionDbPath(), true);

    if (!out || out.ok !== true) {
      setAddCardStatus(out?.error || "Ajout impossible.", true);
      ADD_CARD_MODAL_STATE.addButton.disabled = false;
      return;
    }

    setAddCardStatus("Carte ajoutee.");
    closeAddCardModal();
    await loadDefaultDbCollectionIntoTable();
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
    attachDbActionEvents();
    bindStrategyControls();
    bindSpellbookControls();
    bindDeckAnalysisControls();
    loadDeckStateFromStorage();

    nodes.collections.form.addEventListener("submit", async (event) => {
      event.preventDefault();

      const selected = nodes.collections.fileInput.files && nodes.collections.fileInput.files[0];
      if (!selected) {
        renderCollection({
          ok: false,
          table: "Collections",
          error: "Selectionne un fichier."
        });
        return;
      }

      const sourceType = inferCollectionSourceType(selected.name);
      if (sourceType === "db") {
        const targetDbPath = getConfiguredCollectionDbPath();
        const out = await importIntoCollectionDb(selected, targetDbPath, "db", "collection", true);
        if (!out || out.ok !== true) {
          renderCollection({
            ok: false,
            table: "Collections",
            error: out?.error || "Import DB impossible"
          });
          return;
        }
        await loadDefaultDbCollectionIntoTable(targetDbPath);
      } else if (sourceType === "csv") {
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
        setSavedSelectedCollectionId(state.selectedCollectionId);
        setCollectionSourcePreference("store");
        renderCollectionsList("");
        renderActiveTabTable();
        if (state.selectedCollectionId) {
          await loadStoredCollectionIntoTable(state.selectedCollectionId);
        }
      } else {
        const payload = await uploadCollection(selected, "text", "");
        if (!payload || payload.ok !== true) {
          renderCollection(payload || {
            ok: false,
            table: "Collections",
            error: "Chargement impossible"
          });
          return;
        }
        renderCollection(payloadForNamedView(
          payload,
          selected.name || "Collection",
          selected.name || "collection/upload",
          "cards",
          "collections"
        ));
        setCollectionSourcePreference("store");
      }

      nodes.collections.nameInput.value = "";
      nodes.collections.fileInput.value = "";
      setCollectionPickButtonLabel("Choisir fichier collection");
      nodes.collections.pickFileButton.classList.remove("has-file");
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
      const inferredName = inferDeckNameFromFile(selected.name);
      const deckName = rawName || inferredName || `Deck ${state.decks.length + 1}`;
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
    const sourcePref = getCollectionSourcePreference();
    if (sourcePref === "db") {
      const loadedDb = await loadDefaultDbCollectionIntoTable();
      if (!loadedDb && state.selectedCollectionId) {
        setCollectionSourcePreference("store");
        await loadStoredCollectionIntoTable(state.selectedCollectionId);
      }
    } else if (state.selectedCollectionId) {
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
