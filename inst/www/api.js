async function apiGetJson(path) {
  const response = await fetch(path);
  const data = await response.json();
  return data;
}

async function fetchMdbStatus() {
  return apiGetJson("/mdb/status");
}

async function fetchMdbTables() {
  return apiGetJson("/mdb/tables");
}

async function fetchTablePreview(name, limit) {
  const params = new URLSearchParams({ name, limit: String(limit) });
  return apiGetJson(`/mdb/table?${params.toString()}`);
}
