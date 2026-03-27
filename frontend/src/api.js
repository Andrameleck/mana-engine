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
window.importCollectionCsv = importCollectionCsv;
window.listStoredCollections = listStoredCollections;
window.getStoredCollection = getStoredCollection;
window.deleteStoredCollection = deleteStoredCollection;
window.fetchSpellbookVariants = fetchSpellbookVariants;
window.fetchMtgjsonCards = fetchMtgjsonCards;

export {
  uploadCollection,
  importCollectionCsv,
  listStoredCollections,
  getStoredCollection,
  deleteStoredCollection,
  fetchSpellbookVariants,
  fetchMtgjsonCards
};
