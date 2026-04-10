const API_ENDPOINTS = Object.freeze({
  collectionLoad: "/collection/load",
  collectionUpload: "/collection/upload",
  collectionDbImport: "/collection/db/import",
  collectionDbAddCard: "/collection/db/add_card",
  collectionDbDeleteCard: "/collection/db/delete_card",
  collectionsImportCsv: "/collections/import_csv",
  collections: "/collections",
  strategyBridgeEquation: "/strategy/bridge_equation",
  referenceLotusNoirPosts: "/reference/lotusnoir/posts",
  referenceSpellbookVariants: "/reference/spellbook/variants",
  referenceMtgjsonCards: "/reference/mtgjson/cards"
});

function toText(value) {
  if (value == null) {
    return "";
  }
  return String(value);
}

function toTrimmedText(value) {
  return toText(value).trim();
}

function buildSearchParams(query = {}) {
  const params = new URLSearchParams();
  Object.entries(query || {}).forEach(([key, value]) => {
    if (value == null) {
      return;
    }
    if (Array.isArray(value)) {
      value.forEach((entry) => params.append(key, toText(entry)));
      return;
    }
    params.set(key, toText(value));
  });
  return params;
}

function appendQuery(endpoint, query = {}) {
  const params = buildSearchParams(query);
  const raw = params.toString();
  if (!raw) {
    return endpoint;
  }
  return `${endpoint}?${raw}`;
}

function getClientId() {
  const storageKey = "mtgcodex_client_id_v1";
  try {
    const saved = window.localStorage.getItem(storageKey);
    if (saved && String(saved).trim()) {
      return String(saved).trim();
    }
  } catch (_) {
    // ignore localStorage access errors
  }

  const generated = `web-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
  try {
    window.localStorage.setItem(storageKey, generated);
  } catch (_) {
    // ignore localStorage access errors
  }
  return generated;
}

function uploadBody(file) {
  const formData = new FormData();
  formData.append("file", file);
  return formData;
}

async function apiRequest(endpoint, options = {}) {
  const {
    method = "GET",
    query = {},
    body = undefined,
    headers = undefined,
    fallback = {}
  } = options;

  const url = appendQuery(endpoint, query);
  let response;
  try {
    response = await fetch(url, { method, body, headers });
  } catch (error) {
    return {
      ok: false,
      error: error?.message || String(error),
      ...fallback
    };
  }

  const data = await response.json().catch(() => ({}));
  if (!response.ok && data.ok !== false) {
    return {
      ok: false,
      error: `HTTP ${response.status}`,
      ...fallback
    };
  }
  return data;
}

async function uploadCollection(file, sourceType, tableName) {
  return apiRequest(API_ENDPOINTS.collectionUpload, {
    method: "POST",
    query: {
      type: toText(sourceType),
      table: toText(tableName || "")
    },
    body: uploadBody(file)
  });
}

async function loadCollectionFromDb(dbPath = "", tableName = "collection") {
  return apiRequest(API_ENDPOINTS.collectionLoad, {
    method: "GET",
    query: {
      type: "db",
      path: toText(dbPath || ""),
      table: toText(tableName || "collection")
    }
  });
}

async function importCollectionCsv(file, name, platform) {
  return apiRequest(API_ENDPOINTS.collectionsImportCsv, {
    method: "POST",
    query: {
      client_id: getClientId(),
      name: toText(name || ""),
      platform: toText(platform || "auto")
    },
    body: uploadBody(file)
  });
}

async function importIntoCollectionDb(file, dbPath = "", sourceType = "", sourceTable = "", dedupe = true) {
  return apiRequest(API_ENDPOINTS.collectionDbImport, {
    method: "POST",
    query: {
      db_path: toText(dbPath || ""),
      source_type: toText(sourceType || ""),
      source_table: toText(sourceTable || ""),
      dedupe: dedupe ? "true" : "false"
    },
    body: uploadBody(file)
  });
}

async function addCardToCollectionDb(card = {}, dbPath = "", dedupe = true) {
  const query = {
    db_path: toText(dbPath || ""),
    dedupe: dedupe ? "true" : "false"
  };

  Object.entries(card || {}).forEach(([key, value]) => {
    query[key] = toText(value);
  });

  return apiRequest(API_ENDPOINTS.collectionDbAddCard, {
    method: "POST",
    query
  });
}

async function deleteCardFromCollectionDb(selector = {}, dbPath = "", deleteAll = false) {
  const query = {
    db_path: toText(dbPath || ""),
    delete_all: deleteAll ? "true" : "false"
  };

  Object.entries(selector || {}).forEach(([key, value]) => {
    const text = toTrimmedText(value);
    if (!text) {
      return;
    }
    query[key] = text;
  });

  return apiRequest(API_ENDPOINTS.collectionDbDeleteCard, {
    method: "DELETE",
    query
  });
}

async function listStoredCollections() {
  return apiRequest(API_ENDPOINTS.collections, {
    method: "GET",
    query: {
      client_id: getClientId()
    }
  });
}

async function getStoredCollection(collectionId) {
  const id = encodeURIComponent(toText(collectionId || ""));
  return apiRequest(`${API_ENDPOINTS.collections}/${id}`, {
    method: "GET",
    query: {
      client_id: getClientId()
    }
  });
}

async function deleteStoredCollection(collectionId) {
  const id = encodeURIComponent(toText(collectionId || ""));
  return apiRequest(`${API_ENDPOINTS.collections}/${id}`, {
    method: "DELETE",
    query: {
      client_id: getClientId()
    }
  });
}

async function fetchSpellbookVariants(query, limit = 40) {
  return apiRequest(API_ENDPOINTS.referenceSpellbookVariants, {
    method: "GET",
    query: {
      q: toTrimmedText(query),
      limit: toText(limit || 40)
    },
    fallback: { results: [] }
  });
}

async function fetchLotusNoirPosts(query, limit = 120) {
  return apiRequest(API_ENDPOINTS.referenceLotusNoirPosts, {
    method: "GET",
    query: {
      q: toTrimmedText(query),
      limit: toText(limit || 120)
    },
    fallback: { results: [] }
  });
}

async function fetchStrategyBridgeEquation(payload = {}) {
  return apiRequest(API_ENDPOINTS.strategyBridgeEquation, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload || {}),
    fallback: { candidates: [] }
  });
}

async function fetchMtgjsonCards({
  q = "",
  set_code = "",
  collector_number = "",
  uuid = "",
  limit = 40
} = {}) {
  return apiRequest(API_ENDPOINTS.referenceMtgjsonCards, {
    method: "GET",
    query: {
      q: toTrimmedText(q),
      set_code: toTrimmedText(set_code),
      collector_number: toTrimmedText(collector_number),
      uuid: toTrimmedText(uuid),
      limit: toText(limit || 40)
    },
    fallback: { results: [] }
  });
}

window.uploadCollection = uploadCollection;
window.loadCollectionFromDb = loadCollectionFromDb;
window.importCollectionCsv = importCollectionCsv;
window.importIntoCollectionDb = importIntoCollectionDb;
window.addCardToCollectionDb = addCardToCollectionDb;
window.deleteCardFromCollectionDb = deleteCardFromCollectionDb;
window.listStoredCollections = listStoredCollections;
window.getStoredCollection = getStoredCollection;
window.deleteStoredCollection = deleteStoredCollection;
window.fetchSpellbookVariants = fetchSpellbookVariants;
window.fetchLotusNoirPosts = fetchLotusNoirPosts;
window.fetchStrategyBridgeEquation = fetchStrategyBridgeEquation;
window.fetchMtgjsonCards = fetchMtgjsonCards;

export {
  uploadCollection,
  loadCollectionFromDb,
  importCollectionCsv,
  importIntoCollectionDb,
  addCardToCollectionDb,
  deleteCardFromCollectionDb,
  listStoredCollections,
  getStoredCollection,
  deleteStoredCollection,
  fetchSpellbookVariants,
  fetchLotusNoirPosts,
  fetchStrategyBridgeEquation,
  fetchMtgjsonCards
};
