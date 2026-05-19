/**
 * Shared status-banner helpers.
 *
 * Usage:
 *   setStatus(el, "Searching…", "loading");   // removes .muted
 *   setStatus(el, "5 results",  "idle");       // adds    .muted
 *   setStatus(el, "API error",  "error");      // adds    .muted .status-banner--error
 *   setProgress(barEl, fillEl, labelEl, 42);   // shows 42 %
 *   setProgress(barEl, fillEl, labelEl, null); // hides bar
 */

/**
 * Update text and visual state of a status element.
 * @param {HTMLElement} el
 * @param {string} text
 * @param {"idle"|"loading"|"error"} [type="idle"]
 */
export function setStatus(el, text, type = "idle") {
  el.textContent = text;
  el.classList.toggle("muted", type !== "loading");
  el.classList.toggle("status-banner--loading", type === "loading");
  el.classList.toggle("status-banner--error", type === "error");
}

/**
 * Show or hide a progress bar triple (container / fill / label).
 * @param {HTMLElement} progressEl  wrapper element (controls display)
 * @param {HTMLElement} fillEl      inner fill bar
 * @param {HTMLElement} labelEl     percentage label
 * @param {number|null} pct         0-100 to show; null to hide
 */
export function setProgress(progressEl, fillEl, labelEl, pct) {
  if (pct === null || pct === undefined) {
    progressEl.style.display = "none";
    return;
  }
  progressEl.style.display = "";
  fillEl.style.width = `${pct}%`;
  labelEl.textContent = `${Math.round(pct)}%`;
}
