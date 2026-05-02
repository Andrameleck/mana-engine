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

const CARD_COLOR_FILTER_CODES = ["W", "U", "B", "R", "G", "C"];
const CARD_COLOR_FILTER_LABELS = {
  W: "Blanc",
  U: "Bleu",
  B: "Noir",
  R: "Rouge",
  G: "Vert",
  C: "Incolore"
};

const CARD_VIEW_DEFAULT_PAGE_SIZE = 48;
const ENABLE_TILE_MANA_API_HYDRATION = false;

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
  colorFilter: createEmptyColorFilter(),
  activeViewKey: "",
  viewStateByKey: new Map()
};

const PREVIEW_STATE = {
  locked: false,
  activeRow: null,
  activeElement: null,
  hideTimer: null,
  requestToken: 0,
  cache: new Map()
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
    cm_price_label: "Cardmarket:"
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
    cm_price_label: "Cardmarket:"
  }
};

function uiText(key) {
  const lang = UI_STATE.language === "fr" ? "fr" : "en";
  return UI_I18N[lang]?.[key] || UI_I18N.fr?.[key] || key;
}

let releaseScrollbarSync = null;
const TILE_MANA_CACHE = new Map();
const TILE_PRICE_CACHE = new Map();

initPreviewEvents();

function renderCollection(payload) {
  const title = document.getElementById("table-title");
  const wrap = document.getElementById("table-wrap");
  const summary = document.getElementById("load-summary");

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
  title.textContent = `${payload.table || "Collection"} (${payload.row_count} lignes)`;
  summary.textContent = source;
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

function createEmptyColorFilter() {
  const filter = {};
  CARD_COLOR_FILTER_CODES.forEach((code) => {
    filter[code] = false;
  });
  return filter;
}

function normalizeColorFilterState(raw) {
  const filter = createEmptyColorFilter();
  if (Array.isArray(raw)) {
    raw.forEach((entry) => {
      const code = String(entry || "").trim().toUpperCase();
      if (CARD_COLOR_FILTER_CODES.includes(code)) {
        filter[code] = true;
      }
    });
    return filter;
  }
  if (raw && typeof raw === "object") {
    CARD_COLOR_FILTER_CODES.forEach((code) => {
      filter[code] = raw[code] === true;
    });
  }
  return filter;
}

function getActiveColorFilterCodes(filterMap = UI_STATE.colorFilter) {
  const source = filterMap && typeof filterMap === "object"
    ? filterMap
    : createEmptyColorFilter();
  return CARD_COLOR_FILTER_CODES.filter((code) => source[code] === true);
}

function hydrateViewStateForPayload(payload) {
  const key = viewStateKeyFromPayload(payload);
  UI_STATE.activeViewKey = key;

  if (!UI_STATE.viewStateByKey.has(key)) {
    UI_STATE.searchQuery = "";
    UI_STATE.sortKey = CARD_VIEW_SORT_KEYS.NAME_ASC;
    UI_STATE.colorFilter = createEmptyColorFilter();
    UI_STATE.viewStateByKey.set(key, {
      searchQuery: UI_STATE.searchQuery,
      sortKey: UI_STATE.sortKey,
      colorFilter: []
    });
    return;
  }

  const saved = UI_STATE.viewStateByKey.get(key) || {};
  UI_STATE.searchQuery = String(saved.searchQuery || "");
  UI_STATE.sortKey = String(saved.sortKey || CARD_VIEW_SORT_KEYS.NAME_ASC);
  UI_STATE.colorFilter = normalizeColorFilterState(
    saved.colorFilter ?? saved.colorFilters ?? saved.selectedColors
  );
}

function persistCurrentViewState() {
  const key = String(UI_STATE.activeViewKey || "").trim();
  if (!key) {
    return;
  }

  UI_STATE.viewStateByKey.set(key, {
    searchQuery: UI_STATE.searchQuery,
    sortKey: UI_STATE.sortKey,
    colorFilter: getActiveColorFilterCodes(UI_STATE.colorFilter)
  });
}

function isDeckCardsContext() {
  return UI_STATE.viewMode === "cards" && String(UI_STATE.activeViewKey || "").startsWith("decks::");
}

function renderTablePage(pageNumber) {
  const wrap = document.getElementById("table-wrap");
  if (!wrap) {
    return;
  }

  setPreviewDockMode(false);
  wrap.innerHTML = "";
  releaseTableScrollbarSync();
  clearCardPreview(true);

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
  setPreviewDockMode(!deckContext);
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

  const toolbar = renderCardsToolbar(filteredLiteralCount, totalLiteralCount, {
    deckContext
  });
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
    if (viewKeyIsCollectionsContext()) {
      grid.appendChild(createCollectionAddCardTile());
    }
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

function renderCardsToolbar(filteredCount, totalCount, options = {}) {
  const deckContext = options?.deckContext === true;
  const toolbar = document.createElement("div");
  toolbar.classList.add("collection-browser-toolbar");
  toolbar.innerHTML = `
    <div class="collection-toolbar-head">
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
  `;

  const searchInput = toolbar.querySelector("#collection-grid-search");
  const sortSelect = toolbar.querySelector("#collection-grid-sort");

  if (searchInput) {
    searchInput.value = UI_STATE.searchQuery;
    searchInput.addEventListener("input", () => {
      rerenderCardsFromSearchInput(searchInput);
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

  if (!deckContext) {
    const colorFilters = document.createElement("div");
    colorFilters.classList.add("collection-toolbar-color-filters");
    colorFilters.setAttribute("role", "group");
    colorFilters.setAttribute("aria-label", "Filtre couleur");

    CARD_COLOR_FILTER_CODES.forEach((code) => {
      const toggle = document.createElement("label");
      toggle.classList.add("collection-color-filter-toggle");
      toggle.title = `Couleur: ${CARD_COLOR_FILTER_LABELS[code] || code}`;

      const input = document.createElement("input");
      input.type = "checkbox";
      input.value = code;
      input.checked = UI_STATE.colorFilter[code] === true;

      const symbol = createManaSymbol(code);
      symbol.classList.add("collection-color-filter-symbol");
      symbol.setAttribute("aria-hidden", "true");

      const text = document.createElement("span");
      text.classList.add("visually-hidden");
      text.textContent = CARD_COLOR_FILTER_LABELS[code] || code;

      const syncToggle = () => {
        toggle.classList.toggle("is-active", input.checked === true);
      };
      syncToggle();

      input.addEventListener("change", () => {
        UI_STATE.colorFilter[code] = input.checked === true;
        syncToggle();
        persistCurrentViewState();
        renderCardsPage(1);
      });

      toggle.append(input, symbol, text);
      colorFilters.appendChild(toggle);
    });

    toolbar.appendChild(colorFilters);
  }

  return toolbar;
}

function rerenderCardsFromSearchInput(inputNode) {
  const value = String(inputNode?.value || "");
  const selectionStart = Number.isFinite(inputNode?.selectionStart)
    ? inputNode.selectionStart
    : value.length;
  const selectionEnd = Number.isFinite(inputNode?.selectionEnd)
    ? inputNode.selectionEnd
    : selectionStart;

  UI_STATE.searchQuery = value;
  persistCurrentViewState();
  renderCardsPage(1);

  window.requestAnimationFrame(() => {
    const refreshedInput = document.getElementById("collection-grid-search");
    if (!refreshedInput) {
      return;
    }
    refreshedInput.focus({ preventScroll: true });
    const max = String(refreshedInput.value || "").length;
    const start = Math.max(0, Math.min(selectionStart, max));
    const end = Math.max(start, Math.min(selectionEnd, max));
    if (typeof refreshedInput.setSelectionRange === "function") {
      refreshedInput.setSelectionRange(start, end);
    }
  });
}

function viewKeyIsCollectionsContext() {
  return viewKeySupportsDbActions(String(UI_STATE.activeViewKey || ""));
}

function viewKeySupportsDbActions(viewKeyValue) {
  const viewKey = String(viewKeyValue || "").toLowerCase();
  if (!viewKey.startsWith("collections::")) {
    return false;
  }
  return viewKey.includes(".db") || viewKey.includes("collection/db");
}

function createCollectionAddCardTile() {
  const tile = document.createElement("button");
  tile.type = "button";
  tile.classList.add("collection-card", "collection-card-add");
  tile.innerHTML = `
    <div class="collection-card-art collection-card-add-art" aria-hidden="true">
      <span class="collection-card-add-plus">+</span>
    </div>
    <div class="collection-card-meta">
      <p class="collection-card-name">Ajouter une carte</p>
      <p class="collection-card-line">Recherche Scryfall + choix d'edition</p>
    </div>
  `;
  tile.addEventListener("click", () => {
    window.dispatchEvent(new CustomEvent("mtgcodex:add-card-workflow", {
      detail: {
        viewKey: String(UI_STATE.activeViewKey || "")
      }
    }));
  });
  return tile;
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

  if (viewKeyIsCollectionsContext()) {
    const deleteButton = document.createElement("button");
    deleteButton.type = "button";
    deleteButton.classList.add("collection-card-delete-btn");
    deleteButton.textContent = "x";
    deleteButton.setAttribute("aria-label", "Supprimer la carte");
    deleteButton.title = "Supprimer la carte";
    deleteButton.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      window.dispatchEvent(new CustomEvent("mtgcodex:delete-card-row", {
        detail: {
          viewKey: String(UI_STATE.activeViewKey || ""),
          row: rowData || null
        }
      }));
    });
    tile.appendChild(deleteButton);
  }

  return tile;
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
  const title = document.getElementById("card-preview-title");
  const text = document.getElementById("card-preview-text");
  const image = document.getElementById("card-preview-image");
  if (title) {
    title.textContent = uiText("card");
  }
  if (text) {
    text.textContent = uiText("preview_hint");
  }
  if (image) {
    image.removeAttribute("src");
    image.style.display = "none";
    image.alt = uiText("card_preview_alt");
  }
  renderPreviewMeta([]);
}

function bindRowPreviewEvents(rowElement, rowData) {
  const isDeckContext = String(UI_STATE.activeViewKey || "").startsWith("decks::");
  if (isDeckContext) {
    return;
  }

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
  if (String(UI_STATE.activeViewKey || "").startsWith("decks::")) {
    return;
  }

  cancelPreviewHide();
  if (forceLock) {
    PREVIEW_STATE.locked = true;
  }
  PREVIEW_STATE.activeRow = rowData;
  if (rowElement) {
    markActiveRow(rowElement);
  }

  const panel = document.getElementById("card-preview");
  const title = document.getElementById("card-preview-title");
  const text = document.getElementById("card-preview-text");
  const image = document.getElementById("card-preview-image");
  if (!panel || !title || !text || !image) {
    return;
  }

  panel.classList.remove("hidden");
  title.textContent = formatMainCardTitle(rowData);
  text.textContent = formatPrimaryText(rowData);
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
  const title = document.getElementById("card-preview-title");
  const text = document.getElementById("card-preview-text");
  const image = document.getElementById("card-preview-image");
  if (!title || !text || !image) {
    return;
  }

  const cardName = card.printed_name || card.name || formatMainCardTitle(rowData);
  title.textContent = cardName;
  text.textContent = cardTextForDisplay(card) || formatPrimaryText(rowData);

  const imageUrl = cardImageUrl(card);
  if (imageUrl) {
    image.src = imageUrl;
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
  const panel = document.getElementById("card-preview");
  if (panel) {
    if (isPreviewDockMode()) {
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
  const activeColorCodes = getActiveColorFilterCodes(UI_STATE.colorFilter);

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

  if (activeColorCodes.length > 0) {
    filteredRows = filteredRows.filter((rowData) => rowMatchesColorFilter(rowData, activeColorCodes));
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

function rowMatchesColorFilter(rowData, activeColorCodes) {
  const selected = Array.isArray(activeColorCodes) ? activeColorCodes : [];
  if (selected.length === 0) {
    return true;
  }

  const rowColors = readCardRowColors(rowData);
  return selected.some((code) => {
    if (code === "C") {
      return rowColors.length === 0 || rowColors.includes("C");
    }
    return rowColors.includes(code);
  });
}

function readCardRowColors(rowData) {
  const fromColors = parseColorCodesFromValue(readCellValue(rowData, "colors"));
  if (fromColors.length > 0) {
    return fromColors;
  }

  const manaCost = formatCellValue(readCellValue(rowData, "mana_cost")).trim();
  if (manaCost) {
    const manaColors = extractManaSymbols(manaCost)
      .flatMap((symbol) => parseColorCodesFromManaSymbol(symbol))
      .filter((value, index, source) => source.indexOf(value) === index);
    if (manaColors.length > 0) {
      return manaColors;
    }
  }

  const fromIdentity = parseColorCodesFromValue(readCellValue(rowData, "color_identity"));
  if (fromIdentity.length > 0) {
    return fromIdentity;
  }

  return [];
}

function parseColorCodesFromValue(value) {
  if (value == null) {
    return [];
  }
  if (Array.isArray(value)) {
    const merged = value.flatMap((entry) => parseColorCodesFromValue(entry));
    return merged.filter((item, index, source) => source.indexOf(item) === index);
  }

  const raw = String(value || "").trim().toUpperCase();
  if (!raw) {
    return [];
  }
  if (raw === "COLORLESS") {
    return ["C"];
  }

  const tokens = raw
    .replace(/[\[\]{}()"]/g, " ")
    .replace(/'/g, " ")
    .replace(/[;|]/g, ",")
    .split(/[\s,]+/)
    .map((chunk) => chunk.trim())
    .filter(Boolean);

  const found = [];
  tokens.forEach((token) => {
    if (CARD_COLOR_FILTER_CODES.includes(token)) {
      found.push(token);
      return;
    }
    if (token === "COLORLESS" || token === "COL") {
      found.push("C");
      return;
    }
    if (/^[WUBRGC]+$/.test(token)) {
      token.split("").forEach((char) => {
        found.push(char);
      });
      return;
    }
    if (/^[WUBRGC]\/[WUBRGC]$/.test(token)) {
      token.split("/").forEach((char) => {
        found.push(char);
      });
    }
  });

  return found
    .filter((code) => CARD_COLOR_FILTER_CODES.includes(code))
    .filter((code, index, source) => source.indexOf(code) === index);
}

function parseColorCodesFromManaSymbol(symbol) {
  const normalized = String(symbol || "").trim().toUpperCase();
  if (!normalized) {
    return [];
  }
  return CARD_COLOR_FILTER_CODES
    .filter((code) => normalized.includes(code))
    .filter((code, index, source) => source.indexOf(code) === index);
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

  if (ENABLE_TILE_MANA_API_HYDRATION) {
    hydrateCardTileManaFromScryfall(metaNode, rowData);
  }
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
  const container = document.getElementById("card-preview-meta");
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
  window.localStorage.setItem("mtgcodex_ui_lang", language);

  if (PREVIEW_STATE.activeRow) {
    const activeRow = PREVIEW_STATE.activeRow;
    const activeElement = PREVIEW_STATE.activeElement;
    showCardPreview(activeRow, activeElement, PREVIEW_STATE.locked);
  }
}

function loadSavedLanguage() {
  const saved = window.localStorage.getItem("mtgcodex_ui_lang");
  return saved === "fr" ? "fr" : "en";
}

window.renderCollection = renderCollection;
window.getCollectionLanguage = getCollectionLanguage;
window.setCollectionLanguage = setCollectionLanguage;
window.bindRowPreviewEvents = bindRowPreviewEvents;
window.renderManaCostCell = renderManaCostCell;

export {
  renderCollection,
  getCollectionLanguage,
  setCollectionLanguage,
  bindRowPreviewEvents,
  renderManaCostCell
};
