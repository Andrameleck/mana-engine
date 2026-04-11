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
  fetchLotusNoirPosts as fetchLotusNoirPostsApi,
  fetchSpellbookVariants,
  fetchStrategyBridgeEquation
} from "./api.js?v=20260411-synergy-groups";
import {
  renderCollection,
  getCollectionLanguage,
  setCollectionLanguage,
  bindRowPreviewEvents,
  renderManaCostCell
} from "./ui.js?v=20260411-synergy-groups";

(function bootstrap() {
  const UI_TEXT = {
    en: {
      tabs_collections: "Collections",
      tabs_decks: "Decks",
      tabs_strategy: "Strategy",
      tabs_calculdev: "Calcul_dev",
      tabs_spellbook: "Spellbook",
      subtitle_collections: "Create and manage multiple collection folders.",
      subtitle_decks: "Import and browse multiple decks.",
      subtitle_strategy: "Workspace for synergy and combo exploration.",
      subtitle_calculdev: "Sandbox for testing mechanical synergy changes.",
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
      strategy_waiting: "Waiting for computation.",
      strategy_no_result: "No result.",
      strategy_run_hint_direct: "Run a computation to see direct synergies.",
      strategy_run_hint_group: "Run a computation to see card groups.",
      strategy_choose_seed: "Choose a seed card then click Compute.",
      strategy_source_unavailable: "Select a loaded collection folder to enable computation.",
      strategy_preview_hint: "Hover or select a synergy card to display details.",
      strategy_preview_oracle_fallback: "No Oracle text available.",
      spellbook_hint: "Type a card name to query Commander Spellbook.",
      spellbook_none: "No result.",
      spellbook_search: "Search",
      compute: "Compute",
      strategy_seed_label: "Seed card",
      strategy_direct_limit_label: "Top direct synergies",
      strategy_group_limit_label: "Top groups",
      strategy_include_spellbook_label: "Include combo references (Commander Spellbook)",
      strategy_include_spellbook_hint: "Prioritize cards present in public combos",
      strategy_include_lotus_hint: "Cross-check with LotusNoir community decks (beta)",
      strategy_mana_filter_label: "Mana filter (allowed colors)",
      direct_synergies: "Direct synergies",
      card_groups: "Card groups",
      new_collection_folder: "New collection folder",
      collections_folders: "Collection folders",
      import_deck: "Import deck",
      decks_list: "Deck list",
      source_meta_waiting: "Select a collection folder to enable computation."
    },
    fr: {
      tabs_collections: "Collections",
      tabs_decks: "Decks",
      tabs_strategy: "Strategy",
      tabs_calculdev: "Calcul_dev",
      tabs_spellbook: "Spellbook",
      subtitle_collections: "Creer et gerer plusieurs dossiers de collection.",
      subtitle_decks: "Importer et visualiser plusieurs decks.",
      subtitle_strategy: "Zone reservee au module de strategies.",
      subtitle_calculdev: "Bac a sable pour tester les changements de mecaniques.",
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
      strategy_waiting: "En attente de calcul.",
      strategy_no_result: "Aucun resultat.",
      strategy_run_hint_direct: "Lance un calcul pour voir les synergies directes.",
      strategy_run_hint_group: "Lance un calcul pour voir les groupes de cartes.",
      strategy_choose_seed: "Choisis une carte seed puis clique sur Calculer.",
      strategy_source_unavailable: "Selectionne un dossier collection charge pour activer le calcul.",
      strategy_preview_hint: "Survole ou selectionne une carte de synergie pour afficher ses details.",
      strategy_preview_oracle_fallback: "Aucun texte Oracle disponible.",
      spellbook_hint: "Saisis une carte pour interroger Commander Spellbook.",
      spellbook_none: "Aucun resultat.",
      spellbook_search: "Rechercher",
      compute: "Calculer",
      strategy_seed_label: "Carte seed",
      strategy_direct_limit_label: "Top synergies directes",
      strategy_group_limit_label: "Top groupes",
      strategy_include_spellbook_label: "Inclure reference combos (Commander Spellbook)",
      strategy_include_spellbook_hint: "Prioriser les cartes presentes dans les combos publics",
      strategy_include_lotus_hint: "Croiser avec les decks communautaires LotusNoir (beta)",
      strategy_mana_filter_label: "Filtre mana (couleurs autorisees)",
      direct_synergies: "Synergies directes",
      card_groups: "Groupes de cartes",
      new_collection_folder: "Nouveau dossier collection",
      collections_folders: "Dossiers collections",
      import_deck: "Import deck",
      decks_list: "Decks",
      source_meta_waiting: "Selectionne un dossier collection pour activer le calcul."
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
      calculdev: {
        title: t("tabs_calculdev"),
        subtitle: t("subtitle_calculdev")
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
    calculdev: {
      title: "Calcul_dev",
      subtitle: "Bac a sable pour tester les changements de mecaniques."
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
      seedNameB: "",
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
    },
    calculdev: {
      cardName: "",
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
      includeSpellbookCombos: false,
      includeLotusSignals: false,
      loading: false,
      error: "",
      payload: null,
      runToken: 0,
      progressValue: 0,
      progressLabel: "",
      progressTimer: null,
      progressStartedAt: 0
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
  const STRATEGY_PREVIEW_STATE = {
    activeElement: null,
    requestToken: 0,
    cache: new Map()
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
      seedBInput: document.getElementById("strategy-seed-b-input"),
      seedList: document.getElementById("strategy-seed-list"),
      directLimitInput: document.getElementById("strategy-direct-limit"),
      groupLimitInput: document.getElementById("strategy-group-limit"),
      includeSpellbookInput: document.getElementById("strategy-include-spellbook"),
      includeLotusInput: document.getElementById("strategy-include-lotus"),
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
    },
    calculdev: {
      sourceMeta: document.getElementById("calculdev-source-meta"),
      seedInput: document.getElementById("calculdev-seed-input"),
      directLimitInput: document.getElementById("calculdev-direct-limit"),
      groupLimitInput: document.getElementById("calculdev-group-limit"),
      includeSpellbookInput: document.getElementById("calculdev-include-spellbook"),
      includeLotusInput: document.getElementById("calculdev-include-lotus"),
      manaFilterInputs: Array.from(document.querySelectorAll("input[data-calculdev-mana]")),
      runButton: document.getElementById("calculdev-run-btn"),
      status: document.getElementById("calculdev-status"),
      directList: document.getElementById("calculdev-direct-list"),
      groupList: document.getElementById("calculdev-group-list"),
      progressWrap: document.getElementById("calculdev-progress-wrap"),
      progressText: document.getElementById("calculdev-progress-text"),
      progressValue: document.getElementById("calculdev-progress-value"),
      progressBar: document.getElementById("calculdev-progress-bar"),
      previewTitle: document.getElementById("calculdev-card-preview-title"),
      previewText: document.getElementById("calculdev-card-preview-text"),
      previewImage: document.getElementById("calculdev-card-preview-image"),
      previewMeta: document.getElementById("calculdev-card-preview-meta")
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
      calculdev: t("tabs_calculdev"),
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
    setText("#tab-collections .panel-head h3", t("new_collection_folder"));
    setText("#tab-collections .panel.panel-compact:nth-of-type(2) .panel-head h3", t("collections_folders"));
    setText("#tab-decks .panel-head h3", t("import_deck"));
    setText("#tab-decks .deck-list-panel .panel-head h3", t("decks_list"));
    setText("#tab-strategy #strategy-status", t("strategy_waiting"));
    setText("#strategy-seed-label", t("strategy_seed_label"));
    setText("#strategy-direct-limit-label", t("strategy_direct_limit_label"));
    setText("#strategy-group-limit-label", t("strategy_group_limit_label"));
    setText("#strategy-include-spellbook-label", t("strategy_include_spellbook_label"));
    setText("#strategy-include-spellbook-hint", t("strategy_include_spellbook_hint"));
    setText("#strategy-include-lotus-hint", t("strategy_include_lotus_hint"));
    setText("#strategy-mana-filter-label", t("strategy_mana_filter_label"));
    setText("#tab-strategy .strategy-result-block:nth-of-type(1) .strategy-result-head h4", t("direct_synergies"));
    setText("#tab-strategy .strategy-result-block:nth-of-type(2) .strategy-result-head h4", t("card_groups"));
    setText("#spellbook-run-btn", t("spellbook_search"));
    setText("#strategy-run-btn", t("compute"));
    setText("#strategy-source-meta", t("source_meta_waiting"));
    setText("#strategy-card-preview-text", t("strategy_preview_hint"));
    setText("#spellbook-status", t("spellbook_hint"));
    setText("#tab-calculdev #calculdev-status", t("strategy_waiting"));
    setText("#tab-calculdev .strategy-result-block:nth-of-type(1) .strategy-result-head h4", t("direct_synergies"));
    setText("#tab-calculdev .strategy-result-block:nth-of-type(2) .strategy-result-head h4", t("card_groups"));
    setText("#tab-calculdev .panel-head h3", "Calcul_dev Playground");
    setText("#calculdev-seed-label", t("strategy_seed_label"));
    setText("#calculdev-direct-limit-label", t("strategy_direct_limit_label"));
    setText("#calculdev-group-limit-label", t("strategy_group_limit_label"));
    setText("#calculdev-include-spellbook-hint", currentUiLanguage() === "fr" ? "Option sandbox reservee" : "Sandbox-only option");
    setText("#calculdev-include-lotus-hint", currentUiLanguage() === "fr" ? "Option sandbox reservee" : "Sandbox-only option");
    setText("#calculdev-mana-filter-label", t("strategy_mana_filter_label"));
    setText("#calculdev-run-btn", currentUiLanguage() === "fr" ? "Calculer" : "Compute");
    setText("#calculdev-card-preview-text", t("strategy_preview_hint"));
    const calculSeed = document.getElementById("calculdev-seed-input");
    if (calculSeed) {
      calculSeed.setAttribute("placeholder", "Sheoldred, the Apocalypse");
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

    if (strategyNodes.seedList) {
      strategyNodes.seedInput.setAttribute("list", "strategy-seed-list");
      strategyNodes.seedBInput?.setAttribute("list", "strategy-seed-list");
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
    strategyNodes.seedBInput?.addEventListener("input", () => {
      const query = String(strategyNodes.seedBInput.value || "").trim();
      state.strategy.seedNameB = query;
      updateStrategySeedAutocomplete(query);
    });

    strategyNodes.seedInput.addEventListener("keydown", (event) => {
      if (event.key === "Enter") {
        event.preventDefault();
        runStrategyComputation();
      }
    });
    strategyNodes.seedBInput?.addEventListener("keydown", (event) => {
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

  function bindCalculDevControls() {
    const calculNodes = nodes.calculdev;
    if (!calculNodes.seedInput || !calculNodes.runButton || !calculNodes.status || !calculNodes.directList || !calculNodes.groupList) {
      return;
    }

    calculNodes.seedInput.value = state.calculdev.cardName;
    if (calculNodes.directLimitInput) {
      calculNodes.directLimitInput.value = String(state.calculdev.directLimit);
    }
    if (calculNodes.groupLimitInput) {
      calculNodes.groupLimitInput.value = String(state.calculdev.groupLimit);
    }
    if (calculNodes.includeSpellbookInput) {
      calculNodes.includeSpellbookInput.checked = state.calculdev.includeSpellbookCombos === true;
    }
    if (calculNodes.includeLotusInput) {
      calculNodes.includeLotusInput.checked = state.calculdev.includeLotusSignals === true;
    }
    if (Array.isArray(calculNodes.manaFilterInputs) && calculNodes.manaFilterInputs.length > 0) {
      calculNodes.manaFilterInputs.forEach((inputNode) => {
        const code = String(inputNode?.dataset?.calculdevMana || "").toUpperCase();
        if (!code || !Object.prototype.hasOwnProperty.call(state.calculdev.manaFilter, code)) {
          return;
        }
        inputNode.checked = state.calculdev.manaFilter[code] === true;
        inputNode.addEventListener("change", () => {
          state.calculdev.manaFilter[code] = inputNode.checked === true;
        });
      });
    }
    if (calculNodes.sourceMeta) {
      calculNodes.sourceMeta.textContent = currentUiLanguage() === "fr"
        ? "Mode sandbox: calcul mecanique direct via /synergy/find."
        : "Sandbox mode: direct mechanical scoring via /synergy/find.";
      calculNodes.sourceMeta.style.display = "block";
    }
    resetCalculDevProgress();
    resetCalculDevPreview();
    calculNodes.directList.innerHTML = `<p class="muted">${escapeHtml(currentUiLanguage() === "fr" ? "Lance un calcul pour voir les synergies directes." : "Run a computation to see direct synergies.")}</p>`;
    calculNodes.groupList.innerHTML = `<p class="muted">${escapeHtml(currentUiLanguage() === "fr" ? "Lance un calcul pour afficher les details techniques." : "Run a computation to show technical details.")}</p>`;

    calculNodes.seedInput.addEventListener("keydown", (event) => {
      if (event.key === "Enter") {
        event.preventDefault();
        runCalculDevComputation();
      }
    });
    calculNodes.seedInput.addEventListener("input", () => {
      state.calculdev.cardName = String(calculNodes.seedInput.value || "").trim();
    });

    calculNodes.directLimitInput?.addEventListener("change", () => {
      const value = clampInt(calculNodes.directLimitInput.value, 4, 24, 12);
      state.calculdev.directLimit = value;
      calculNodes.directLimitInput.value = String(value);
    });
    calculNodes.groupLimitInput?.addEventListener("change", () => {
      const value = clampInt(calculNodes.groupLimitInput.value, 3, 12, 6);
      state.calculdev.groupLimit = value;
      calculNodes.groupLimitInput.value = String(value);
    });

    calculNodes.includeSpellbookInput?.addEventListener("change", () => {
      state.calculdev.includeSpellbookCombos = calculNodes.includeSpellbookInput.checked === true;
    });
    calculNodes.includeLotusInput?.addEventListener("change", () => {
      state.calculdev.includeLotusSignals = calculNodes.includeLotusInput.checked === true;
    });

    calculNodes.runButton.addEventListener("click", () => {
      runCalculDevComputation();
    });
  }

  function setCalculDevProgress(percent, label = "", visible = true) {
    const calculNodes = nodes.calculdev;
    const safePercent = Math.max(0, Math.min(100, Math.round(Number(percent) || 0)));
    state.calculdev.progressValue = safePercent;
    state.calculdev.progressLabel = String(label || "");

    if (calculNodes.progressWrap) {
      calculNodes.progressWrap.classList.toggle("is-hidden", visible !== true);
    }
    if (calculNodes.progressText) {
      calculNodes.progressText.textContent = state.calculdev.progressLabel || (currentUiLanguage() === "fr" ? "Calcul en cours..." : "Computation in progress...");
    }
    if (calculNodes.progressValue) {
      calculNodes.progressValue.textContent = `${safePercent}%`;
    }
    if (calculNodes.progressBar) {
      calculNodes.progressBar.style.width = `${safePercent}%`;
      const track = calculNodes.progressBar.parentElement;
      if (track) {
        track.setAttribute("aria-valuenow", String(safePercent));
      }
    }
  }

  function resetCalculDevProgress() {
    if (state.calculdev.progressTimer) {
      window.clearInterval(state.calculdev.progressTimer);
      state.calculdev.progressTimer = null;
    }
    state.calculdev.progressStartedAt = 0;
    setCalculDevProgress(0, currentUiLanguage() === "fr" ? "En attente du calcul..." : "Waiting for computation...", false);
  }

  function startCalculDevProgress() {
    resetCalculDevProgress();
    state.calculdev.progressStartedAt = Date.now();
    setCalculDevProgress(
      1,
      currentUiLanguage() === "fr"
        ? "Job cree, attente du serveur..."
        : "Job created, waiting for server...",
      true
    );
  }

  function finishCalculDevProgress(payload, success = true, statusPayload = null) {
    const timings = payload?.timings && typeof payload.timings === "object" ? payload.timings : {};
    const totalMs = Number(timings.total_ms || timings.totalMs || 0);
    const totalSeconds = totalMs > 0 ? (totalMs / 1000).toFixed(1) : "";

    if (success) {
      const label = currentUiLanguage() === "fr"
        ? (totalSeconds ? `Calcul termine en ${totalSeconds}s` : "Calcul termine")
        : (totalSeconds ? `Completed in ${totalSeconds}s` : "Completed");
      setCalculDevProgress(100, label, true);
      return;
    }

    const backendPercent = Number(statusPayload?.progress?.percent || state.calculdev.progressValue || 0);
    const backendStage = String(statusPayload?.progress?.stage || "").trim();
    const fallbackLabel = currentUiLanguage() === "fr"
      ? "Calcul interrompu"
      : "Computation stopped";
    const detailLabel = totalSeconds
      ? `${fallbackLabel} (${totalSeconds}s)`
      : (backendStage || fallbackLabel);
    setCalculDevProgress(Math.max(0, Math.min(99, backendPercent)), detailLabel, true);
  }

  function sleepMs(durationMs = 0) {
    const safeDuration = Math.max(0, Number(durationMs) || 0);
    return new Promise((resolve) => {
      window.setTimeout(resolve, safeDuration);
    });
  }

  async function pollCalculDevJob(jobId, runToken, cardName = "") {
    const calculNodes = nodes.calculdev;
    if (!jobId) {
      throw new Error(currentUiLanguage() === "fr" ? "Job backend introuvable." : "Missing backend job.");
    }

    let completedWithoutResultCount = 0;

    while (runToken === state.calculdev.runToken) {
      const statusPayload = typeof window.fetchSynergyJobStatus === "function"
        ? await window.fetchSynergyJobStatus(jobId)
        : { ok: false, error: "Missing fetchSynergyJobStatus helper." };

      if (runToken !== state.calculdev.runToken) {
        return null;
      }

      if (!statusPayload || statusPayload.ok !== true) {
        throw new Error(String(statusPayload?.error || "Unable to fetch synergy job status."));
      }

      const progress = statusPayload.progress && typeof statusPayload.progress === "object"
        ? statusPayload.progress
        : {};
      const percent = Number(progress.percent || 0);
      const stage = String(progress.stage || "").trim();
      if (stage || Number.isFinite(percent)) {
        setCalculDevProgress(percent, stage || (currentUiLanguage() === "fr" ? "Calcul en cours..." : "Computation in progress..."), true);
        if (calculNodes.status) {
          calculNodes.status.textContent = currentUiLanguage() === "fr"
            ? `${stage || "Calcul en cours..."} (${Math.round(Math.max(0, Math.min(100, percent || 0)))}%)`
            : `${stage || "Computation in progress..."} (${Math.round(Math.max(0, Math.min(100, percent || 0)))}%)`;
        }
      }

      const jobStatus = String(statusPayload.status || "").toLowerCase();
      if (jobStatus === "completed") {
        if (statusPayload.result && statusPayload.result.ok === true) {
          return statusPayload.result;
        }

        completedWithoutResultCount += 1;
        setCalculDevProgress(99, currentUiLanguage() === "fr" ? "Finalisation du resultat..." : "Finalizing result...", true);
        if (completedWithoutResultCount >= 8) {
          throw new Error(currentUiLanguage() === "fr"
            ? "Le job est termine mais le resultat reste indisponible."
            : "The job completed but the result is still unavailable.");
        }
        await sleepMs(250);
        continue;
      }
      if (jobStatus === "error") {
        finishCalculDevProgress(null, false, statusPayload);
        throw new Error(String(statusPayload.error || (currentUiLanguage() === "fr" ? "Le job backend a echoue." : "Background job failed.")));
      }

      await sleepMs(700);
    }

    return null;
  }

  function formatCalculDevStatus(count, cardName, payload = null) {
    const safeCount = Number(count || 0);
    const timings = payload?.timings && typeof payload.timings === "object" ? payload.timings : {};
    const pipeline = payload?.pipeline && typeof payload.pipeline === "object" ? payload.pipeline : {};
    const totalMs = Number(timings.total_ms || 0);
    const totalSeconds = totalMs > 0 ? (totalMs / 1000).toFixed(1) : "";

    const parts = currentUiLanguage() === "fr"
      ? [`${safeCount} resultat(s) pour "${cardName}".`]
      : [`${safeCount} result(s) for "${cardName}".`];

    if (pipeline.catalog_size) {
      parts.push(currentUiLanguage() === "fr"
        ? `catalogue scanne: ${pipeline.catalog_size}`
        : `catalog scanned: ${pipeline.catalog_size}`);
    }
    if (pipeline.deep_score_count) {
      parts.push(currentUiLanguage() === "fr"
        ? `scoring profond: ${pipeline.deep_score_count}`
        : `deep scoring: ${pipeline.deep_score_count}`);
    }
    if (pipeline.package_candidate_count) {
      parts.push(currentUiLanguage() === "fr"
        ? `packages: ${pipeline.package_candidate_count}`
        : `packages: ${pipeline.package_candidate_count}`);
    }
    if (totalSeconds) {
      parts.push(currentUiLanguage() === "fr"
        ? `temps: ${totalSeconds}s`
        : `time: ${totalSeconds}s`);
    }

    return parts.join(" | ");
  }

  function buildCalculDevSynergyPayload(cardName, maxResults, groupLimit, colorIdentity = []) {
    const safeMaxResults = clampInt(maxResults, 4, 24, 12);
    const safeGroupLimit = clampInt(groupLimit, 3, 12, 6);
    const payload = {
      card_name: String(cardName || "").trim(),
      format: "commander",
      max_results: safeMaxResults,
      top_k: Math.max(safeMaxResults * 3, safeGroupLimit * 4, 24),
      package_top_n: Math.max(Math.min(safeGroupLimit * 2, 16), 6),
      max_groups: safeGroupLimit,
      max_group_size: 4,
      max_group_paths: Math.max(48, safeGroupLimit * 12)
    };
    if (Array.isArray(colorIdentity) && colorIdentity.length > 0) {
      payload.color_identity = colorIdentity;
    }
    return payload;
  }

  async function runCalculDevComputation() {
    const calculNodes = nodes.calculdev;
    if (!calculNodes.seedInput || !calculNodes.runButton || !calculNodes.status || !calculNodes.directList || !calculNodes.groupList) {
      return;
    }

    const cardName = String(calculNodes.seedInput.value || "").trim();
    const maxResults = clampInt(calculNodes.directLimitInput?.value, 4, 24, state.calculdev.directLimit || 12);
    const groupLimit = clampInt(calculNodes.groupLimitInput?.value, 3, 12, state.calculdev.groupLimit || 6);
    const colorIdentity = selectedCalculDevColors();
    const formatName = "commander";

    state.calculdev.cardName = cardName;
    state.calculdev.directLimit = maxResults;
    state.calculdev.groupLimit = groupLimit;
    if (calculNodes.directLimitInput) {
      calculNodes.directLimitInput.value = String(maxResults);
    }
    if (calculNodes.groupLimitInput) {
      calculNodes.groupLimitInput.value = String(groupLimit);
    }
    state.calculdev.manaFilter = {
      W: colorIdentity.includes("W"),
      U: colorIdentity.includes("U"),
      B: colorIdentity.includes("B"),
      R: colorIdentity.includes("R"),
      G: colorIdentity.includes("G"),
      C: colorIdentity.includes("C")
    };

    if (!cardName) {
      calculNodes.status.textContent = currentUiLanguage() === "fr"
        ? "Saisis une carte cible."
        : "Type a target card.";
      return;
    }

    const runToken = ++state.calculdev.runToken;
    state.calculdev.loading = true;
    state.calculdev.error = "";
    if (calculNodes.runButton) {
      calculNodes.runButton.disabled = true;
    }
    calculNodes.status.textContent = currentUiLanguage() === "fr"
      ? `Calcul mecanique en cours pour "${cardName}"...`
      : `Mechanical scoring in progress for "${cardName}"...`;
    startCalculDevProgress();
    calculNodes.directList.innerHTML = `<p class="muted">${currentUiLanguage() === "fr" ? "Chargement..." : "Loading..."}</p>`;
    calculNodes.groupList.innerHTML = `<p class="muted">${currentUiLanguage() === "fr" ? "Chargement..." : "Loading..."}</p>`;
    resetCalculDevPreview();

    const payload = buildCalculDevSynergyPayload(cardName, maxResults, groupLimit, colorIdentity);

    try {
      const jobStart = typeof window.startSynergyJob === "function"
        ? await window.startSynergyJob(payload)
        : { ok: false, error: "Missing startSynergyJob helper." };
      if (runToken !== state.calculdev.runToken) {
        return;
      }
      if (!jobStart || jobStart.ok !== true || !jobStart.job_id) {
        state.calculdev.error = String(jobStart?.error || (currentUiLanguage() === "fr" ? "Impossible de lancer le job backend." : "Unable to start backend job."));
        finishCalculDevProgress(null, false, jobStart);
        calculNodes.status.textContent = currentUiLanguage() === "fr"
          ? `Erreur: ${state.calculdev.error}`
          : `Error: ${state.calculdev.error}`;
        calculNodes.directList.innerHTML = `<p class="muted">${escapeHtml(currentUiLanguage() === "fr" ? "Aucun resultat." : "No result.")}</p>`;
        calculNodes.groupList.innerHTML = `<p class="muted">${escapeHtml(currentUiLanguage() === "fr" ? "Aucun resultat." : "No result.")}</p>`;
        return;
      }

      setCalculDevProgress(
        Number(jobStart?.progress?.percent || 2),
        String(jobStart?.progress?.stage || (currentUiLanguage() === "fr" ? "Job backend lance..." : "Background job started...")),
        true
      );

      const out = await pollCalculDevJob(jobStart.job_id, runToken, cardName);
      if (runToken !== state.calculdev.runToken || !out) {
        return;
      }

      state.calculdev.payload = out;
      state.calculdev.error = "";
      const groupedResults = resolveCalculDevGroups(out);
      renderCalculDevResults(out.best_matches, cardName, groupedResults);
      const count = Array.isArray(out.best_matches) ? out.best_matches.length : 0;
      finishCalculDevProgress(out, true);
      calculNodes.status.textContent = formatCalculDevStatus(count, cardName, out);
    } catch (error) {
      if (runToken !== state.calculdev.runToken) {
        return;
      }
      state.calculdev.error = String(error?.message || error || "unexpected error");
      finishCalculDevProgress(null, false);
      calculNodes.status.textContent = currentUiLanguage() === "fr"
        ? `Erreur: ${state.calculdev.error}`
        : `Error: ${state.calculdev.error}`;
      calculNodes.directList.innerHTML = `<p class="muted">${escapeHtml(currentUiLanguage() === "fr" ? "Aucun resultat." : "No result.")}</p>`;
      calculNodes.groupList.innerHTML = `<p class="muted">${escapeHtml(currentUiLanguage() === "fr" ? "Aucun resultat." : "No result.")}</p>`;
    } finally {
      if (runToken === state.calculdev.runToken) {
        state.calculdev.loading = false;
        if (calculNodes.runButton) {
          calculNodes.runButton.disabled = false;
        }
      }
    }
  }

  function resolveCalculDevGroups(payload) {
    const out = payload && typeof payload === "object" ? payload : {};
    const buckets = out.buckets && typeof out.buckets === "object" ? out.buckets : {};

    const pools = [
      out.synergy_groups,
      out.package_lines,
      out.packages,
      buckets?.synergy_groups?.results,
      buckets?.package_lines?.results,
      buckets?.packages?.results
    ];
    const flattened = pools.flatMap((entry) => Array.isArray(entry) ? entry : []);
    if (flattened.length === 0) {
      return [];
    }

    const seen = new Set();
    const deduped = [];
    flattened.forEach((entry, index) => {
      if (!entry || typeof entry !== "object") {
        return;
      }
      const key = String(entry.id || entry.group_id || entry.chain?.member_ids?.join("|") || `group-${index}`);
      if (!key || seen.has(key)) {
        return;
      }
      seen.add(key);
      deduped.push(entry);
    });

    deduped.sort((left, right) => Number(right?.total_score || right?.score || 0) - Number(left?.total_score || left?.score || 0));
    return deduped;
  }

  function selectedCalculDevColors() {
    const calculNodes = nodes.calculdev;
    if (!Array.isArray(calculNodes?.manaFilterInputs) || calculNodes.manaFilterInputs.length === 0) {
      return [];
    }
    const selected = [];
    calculNodes.manaFilterInputs.forEach((inputNode) => {
      const code = String(inputNode?.dataset?.calculdevMana || "").toUpperCase();
      if (!code || !"WUBRGC".includes(code) || inputNode.checked !== true) {
        return;
      }
      selected.push(code);
    });
    return Array.from(new Set(selected));
  }

  function resetCalculDevPreview() {
    const calculNodes = nodes.calculdev;
    if (calculNodes.previewTitle) {
      calculNodes.previewTitle.textContent = currentUiLanguage() === "fr" ? "Carte" : "Card";
    }
    if (calculNodes.previewText) {
      calculNodes.previewText.textContent = currentUiLanguage() === "fr"
        ? "Survole ou selectionne une carte de synergie pour afficher ses details."
        : "Hover or select a synergy card to display details.";
    }
    if (calculNodes.previewImage) {
      calculNodes.previewImage.removeAttribute("src");
      calculNodes.previewImage.classList.add("is-hidden");
    }
    if (calculNodes.previewMeta) {
      calculNodes.previewMeta.innerHTML = "";
    }
  }

  function renderCalculDevCardPreview(entry, cardNode) {
    const calculNodes = nodes.calculdev;
    if (!calculNodes.previewTitle || !calculNodes.previewText || !calculNodes.previewImage || !calculNodes.previewMeta) {
      return;
    }

    calculNodes.previewTitle.textContent = String(entry?.name || "Card");
    const reasons = Array.isArray(entry?.reasons) ? entry.reasons : [];
    calculNodes.previewText.innerHTML = reasons.length > 0
      ? reasons.map((reason) => escapeHtml(String(reason || ""))).join("<br>")
      : escapeHtml(currentUiLanguage() === "fr" ? "Aucune explication." : "No explanation.");

    const cardId = String(entry?.id || "").trim();
    if (isLikelyScryfallId(cardId)) {
      calculNodes.previewImage.src = `https://api.scryfall.com/cards/${encodeURIComponent(cardId)}?format=image&version=normal`;
      calculNodes.previewImage.classList.remove("is-hidden");
    } else {
      calculNodes.previewImage.removeAttribute("src");
      calculNodes.previewImage.classList.add("is-hidden");
    }

    const breakdown = entry?.score_breakdown && typeof entry.score_breakdown === "object"
      ? entry.score_breakdown
      : {};
    const relationClasses = Array.isArray(entry?.relation_classes) ? entry.relation_classes : [];
    calculNodes.previewMeta.innerHTML = `
      <dt>score</dt><dd>${escapeHtml(String(entry?.score ?? 0))}</dd>
      <dt>relations</dt><dd>${escapeHtml(relationClasses.join(", ") || "-")}</dd>
      <dt>event match</dt><dd>${escapeHtml(String(breakdown?.event_production_match ?? 0))}</dd>
      <dt>payoff match</dt><dd>${escapeHtml(String(breakdown?.event_payoff_match ?? 0))}</dd>
      <dt>anti penalty</dt><dd>${escapeHtml(String(breakdown?.anti_penalty ?? 0))}</dd>
    `;

    const directList = calculNodes.directList;
    const groupList = calculNodes.groupList;
    if (directList) {
      Array.from(directList.querySelectorAll(".row-active")).forEach((node) => node.classList.remove("row-active"));
    }
    if (groupList) {
      Array.from(groupList.querySelectorAll(".row-active")).forEach((node) => node.classList.remove("row-active"));
    }
    if (cardNode && typeof cardNode.classList?.add === "function") {
      cardNode.classList.add("row-active");
    }
  }

  function isLikelyScryfallId(value) {
    const raw = String(value || "").trim();
    return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(raw);
  }

  function createCalculDevCardElement(entry, index) {
    const cardNode = document.createElement("article");
    cardNode.className = "strategy-card";

    const cardName = String(entry?.name || "Card");
    const cardId = String(entry?.id || "");
    const imageUrl = isLikelyScryfallId(cardId)
      ? `https://api.scryfall.com/cards/${encodeURIComponent(cardId)}?format=image&version=art_crop`
      : "";

    const art = document.createElement("div");
    art.className = "strategy-card-art";
    if (imageUrl) {
      const img = document.createElement("img");
      img.src = imageUrl;
      img.alt = cardName;
      img.loading = "lazy";
      art.appendChild(img);
    } else {
      const fallback = document.createElement("span");
      fallback.className = "strategy-card-fallback";
      fallback.textContent = currentUiLanguage() === "fr" ? "Image indisponible" : "No image";
      art.appendChild(fallback);
    }
    cardNode.appendChild(art);

    const body = document.createElement("div");
    body.className = "strategy-card-body";

    const nameLine = document.createElement("p");
    nameLine.className = "strategy-card-name";
    nameLine.textContent = cardName;
    body.appendChild(nameLine);

    const badgesLine = document.createElement("div");
    badgesLine.className = "strategy-card-badges";
    appendStrategyCardBadge(badgesLine, `#${index + 1}`, "is-core");
    appendStrategyCardBadge(badgesLine, "Source: API", "is-source-scryfall");
    body.appendChild(badgesLine);

    const scoreLine = document.createElement("p");
    scoreLine.className = "strategy-card-meta";
    scoreLine.textContent = `score ${formatDecimal(Number(entry?.score || 0))}`;
    body.appendChild(scoreLine);

    const relationClasses = Array.isArray(entry?.relation_classes) ? entry.relation_classes : [];
    const relationLine = document.createElement("p");
    relationLine.className = "strategy-card-meta";
    relationLine.textContent = relationClasses.length > 0
      ? relationClasses.join(", ")
      : (currentUiLanguage() === "fr" ? "Aucune relation classee" : "No classified relation");
    body.appendChild(relationLine);

    cardNode.appendChild(body);

    cardNode.addEventListener("mouseenter", () => renderCalculDevCardPreview(entry, cardNode));
    cardNode.addEventListener("click", () => renderCalculDevCardPreview(entry, cardNode));

    return cardNode;
  }

  function calculDevCardImageUrl(cardId, cardName, version = "art_crop") {
    const idValue = String(cardId || "").trim();
    if (isLikelyScryfallId(idValue)) {
      return `https://api.scryfall.com/cards/${encodeURIComponent(idValue)}?format=image&version=${encodeURIComponent(version)}`;
    }
    const nameValue = String(cardName || "").trim();
    if (!nameValue) {
      return "";
    }
    const params = new URLSearchParams({
      exact: nameValue,
      format: "image",
      version: String(version || "art_crop")
    });
    return `https://api.scryfall.com/cards/named?${params.toString()}`;
  }

  function dedupeCalculDevMembers(members) {
    const values = Array.isArray(members) ? members : [];
    const seen = new Set();
    const out = [];
    values.forEach((member, index) => {
      if (!member || typeof member !== "object") {
        return;
      }
      const key = String(member.id || member.name || `member-${index}`).trim().toLowerCase();
      if (!key || seen.has(key)) {
        return;
      }
      seen.add(key);
      out.push(member);
    });
    return out;
  }

  function createCalculDevGroupMemberCard(member, group, options = {}) {
    const tone = String(options.tone || "core").toLowerCase() === "side" ? "side" : "core";
    const cardNode = document.createElement("article");
    cardNode.className = "strategy-card is-compact";

    const cardName = String(member?.name || "Card");
    const cardId = String(member?.id || "");
    const inferredRole = String(member?.inferred_role || member?.role || member?.inferredRole || "member");
    const imageUrl = calculDevCardImageUrl(cardId, cardName, "art_crop");

    const art = document.createElement("div");
    art.className = "strategy-card-art";
    if (imageUrl) {
      const img = document.createElement("img");
      img.src = imageUrl;
      img.alt = cardName;
      img.loading = "lazy";
      art.appendChild(img);
    } else {
      const fallback = document.createElement("span");
      fallback.className = "strategy-card-fallback";
      fallback.textContent = currentUiLanguage() === "fr" ? "Image indisponible" : "No image";
      art.appendChild(fallback);
    }
    cardNode.appendChild(art);

    const body = document.createElement("div");
    body.className = "strategy-card-body";

    const nameLine = document.createElement("p");
    nameLine.className = "strategy-card-name";
    nameLine.textContent = cardName;
    body.appendChild(nameLine);

    const badgesLine = document.createElement("div");
    badgesLine.className = "strategy-card-badges";
    appendStrategyCardBadge(
      badgesLine,
      inferredRole || (currentUiLanguage() === "fr" ? "role inconnu" : "unknown role"),
      tone === "side" ? "is-side" : "is-core"
    );
    body.appendChild(badgesLine);

    const groupScore = Number(group?.total_score || group?.score || 0);
    const scoreLine = document.createElement("p");
    scoreLine.className = "strategy-card-meta";
    scoreLine.textContent = `${currentUiLanguage() === "fr" ? "score groupe" : "group score"} ${formatDecimal(groupScore)}`;
    body.appendChild(scoreLine);

    const category = String(group?.category || group?.bucket_label || group?.group_type || "group");
    const categoryLine = document.createElement("p");
    categoryLine.className = "strategy-card-meta";
    categoryLine.textContent = category;
    body.appendChild(categoryLine);

    cardNode.appendChild(body);

    const reasonLines = Array.isArray(group?.reasons) ? group.reasons.slice(0, 3) : [];
    const previewReasons = [
      currentUiLanguage() === "fr"
        ? `Role dans le groupe: ${inferredRole}`
        : `Role in group: ${inferredRole}`,
      ...reasonLines
    ];
    const previewEntry = {
      id: cardId,
      name: cardName,
      score: Number(group?.total_score || group?.score || 0),
      score_breakdown: group?.score_breakdown && typeof group.score_breakdown === "object" ? group.score_breakdown : {},
      relation_classes: [
        String(group?.bucket || "group"),
        String(group?.group_type || "synergy_group")
      ],
      reasons: previewReasons
    };

    cardNode.addEventListener("mouseenter", () => renderCalculDevCardPreview(previewEntry, cardNode));
    cardNode.addEventListener("click", () => renderCalculDevCardPreview(previewEntry, cardNode));
    return cardNode;
  }

  function renderCalculDevResults(matches, seedName = "", groups = []) {
    const calculNodes = nodes.calculdev;
    if (!calculNodes.directList || !calculNodes.groupList) {
      return;
    }

    const safeMatches = Array.isArray(matches) ? matches : [];
    const safeGroups = Array.isArray(groups) ? groups : [];
    if (safeMatches.length === 0 && safeGroups.length === 0) {
      calculNodes.directList.innerHTML = `<p class="muted">${escapeHtml(currentUiLanguage() === "fr" ? "Aucune synergie directe calculee." : "No direct synergy found.")}</p>`;
      calculNodes.groupList.innerHTML = `<p class="muted">${escapeHtml(currentUiLanguage() === "fr" ? "Aucun groupe de synergie multicarte." : "No multi-card synergy group found.")}</p>`;
      return;
    }

    calculNodes.directList.innerHTML = "";
    if (safeMatches.length === 0) {
      calculNodes.directList.innerHTML = `<p class="muted">${escapeHtml(currentUiLanguage() === "fr" ? "Aucune synergie directe calculee." : "No direct synergy found.")}</p>`;
    } else {
      const directFragment = document.createDocumentFragment();
      safeMatches.forEach((entry, index) => {
        const cardNode = createCalculDevCardElement(entry, index);
        directFragment.appendChild(cardNode);
      });
      calculNodes.directList.appendChild(directFragment);
    }

    const detailLimit = clampInt(state.calculdev.groupLimit, 3, 12, 6);
    calculNodes.groupList.innerHTML = "";

    if (safeGroups.length === 0) {
      calculNodes.groupList.innerHTML = `<p class="muted">${escapeHtml(currentUiLanguage() === "fr" ? "Aucun groupe de synergie multicarte." : "No multi-card synergy group found.")}</p>`;
    } else {
      const fragment = document.createDocumentFragment();
      safeGroups.slice(0, Math.min(detailLimit, safeGroups.length)).forEach((group, index) => {
        const article = document.createElement("article");
        article.className = "strategy-group is-heuristic";

        const title = document.createElement("p");
        title.className = "strategy-group-title";
        const titleLabel = `${String(group?.category || group?.bucket_label || group?.group_type || "Group")} | score ${Number(group?.total_score || group?.score || 0)}`;
        title.textContent = `#${index + 1} ${titleLabel}`;
        const sourceBadge = document.createElement("span");
        sourceBadge.className = "strategy-group-source-badge is-heuristic";
        sourceBadge.textContent = "Source: API";
        title.appendChild(sourceBadge);
        article.appendChild(title);

        const members = Array.isArray(group?.members) ? group.members : [];
        const roleLine = members.map((member) => {
          const memberName = String(member?.name || "Card");
          const inferredRole = String(member?.inferred_role || member?.role || "member");
          return `${memberName} (${inferredRole})`;
        }).join(" -> ");
        const lineNode = document.createElement("p");
        lineNode.className = "strategy-group-line";
        lineNode.textContent = roleLine || String(group?.explanation_text || "");
        article.appendChild(lineNode);

        const matchedEvents = Array.isArray(group?.matched_events) ? group.matched_events : [];
        const eventsNode = document.createElement("p");
        eventsNode.className = "strategy-group-line";
        eventsNode.textContent = matchedEvents.length > 0
          ? `${currentUiLanguage() === "fr" ? "Events" : "Events"}: ${matchedEvents.slice(0, 6).join(", ")}`
          : (currentUiLanguage() === "fr" ? "Aucun event capture." : "No matched events.");
        article.appendChild(eventsNode);

        const packageStructure = group?.package_structure && typeof group.package_structure === "object"
          ? group.package_structure
          : {};
        const coreMembers = dedupeCalculDevMembers([
          packageStructure?.start_member,
          packageStructure?.end_member
        ].filter(Boolean).length > 0
          ? [packageStructure?.start_member, packageStructure?.end_member].filter(Boolean)
          : [members[0], members[members.length - 1]].filter(Boolean));
        const sideMembers = dedupeCalculDevMembers(
          Array.isArray(packageStructure?.intermediate_members)
            ? packageStructure.intermediate_members
            : members.slice(1, Math.max(1, members.length - 1))
        );

        if (coreMembers.length > 0) {
          const coreSection = document.createElement("div");
          coreSection.className = "strategy-group-section is-core";
          const coreSectionTitle = document.createElement("p");
          coreSectionTitle.className = "strategy-group-section-title";
          coreSectionTitle.textContent = currentUiLanguage() === "fr" ? "Cartes core" : "Core cards";
          coreSection.appendChild(coreSectionTitle);
          const coreGrid = document.createElement("div");
          coreGrid.className = "strategy-group-cards is-core";
          coreMembers.forEach((member) => {
            coreGrid.appendChild(createCalculDevGroupMemberCard(member, group, { tone: "core" }));
          });
          coreSection.appendChild(coreGrid);
          article.appendChild(coreSection);
        }

        if (sideMembers.length > 0) {
          const sideSection = document.createElement("div");
          sideSection.className = "strategy-group-section is-side";
          const sideSectionTitle = document.createElement("p");
          sideSectionTitle.className = "strategy-group-section-title";
          sideSectionTitle.textContent = currentUiLanguage() === "fr" ? "Cartes intermediaires" : "Bridge cards";
          sideSection.appendChild(sideSectionTitle);
          const sideGrid = document.createElement("div");
          sideGrid.className = "strategy-group-cards is-side";
          sideMembers.forEach((member) => {
            sideGrid.appendChild(createCalculDevGroupMemberCard(member, group, { tone: "side" }));
          });
          sideSection.appendChild(sideGrid);
          article.appendChild(sideSection);
        }

        const reasons = Array.isArray(group?.reasons) ? group.reasons : [];
        if (reasons.length > 0) {
          const details = document.createElement("details");
          details.className = "strategy-group-details";
          const summary = document.createElement("summary");
          summary.textContent = currentUiLanguage() === "fr" ? "Pourquoi ce groupe" : "Why this group";
          details.appendChild(summary);
          const reasonList = document.createElement("ul");
          reasonList.className = "strategy-group-line";
          reasonList.innerHTML = reasons.slice(0, 5).map((reason) => `<li>${escapeHtml(String(reason || ""))}</li>`).join("");
          details.appendChild(reasonList);
          article.appendChild(details);
        }

        fragment.appendChild(article);
      });
      calculNodes.groupList.appendChild(fragment);
    }

    calculNodes.status.textContent = currentUiLanguage() === "fr"
      ? `${safeMatches.length} synergie(s) directe(s) et ${safeGroups.length} groupe(s) pour ${seedName || "la seed"}.`
      : `${safeMatches.length} direct synergy result(s) and ${safeGroups.length} group(s) for ${seedName || "seed"}.`;
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
          error: currentUiLanguage() === "fr"
            ? "Mode sans collection: utilise une seed libre, puis calcul via Scryfall."
            : "No-collection mode: use a free seed, then compute via Scryfall."
        });
      }
      renderStrategyPanel(payload, meta);
      renderDeckStatsPanel(null);
      return;
    }

    if (state.activeTab === "calculdev") {
      setWorkspaceLowerHidden(true);
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
      strategyNodes.sourceMeta.textContent = currentUiLanguage() === "fr"
        ? `${collectionName} | ${model.cards.length} cartes analysees`
        : `${collectionName} | ${model.cards.length} analyzed cards`;
    }

    const currentCollectionChanged = state.strategy.lastCollectionId !== state.selectedCollectionId;
    state.strategy.lastCollectionId = state.selectedCollectionId;

    if (currentCollectionChanged) {
      state.strategy.seedName = "";
      state.strategy.seedNameB = "";
      strategyNodes.seedInput.value = "";
      if (strategyNodes.seedBInput) {
        strategyNodes.seedBInput.value = "";
      }
      strategyNodes.directList.innerHTML = `<p class="muted">${escapeHtml(t("strategy_run_hint_direct"))}</p>`;
      strategyNodes.groupList.innerHTML = `<p class="muted">${escapeHtml(t("strategy_run_hint_group"))}</p>`;
      strategyNodes.status.textContent = hasCollectionPayload
        ? t("strategy_choose_seed")
        : (currentUiLanguage() === "fr"
            ? "Saisis une carte seed puis clique sur Calculer (mode sans collection)."
            : "Type a seed card then click Compute (no-collection mode).");
      resetStrategyCardPreview();
    }
    if (strategyNodes.seedBInput && !currentCollectionChanged) {
      strategyNodes.seedBInput.value = state.strategy.seedNameB || "";
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

    if (scryfallId) {
      imageNode.src = `https://api.scryfall.com/cards/${encodeURIComponent(scryfallId)}?format=image&version=normal`;
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
    const model = payload && payload.ok === true
      ? getStrategyModelForCollection(collectionId, payload)
      : { cards: [] };
    const includeKnown = isStrategyIncludeKnownEnabled();
    executeStrategyComputation(
      strategyNodes,
      model,
      rawSeedFromUi(strategyNodes),
      rawSeedBFromUi(strategyNodes),
      includeKnown,
      runToken
    )
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

  function rawSeedBFromUi(strategyNodes) {
    return String(strategyNodes.seedBInput?.value || state.strategy.seedNameB || "").trim();
  }

  async function executeStrategyComputation(strategyNodes, model, rawSeed, rawSeedB, includeKnown, runToken) {
    if (runToken !== state.strategy.runToken) {
      return;
    }
    if (!model.cards.length && !includeKnown) {
      strategyNodes.status.textContent = currentUiLanguage() === "fr"
        ? "Collection vide ou cartes non reconnues."
        : "Empty collection or unrecognized cards.";
      strategyNodes.directList.innerHTML = `<p class="muted">${escapeHtml(t("strategy_no_result"))}</p>`;
      strategyNodes.groupList.innerHTML = `<p class="muted">${escapeHtml(t("strategy_no_result"))}</p>`;
      return;
    }

    if (!rawSeed) {
      strategyNodes.status.textContent = currentUiLanguage() === "fr"
        ? "Saisis une carte seed (ex: Entomb)."
        : "Type a seed card (e.g. Entomb).";
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

    let seedCardB = null;
    if (rawSeedB) {
      seedCardB = resolveSeedCard(rawSeedB, activeModel.cards);
      if (!seedCardB && includeKnown) {
        strategyNodes.status.textContent = `Recherche de la cible B "${rawSeedB}" via Scryfall...`;
        seedCardB = await resolveStrategySeedFromScryfall(rawSeedB, strategyLanguage);
        if (runToken !== state.strategy.runToken) {
          return;
        }
      }
      if (!seedCardB) {
        strategyNodes.status.textContent = includeKnown
          ? `Carte cible B "${rawSeedB}" introuvable (collection et Scryfall).`
          : `Carte cible B "${rawSeedB}" introuvable dans la collection.`;
        return;
      }
    }

    if (seedCard.source === "scryfall") {
      activeModel = mergeStrategyModels(activeModel, { cards: [seedCard] });
    }
    if (seedCardB?.source === "scryfall") {
      activeModel = mergeStrategyModels(activeModel, { cards: [seedCardB] });
    }
    const scryfallAddedCount = Math.max(0, activeModel.cards.length - model.cards.length);

    const manaFilterCodes = getActiveStrategyManaFilterCodes();
    const protectedSeedKeys = [seedCard?.key];
    if (seedCardB?.key) {
      protectedSeedKeys.push(seedCardB.key);
    }
    const colorFilteredCards = filterStrategyCardsByMana(activeModel.cards, manaFilterCodes, protectedSeedKeys);
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
    const resolvedSeedB = seedCardB
      ? (resolveSeedCard(seedCardB.name, activeModel.cards) || seedCardB)
      : null;
    state.strategy.seedNameB = resolvedSeedB?.name || rawSeedB || "";
    if (strategyNodes.seedBInput) {
      strategyNodes.seedBInput.value = state.strategy.seedNameB;
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
        { allowExternalCards: manaFilterCodes.length === 0 }
      )
      : [];
    const fallbackGroups = computeSynergyGroups(resolvedSeed, direct, activeModel.cards, groupLimit);
    let groups = mergeStrategyGroups(spellbookGroups, fallbackGroups, groupLimit);
    groups = await enrichStrategyGroupsWithScryfall(groups, getCollectionLanguage());
    if (runToken !== state.strategy.runToken) {
      return;
    }

    renderDirectSynergyCards(direct, resolvedSeed.name);
    renderGroupCards(groups, resolvedSeed.name, spellbookContext);

    const suffix = includeKnown && scryfallAddedCount > 0
      ? (currentUiLanguage() === "fr"
          ? ` (incluant ${scryfallAddedCount} cartes Scryfall)`
          : ` (including ${scryfallAddedCount} Scryfall cards)`)
      : "";
    const manaSuffix = manaFilterCodes.length > 0
      ? (currentUiLanguage() === "fr"
          ? ` | filtre mana ${formatStrategyManaFilter(manaFilterCodes)}`
          : ` | mana filter ${formatStrategyManaFilter(manaFilterCodes)}`)
      : "";

    if (resolvedSeedB && resolvedSeedB.key !== resolvedSeed.key) {
      strategyNodes.status.textContent = `Resolution equation A + n*k + B pour ${resolvedSeed.name} et ${resolvedSeedB.name}...`;
      const bridgeResponse = await fetchStrategyBridgeEquation(
        buildBridgeEquationRequestPayload(activeModel.cards, resolvedSeed, resolvedSeedB, directLimit, spellbookContext)
      );
      if (runToken !== state.strategy.runToken) {
        return;
      }
      if (bridgeResponse?.ok === true && Array.isArray(bridgeResponse.candidates)) {
        const bridgeCandidates = bridgeResponse.candidates.slice(0, directLimit);
        const bridgeDirectEntries = mapBridgeCandidatesToDirectEntries(bridgeCandidates, activeModel.cards);
        const bridgeGroups = mapBridgeCandidatesToGroups(
          bridgeCandidates.slice(0, groupLimit),
          activeModel.cards,
          resolvedSeed,
          resolvedSeedB
        );
        renderDirectSynergyCards(bridgeDirectEntries, `${resolvedSeed.name} -> ${resolvedSeedB.name}`);
        renderGroupCards(bridgeGroups, `${resolvedSeed.name} -> ${resolvedSeedB.name}`, spellbookContext);

        const exactCount = bridgeCandidates.filter((entry) => String(entry?.reference_state || "") === "exact").length;
        const nearCount = bridgeCandidates.filter((entry) => String(entry?.reference_state || "") === "near").length;
        const novelCount = bridgeCandidates.filter((entry) => String(entry?.reference_state || "") === "novel").length;
        strategyNodes.status.textContent = `${resolvedSeed.name} + n*k + ${resolvedSeedB.name}: ${bridgeCandidates.length} candidats (${exactCount} exact, ${nearCount} near, ${novelCount} novel).${suffix}${manaSuffix}`;
        return;
      }
    }

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

  function filterStrategyCardsByMana(cards, selectedCodes, seedKeys = []) {
    const safeCards = Array.isArray(cards) ? cards : [];
    const selected = new Set(Array.isArray(selectedCodes) ? selectedCodes : []);
    if (selected.size === 0) {
      return safeCards;
    }
    const protectedKeys = Array.isArray(seedKeys) ? seedKeys : [seedKeys];
    const normalizedSeedKeys = new Set(
      protectedKeys
        .map((entry) => normalizeStrategyName(entry))
        .filter(Boolean)
    );
    return safeCards.filter((card) => {
      if (normalizedSeedKeys.size > 0 && normalizedSeedKeys.has(normalizeStrategyName(card?.key))) {
        return true;
      }
      const cardColors = Array.isArray(card?.colors) ? card.colors.filter((code) => "WUBRG".includes(code)) : [];
      if (cardColors.length === 0) {
        return selected.has("C");
      }
      return cardColors.every((code) => selected.has(code));
    });
  }

  function buildBridgeEquationRequestPayload(cards, seedA, seedB, limit, spellbookContext) {
    const safeCards = Array.isArray(cards) ? cards : [];
    const bridgeCards = safeCards
      .filter((card) => card && card.key)
      .map((card) => ({
        id: String(card.key || "").trim(),
        name: String(card.name || card.key || "").trim(),
        features: { ...(card.features || {}) },
        colors: Array.isArray(card.colors) ? card.colors : []
      }));

    return {
      cards: bridgeCards,
      seed_a: String(seedA?.key || "").trim(),
      seed_b: String(seedB?.key || "").trim(),
      n: 2,
      depth_n: 3,
      top_k: 50,
      top_n: clampInt(limit, 1, 100, 20),
      max_missing_cards: 2,
      known_synergies: mapSpellbookContextToKnownSynergies(spellbookContext)
    };
  }

  function mapSpellbookContextToKnownSynergies(spellbookContext) {
    const variants = Array.isArray(spellbookContext?.variants) ? spellbookContext.variants : [];
    return variants
      .filter((variant) => Array.isArray(variant?.cardKeys) && variant.cardKeys.length >= 2)
      .map((variant, index) => {
        const popularity = Number(variant?.popularity) || 0;
        const weight = Math.max(1, Math.log10(popularity + 1) + 1);
        return {
          source: "commander_spellbook",
          label: `spellbook_variant_${index + 1}`,
          cards: variant.cardKeys,
          weight
        };
      });
  }

  function mapBridgeCandidatesToDirectEntries(candidates, cards) {
    const byKey = new Map();
    (Array.isArray(cards) ? cards : []).forEach((card) => {
      if (card?.key) {
        byKey.set(card.key, card);
      }
    });

    return (Array.isArray(candidates) ? candidates : []).map((candidate) => {
      const bridgeKey = String(candidate?.bridge_id || "").trim();
      const bridgeName = String(candidate?.bridge_name || bridgeKey || "Bridge").trim();
      const card = byKey.get(bridgeKey) || {
        key: bridgeKey || normalizeStrategyName(bridgeName),
        name: bridgeName || bridgeKey || "Bridge",
        row: {},
        colors: [],
        source: "reference",
        features: {},
        semantics: {}
      };
      const referenceState = String(candidate?.reference_state || "").toLowerCase();
      return {
        card,
        score: Number(candidate?.total_score) || 0,
        ruleScore: Number(candidate?.structural_score) || 0,
        comboBoost: referenceState === "exact" ? 0.4 : (referenceState === "near" ? 0.2 : 0),
        spellbookBoost: referenceState === "novel" ? 0 : 0.1
      };
    });
  }

  function mapBridgeCandidatesToGroups(candidates, cards, seedA, seedB) {
    const byKey = new Map();
    (Array.isArray(cards) ? cards : []).forEach((card) => {
      if (card?.key) {
        byKey.set(card.key, card);
      }
    });

    const toCard = (id, fallbackName = "") => {
      const key = String(id || "").trim();
      if (key && byKey.has(key)) {
        return byKey.get(key);
      }
      return {
        key: key || normalizeStrategyName(fallbackName),
        name: String(fallbackName || key || "Card").trim(),
        row: {},
        colors: [],
        source: "reference",
        features: {},
        semantics: {}
      };
    };

    return (Array.isArray(candidates) ? candidates : []).map((candidate) => {
      const bridgeIds = String(candidate?.bridge_cards || "")
        .split("|")
        .map((entry) => String(entry || "").trim())
        .filter(Boolean);
      const bridgeNames = String(candidate?.bridge_card_names || "")
        .split("|")
        .map((entry) => String(entry || "").trim());

      const coreCards = bridgeIds.length > 0
        ? bridgeIds.map((id, idx) => toCard(id, bridgeNames[idx] || id))
        : [toCard(candidate?.bridge_id, candidate?.bridge_name)];
      const sideCards = [toCard(seedA?.key, seedA?.name), toCard(seedB?.key, seedB?.name)]
        .filter((card) => card?.key && !coreCards.some((core) => core.key === card.key));
      const allCards = [...coreCards, ...sideCards];

      return {
        score: Number(candidate?.total_score) || 0,
        cards: allCards,
        coreCards,
        sideCards,
        lineA: `${seedA?.name || "A"} -> ${candidate?.bridge_name || "bridge"}`,
        lineB: `${candidate?.bridge_name || "bridge"} -> ${seedB?.name || "B"}`
      };
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
          lotusBoost
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
          sourceType: "heuristic",
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

  function computeSpellbookSynergyGroups(seedCard, directEntries, allCards, groupLimit, spellbookContext, options = {}) {
    const variants = Array.isArray(spellbookContext?.variants) ? spellbookContext.variants : [];
    if (variants.length === 0) {
      return [];
    }
    const allowExternalCards = options?.allowExternalCards !== false;

    const cardsByKey = new Map((Array.isArray(allCards) ? allCards : []).map((card) => [card.key, card]));
    const directByKey = new Map((Array.isArray(directEntries) ? directEntries : []).map((entry) => [entry.card.key, entry]));
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
        sourceVariantId: String(variant?.id || "").trim(),
        comboDetails,
        bridgeName,
        score: groupScore,
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
      const lotusPart = entry.lotusBoost > 0 ? ` | lotus ${formatDecimal(entry.lotusBoost)}` : "";
      const fullMeta = `score ${formatDecimal(entry.score)} | rules ${formatDecimal(entry.ruleScore || 0)}${comboPart}${spellbookPart}${lotusPart}`;
      fragment.appendChild(
        createStrategyCardElement(
          entry.card,
          `#${index + 1}`,
          {
            metaTitle: fullMeta,
            validationMeta: buildDirectValidationMeta(entry.validation)
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
    const cardNode = document.createElement("article");
    cardNode.className = compact ? "strategy-card is-compact" : "strategy-card";

    const scryfallId = card.scryfallId || "";
    const imageVersion = "art_crop";
    const imageUrl = scryfallId
      ? `https://api.scryfall.com/cards/${encodeURIComponent(scryfallId)}?format=image&version=${encodeURIComponent(imageVersion)}`
      : "";
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
    attachDbActionEvents();
    bindStrategyControls();
    bindCalculDevControls();
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
    selectTab(state.activeTab);
  }

  init().catch((error) => {
    renderCollection({
      ok: false,
      error: String(error)
    });
  });
})();
