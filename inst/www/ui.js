function renderCollection(payload) {
  const title = document.getElementById("table-title");
  const wrap = document.getElementById("table-wrap");
  const summary = document.getElementById("load-summary");

  wrap.innerHTML = "";
  wrap.removeAttribute("data-table");

  if (!payload || payload.ok !== true) {
    const dbHints = Array.isArray(payload?.available_tables) && payload.available_tables.length > 0
      ? ` Tables disponibles: ${payload.available_tables.join(", ")}`
      : "";
    title.textContent = "Collection";
    wrap.innerHTML = `<p class="muted">${payload?.error || "No data"}${dbHints}</p>`;
    summary.textContent = payload?.path || "";
    return;
  }

  const source = `${payload.source_type || "source"}: ${payload.path || ""}`;
  title.textContent = `${payload.table || "Collection"} (${payload.row_count} lignes)`;
  summary.textContent = source;
  wrap.dataset.table = String(payload.source_type || "").toLowerCase();

  const columns = reorderColumns(payload.columns || []);
  const rows = payload.rows || [];

  if (columns.length === 0) {
    wrap.innerHTML = '<p class="muted">Aucune colonne a afficher.</p>';
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
  rows.forEach((row) => {
    const tr = document.createElement("tr");
    columns.forEach((col) => {
      const td = document.createElement("td");
      const value = readCellValue(row, col);
      const text = formatCellValue(value);
      td.textContent = text;
      td.dataset.col = col;
      td.classList.add(columnClassName(col));
      if (text.length > 120) {
        td.title = text;
      }
      tr.appendChild(td);
    });
    tbody.appendChild(tr);
  });

  table.appendChild(tbody);
  wrap.appendChild(table);
}

function columnClassName(col) {
  return `col-${String(col || "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")}`;
}

function reorderColumns(columns) {
  const ordered = Array.isArray(columns) ? [...columns] : [];
  const scryfallIdIndex = ordered.findIndex(
    (col) => String(col).toLowerCase() === "scryfall_id"
  );

  if (scryfallIdIndex < 0) {
    return ordered;
  }

  const [scryfallIdColumn] = ordered.splice(scryfallIdIndex, 1);
  ordered.push(scryfallIdColumn);
  return ordered;
}

function readCellValue(row, col) {
  if (row && Object.prototype.hasOwnProperty.call(row, col)) {
    return row[col];
  }

  // Some serializers can wrap a row object in a single-item array.
  if (Array.isArray(row) && row.length === 1 && row[0] && typeof row[0] === "object") {
    const nested = row[0];
    if (Object.prototype.hasOwnProperty.call(nested, col)) {
      return nested[col];
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
