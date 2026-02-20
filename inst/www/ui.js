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
  sortKey: CARD_VIEW_SORT_KEYS.NAME_ASC
};

const PREVIEW_STATE = {
  locked: false,
  activeRow: null,
  activeElement: null,
  hideTimer: null,
  requestToken: 0,
  cache: new Map()
};

let releaseScrollbarSync = null;

initPreviewEvents();

function renderCollection(payload) {
  const title = document.getElementById("table-title");
  const wrap = document.getElementById("table-wrap");
  const summary = document.getElementById("load-summary");

  wrap.innerHTML = "";
  wrap.classList.remove("is-card-view");
  wrap.removeAttribute("data-table");
  releaseTableScrollbarSync();

  if (!payload || payload.ok !== true) {
    const dbHints = Array.isArray(payload?.available_tables) && payload.available_tables.length > 0
      ? ` Tables disponibles: ${payload.available_tables.join(", ")}`
      : "";
    title.textContent = payload?.table || "Table";
    wrap.innerHTML = `<p class="muted">${payload?.error || "No data"}${dbHints}</p>`;
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

  UI_STATE.rawColumns = Array.isArray(payload.columns) ? payload.columns : [];
  UI_STATE.rows = Array.isArray(payload.rows) ? payload.rows.map(normalizeRowObject) : [];
  UI_STATE.columns = selectVisibleColumns(UI_STATE.rawColumns);

  const payloadPageSize = Number(payload.page_size);
  if (Number.isFinite(payloadPageSize) && payloadPageSize > 0) {
    UI_STATE.tablePageSize = Math.floor(payloadPageSize);
  }
  UI_STATE.pageSize = UI_STATE.viewMode === "cards" ? UI_STATE.cardPageSize : UI_STATE.tablePageSize;
  UI_STATE.currentPage = 1;

  if (UI_STATE.columns.length === 0) {
    wrap.innerHTML = '<p class="muted">Aucune colonne a afficher.</p>';
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

function renderTablePage(pageNumber) {
  const wrap = document.getElementById("table-wrap");
  if (!wrap) {
    return;
  }

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

  const filteredRows = applyCardFiltersAndSorting(UI_STATE.rows);
  const totalRows = filteredRows.length;
  const totalPages = Math.max(1, Math.ceil(totalRows / UI_STATE.pageSize));
  const nextPage = Number.isFinite(pageNumber) ? Math.floor(pageNumber) : 1;
  UI_STATE.currentPage = Math.min(Math.max(nextPage, 1), totalPages);

  const startIndex = (UI_STATE.currentPage - 1) * UI_STATE.pageSize;
  const endIndex = startIndex + UI_STATE.pageSize;
  const pageRows = filteredRows.slice(startIndex, endIndex);

  const browser = document.createElement("section");
  browser.classList.add("collection-browser");

  const toolbar = renderCardsToolbar(totalRows, UI_STATE.rows.length);
  browser.appendChild(toolbar);

  const grid = document.createElement("div");
  grid.classList.add("collection-card-grid");
  if (pageRows.length === 0) {
    grid.innerHTML = '<div class="collection-empty-state muted">Aucune carte ne correspond a ta recherche.</div>';
  } else {
    pageRows.forEach((rowData) => {
      grid.appendChild(createCollectionCardTile(rowData));
    });
  }
  browser.appendChild(grid);

  wrap.appendChild(browser);
  renderTablePager(totalRows, startIndex, pageRows.length);
}

function renderCardsToolbar(filteredCount, totalCount) {
  const toolbar = document.createElement("div");
  toolbar.classList.add("collection-browser-toolbar");
  toolbar.innerHTML = `
    <div class="collection-toolbar-head">
      <div class="collection-toolbar-actions">
        <button type="button" class="collection-action-btn" data-action="quick-import">Actions</button>
        <button type="button" class="collection-action-btn is-muted" data-action="toggle-preview">Edit</button>
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
  `;

  const searchInput = toolbar.querySelector("#collection-grid-search");
  const sortSelect = toolbar.querySelector("#collection-grid-sort");
  const quickImportButton = toolbar.querySelector('button[data-action="quick-import"]');
  const previewButton = toolbar.querySelector('button[data-action="toggle-preview"]');
  const shareButton = toolbar.querySelector('button[data-action="focus-search"]');

  if (searchInput) {
    searchInput.value = UI_STATE.searchQuery;
    searchInput.addEventListener("input", () => {
      UI_STATE.searchQuery = searchInput.value || "";
      renderCardsPage(1);
    });
  }

  if (sortSelect) {
    sortSelect.value = UI_STATE.sortKey;
    sortSelect.addEventListener("change", () => {
      UI_STATE.sortKey = sortSelect.value || CARD_VIEW_SORT_KEYS.NAME_ASC;
      renderCardsPage(1);
    });
  }

  if (quickImportButton) {
    quickImportButton.addEventListener("click", () => {
      const form = document.getElementById("collection-load-form");
      form?.scrollIntoView({ behavior: "smooth", block: "start" });
    });
  }

  if (previewButton) {
    previewButton.addEventListener("click", () => {
      if (PREVIEW_STATE.activeRow && PREVIEW_STATE.activeElement) {
        showCardPreview(PREVIEW_STATE.activeRow, PREVIEW_STATE.activeElement, true);
      }
    });
  }

  if (shareButton) {
    shareButton.addEventListener("click", () => {
      searchInput?.focus();
      searchInput?.select();
    });
  }

  return toolbar;
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
  const manaCost = formatCellValue(readCellValue(rowData, "mana_cost"));
  meta.innerHTML = `
    <p class="collection-card-name">${escapeHtml(formatMainCardTitle(rowData))}</p>
    <p class="collection-card-line">${escapeHtml(formatCardTileSubtitle(rowData))}</p>
  `;
  const manaIcons = createCardTileManaIcons(manaCost);
  if (manaIcons) {
    meta.appendChild(manaIcons);
  }
  tile.appendChild(meta);

  return tile;
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
  const dataLabel = UI_STATE.viewMode === "cards" ? "Cartes" : "Lignes";
  const onPageChange = UI_STATE.viewMode === "cards" ? renderCardsPage : renderTablePage;

  pager.classList.add("is-visible");
  pager.innerHTML = `
    <div class="table-pager-info">${dataLabel} ${start}-${end} / ${totalRows} (page ${UI_STATE.currentPage}/${totalPages})</div>
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

function bindRowPreviewEvents(rowElement, rowData) {
  rowElement.addEventListener("mouseenter", () => {
    if (PREVIEW_STATE.locked && PREVIEW_STATE.activeElement !== rowElement) {
      return;
    }
    showCardPreview(rowData, rowElement, false);
  });

  rowElement.addEventListener("mouseleave", () => {
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
    panel.classList.add("hidden");
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
  return {};
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

  let filteredRows = sourceRows;
  if (query) {
    filteredRows = sourceRows.filter((rowData) => {
      const lookup = [
        readCellValue(rowData, "name"),
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

function readCardQuantity(rowData) {
  const quantityRaw = readFirstCellValue(rowData, ["quantity", "qty", "count", "owned"]);
  const quantity = Number.parseInt(String(quantityRaw || "").trim(), 10);
  return Number.isFinite(quantity) && quantity > 0 ? quantity : 1;
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

function cardImageUrlFromRow(rowData) {
  const scryfallId = formatCellValue(readFirstCellValue(rowData, ["scryfall_id", "scry_fall_id"])).trim();
  if (scryfallId) {
    return `https://api.scryfall.com/cards/${encodeURIComponent(scryfallId)}?format=image&version=normal`;
  }

  const cardName = formatCellValue(readCellValue(rowData, "name")).trim();
  if (!cardName) {
    return "";
  }

  const params = new URLSearchParams({
    exact: cardName,
    format: "image",
    version: "normal"
  });

  const setCode = formatCellValue(readCellValue(rowData, "set_code")).trim();
  if (/^[a-z0-9]{2,6}$/i.test(setCode)) {
    params.set("set", setCode.toLowerCase());
  }

  const language = formatCellValue(readFirstCellValue(rowData, ["language", "lang"])).trim();
  if (/^[a-z]{2}$/.test(language.toLowerCase())) {
    params.set("lang", language.toLowerCase());
  }

  return `https://api.scryfall.com/cards/named?${params.toString()}`;
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
  const raw = String(text || "");
  const matches = raw.match(/\{([^}]+)\}/g);
  if (!matches || matches.length === 0) {
    return [];
  }
  return matches
    .map((chunk) => chunk.slice(1, -1).trim())
    .filter(Boolean);
}

function createManaSymbol(symbol) {
  const normalized = String(symbol || "").trim().toUpperCase();
  const iconWrap = document.createElement("span");
  iconWrap.classList.add("mana-symbol");
  iconWrap.setAttribute("aria-label", `Mana ${normalized}`);

  const iconUrl = manaSymbolIconUrl(normalized);
  if (!iconUrl) {
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
  const fallback = readFirstCellValue(rowData, ["scryfall_id", "scry_fall_id"]);
  return formatCellValue(readCellValue(rowData, "name")) || formatCellValue(fallback) || "Carte";
}

function formatPrimaryText(rowData) {
  return formatCellValue(readCellValue(rowData, "oracle_text")) || "Aucun texte oracle disponible.";
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
