/**
 * filter_sidebar.js — single source of truth for collapsible filter sidebars.
 *
 * All three tabs (Synergy Lab, Deck Lab, Card Explorer) call
 * mountFilterSidebar() with their own sections config.  The widget creates
 * the filter-group / filter-summary / filter-body shells; each section
 * provides a build() callback that populates the body element.
 */

const MANA_URL = (c) => `https://svgs.scryfall.io/card-symbols/${c}.svg`;
const MANA_COLORS = ["W", "U", "B", "R", "G", "C"];

/**
 * Builds a WUBRG+C row of checkbox mana toggles (Synergy Lab / Deck Lab style).
 *
 * @param {{ wrapClass: string, rowClass: string, toggleClass: string,
 *           iconClass?: string, dataAttr: string }} opts
 * @returns {HTMLElement}
 */
export function buildManaToggleRow({ wrapClass, rowClass, toggleClass, iconClass = "", dataAttr }) {
  const wrap = document.createElement("label");
  wrap.className = wrapClass;
  const row = document.createElement("span");
  row.className = rowClass;
  for (const c of MANA_COLORS) {
    const lbl = document.createElement("label");
    lbl.className = toggleClass;
    const inp = document.createElement("input");
    inp.type = "checkbox";
    inp.dataset[dataAttr] = c;
    const img = document.createElement("img");
    if (iconClass) img.className = iconClass;
    img.src = MANA_URL(c);
    img.alt = c;
    img.loading = "lazy";
    lbl.append(inp, img);
    row.append(lbl);
  }
  wrap.append(row);
  return wrap;
}

/**
 * Builds a WUBRG+C row of aria-pressed button color pickers (Card Explorer style).
 *
 * @returns {HTMLElement}
 */
export function buildColorButtonRow() {
  const NAMES = { W: "White", U: "Blue", B: "Black", R: "Red", G: "Green", C: "Colorless" };
  const row = document.createElement("div");
  row.className = "cf-color-row";
  row.id = "cf-colors";
  row.setAttribute("role", "group");
  row.setAttribute("aria-label", "Color identity filter");
  for (const c of MANA_COLORS) {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "cf-color-btn";
    btn.dataset.color = c;
    btn.setAttribute("aria-pressed", "false");
    btn.title = NAMES[c];
    const img = document.createElement("img");
    img.src = MANA_URL(c);
    img.alt = c;
    img.loading = "lazy";
    btn.append(img);
    row.append(btn);
  }
  return row;
}

/**
 * Mounts filter-group sections inside containerEl (the inner panel element).
 *
 * containerEl is the visual-box element for each tab:
 *   Synergy Lab  → div#strategy-sidebar-inner (.lab-sidebar-inner)
 *   Deck Lab     → section#deck-gen-sidebar-inner (.generator-wizard)
 *   Card Explorer→ form#card-finder-form (.card-finder-form)
 *
 * @param {HTMLElement} containerEl
 * @param {Array<{
 *   label: string,
 *   i18n?: string,
 *   open?: boolean,
 *   row?: boolean,
 *   build: (bodyEl: HTMLElement) => void
 * }>} sections
 * @param {HTMLElement|null} [ctaEl] - Optional CTA button; wrapped in div.wizard-cta.
 */
export function mountFilterSidebar(containerEl, sections, ctaEl = null) {
  containerEl.innerHTML = "";
  for (const sec of sections) {
    const details = document.createElement("details");
    details.className = "filter-group";
    if (sec.open) details.open = true;

    const summary = document.createElement("summary");
    summary.className = "filter-summary";
    if (sec.i18n) summary.dataset.i18n = sec.i18n;
    summary.textContent = sec.label;

    const body = document.createElement("div");
    body.className = sec.row ? "filter-body filter-body--row" : "filter-body";
    sec.build(body);

    details.append(summary, body);
    containerEl.append(details);
  }

  if (ctaEl) {
    const wrap = document.createElement("div");
    wrap.className = "wizard-cta";
    wrap.append(ctaEl);
    containerEl.append(wrap);
  }
}
