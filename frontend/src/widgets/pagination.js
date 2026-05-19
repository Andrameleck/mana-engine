/**
 * Shared pagination widget.
 *
 * Renders a ← Prev | page info | Next → row into a container element.
 * The container's visibility (display none / flex) is managed by the caller.
 *
 * Usage:
 *   renderPagination(containerEl, {
 *     page: 2, totalPages: 5,
 *     infoText: "Page 2 / 5",
 *     onPrev: () => loadPage(page - 1),
 *     onNext: () => loadPage(page + 1),
 *   });
 *
 * CSS: elements carry classes `.page-btn` and `.page-info`.
 * Both the old `.cf-page-btn` / `.table-pager-actions button` selectors are
 * kept as aliases in styles.css until the visual-harmonization pass (task #10).
 */

/**
 * @param {HTMLElement} containerEl
 * @param {object} opts
 * @param {number}   opts.page        1-based current page
 * @param {number}   opts.totalPages
 * @param {string}   opts.infoText    label rendered between the buttons
 * @param {Function} opts.onPrev      called when Prev is clicked
 * @param {Function} opts.onNext      called when Next is clicked
 */
export function renderPagination(containerEl, { page, totalPages, infoText, onPrev, onNext }) {
  containerEl.innerHTML = "";
  if (!containerEl || totalPages <= 1) return;

  const prev = document.createElement("button");
  prev.type = "button";
  prev.className = "page-btn";
  prev.textContent = "← Prev";
  prev.disabled = page <= 1;
  prev.addEventListener("click", onPrev);

  const info = document.createElement("span");
  info.className = "page-info";
  info.textContent = infoText;

  const next = document.createElement("button");
  next.type = "button";
  next.className = "page-btn";
  next.textContent = "Next →";
  next.disabled = page >= totalPages;
  next.addEventListener("click", onNext);

  containerEl.append(prev, info, next);
}
