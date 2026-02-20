import {
  uploadCollection,
  importCollectionCsv,
  listStoredCollections,
  getStoredCollection,
  deleteStoredCollection
} from "./api.js";
import {
  renderCollection,
  getCollectionLanguage,
  setCollectionLanguage
} from "./ui.js";

(function bootstrap() {
  const TAB_META = {
    collections: {
      title: "Collections",
      subtitle: "Creer et gerer plusieurs dossiers de collection."
    },
    decks: {
      title: "Decks",
      subtitle: "Importer et visualiser plusieurs decks."
    },
    strategy: {
      title: "Strategy",
      subtitle: "Zone reservee au module de strategies."
    }
  };

  const state = {
    activeTab: "collections",
    collections: [],
    collectionPayloadById: {},
    selectedCollectionId: null,
    decks: [],
    selectedDeckId: null
  };

  const nodes = {
    tabButtons: Array.from(document.querySelectorAll(".side-tab")),
    tabViews: Array.from(document.querySelectorAll(".tab-view")),
    workspaceTitle: document.getElementById("workspace-title"),
    workspaceSubtitle: document.getElementById("workspace-subtitle"),
    langEnButton: document.getElementById("lang-en"),
    langFrButton: document.getElementById("lang-fr"),
    collections: {
      form: document.getElementById("collection-load-form"),
      nameInput: document.getElementById("collection-name"),
      fileInput: document.getElementById("collection-source-file"),
      pickFileButton: document.getElementById("collection-pick-file"),
      list: document.getElementById("collections-list")
    },
    decks: {
      form: document.getElementById("deck-load-form"),
      nameInput: document.getElementById("deck-name"),
      fileInput: document.getElementById("deck-source-file"),
      pickFileButton: document.getElementById("deck-pick-file"),
      list: document.getElementById("decks-list")
    }
  };

  function applyLanguageButtonState(language) {
    if (!nodes.langEnButton || !nodes.langFrButton) {
      return;
    }
    nodes.langEnButton.classList.toggle("is-active", language === "en");
    nodes.langFrButton.classList.toggle("is-active", language === "fr");
  }

  function onLanguageSelect(language) {
    setCollectionLanguage(language);
    applyLanguageButtonState(language);
    if (state.activeTab === "collections" && state.selectedCollectionId) {
      loadStoredCollectionIntoTable(state.selectedCollectionId);
    }
  }

  function bindCollectionPicker() {
    nodes.collections.fileInput.accept = ".csv,.txt";
    const defaultPickLabel = "Choisir CSV";
    setCollectionPickButtonLabel(defaultPickLabel);
    nodes.collections.pickFileButton.classList.remove("has-file");
    nodes.collections.pickFileButton.addEventListener("click", () => {
      nodes.collections.fileInput.click();
    });
    nodes.collections.fileInput.addEventListener("change", () => {
      const selected = nodes.collections.fileInput.files && nodes.collections.fileInput.files[0];
      setCollectionPickButtonLabel(selected ? `CSV: ${selected.name}` : defaultPickLabel);
      nodes.collections.pickFileButton.classList.toggle("has-file", Boolean(selected));
    });
  }

  function setCollectionPickButtonLabel(label) {
    const button = nodes.collections.pickFileButton;
    if (!button) {
      return;
    }
    const text = String(label || "Choisir CSV");
    const labelNode = button.querySelector(".btn-label");
    if (labelNode) {
      labelNode.textContent = text;
      button.title = text;
      button.setAttribute("aria-label", text);
      return;
    }
    button.title = text;
    button.setAttribute("aria-label", text);
  }

  function bindDeckPicker() {
    nodes.decks.fileInput.accept = ".txt,.text,.tsv,.csv,.db,.sqlite,.sqlite3";
    const defaultPickLabel = "Choisir un fichier deck";
    setDeckPickButtonLabel(defaultPickLabel);
    nodes.decks.pickFileButton.classList.remove("has-file");
    nodes.decks.pickFileButton.addEventListener("click", () => {
      nodes.decks.fileInput.click();
    });
    nodes.decks.fileInput.addEventListener("change", () => {
      const selected = nodes.decks.fileInput.files && nodes.decks.fileInput.files[0];
      setDeckPickButtonLabel(selected ? `Deck: ${selected.name}` : defaultPickLabel);
      nodes.decks.pickFileButton.classList.toggle("has-file", Boolean(selected));
    });
  }

  function setDeckPickButtonLabel(label) {
    const button = nodes.decks.pickFileButton;
    if (!button) {
      return;
    }
    const text = String(label || "Choisir un fichier deck");
    button.title = text;
    button.setAttribute("aria-label", text);
  }

  function inferDeckSourceType(fileName) {
    const lowerName = String(fileName || "").toLowerCase();
    if (lowerName.endsWith(".db") || lowerName.endsWith(".sqlite") || lowerName.endsWith(".sqlite3")) {
      return "db";
    }
    if (lowerName.endsWith(".csv")) {
      return "csv";
    }
    return "text";
  }

  function selectTab(tabId) {
    state.activeTab = tabId;

    nodes.tabButtons.forEach((button) => {
      button.classList.toggle("is-active", button.dataset.tab === tabId);
    });
    nodes.tabViews.forEach((view) => {
      view.classList.toggle("is-active", view.id === `tab-${tabId}`);
    });

    const meta = TAB_META[tabId] || TAB_META.collections;
    nodes.workspaceTitle.textContent = meta.title;
    nodes.workspaceSubtitle.textContent = meta.subtitle;
    renderActiveTabTable();
  }

  function payloadForNamedView(payload, name, fallbackSummary, viewMode = "table") {
    if (!payload) {
      return {
        ok: false,
        table: name,
        error: "No data loaded."
      };
    }
    return {
      ...payload,
      table: payload.table || name,
      path: payload.path || fallbackSummary,
      view_mode: viewMode
    };
  }

  async function refreshCollectionsListFromApi() {
    const payload = await listStoredCollections();
    if (!payload || payload.ok !== true) {
      state.collections = [];
      state.selectedCollectionId = null;
      renderCollectionsList(payload?.error || "Impossible de charger les dossiers.");
      return false;
    }

    state.collections = Array.isArray(payload.collections) ? payload.collections : [];
    if (!state.collections.some((entry) => entry.id === state.selectedCollectionId)) {
      state.selectedCollectionId = state.collections[0]?.id || null;
    }
    renderCollectionsList("");
    return true;
  }

  function renderCollectionsList(errorMessage) {
    const list = nodes.collections.list;
    if (!list) {
      return;
    }

    if (errorMessage) {
      list.innerHTML = `<p class="muted">${escapeHtml(errorMessage)}</p>`;
      return;
    }

    if (state.collections.length === 0) {
      list.innerHTML = '<p class="muted">Aucun dossier collection pour le moment.</p>';
      return;
    }

    list.innerHTML = state.collections.map((entry) => {
      const activeClass = entry.id === state.selectedCollectionId ? "is-active" : "";
      const platform = entry.platform || "auto";
      const createdAt = entry.created_at || "";
      const rowCount = entry.row_count ?? "-";

      return `
        <article class="entity-item ${activeClass}" data-entity-id="${escapeHtml(entry.id)}">
          <div>
            <p class="entity-item-name">Dossier: ${escapeHtml(entry.name || entry.id)}</p>
            <p class="entity-item-meta">${escapeHtml(platform)} | ${escapeHtml(String(rowCount))} lignes | ${escapeHtml(createdAt)}</p>
          </div>
          <div class="entity-actions">
            <button type="button" class="entity-select" data-action="select">Ouvrir</button>
            <button type="button" class="entity-delete" data-action="delete">Supprimer</button>
          </div>
        </article>
      `;
    }).join("");
  }

  async function loadStoredCollectionIntoTable(collectionId) {
    if (!collectionId) {
      return;
    }
    const payload = await getStoredCollection(collectionId);
    state.collectionPayloadById[collectionId] = payload;
    if (state.activeTab === "collections" && state.selectedCollectionId === collectionId) {
      renderActiveTabTable();
    }
  }

  function renderDecksList() {
    const list = nodes.decks.list;
    if (!list) {
      return;
    }
    if (state.decks.length === 0) {
      list.innerHTML = '<p class="muted">Aucun deck pour le moment.</p>';
      return;
    }

    list.innerHTML = state.decks.map((entry, index) => {
      const activeClass = entry.id === state.selectedDeckId ? "is-active" : "";
      const rowCount = entry.payload?.row_count ?? "-";
      const deckName = escapeHtml(entry.name);
      const deckId = escapeHtml(entry.id);
      const glyph = escapeHtml(deckGlyph(entry.name, index + 1));
      return `
        <article class="deck-icon-item ${activeClass}" data-entity-id="${deckId}">
          <button type="button" class="deck-icon-open" data-action="select" aria-label="Ouvrir ${deckName}" title="Ouvrir ${deckName}">
            <span class="deck-icon-glyph">${glyph}</span>
          </button>
          <button type="button" class="deck-icon-delete" data-action="delete" aria-label="Supprimer ${deckName}" title="Supprimer ${deckName}">
            <svg viewBox="0 0 24 24" class="deck-icon-delete-svg" aria-hidden="true">
              <path d="M6 7h12"></path>
              <path d="M9 7V5h6v2"></path>
              <path d="M8 7l1 12h6l1-12"></path>
            </svg>
          </button>
          <p class="deck-icon-name">${deckName}</p>
          <p class="deck-icon-meta">${escapeHtml(String(rowCount))} lignes</p>
        </article>
      `;
    }).join("");
  }

  function deckGlyph(name, fallbackIndex) {
    const raw = String(name || "").trim();
    if (!raw) {
      return String(fallbackIndex || "?");
    }
    const cleaned = raw.replace(/[^A-Za-z0-9]+/g, "");
    if (!cleaned) {
      return String(fallbackIndex || "?");
    }
    return cleaned.slice(0, 2).toUpperCase();
  }

  function renderActiveTabTable() {
    if (state.activeTab === "collections") {
      if (!state.selectedCollectionId) {
        renderCollection({
          ok: false,
          table: "Collections",
          error: "Aucun dossier selectionne."
        });
        return;
      }

      const meta = state.collections.find((entry) => entry.id === state.selectedCollectionId);
      const payload = state.collectionPayloadById[state.selectedCollectionId];
      if (!payload) {
        renderCollection({
          ok: false,
          table: meta?.name || "Collections",
          error: "Chargement du dossier en cours..."
        });
        return;
      }

      renderCollection(payloadForNamedView(payload, meta?.name || "Collection", "collection/store", "cards"));
      return;
    }

    if (state.activeTab === "decks") {
      const selected = state.decks.find((entry) => entry.id === state.selectedDeckId);
      if (!selected) {
        renderCollection({
          ok: false,
          table: "Decks",
          error: "Aucun deck selectionne."
        });
        return;
      }
      renderCollection(payloadForNamedView(selected.payload, selected.name, "deck/local", "cards"));
      return;
    }

    if (state.activeTab === "strategy") {
      renderCollection({
        ok: false,
        table: "Strategy",
        error: "Module Strategy en construction."
      });
      return;
    }

    renderCollection({
      ok: false,
      table: "Collections",
      error: "Selectionne un onglet disponible."
    });
  }

  function attachCollectionListEvents() {
    nodes.collections.list.addEventListener("click", async (event) => {
      const button = event.target.closest("button[data-action]");
      const item = event.target.closest(".entity-item");
      if (!item) {
        return;
      }

      const id = item.getAttribute("data-entity-id");
      if (!id) {
        return;
      }

      const action = button?.dataset.action || "select";

      if (action === "select") {
        state.selectedCollectionId = id;
        renderCollectionsList("");
        renderActiveTabTable();
        if (!state.collectionPayloadById[id]) {
          await loadStoredCollectionIntoTable(id);
        }
        return;
      }

      if (action === "delete") {
        const out = await deleteStoredCollection(id);
        if (!out || out.ok !== true) {
          renderCollection({
            ok: false,
            table: "Collections",
            error: out?.error || "Suppression impossible"
          });
          return;
        }

        delete state.collectionPayloadById[id];
        await refreshCollectionsListFromApi();
        renderActiveTabTable();
        if (state.selectedCollectionId && !state.collectionPayloadById[state.selectedCollectionId]) {
          await loadStoredCollectionIntoTable(state.selectedCollectionId);
        }
      }
    });
  }

  function attachDeckListEvents() {
    nodes.decks.list.addEventListener("click", (event) => {
      const button = event.target.closest("button[data-action]");
      const item = event.target.closest("[data-entity-id]");
      if (!item) {
        return;
      }

      const id = item.getAttribute("data-entity-id");
      if (!id) {
        return;
      }

      const action = button?.dataset.action || "select";

      if (action === "select") {
        state.selectedDeckId = id;
        renderDecksList();
        renderActiveTabTable();
        return;
      }

      if (action === "delete") {
        state.decks = state.decks.filter((entry) => entry.id !== id);
        if (state.selectedDeckId === id) {
          state.selectedDeckId = state.decks[0]?.id || null;
        }
        renderDecksList();
        renderActiveTabTable();
      }
    });
  }

  function uniqueId(prefix) {
    return `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  }

  function escapeHtml(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;");
  }

  async function init() {
    const initialLanguage = getCollectionLanguage();
    applyLanguageButtonState(initialLanguage);

    if (nodes.langEnButton && nodes.langFrButton) {
      nodes.langEnButton.addEventListener("click", () => onLanguageSelect("en"));
      nodes.langFrButton.addEventListener("click", () => onLanguageSelect("fr"));
    }

    nodes.tabButtons.forEach((button) => {
      button.addEventListener("click", () => selectTab(button.dataset.tab || "collections"));
    });

    bindCollectionPicker();
    bindDeckPicker();

    nodes.collections.form.addEventListener("submit", async (event) => {
      event.preventDefault();

      const selected = nodes.collections.fileInput.files && nodes.collections.fileInput.files[0];
      if (!selected) {
        renderCollection({
          ok: false,
          table: "Collections",
          error: "Selectionne un csv."
        });
        return;
      }

      const payload = await importCollectionCsv(
        selected,
        nodes.collections.nameInput.value.trim(),
        "auto"
      );

      if (!payload || payload.ok !== true) {
        renderCollection({
          ok: false,
          table: "Collections",
          error: payload?.error || "Import impossible"
        });
        return;
      }

      await refreshCollectionsListFromApi();
      const newId = payload.collection?.id || state.collections[0]?.id || null;
      if (newId) {
        state.selectedCollectionId = newId;
      }
      nodes.collections.nameInput.value = "";
      nodes.collections.fileInput.value = "";
      setCollectionPickButtonLabel("Choisir CSV");
      nodes.collections.pickFileButton.classList.remove("has-file");
      renderCollectionsList("");
      renderActiveTabTable();
      if (state.selectedCollectionId) {
        await loadStoredCollectionIntoTable(state.selectedCollectionId);
      }
    });

    nodes.decks.form.addEventListener("submit", async (event) => {
      event.preventDefault();
      const selected = nodes.decks.fileInput.files && nodes.decks.fileInput.files[0];
      if (!selected) {
        renderCollection({
          ok: false,
          table: "Decks",
          error: "Selectionne un fichier."
        });
        return;
      }

      const sourceType = inferDeckSourceType(selected.name);
      const payload = await uploadCollection(selected, sourceType, "");
      if (!payload || payload.ok !== true) {
        if (state.activeTab === "decks") {
          renderCollection(payload || {
            ok: false,
            error: "Impossible de charger le deck."
          });
        }
        return;
      }
      const rawName = nodes.decks.nameInput.value.trim();
      const deckName = rawName || `Deck ${state.decks.length + 1}`;
      const entry = {
        id: uniqueId("deck"),
        name: deckName,
        payload
      };
      state.decks.unshift(entry);
      state.selectedDeckId = entry.id;
      renderDecksList();
      nodes.decks.nameInput.value = "";
      nodes.decks.fileInput.value = "";
      setDeckPickButtonLabel("Choisir un fichier deck");
      nodes.decks.pickFileButton.classList.remove("has-file");
      if (state.activeTab === "decks") {
        renderActiveTabTable();
      }
    });

    attachCollectionListEvents();
    attachDeckListEvents();

    await refreshCollectionsListFromApi();
    if (state.selectedCollectionId) {
      await loadStoredCollectionIntoTable(state.selectedCollectionId);
    }
    renderDecksList();
    renderActiveTabTable();
  }

  init().catch((error) => {
    renderCollection({
      ok: false,
      error: String(error)
    });
  });
})();
