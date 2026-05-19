/**
 * Shared card-preview helpers used by Synergy Lab, Card Explorer,
 * Collection panel, and Deck inline preview.
 *
 * The static HTML shells for A1 (Synergy Lab) and A2 (Card Explorer)
 * already exist in index.html with the shared `.strategy-result-preview`
 * structure.  The helpers here are used by their JS update functions to
 * avoid copy-pasting the image-update and meta-DL logic.
 *
 * `buildCardPreviewShell` is for programmatically injected panels (A3/A4)
 * that live inside dynamically created tab content.
 */

/**
 * Set (or clear) a card preview image with a consistent error fallback.
 *
 * @param {HTMLImageElement} imageEl
 * @param {string|null}      url      full image URL, or falsy to hide
 * @param {string}           [alt=""] alt text
 */
export function applyPreviewImage(imageEl, url, alt = "") {
  imageEl.onerror = function () {
    this.onerror = null;
    this.removeAttribute("src");
    this.classList.add("is-hidden");
  };
  if (url) {
    imageEl.src = url;
    if (alt) imageEl.alt = alt;
    imageEl.classList.remove("is-hidden");
  } else {
    imageEl.removeAttribute("src");
    imageEl.classList.add("is-hidden");
  }
}

/**
 * Fill a `<dl class="card-preview-meta">` with key/value rows.
 * Falsy values are skipped.
 *
 * @param {HTMLElement} dlEl
 * @param {Array<[string, string]>} entries  [[key, value], …]
 * @param {object} [opts]
 * @param {Function} [opts.labelFn]  (key) => display label string
 * @param {Function} [opts.manaFn]   (value) => HTML string for mana keys
 */
export function renderPreviewMetaDl(dlEl, entries, { labelFn = (k) => k, manaFn = null } = {}) {
  dlEl.innerHTML = "";
  for (const [key, value] of entries) {
    if (!String(value ?? "").trim()) continue;
    const dt = document.createElement("dt");
    dt.textContent = labelFn(key);
    const dd = document.createElement("dd");
    if (key === "mana" && manaFn) {
      dd.innerHTML = manaFn(value);
    } else {
      dd.textContent = String(value);
    }
    dlEl.append(dt, dd);
  }
}

/**
 * Build the DOM shell for a card-preview panel (A3/A4 "Collection / Deck"
 * style: opaque panel with optional close button).
 *
 * Produces:
 *   <aside id="{rootId}" class="card-preview {extraClass}" aria-live="polite">
 *     <div class="card-preview-head">
 *       <strong id="{rootId}-title">…</strong>
 *       [<button id="{rootId}-close" …>x</button>]
 *     </div>
 *     <div class="card-preview-body">
 *       <img  id="{rootId}-image" …>
 *       <p    id="{rootId}-text"  class="muted"></p>
 *       <dl   id="{rootId}-meta"  class="card-preview-meta"></dl>
 *     </div>
 *   </aside>
 *
 * @param {string} rootId
 * @param {object} [opts]
 * @param {boolean} [opts.hasClose=false]
 * @param {string}  [opts.extraClass=""]
 * @returns {HTMLElement} the aside element
 */
export function buildCardPreviewShell(rootId, { hasClose = false, extraClass = "" } = {}) {
  const aside = document.createElement("aside");
  aside.id = rootId;
  aside.className = ["card-preview", extraClass].filter(Boolean).join(" ");
  aside.setAttribute("aria-live", "polite");

  // Head
  const head = document.createElement("div");
  head.className = "card-preview-head";

  const title = document.createElement("strong");
  title.id = `${rootId}-title`;
  head.appendChild(title);

  if (hasClose) {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.id = `${rootId}-close`;
    btn.className = "card-preview-close";
    btn.setAttribute("aria-label", "Close panel");
    btn.textContent = "x";
    head.appendChild(btn);
  }

  // Body
  const body = document.createElement("div");
  body.className = "card-preview-body";

  const img = document.createElement("img");
  img.id = `${rootId}-image`;
  img.alt = "Card preview";
  img.loading = "lazy";

  const text = document.createElement("p");
  text.id = `${rootId}-text`;
  text.className = "muted";

  const meta = document.createElement("dl");
  meta.id = `${rootId}-meta`;
  meta.className = "card-preview-meta";

  body.append(img, text, meta);
  aside.append(head, body);
  return aside;
}
