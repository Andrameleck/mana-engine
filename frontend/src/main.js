import {
  uploadCollection,
  importCollectionCsv,
  listStoredCollections,
  getStoredCollection,
  deleteStoredCollection,
  fetchLotusNoirPosts as fetchLotusNoirPostsApi,
  fetchSpellbookVariants,
  fetchSynergyFind,
  startSynergyJob,
  fetchSynergyJobStatus
} from "./api.js";
import {
  renderCollection,
  getCollectionLanguage,
  setCollectionLanguage,
  bindRowPreviewEvents,
  renderManaCostCell
} from "./ui.js";

(function bootstrap() {
  const UI_TEXT = {
    en: {
      tabs_collections: "Collections",
      tabs_decks: "Decks",
      tabs_strategy: "Strategy",
      tabs_spellbook: "Spellbook",
      subtitle_collections: "Create and manage multiple collection folders.",
      subtitle_decks: "Import and browse multiple decks.",
      subtitle_strategy: "Workspace for synergy and combo exploration.",
      subtitle_spellbook: "Query Commander Spellbook by card name.",
      pick_csv: "Choose CSV",
      pick_deck_file: "Choose deck file",
      open: "Open",
      delete: "Delete",
      folder: "Folder",
      rows: "rows",
      decks_empty: "No deck yet.",
      collections_empty: "No collection folder yet.",
      load_collections_error: "Unable to load folders.",
      table_no_data: "No data loaded.",
      table_no_data_available: "No data",
      strategy_waiting: "Waiting for computation.",
      strategy_no_result: "No result.",
      strategy_run_hint_direct: "Run a computation to see direct synergies.",
      strategy_run_hint_group: "Run a computation to see card groups.",
      strategy_choose_seed: "Choose a seed card then click Compute.",
      strategy_source_unavailable: "Select a loaded collection folder to enable computation.",
      strategy_seed_placeholder: "Seed card (ex: Entomb).",
      strategy_preview_hint: "Hover or select a synergy card to display details.",
      strategy_preview_oracle_fallback: "No Oracle text available.",
      spellbook_hint: "Type a card name to query Commander Spellbook.",
      spellbook_none: "No result.",
      spellbook_card_label: "Card name",
      spellbook_limit_label: "Limit",
      spellbook_search: "Search",
      compute: "Compute",
      strategy_seed_label: "Seed card",
      strategy_direct_limit_label: "Top direct synergies",
      strategy_group_limit_label: "Top groups",
      strategy_include_spellbook_label: "Include combo references (Commander Spellbook)",
      strategy_include_spellbook_hint: "Prioritize cards present in public combos (adds a score bonus)",
      strategy_include_lotus_hint: "Cross-check with LotusNoir community decks (beta)",
      strategy_only_collection_hint: "Restrict the calculator to cards from the loaded collection",
      strategy_mana_filter_label: "Mana filter (allowed colors)",
      direct_synergies: "Direct synergies",
      card_groups: "Card groups",
      collection_name_label: "Folder name",
      deck_name_label: "Deck name",
      new_collection_folder: "New collection folder",
      collections_folders: "Collection folders",
      import_deck: "Import deck",
      decks_list: "Deck list",
      source_meta_waiting: "Select a collection folder to enable computation.",
      create_folder: "Create folder",
      add_deck: "Add deck"
    },
    fr: {
      tabs_collections: "Collections",
      tabs_decks: "Decks",
      tabs_strategy: "Strategy",
      tabs_spellbook: "Spellbook",
      subtitle_collections: "Creer et gerer plusieurs dossiers de collection.",
      subtitle_decks: "Importer et visualiser plusieurs decks.",
      subtitle_strategy: "Zone reservee au module de strategies.",
      subtitle_spellbook: "Interroger Commander Spellbook par nom de carte.",
      pick_csv: "Choisir CSV",
      pick_deck_file: "Choisir un fichier deck",
      open: "Ouvrir",
      delete: "Supprimer",
      folder: "Dossier",
      rows: "lignes",
      decks_empty: "Aucun deck pour le moment.",
      collections_empty: "Aucun dossier collection pour le moment.",
      load_collections_error: "Impossible de charger les dossiers.",
      table_no_data: "Aucune donnee chargee.",
      table_no_data_available: "Aucune donnee",
      strategy_waiting: "En attente de calcul.",
      strategy_no_result: "Aucun resultat.",
      strategy_run_hint_direct: "Lance un calcul pour voir les synergies directes.",
      strategy_run_hint_group: "Lance un calcul pour voir les groupes de cartes.",
      strategy_choose_seed: "Choisis une carte seed puis clique sur Calculer.",
      strategy_source_unavailable: "Selectionne un dossier collection charge pour activer le calcul.",
      strategy_seed_placeholder: "Carte seed (ex: Entomb).",
      strategy_preview_hint: "Survole ou selectionne une carte de synergie pour afficher ses details.",
      strategy_preview_oracle_fallback: "Aucun texte Oracle disponible.",
      spellbook_hint: "Saisis une carte pour interroger Commander Spellbook.",
      spellbook_none: "Aucun resultat.",
      spellbook_card_label: "Nom de carte",
      spellbook_limit_label: "Limite",
      spellbook_search: "Rechercher",
      compute: "Calculer",
      strategy_seed_label: "Carte seed",
      strategy_direct_limit_label: "Top synergies directes",
      strategy_group_limit_label: "Top groupes",
      strategy_include_spellbook_label: "Inclure reference combos (Commander Spellbook)",
      strategy_include_spellbook_hint: "Prioriser les cartes presentes dans les combos publics (ajoute un bonus de score)",
      strategy_include_lotus_hint: "Croiser avec les decks communautaires LotusNoir (beta)",
      strategy_only_collection_hint: "Limiter le calcul aux cartes de la collection chargee",
      strategy_mana_filter_label: "Filtre mana (couleurs autorisees)",
      direct_synergies: "Synergies directes",
      card_groups: "Groupes de cartes",
      collection_name_label: "Nom du dossier",
      deck_name_label: "Nom du deck",
      new_collection_folder: "Nouveau dossier collection",
      collections_folders: "Dossiers collections",
      import_deck: "Import deck",
      decks_list: "Decks list",
      source_meta_waiting: "Selectionne un dossier collection pour activer le calcul.",
      create_folder: "Creer le dossier",
      add_deck: "Ajouter le deck"
    }
  };

  function currentUiLanguage() {
    return getCollectionLanguage() === "fr" ? "fr" : "en";
  }

  function t(key) {
    const lang = currentUiLanguage();
    return UI_TEXT[lang]?.[key] || UI_TEXT.fr?.[key] || key;
  }

  function tabMetaFor(tabId) {
    return {
      collections: {
        title: t("tabs_collections"),
        subtitle: t("subtitle_collections")
      },
      decks: {
        title: t("tabs_decks"),
        subtitle: t("subtitle_decks")
      },
      strategy: {
        title: t("tabs_strategy"),
        subtitle: t("subtitle_strategy")
      },
      spellbook: {
        title: t("tabs_spellbook"),
        subtitle: t("subtitle_spellbook")
      }
    }[tabId] || {
      title: t("tabs_collections"),
      subtitle: t("subtitle_collections")
    };
  }

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
      includeKnownCards: true,
      includeSpellbookCombos: true,
      includeLotusSignals: false,
      useCollectionOnly: false,
      knownCardsModel: null,
      knownCardsModelKey: "",
      knownCardsModelPromise: null,
      knownCardsModelPromiseKey: "",
      knownCardsError: "",
      spellbookCache: new Map(),
      spellbookPromiseCache: new Map(),
      lotusCache: new Map(),
      lotusPromiseCache: new Map(),
      namedCardCache: new Map(),
      namedCardPromiseCache: new Map(),
      seedAutocompleteCache: new Map(),
      seedAutocompleteToken: 0,
      spellbookError: "",
      lotusError: "",
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
  const DECK_STATS_STATE = {
    requestToken: 0,
    metadataCache: new Map()
  };
  const DECK_ANALYSIS_STATE = {
    requestToken: 0,
    activePane: "stats"
  };
  const STRATEGY_PREVIEW_STATE = {
    activeElement: null,
    requestToken: 0,
    cache: new Map()
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
      includeSpellbookInput: document.getElementById("strategy-include-spellbook"),
      includeLotusInput: document.getElementById("strategy-include-lotus"),
      onlyCollectionInput: document.getElementById("strategy-only-collection"),
      manaFilterInputs: Array.from(document.querySelectorAll("input[data-strategy-mana]")),
      runButton: document.getElementById("strategy-run-btn"),
      status: document.getElementById("strategy-status"),
      directList: document.getElementById("strategy-direct-list"),
      groupList: document.getElementById("strategy-group-list"),
      previewTitle: document.getElementById("strategy-card-preview-title"),
      previewText: document.getElementById("strategy-card-preview-text"),
      previewImage: document.getElementById("strategy-card-preview-image"),
      previewMeta: document.getElementById("strategy-card-preview-meta")
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

  function applyStaticUiTranslations() {
    document.documentElement.setAttribute("lang", currentUiLanguage());

    const tabLabels = {
      collections: t("tabs_collections"),
      decks: t("tabs_decks"),
      strategy: t("tabs_strategy"),
      spellbook: t("tabs_spellbook")
    };
    nodes.tabButtons.forEach((button) => {
      const tabId = String(button?.dataset?.tab || "");
      const label = tabLabels[tabId] || tabLabels.collections;
      button.setAttribute("aria-label", label);
      button.setAttribute("title", label);
      const hidden = button.querySelector(".visually-hidden");
      if (hidden) {
        hidden.textContent = label;
      }
    });

    const setText = (selector, text) => {
      const node = document.querySelector(selector);
      if (node) {
        node.textContent = text;
      }
    };
    const setPlaceholder = (selector, text) => {
      const node = document.querySelector(selector);
      if (node) {
        node.setAttribute("placeholder", text);
      }
    };

    setText("#tab-collections .panel-head h3", t("new_collection_folder"));
    setText("#tab-collections .panel.panel-compact:nth-of-type(2) .panel-head h3", t("collections_folders"));
    setText("#tab-decks .panel-head h3", t("import_deck"));
    setText("#tab-decks .deck-list-panel .panel-head h3", t("decks_list"));
    setText("#tab-strategy .panel-head h3", "Synergy Finder");
    setText("#tab-strategy #strategy-status", t("strategy_waiting"));
    setText("#strategy-seed-label", t("strategy_seed_label"));
    setText("#strategy-direct-limit-label", t("strategy_direct_limit_label"));
    setText("#strategy-group-limit-label", t("strategy_group_limit_label"));
    setText("#strategy-include-spellbook-label", t("strategy_include_spellbook_label"));
    setText("#strategy-include-spellbook-hint", t("strategy_include_spellbook_hint"));
    setText("#strategy-include-lotus-hint", t("strategy_include_lotus_hint"));
    setText("#strategy-only-collection-hint", t("strategy_only_collection_hint"));
    setText("#strategy-mana-filter-label", t("strategy_mana_filter_label"));
    setText("#tab-strategy .strategy-result-block:nth-of-type(1) .strategy-result-head h4", t("direct_synergies"));
    setText("#tab-strategy .strategy-result-block:nth-of-type(2) .strategy-result-head h4", t("card_groups"));
    setText("#tab-spellbook .panel-head h3", "Commander Spellbook Lookup");
    setText("#spellbook-run-btn", t("spellbook_search"));
    setText("#strategy-run-btn", t("compute"));
    setText("#strategy-source-meta", t("source_meta_waiting"));
    setText("#strategy-card-preview-text", t("strategy_preview_hint"));
    setText("#spellbook-status", t("spellbook_hint"));

    setPlaceholder("#strategy-seed-input", "Entomb");
    setPlaceholder("#spellbook-card-input", "Entomb");

    const tableSummary = document.getElementById("load-summary");
    if (tableSummary && (!tableSummary.textContent || tableSummary.textContent === "No data loaded." || tableSummary.textContent === "Aucune donnee chargee.")) {
      tableSummary.textContent = t("table_no_data");
    }
  }

  function onLanguageSelect(language) {
    setCollectionLanguage(language);
    applyLanguageButtonState(language);
    applyStaticUiTranslations();
    resetStrategyKnownCardsCache();
    renderCollectionsList("");
    renderDecksList();
    selectTab(state.activeTab);
    renderSpellbookPanel();
  }

  function bindCollectionPicker() {
    nodes.collections.fileInput.accept = ".csv,.txt";
    const defaultPickLabel = t("pick_csv");
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
    const text = String(label || t("pick_csv"));
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
    const defaultPickLabel = t("pick_deck_file");
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
    const text = String(label || t("pick_deck_file"));
    button.title = text;
    button.setAttribute("aria-label", text);
  }

  function bindStrategyControls() {
    const strategyNodes = nodes.strategy;
    if (!strategyNodes.seedInput || !strategyNodes.runButton) {
      return;
    }

    if (strategyNodes.seedList) {
      strategyNodes.seedInput.setAttribute("list", "strategy-seed-list");
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

    if (strategyNodes.includeLotusInput) {
      strategyNodes.includeLotusInput.checked = isStrategyIncludeLotusEnabled();
      strategyNodes.includeLotusInput.addEventListener("change", () => {
        state.strategy.includeLotusSignals = strategyNodes.includeLotusInput.checked === true;
        resetStrategyLotusCache();
        const collectionId = state.selectedCollectionId;
        const payload = collectionId ? state.collectionPayloadById[collectionId] : null;
        const meta = state.collections.find((entry) => entry.id === collectionId);
        renderStrategyPanel(payload, meta);
      });
    }

    if (strategyNodes.onlyCollectionInput) {
      strategyNodes.onlyCollectionInput.checked = isStrategyUseCollectionOnlyEnabled();
      strategyNodes.onlyCollectionInput.addEventListener("change", () => {
        state.strategy.useCollectionOnly = strategyNodes.onlyCollectionInput.checked === true;
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
      const query = String(strategyNodes.seedInput.value || "").trim();
      state.strategy.seedName = query;
      updateStrategySeedAutocomplete(query);
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

  function selectTab(tabId) {
    state.activeTab = tabId;

    nodes.tabButtons.forEach((button) => {
      button.classList.toggle("is-active", button.dataset.tab === tabId);
    });
    nodes.tabViews.forEach((view) => {
      view.classList.toggle("is-active", view.id === `tab-${tabId}`);
    });

    const meta = tabMetaFor(tabId);
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
      renderCollectionsList(payload?.error || t("load_collections_error"));
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
      list.innerHTML = `<p class="muted">${escapeHtml(t("collections_empty"))}</p>`;
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
            <p class="entity-item-name">${escapeHtml(t("folder"))}: ${escapeHtml(entry.name || entry.id)}</p>
            <p class="entity-item-meta">${escapeHtml(platform)} | ${escapeHtml(String(rowCount))} ${escapeHtml(t("rows"))} | ${escapeHtml(createdAt)}</p>
          </div>
          <div class="entity-actions">
            <button type="button" class="entity-select" data-action="select">${escapeHtml(t("open"))}</button>
            <button type="button" class="entity-delete" data-action="delete">${escapeHtml(t("delete"))}</button>
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
      list.innerHTML = `<p class="muted">${escapeHtml(t("decks_empty"))}</p>`;
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
          <button type="button" class="deck-icon-open" data-action="select" aria-label="${escapeHtml(t("open"))} ${deckName}" title="${escapeHtml(t("open"))} ${deckName}">
            <span class="deck-icon-glyph">${glyph}</span>
          </button>
          <button type="button" class="deck-icon-delete" data-action="delete" aria-label="${escapeHtml(t("delete"))} ${deckName}" title="${escapeHtml(t("delete"))} ${deckName}">
            <svg viewBox="0 0 24 24" class="deck-icon-delete-svg" aria-hidden="true">
              <path d="M6 7h12"></path>
              <path d="M9 7V5h6v2"></path>
              <path d="M8 7l1 12h6l1-12"></path>
            </svg>
          </button>
          <p class="deck-icon-name">${deckName}</p>
          <p class="deck-icon-meta">${escapeHtml(String(rowCount))} ${escapeHtml(t("rows"))}</p>
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
      if (!state.selectedCollectionId) {
        renderCollection({
          ok: false,
          table: t("tabs_collections"),
          error: currentUiLanguage() === "fr" ? "Aucun dossier selectionne." : "No folder selected."
        });
        renderDeckStatsPanel(null);
        return;
      }

      const meta = state.collections.find((entry) => entry.id === state.selectedCollectionId);
      const payload = state.collectionPayloadById[state.selectedCollectionId];
      if (!payload) {
        renderCollection({
          ok: false,
          table: meta?.name || t("tabs_collections"),
          error: currentUiLanguage() === "fr" ? "Chargement du dossier en cours..." : "Loading folder..."
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
          table: t("tabs_decks"),
          error: currentUiLanguage() === "fr" ? "Aucun deck selectionne." : "No deck selected."
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
          table: t("tabs_strategy"),
          error: currentUiLanguage() === "fr"
            ? "Mode sans collection: utilise une seed libre, puis calcul via Scryfall."
            : "No-collection mode: use a free seed, then compute via Scryfall."
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
      table: t("tabs_collections"),
      error: currentUiLanguage() === "fr" ? "Selectionne un onglet disponible." : "Select an available tab."
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

    const hasCollectionPayload = Boolean(payload && payload.ok === true);
    const collectionName = collectionMeta?.name || "Collection";
    const model = hasCollectionPayload
      ? getStrategyModelForCollection(state.selectedCollectionId, payload)
      : { cards: [] };
    const includeKnown = isStrategyIncludeKnownEnabled();
    if (!hasCollectionPayload) {
      strategyNodes.sourceMeta.textContent = currentUiLanguage() === "fr"
        ? "Mode seed libre: Scryfall uniquement (aucune collection chargee)."
        : "Free-seed mode: Scryfall only (no loaded collection).";
    } else if (includeKnown) {
      const knownCount = Array.isArray(state.strategy.knownCardsModel?.cards)
        ? state.strategy.knownCardsModel.cards.length
        : 0;
      if (knownCount > 0) {
        strategyNodes.sourceMeta.textContent = currentUiLanguage() === "fr"
          ? `${collectionName} | ${model.cards.length} cartes collection + ${knownCount} cartes via Scryfall (seed libre)`
          : `${collectionName} | ${model.cards.length} collection cards + ${knownCount} cards via Scryfall (free seed)`;
      } else if (state.strategy.knownCardsError) {
        strategyNodes.sourceMeta.textContent = currentUiLanguage() === "fr"
          ? `${collectionName} | ${model.cards.length} cartes collection (Scryfall indisponible)`
          : `${collectionName} | ${model.cards.length} collection cards (Scryfall unavailable)`;
      } else {
        strategyNodes.sourceMeta.textContent = currentUiLanguage() === "fr"
          ? `${collectionName} | ${model.cards.length} cartes collection (+ seed/cartes via Scryfall au calcul)`
          : `${collectionName} | ${model.cards.length} collection cards (+ seed/cards via Scryfall at compute time)`;
      }
    } else {
      strategyNodes.sourceMeta.textContent = `${collectionName} | ${model.cards.length} cartes analysees`;
    }

    const currentCollectionChanged = state.strategy.lastCollectionId !== state.selectedCollectionId;
    state.strategy.lastCollectionId = state.selectedCollectionId;

    if (currentCollectionChanged) {
      state.strategy.seedName = "";
      strategyNodes.seedInput.value = "";
      strategyNodes.directList.innerHTML = `<p class="muted">${escapeHtml(t("strategy_run_hint_direct"))}</p>`;
      strategyNodes.groupList.innerHTML = `<p class="muted">${escapeHtml(t("strategy_run_hint_group"))}</p>`;
      strategyNodes.status.textContent = hasCollectionPayload
        ? t("strategy_choose_seed")
        : (currentUiLanguage() === "fr"
            ? "Saisis une carte seed puis clique sur Calculer (mode sans collection)."
            : "Type a seed card then click Compute (no-collection mode).");
      resetStrategyCardPreview();
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

    renderStrategySeedDatalist(model.cards, [], "");
  }

  function resetStrategyCardPreview() {
    const strategyNodes = nodes.strategy;
    if (strategyNodes.previewTitle) {
      strategyNodes.previewTitle.textContent = currentUiLanguage() === "fr" ? "Carte" : "Card";
    }
    if (strategyNodes.previewText) {
      strategyNodes.previewText.textContent = t("strategy_preview_hint");
    }
    if (strategyNodes.previewImage) {
      strategyNodes.previewImage.removeAttribute("src");
      strategyNodes.previewImage.classList.add("is-hidden");
      strategyNodes.previewImage.alt = "Card preview";
    }
    if (strategyNodes.previewMeta) {
      strategyNodes.previewMeta.innerHTML = "";
    }
    if (STRATEGY_PREVIEW_STATE.activeElement) {
      STRATEGY_PREVIEW_STATE.activeElement.classList.remove("is-selected");
    }
    STRATEGY_PREVIEW_STATE.activeElement = null;
  }

  function renderStrategyCardPreview(card, cardElement = null) {
    const strategyNodes = nodes.strategy;
    const titleNode = strategyNodes.previewTitle;
    const textNode = strategyNodes.previewText;
    const imageNode = strategyNodes.previewImage;
    const metaNode = strategyNodes.previewMeta;
    if (!titleNode || !textNode || !imageNode || !metaNode) {
      return;
    }

    if (STRATEGY_PREVIEW_STATE.activeElement && STRATEGY_PREVIEW_STATE.activeElement !== cardElement) {
      STRATEGY_PREVIEW_STATE.activeElement.classList.remove("is-selected");
    }
    if (cardElement) {
      cardElement.classList.add("is-selected");
      STRATEGY_PREVIEW_STATE.activeElement = cardElement;
    }

    const cardName = String(card?.name || "").trim() || (currentUiLanguage() === "fr" ? "Carte" : "Card");
    const oracle = rowValue(card?.row, ["oracle_text", "printed_text", "card_text", "rules_text", "description"]);
    const setCode = rowValue(card?.row, ["set_code", "set"]).toUpperCase();
    const collector = rowValue(card?.row, ["collector_number"]);
    const mana = rowValue(card?.row, ["mana_cost", "manacost", "mana"]);
    const typeLine = rowValue(card?.row, ["type_line"]);
    const source = strategySourceBadgeText(card?.source || "collection") || "Collection";
    const sourceValue = source.replace(/^source\s*:\s*/i, "").trim() || source;
    const scryfallId = String(card?.scryfallId || rowValue(card?.row, ["scryfall_id", "scry_fall_id"])).trim();

    titleNode.textContent = cardName;
    textNode.innerHTML = strategyOracleTextToHtml(oracle || t("strategy_preview_oracle_fallback"));

    const previewImageUrl = scryfallCdnImageUrl(scryfallId, "normal");
    if (previewImageUrl) {
      imageNode.src = previewImageUrl;
      imageNode.alt = `Apercu ${cardName}`;
      imageNode.classList.remove("is-hidden");
    } else {
      imageNode.removeAttribute("src");
      imageNode.alt = `Apercu ${cardName}`;
      imageNode.classList.add("is-hidden");
    }

    const metaParts = [
      ["source", sourceValue],
      ["type", typeLine],
      ["mana", mana],
      ["set", [setCode, collector ? `#${collector}` : ""].filter(Boolean).join(" ")],
      ["scryfall_id", scryfallId]
    ].filter((entry) => String(entry[1] || "").trim().length > 0);

    metaNode.innerHTML = "";
    metaParts.forEach(([key, value]) => {
      const dt = document.createElement("dt");
      dt.textContent = strategyMetaLabel(key);
      const dd = document.createElement("dd");
      if (key === "mana") {
        dd.innerHTML = strategyManaValueToHtml(value);
      } else {
        dd.textContent = String(value);
      }
      metaNode.appendChild(dt);
      metaNode.appendChild(dd);
    });

    const requestToken = ++STRATEGY_PREVIEW_STATE.requestToken;
    loadStrategyPreviewCardForLanguage(card, getCollectionLanguage())
      .then((localizedCard) => {
        if (!localizedCard || requestToken !== STRATEGY_PREVIEW_STATE.requestToken) {
          return;
        }
        const localizedName = String(localizedCard?.printed_name || localizedCard?.name || cardName).trim();
        const localizedText = String(localizedCard?.printed_text || localizedCard?.oracle_text || "").trim();
        const localizedImage = String(localizedCard?.image_uris?.normal || "").trim();

        if (localizedName) {
          titleNode.textContent = localizedName;
        }
        if (localizedText) {
          textNode.innerHTML = strategyOracleTextToHtml(localizedText);
        }
        if (localizedImage) {
          imageNode.src = localizedImage;
          imageNode.classList.remove("is-hidden");
        }
      })
      .catch(() => {
        // keep fallback row data if localization fetch fails
      });
  }

  function strategyMetaLabel(key) {
    const normalized = String(key || "").trim().toLowerCase();
    const labels = currentUiLanguage() === "fr"
      ? {
          source: "Source",
          type: "Type",
          mana: "Mana",
          set: "Edition",
          scryfall_id: "Scryfall ID"
        }
      : {
          source: "Source",
          type: "Type",
          mana: "Mana",
          set: "Set",
          scryfall_id: "Scryfall ID"
        };
    return labels[normalized] || normalized;
  }

  function strategyManaValueToHtml(value) {
    const raw = String(value || "").trim();
    if (!raw) {
      return "";
    }
    const manaMatches = raw.match(/\{[^}]+\}/g) || [];
    if (manaMatches.length === 0) {
      return escapeHtml(raw);
    }
    const manaIcons = manaMatches
      .map((chunk) => {
        const token = chunk.slice(1, -1).trim().toUpperCase();
        const iconUrl = strategyManaSymbolIconUrl(token);
        if (!iconUrl) {
          return `<span class="strategy-mana-symbol is-fallback">${escapeHtml(token)}</span>`;
        }
        return `<span class="strategy-mana-symbol"><img src="${iconUrl}" alt="${escapeHtml(token)}" loading="lazy"></span>`;
      })
      .join("");
    return `<span class="strategy-mana-inline" title="${escapeHtml(raw)}">${manaIcons}</span>`;
  }

  function strategyOracleTextToHtml(value) {
    const raw = String(value || "").trim();
    if (!raw) {
      return "";
    }
    const parts = raw.split(/(\{[^}]+\})/g).filter(Boolean);
    return parts.map((part) => {
      if (/^\{[^}]+\}$/.test(part)) {
        const token = part.slice(1, -1).trim().toUpperCase();
        const iconUrl = strategyManaSymbolIconUrl(token);
        if (!iconUrl) {
          return `<span class="strategy-mana-symbol is-fallback">${escapeHtml(token)}</span>`;
        }
        return `<span class="strategy-mana-symbol"><img src="${iconUrl}" alt="${escapeHtml(token)}" loading="lazy"></span>`;
      }
      return escapeHtml(part).replace(/\n/g, "<br>");
    }).join("");
  }

  function strategyManaSymbolIconUrl(symbol) {
    let code = String(symbol || "").toUpperCase().trim();
    if (!code) {
      return "";
    }
    code = code.replace(/\s+/g, "");
    code = code.replace(/\//g, "");
    code = code.replace(/∞/g, "INFINITY");
    code = code.replace(/½/g, "HALF");
    if (!/^[A-Z0-9]+$/.test(code)) {
      return "";
    }
    return `https://svgs.scryfall.io/card-symbols/${code}.svg`;
  }

  async function loadStrategyPreviewCardForLanguage(card, language) {
    const scryfallId = String(card?.scryfallId || rowValue(card?.row, ["scryfall_id", "scry_fall_id"]) || "").trim();
    const cardName = String(card?.name || "").trim();
    const lang = String(language || "en").trim().toLowerCase();
    const cacheKey = `${scryfallId || cardName}::${lang}`;
    if (!cacheKey || cacheKey === "::") {
      return null;
    }
    if (STRATEGY_PREVIEW_STATE.cache.has(cacheKey)) {
      return STRATEGY_PREVIEW_STATE.cache.get(cacheKey);
    }

    const task = resolveStrategyPreviewCardForLanguage(scryfallId, cardName, lang)
      .catch(() => null);
    STRATEGY_PREVIEW_STATE.cache.set(cacheKey, task);
    return task;
  }

  async function resolveStrategyPreviewCardForLanguage(scryfallId, cardName, language) {
    let base = null;
    if (scryfallId) {
      base = await fetchScryfallJson(`https://api.scryfall.com/cards/${encodeURIComponent(scryfallId)}`);
    }
    if (!base && cardName) {
      base = await fetchScryfallJson(`https://api.scryfall.com/cards/named?${new URLSearchParams({ exact: cardName }).toString()}`);
    }
    if (!base || base.object !== "card") {
      return null;
    }
    if (!language || base.lang === language) {
      return base;
    }

    if (base.oracle_id) {
      const query = encodeURIComponent(`oracleid:${base.oracle_id} lang:${language}`);
      const byOracle = await fetchScryfallJson(`https://api.scryfall.com/cards/search?q=${query}&order=released&dir=desc`);
      const localized = Array.isArray(byOracle?.data) ? byOracle.data : [];
      if (localized.length > 0) {
        return localized[0];
      }
    }

    if (cardName) {
      const byName = await fetchScryfallJson(`https://api.scryfall.com/cards/named?${new URLSearchParams({ exact: cardName, lang: language }).toString()}`);
      if (byName && byName.object === "card") {
        return byName;
      }
    }

    return base;
  }

  function getStrategyBaseSeedCards() {
    const collectionId = state.selectedCollectionId;
    const payload = collectionId ? state.collectionPayloadById[collectionId] : null;
    if (!payload || payload.ok !== true) {
      return [];
    }
    const model = getStrategyModelForCollection(collectionId, payload);
    return Array.isArray(model?.cards) ? model.cards : [];
  }

  function renderStrategySeedDatalist(baseCards, extraNames = [], queryText = "") {
    const strategyNodes = nodes.strategy;
    if (!strategyNodes?.seedList) {
      return;
    }

    const query = normalizeStrategyName(queryText);
    const seen = new Set();
    const optionNames = [];

    const maxBase = query ? 240 : 800;
    (Array.isArray(baseCards) ? baseCards : []).forEach((card) => {
      const name = String(card?.name || "").trim();
      if (!name) {
        return;
      }
      if (query && !normalizeStrategyName(name).includes(query)) {
        return;
      }
      const key = normalizeStrategyName(name);
      if (!key || seen.has(key)) {
        return;
      }
      seen.add(key);
      optionNames.push(name);
    });

    const scryfallNames = Array.isArray(extraNames) ? extraNames : [];
    scryfallNames.forEach((nameValue) => {
      const name = String(nameValue || "").trim();
      if (!name) {
        return;
      }
      const key = normalizeStrategyName(name);
      if (!key || seen.has(key)) {
        return;
      }
      seen.add(key);
      optionNames.push(name);
    });

    const optionsMarkup = optionNames
      .slice(0, maxBase + 80)
      .map((name) => `<option value="${escapeHtml(name)}"></option>`)
      .join("");
    strategyNodes.seedList.innerHTML = optionsMarkup;
  }

  async function updateStrategySeedAutocomplete(queryText = "") {
    const query = String(queryText || "").trim();
    const token = ++state.strategy.seedAutocompleteToken;
    const baseCards = getStrategyBaseSeedCards();

    if (query.length < 2) {
      renderStrategySeedDatalist(baseCards, [], query);
      return;
    }

    const scryfallNames = await fetchScryfallAutocompleteNames(query);
    if (token !== state.strategy.seedAutocompleteToken) {
      return;
    }
    renderStrategySeedDatalist(baseCards, scryfallNames, query);
  }

  async function fetchScryfallAutocompleteNames(queryText) {
    const query = String(queryText || "").trim();
    if (query.length < 2) {
      return [];
    }

    const cacheKey = normalizeStrategyName(query);
    if (state.strategy.seedAutocompleteCache.has(cacheKey)) {
      return state.strategy.seedAutocompleteCache.get(cacheKey);
    }

    const url = `https://api.scryfall.com/cards/autocomplete?${new URLSearchParams({
      q: query,
      include_extras: "true"
    }).toString()}`;
    const payload = await fetchScryfallJson(url);
    const names = Array.isArray(payload?.data)
      ? payload.data.map((name) => String(name || "").trim()).filter(Boolean)
      : [];

    state.strategy.seedAutocompleteCache.set(cacheKey, names);
    return names;
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
      spellbookNodes.status.textContent = currentUiLanguage() === "fr"
        ? `Recherche Spellbook en cours pour "${state.spellbook.cardName}"...`
        : `Spellbook lookup running for "${state.spellbook.cardName}"...`;
      return;
    }

    if (state.spellbook.error) {
      spellbookNodes.status.textContent = currentUiLanguage() === "fr"
        ? `Erreur: ${state.spellbook.error}`
        : `Error: ${state.spellbook.error}`;
      return;
    }

    const variants = Array.isArray(state.spellbook.payload?.results) ? state.spellbook.payload.results : [];
    if (!state.spellbook.cardName) {
      spellbookNodes.status.textContent = t("spellbook_hint");
      spellbookNodes.results.innerHTML = `<p class="muted">${escapeHtml(t("spellbook_none"))}</p>`;
      return;
    }

    spellbookNodes.status.textContent = currentUiLanguage() === "fr"
      ? `${variants.length} variant(s) retournee(s) pour "${state.spellbook.cardName}".`
      : `${variants.length} variant(s) returned for "${state.spellbook.cardName}".`;
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
      spellbookNodes.status.textContent = currentUiLanguage() === "fr" ? "Saisis un nom de carte." : "Type a card name.";
      spellbookNodes.results.innerHTML = `<p class="muted">${escapeHtml(t("spellbook_none"))}</p>`;
      return;
    }

    const runToken = ++state.spellbook.runToken;
    state.spellbook.loading = true;
    state.spellbook.error = "";
    spellbookNodes.status.textContent = currentUiLanguage() === "fr"
      ? `Recherche Spellbook en cours pour "${cardName}"...`
      : `Spellbook lookup running for "${cardName}"...`;
    spellbookNodes.results.innerHTML = `<p class="muted">${currentUiLanguage() === "fr" ? "Chargement..." : "Loading..."}</p>`;

    try {
      const payload = await fetchSpellbookVariants(cardName, limitValue);
      if (runToken !== state.spellbook.runToken) {
        return;
      }

      if (!payload || payload.ok !== true) {
        state.spellbook.payload = null;
        state.spellbook.error = String(payload?.error || "Spellbook indisponible");
        spellbookNodes.status.textContent = currentUiLanguage() === "fr"
          ? `Erreur: ${state.spellbook.error}`
          : `Error: ${state.spellbook.error}`;
        spellbookNodes.results.innerHTML = `<p class="muted">${escapeHtml(t("spellbook_none"))}</p>`;
        return;
      }

      state.spellbook.payload = payload;
      state.spellbook.error = "";
      const variants = Array.isArray(payload.results) ? payload.results : [];
      spellbookNodes.status.textContent = currentUiLanguage() === "fr"
        ? `${variants.length} variant(s) retournee(s) pour "${cardName}".`
        : `${variants.length} variant(s) returned for "${cardName}".`;
      spellbookNodes.results.innerHTML = renderSpellbookVariants(variants);
    } catch (error) {
      if (runToken !== state.spellbook.runToken) {
        return;
      }
      state.spellbook.payload = null;
      state.spellbook.error = String(error?.message || error || "Spellbook indisponible");
      spellbookNodes.status.textContent = currentUiLanguage() === "fr"
        ? `Erreur: ${state.spellbook.error}`
        : `Error: ${state.spellbook.error}`;
      spellbookNodes.results.innerHTML = `<p class="muted">${escapeHtml(t("spellbook_none"))}</p>`;
    } finally {
      if (runToken === state.spellbook.runToken) {
        state.spellbook.loading = false;
      }
    }
  }

  function renderSpellbookVariants(variants) {
    const safeVariants = Array.isArray(variants) ? variants : [];
    if (safeVariants.length === 0) {
      return `<p class="muted">${currentUiLanguage() === "fr" ? "Aucun combo trouve." : "No combo found."}</p>`;
    }

    return safeVariants.map((variant, index) => {
      const status = String(variant?.status || "").trim() || "UNKNOWN";
      const variantId = String(variant?.id || "").trim() || String(index + 1);
      const statusClass = status === "OK" ? "is-ok" : "is-other";
      const popularity = Number(variant?.popularity);
      const popularityText = Number.isFinite(popularity)
        ? popularity.toLocaleString(currentUiLanguage() === "fr" ? "fr-FR" : "en-US")
        : "-";
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
            <h4>${currentUiLanguage() === "fr" ? "Variante" : "Variant"} ${escapeHtml(String(index + 1))}</h4>
            <div class="spellbook-head-badges">
              <span class="spellbook-head-badge ${statusClass}">${escapeHtml(status)}</span>
              <span class="spellbook-head-badge">${currentUiLanguage() === "fr" ? "Popularite" : "Popularity"} ${escapeHtml(popularityText)}</span>
              <span class="spellbook-head-badge">ID ${escapeHtml(variantId)}</span>
            </div>
          </div>
          <div class="spellbook-variant-content">
            <section class="spellbook-summary-row">
              <p class="spellbook-column-title">${currentUiLanguage() === "fr" ? "Resume rapide" : "Quick summary"}</p>
              <p class="spellbook-explicit-text">${escapeHtml(explicitText)}</p>
            </section>
            <section class="spellbook-card-ribbon-wrap">
              <p class="spellbook-column-title">${currentUiLanguage() === "fr" ? "Cartes du combo" : "Combo cards"}</p>
              ${cardsMarkup}
            </section>
            <section class="spellbook-action-block">
              <p class="spellbook-column-title">${currentUiLanguage() === "fr" ? "Arbre d'actions" : "Action tree"}</p>
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

  function isLikelyScryfallId(value) {
    const raw = String(value || "").trim();
    return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(raw);
  }

  // Direct CDN URLs avoid browser blocking on api.scryfall.com image redirects.
  function scryfallCdnImageUrl(scryfallId, version = "normal") {
    const id = String(scryfallId || "").trim().toLowerCase();
    if (!isLikelyScryfallId(id)) {
      return "";
    }
    return `https://cards.scryfall.io/${version}/front/${id[0]}/${id[1]}/${id}.jpg`;
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
    const model = payload && payload.ok === true
      ? getStrategyModelForCollection(collectionId, payload)
      : { cards: [] };
    const onlyCollection = isStrategyUseCollectionOnlyEnabled();
    const includeKnown = !onlyCollection && isStrategyIncludeKnownEnabled();
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
    if (!model.cards.length && !includeKnown) {
      const onlyCollection = isStrategyUseCollectionOnlyEnabled();
      if (onlyCollection) {
        strategyNodes.status.textContent = currentUiLanguage() === "fr"
          ? "Aucune collection chargee: decoche \"Limiter a la collection\" ou charge une collection dans l'onglet 1."
          : "No collection loaded: uncheck \"Restrict to collection\" or load a collection in tab 1.";
      } else {
        strategyNodes.status.textContent = "Collection vide ou cartes non reconnues.";
      }
      strategyNodes.directList.innerHTML = '<p class="muted">Aucun resultat.</p>';
      strategyNodes.groupList.innerHTML = '<p class="muted">Aucun resultat.</p>';
      return;
    }

    if (!rawSeed) {
      strategyNodes.status.textContent = "Saisis une carte seed (ex: Entomb).";
      return;
    }

    if (!model.cards.length && includeKnown) {
      strategyNodes.status.textContent = currentUiLanguage() === "fr"
        ? "Aucune collection active: recherche Scryfall uniquement..."
        : "No active collection: using Scryfall-only lookup...";
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
        strategyNodes.status.textContent = currentUiLanguage() === "fr"
          ? "Scryfall indisponible, calcul sur la collection uniquement."
          : "Scryfall unavailable, running with collection only.";
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
      strategyNodes.status.textContent = currentUiLanguage() === "fr"
        ? `${seedCard.name}: aucun candidat apres filtre mana ${formatStrategyManaFilter(manaFilterCodes)}.`
        : `${seedCard.name}: no candidate after mana filter ${formatStrategyManaFilter(manaFilterCodes)}.`;
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
    const synergyPayload = buildStrategySynergyPayload(resolvedSeed, activeModel.cards, directLimit, groupLimit);

    strategyNodes.status.textContent = currentUiLanguage() === "fr"
      ? `Analyse mecanique backend en cours pour ${resolvedSeed.name}...`
      : `Running backend mechanical analysis for ${resolvedSeed.name}...`;
    const synergyResult = await fetchStrategySynergyResult(strategyNodes, synergyPayload, resolvedSeed.name, runToken);
    if (runToken !== state.strategy.runToken) {
      return;
    }
    if (synergyResult?.ok) {
      let spellbookBoostApplied = 0;
      let spellbookContext = {
        boostByKey: new Map(),
        refsByKey: new Map(),
        popularityByKey: new Map(),
        variantCount: 0,
        variants: []
      };
      let lotusContext = {
        boostByKey: new Map(),
        refsByKey: new Map(),
        postCount: 0
      };
      try {
        const [spellbookOut, lotusOut] = await Promise.all([
          isStrategyIncludeSpellbookEnabled()
            ? getStrategySpellbookContext(resolvedSeed)
            : Promise.resolve(spellbookContext),
          isStrategyIncludeLotusEnabled()
            ? getStrategyLotusNoirContext(resolvedSeed, activeModel.cards)
            : Promise.resolve(lotusContext)
        ]);
        spellbookContext = spellbookOut;
        lotusContext = lotusOut;
        if (runToken !== state.strategy.runToken) {
          return;
        }
        if (isStrategyIncludeSpellbookEnabled()) {
          spellbookBoostApplied = applySpellbookBoostToBackendResult(synergyResult, spellbookContext);
        }
      } catch (error) {
        // External references are best-effort: keep backend results usable.
      }
      annotateBackendResultProvenance(synergyResult, spellbookContext, lotusContext);
      renderBackendDirectSynergyCards(synergyResult, resolvedSeed.name, activeModel.cards, directLimit);
      renderBackendSynergyBuckets(synergyResult, resolvedSeed.name, activeModel.cards, groupLimit);

      const bucketCount = Object.values(synergyResult?.buckets || {}).reduce((sum, bucket) => {
        const count = Number(bucket?.count || (Array.isArray(bucket?.results) ? bucket.results.length : 0));
        return sum + (Number.isFinite(count) ? count : 0);
      }, 0);
      const totalMs = Number(synergyResult?.timings?.total_ms || 0);
      const durationText = Number.isFinite(totalMs) && totalMs > 0
        ? ` ${currentUiLanguage() === "fr" ? "Temps" : "Time"}: ${(totalMs / 1000).toFixed(totalMs >= 10000 ? 0 : 1)}s.`
        : "";
      const boostText = spellbookBoostApplied > 0
        ? (currentUiLanguage() === "fr"
          ? ` Bonus Spellbook applique a ${spellbookBoostApplied} entree(s).`
          : ` Spellbook bonus applied to ${spellbookBoostApplied} entr${spellbookBoostApplied > 1 ? "ies" : "y"}.`)
        : "";
      strategyNodes.status.textContent = currentUiLanguage() === "fr"
        ? `${resolvedSeed.name}: ${Number(synergyResult?.count || 0)} cartes classees, ${bucketCount} elements bucketes, ${Number(synergyResult?.package_count || 0)} packages backend.${durationText}${boostText}`
        : `${resolvedSeed.name}: ${Number(synergyResult?.count || 0)} ranked cards, ${bucketCount} bucketed entries, ${Number(synergyResult?.package_count || 0)} backend packages.${durationText}${boostText}`;
      return;
    }

    let spellbookContext = {
      boostByKey: new Map(),
      refsByKey: new Map(),
      popularityByKey: new Map(),
      variantCount: 0,
      variants: []
    };
    let lotusContext = {
      boostByKey: new Map(),
      refsByKey: new Map(),
      postCount: 0
    };

    if (isStrategyIncludeSpellbookEnabled()) {
      strategyNodes.status.textContent = currentUiLanguage() === "fr"
        ? `Analyse Commander Spellbook en cours pour ${resolvedSeed.name}...`
        : `Commander Spellbook analysis in progress for ${resolvedSeed.name}...`;
      spellbookContext = await getStrategySpellbookContext(resolvedSeed);
    }
    if (isStrategyIncludeLotusEnabled()) {
      strategyNodes.status.textContent = currentUiLanguage() === "fr"
        ? `Analyse LotusNoir en cours pour ${resolvedSeed.name}...`
        : `LotusNoir analysis in progress for ${resolvedSeed.name}...`;
      lotusContext = await getStrategyLotusNoirContext(resolvedSeed, activeModel.cards);
    }
    if (runToken !== state.strategy.runToken) {
      return;
    }

    const externalContext = mergeStrategyExternalContexts(spellbookContext, lotusContext);

    const direct = computeDirectSynergiesForSeedFaces(
      resolvedSeed,
      activeModel.cards,
      directLimit,
      externalContext
    );
    const spellbookGroups = isStrategyIncludeSpellbookEnabled()
      ? computeSpellbookSynergyGroups(
        resolvedSeed,
        direct,
        activeModel.cards,
        groupLimit,
        spellbookContext,
        { allowExternalCards: manaFilterCodes.length === 0, externalContext }
      )
      : [];
    const fallbackGroups = computeSynergyGroups(resolvedSeed, direct, activeModel.cards, groupLimit, externalContext);
    let groups = mergeStrategyGroups(spellbookGroups, fallbackGroups, groupLimit);
    groups = await enrichStrategyGroupsWithScryfall(groups, getCollectionLanguage());
    if (runToken !== state.strategy.runToken) {
      return;
    }

    renderDirectSynergyCards(direct, resolvedSeed.name);
    renderGroupCards(groups, resolvedSeed.name, spellbookContext);

    const suffix = includeKnown && scryfallAddedCount > 0
      ? ` (incluant ${scryfallAddedCount} cartes Scryfall)`
      : "";
    const manaSuffix = manaFilterCodes.length > 0
      ? (currentUiLanguage() === "fr"
          ? ` | filtre mana ${formatStrategyManaFilter(manaFilterCodes)}`
          : ` | mana filter ${formatStrategyManaFilter(manaFilterCodes)}`)
      : "";
    strategyNodes.status.textContent = currentUiLanguage() === "fr"
      ? `${resolvedSeed.name}: ${direct.length} synergies directes, ${groups.length} groupes construits.${suffix}${manaSuffix}`
      : `${resolvedSeed.name}: ${direct.length} direct synergies, ${groups.length} groups built.${suffix}${manaSuffix}`;
  }

  function isStrategyIncludeKnownEnabled() {
    return true;
  }

  function isStrategyIncludeSpellbookEnabled() {
    return state.strategy.includeSpellbookCombos === true;
  }

  function isStrategyIncludeLotusEnabled() {
    return state.strategy.includeLotusSignals === true;
  }

  function isStrategyUseCollectionOnlyEnabled() {
    return state.strategy.useCollectionOnly === true;
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

  function parseStrategyColorCodes(value) {
    if (Array.isArray(value)) {
      return [...new Set(value.map((entry) => String(entry || "").toUpperCase()).filter((entry) => "WUBRGC".includes(entry)))];
    }
    const text = String(value || "").toUpperCase();
    if (!text) {
      return [];
    }
    const matches = text.match(/[WUBRGC]/g) || [];
    return [...new Set(matches)];
  }

  function parseStrategyKeywordList(value) {
    if (Array.isArray(value)) {
      return value.map((entry) => String(entry || "").trim()).filter(Boolean);
    }
    return String(value || "")
      .split(/[;,|/]+/)
      .map((entry) => entry.trim())
      .filter(Boolean);
  }

  function toStrategySynergyCardPayload(card) {
    const row = card?.row && typeof card.row === "object" ? card.row : {};
    const oracleText = rowValue(row, ["oracle_text", "printed_text", "card_text", "rules_text", "description"]);
    const typeLine = rowValue(row, ["type_line", "type"]);
    const keywords = parseStrategyKeywordList(rowValue(row, ["keywords", "abilities", "keyword"]));
    const colors = parseStrategyColorCodes(Array.isArray(card?.colors) ? card.colors : rowValue(row, ["colors"]));
    const colorIdentity = parseStrategyColorCodes(rowValue(row, ["color_identity"]));
    const cmcRaw = rowValue(row, ["cmc", "mana_value", "mv"]);
    const cmcValue = Number(cmcRaw);

    const payload = {
      id: String(card?.scryfallId || card?.key || card?.name || "").trim(),
      name: String(card?.name || "").trim(),
      oracle_text: oracleText,
      type_line: typeLine,
      colors,
      color_identity: colorIdentity.length > 0 ? colorIdentity : colors,
      keywords
    };
    if (Number.isFinite(cmcValue)) {
      payload.cmc = cmcValue;
    }
    return payload;
  }

  function buildStrategySynergyPayload(seedCard, cards, directLimit, groupLimit) {
    const safeCards = Array.isArray(cards) ? cards.map(toStrategySynergyCardPayload).filter((card) => card.name) : [];
    const maxResults = Math.max(Number(directLimit) || 0, (Number(groupLimit) || 0) * 2, 12);
    const topK = Math.max(maxResults * 4, (Number(groupLimit) || 0) * 6, 48);
    const packageTopN = Math.max(Math.min((Number(groupLimit) || 0) * 2, 24), 6);
    return {
      card_name: String(seedCard?.name || "").trim(),
      format: "commander",
      max_results: maxResults,
      top_k: topK,
      package_top_n: packageTopN,
      cards: safeCards
    };
  }

  function waitStrategyMilliseconds(value) {
    const milliseconds = Math.max(0, Number(value) || 0);
    return new Promise((resolve) => {
      window.setTimeout(resolve, milliseconds);
    });
  }

  async function fetchStrategySynergyResult(strategyNodes, payload, seedName, runToken) {
    const fallbackDirect = async (message) => {
      if (runToken !== state.strategy.runToken) {
        return { ok: false, cancelled: true };
      }
      strategyNodes.status.textContent = message;
      return fetchSynergyFind(payload);
    };

    const queued = await startSynergyJob(payload);
    if (runToken !== state.strategy.runToken) {
      return { ok: false, cancelled: true };
    }

    const jobId = String(queued?.job_id || "").trim();
    if (!queued?.ok || !jobId) {
      const message = currentUiLanguage() === "fr"
        ? `${seedName}: job backend indisponible, repli sur /synergy/find...`
        : `${seedName}: background job unavailable, falling back to /synergy/find...`;
      return fallbackDirect(message);
    }

    for (let attempt = 0; attempt < 180; attempt += 1) {
      const status = attempt === 0 ? queued : await fetchSynergyJobStatus(jobId);
      if (runToken !== state.strategy.runToken) {
        return { ok: false, cancelled: true };
      }

      if (status?.result?.ok) {
        return status.result;
      }

      const statusValue = String(status?.status || "").trim().toLowerCase();
      if (statusValue === "completed" && status?.result?.ok) {
        return status.result;
      }
      if (statusValue === "error") {
        const message = currentUiLanguage() === "fr"
          ? `${seedName}: job backend en erreur, repli sur /synergy/find...`
          : `${seedName}: background job failed, falling back to /synergy/find...`;
        return fallbackDirect(message);
      }

      const percent = clampInt(status?.progress?.percent, 0, 100, 0);
      const stage = String(status?.progress?.stage || "").trim() || (currentUiLanguage() === "fr" ? "Analyse backend" : "Backend analysis");
      strategyNodes.status.textContent = `${seedName}: ${stage} (${percent}%)...`;
      await waitStrategyMilliseconds(attempt < 6 ? 250 : 500);
    }

    const timeoutMessage = currentUiLanguage() === "fr"
      ? `${seedName}: job backend trop long, repli sur /synergy/find...`
      : `${seedName}: background job timed out, falling back to /synergy/find...`;
    return fallbackDirect(timeoutMessage);
  }

  function buildStrategySynergyLookup(cards) {
    const byId = new Map();
    const byKey = new Map();
    const byName = new Map();

    (Array.isArray(cards) ? cards : []).forEach((card) => {
      if (!card) {
        return;
      }
      const rawId = String(card?.scryfallId || card?.key || "").trim();
      const key = normalizeStrategyName(card?.key || card?.name || rawId);
      const nameKey = normalizeStrategyName(card?.name || "");
      if (rawId) {
        byId.set(rawId, card);
      }
      if (key) {
        byKey.set(key, card);
      }
      if (nameKey) {
        byName.set(nameKey, card);
      }
    });

    return { byId, byKey, byName };
  }

  function createStrategyApiPlaceholderCard(entry) {
    const name = String(entry?.name || entry?.id || "Carte API").trim();
    const key = normalizeStrategyName(entry?.id || name) || name;
    const oracleText = String(entry?.explanation_text || (Array.isArray(entry?.reasons) ? entry.reasons.join(" ") : "")).trim();
    const typeLine = Array.isArray(entry?.roles) && entry.roles.length > 0
      ? entry.roles.join(" / ")
      : "Synergy result";

    return {
      key,
      name,
      row: {
        oracle_text: oracleText,
        type_line: typeLine
      },
      quantity: 1,
      features: {},
      semantics: {},
      colors: [],
      scryfallId: "",
      source: "api"
    };
  }

  function resolveStrategySynergyCard(entry, lookup) {
    const rawId = String(entry?.id || "").trim();
    const key = normalizeStrategyName(rawId);
    const nameKey = normalizeStrategyName(entry?.name || "");
    const matched = (rawId && lookup?.byId?.get(rawId)) || (key && lookup?.byKey?.get(key)) || (nameKey && lookup?.byName?.get(nameKey)) || null;
    if (!matched) {
      return createStrategyApiPlaceholderCard(entry);
    }

    const mergedRow = {
      ...(matched.row && typeof matched.row === "object" ? matched.row : {})
    };
    if (!rowValue(mergedRow, ["oracle_text", "printed_text", "card_text", "rules_text", "description"])) {
      mergedRow.oracle_text = String(entry?.explanation_text || "").trim();
    }
    return {
      ...matched,
      row: mergedRow
    };
  }

  function formatSynergyAxisValue(value) {
    const safe = Number(value);
    if (!Number.isFinite(safe)) {
      return "0.00";
    }
    return safe.toFixed(2);
  }

  function formatSynergyEntryMeta(entry, rank = 0) {
    const score = Math.round(Number(entry?.total_score || entry?.score || 0));
    const bucketLabel = String(entry?.bucket_label || entry?.bucket || "").trim();
    const prefix = rank > 0 ? `#${rank} | ` : "";
    return `${prefix}score ${score}${bucketLabel ? ` | ${bucketLabel}` : ""}`;
  }

  function formatSynergyEntryTitle(entry) {
    const axes = entry?.axis_scores || {};
    const roles = Array.isArray(entry?.roles) ? entry.roles.join(", ") : "";
    const lines = [
      String(entry?.explanation_text || "").trim(),
      `direct ${formatSynergyAxisValue(axes.direct_event_score)} | indirect ${formatSynergyAxisValue(axes.indirect_engine_score)} | reciprocal ${formatSynergyAxisValue(axes.reciprocal_value_score)}`,
      `package ${formatSynergyAxisValue(axes.package_score)} | anti ${formatSynergyAxisValue(axes.anti_synergy_score)} | cadence ${formatSynergyAxisValue(axes.cadence_score)} | role ${formatSynergyAxisValue(axes.role_complementarity_score)}`,
      roles ? `roles: ${roles}` : ""
    ].filter(Boolean);
    return lines.join("\n");
  }

  function renderBackendDirectSynergyCards(result, seedName, cards, limit) {
    const target = nodes.strategy.directList;
    if (!target) {
      return;
    }

    const lookup = buildStrategySynergyLookup(cards);
    const directBucket = Array.isArray(result?.buckets?.direct_enablers?.results)
      ? result.buckets.direct_enablers.results
      : [];
    const fallbackEntries = Array.isArray(result?.best_matches) ? result.best_matches : [];
    const entries = (directBucket.length > 0 ? directBucket : fallbackEntries).slice(0, Math.max(1, Number(limit) || 1));
    if (entries.length === 0) {
      target.innerHTML = `<p class="muted">Aucune synergie directe calculee pour ${escapeHtml(seedName)}.</p>`;
      return;
    }

    target.innerHTML = "";
    const fragment = document.createDocumentFragment();
    entries.forEach((entry, index) => {
      const card = resolveStrategySynergyCard(entry, lookup);
      fragment.appendChild(
        createStrategyCardElement(
          card,
          formatSynergyEntryMeta(entry, index + 1),
          {
            metaTitle: formatSynergyEntryTitle(entry),
            badge: String(entry?.bucket_label || "").trim() || "Direct",
            provenanceTags: readStrategyProvenanceTags(entry)
          }
        )
      );
    });
    target.appendChild(fragment);
  }

  function appendBackendBucketSection(container, bucket, cards, options = {}) {
    const results = Array.isArray(bucket?.results) ? bucket.results : [];
    if (results.length === 0) {
      return;
    }

    const lookup = buildStrategySynergyLookup(cards);
    const article = document.createElement("article");
    article.className = "strategy-group is-heuristic";

    const title = document.createElement("p");
    title.className = "strategy-group-title";
    title.textContent = `${String(bucket?.label || bucket?.key || "Bucket").trim()} | ${results.length}`;
    article.appendChild(title);

    const detail = document.createElement("p");
    detail.className = "strategy-group-line";
    detail.textContent = String(options.description || "Classement backend par structure mecanique.").trim();
    article.appendChild(detail);

    const grid = document.createElement("div");
    grid.className = "strategy-card-grid";
    results.slice(0, Math.max(1, Number(options.limit) || 6)).forEach((entry) => {
      const card = resolveStrategySynergyCard(entry, lookup);
      grid.appendChild(
        createStrategyCardElement(
          card,
          formatSynergyEntryMeta(entry),
          {
            compact: true,
            metaTitle: formatSynergyEntryTitle(entry),
            badge: String(entry?.bucket_label || bucket?.label || "").trim(),
            provenanceTags: readStrategyProvenanceTags(entry)
          }
        )
      );
    });

    article.appendChild(grid);
    container.appendChild(article);
  }

  function appendBackendPackageSection(container, packages, cards, limit = 6) {
    const results = Array.isArray(packages) ? packages : [];
    if (results.length === 0) {
      return;
    }

    const lookup = buildStrategySynergyLookup(cards);
    const article = document.createElement("article");
    article.className = "strategy-group is-heuristic";

    const title = document.createElement("p");
    title.className = "strategy-group-title";
    title.textContent = `Top packages / groups | ${results.length}`;
    if (results.length > 0) {
      appendStrategyProvenanceBadges(title, readStrategyProvenanceTags(results[0]));
    }
    article.appendChild(title);

    results.slice(0, Math.max(1, Number(limit) || 6)).forEach((pkg, index) => {
      const block = document.createElement("div");
      block.className = "strategy-group-section is-core";

      const line = document.createElement("p");
      line.className = "strategy-group-line";
      line.textContent = `#${index + 1} | score ${Math.round(Number(pkg?.score || 0))} | ${String(pkg?.archetype || "package").trim()}`;
      appendStrategyProvenanceBadges(line, readStrategyProvenanceTags(pkg));
      block.appendChild(line);

      const reason = document.createElement("p");
      reason.className = "strategy-group-line";
      reason.textContent = Array.isArray(pkg?.reasons) && pkg.reasons.length > 0
        ? String(pkg.reasons[0]).trim()
        : "Package mecanique detecte.";
      block.appendChild(reason);

      const grid = document.createElement("div");
      grid.className = "strategy-card-grid";
      [pkg?.cards?.setup, pkg?.cards?.converter, pkg?.cards?.payoff].filter(Boolean).forEach((entry) => {
        const card = resolveStrategySynergyCard(entry, lookup);
        grid.appendChild(
          createStrategyCardElement(card, String(entry?.name || "").trim(), {
            compact: true,
            badge: String(pkg?.archetype || "package").trim()
          })
        );
      });

      block.appendChild(grid);
      article.appendChild(block);
    });

    container.appendChild(article);
  }

  function renderBackendSynergyBuckets(result, seedName, cards, limit = 6) {
    const target = nodes.strategy.groupList;
    if (!target) {
      return;
    }

    const buckets = result?.buckets && typeof result.buckets === "object" ? result.buckets : {};
    target.innerHTML = "";

    const fragment = document.createDocumentFragment();
    appendBackendBucketSection(fragment, buckets.indirect_engines, cards, {
      limit,
      description: "Engines indirects repetables, convertisseurs ou bridges"
    });
    appendBackendBucketSection(fragment, buckets.reciprocal_value_cards, cards, {
      limit,
      description: "Cartes a valeur reciproque plutot que payoff unilateral"
    });
    appendBackendBucketSection(fragment, buckets.anti_synergy_warnings, cards, {
      limit,
      description: "Avertissements de conflits mecaniques et de plans"
    });
    appendBackendPackageSection(fragment, result?.packages, cards, limit);

    if (!fragment.childNodes.length) {
      target.innerHTML = `<p class="muted">Aucun groupe genere pour ${escapeHtml(seedName)}.</p>`;
      return;
    }

    target.appendChild(fragment);
  }

  // Apply a Commander Spellbook bonus to backend synergy entries whose card name
  // appears in a public combo featuring the seed. Mutates `result` in place and
  // re-sorts the impacted lists so the UI renders the boosted ranking.
  function applySpellbookBoostToBackendResult(result, spellbookContext) {
    if (!result || typeof result !== "object") {
      return 0;
    }
    const boostByKey = spellbookContext?.boostByKey;
    if (!(boostByKey instanceof Map) || boostByKey.size === 0) {
      return 0;
    }
    // Backend `total_score` typically falls in the 0..100 range. Spellbook boost
    // is in 0..1.2; multiplying by 18 keeps the bonus meaningful (max ~22 pts)
    // without dwarfing the underlying mechanical signal.
    const SCORE_SCALE = 18;

    const boostEntry = (entry) => {
      if (!entry || typeof entry !== "object") {
        return false;
      }
      const nameKey = normalizeStrategyName(entry?.name || entry?.id || "");
      if (!nameKey) {
        return false;
      }
      const boost = Number(boostByKey.get(nameKey) || 0);
      if (!(boost > 0)) {
        return false;
      }
      const baseTotal = Number(entry.total_score || entry.score || 0);
      const baseRaw = Number(entry.score || entry.total_score || 0);
      const bonus = boost * SCORE_SCALE;
      entry.spellbook_boost = boost;
      entry.spellbook_bonus = bonus;
      entry.total_score = (Number.isFinite(baseTotal) ? baseTotal : 0) + bonus;
      entry.score = (Number.isFinite(baseRaw) ? baseRaw : 0) + bonus;
      const reason = `Commander Spellbook combo bonus (+${bonus.toFixed(1)})`;
      if (Array.isArray(entry.reasons)) {
        if (!entry.reasons.includes(reason)) {
          entry.reasons = [reason, ...entry.reasons];
        }
      } else {
        entry.reasons = [reason];
      }
      return true;
    };

    const sortByScoreDesc = (list) => {
      list.sort((a, b) => Number(b?.total_score || b?.score || 0) - Number(a?.total_score || a?.score || 0));
    };

    let touched = 0;

    if (Array.isArray(result.best_matches)) {
      result.best_matches.forEach((entry) => { if (boostEntry(entry)) touched += 1; });
      sortByScoreDesc(result.best_matches);
    }

    const buckets = result?.buckets && typeof result.buckets === "object" ? result.buckets : {};
    Object.keys(buckets).forEach((bucketKey) => {
      const bucket = buckets[bucketKey];
      if (bucket && Array.isArray(bucket.results)) {
        bucket.results.forEach((entry) => { if (boostEntry(entry)) touched += 1; });
        sortByScoreDesc(bucket.results);
      }
    });

    if (Array.isArray(result.packages)) {
      result.packages.forEach((pkg) => {
        if (!pkg || typeof pkg !== "object") {
          return;
        }
        const memberCards = [pkg?.cards?.setup, pkg?.cards?.converter, pkg?.cards?.payoff].filter(Boolean);
        let pkgBonus = 0;
        let memberHits = 0;
        memberCards.forEach((member) => {
          const nameKey = normalizeStrategyName(member?.name || member?.id || "");
          const boost = Number(boostByKey.get(nameKey) || 0);
          if (boost > 0) {
            pkgBonus += boost * SCORE_SCALE;
            memberHits += 1;
          }
        });
        if (pkgBonus > 0) {
          // Half-credit for groups so a single combo-card doesn't dominate.
          const appliedBonus = pkgBonus * 0.5;
          const baseScore = Number(pkg.score || 0);
          pkg.spellbook_bonus = appliedBonus;
          pkg.score = (Number.isFinite(baseScore) ? baseScore : 0) + appliedBonus;
          const reason = `Spellbook combo overlap on ${memberHits} card${memberHits > 1 ? "s" : ""} (+${appliedBonus.toFixed(1)})`;
          if (Array.isArray(pkg.reasons)) {
            if (!pkg.reasons.includes(reason)) {
              pkg.reasons = [reason, ...pkg.reasons];
            }
          } else {
            pkg.reasons = [reason];
          }
          touched += 1;
        }
      });
      result.packages.sort((a, b) => Number(b?.score || 0) - Number(a?.score || 0));
    }

    return touched;
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

  function resetStrategyLotusCache() {
    state.strategy.lotusCache = new Map();
    state.strategy.lotusPromiseCache = new Map();
    state.strategy.lotusError = "";
  }

  async function getStrategySpellbookContext(seedCard) {
    const seedKey = normalizeStrategyName(seedCard?.key || seedCard?.name || "");
    if (!seedKey) {
      return { boostByKey: new Map(), refsByKey: new Map(), popularityByKey: new Map(), variantCount: 0, variants: [] };
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
        const fallback = { boostByKey: new Map(), refsByKey: new Map(), popularityByKey: new Map(), variantCount: 0, variants: [] };
        state.strategy.spellbookCache.set(seedKey, fallback);
        return fallback;
      })
      .finally(() => {
        state.strategy.spellbookPromiseCache.delete(seedKey);
      });

    state.strategy.spellbookPromiseCache.set(seedKey, task);
    return task;
  }

  function mergeStrategyExternalContexts(spellbookContext = {}, lotusContext = {}) {
    const boostByKey = spellbookContext?.boostByKey instanceof Map
      ? new Map(spellbookContext.boostByKey)
      : new Map();
    const refsByKey = spellbookContext?.refsByKey instanceof Map
      ? new Map(spellbookContext.refsByKey)
      : new Map();
    const popularityByKey = spellbookContext?.popularityByKey instanceof Map
      ? new Map(spellbookContext.popularityByKey)
      : new Map();

    const lotusBoostByKey = lotusContext?.boostByKey instanceof Map
      ? new Map(lotusContext.boostByKey)
      : new Map();
    const lotusRefsByKey = lotusContext?.refsByKey instanceof Map
      ? new Map(lotusContext.refsByKey)
      : new Map();

    lotusBoostByKey.forEach((value, key) => {
      const previous = Number(boostByKey.get(key) || 0);
      boostByKey.set(key, previous + Number(value || 0));
    });

    return {
      boostByKey,
      refsByKey,
      popularityByKey,
      variantCount: Math.max(1, Number(spellbookContext?.variantCount) || 0),
      lotusBoostByKey,
      lotusRefsByKey,
      lotusPostCount: Math.max(0, Number(lotusContext?.postCount) || 0)
    };
  }

  async function getStrategyLotusNoirContext(seedCard, cards) {
    const seedKey = normalizeStrategyName(seedCard?.key || seedCard?.name || "");
    if (!seedKey) {
      return { boostByKey: new Map(), refsByKey: new Map(), postCount: 0 };
    }
    if (state.strategy.lotusCache.has(seedKey)) {
      return state.strategy.lotusCache.get(seedKey);
    }
    if (state.strategy.lotusPromiseCache.has(seedKey)) {
      return state.strategy.lotusPromiseCache.get(seedKey);
    }

    const task = fetchStrategyLotusNoirContext(seedCard, cards)
      .then((context) => {
        state.strategy.lotusCache.set(seedKey, context);
        state.strategy.lotusError = "";
        return context;
      })
      .catch((error) => {
        state.strategy.lotusError = String(error?.message || "LotusNoir indisponible");
        const fallback = { boostByKey: new Map(), refsByKey: new Map(), postCount: 0 };
        state.strategy.lotusCache.set(seedKey, fallback);
        return fallback;
      })
      .finally(() => {
        state.strategy.lotusPromiseCache.delete(seedKey);
      });

    state.strategy.lotusPromiseCache.set(seedKey, task);
    return task;
  }

  async function fetchStrategyLotusNoirContext(seedCard, cards) {
    const seedName = String(seedCard?.name || "").trim();
    const seedKey = normalizeStrategyName(seedCard?.key || seedName);
    if (!seedName || !seedKey) {
      return { boostByKey: new Map(), refsByKey: new Map(), postCount: 0 };
    }

    const posts = await fetchLotusNoirPosts(seedName);
    const refsByKey = new Map();
    const boostByKey = new Map();
    const uniquePosts = Array.isArray(posts) ? posts : [];
    const postCount = uniquePosts.length;
    if (postCount === 0) {
      return { boostByKey, refsByKey, postCount: 0 };
    }

    const safeCards = Array.isArray(cards) ? cards : [];
    const candidates = safeCards
      .map((card) => ({
        key: normalizeStrategyName(card?.key || card?.name || ""),
        name: String(card?.name || "").trim()
      }))
      .filter((entry) => entry.key && entry.key !== seedKey && entry.key.length >= 3);

    uniquePosts.forEach((post) => {
      const normalizedText = ` ${normalizeStrategyName(stripHtml(String(post?.content || "")))} `;
      if (!normalizedText.includes(` ${seedKey} `)) {
        return;
      }

      candidates.forEach((candidate) => {
        if (normalizedText.includes(` ${candidate.key} `)) {
          refsByKey.set(candidate.key, (refsByKey.get(candidate.key) || 0) + 1);
        }
      });
    });

    refsByKey.forEach((refs, cardKey) => {
      const ratio = refs > 0 ? refs / Math.max(1, postCount) : 0;
      const boost = Math.min(0.34, 0.08 + ratio * 0.44);
      boostByKey.set(cardKey, boost);
    });

    return { boostByKey, refsByKey, postCount };
  }

  async function fetchLotusNoirPosts(seedName) {
    const safeSearch = String(seedName || "").trim();
    if (!safeSearch) {
      return [];
    }

    const payload = await fetchLotusNoirPostsApi(safeSearch, 120);
    if (!payload || payload.ok === false) {
      return [];
    }
    const allPosts = Array.isArray(payload.results) ? payload.results : [];
    const dedup = new Map();
    allPosts.forEach((post) => {
      const id = String(post?.id || "").trim();
      if (!id) {
        return;
      }
      const title = stripHtml(String(post?.title || ""));
      const excerpt = stripHtml(String(post?.snippet || ""));
      const link = stripHtml(String(post?.url || ""));
      dedup.set(id, {
        id,
        content: `${title}\n${excerpt}\n${link}`
      });
    });
    return Array.from(dedup.values());
  }

  function stripHtml(value) {
    return String(value || "")
      .replace(/<[^>]*>/g, " ")
      .replace(/&nbsp;/gi, " ")
      .replace(/&amp;/gi, "&")
      .replace(/&quot;/gi, '"')
      .replace(/&#39;/gi, "'")
      .replace(/\s+/g, " ")
      .trim();
  }

  async function fetchStrategySpellbookContext(seedCard) {
    const seedName = String(seedCard?.name || "").trim();
    if (!seedName) {
      return { boostByKey: new Map(), refsByKey: new Map(), popularityByKey: new Map(), variantCount: 0, variants: [] };
    }

    const spellbookLimit = clampInt(state?.spellbook?.limit, 1, 100, 40);
    const payload = await fetchSpellbookVariants(seedName, spellbookLimit);
    if (!payload || payload.ok === false || payload?.results == null) {
      throw new Error(payload?.error || payload?.detail || payload?.details || "Spellbook HTTP error");
    }

    const variants = Array.isArray(payload.results) ? payload.results : [];
    const seedKey = normalizeStrategyName(seedCard?.key || seedName);
    const boostByKey = new Map();
    const refsByKey = new Map();
    const popularityByKey = new Map();
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

      const normalizedCards = uses
        .map((entry) => {
          const name = String(entry?.card?.name || "").trim();
          const key = normalizeStrategyName(name);
          if (!key) {
            return null;
          }
          return { key, name: name || key };
        })
        .filter(Boolean);

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
        refsByKey.set(nameKey, (refsByKey.get(nameKey) || 0) + 1);
        popularityByKey.set(nameKey, (popularityByKey.get(nameKey) || 0) + popularity);
      });

      variantCards.push({
        cards: normalizedCards,
        cardKeys: normalizedNames,
        popularity
      });
    });

    return { boostByKey, refsByKey, popularityByKey, variantCount, variants: variantCards };
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
    const cardFaces = Array.isArray(card?.card_faces) ? card.card_faces : [];
    const faceNames = cardFaces
      .map((face) => String(face?.printed_name || face?.name || "").trim())
      .filter(Boolean);
    const faceOracles = cardFaces
      .map((face) => String(face?.printed_text || face?.oracle_text || "").trim())
      .filter(Boolean);
    const faceTypes = cardFaces
      .map((face) => String(face?.printed_type_line || face?.type_line || "").trim())
      .filter(Boolean);
    const faceManaCosts = cardFaces
      .map((face) => String(face?.mana_cost || "").trim())
      .filter(Boolean);
    return {
      name: displayName || String(card?.name || "").trim(),
      name_en: String(card?.name || "").trim(),
      mana_cost: scryfallManaCost(card),
      oracle_text: scryfallDisplayOracleText(card, strategyLanguage),
      face_names: faceNames.join(" || "),
      face_oracle_texts: faceOracles.join(" || "),
      face_type_lines: faceTypes.join(" || "),
      face_mana_costs: faceManaCosts.join(" || "),
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

  function normalizeStrategyProvenanceTag(tag) {
    const value = normalizeStrategyName(tag);
    if (!value) {
      return "";
    }
    if (value === "spellbook" || value === "commander_spellbook") {
      return "spellbook";
    }
    if (value === "lotus_noir" || value === "lotusnoir" || value === "lotus-noir") {
      return "lotus_noir";
    }
    if (value === "heuristic" || value === "heuristique" || value === "mechanical" || value === "mecanique") {
      return "heuristic";
    }
    return value;
  }

  function readStrategyProvenanceTags(entry) {
    const raw = Array.isArray(entry?.provenance_tags)
      ? entry.provenance_tags
      : (Array.isArray(entry?.provenanceTags) ? entry.provenanceTags : []);
    const seen = new Set();
    const out = [];
    raw.forEach((tag) => {
      const normalized = normalizeStrategyProvenanceTag(tag);
      if (!normalized || seen.has(normalized)) {
        return;
      }
      seen.add(normalized);
      out.push(normalized);
    });
    return out;
  }

  function buildStrategyProvenanceTags({ heuristic = false, spellbook = false, lotus = false } = {}) {
    const tags = [];
    if (heuristic) {
      tags.push("heuristic");
    }
    if (spellbook) {
      tags.push("spellbook");
    }
    if (lotus) {
      tags.push("lotus_noir");
    }
    return tags;
  }

  function strategyProvenanceTagLabel(tag) {
    const normalized = normalizeStrategyProvenanceTag(tag);
    const isFr = getCollectionLanguage() === "fr";
    switch (normalized) {
    case "heuristic":
      return isFr ? "Heuristique" : "Heuristic";
    case "spellbook":
      return "Spellbook";
    case "lotus_noir":
      return "Lotus Noir";
    default:
      return String(tag || "").trim();
    }
  }

  function strategyProvenanceToneClass(tag) {
    const normalized = normalizeStrategyProvenanceTag(tag);
    switch (normalized) {
    case "heuristic":
      return "is-provenance-heuristic";
    case "spellbook":
      return "is-provenance-spellbook";
    case "lotus_noir":
      return "is-provenance-lotus";
    default:
      return "is-side";
    }
  }

  function appendStrategyProvenanceBadges(container, tags) {
    const safeTags = Array.isArray(tags) ? tags : [];
    safeTags.forEach((tag) => {
      const normalized = normalizeStrategyProvenanceTag(tag);
      if (!normalized) {
        return;
      }
      appendStrategyCardBadge(
        container,
        strategyProvenanceTagLabel(normalized),
        strategyProvenanceToneClass(normalized)
      );
    });
  }

  function collectStrategyExternalEvidenceForKey(cardKey, externalContext = {}) {
    const key = normalizeStrategyName(cardKey);
    if (!key) {
      return {
        spellbookRefs: 0,
        spellbookBoost: 0,
        lotusRefs: 0,
        lotusBoost: 0
      };
    }

    return {
      spellbookRefs: Math.max(0, Number(externalContext?.refsByKey?.get?.(key) || 0)),
      spellbookBoost: Math.max(0, Number(externalContext?.boostByKey?.get?.(key) || 0)),
      lotusRefs: Math.max(0, Number(externalContext?.lotusRefsByKey?.get?.(key) || 0)),
      lotusBoost: Math.max(0, Number(externalContext?.lotusBoostByKey?.get?.(key) || 0))
    };
  }

  function collectStrategyExternalEvidenceForCards(cards, externalContext = {}) {
    const safeCards = Array.isArray(cards) ? cards : [];
    return safeCards.reduce((acc, card) => {
      const evidence = collectStrategyExternalEvidenceForKey(card?.key || card?.name || "", externalContext);
      acc.spellbookRefs += evidence.spellbookRefs;
      acc.spellbookBoost = Math.max(acc.spellbookBoost, evidence.spellbookBoost);
      acc.lotusRefs += evidence.lotusRefs;
      acc.lotusBoost = Math.max(acc.lotusBoost, evidence.lotusBoost);
      return acc;
    }, {
      spellbookRefs: 0,
      spellbookBoost: 0,
      lotusRefs: 0,
      lotusBoost: 0
    });
  }

  function buildStrategyGroupProvenanceTags(group, externalContext = {}) {
    const sourceType = String(group?.sourceType || "").toLowerCase();
    const evidence = collectStrategyExternalEvidenceForCards(group?.cards, externalContext);
    return buildStrategyProvenanceTags({
      heuristic: sourceType === "heuristic",
      spellbook: sourceType === "spellbook" || evidence.spellbookRefs > 0 || evidence.spellbookBoost > 0,
      lotus: evidence.lotusRefs > 0 || evidence.lotusBoost > 0
    });
  }

  function annotateBackendResultProvenance(result, spellbookContext = {}, lotusContext = {}) {
    if (!result || typeof result !== "object") {
      return;
    }

    const externalContext = mergeStrategyExternalContexts(spellbookContext, lotusContext);

    const annotateEntry = (entry) => {
      if (!entry || typeof entry !== "object") {
        return;
      }
      const evidence = collectStrategyExternalEvidenceForKey(entry?.name || entry?.id || "", externalContext);
      entry.provenance_tags = buildStrategyProvenanceTags({
        heuristic: true,
        spellbook: evidence.spellbookRefs > 0 || evidence.spellbookBoost > 0 || Number(entry?.spellbook_boost || 0) > 0,
        lotus: evidence.lotusRefs > 0 || evidence.lotusBoost > 0
      });
    };

    const annotateGroup = (group) => {
      if (!group || typeof group !== "object") {
        return;
      }
      const members = Array.isArray(group?.members)
        ? group.members
        : [];
      const cards = members.map((member) => ({
        key: member?.id || member?.name || "",
        name: member?.name || member?.id || ""
      }));
      group.provenance_tags = buildStrategyGroupProvenanceTags(
        { cards, sourceType: "heuristic" },
        externalContext
      );
    };

    if (Array.isArray(result.best_matches)) {
      result.best_matches.forEach(annotateEntry);
    }
    const buckets = result?.buckets && typeof result.buckets === "object" ? result.buckets : {};
    Object.values(buckets).forEach((bucket) => {
      if (bucket && Array.isArray(bucket.results)) {
        bucket.results.forEach(annotateEntry);
      }
    });
    if (Array.isArray(result.packages)) {
      result.packages.forEach(annotateGroup);
    }
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

  function parseStrategyFaceList(value) {
    return String(value || "")
      .split(/\s*\|\|\s*/g)
      .map((entry) => String(entry || "").trim())
      .filter(Boolean);
  }

  function strategySeedFaceVariants(seedCard) {
    if (!seedCard || !seedCard.key) {
      return [];
    }

    const seedRow = seedCard.row || {};
    const faceNames = parseStrategyFaceList(rowValue(seedRow, ["face_names"]));
    const faceOracles = parseStrategyFaceList(rowValue(seedRow, ["face_oracle_texts"]));
    const faceTypes = parseStrategyFaceList(rowValue(seedRow, ["face_type_lines"]));
    const faceManaCosts = parseStrategyFaceList(rowValue(seedRow, ["face_mana_costs"]));

    const variants = [seedCard];
    faceNames.forEach((faceName, index) => {
      const faceKey = normalizeStrategyName(faceName);
      if (!faceKey || faceKey === seedCard.key) {
        return;
      }

      const faceRow = {
        ...seedRow,
        name: faceName,
        name_en: faceName,
        oracle_text: faceOracles[index] || rowValue(seedRow, ["oracle_text", "printed_text", "card_text", "rules_text", "description"]),
        type_line: faceTypes[index] || rowValue(seedRow, ["type_line", "type"]),
        mana_cost: faceManaCosts[index] || rowValue(seedRow, ["mana_cost", "manacost", "mana"])
      };

      const textBlob = [
        rowValue(faceRow, ["type_line", "type"]),
        rowValue(faceRow, ["oracle_text", "printed_text", "card_text", "rules_text", "description"]),
        rowValue(faceRow, ["keywords", "abilities", "keyword"])
      ].join(" ");

      variants.push({
        ...seedCard,
        key: faceKey,
        name: faceName,
        row: faceRow,
        features: extractStrategyFeatureMap(textBlob),
        semantics: extractStrategySemantics(faceRow)
      });
    });

    const unique = new Map();
    variants.forEach((entry) => {
      if (!entry?.key || unique.has(entry.key)) {
        return;
      }
      unique.set(entry.key, entry);
    });
    return Array.from(unique.values());
  }

  function mergeDirectSynergyEntries(entriesByKey, limit) {
    const merged = Array.from(entriesByKey.values()).map((entry) => {
      const out = { ...entry };
      delete out._seedFaces;
      return out;
    });

    merged.sort((left, right) => {
      const leftSbScore = Number(left?.validation?.spellbookScore || 0);
      const rightSbScore = Number(right?.validation?.spellbookScore || 0);
      if (Math.abs(rightSbScore - leftSbScore) > 1e-9) {
        return rightSbScore - leftSbScore;
      }
      if (Math.abs(right.score - left.score) > 1e-9) {
        return right.score - left.score;
      }
      const leftLotusScore = Number(left?.validation?.lotusScore || 0);
      const rightLotusScore = Number(right?.validation?.lotusScore || 0);
      if (Math.abs(rightLotusScore - leftLotusScore) > 1e-9) {
        return rightLotusScore - leftLotusScore;
      }
      return left.card.name.localeCompare(right.card.name);
    });

    return merged.slice(0, Math.max(1, limit));
  }

  function computeDirectSynergiesForSeedFaces(seedCard, cards, limit, externalContext = {}) {
    const variants = strategySeedFaceVariants(seedCard);
    if (variants.length <= 1) {
      return computeDirectSynergies(seedCard, cards, limit, externalContext);
    }

    const candidateLimit = Math.max(24, Number(limit) || 1);
    const mergedByKey = new Map();

    variants.forEach((variantSeed) => {
      const direct = computeDirectSynergies(variantSeed, cards, candidateLimit, externalContext);
      direct.forEach((entry) => {
        const key = String(entry?.card?.key || "").trim();
        if (!key) {
          return;
        }
        const existing = mergedByKey.get(key);
        if (!existing) {
          mergedByKey.set(key, {
            ...entry,
            _seedFaces: new Set([variantSeed.name])
          });
          return;
        }

        existing.score = Math.max(Number(existing.score || 0), Number(entry.score || 0));
        existing.featureScore = Math.max(Number(existing.featureScore || 0), Number(entry.featureScore || 0));
        existing.ruleScore = Math.max(Number(existing.ruleScore || 0), Number(entry.ruleScore || 0));
        existing.colorScore = Math.max(Number(existing.colorScore || 0), Number(entry.colorScore || 0));
        existing.comboBoost = Math.max(Number(existing.comboBoost || 0), Number(entry.comboBoost || 0));
        existing.spellbookBoost = Math.max(Number(existing.spellbookBoost || 0), Number(entry.spellbookBoost || 0));
        existing.lotusBoost = Math.max(Number(existing.lotusBoost || 0), Number(entry.lotusBoost || 0));
        const existingValidation = Number(existing?.validation?.score || 0);
        const nextValidation = Number(entry?.validation?.score || 0);
        if (nextValidation >= existingValidation) {
          existing.validation = entry.validation;
        }
        existing._seedFaces.add(variantSeed.name);
      });
    });

    return mergeDirectSynergyEntries(mergedByKey, limit);
  }

  function computeDirectSynergies(seedCard, cards, limit, externalContext = {}) {
    const spellbookBoostByKey = externalContext?.boostByKey instanceof Map
      ? externalContext.boostByKey
      : new Map();
    const refsByKey = externalContext?.refsByKey instanceof Map
      ? externalContext.refsByKey
      : new Map();
    const popularityByKey = externalContext?.popularityByKey instanceof Map
      ? externalContext.popularityByKey
      : new Map();
    const lotusBoostByKey = externalContext?.lotusBoostByKey instanceof Map
      ? externalContext.lotusBoostByKey
      : new Map();
    const lotusRefsByKey = externalContext?.lotusRefsByKey instanceof Map
      ? externalContext.lotusRefsByKey
      : new Map();
    const variantCount = Math.max(1, Number(externalContext?.variantCount) || 0);
    const lotusPostCount = Math.max(1, Number(externalContext?.lotusPostCount) || 0);

    const scored = cards
      .filter((card) => card.key !== seedCard.key)
      .map((card) => {
        const sim = strategySimilarity(seedCard, card);
        const spellbookRaw = Number(spellbookBoostByKey?.get?.(card.key) || 0);
        const spellbookBoost = Math.max(0, spellbookRaw);
        const spellbookRefs = Math.max(0, Number(refsByKey?.get?.(card.key) || 0));
        const spellbookPopularity = Math.max(0, Number(popularityByKey?.get?.(card.key) || 0));
        const lotusRefs = Math.max(0, Number(lotusRefsByKey?.get?.(card.key) || 0));
        const lotusBoost = Math.max(0, Number(lotusBoostByKey?.get?.(card.key) || 0));
        const scryfallExists = Boolean(String(card?.scryfallId || "").trim());
        const externalBoost = Math.min(0.55, spellbookBoost * 0.42 + lotusBoost * 0.35);
        const score = clampScore(sim.score + externalBoost);
        const validation = computeDirectApiValidation(
          scryfallExists,
          spellbookRefs,
          spellbookPopularity,
          variantCount,
          lotusRefs,
          lotusPostCount
        );
        return {
          card,
          score,
          heuristicScore: clampScore(sim.score),
          validation,
          featureScore: sim.featureScore,
          ruleScore: sim.ruleScore,
          colorScore: sim.colorScore,
          comboBoost: sim.comboBoost,
          spellbookBoost,
          lotusBoost,
          provenance_tags: buildStrategyProvenanceTags({
            heuristic: true,
            spellbook: spellbookRefs > 0 || spellbookBoost > 0,
            lotus: lotusRefs > 0 || lotusBoost > 0
          })
        };
      });

    const results = scored
      .filter((entry) => entry.score > 0.05 && (
        entry.ruleScore > 0.02 ||
        entry.featureScore > 0.08 ||
        entry.comboBoost > 0 ||
        entry.spellbookBoost > 0.12 ||
        entry.lotusBoost > 0.08
      ))
      .sort((left, right) => {
        const leftSbScore = Number(left?.validation?.spellbookScore || 0);
        const rightSbScore = Number(right?.validation?.spellbookScore || 0);
        if (Math.abs(rightSbScore - leftSbScore) > 1e-9) {
          return rightSbScore - leftSbScore;
        }
        if (Math.abs(right.score - left.score) > 1e-9) {
          return right.score - left.score;
        }
        const leftLotusScore = Number(left?.validation?.lotusScore || 0);
        const rightLotusScore = Number(right?.validation?.lotusScore || 0);
        if (Math.abs(rightLotusScore - leftLotusScore) > 1e-9) {
          return rightLotusScore - leftLotusScore;
        }
        if (Math.abs((right.spellbookBoost || 0) - (left.spellbookBoost || 0)) > 1e-9) {
          return (right.spellbookBoost || 0) - (left.spellbookBoost || 0);
        }
        if (Math.abs((right.comboBoost || 0) - (left.comboBoost || 0)) > 1e-9) {
          return (right.comboBoost || 0) - (left.comboBoost || 0);
        }
        return left.card.name.localeCompare(right.card.name);
      });

    if (results.length === 0 && scored.length > 0) {
      const fallback = scored
        .slice()
        .sort((left, right) => {
          if (Math.abs(right.heuristicScore - left.heuristicScore) > 1e-9) {
            return right.heuristicScore - left.heuristicScore;
          }
          if (Math.abs((right.ruleScore || 0) - (left.ruleScore || 0)) > 1e-9) {
            return (right.ruleScore || 0) - (left.ruleScore || 0);
          }
          if (Math.abs((right.featureScore || 0) - (left.featureScore || 0)) > 1e-9) {
            return (right.featureScore || 0) - (left.featureScore || 0);
          }
          if (Math.abs((right.colorScore || 0) - (left.colorScore || 0)) > 1e-9) {
            return (right.colorScore || 0) - (left.colorScore || 0);
          }
          return left.card.name.localeCompare(right.card.name);
        });
      return fallback.slice(0, Math.max(1, limit));
    }

    return results.slice(0, Math.max(1, limit));
  }

  function computeDirectApiValidation(scryfallExists, spellbookRefs, spellbookPopularity, variantCount, lotusRefs = 0, lotusPostCount = 0) {
    const scryfallScore = scryfallExists ? 1 : 0;
    const refRatio = spellbookRefs > 0 ? Math.min(1, spellbookRefs / Math.max(1, variantCount)) : 0;
    const popularityNorm = spellbookPopularity > 0
      ? Math.min(1, Math.log10(spellbookPopularity + 1) / 4)
      : 0;
    const spellbookScore = clampScore(refRatio * 0.75 + popularityNorm * 0.25);
    const lotusScore = lotusRefs > 0 ? Math.min(1, lotusRefs / Math.max(1, lotusPostCount)) : 0;
    const normalized = clampScore(spellbookScore * 0.7 + lotusScore * 0.3);

    return {
      score: clampScore(normalized),
      scryfallScore: clampScore(scryfallScore),
      spellbookScore: clampScore(spellbookScore),
      lotusScore: clampScore(lotusScore),
      spellbookRefs,
      spellbookPopularity,
      lotusRefs,
      lotusPostCount,
      scryfallExists
    };
  }

  function computeGroupApiValidation(group, spellbookContext) {
    const cards = Array.isArray(group?.cards) ? group.cards : [];
    if (cards.length === 0) {
      return {
        score: 0,
        variantHits: 0,
        variantHitsFull: 0,
        variantHitsPartial: 0,
        matchedPopularity: 0,
        scryfallCoverage: 0
      };
    }

    const seedKey = String(cards[0]?.key || "").trim();
    const nonSeedKeys = cards
      .map((card) => String(card?.key || "").trim())
      .filter((key) => key && key !== seedKey);
    if (nonSeedKeys.length === 0) {
      return {
        score: 0,
        variantHits: 0,
        variantHitsFull: 0,
        variantHitsPartial: 0,
        matchedPopularity: 0,
        scryfallCoverage: 0
      };
    }

    const keySet = new Set(nonSeedKeys);
    const variants = Array.isArray(spellbookContext?.variants) ? spellbookContext.variants : [];
    let variantHitsFull = 0;
    let variantHitsPartial = 0;
    let matchedPopularity = 0;
    let coverageSum = 0;
    const minMatchCount = Math.min(2, keySet.size);

    variants.forEach((variant) => {
      const variantKeys = new Set(Array.isArray(variant?.cardKeys) ? variant.cardKeys : []);
      let matchedCount = 0;
      keySet.forEach((key) => {
        if (variantKeys.has(key)) {
          matchedCount += 1;
        }
      });

      const fullMatch = matchedCount === keySet.size;
      if (fullMatch) {
        variantHitsFull += 1;
      }

      const partialMatch = matchedCount >= minMatchCount;
      if (partialMatch) {
        variantHitsPartial += 1;
      }

      if (!partialMatch) {
        return;
      }

      const coverage = matchedCount / keySet.size;
      if (!fullMatch) {
        coverageSum += coverage;
      } else {
        coverageSum += 1;
      }
      matchedPopularity += Math.max(0, Number(variant?.popularity) || 0) * coverage;
    });

    const variantCount = Math.max(1, Number(spellbookContext?.variantCount) || 0);
    const hitRatio = Math.min(1, coverageSum / variantCount);
    const popularityNorm = matchedPopularity > 0
      ? Math.min(1, Math.log10(matchedPopularity + 1) / 5)
      : 0;
    const spellbookScore = clampScore(hitRatio * 0.75 + popularityNorm * 0.25);
    const scryfallKnown = cards.filter((card) => Boolean(String(card?.scryfallId || "").trim())).length;
    const scryfallCoverage = scryfallKnown / cards.length;

    const normalized = spellbookScore;

    return {
      score: clampScore(normalized),
      scryfallScore: clampScore(scryfallCoverage),
      spellbookScore: clampScore(spellbookScore),
      variantHits: variantHitsFull,
      variantHitsFull,
      variantHitsPartial,
      matchedPopularity,
      scryfallCoverage
    };
  }

  function computeSynergyGroups(seedCard, directEntries, allCards, groupLimit, externalContext = {}) {
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
        const groupScoreParts = sumStrategyScoreParts([
          left.scoreParts,
          right.scoreParts,
          support ? buildStrategyScoreParts(support.card, support.score * 0.35, 0, 0) : null
        ]);
        groups.push({
          cards: packageCards,
          coreCards: split.coreCards,
          sideCards: split.sideCards,
          sourceType: "heuristic",
          provenance_tags: buildStrategyGroupProvenanceTags({
            cards: packageCards,
            sourceType: "heuristic"
          }, externalContext),
          bridgeName: left.score >= right.score ? left.card.name : right.card.name,
          score: groupScore,
          scoreParts: groupScoreParts,
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

  function computeSpellbookSynergyGroups(seedCard, directEntries, allCards, groupLimit, spellbookContext, options = {}) {
    const variants = Array.isArray(spellbookContext?.variants) ? spellbookContext.variants : [];
    if (variants.length === 0) {
      return [];
    }
    const allowExternalCards = options?.allowExternalCards !== false;
    const externalContext = options?.externalContext && typeof options.externalContext === "object"
      ? options.externalContext
      : {};

    const cardsByKey = new Map((Array.isArray(allCards) ? allCards : []).map((card) => [card.key, card]));
    const directByKey = new Map((Array.isArray(directEntries) ? directEntries : []).map((entry) => [entry.card.key, entry]));
    const directKeys = new Set(directByKey.keys());
    const seedKey = seedCard.key;

    const groups = [];
    const seen = new Set();

    variants.forEach((variant) => {
      const variantCards = Array.isArray(variant?.cards) ? variant.cards : [];
      const variantKeys = variantCards.length > 0
        ? variantCards.map((entry) => String(entry?.key || "").trim()).filter(Boolean)
        : (Array.isArray(variant?.cardKeys) ? variant.cardKeys : []);
      if (!variantKeys.includes(seedKey)) {
        return;
      }

      const partnerEntries = (variantCards.length > 0
        ? variantCards
        : variantKeys.map((key) => ({ key, name: key })))
        .map((entry) => {
          const key = String(entry?.key || "").trim();
          if (!key || key === seedKey) {
            return null;
          }
          const existing = cardsByKey.get(key);
          if (existing) {
            return { key, card: existing };
          }
          if (!allowExternalCards) {
            return null;
          }
          const fallbackName = String(entry?.name || "").trim() || key;
          const placeholder = createStrategySpellbookPlaceholderCard(fallbackName, key);
          cardsByKey.set(key, placeholder);
          return { key, card: placeholder };
        })
        .filter(Boolean)
        .map((item) => ({
          ...item,
          score: Number(directByKey.get(item.key)?.score || 0)
        }))
        .sort((left, right) => right.score - left.score);

      if (partnerEntries.length === 0) {
        return;
      }

      const packageCards = [seedCard].concat(partnerEntries.map((item) => item.card));
      const signature = packageCards.map((card) => card.key).sort().join("|");
      if (seen.has(signature)) {
        return;
      }
      seen.add(signature);

      const split = splitGroupCoreAndSide(seedCard, packageCards);
      const popularity = Number(variant?.popularity) || 0;
      const popularityFactor = Math.min(1, Math.log10(popularity + 1) / 4);
      const avgDirectScore = partnerEntries.reduce((sum, item) => sum + item.score, 0) / partnerEntries.length;
      const groupScore = clampScore(avgDirectScore * 0.8 + popularityFactor * 0.2);
      const groupScoreParts = sumStrategyScoreParts([
        ...partnerEntries.map((item) => directByKey.get(item.key)?.scoreParts || null),
        { collection: 0, scryfall: 0, spellbook: popularityFactor * 0.2 }
      ]);
      const comboDetails = spellbookNormalizeText(spellbookDescription(variant));

      const orderedNames = partnerEntries
        .map((item) => item.card?.name)
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
        sourceType: "spellbook",
        provenance_tags: buildStrategyGroupProvenanceTags({
          cards: packageCards,
          sourceType: "spellbook"
        }, externalContext),
        sourceVariantId: String(variant?.id || "").trim(),
        comboDetails,
        bridgeName,
        score: groupScore,
        scoreParts: groupScoreParts,
        lineA,
        lineB
      });
    });

    return groups.slice(0, Math.max(1, groupLimit));
  }

  function mergeStrategyGroups(primaryGroups, fallbackGroups, limit) {
    const cap = Math.max(1, Number(limit) || 1);
    const out = [];
    const seen = new Set();
    const hasPrimary = Array.isArray(primaryGroups) && primaryGroups.length > 0;
    const hasFallback = Array.isArray(fallbackGroups) && fallbackGroups.length > 0;
    const reserveFallbackSlot = hasPrimary && hasFallback && cap > 1;
    const primaryCap = reserveFallbackSlot ? cap - 1 : cap;

    function pushUniqueOne(group) {
      if (!group || !Array.isArray(group.cards)) {
        return false;
      }
      const key = group.cards.map((card) => card.key).sort().join("|");
      if (seen.has(key)) {
        return false;
      }
      seen.add(key);
      out.push(group);
      return true;
    }

    function pushUnique(groups, maxCount = Infinity) {
      for (const group of (Array.isArray(groups) ? groups : [])) {
        if (out.length >= cap || maxCount <= 0) {
          break;
        }
        const pushed = pushUniqueOne(group);
        if (pushed) {
          maxCount -= 1;
        }
      }
    }

    pushUnique(primaryGroups, primaryCap);
    if (out.length < cap) {
      pushUnique(fallbackGroups);
    }
    if (out.length < cap) {
      pushUnique(primaryGroups);
    }
    return out.slice(0, cap);
  }

  function createStrategySpellbookPlaceholderCard(name, key) {
    return {
      key: String(key || "").trim(),
      name: String(name || key || "").trim(),
      row: {},
      quantity: 1,
      features: {},
      semantics: {},
      colors: [],
      scryfallId: "",
      source: "spellbook"
    };
  }

  async function enrichStrategyGroupsWithScryfall(groups, strategyLanguage = "en") {
    const safeGroups = Array.isArray(groups) ? groups : [];
    if (safeGroups.length === 0) {
      return safeGroups;
    }

    const language = normalizeStrategyLanguage(strategyLanguage);
    const fetchTargets = [];
    const seen = new Set();

    safeGroups.forEach((group) => {
      (Array.isArray(group?.cards) ? group.cards : []).forEach((card) => {
        const cardName = String(card?.name || "").trim();
        if (!cardName) {
          return;
        }
        const hasScryfallId = Boolean(String(card?.scryfallId || rowValue(card?.row, ["scryfall_id", "scry_fall_id"])).trim());
        if (hasScryfallId) {
          return;
        }
        const key = normalizeStrategyName(card?.key || cardName);
        if (!key) {
          return;
        }
        const cacheKey = `${language}::${key}`;
        if (seen.has(cacheKey)) {
          return;
        }
        seen.add(cacheKey);
        fetchTargets.push({ cacheKey, cardName });
      });
    });

    for (let i = 0; i < fetchTargets.length; i += 6) {
      const chunk = fetchTargets.slice(i, i + 6);
      await Promise.all(chunk.map((target) => getStrategyNamedCardFromScryfall(target.cardName, language, target.cacheKey)));
    }

    safeGroups.forEach((group) => {
      (Array.isArray(group?.cards) ? group.cards : []).forEach((card) => {
        const cardName = String(card?.name || "").trim();
        const key = normalizeStrategyName(card?.key || cardName);
        if (!key) {
          return;
        }
        const cacheKey = `${language}::${key}`;
        const enriched = state.strategy.namedCardCache.get(cacheKey);
        if (!enriched || !enriched.row) {
          return;
        }

        card.row = {
          ...(card.row && typeof card.row === "object" ? card.row : {}),
          ...enriched.row
        };
        if (!card.scryfallId) {
          card.scryfallId = enriched.scryfallId;
        }
        if ((!Array.isArray(card.colors) || card.colors.length === 0) && Array.isArray(enriched.colors)) {
          card.colors = enriched.colors;
        }
        card.source = "scryfall";
      });
    });

    return safeGroups;
  }

  async function getStrategyNamedCardFromScryfall(cardName, strategyLanguage = "en", forcedCacheKey = "") {
    const safeName = String(cardName || "").trim();
    if (!safeName) {
      return null;
    }

    const language = normalizeStrategyLanguage(strategyLanguage);
    const cacheKey = forcedCacheKey || `${language}::${normalizeStrategyName(safeName)}`;
    if (state.strategy.namedCardCache.has(cacheKey)) {
      return state.strategy.namedCardCache.get(cacheKey);
    }
    if (state.strategy.namedCardPromiseCache.has(cacheKey)) {
      return state.strategy.namedCardPromiseCache.get(cacheKey);
    }

    const task = fetchScryfallNamedCardRecord(safeName, language)
      .then((record) => {
        if (!record || record.object !== "card") {
          state.strategy.namedCardCache.set(cacheKey, null);
          return null;
        }

        const row = mapScryfallCardToStrategyRow(record, language);
        const enriched = {
          row,
          scryfallId: String(row?.scryfall_id || "").trim(),
          colors: Array.isArray(record?.colors)
            ? record.colors.filter((code) => "WUBRG".includes(String(code || "").toUpperCase()))
            : []
        };
        state.strategy.namedCardCache.set(cacheKey, enriched);
        return enriched;
      })
      .catch(() => {
        state.strategy.namedCardCache.set(cacheKey, null);
        return null;
      })
      .finally(() => {
        state.strategy.namedCardPromiseCache.delete(cacheKey);
      });

    state.strategy.namedCardPromiseCache.set(cacheKey, task);
    return task;
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
      const fullMeta = `score ${formatDecimal(entry.score)} | rules ${formatDecimal(entry.ruleScore || 0)}${comboPart}${spellbookPart}`;
      fragment.appendChild(
        createStrategyCardElement(
          entry.card,
          `#${index + 1}`,
          {
            metaTitle: fullMeta,
            validationMeta: buildDirectValidationMeta(entry.validation),
            provenanceTags: readStrategyProvenanceTags(entry)
          }
        )
      );
    });
    target.appendChild(fragment);
  }

  function buildDirectValidationMeta(validation) {
    const spellbook = Math.max(0, Math.min(1, Number(validation?.spellbookScore) || 0));
    const lotus = Math.max(0, Math.min(1, Number(validation?.lotusScore) || 0));
    const global = Math.max(0, Math.min(1, Number(validation?.score) || 0));
    const refs = Math.max(0, Number(validation?.spellbookRefs) || 0);
    const lotusRefs = Math.max(0, Number(validation?.lotusRefs) || 0);
    return {
      spellbook: `SB ${Math.round(spellbook * 100)}%`,
      lotus: `LN ${Math.round(lotus * 100)}%`,
      global: `API ${Math.round(global * 100)}%`,
      refs: `refs SB ${refs} | LN ${lotusRefs}`
    };
  }

  function renderGroupCards(groups, seedName, spellbookContext = {}) {
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
      const sourceType = normalizeGroupSourceType(group?.sourceType);
      article.className = `strategy-group is-${sourceType}`;
      const groupValidation = computeGroupApiValidation(group, spellbookContext);

      const title = document.createElement("p");
      title.className = "strategy-group-title";
      title.textContent = `Groupe ${index + 1} | Global ${Math.round((groupValidation.score || 0) * 100)}%`;
      const sourceBadge = document.createElement("span");
      sourceBadge.className = `strategy-group-source-badge is-${sourceType}`;
      sourceBadge.textContent = sourceType === "spellbook" ? "Source: Spellbook" : "Source: Heuristique";
      title.appendChild(sourceBadge);
      appendStrategyProvenanceBadges(title, readStrategyProvenanceTags(group));
      article.appendChild(title);

      const validationLine = document.createElement("p");
      validationLine.className = "strategy-group-line";
      validationLine.textContent = formatGroupValidationText(groupValidation);
      article.appendChild(validationLine);

      const coreCards = Array.isArray(group.coreCards) && group.coreCards.length > 0
        ? group.coreCards
        : group.cards.slice(0, Math.min(2, group.cards.length));
      const coreKeySet = new Set(coreCards.map((card) => card.key));
      const sideCards = Array.isArray(group.sideCards)
        ? group.sideCards
        : group.cards.filter((card) => !coreKeySet.has(card.key));

      const comboDetailsText = String(group?.comboDetails || "").trim();
      if (sourceType === "spellbook") {
        const details = document.createElement("details");
        details.className = "strategy-group-details";
        const summary = document.createElement("summary");
        const variantId = String(group?.sourceVariantId || "").trim();
        summary.textContent = variantId
          ? `Details combo (Spellbook #${variantId})`
          : "Details combo (Spellbook)";
        details.appendChild(summary);

        const detailsText = document.createElement("p");
        detailsText.className = "strategy-group-line";
        detailsText.textContent = comboDetailsText || "Aucun detail API Spellbook pour cette variante.";
        details.appendChild(detailsText);

        article.appendChild(details);
      }

      const coreSection = document.createElement("div");
      coreSection.className = "strategy-group-section is-core";
      const coreSectionTitle = document.createElement("p");
      coreSectionTitle.className = "strategy-group-section-title";
      coreSectionTitle.textContent = "Core cards";
      coreSection.appendChild(coreSectionTitle);
      const coreGrid = document.createElement("div");
      coreGrid.className = "strategy-group-cards is-core";
      coreCards.forEach((card) => {
        coreGrid.appendChild(createStrategyCardElement(card, "", { compact: true }));
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
          sideGrid.appendChild(createStrategyCardElement(card, "", { compact: true }));
        });
        sideSection.appendChild(sideGrid);
        article.appendChild(sideSection);
      }

      fragment.appendChild(article);
    });

    target.appendChild(fragment);
  }

  function formatGroupValidationText(validation) {
    const hitsFull = Math.max(0, Number(validation?.variantHitsFull) || 0);
    const hitsPartial = Math.max(0, Number(validation?.variantHitsPartial) || 0);
    const spellbook = Math.max(0, Math.min(1, Number(validation?.spellbookScore) || 0));
    return `full SB ${hitsFull} | partiel SB ${hitsPartial} | SB ${Math.round(spellbook * 100)}%`;
  }

  function normalizeGroupSourceType(sourceType) {
    return String(sourceType || "").toLowerCase() === "spellbook" ? "spellbook" : "heuristic";
  }

  function createStrategyCardElement(card, metaLine, options = {}) {
    const compact = Boolean(options.compact);
    const badge = String(options.badge || "").trim();
    const badgeTone = String(options.badgeTone || "core").toLowerCase();
    const metaTitle = String(options.metaTitle || "").trim();
    const validationMeta = options.validationMeta && typeof options.validationMeta === "object"
      ? options.validationMeta
      : null;
    const provenanceTags = readStrategyProvenanceTags({ provenance_tags: options.provenanceTags });
    const cardNode = document.createElement("article");
    cardNode.className = compact ? "strategy-card is-compact" : "strategy-card";

    const scryfallId = String(card?.scryfallId || rowValue(card?.row, ["scryfall_id", "scry_fall_id"]) || "").trim();
    const imageVersion = "art_crop";
    const imageUrl = scryfallCdnImageUrl(scryfallId, imageVersion);
    const hasImage = Boolean(imageUrl);
    if (!hasImage) {
      cardNode.classList.add("is-placeholder");
    }
    const setCode = rowValue(card.row, ["set_code", "set"]).toUpperCase();
    const collector = rowValue(card.row, ["collector_number"]);
    const setLine = [setCode, collector ? `#${collector}` : ""].filter(Boolean).join(" ");
    const manaCost = rowValue(card.row, ["mana_cost", "manacost", "mana"]);

    const art = document.createElement("div");
    art.className = "strategy-card-art";
    if (hasImage) {
      const img = document.createElement("img");
      img.src = imageUrl;
      img.alt = card.name;
      img.loading = "lazy";
      img.decoding = "async";
      img.addEventListener("error", () => {
        art.innerHTML = "";
        const fallback = document.createElement("span");
        fallback.className = "strategy-card-fallback";
        fallback.textContent = "Image indisponible";
        art.appendChild(fallback);
        cardNode.classList.add("is-placeholder");
      }, { once: true });
      art.appendChild(img);
    } else {
      const fallback = document.createElement("span");
      fallback.className = "strategy-card-fallback";
      fallback.textContent = "Image indisponible";
      art.appendChild(fallback);
    }
    cardNode.appendChild(art);

    const body = document.createElement("div");
    body.className = "strategy-card-body";

    const nameLine = document.createElement("p");
    nameLine.className = "strategy-card-name";
    nameLine.textContent = card.name;
    body.appendChild(nameLine);

    const oracleText = rowValue(card.row, ["oracle_text", "printed_text", "card_text", "rules_text", "description"]);
    if (compact && oracleText) {
      cardNode.title = oracleText;
    }

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
    appendStrategyProvenanceBadges(badgesLine, provenanceTags);
    if (badgesLine.childNodes.length > 0) {
      body.appendChild(badgesLine);
    }

    if (metaLine) {
      const rankingLine = document.createElement("p");
      rankingLine.className = "strategy-card-meta";
      rankingLine.textContent = metaLine;
      if (metaTitle) {
        rankingLine.title = metaTitle;
      }
      body.appendChild(rankingLine);
    }

    if (!compact && validationMeta) {
      const validationRow = document.createElement("div");
      validationRow.className = "strategy-validation-row";

      const sbChip = document.createElement("span");
      sbChip.className = "strategy-validation-chip is-spellbook";
      sbChip.textContent = validationMeta.spellbook;
      validationRow.appendChild(sbChip);

      if (validationMeta.lotus) {
        const lotusChip = document.createElement("span");
        lotusChip.className = "strategy-validation-chip is-source-scryfall";
        lotusChip.textContent = validationMeta.lotus;
        validationRow.appendChild(lotusChip);
      }

      const glChip = document.createElement("span");
      glChip.className = "strategy-validation-chip is-global";
      glChip.textContent = validationMeta.global;
      validationRow.appendChild(glChip);

      if (validationMeta.refs) {
        const refsChip = document.createElement("span");
        refsChip.className = "strategy-validation-chip is-refs";
        refsChip.textContent = validationMeta.refs;
        validationRow.appendChild(refsChip);
      }

      body.appendChild(validationRow);
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

    cardNode.addEventListener("mouseenter", () => {
      renderStrategyCardPreview(card, cardNode);
    });
    cardNode.addEventListener("click", () => {
      renderStrategyCardPreview(card, cardNode);
    });

    if (card?.row && typeof card.row === "object") {
      cardNode.classList.add("is-interactive", "data-row");
      bindRowPreviewEvents(cardNode, card.row);
    }

    return cardNode;
  }

  function strategyOriginPartsFromDirectEntry(entry) {
    const source = String(entry?.card?.source || "collection").toLowerCase();
    const spellbookBoost = Math.max(0, Number(entry?.spellbookBoost) || 0);
    const collection = source === "scryfall" ? 0 : 1;
    const api = (source === "scryfall" ? 1 : 0) + Math.min(0.7, spellbookBoost * 0.4);
    return {
      collection,
      api,
      apiDetails: {
        scryfall: source === "scryfall" ? 1 : 0,
        spellbook: Math.min(0.7, spellbookBoost * 0.4)
      }
    };
  }

  function strategyOriginPartsFromGroup(group) {
    const cards = Array.isArray(group?.cards) ? group.cards : [];
    if (cards.length === 0) {
      return { collection: 0, api: 0, apiDetails: { scryfall: 0, spellbook: 0 } };
    }

    let collection = 0;
    let api = 0;
    cards.forEach((card) => {
      const source = String(card?.source || "collection").toLowerCase();
      if (source === "scryfall") {
        api += 1;
      } else {
        collection += 1;
      }
    });

    return {
      collection,
      api,
      apiDetails: {
        scryfall: api,
        spellbook: 0
      }
    };
  }

  function buildStrategyScoreParts(card, internalScore = 0, scryfallBoost = 0, spellbookBoost = 0) {
    const sourceType = String(card?.source || "collection").toLowerCase();
    const internal = Math.max(0, Number(internalScore) || 0);
    const scryfall = Math.max(0, Number(scryfallBoost) || 0);
    const spellbook = Math.max(0, Number(spellbookBoost) || 0);
    if (sourceType === "scryfall") {
      return {
        collection: 0,
        scryfall: internal + scryfall,
        spellbook
      };
    }
    return {
      collection: internal,
      scryfall,
      spellbook
    };
  }

  function sumStrategyScoreParts(partsList) {
    const total = { collection: 0, scryfall: 0, spellbook: 0 };
    (Array.isArray(partsList) ? partsList : []).forEach((parts) => {
      if (!parts || typeof parts !== "object") {
        return;
      }
      total.collection += Math.max(0, Number(parts.collection) || 0);
      total.scryfall += Math.max(0, Number(parts.scryfall) || 0);
      total.spellbook += Math.max(0, Number(parts.spellbook) || 0);
    });
    return total;
  }

  function createStrategyScoreBar(parts) {
    const safe = {
      collection: Math.max(0, Number(parts?.collection) || 0),
      scryfall: Math.max(0, Number(parts?.scryfall) || 0),
      spellbook: Math.max(0, Number(parts?.spellbook) || 0)
    };
    const apiTotal = safe.scryfall + safe.spellbook;
    const total = safe.collection + apiTotal;
    if (total <= 0) {
      return null;
    }

    const wrap = document.createElement("div");
    wrap.className = "strategy-score-wrap";

    const bar = document.createElement("div");
    bar.className = "strategy-score-bar";

    const segments = [
      {
        key: "collection",
        label: "Collection",
        value: safe.collection,
        className: "is-collection"
      },
      {
        key: "api",
        label: "API",
        value: apiTotal,
        className: "is-api"
      }
    ].filter((segment) => segment.value > 0);

    segments.forEach((segment) => {
      const node = document.createElement("span");
      node.className = `strategy-score-segment ${segment.className}`;
      node.style.width = `${(segment.value / total) * 100}%`;
      if (segment.key === "api") {
        node.title = `${segment.label}: ${formatDecimal(segment.value)} (${Math.round((segment.value / total) * 100)}%) | Scryfall ${formatDecimal(safe.scryfall)} + Spellbook ${formatDecimal(safe.spellbook)}`;
      } else {
        node.title = `${segment.label}: ${formatDecimal(segment.value)} (${Math.round((segment.value / total) * 100)}%)`;
      }
      bar.appendChild(node);
    });

    const legend = document.createElement("div");
    legend.className = "strategy-score-legend";
    legend.textContent = segments
      .map((segment) => `${segment.label} ${Math.round((segment.value / total) * 100)}%`)
      .join(" | ");

    wrap.appendChild(bar);
    wrap.appendChild(legend);
    return wrap;
  }

  function createStrategyOriginBar(parts) {
    const safe = {
      collection: Math.max(0, Number(parts?.collection) || 0),
      api: Math.max(0, Number(parts?.api) || 0),
      apiScryfall: Math.max(0, Number(parts?.apiDetails?.scryfall) || 0),
      apiSpellbook: Math.max(0, Number(parts?.apiDetails?.spellbook) || 0)
    };
    const total = safe.collection + safe.api;
    if (total <= 0) {
      return null;
    }

    const wrap = document.createElement("div");
    wrap.className = "strategy-origin-wrap";

    const bar = document.createElement("div");
    bar.className = "strategy-origin-bar";

    const segments = [
      { label: "Collection", value: safe.collection, className: "is-collection" },
      { label: "API", value: safe.api, className: "is-api" }
    ].filter((segment) => segment.value > 0);

    segments.forEach((segment) => {
      const node = document.createElement("span");
      node.className = `strategy-origin-segment ${segment.className}`;
      node.style.width = `${(segment.value / total) * 100}%`;
      if (segment.className === "is-api") {
        node.title = `${segment.label}: ${Math.round((segment.value / total) * 100)}% | Scryfall ${formatDecimal(safe.apiScryfall)} + Spellbook ${formatDecimal(safe.apiSpellbook)}`;
      } else {
        node.title = `${segment.label}: ${Math.round((segment.value / total) * 100)}%`;
      }
      bar.appendChild(node);
    });

    const legend = document.createElement("div");
    legend.className = "strategy-origin-legend";
    legend.textContent = `Origine synergie: Collection ${Math.round((safe.collection / total) * 100)}% | API ${Math.round((safe.api / total) * 100)}%`;

    wrap.appendChild(bar);
    wrap.appendChild(legend);
    return wrap;
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
    applyStaticUiTranslations();

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
    bindSpellbookControls();
    bindDeckAnalysisControls();
    loadDeckStateFromStorage();

    nodes.collections.form.addEventListener("submit", async (event) => {
      event.preventDefault();

      const selected = nodes.collections.fileInput.files && nodes.collections.fileInput.files[0];
      if (!selected) {
        renderCollection({
          ok: false,
          table: t("tabs_collections"),
          error: currentUiLanguage() === "fr" ? "Selectionne un csv." : "Select a CSV file."
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
          table: t("tabs_collections"),
          error: payload?.error || (currentUiLanguage() === "fr" ? "Import impossible" : "Import failed")
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
      setCollectionPickButtonLabel(t("pick_csv"));
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
          table: t("tabs_decks"),
          error: currentUiLanguage() === "fr" ? "Selectionne un fichier." : "Select a file."
        });
        return;
      }

      const sourceType = inferDeckSourceType(selected.name);
      const payload = await uploadCollection(selected, sourceType, "");
      if (!payload || payload.ok !== true) {
        if (state.activeTab === "decks") {
          renderCollection(payload || {
            ok: false,
            error: currentUiLanguage() === "fr" ? "Impossible de charger le deck." : "Unable to load deck."
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
      setDeckPickButtonLabel(t("pick_deck_file"));
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
    selectTab(state.activeTab);
  }

  init().catch((error) => {
    renderCollection({
      ok: false,
      error: String(error)
    });
  });
})();
