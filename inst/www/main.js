(function bootstrap() {
  const typeInput = document.getElementById("source-type");
  const fileInput = document.getElementById("source-file");
  const fileNameInput = document.getElementById("source-file-name");
  const tableInput = document.getElementById("source-table");
  const form = document.getElementById("load-form");
  const pickFileButton = document.getElementById("pick-file");

  function syncSelectedFile() {
    const selected = fileInput.files && fileInput.files[0];
    fileNameInput.value = selected ? selected.name : "";
  }

  function syncFormState() {
    const isDb = typeInput.value === "db";
    tableInput.disabled = !isDb;
    tableInput.placeholder = isDb ? "cards (optionnel)" : "Non utilise pour ce type";
    fileInput.accept = isDb ? ".db,.sqlite,.sqlite3" : (typeInput.value === "csv" ? ".csv" : ".txt,.text,.tsv");

    if (!isDb) {
      tableInput.value = "";
    }
  }

  async function runLoad() {
    const sourceType = typeInput.value;
    const sourceTable = tableInput.value.trim();
    const selected = fileInput.files && fileInput.files[0];

    if (!selected) {
      renderCollection({
        ok: false,
        error: "Selectionne un fichier."
      });
      return;
    }

    const payload = await uploadCollection(selected, sourceType, sourceTable);

    renderCollection(payload);
  }

  async function init() {
    syncFormState();
    syncSelectedFile();
    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      await runLoad();
    });
    pickFileButton.addEventListener("click", () => {
      fileInput.click();
    });
    fileInput.addEventListener("change", syncSelectedFile);
    typeInput.addEventListener("change", syncFormState);
  }

  init().catch((error) => {
    renderCollection({
      ok: false,
      error: String(error)
    });
  });
})();
