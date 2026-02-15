const COMPACT_COLUMN_ORDER = [
  "name",
  "oracle_text",
  "type_line",
  "mana_cost",
  "cmc",
  "colors",
  "color_identity",
  "set",
  "collector_number",
  "rarity",
  "scry_fall_id",
  "scryfall_id"
];

const UI_STATE = {
  language: loadSavedLanguage(),
  rows: [],
  rawColumns: []
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
  wrap.removeAttribute("data-table");
  releaseTableScrollbarSync();

  if (!payload || payload.ok !== true) {
    const dbHints = Array.isArray(payload?.available_tables) && payload.available_tables.length > 0
      ? ` Tables disponibles: ${payload.available_tables.join(", ")}`
      : "";
    title.textContent = "Collection";
    wrap.innerHTML = `<p class="muted">${payload?.error || "No data"}${dbHints}</p>`;
    summary.textContent = payload?.path || "";
    clearCardPreview(true);
    hideBottomScrollbar();
    return;
  }

  const source = `${payload.source_type || "source"}: ${payload.path || ""}`;
  title.textContent = `${payload.table || "Collection"} (${payload.row_count} lignes)`;
  summary.textContent = source;
  wrap.dataset.table = String(payload.source_type || "").toLowerCase();

  UI_STATE.rawColumns = Array.isArray(payload.columns) ? payload.columns : [];
  UI_STATE.rows = Array.isArray(payload.rows) ? payload.rows.map(normalizeRowObject) : [];

  const columns = selectVisibleColumns(UI_STATE.rawColumns);

  if (columns.length === 0) {
    wrap.innerHTML = '<p class="muted">Aucune colonne a afficher.</p>';
    clearCardPreview(true);
    hideBottomScrollbar();
    return;
  }

  const table = document.createElement("table");
  const thead = document.createElement("thead");
  const headRow = document.createElement("tr");

  columns.forEach((col) => {
    const th = document.createElement("th");
    th.textContent = col;
    th.dataset.col = col;
    th.classList.add(columnClassName(col));
    headRow.appendChild(th);
  });
  thead.appendChild(headRow);
  table.appendChild(thead);

  const tbody = document.createElement("tbody");
  UI_STATE.rows.forEach((rowData) => {
    const tr = document.createElement("tr");
    tr.classList.add("data-row");
    bindRowPreviewEvents(tr, rowData);

    columns.forEach((col) => {
      const td = document.createElement("td");
      const value = readCellValue(rowData, col);
      const text = formatCellValue(value);
      td.textContent = text;
      td.dataset.col = col;
      td.classList.add(columnClassName(col));
      if (text.length > 70) {
        td.title = text;
      }
      tr.appendChild(td);
    });
    tbody.appendChild(tr);
  });

  table.appendChild(tbody);
  wrap.appendChild(table);
  syncBottomScrollbar(wrap, table);
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
  const availableByLowercase = new Map();
  columns.forEach((column) => {
    availableByLowercase.set(String(column).toLowerCase(), column);
  });

  const ordered = COMPACT_COLUMN_ORDER
    .map((columnName) => availableByLowercase.get(columnName))
    .filter(Boolean);

  if (ordered.length === 0) {
    return reorderColumns(columns.slice(0, 10));
  }

  return reorderColumns(ordered);
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
    ["lang", formatCellValue(readCellValue(rowData, "lang")) || getCollectionLanguage()],
    ["rarete", formatCellValue(readCellValue(rowData, "rarity"))],
    ["set", formatCellValue(readCellValue(rowData, "set"))],
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

  const preferredSet = String(readCellValue(rowData, "set") || "").toLowerCase();
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
