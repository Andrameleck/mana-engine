(function bootstrap() {
  const state = {
    selectedTable: "cards"
  };

  async function resolveCardsTableName() {
    const tables = await fetchMdbTables();
    if (tables.ok !== true || !Array.isArray(tables.data) || tables.data.length === 0) {
      return;
    }

    const names = tables.data;
    const exactCards = names.find((name) => String(name).toLowerCase() === "cards");
    if (exactCards) {
      state.selectedTable = exactCards;
      return;
    }

    const containsCard = names.find((name) => String(name).toLowerCase().includes("card"));
    if (containsCard) {
      state.selectedTable = containsCard;
      return;
    }

    state.selectedTable = names[0];
  }

  async function loadCardsTable() {
    if (!state.selectedTable) {
      renderTablePreview({
        ok: false,
        error: "Aucune table disponible."
      });
      return;
    }

    const payload = await fetchTablePreview(state.selectedTable, 1000);
    renderTablePreview(payload);
  }

  async function init() {
    await resolveCardsTableName();
    await loadCardsTable();
  }

  init().catch((error) => {
    renderTablePreview({
      ok: false,
      error: String(error)
    });
  });
})();
