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
      platformInput: document.getElementById("collection-platform"),
      fileInput: document.getElementById("collection-source-file"),
      fileNameInput: document.getElementById("collection-source-file-name"),
      pickFileButton: document.getElementById("collection-pick-file"),
      list: document.getElementById("collections-list")
    },
    decks: {
      form: document.getElementById("deck-load-form"),
      nameInput: document.getElementById("deck-name"),
      typeInput: document.getElementById("deck-source-type"),
      fileInput: document.getElementById("deck-source-file"),
      fileNameInput: document.getElementById("deck-source-file-name"),
      tableInput: document.getElementById("deck-source-table"),
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
    if (typeof window.setCollectionLanguage === "function") {
      window.setCollectionLanguage(language);
    }
    applyLanguageButtonState(language);
    if (state.activeTab === "collections" && state.selectedCollectionId) {
      loadStoredCollectionIntoTable(state.selectedCollectionId);
    }
  }

  function bindCollectionPicker() {
    nodes.collections.fileInput.accept = ".csv,.txt";
    nodes.collections.pickFileButton.addEventListener("click", () => {
      nodes.collections.fileInput.click();
    });
    nodes.collections.fileInput.addEventListener("change", () => {
      const selected = nodes.collections.fileInput.files && nodes.collections.fileInput.files[0];
      nodes.collections.fileNameInput.value = selected ? selected.name : "";
    });
  }

  function syncDeckInputs() {
    const isDb = nodes.decks.typeInput.value === "db";
    nodes.decks.tableInput.disabled = !isDb;
    nodes.decks.tableInput.placeholder = isDb ? "cards (optional)" : "Unused for this source";
    nodes.decks.fileInput.accept = isDb ? ".db,.sqlite,.sqlite3" : (nodes.decks.typeInput.value === "csv" ? ".csv" : ".txt,.text,.tsv");
    if (!isDb) {
      nodes.decks.tableInput.value = "";
    }
  }

  function bindDeckPicker() {
    nodes.decks.pickFileButton.addEventListener("click", () => {
      nodes.decks.fileInput.click();
    });
    nodes.decks.fileInput.addEventListener("change", () => {
      const selected = nodes.decks.fileInput.files && nodes.decks.fileInput.files[0];
      nodes.decks.fileNameInput.value = selected ? selected.name : "";
    });
    nodes.decks.typeInput.addEventListener("change", syncDeckInputs);
    syncDeckInputs();
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

  function payloadForNamedView(payload, name, fallbackSummary) {
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
      path: payload.path || fallbackSummary
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
      list.innerHTML = '<p class="muted">No deck yet.</p>';
      return;
    }

    list.innerHTML = state.decks.map((entry) => {
      const activeClass = entry.id === state.selectedDeckId ? "is-active" : "";
      const rowCount = entry.payload?.row_count ?? "-";
      return `
        <article class="entity-item ${activeClass}" data-entity-id="${entry.id}">
          <div>
            <p class="entity-item-name">${escapeHtml(entry.name)}</p>
            <p class="entity-item-meta">${rowCount} rows</p>
          </div>
          <div class="entity-actions">
            <button type="button" class="entity-select" data-action="select">Open</button>
            <button type="button" class="entity-delete" data-action="delete">Delete</button>
          </div>
        </article>
      `;
    }).join("");
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

      renderCollection(payloadForNamedView(payload, meta?.name || "Collection", "collection/store"));
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
      renderCollection(payloadForNamedView(selected.payload, selected.name, "deck/local"));
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
    const initialLanguage = typeof window.getCollectionLanguage === "function"
      ? window.getCollectionLanguage()
      : "en";
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
        nodes.collections.platformInput.value
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
      nodes.collections.fileNameInput.value = "";
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

      const payload = await uploadCollection(selected, nodes.decks.typeInput.value, nodes.decks.tableInput.value.trim());
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
