async function uploadCollection(file, sourceType, tableName) {
  const params = new URLSearchParams({
    type: sourceType,
    table: tableName || ""
  });
  const formData = new FormData();
  formData.append("file", file);

  const response = await fetch(`/collection/upload?${params.toString()}`, {
    method: "POST",
    body: formData
  });
  const data = await response.json().catch(() => ({}));

  if (!response.ok && data.ok !== false) {
    return {
      ok: false,
      error: `HTTP ${response.status}`
    };
  }

  return data;
}

async function loadCollectionFromDb(dbPath = "", tableName = "collection") {
  const params = new URLSearchParams({
    type: "db",
    path: dbPath || "",
    table: tableName || "collection"
  });
  const response = await fetch(`/collection/load?${params.toString()}`, {
    method: "GET"
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok && data.ok !== false) {
    return {
      ok: false,
      error: `HTTP ${response.status}`
    };
  }
  return data;
}

async function importCollectionCsv(file, name, platform) {
  const params = new URLSearchParams({
    name: name || "",
    platform: platform || "auto"
  });
  const formData = new FormData();
  formData.append("file", file);

  const response = await fetch(`/collections/import_csv?${params.toString()}`, {
    method: "POST",
    body: formData
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok && data.ok !== false) {
    return {
      ok: false,
      error: `HTTP ${response.status}`
    };
  }
  return data;
}

async function importIntoCollectionDb(file, dbPath = "", sourceType = "", sourceTable = "", dedupe = true) {
  const params = new URLSearchParams({
    db_path: dbPath || "",
    source_type: sourceType || "",
    source_table: sourceTable || "",
    dedupe: dedupe ? "true" : "false"
  });
  const formData = new FormData();
  formData.append("file", file);

  const response = await fetch(`/collection/db/import?${params.toString()}`, {
    method: "POST",
    body: formData
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok && data.ok !== false) {
    return {
      ok: false,
      error: `HTTP ${response.status}`
    };
  }
  return data;
}

async function addCardToCollectionDb(card = {}, dbPath = "", dedupe = true) {
  const params = new URLSearchParams({
    db_path: dbPath || "",
    dedupe: dedupe ? "true" : "false"
  });

  Object.entries(card || {}).forEach(([key, value]) => {
    params.set(key, value == null ? "" : String(value));
  });

  const response = await fetch(`/collection/db/add_card?${params.toString()}`, {
    method: "POST"
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok && data.ok !== false) {
    return {
      ok: false,
      error: `HTTP ${response.status}`
    };
  }
  return data;
}

async function deleteCardFromCollectionDb(selector = {}, dbPath = "", deleteAll = false) {
  const params = new URLSearchParams({
    db_path: dbPath || "",
    delete_all: deleteAll ? "true" : "false"
  });

  Object.entries(selector || {}).forEach(([key, value]) => {
    if (value == null) {
      return;
    }
    const text = String(value).trim();
    if (!text) {
      return;
    }
    params.set(key, text);
  });

  const response = await fetch(`/collection/db/delete_card?${params.toString()}`, {
    method: "DELETE"
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok && data.ok !== false) {
    return {
      ok: false,
      error: `HTTP ${response.status}`
    };
  }
  return data;
}

async function listStoredCollections() {
  const response = await fetch("/collections", {
    method: "GET"
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok && data.ok !== false) {
    return {
      ok: false,
      error: `HTTP ${response.status}`
    };
  }
  return data;
}

async function getStoredCollection(collectionId) {
  const id = encodeURIComponent(String(collectionId || ""));
  const response = await fetch(`/collections/${id}`, {
    method: "GET"
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok && data.ok !== false) {
    return {
      ok: false,
      error: `HTTP ${response.status}`
    };
  }
  return data;
}

async function deleteStoredCollection(collectionId) {
  const id = encodeURIComponent(String(collectionId || ""));
  const response = await fetch(`/collections/${id}`, {
    method: "DELETE"
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok && data.ok !== false) {
    return {
      ok: false,
      error: `HTTP ${response.status}`
    };
  }
  return data;
}

async function fetchSpellbookVariants(query, limit = 40) {
  const params = new URLSearchParams({
    q: String(query || "").trim(),
    limit: String(limit || 40)
  });
  const response = await fetch(`/reference/spellbook/variants?${params.toString()}`, {
    method: "GET"
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok && data.ok !== false) {
    return {
      ok: false,
      error: `HTTP ${response.status}`,
      results: []
    };
  }
  return data;
}

async function fetchMtgjsonCards({
  q = "",
  set_code = "",
  collector_number = "",
  uuid = "",
  limit = 40
} = {}) {
  const params = new URLSearchParams({
    q: String(q || "").trim(),
    set_code: String(set_code || "").trim(),
    collector_number: String(collector_number || "").trim(),
    uuid: String(uuid || "").trim(),
    limit: String(limit || 40)
  });
  const response = await fetch(`/reference/mtgjson/cards?${params.toString()}`, {
    method: "GET"
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok && data.ok !== false) {
    return {
      ok: false,
      error: `HTTP ${response.status}`,
      results: []
    };
  }
  return data;
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
  fetchMtgjsonCards
};
