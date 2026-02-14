function renderStatus(status) {
  const box = document.getElementById("status-box");
  box.textContent = JSON.stringify(status, null, 2);
}

function renderTables(tables, onSelect) {
  const list = document.getElementById("tables-list");
  list.innerHTML = "";

  if (!Array.isArray(tables) || tables.length === 0) {
    list.innerHTML = '<li class="muted">No table found</li>';
    return;
  }

  tables.forEach((tableName) => {
    const item = document.createElement("li");
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = tableName;
    button.addEventListener("click", () => onSelect(tableName));
    item.appendChild(button);
    list.appendChild(item);
  });
}

function renderTablePreview(payload) {
  const title = document.getElementById("table-title");
  const wrap = document.getElementById("table-wrap");
  wrap.innerHTML = "";
  wrap.removeAttribute("data-table");

  if (!payload || payload.ok !== true) {
    title.textContent = "Cartes";
    wrap.innerHTML = `<p class="muted">${payload?.error || "No data"}</p>`;
    return;
  }

  title.textContent = `Cartes: ${payload.table} (${payload.row_count} lignes)`;
  wrap.dataset.table = String(payload.table || "").toLowerCase();

  const columns = reorderColumns(payload.columns || []);
  const rows = payload.rows || [];

  if (columns.length === 0) {
    wrap.innerHTML = '<p class="muted">Table is empty.</p>';
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

function reorderColumns(columns) {
  if (!Array.isArray(columns)) {
    return [];
  }

  const ordered = [...columns];
  const scryfallIndex = ordered.findIndex((col) => String(col).toLowerCase() === "scryfall_id");
  if (scryfallIndex === -1) {
    return ordered;
  }

  const [scryfallCol] = ordered.splice(scryfallIndex, 1);
  ordered.push(scryfallCol);
  return ordered;
}

function columnClassName(col) {
  return `col-${String(col || "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")}`;
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
