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
