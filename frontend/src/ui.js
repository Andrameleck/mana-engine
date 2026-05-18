import {
  addCardToStoredCollection,
  removeCardFromStoredCollection,
  getStoredCollection
} from "./api.js";

const COMPACT_COLUMN_ORDER = [
  "quantity",
  "name",
  "oracle_text",
  "abilities",
  "type_line",
  "mana_cost",
  "cmc",
  "colors",
  "color_identity",
  "set",
  "set_code",
  "collector_number",
  "rarity",
  "language",
  "lang",
  "finish",
  "card_condition",
  "notes",
  "scry_fall_id",
  "scryfall_id"
];

const HIDDEN_COLUMN_KEYS = new Set([
  "keywords",
  "keyword"
]);

const DESCRIPTION_COLUMN_KEYS = new Set([
  "oracle_text",
  "printed_text",
  "card_text",
  "rules_text",
  "description",
  "desc"
]);

const MANA_COST_COLUMN_KEYS = new Set([
  "mana_cost",
  "manacost"
]);

const CARD_VIEW_SORT_KEYS = {
  NAME_ASC: "name-asc",
  QUANTITY_DESC: "quantity-desc",
  SET_ASC: "set-asc"
};

const CARD_VIEW_DEFAULT_PAGE_SIZE = 48;

const UI_STATE = {
  language: loadSavedLanguage(),
  rows: [],
  rawColumns: [],
  columns: [],
  tablePageSize: 200,
  cardPageSize: CARD_VIEW_DEFAULT_PAGE_SIZE,
  pageSize: 200,
  currentPage: 1,
  viewMode: "table",
  searchQuery: "",
  sortKey: CARD_VIEW_SORT_KEYS.NAME_ASC,
  selectedColors: [],
  previewDockEnabled: true,
  editMode: false,
  activeViewKey: "",
  viewStateByKey: new Map(),
  currentCollectionId: "",
  currentCollectionMeta: null,
  currentPayload: null
};

const PREVIEW_STATE = {
  locked: false,
  activeRow: null,
  activeElement: null,
  hideTimer: null,
  requestToken: 0,
  cache: new Map()
};

const UI_HANDLERS = {
  reloadStoredCollection: null,
  setDeckPane: null
};

const UI_I18N = {
  en: {
    no_data: "No data",
    no_column: "No column to display.",
    no_match: "No card matches your search.",
    main_deck: "Main Deck",
    sideboard: "Sideboard",
    cards: "Cards",
    rows: "Rows",
    page: "page",
    card: "Card",
    preview_hint: "Hover or select a card to show details.",
    card_preview_alt: "Card preview",
    no_oracle: "No oracle text available.",
    cm_price_loading: "Cardmarket: loading...",
    cm_price_na: "Cardmarket: n/a",
    cm_price_label: "Cardmarket:",
    no_set_info: "No set info",
    no_data_loaded: "No data loaded."
  },
  fr: {
    no_data: "Aucune donnee",
    no_column: "Aucune colonne a afficher.",
    no_match: "Aucune carte ne correspond a ta recherche.",
    main_deck: "Main Deck",
    sideboard: "Sideboard",
    cards: "Cartes",
    rows: "Lignes",
    page: "page",
    card: "Carte",
    preview_hint: "Survole ou selectionne une carte pour afficher les details.",
    card_preview_alt: "Apercu carte",
    no_oracle: "Aucun texte oracle disponible.",
    cm_price_loading: "Cardmarket: chargement...",
    cm_price_na: "Cardmarket: n/d",
    cm_price_label: "Cardmarket:",
    no_set_info: "Aucune info d'edition",
    no_data_loaded: "Aucune donnee chargee."
  }
};

function uiText(key) {
  const lang = UI_STATE.language === "fr" ? "fr" : "en";
  return UI_I18N[lang]?.[key] || UI_I18N.fr?.[key] || key;
}

let releaseScrollbarSync = null;
const TILE_MANA_CACHE = new Map();
const TILE_PRICE_CACHE = new Map();
const DECK_ROW_METADATA_CACHE = new Map();
const DECK_ROW_HYDRATION_TASKS = new Map();
let DECK_ROW_HYDRATION_TOKEN = 0;

initPreviewEvents();

function renderCollection(payload) {
  const title = document.getElementById("table-title");
  const wrap = document.getElementById("table-wrap");
  const summary = document.getElementById("load-summary");
  const tablePanel = title?.closest(".table-panel");
  const isCollectionsContext = String(payload?.ui_context || "").toLowerCase() === "collections";
  const isDecksContext = String(payload?.ui_context || "").toLowerCase() === "decks";
  UI_STATE.currentPayload = payload || null;
  UI_STATE.currentCollectionId = String(payload?.collection?.id || "");
  UI_STATE.currentCollectionMeta = payload?.collection || null;

  tablePanel?.classList.toggle("is-collection-view", isCollectionsContext);
  tablePanel?.classList.toggle("is-deck-view", isDecksContext);
  wrap.innerHTML = "";
  wrap.classList.remove("is-card-view");
  wrap.classList.remove("is-card-view-deck");
  wrap.removeAttribute("data-table");
  setPreviewDockMode(false);
  releaseTableScrollbarSync();

  if (!payload || payload.ok !== true) {
    const dbHints = Array.isArray(payload?.available_tables) && payload.available_tables.length > 0
      ? ` Tables disponibles: ${payload.available_tables.join(", ")}`
      : "";
    title.textContent = payload?.table || "Table";
    wrap.innerHTML = `<p class="muted">${payload?.error || uiText("no_data")}${dbHints}</p>`;
    summary.textContent = payload?.path || "";
    clearCardPreview(true);
    hideBottomScrollbar();
    hideTablePager();
    return;
  }

  const source = `${payload.source_type || "source"}: ${payload.path || ""}`;
  title.textContent = isDecksContext
    ? `${payload.table || "Deck"}`
    : `${payload.table || "Collection"} (${payload.row_count} lignes)`;
  summary.textContent = isDecksContext ? "" : source;
  wrap.dataset.table = String(payload.source_type || "").toLowerCase();
  UI_STATE.viewMode = String(payload.view_mode || "table").toLowerCase() === "cards"
    ? "cards"
    : "table";
  wrap.classList.toggle("is-card-view", UI_STATE.viewMode === "cards");
  hydrateViewStateForPayload(payload);
  wrap.classList.toggle("is-card-view-deck", isDeckCardsContext());

  const payloadColumns = Array.isArray(payload.columns)
    ? payload.columns.filter((column) => String(column || "").trim().length > 0)
    : [];
  UI_STATE.rows = Array.isArray(payload.rows) ? payload.rows.map(normalizeRowObject) : [];
  UI_STATE.rawColumns = payloadColumns.length > 0 ? payloadColumns : deriveColumnsFromRows(UI_STATE.rows);
  UI_STATE.columns = selectVisibleColumns(UI_STATE.rawColumns);
  if (isDecksContext) {
    hydrateDeckRowsInBackground();
  }

  const payloadPageSize = Number(payload.page_size);
  if (Number.isFinite(payloadPageSize) && payloadPageSize > 0) {
    UI_STATE.tablePageSize = Math.floor(payloadPageSize);
  }
  UI_STATE.pageSize = UI_STATE.viewMode === "cards" ? UI_STATE.cardPageSize : UI_STATE.tablePageSize;
  UI_STATE.currentPage = 1;

  if (UI_STATE.columns.length === 0) {
    wrap.innerHTML = `<p class="muted">${uiText("no_column")}</p>`;
    clearCardPreview(true);
    hideBottomScrollbar();
    hideTablePager();
    return;
  }

  if (UI_STATE.viewMode === "cards") {
    renderCardsPage(UI_STATE.currentPage);
    return;
  }
  renderTablePage(UI_STATE.currentPage);
}

function viewStateKeyFromPayload(payload) {
  const context = String(payload?.ui_context || payload?.source_type || "default")
    .toLowerCase()
    .trim();
  const identity = String(payload?.path || payload?.table || "unknown")
    .toLowerCase()
    .trim();
  return `${context}::${identity}`;
}

function hydrateViewStateForPayload(payload) {
  const key = viewStateKeyFromPayload(payload);
  UI_STATE.activeViewKey = key;

  if (!UI_STATE.viewStateByKey.has(key)) {
    UI_STATE.searchQuery = "";
    UI_STATE.sortKey = CARD_VIEW_SORT_KEYS.NAME_ASC;
    UI_STATE.selectedColors = [];
    UI_STATE.previewDockEnabled = true;
    UI_STATE.editMode = false;
    UI_STATE.viewStateByKey.set(key, {
      searchQuery: UI_STATE.searchQuery,
      sortKey: UI_STATE.sortKey,
      selectedColors: UI_STATE.selectedColors.slice(),
      previewDockEnabled: UI_STATE.previewDockEnabled,
      editMode: UI_STATE.editMode
    });
    return;
  }

  const saved = UI_STATE.viewStateByKey.get(key) || {};
  UI_STATE.searchQuery = String(saved.searchQuery || "");
  UI_STATE.sortKey = String(saved.sortKey || CARD_VIEW_SORT_KEYS.NAME_ASC);
  UI_STATE.selectedColors = Array.isArray(saved.selectedColors)
    ? saved.selectedColors
      .map((value) => String(value || "").trim().toUpperCase())
      .filter((value) => "WUBRGC".includes(value))
    : [];
  UI_STATE.previewDockEnabled = saved.previewDockEnabled !== false;
  UI_STATE.editMode = saved.editMode === true;
}

function persistCurrentViewState() {
  const key = String(UI_STATE.activeViewKey || "").trim();
  if (!key) {
    return;
  }

  UI_STATE.viewStateByKey.set(key, {
    searchQuery: UI_STATE.searchQuery,
    sortKey: UI_STATE.sortKey,
    selectedColors: UI_STATE.selectedColors.slice(),
    previewDockEnabled: UI_STATE.previewDockEnabled,
    editMode: UI_STATE.editMode
  });
}

function isDeckCardsContext() {
  return UI_STATE.viewMode === "cards" && String(UI_STATE.activeViewKey || "").startsWith("decks::");
}

function isStoredCollectionsContext() {
  return UI_STATE.viewMode === "cards" && String(UI_STATE.activeViewKey || "").startsWith("collections::");
}

function isStoredDecksContext() {
  return UI_STATE.viewMode === "cards" && String(UI_STATE.activeViewKey || "").startsWith("decks::");
}

function shouldShowPreviewDock(deckContext) {
  if (isStoredCollectionsContext()) {
    return true;
  }
  if (deckContext) {
    return false;
  }
  return UI_STATE.previewDockEnabled !== false;
}

function isDeckInlinePreviewContext() {
  return isStoredDecksContext();
}

function renderTablePage(pageNumber) {
  const wrap = document.getElementById("table-wrap");
  if (!wrap) {
    return;
  }

  wrap.innerHTML = "";
  releaseTableScrollbarSync();
  clearCardPreview(true);
  setPreviewDockMode(false);

  const totalRows = UI_STATE.rows.length;
  const totalPages = Math.max(1, Math.ceil(totalRows / UI_STATE.pageSize));
  const nextPage = Number.isFinite(pageNumber) ? Math.floor(pageNumber) : 1;
  UI_STATE.currentPage = Math.min(Math.max(nextPage, 1), totalPages);

  const startIndex = (UI_STATE.currentPage - 1) * UI_STATE.pageSize;
  const endIndex = startIndex + UI_STATE.pageSize;
  const pageRows = UI_STATE.rows.slice(startIndex, endIndex);

  const table = document.createElement("table");
  const thead = document.createElement("thead");
  const headRow = document.createElement("tr");

  UI_STATE.columns.forEach((col) => {
    const th = document.createElement("th");
    th.textContent = col;
    th.dataset.col = col;
    th.classList.add(columnClassName(col));
    if (isDescriptionColumn(col)) {
      th.classList.add("col-description");
    }
    if (isManaCostColumn(col)) {
      th.classList.add("col-mana-icons");
    }
    headRow.appendChild(th);
  });
  thead.appendChild(headRow);
  table.appendChild(thead);

  const tbody = document.createElement("tbody");
  pageRows.forEach((rowData) => {
    const tr = document.createElement("tr");
    tr.classList.add("data-row");
    bindRowPreviewEvents(tr, rowData);

    UI_STATE.columns.forEach((col) => {
      const td = document.createElement("td");
      const value = readCellValue(rowData, col);
      const text = formatCellValue(value);
      td.dataset.col = col;
      td.classList.add(columnClassName(col));
      if (isDescriptionColumn(col)) {
        td.classList.add("col-description");
        renderDescriptionIconCell(td, text);
      } else if (isManaCostColumn(col)) {
        td.classList.add("col-mana-icons");
        renderManaCostCell(td, text);
      } else {
        td.textContent = text;
        if (text.length > 70) {
          td.title = text;
        }
      }
      tr.appendChild(td);
    });
    tbody.appendChild(tr);
  });

  table.appendChild(tbody);
  wrap.appendChild(table);
  syncBottomScrollbar(wrap, table);
  renderTablePager(totalRows, startIndex, pageRows.length);
}

function renderCardsPage(pageNumber) {
  const wrap = document.getElementById("table-wrap");
  if (!wrap) {
    return;
  }

  wrap.innerHTML = "";
  releaseTableScrollbarSync();
  clearCardPreview(true);
  hideBottomScrollbar();

  const sourceRows = isDeckCardsContext()
    ? annotateDeckRowsWithZone(UI_STATE.rows)
    : UI_STATE.rows;
  const cardRows = sourceRows.filter(isCardLikeRow);
  const filteredRows = applyCardFiltersAndSorting(cardRows);
  const totalRows = filteredRows.length;
  const deckContext = isDeckCardsContext();
  setPreviewDockMode(shouldShowPreviewDock(deckContext));
  const filteredLiteralCount = deckContext ? sumCardQuantities(filteredRows) : totalRows;
  const totalLiteralCount = deckContext ? sumCardQuantities(cardRows) : cardRows.length;
  let startIndex = 0;
  let pageRows = filteredRows;

  if (!deckContext) {
    const totalPages = Math.max(1, Math.ceil(totalRows / UI_STATE.pageSize));
    const nextPage = Number.isFinite(pageNumber) ? Math.floor(pageNumber) : 1;
    UI_STATE.currentPage = Math.min(Math.max(nextPage, 1), totalPages);
    startIndex = (UI_STATE.currentPage - 1) * UI_STATE.pageSize;
    const endIndex = startIndex + UI_STATE.pageSize;
    pageRows = filteredRows.slice(startIndex, endIndex);
  } else {
    UI_STATE.currentPage = 1;
  }

  const browser = document.createElement("section");
  browser.classList.add("collection-browser");

  const toolbar = renderCardsToolbar(filteredLiteralCount, totalLiteralCount);
  browser.appendChild(toolbar);

  if (pageRows.length === 0) {
    const grid = document.createElement("div");
    grid.classList.add("collection-card-grid");
    grid.innerHTML = `<div class="collection-empty-state muted">${uiText("no_match")}</div>`;
    browser.appendChild(grid);
  } else if (deckContext) {
    const grouped = splitDeckRowsByZone(pageRows);
    if (grouped.main.length > 0) {
      browser.appendChild(createDeckCardSection(uiText("main_deck"), grouped.main, "main"));
    }
    if (grouped.side.length > 0) {
      browser.appendChild(createDeckCardSection(uiText("sideboard"), grouped.side, "side"));
    }
  } else {
    const grid = document.createElement("div");
    grid.classList.add("collection-card-grid");
    pageRows.forEach((rowData) => {
      grid.appendChild(createCollectionCardTile(rowData));
    });
    browser.appendChild(grid);
  }

  wrap.appendChild(browser);
  if (deckContext) {
    hideTablePager();
    return;
  }
  renderTablePager(totalRows, startIndex, pageRows.length);
}

function isCardLikeRow(rowData) {
  const inferred = inferDeckEntryFromRow(rowData);
  const title = formatCellValue(readCellValue(rowData, "name")).trim() || inferred.name;
  const scryfallId = formatCellValue(readFirstCellValue(rowData, ["scryfall_id", "scry_fall_id"])).trim();
  if (scryfallId) {
    return true;
  }
  if (!title) {
    return false;
  }

  const isOnlyDigits = /^[0-9]+$/.test(title);
  if (!isOnlyDigits) {
    return true;
  }

  const hasSupportingData = [
    readCellValue(rowData, "type_line"),
    readCellValue(rowData, "oracle_text"),
    readFirstCellValue(rowData, ["set", "set_code"]),
    readCellValue(rowData, "collector_number"),
    readCellValue(rowData, "mana_cost")
  ]
    .map((value) => formatCellValue(value).trim())
    .some(Boolean);

  return hasSupportingData;
}

function renderCardsToolbar(filteredCount, totalCount) {
  const toolbar = document.createElement("div");
  const isCollectionsContext = isStoredCollectionsContext();
  const utilityButtonLabel = isCollectionsContext
    ? (UI_STATE.editMode ? "Done" : "Edit")
    : "";
  const utilityButtonClass = (
    isCollectionsContext
      ? UI_STATE.editMode
      : false
  )
    ? "collection-action-btn is-active"
    : "collection-action-btn is-muted";
  const utilityButtonHtml = isCollectionsContext
    ? `<button type="button" class="${utilityButtonClass}" data-action="toggle-edit">${utilityButtonLabel}</button>`
    : "";
  toolbar.classList.add("collection-browser-toolbar");
  toolbar.innerHTML = `
    <div class="collection-toolbar-head">
      <div class="collection-toolbar-actions">
        ${utilityButtonHtml}
        <button type="button" class="collection-action-btn is-muted" data-action="focus-search">Share</button>
      </div>
      <p class="collection-toolbar-count">${filteredCount} / ${totalCount} cartes</p>
    </div>
    <div class="collection-toolbar-filters">
      <input id="collection-grid-search" type="search" placeholder="Search / filter cards">
      <select id="collection-grid-sort">
        <option value="${CARD_VIEW_SORT_KEYS.NAME_ASC}">Nom A-Z</option>
        <option value="${CARD_VIEW_SORT_KEYS.QUANTITY_DESC}">Quantite desc</option>
        <option value="${CARD_VIEW_SORT_KEYS.SET_ASC}">Set A-Z</option>
      </select>
    </div>
    <div class="collection-color-filters" aria-label="Color filters">
      ${renderColorFilterButtons()}
    </div>
  `;

  const searchInput = toolbar.querySelector("#collection-grid-search");
  const sortSelect = toolbar.querySelector("#collection-grid-sort");
  const editButton = toolbar.querySelector('button[data-action="toggle-edit"]');
  const shareButton = toolbar.querySelector('button[data-action="focus-search"]');
  const colorButtons = Array.from(toolbar.querySelectorAll(".collection-color-filter"));

  if (searchInput) {
    searchInput.value = UI_STATE.searchQuery;
    searchInput.addEventListener("input", () => {
      UI_STATE.searchQuery = searchInput.value || "";
      persistCurrentViewState();
      renderCardsPage(1);
    });
  }

  if (sortSelect) {
    sortSelect.value = UI_STATE.sortKey;
    sortSelect.addEventListener("change", () => {
      UI_STATE.sortKey = sortSelect.value || CARD_VIEW_SORT_KEYS.NAME_ASC;
      persistCurrentViewState();
      renderCardsPage(1);
    });
  }

  if (editButton) {
    editButton.addEventListener("click", () => {
      UI_STATE.editMode = !UI_STATE.editMode;
      UI_STATE.previewDockEnabled = true;
      persistCurrentViewState();
      setPreviewDockMode(shouldShowPreviewDock(isDeckCardsContext()));
      if (PREVIEW_STATE.activeRow && PREVIEW_STATE.activeElement) {
        showCardPreview(PREVIEW_STATE.activeRow, PREVIEW_STATE.activeElement, true);
      } else if (shouldShowPreviewDock(isDeckCardsContext())) {
        resetCardPreviewPlaceholder();
      }
      renderCardsPage(UI_STATE.currentPage);
    });
  }

  if (shareButton) {
    shareButton.addEventListener("click", async () => {
      const snapshot = buildCardShareText();
      try {
        if (navigator.clipboard?.writeText) {
          await navigator.clipboard.writeText(snapshot);
          shareButton.textContent = "Copied";
          window.setTimeout(() => {
            shareButton.textContent = "Share";
          }, 1200);
          return;
        }
      } catch (_) {}
      searchInput?.focus();
      searchInput?.select();
    });
  }

  colorButtons.forEach((button) => {
    button.addEventListener("click", () => {
      const color = String(button.dataset.color || "").toUpperCase();
      if (!"WUBRGC".includes(color)) {
        return;
      }
      const next = new Set(UI_STATE.selectedColors);
      if (next.has(color)) {
        next.delete(color);
      } else {
        next.add(color);
      }
      UI_STATE.selectedColors = Array.from(next);
      persistCurrentViewState();
      renderCardsPage(1);
    });
  });

  return toolbar;
}

function renderColorFilterButtons() {
  return ["W", "U", "B", "R", "G", "C"].map((color) => {
    const isActive = UI_STATE.selectedColors.includes(color);
    const activeClass = isActive ? " is-active" : "";
    return `
      <button
        type="button"
        class="collection-color-filter${activeClass}"
        data-color="${color}"
        aria-pressed="${isActive ? "true" : "false"}"
        title="${color === "C" ? "Colorless" : color}"
      >
        <img src="https://svgs.scryfall.io/card-symbols/${color}.svg" alt="${color}" loading="lazy">
      </button>
    `;
  }).join("");
}

function createCollectionCardTile(rowData) {
  const tile = document.createElement("article");
  tile.classList.add("collection-card", "data-row");
  bindRowPreviewEvents(tile, rowData);

  const imageFrame = document.createElement("div");
  imageFrame.classList.add("collection-card-art");

  const imageUrl = cardImageUrlFromRow(rowData);
  if (imageUrl) {
    const img = document.createElement("img");
    img.src = imageUrl;
    img.alt = formatMainCardTitle(rowData);
    img.loading = "lazy";
    img.decoding = "async";
    img.addEventListener("error", () => {
      imageFrame.innerHTML = `<span class="collection-card-fallback">${escapeHtml(formatMainCardTitle(rowData))}</span>`;
      tile.classList.add("is-image-missing");
    }, { once: true });
    imageFrame.appendChild(img);
  } else {
    imageFrame.innerHTML = `<span class="collection-card-fallback">${escapeHtml(formatMainCardTitle(rowData))}</span>`;
    tile.classList.add("is-image-missing");
  }

  const quantity = readCardQuantity(rowData);
  const qtyBadge = document.createElement("span");
  qtyBadge.classList.add("collection-card-qty");
  qtyBadge.textContent = `x${quantity}`;
  imageFrame.appendChild(qtyBadge);
  if (UI_STATE.editMode && isStoredCollectionsContext()) {
    imageFrame.appendChild(createCollectionCardEditControls(rowData));
  }
  tile.appendChild(imageFrame);

  const meta = document.createElement("div");
  meta.classList.add("collection-card-meta");
  meta.innerHTML = `
    <p class="collection-card-name">${escapeHtml(formatMainCardTitle(rowData))}</p>
    <p class="collection-card-line">${escapeHtml(formatCardTileSubtitle(rowData))}</p>
  `;
  appendCardTileMana(meta, rowData);
  appendCardTileMarketPrice(meta, rowData, quantity);
  tile.appendChild(meta);

  return tile;
}

function createCollectionCardEditControls(rowData) {
  const controls = document.createElement("div");
  controls.classList.add("collection-card-edit-controls");
  controls.innerHTML = `
    <button type="button" class="collection-card-edit-btn" data-edit-action="decrement" aria-label="Remove one card">-</button>
    <button type="button" class="collection-card-edit-btn" data-edit-action="increment" aria-label="Add one card">+</button>
  `;

  controls.querySelectorAll("button").forEach((button) => {
    button.addEventListener("click", async (event) => {
      event.preventDefault();
      event.stopPropagation();
      const action = String(button.dataset.editAction || "");
      await mutateStoredCollectionRow(rowData, action, controls);
    });
  });

  controls.addEventListener("pointerdown", (event) => {
    event.stopPropagation();
  });

  return controls;
}

async function mutateStoredCollectionRow(rowData, action, controlsNode) {
  const collectionId = String(UI_STATE.currentCollectionId || "").trim();
  if (!collectionId) {
    return;
  }

  const payload = buildStoredCollectionMutationPayload(rowData);
  if (!payload.name) {
    return;
  }

  setCollectionEditControlsBusy(controlsNode, true);
  const request = action === "decrement"
    ? removeCardFromStoredCollection(collectionId, payload)
    : addCardToStoredCollection(collectionId, payload);

  try {
    const out = await request;
    if (!out || out.ok !== true) {
      throw new Error(out?.error || "Collection update failed");
    }
    await reloadCurrentStoredCollection();
  } catch (error) {
    window.alert(error?.message || String(error));
  } finally {
    setCollectionEditControlsBusy(controlsNode, false);
  }
}

function setCollectionEditControlsBusy(controlsNode, busy) {
  if (!controlsNode) {
    return;
  }
  controlsNode.classList.toggle("is-busy", busy === true);
  controlsNode.querySelectorAll("button").forEach((button) => {
    button.disabled = busy === true;
  });
}

function buildStoredCollectionMutationPayload(rowData) {
  return {
    name: formatCellValue(readCellValue(rowData, "name")).trim(),
    quantity: "1",
    set_code: formatCellValue(readFirstCellValue(rowData, ["set_code", "set"])).trim(),
    collector_number: formatCellValue(readCellValue(rowData, "collector_number")).trim(),
    mana_cost: formatCellValue(readCellValue(rowData, "mana_cost")).trim(),
    oracle_text: formatCellValue(readFirstCellValue(rowData, ["oracle_text", "printed_text", "card_text"])).trim(),
    keywords: formatCellValue(readCellValue(rowData, "keywords")).trim(),
    language: formatCellValue(readFirstCellValue(rowData, ["language", "lang"])).trim() || "en",
    finish: formatCellValue(readCellValue(rowData, "finish")).trim(),
    card_condition: formatCellValue(readCellValue(rowData, "card_condition")).trim(),
    scryfall_id: formatCellValue(readFirstCellValue(rowData, ["scryfall_id", "scry_fall_id"])).trim(),
    notes: formatCellValue(readCellValue(rowData, "notes")).trim()
  };
}

async function reloadCurrentStoredCollection() {
  const collectionId = String(UI_STATE.currentCollectionId || "").trim();
  if (!collectionId) {
    return;
  }

  if (typeof UI_HANDLERS.reloadStoredCollection === "function") {
    await UI_HANDLERS.reloadStoredCollection(collectionId);
    return;
  }

  const payload = await getStoredCollection(collectionId);
  if (payload && payload.ok === true) {
    renderCollection(payload);
  }
}

function configureCollectionUiHandlers(handlers = {}) {
  UI_HANDLERS.reloadStoredCollection = typeof handlers.reloadStoredCollection === "function"
    ? handlers.reloadStoredCollection
    : null;
  UI_HANDLERS.setDeckPane = typeof handlers.setDeckPane === "function"
    ? handlers.setDeckPane
    : null;
}

function appendCardTileMarketPrice(metaNode, rowData, quantity) {
  if (!metaNode) {
    return;
  }

  const priceLine = document.createElement("p");
  priceLine.classList.add("collection-card-price", "muted");
  priceLine.textContent = uiText("cm_price_loading");
  metaNode.appendChild(priceLine);

  hydrateCardTileMarketPrice(priceLine, rowData, quantity);
}

function hydrateCardTileMarketPrice(targetNode, rowData, quantity) {
  resolveCardMarketPriceEur(rowData)
    .then((priceValue) => {
      if (!targetNode) {
        return;
      }

      if (!Number.isFinite(priceValue) || priceValue <= 0) {
        targetNode.textContent = uiText("cm_price_na");
        return;
      }

      const formatter = new Intl.NumberFormat(UI_STATE.language === "fr" ? "fr-FR" : "en-US", {
        style: "currency",
        currency: "EUR",
        maximumFractionDigits: 2
      });
      const eachPrice = formatter.format(priceValue);
      const qty = Number.isFinite(Number(quantity)) ? Math.max(1, Number(quantity)) : 1;
      if (qty > 1) {
        const totalPrice = formatter.format(priceValue * qty);
        targetNode.textContent = `${uiText("cm_price_label")} ${eachPrice} | x${qty} = ${totalPrice}`;
      } else {
        targetNode.textContent = `${uiText("cm_price_label")} ${eachPrice}`;
      }
      targetNode.title = "Source: Cardmarket (via Scryfall prices.eur)";
    })
    .catch(() => {
      if (targetNode) {
        targetNode.textContent = uiText("cm_price_na");
      }
    });
}

function resolveCardMarketPriceEur(rowData) {
  const scryfallId = formatCellValue(readFirstCellValue(rowData, ["scryfall_id", "scry_fall_id"])).trim();
  const inferred = inferDeckEntryFromRow(rowData);
  const cardName = formatCellValue(readCellValue(rowData, "name")).trim() || inferred.name;
  const cacheKey = scryfallId ? `id:${scryfallId}` : `name:${cardName.toLowerCase()}`;

  if (!cacheKey || cacheKey === "name:") {
    return Promise.resolve(null);
  }

  const cached = TILE_PRICE_CACHE.get(cacheKey);
  if (cached != null) {
    return Promise.resolve(cached);
  }

  const task = resolveCardMarketPriceFromApi(scryfallId, cardName)
    .then((value) => {
      const normalized = Number.isFinite(value) && value > 0 ? value : null;
      TILE_PRICE_CACHE.set(cacheKey, normalized);
      return normalized;
    })
    .catch(() => {
      TILE_PRICE_CACHE.set(cacheKey, null);
      return null;
    });

  TILE_PRICE_CACHE.set(cacheKey, task);
  return task;
}

async function resolveCardMarketPriceFromApi(scryfallId, cardName) {
  if (scryfallId) {
    const byId = await fetchJson(`https://api.scryfall.com/cards/${encodeURIComponent(scryfallId)}`);
    const byIdPrice = extractCardMarketEur(byId);
    if (byIdPrice != null) {
      return byIdPrice;
    }
  }

  if (cardName) {
    const byName = await fetchCardByName(cardName, "en");
    const byNamePrice = extractCardMarketEur(byName);
    if (byNamePrice != null) {
      return byNamePrice;
    }
  }

  return null;
}

function extractCardMarketEur(card) {
  const prices = card?.prices && typeof card.prices === "object" ? card.prices : null;
  if (!prices) {
    return null;
  }

  const candidates = [prices.eur, prices.eur_foil, prices.eur_etched];
  for (const raw of candidates) {
    const value = Number.parseFloat(String(raw || "").trim());
    if (Number.isFinite(value) && value > 0) {
      return value;
    }
  }
  return null;
}

function renderTablePager(totalRows, startIndex, pageLength) {
  const pager = document.getElementById("table-pager");
  if (!pager) {
    return;
  }

  if (totalRows <= UI_STATE.pageSize) {
    hideTablePager();
    return;
  }

  const totalPages = Math.max(1, Math.ceil(totalRows / UI_STATE.pageSize));
  const start = startIndex + 1;
  const end = startIndex + pageLength;
  const dataLabel = UI_STATE.viewMode === "cards" ? uiText("cards") : uiText("rows");
  const onPageChange = UI_STATE.viewMode === "cards" ? renderCardsPage : renderTablePage;

  pager.classList.add("is-visible");
  pager.innerHTML = `
    <div class="table-pager-info">${dataLabel} ${start}-${end} / ${totalRows} (${uiText("page")} ${UI_STATE.currentPage}/${totalPages})</div>
    <div class="table-pager-actions">
      <button type="button" data-page="prev">Prev</button>
      <button type="button" data-page="next">Next</button>
    </div>
  `;

  const prevButton = pager.querySelector('button[data-page="prev"]');
  const nextButton = pager.querySelector('button[data-page="next"]');
  if (prevButton) {
    prevButton.disabled = UI_STATE.currentPage <= 1;
    prevButton.addEventListener("click", () => {
      onPageChange(UI_STATE.currentPage - 1);
    });
  }
  if (nextButton) {
    nextButton.disabled = UI_STATE.currentPage >= totalPages;
    nextButton.addEventListener("click", () => {
      onPageChange(UI_STATE.currentPage + 1);
    });
  }
}

function hideTablePager() {
  const pager = document.getElementById("table-pager");
  if (!pager) {
    return;
  }
  pager.classList.remove("is-visible");
  pager.innerHTML = "";
}

function isPreviewDockMode() {
  const workspaceLower = document.getElementById("workspace-lower");
  return Boolean(workspaceLower?.classList.contains("has-preview-panel"));
}

function getActivePreviewNodes() {
  if (isDeckInlinePreviewContext()) {
    return {
      panel: document.getElementById("deck-card-preview"),
      title: document.getElementById("deck-card-preview-title"),
      text: document.getElementById("deck-card-preview-text"),
      image: document.getElementById("deck-card-preview-image"),
      meta: document.getElementById("deck-card-preview-meta"),
      inline: true
    };
  }

  return {
    panel: document.getElementById("card-preview"),
    title: document.getElementById("card-preview-title"),
    text: document.getElementById("card-preview-text"),
    image: document.getElementById("card-preview-image"),
    meta: document.getElementById("card-preview-meta"),
    inline: false
  };
}

function setPreviewDockMode(enabled) {
  const workspaceLower = document.getElementById("workspace-lower");
  const panel = document.getElementById("card-preview");
  if (!workspaceLower || !panel) {
    return;
  }

  workspaceLower.classList.toggle("has-preview-panel", enabled === true);
  if (enabled === true) {
    panel.classList.remove("hidden");
    if (!PREVIEW_STATE.activeRow) {
      resetCardPreviewPlaceholder();
    }
    return;
  }

  PREVIEW_STATE.locked = false;
  panel.classList.add("hidden");
}

function resetCardPreviewPlaceholder() {
  const { panel, title, text, image, inline } = getActivePreviewNodes();
  if (title) {
    title.textContent = uiText("card");
  }
  if (text) {
    text.textContent = uiText("preview_hint");
    text.classList.remove("is-hidden");
  }
  if (image) {
    image.removeAttribute("src");
    image.style.display = "none";
    image.alt = uiText("card_preview_alt");
  }
  if (panel && inline) {
    panel.classList.remove("hidden");
  }
  renderPreviewMeta([]);
}

function bindRowPreviewEvents(rowElement, rowData) {
  rowElement.addEventListener("mouseenter", () => {
    if (PREVIEW_STATE.locked && PREVIEW_STATE.activeElement !== rowElement) {
      return;
    }
    showCardPreview(rowData, rowElement, false);
  });

  rowElement.addEventListener("mouseleave", () => {
    if (isPreviewDockMode()) {
      return;
    }
    if (!PREVIEW_STATE.locked) {
      schedulePreviewHide();
    }
  });

  rowElement.addEventListener("click", () => {
    const shouldUnlock = PREVIEW_STATE.locked && PREVIEW_STATE.activeElement === rowElement;
    PREVIEW_STATE.locked = !shouldUnlock;
    if (shouldUnlock) {
      clearCardPreview(true);
      return;
    }
    showCardPreview(rowData, rowElement, true);
  });
}

function showCardPreview(rowData, rowElement, forceLock) {
  cancelPreviewHide();
  if (forceLock) {
    PREVIEW_STATE.locked = true;
  }
  PREVIEW_STATE.activeRow = rowData;
  if (rowElement) {
    markActiveRow(rowElement);
  }

  const { panel, title, text, image, inline } = getActivePreviewNodes();
  if (!panel || !title || !text || !image) {
    return;
  }

  if (inline) {
    activateDeckPreviewPane();
  }
  panel.classList.remove("hidden");
  title.textContent = formatMainCardTitle(rowData);
  text.textContent = formatPrimaryText(rowData);
  text.classList.remove("is-hidden");
  image.removeAttribute("src");
  image.style.display = "block";
  image.alt = `Apercu ${title.textContent}`;
  renderPreviewMetaFromRow(rowData);

  const requestToken = ++PREVIEW_STATE.requestToken;
  const lang = getCollectionLanguage();

  loadCardForLanguage(rowData, lang)
    .then((card) => {
      if (!card || requestToken !== PREVIEW_STATE.requestToken) {
        return;
      }
      applyScryfallCardToPreview(card, rowData);
    })
    .catch(() => {
      if (requestToken !== PREVIEW_STATE.requestToken) {
        return;
      }
      renderPreviewMetaFromRow(rowData);
    });
}

function applyScryfallCardToPreview(card, rowData) {
  const { title, text, image } = getActivePreviewNodes();
  if (!title || !text || !image) {
    return;
  }

  const cardName = card.printed_name || card.name || formatMainCardTitle(rowData);
  title.textContent = cardName;
  text.textContent = cardTextForDisplay(card) || formatPrimaryText(rowData);

  const imageUrl = cardImageUrl(card);
  if (imageUrl) {
    image.src = imageUrl;
    text.textContent = "";
    text.classList.add("is-hidden");
  } else {
    text.classList.remove("is-hidden");
  }
  image.alt = `Apercu ${cardName}`;

  const metaEntries = [
    ["lang", card.lang || getCollectionLanguage()],
    ["rarete", card.rarity || readCellValue(rowData, "rarity")],
    ["set", formatSetLabel(card)],
    ["collector", card.collector_number || readCellValue(rowData, "collector_number")],
    ["prix usd", safePrice(card?.prices?.usd)],
    ["prix eur", safePrice(card?.prices?.eur)],
    ["scryfall_id", card.id || readFirstCellValue(rowData, ["scryfall_id", "scry_fall_id"])]
  ];
  renderPreviewMeta(metaEntries);
}

function clearCardPreview(force) {
  cancelPreviewHide();
  if (!force && PREVIEW_STATE.locked) {
    return;
  }
  PREVIEW_STATE.locked = false;
  PREVIEW_STATE.activeRow = null;
  PREVIEW_STATE.requestToken += 1;
  PREVIEW_STATE.activeElement?.classList.remove("row-active");
  PREVIEW_STATE.activeElement = null;
  const { panel, inline } = getActivePreviewNodes();
  if (panel) {
    if (inline) {
      panel.classList.remove("hidden");
      resetCardPreviewPlaceholder();
    } else if (isPreviewDockMode()) {
      panel.classList.remove("hidden");
      resetCardPreviewPlaceholder();
    } else {
      panel.classList.add("hidden");
    }
  }
}

function schedulePreviewHide() {
  cancelPreviewHide();
  PREVIEW_STATE.hideTimer = window.setTimeout(() => {
    clearCardPreview(false);
  }, 260);
}

function cancelPreviewHide() {
  if (PREVIEW_STATE.hideTimer != null) {
    window.clearTimeout(PREVIEW_STATE.hideTimer);
    PREVIEW_STATE.hideTimer = null;
  }
}

function markActiveRow(rowElement) {
  PREVIEW_STATE.activeElement?.classList.remove("row-active");
  PREVIEW_STATE.activeElement = rowElement || null;
  if (PREVIEW_STATE.activeElement) {
    PREVIEW_STATE.activeElement.classList.add("row-active");
  }
}

function initPreviewEvents() {
  const panel = document.getElementById("card-preview");
  const closeButton = document.getElementById("card-preview-close");
  if (!panel || !closeButton) {
    return;
  }

  closeButton.addEventListener("click", () => {
    clearCardPreview(true);
  });

  panel.addEventListener("mouseenter", () => {
    cancelPreviewHide();
  });

  panel.addEventListener("mouseleave", () => {
    if (isPreviewDockMode()) {
      return;
    }
    if (!PREVIEW_STATE.locked) {
      schedulePreviewHide();
    }
  });

  document.addEventListener("click", (event) => {
    const trigger = event.target.closest("#deck-card-preview-close");
    if (!trigger) {
      return;
    }
    clearCardPreview(true);
  });
}

function selectVisibleColumns(columns) {
  const visibleColumns = columns.filter((column) => !isHiddenColumn(column));

  const availableByLowercase = new Map();
  visibleColumns.forEach((column) => {
    availableByLowercase.set(String(column).toLowerCase(), column);
  });

  const ordered = COMPACT_COLUMN_ORDER
    .map((columnName) => availableByLowercase.get(columnName))
    .filter(Boolean);

  if (ordered.length < Math.min(4, visibleColumns.length)) {
    const used = new Set(ordered.map((column) => String(column).toLowerCase()));
    const extra = visibleColumns.filter((column) => !used.has(String(column).toLowerCase()));
    return reorderColumns([...ordered, ...extra].slice(0, 12));
  }

  return reorderColumns(ordered);
}

function isHiddenColumn(col) {
  return HIDDEN_COLUMN_KEYS.has(String(col || "").toLowerCase());
}

function reorderColumns(columns) {
  const ordered = Array.isArray(columns) ? [...columns] : [];
  const scryfallIdIndex = ordered.findIndex(
    (col) => {
      const normalized = String(col).toLowerCase();
      return normalized === "scryfall_id" || normalized === "scry_fall_id";
    }
  );

  if (scryfallIdIndex < 0) {
    return ordered;
  }

  const [scryfallIdColumn] = ordered.splice(scryfallIdIndex, 1);
  ordered.push(scryfallIdColumn);
  return ordered;
}

function normalizeRowObject(row) {
  if (row && typeof row === "object" && !Array.isArray(row)) {
    return row;
  }
  if (Array.isArray(row) && row.length === 1 && row[0] && typeof row[0] === "object") {
    return row[0];
  }
  if (Array.isArray(row)) {
    if (row.length === 1) {
      return { line: formatCellValue(row[0]) };
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
  return {
    line: String(row)
  };
}

function sumCardQuantities(rows) {
  const source = Array.isArray(rows) ? rows : [];
  return source.reduce((sum, rowData) => sum + readCardQuantity(rowData), 0);
}

function deriveColumnsFromRows(rows) {
  const sourceRows = Array.isArray(rows) ? rows : [];
  const collected = [];
  const seen = new Set();
  sourceRows.forEach((row) => {
    if (!row || typeof row !== "object") {
      return;
    }
    Object.keys(row).forEach((key) => {
      const normalized = String(key || "").trim();
      if (!normalized || seen.has(normalized.toLowerCase())) {
        return;
      }
      seen.add(normalized.toLowerCase());
      collected.push(normalized);
    });
  });
  return collected;
}

function readCellValue(row, col) {
  if (row && Object.prototype.hasOwnProperty.call(row, col)) {
    return row[col];
  }

  const key = String(col || "").toLowerCase();
  if (row && typeof row === "object") {
    const found = Object.keys(row).find((candidate) => candidate.toLowerCase() === key);
    if (found) {
      return row[found];
    }
  }

  return "";
}

function formatCellValue(value) {
  if (value == null) {
    return "";
  }

  if (Array.isArray(value)) {
    if (value.length === 0) {
      return "";
    }
    if (value.length === 1) {
      return formatCellValue(value[0]);
    }
    return value.map(formatCellValue).join(", ");
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

function applyCardFiltersAndSorting(rows) {
  const sourceRows = Array.isArray(rows) ? rows : [];
  const query = String(UI_STATE.searchQuery || "").trim().toLowerCase();
  const selectedColors = Array.isArray(UI_STATE.selectedColors) ? UI_STATE.selectedColors : [];

  let filteredRows = sourceRows;
  if (query) {
    filteredRows = sourceRows.filter((rowData) => {
      const inferred = inferDeckEntryFromRow(rowData);
      const lookup = [
        inferred.name,
        readCellValue(rowData, "name"),
        readCellValue(rowData, "line"),
        readCellValue(rowData, "type_line"),
        readCellValue(rowData, "set"),
        readCellValue(rowData, "set_code"),
        readCellValue(rowData, "oracle_text"),
        readCellValue(rowData, "mana_cost")
      ]
        .map((value) => formatCellValue(value).toLowerCase())
        .join(" ");
      return lookup.includes(query);
    });
  }

  if (selectedColors.length > 0) {
    filteredRows = filteredRows.filter((rowData) => rowMatchesSelectedColors(rowData, selectedColors));
  }

  const sortedRows = [...filteredRows];
  if (UI_STATE.sortKey === CARD_VIEW_SORT_KEYS.QUANTITY_DESC) {
    sortedRows.sort((left, right) => {
      const byQty = readCardQuantity(right) - readCardQuantity(left);
      if (byQty !== 0) {
        return byQty;
      }
      return formatMainCardTitle(left).localeCompare(formatMainCardTitle(right), "fr", { sensitivity: "base" });
    });
    return sortedRows;
  }

  if (UI_STATE.sortKey === CARD_VIEW_SORT_KEYS.SET_ASC) {
    sortedRows.sort((left, right) => {
      const leftSet = formatCellValue(readFirstCellValue(left, ["set_code", "set"]));
      const rightSet = formatCellValue(readFirstCellValue(right, ["set_code", "set"]));
      const bySet = leftSet.localeCompare(rightSet, "fr", { sensitivity: "base" });
      if (bySet !== 0) {
        return bySet;
      }
      return formatMainCardTitle(left).localeCompare(formatMainCardTitle(right), "fr", { sensitivity: "base" });
    });
    return sortedRows;
  }

  sortedRows.sort((left, right) => (
    formatMainCardTitle(left).localeCompare(formatMainCardTitle(right), "fr", { sensitivity: "base" })
  ));
  return sortedRows;
}

function rowMatchesSelectedColors(rowData, selectedColors) {
  const expected = Array.isArray(selectedColors) ? selectedColors : [];
  if (expected.length === 0) {
    return true;
  }

  const rowColors = extractRowColorCodes(rowData);
  return expected.every((color) => {
    if (color === "C") {
      return rowColors.length === 0 || rowColors.includes("C");
    }
    return rowColors.includes(color);
  });
}

function extractRowColorCodes(rowData) {
  const source = [
    formatCellValue(readFirstCellValue(rowData, ["color_identity", "colors"])),
    formatCellValue(readCellValue(rowData, "color")),
    readRowManaCost(rowData)
  ]
    .join(" ")
    .toUpperCase();
  const symbols = Array.from(new Set((source.match(/[WUBRG]/g) || [])));
  if (symbols.length > 0) {
    return symbols;
  }
  if (/\{C\}|\bC\b/.test(source)) {
    return ["C"];
  }
  return [];
}

function buildCardFilterShareText() {
  const parts = [];
  const query = String(UI_STATE.searchQuery || "").trim();
  if (query) {
    parts.push(`search=${query}`);
  }
  if (UI_STATE.sortKey) {
    parts.push(`sort=${UI_STATE.sortKey}`);
  }
  if (Array.isArray(UI_STATE.selectedColors) && UI_STATE.selectedColors.length > 0) {
    parts.push(`colors=${UI_STATE.selectedColors.join("")}`);
  }
  return parts.length > 0 ? parts.join(" | ") : "all cards";
}

function buildCardShareText() {
  if (UI_STATE.viewMode !== "cards") {
    return buildCardFilterShareText();
  }

  const sourceRows = isDeckCardsContext()
    ? annotateDeckRowsWithZone(UI_STATE.rows)
    : UI_STATE.rows;
  const cardRows = sourceRows.filter(isCardLikeRow);
  const filteredRows = applyCardFiltersAndSorting(cardRows);

  if (filteredRows.length === 0) {
    return buildCardFilterShareText();
  }

  if (isDeckCardsContext()) {
    return buildDeckShareText(filteredRows);
  }

  return buildCollectionShareText(filteredRows);
}

function buildDeckShareText(rows) {
  const grouped = splitDeckRowsByZone(rows);
  const blocks = [];

  if (grouped.main.length > 0) {
    blocks.push("Main Deck");
    blocks.push(...grouped.main.map(formatSharedCardLine));
  }

  if (grouped.side.length > 0) {
    if (blocks.length > 0) {
      blocks.push("");
    }
    blocks.push("Sideboard");
    blocks.push(...grouped.side.map(formatSharedCardLine));
  }

  return blocks.join("\n");
}

function buildCollectionShareText(rows) {
  return rows.map(formatSharedCardLine).join("\n");
}

function formatSharedCardLine(rowData) {
  const quantity = readCardQuantity(rowData);
  const name = formatMainCardTitle(rowData);
  const setCode = formatCellValue(readFirstCellValue(rowData, ["set_code", "set"])).trim().toUpperCase();
  if (setCode) {
    return `${quantity} ${name} [${setCode}]`;
  }
  return `${quantity} ${name}`;
}

function readCardQuantity(rowData) {
  const quantityRaw = readFirstCellValue(rowData, ["quantity", "qty", "count", "owned"]);
  const quantity = Number.parseInt(String(quantityRaw || "").trim(), 10);
  if (Number.isFinite(quantity) && quantity > 0) {
    return quantity;
  }
  const inferred = inferDeckEntryFromRow(rowData);
  return inferred.quantity > 0 ? inferred.quantity : 1;
}

function formatCardTileSubtitle(rowData) {
  const setLabel = formatCellValue(readFirstCellValue(rowData, ["set_code", "set"])).toUpperCase();
  const rarity = formatCellValue(readCellValue(rowData, "rarity"));
  const parts = [setLabel, rarity].filter(Boolean);
  return parts.join(" | ");
}

function createCardTileManaIcons(manaCostText) {
  const raw = String(manaCostText || "").trim();
  if (!raw) {
    return null;
  }

  const symbols = extractManaSymbols(raw);
  if (symbols.length === 0) {
    const fallback = document.createElement("p");
    fallback.classList.add("collection-card-mana", "collection-card-mana-fallback");
    fallback.textContent = raw;
    return fallback;
  }

  const wrap = document.createElement("div");
  wrap.classList.add("collection-card-mana", "mana-cost-icons");
  symbols.forEach((symbol) => {
    wrap.appendChild(createManaSymbol(symbol));
  });
  wrap.title = raw;
  return wrap;
}

function appendCardTileMana(metaNode, rowData) {
  if (!metaNode) {
    return;
  }

  const rowMana = readRowManaCost(rowData);
  const immediate = createCardTileManaIcons(rowMana);
  if (immediate) {
    metaNode.appendChild(immediate);
    return;
  }

  const fallback = createCardTileColorIdentityIcons(rowData);
  if (fallback) {
    metaNode.appendChild(fallback);
  }

  hydrateCardTileManaFromScryfall(metaNode, rowData);
}

function readRowManaCost(rowData) {
  return formatCellValue(readFirstCellValue(rowData, ["mana_cost", "manacost", "cost"])).trim();
}

function createCardTileColorIdentityIcons(rowData) {
  const source = [
    formatCellValue(readFirstCellValue(rowData, ["color_identity", "colors"])),
    formatCellValue(readCellValue(rowData, "color"))
  ]
    .join(" ")
    .toUpperCase();
  const symbols = Array.from(new Set((source.match(/[WUBRG]/g) || [])));
  if (symbols.length === 0) {
    return null;
  }

  const wrap = document.createElement("div");
  wrap.classList.add("collection-card-mana", "mana-cost-icons");
  wrap.dataset.manaFallback = "color_identity";
  symbols.forEach((symbol) => {
    wrap.appendChild(createManaSymbol(symbol));
  });
  wrap.title = "Color identity";
  return wrap;
}

function hydrateCardTileManaFromScryfall(metaNode, rowData) {
  resolveCardManaCost(rowData)
    .then((manaCost) => {
      const normalized = String(manaCost || "").trim();
      if (!normalized) {
        return;
      }

      const manaIcons = createCardTileManaIcons(normalized);
      if (!manaIcons) {
        return;
      }

      const existing = metaNode.querySelector(".collection-card-mana");
      if (existing && existing.dataset.manaFallback !== "color_identity") {
        return;
      }
      if (existing) {
        existing.replaceWith(manaIcons);
      } else {
        metaNode.appendChild(manaIcons);
      }
    })
    .catch(() => {});
}

function resolveCardManaCost(rowData) {
  const scryfallId = formatCellValue(readFirstCellValue(rowData, ["scryfall_id", "scry_fall_id"])).trim();
  const inferred = inferDeckEntryFromRow(rowData);
  const cardName = formatCellValue(readCellValue(rowData, "name")).trim() || inferred.name;
  const cacheKey = scryfallId ? `id:${scryfallId}` : `name:${cardName.toLowerCase()}`;

  if (!cacheKey || cacheKey === "name:") {
    return Promise.resolve("");
  }

  const cached = TILE_MANA_CACHE.get(cacheKey);
  if (cached != null) {
    return Promise.resolve(cached);
  }

  const task = resolveCardManaCostFromApi(scryfallId, cardName)
    .then((manaCost) => {
      const normalized = String(manaCost || "").trim();
      TILE_MANA_CACHE.set(cacheKey, normalized);
      return normalized;
    })
    .catch(() => {
      TILE_MANA_CACHE.set(cacheKey, "");
      return "";
    });

  TILE_MANA_CACHE.set(cacheKey, task);
  return task;
}

async function resolveCardManaCostFromApi(scryfallId, cardName) {
  if (scryfallId) {
    const byId = await fetchJson(`https://api.scryfall.com/cards/${encodeURIComponent(scryfallId)}`);
    const manaCost = String(byId?.mana_cost || "").trim();
    if (manaCost) {
      return manaCost;
    }
  }

  if (cardName) {
    const byName = await fetchCardByName(cardName, "en");
    const manaCost = String(byName?.mana_cost || "").trim();
    if (manaCost) {
      return manaCost;
    }
  }

  return "";
}

function cardImageUrlFromRow(rowData) {
  const scryfallId = formatCellValue(readFirstCellValue(rowData, ["scryfall_id", "scry_fall_id"])).trim();
  const scryfallImageUrl = scryfallCdnImageUrl(scryfallId, "art_crop");
  if (scryfallImageUrl) {
    return scryfallImageUrl;
  }

  const inferred = inferDeckEntryFromRow(rowData);
  const cardName = formatCellValue(readCellValue(rowData, "name")).trim() || inferred.name;
  if (!cardName) {
    return "";
  }

  const params = new URLSearchParams({
    exact: cardName,
    format: "image",
    version: "art_crop"
  });

  const setCode = formatCellValue(readCellValue(rowData, "set_code")).trim();
  if (/^[a-z0-9]{2,6}$/i.test(setCode)) {
    params.set("set", setCode.toLowerCase());
  }

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

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function isDescriptionColumn(col) {
  return DESCRIPTION_COLUMN_KEYS.has(String(col || "").toLowerCase());
}

function isManaCostColumn(col) {
  return MANA_COST_COLUMN_KEYS.has(String(col || "").toLowerCase());
}

function renderDescriptionIconCell(cell, text) {
  const fullText = String(text || "").trim();
  if (!fullText) {
    cell.textContent = "";
    return;
  }

  const icon = document.createElement("span");
  icon.classList.add("description-icon");
  icon.textContent = "i";
  icon.setAttribute("aria-label", "Description");
  cell.appendChild(icon);
  cell.title = fullText;
}

function renderManaCostCell(cell, text) {
  const rawText = String(text || "").trim();
  if (!rawText) {
    cell.textContent = "";
    return;
  }

  const symbols = extractManaSymbols(rawText);
  if (symbols.length === 0) {
    cell.textContent = rawText;
    return;
  }

  const wrap = document.createElement("span");
  wrap.classList.add("mana-cost-icons");
  symbols.forEach((symbol) => {
    const icon = createManaSymbol(symbol);
    wrap.appendChild(icon);
  });

  cell.appendChild(wrap);
  cell.title = rawText;
}

function extractManaSymbols(text) {
  const raw = String(text || "").trim();
  if (!raw) {
    return [];
  }

  const matches = raw.match(/\{([^}]+)\}/g);
  if (matches && matches.length > 0) {
    return matches
      .map((chunk) => chunk.slice(1, -1).trim())
      .filter(Boolean);
  }

  return extractCompactManaSymbols(raw);
}

function extractCompactManaSymbols(text) {
  const source = String(text || "")
    .toUpperCase()
    .replace(/\s+/g, "")
    .replace(/[()]/g, "");
  if (!source) {
    return [];
  }
  if (!/^[A-Z0-9/]+$/.test(source)) {
    return [];
  }

  const tokens = [];
  let index = 0;
  while (index < source.length) {
    const current = source[index];

    if (/[0-9]/.test(current)) {
      let end = index + 1;
      while (end < source.length && /[0-9]/.test(source[end])) {
        end += 1;
      }
      const numberToken = source.slice(index, end);
      if (end + 1 < source.length && source[end] === "/" && /[A-Z0-9]/.test(source[end + 1])) {
        tokens.push(`${numberToken}/${source[end + 1]}`);
        index = end + 2;
        continue;
      }
      tokens.push(numberToken);
      index = end;
      continue;
    }

    if (!/[A-Z]/.test(current)) {
      return [];
    }
    if (index + 2 < source.length && source[index + 1] === "/" && /[A-Z0-9]/.test(source[index + 2])) {
      tokens.push(`${current}/${source[index + 2]}`);
      index += 3;
      continue;
    }

    tokens.push(current);
    index += 1;
  }

  return tokens;
}

function createManaSymbol(symbol) {
  const normalized = String(symbol || "").trim().toUpperCase();
  const iconWrap = document.createElement("span");
  iconWrap.classList.add("mana-symbol");
  iconWrap.setAttribute("aria-label", `Mana ${normalized}`);

  const iconUrl = manaSymbolIconUrl(normalized);
  if (!iconUrl) {
    iconWrap.classList.add("mana-symbol-fallback");
    iconWrap.textContent = normalized;
    return iconWrap;
  }

  const img = document.createElement("img");
  img.classList.add("mana-symbol-icon");
  img.src = iconUrl;
  img.alt = normalized;
  img.loading = "lazy";
  img.decoding = "async";
  img.addEventListener("error", () => {
    iconWrap.classList.add("mana-symbol-fallback");
    iconWrap.textContent = normalized;
  }, { once: true });

  iconWrap.appendChild(img);
  return iconWrap;
}

function manaSymbolIconUrl(symbol) {
  if (!symbol) {
    return "";
  }

  let code = String(symbol).toUpperCase().trim();
  code = code.replace(/\s+/g, "");
  code = code.replace(/\//g, "");
  code = code.replace(/∞/g, "INFINITY");
  code = code.replace(/½/g, "HALF");

  if (!/^[A-Z0-9]+$/.test(code)) {
    return "";
  }

  return `https://svgs.scryfall.io/card-symbols/${code}.svg`;
}

function columnClassName(col) {
  return `col-${String(col || "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")}`;
}

function formatMainCardTitle(rowData) {
  const inferred = inferDeckEntryFromRow(rowData);
  const fallback = readFirstCellValue(rowData, ["scryfall_id", "scry_fall_id"]);
  return formatCellValue(readCellValue(rowData, "name")) || inferred.name || formatCellValue(fallback) || "Carte";
}

function inferDeckEntryFromRow(rowData) {
  const explicitName = formatCellValue(
    readFirstCellValue(rowData, ["name", "card_name", "card", "cardname", "printed_name", "card_title"])
  ).trim();
  const explicitQty = Number.parseInt(
    String(readFirstCellValue(rowData, ["quantity", "qty", "count", "owned", "qte", "amount"]) || "").trim(),
    10
  );
  if (explicitName) {
    return {
      name: explicitName,
      quantity: Number.isFinite(explicitQty) && explicitQty > 0 ? explicitQty : 1
    };
  }

  const rawLine = formatCellValue(
    readFirstCellValue(rowData, ["line", "card_line", "raw", "entry", "deck_line", "deck_entry"])
  ).trim();
  if (!rawLine) {
    return { name: "", quantity: 0 };
  }

  const stripped = rawLine.replace(/^SB:\s*/i, "").trim();
  if (!stripped || /^(#|\/\/)/.test(stripped)) {
    return { name: "", quantity: 0 };
  }
  if (/^(sideboard|commander|maybeboard|companion|deck|mainboard)\b/i.test(stripped)) {
    return { name: "", quantity: 0 };
  }

  let quantity = 1;
  let name = stripped;
  const withQty = stripped.match(/^([0-9]+)\s*x?\s+(.+)$/i);
  if (withQty) {
    quantity = Number.parseInt(withQty[1], 10);
    name = withQty[2].trim();
  }

  name = name
    .replace(/\s+\([^)]+\)\s+[A-Za-z0-9-]+(?:\s*\*?[A-Za-z0-9]+)?\s*$/u, "")
    .replace(/\s+\[[^\]]+\]\s*$/u, "")
    .replace(/\s+\*\w+\s*$/u, "")
    .trim();

  if (!name) {
    return { name: "", quantity: 0 };
  }

  return {
    name,
    quantity: Number.isFinite(quantity) && quantity > 0 ? quantity : 1
  };
}

function hydrateDeckRowsInBackground() {
  if (!isStoredDecksContext() || !Array.isArray(UI_STATE.rows) || UI_STATE.rows.length === 0) {
    return;
  }

  const token = ++DECK_ROW_HYDRATION_TOKEN;
  const activeViewKey = UI_STATE.activeViewKey;
  const tasks = UI_STATE.rows.map((rowData, index) => hydrateSingleDeckRow(rowData, index));

  Promise.all(tasks)
    .then((updatedRows) => {
      if (token !== DECK_ROW_HYDRATION_TOKEN || activeViewKey !== UI_STATE.activeViewKey) {
        return;
      }

      const nextRows = updatedRows.map((rowData, index) => rowData || UI_STATE.rows[index]);
      const changed = nextRows.some((rowData, index) => rowData !== UI_STATE.rows[index]);
      if (!changed) {
        return;
      }

      UI_STATE.rows = nextRows;
      UI_STATE.rawColumns = deriveColumnsFromRows(UI_STATE.rows);
      UI_STATE.columns = selectVisibleColumns(UI_STATE.rawColumns);
      renderCardsPage(UI_STATE.currentPage);
    })
    .catch(() => {});
}

function hydrateSingleDeckRow(rowData, index) {
  if (!rowData || typeof rowData !== "object") {
    return Promise.resolve(rowData);
  }

  const inferred = inferDeckEntryFromRow(rowData);
  const cardName = formatCellValue(readCellValue(rowData, "name")).trim() || inferred.name;
  if (!cardName || !deckRowNeedsMetadata(rowData)) {
    return Promise.resolve(rowData);
  }

  const cacheKey = cardName.toLowerCase();
  if (DECK_ROW_METADATA_CACHE.has(cacheKey)) {
    return Promise.resolve(applyDeckRowMetadata(rowData, DECK_ROW_METADATA_CACHE.get(cacheKey)));
  }

  if (DECK_ROW_HYDRATION_TASKS.has(cacheKey)) {
    return DECK_ROW_HYDRATION_TASKS.get(cacheKey).then((metadata) => applyDeckRowMetadata(rowData, metadata));
  }

  const task = fetchDeckRowMetadata(cardName)
    .then((metadata) => {
      DECK_ROW_METADATA_CACHE.set(cacheKey, metadata);
      DECK_ROW_HYDRATION_TASKS.delete(cacheKey);
      return metadata;
    })
    .catch(() => {
      DECK_ROW_HYDRATION_TASKS.delete(cacheKey);
      return null;
    });

  DECK_ROW_HYDRATION_TASKS.set(cacheKey, task);
  return task.then((metadata) => applyDeckRowMetadata(rowData, metadata));
}

function deckRowNeedsMetadata(rowData) {
  return !formatCellValue(readFirstCellValue(rowData, ["scryfall_id", "scry_fall_id"])).trim()
    || !formatCellValue(readFirstCellValue(rowData, ["color_identity", "colors"])).trim()
    || !readRowManaCost(rowData)
    || !formatCellValue(readFirstCellValue(rowData, ["set_code", "set"])).trim();
}

function applyDeckRowMetadata(rowData, metadata) {
  if (!metadata || typeof metadata !== "object") {
    return rowData;
  }

  const nextRow = { ...rowData };
  let changed = false;
  const assignIfMissing = (keys, value) => {
    const normalized = String(value || "").trim();
    if (!normalized) {
      return;
    }
    const hasValue = keys.some((key) => formatCellValue(readCellValue(nextRow, key)).trim());
    if (hasValue) {
      return;
    }
    nextRow[keys[0]] = normalized;
    changed = true;
  };

  assignIfMissing(["scryfall_id"], metadata.scryfall_id);
  assignIfMissing(["mana_cost"], metadata.mana_cost);
  assignIfMissing(["color_identity"], metadata.color_identity);
  assignIfMissing(["colors"], metadata.colors);
  assignIfMissing(["oracle_text"], metadata.oracle_text);
  assignIfMissing(["set_code"], metadata.set_code);
  assignIfMissing(["collector_number"], metadata.collector_number);
  assignIfMissing(["rarity"], metadata.rarity);
  return changed ? nextRow : rowData;
}

async function fetchDeckRowMetadata(cardName) {
  const card = await fetchCardByName(cardName, "en");
  if (!card || card.object !== "card") {
    return null;
  }

  const colorIdentity = Array.isArray(card.color_identity)
    ? card.color_identity.join("")
    : String(card.color_identity || "").trim();
  const colors = Array.isArray(card.colors)
    ? card.colors.join("")
    : String(card.colors || "").trim();

  return {
    scryfall_id: String(card.id || "").trim(),
    mana_cost: String(card.mana_cost || "").trim(),
    color_identity: colorIdentity,
    colors,
    oracle_text: cardTextForDisplay(card),
    set_code: String(card.set || "").trim().toUpperCase(),
    collector_number: String(card.collector_number || "").trim(),
    rarity: String(card.rarity || "").trim()
  };
}

function annotateDeckRowsWithZone(rows) {
  const source = Array.isArray(rows) ? rows : [];
  const annotated = [];
  let currentZone = "main";

  source.forEach((rowData) => {
    const row = rowData && typeof rowData === "object" ? { ...rowData } : normalizeRowObject(rowData);
    const zoneMarker = detectDeckZoneMarker(row);
    if (zoneMarker) {
      currentZone = zoneMarker;
      row.__deck_zone = currentZone;
      row.__deck_zone_marker = true;
      annotated.push(row);
      return;
    }

    const explicitZone = explicitDeckZoneFromRow(row);
    row.__deck_zone = explicitZone || currentZone;
    annotated.push(row);
  });

  return annotated;
}

function detectDeckZoneMarker(rowData) {
  const line = formatCellValue(readFirstCellValue(rowData, ["line", "card_line", "raw", "entry", "name"])).trim();
  if (!line) {
    return "";
  }
  const normalized = line.toLowerCase().replace(/\s+/g, " ").trim();
  if (/^(sideboard|sb|side)\b:?$/i.test(normalized)) {
    return "side";
  }
  if (/^(mainboard|main deck|deck|maindeck)\b:?$/i.test(normalized)) {
    return "main";
  }
  return "";
}

function explicitDeckZoneFromRow(rowData) {
  const candidates = [
    readFirstCellValue(rowData, ["deck_zone", "zone", "section", "board", "group"]),
    readFirstCellValue(rowData, ["is_sideboard", "sideboard"])
  ];
  const direct = formatCellValue(candidates[0]).toLowerCase().trim();
  if (direct) {
    if (/side|sb/.test(direct)) {
      return "side";
    }
    if (/main|deck/.test(direct)) {
      return "main";
    }
  }

  const sideFlag = formatCellValue(candidates[1]).toLowerCase().trim();
  if (["1", "true", "yes", "y"].includes(sideFlag)) {
    return "side";
  }
  if (["0", "false", "no", "n"].includes(sideFlag)) {
    return "main";
  }

  const rawLine = formatCellValue(readFirstCellValue(rowData, ["line", "card_line", "raw", "entry"])).trim();
  if (/^sb:\s*/i.test(rawLine)) {
    return "side";
  }
  return "";
}

function splitDeckRowsByZone(rows) {
  const source = Array.isArray(rows) ? rows : [];
  const grouped = { main: [], side: [] };
  source.forEach((rowData) => {
    if (!isCardLikeRow(rowData)) {
      return;
    }
    const zone = readDeckZone(rowData);
    if (zone === "side") {
      grouped.side.push(rowData);
    } else {
      grouped.main.push(rowData);
    }
  });
  return grouped;
}

function readDeckZone(rowData) {
  const zone = String(rowData?.__deck_zone || "").toLowerCase().trim();
  if (zone === "side") {
    return "side";
  }
  return "main";
}

function createDeckCardSection(title, rows, zone) {
  const section = document.createElement("section");
  section.classList.add("deck-card-section", zone === "side" ? "is-side" : "is-main");

  const titleRow = document.createElement("div");
  titleRow.classList.add("deck-card-section-head");
  const literalCount = sumCardQuantities(rows);
  titleRow.innerHTML = `
    <h3>${escapeHtml(title)}</h3>
    <span>${literalCount} cartes</span>
  `;
  section.appendChild(titleRow);

  const grid = document.createElement("div");
  grid.classList.add("collection-card-grid", "deck-card-grid");
  rows.forEach((rowData) => {
    const tile = createCollectionCardTile(rowData);
    if (zone === "side") {
      tile.classList.add("is-side");
    } else {
      tile.classList.add("is-main");
    }
    grid.appendChild(tile);
  });
  section.appendChild(grid);
  return section;
}

function formatPrimaryText(rowData) {
  return formatCellValue(readCellValue(rowData, "oracle_text")) || uiText("no_oracle");
}

function renderPreviewMetaFromRow(rowData) {
  const entries = [
    [
      "lang",
      formatCellValue(readFirstCellValue(rowData, ["language", "lang"])) || getCollectionLanguage()
    ],
    ["rarete", formatCellValue(readCellValue(rowData, "rarity"))],
    ["set", formatCellValue(readFirstCellValue(rowData, ["set", "set_code"]))],
    ["collector", formatCellValue(readCellValue(rowData, "collector_number"))],
    ["scryfall_id", formatCellValue(readFirstCellValue(rowData, ["scryfall_id", "scry_fall_id"]))]
  ];
  renderPreviewMeta(entries);
}

function renderPreviewMeta(entries) {
  const { meta: container } = getActivePreviewNodes();
  if (!container) {
    return;
  }
  container.innerHTML = "";
  entries.forEach(([label, value]) => {
    if (!value) {
      return;
    }
    const dt = document.createElement("dt");
    dt.textContent = label;
    const dd = document.createElement("dd");
    dd.textContent = value;
    container.appendChild(dt);
    container.appendChild(dd);
  });
}

function activateDeckPreviewPane() {
  if (!isDeckInlinePreviewContext()) {
    return;
  }
  if (typeof UI_HANDLERS.setDeckPane === "function") {
    UI_HANDLERS.setDeckPane("preview");
  }
}

async function loadCardForLanguage(rowData, language) {
  const scryfallId = formatCellValue(readFirstCellValue(rowData, ["scryfall_id", "scry_fall_id"]));
  const cardName = formatCellValue(readCellValue(rowData, "name"));
  const cacheKey = `${scryfallId || cardName}::${language}`;

  if (PREVIEW_STATE.cache.has(cacheKey)) {
    return PREVIEW_STATE.cache.get(cacheKey);
  }

  const task = resolveCardForLanguage(scryfallId, cardName, rowData, language)
    .catch(() => null);
  PREVIEW_STATE.cache.set(cacheKey, task);
  return task;
}

async function resolveCardForLanguage(scryfallId, cardName, rowData, language) {
  let baseCard = null;
  if (scryfallId) {
    baseCard = await fetchJson(`https://api.scryfall.com/cards/${encodeURIComponent(scryfallId)}`);
  }

  if (!baseCard && cardName) {
    baseCard = await fetchCardByName(cardName, "en");
  }

  if (!baseCard || baseCard.object !== "card") {
    return null;
  }

  if (!language || baseCard.lang === language) {
    return baseCard;
  }

  const preferredSet = String(readFirstCellValue(rowData, ["set", "set_code"]) || "").toLowerCase();
  const preferredCollector = String(readCellValue(rowData, "collector_number") || "").toLowerCase();

  if (baseCard.oracle_id) {
    const query = encodeURIComponent(`oracleid:${baseCard.oracle_id} lang:${language}`);
    const searchResult = await fetchJson(`https://api.scryfall.com/cards/search?q=${query}&order=released&dir=desc`);
    const localizedCards = Array.isArray(searchResult?.data) ? searchResult.data : [];
    if (localizedCards.length > 0) {
      const exactPrint = localizedCards.find((candidate) => {
        const sameSet = preferredSet && String(candidate.set || "").toLowerCase() === preferredSet;
        const sameCollector = preferredCollector
          && String(candidate.collector_number || "").toLowerCase() === preferredCollector;
        return sameSet && (!preferredCollector || sameCollector);
      });
      return exactPrint || localizedCards[0];
    }
  }

  const namedCard = await fetchCardByName(cardName, language);
  return namedCard || baseCard;
}

async function fetchCardByName(cardName, language) {
  if (!cardName) {
    return null;
  }
  const params = new URLSearchParams({ exact: cardName });
  if (language) {
    params.set("lang", language);
  }
  const response = await fetchJson(`https://api.scryfall.com/cards/named?${params.toString()}`);
  if (!response || response.object !== "card") {
    return null;
  }
  return response;
}

async function fetchJson(url) {
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

function cardImageUrl(card) {
  if (card?.image_uris?.normal) {
    return card.image_uris.normal;
  }
  if (Array.isArray(card?.card_faces)) {
    const faceWithImage = card.card_faces.find((face) => face?.image_uris?.normal);
    if (faceWithImage) {
      return faceWithImage.image_uris.normal;
    }
  }
  return "";
}

function cardTextForDisplay(card) {
  if (card.printed_text) {
    return card.printed_text;
  }
  if (card.oracle_text) {
    return card.oracle_text;
  }
  if (Array.isArray(card.card_faces)) {
    return card.card_faces
      .map((face) => face.printed_text || face.oracle_text || "")
      .filter(Boolean)
      .join(" // ");
  }
  return "";
}

function formatSetLabel(card) {
  if (card?.set_name && card?.set) {
    return `${card.set_name} (${String(card.set).toUpperCase()})`;
  }
  return card?.set_name || card?.set || "";
}

function safePrice(value) {
  return value == null || value === "" ? "" : value;
}

function readFirstCellValue(row, columnNames) {
  for (const columnName of columnNames) {
    const value = readCellValue(row, columnName);
    if (value != null && String(value) !== "") {
      return value;
    }
  }
  return "";
}

function syncBottomScrollbar(tableWrap, tableElement) {
  releaseTableScrollbarSync();
  const scrollbar = document.getElementById("table-scrollbar");
  const scrollbarInner = document.getElementById("table-scrollbar-inner");
  if (!scrollbar || !scrollbarInner) {
    return;
  }

  let isSyncing = false;
  const syncFromTable = () => {
    if (isSyncing) {
      return;
    }
    isSyncing = true;
    scrollbar.scrollLeft = tableWrap.scrollLeft;
    isSyncing = false;
  };
  const syncFromBottom = () => {
    if (isSyncing) {
      return;
    }
    isSyncing = true;
    tableWrap.scrollLeft = scrollbar.scrollLeft;
    isSyncing = false;
  };
  const refresh = () => {
    const targetWidth = Math.ceil(tableElement.scrollWidth);
    scrollbarInner.style.width = `${targetWidth}px`;
    const shouldShow = targetWidth > tableWrap.clientWidth + 2;
    scrollbar.style.display = shouldShow ? "block" : "none";
    scrollbar.scrollLeft = tableWrap.scrollLeft;
  };

  tableWrap.addEventListener("scroll", syncFromTable);
  scrollbar.addEventListener("scroll", syncFromBottom);
  window.addEventListener("resize", refresh);

  let observer = null;
  if (typeof ResizeObserver !== "undefined") {
    observer = new ResizeObserver(refresh);
    observer.observe(tableWrap);
    observer.observe(tableElement);
  }

  refresh();

  releaseScrollbarSync = () => {
    tableWrap.removeEventListener("scroll", syncFromTable);
    scrollbar.removeEventListener("scroll", syncFromBottom);
    window.removeEventListener("resize", refresh);
    observer?.disconnect();
    releaseScrollbarSync = null;
  };
}

function releaseTableScrollbarSync() {
  if (typeof releaseScrollbarSync === "function") {
    releaseScrollbarSync();
  }
}

function hideBottomScrollbar() {
  const scrollbar = document.getElementById("table-scrollbar");
  if (scrollbar) {
    scrollbar.style.display = "none";
  }
}

function getCollectionLanguage() {
  return UI_STATE.language;
}

function setCollectionLanguage(language) {
  if (language !== "fr" && language !== "en") {
    return;
  }
  UI_STATE.language = language;
  window.localStorage.setItem("mana_engine_ui_lang", language);

  if (PREVIEW_STATE.activeRow) {
    const activeRow = PREVIEW_STATE.activeRow;
    const activeElement = PREVIEW_STATE.activeElement;
    showCardPreview(activeRow, activeElement, PREVIEW_STATE.locked);
  }
}

function loadSavedLanguage() {
  const saved = window.localStorage.getItem("mana_engine_ui_lang")
    || window.localStorage.getItem("mtgcodex_ui_lang");
  return saved === "fr" ? "fr" : "en";
}

window.renderCollection = renderCollection;
window.getCollectionLanguage = getCollectionLanguage;
window.setCollectionLanguage = setCollectionLanguage;
window.bindRowPreviewEvents = bindRowPreviewEvents;
window.renderManaCostCell = renderManaCostCell;
window.configureCollectionUiHandlers = configureCollectionUiHandlers;

export {
  renderCollection,
  getCollectionLanguage,
  setCollectionLanguage,
  bindRowPreviewEvents,
  renderManaCostCell,
  configureCollectionUiHandlers
};
