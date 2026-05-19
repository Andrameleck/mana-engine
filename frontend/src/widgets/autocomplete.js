/**
 * Datalist-backed autocomplete widget.
 *
 * Attaches an `input` listener to `inputEl` that fills `listEl` (<datalist>)
 * with suggestions.  Supports:
 *  - debouncing (configurable ms, default 250)
 *  - stale-request cancellation via an internal token counter
 *  - internal LRU-style Map cache per widget instance
 *  - optional local base-names merged with remote names
 *
 * Usage — Card Explorer:
 *   attachDatalistAutocomplete(cfQInput, cfQList, {
 *     fetchNames: (q) => fetchScryfallAutocompleteNames(q),
 *     debounceMs: 250
 *   });
 *
 * Usage — Synergy Lab (instant + merge local collection):
 *   attachDatalistAutocomplete(seedInput, seedList, {
 *     fetchNames: (q) => fetchScryfallAutocompleteNames(q),
 *     debounceMs: 0,
 *     getBaseNames: () => getStrategyBaseSeedCards().map(c => c.name),
 *     normalize: normalizeStrategyName,
 *     maxResults: 320
 *   });
 */

function _escapeHtml(s) {
  return String(s || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/**
 * @param {HTMLInputElement}    inputEl
 * @param {HTMLDataListElement} listEl
 * @param {object}  opts
 * @param {Function} [opts.fetchNames]   async (query: string) => string[]
 * @param {number}   [opts.debounceMs=250]
 * @param {number}   [opts.minLength=2]
 * @param {Function} [opts.getBaseNames] () => string[]  — local names merged first
 * @param {Function} [opts.normalize]    (s: string) => string  — for dedup & filter
 * @param {number}   [opts.maxResults=320]
 */
export function attachDatalistAutocomplete(inputEl, listEl, opts = {}) {
  const {
    fetchNames   = null,
    debounceMs   = 250,
    minLength    = 2,
    getBaseNames = null,
    normalize    = (s) => String(s || "").toLowerCase().trim(),
    maxResults   = 320,
  } = opts;

  const cache = new Map();
  let timer = null;
  let token = 0;

  function fillList(baseNames, remoteNames, query) {
    const norm = normalize(query);
    const seen = new Set();
    const result = [];

    for (const name of (baseNames || [])) {
      const k = normalize(name);
      if (!k) continue;
      if (norm && !k.includes(norm)) continue;
      if (seen.has(k)) continue;
      seen.add(k);
      result.push(name);
    }

    for (const name of (remoteNames || [])) {
      const k = normalize(name);
      if (!k || seen.has(k)) continue;
      seen.add(k);
      result.push(name);
    }

    listEl.innerHTML = result
      .slice(0, maxResults)
      .map((n) => `<option value="${_escapeHtml(n)}"></option>`)
      .join("");
  }

  async function update(query) {
    const myToken = ++token;
    const base = getBaseNames ? getBaseNames() : [];

    if (!fetchNames || query.length < minLength) {
      fillList(base, [], query);
      return;
    }

    const cacheKey = normalize(query);
    if (!cache.has(cacheKey)) {
      const names = await fetchNames(query);
      cache.set(cacheKey, Array.isArray(names) ? names : []);
    }
    if (myToken !== token) return; // stale — a newer request is in flight

    fillList(base, cache.get(cacheKey), query);
  }

  inputEl.addEventListener("input", () => {
    const val = inputEl.value.trim();
    if (val.length < minLength) {
      listEl.innerHTML = "";
      return;
    }
    if (debounceMs <= 0) {
      update(val);
    } else {
      clearTimeout(timer);
      timer = setTimeout(() => update(val), debounceMs);
    }
  });
}
