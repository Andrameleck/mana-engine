// Generator tab: form + result rendering.
// This module is self-contained and registers its own DOM hooks once the
// document is ready. It piggy-backs on the existing tab-switching logic in
// main.js: main.js toggles the `.tab-view#tab-generator` `is-active` class
// based on `data-tab="generator"` clicks, so we only need to populate the
// section and respond to the "Générer" button.

import { fetchSynergyDeckGenerate, listStoredCollections } from "./api.js";
import { getCollectionLanguage } from "./ui.js";

// Minimal translation helper for this module
const GEN_TEXT = {
  en: {
    role_land: "Lands",
    role_ramp: "Ramp",
    role_card_draw: "Card draw",
    role_removal: "Removal",
    role_threat: "Threats",
    role_core: "Synergy core",
    role_filler: "Other",
    no_collection: "No collection loaded",
    import_hint: "Import a collection in the Collections tab.",
    cards_count: "cards",
    copied: "Copied \u2713",
    copy: "Copy",
    error: "Error"
  },
  fr: {
    role_land: "Terrains",
    role_ramp: "Ramp",
    role_card_draw: "Pioche",
    role_removal: "R\u00e9ponses",
    role_threat: "Menaces",
    role_core: "C\u0153ur synergique",
    role_filler: "Divers",
    no_collection: "Aucune collection charg\u00e9e",
    import_hint: "Importez une collection dans l'onglet Collections.",
    cards_count: "cartes",
    copied: "Copi\u00e9 \u2713",
    copy: "Copier",
    error: "Erreur"
  }
};

function tGen(key) {
  const lang = getCollectionLanguage() === "fr" ? "fr" : "en";
  return GEN_TEXT[lang]?.[key] ?? GEN_TEXT.en?.[key] ?? key;
}

const ROLE_ORDER = ["land", "ramp", "card_draw", "removal", "threat", "core", "filler"];

const CURVE_BUCKETS = ["0-1", "2", "3", "4", "5", "6+"];

const state = {
  archetypeCatalog: [],
  archetypeCatalogLoaded: false,
  selectedArchetypes: new Set(),
  collections: [],
  collectionsLoaded: false,
  busy: false,
  lastPayload: null,
  lastResult: null
};

function $(id) {
  return document.getElementById(id);
}

function setText(node, text) {
  if (node) node.textContent = text == null ? "" : String(text);
}

function selectedColors() {
  const out = [];
  document.querySelectorAll("[data-deck-gen-color]").forEach((cb) => {
    if (cb.checked) out.push(cb.dataset.deckGenColor);
  });
  return out;
}

function selectedArchetypes() {
  return Array.from(state.selectedArchetypes);
}

async function ensureArchetypeCatalog() {
  if (state.archetypeCatalogLoaded) return;
  try {
    const res = await fetch("/archetypes", { headers: { Accept: "application/json" } });
    if (res.ok) {
      const data = await res.json();
      const list = Array.isArray(data?.archetypes) ? data.archetypes : [];
      state.archetypeCatalog = list
        .map((entry) => ({
          key: String(entry?.key || "").trim(),
          label: String(entry?.label || entry?.key || "").trim(),
          description: String(entry?.description || "")
        }))
        .filter((e) => e.key.length > 0);
    }
  } catch (err) {
    // Silent: chips just stay empty.
  }
  state.archetypeCatalogLoaded = true;
  renderArchetypeChips();
}

async function ensureCollections() {
  if (state.collectionsLoaded) return;
  const sel = $("deck-gen-collection-select");
  const status = $("deck-gen-collection-status");
  try {
    const data = await listStoredCollections();
    state.collections = Array.isArray(data?.collections) ? data.collections : [];
  } catch (err) {
    state.collections = [];
  }
  state.collectionsLoaded = true;
  if (sel) {
    sel.innerHTML = "";
    if (state.collections.length === 0) {
      const opt = document.createElement("option");
      opt.value = "";
      opt.textContent = tGen("no_collection");
      sel.appendChild(opt);
      if (status) status.textContent = tGen("import_hint");
    } else {
      state.collections.forEach((c) => {
        const opt = document.createElement("option");
        opt.value = c.id || "";
        opt.textContent = `${c.name || c.id} (${c.row_count ?? "?"} ${tGen("cards_count")})`;
        sel.appendChild(opt);
      });
      if (status) status.textContent = "";
    }
  }
}

function renderArchetypeChips() {
  const container = $("deck-gen-archetype-chips");
  if (!container) return;
  container.innerHTML = "";
  state.archetypeCatalog.forEach((entry) => {
    const chip = document.createElement("button");
    chip.type = "button";
    chip.className = "deck-gen-archetype-chip";
    chip.dataset.archetypeKey = entry.key;
    chip.title = entry.description || entry.label;
    chip.textContent = entry.label;
    if (state.selectedArchetypes.has(entry.key)) chip.classList.add("is-selected");
    chip.addEventListener("click", () => {
      if (state.selectedArchetypes.has(entry.key)) {
        state.selectedArchetypes.delete(entry.key);
      } else {
        state.selectedArchetypes.add(entry.key);
      }
      renderArchetypeChips();
    });
    container.appendChild(chip);
  });
}

function setBusy(flag, message) {
  state.busy = !!flag;
  const btn = $("deck-gen-run-btn");
  if (btn) btn.disabled = !!flag;
  const status = $("deck-gen-status");
  if (status && message != null) setText(status, message);
}

function manaCostHtml(mana_cost) {
  if (!mana_cost || typeof mana_cost !== "string") return "";
  const symbols = mana_cost.match(/\{[^}]+\}/g) || [];
  return symbols
    .map((sym) => {
      const inner = sym.slice(1, -1).replace(/\//g, "");
      return `<img class="deck-gen-mana-symbol" src="https://svgs.scryfall.io/card-symbols/${inner}.svg" alt="${sym}" loading="lazy">`;
    })
    .join("");
}

function escapeHtml(str) {
  return String(str == null ? "" : str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function scryfallImageUrl(scryfallId) {
  if (!scryfallId) return "";
  const id = String(scryfallId);
  if (id.length < 2) return "";
  return `https://cards.scryfall.io/normal/front/${id[0]}/${id[1]}/${id}.jpg`;
}

function renderRoleSection(role, cards) {
  const items = cards
    .map((c) => {
      const cost = manaCostHtml(c.mana_cost);
      const filler = c.is_basic_filler ? '<span class="deck-gen-card-filler">basic</span>' : "";
      const coreBadge = c.is_core ? '<span class="deck-gen-card-core" title="Carte cœur du plan de jeu">★</span>' : "";
      const score = (typeof c.score === "number" && c.score > 0)
        ? `<span class="deck-gen-card-score">${Math.round(c.score)}</span>`
        : "";
      const rowCls = c.is_core ? "deck-gen-card-row is-core" : "deck-gen-card-row";
      return `<li class="${rowCls}">
        ${coreBadge}
        <span class="deck-gen-card-name">${escapeHtml(c.name || "")}</span>
        <span class="deck-gen-card-cost">${cost}</span>
        ${filler}
        ${score}
      </li>`;
    })
    .join("");
  return `<section class="deck-gen-section">
    <header class="deck-gen-section-head">
      <span class="deck-gen-section-title">${escapeHtml(tGen("role_" + role) || role)}</span>
      <span class="deck-gen-section-count">${cards.length}</span>
    </header>
    <ul class="deck-gen-card-list">${items}</ul>
  </section>`;
}

function renderCurveBars(curve_counts, curve_target) {
  const max = Math.max(
    ...CURVE_BUCKETS.map((b) => Math.max(curve_counts?.[b] || 0, curve_target?.[b] || 0)),
    1
  );
  const bars = CURVE_BUCKETS.map((b) => {
    const actual = curve_counts?.[b] || 0;
    const target = curve_target?.[b] || 0;
    const heightPct = Math.round((actual / max) * 100);
    const targetPct = Math.round((target / max) * 100);
    return `<div class="deck-gen-curve-col" title="${b}: ${actual} (cible ${target})">
      <div class="deck-gen-curve-bar-wrap">
        <span class="deck-gen-curve-target" style="bottom:${targetPct}%"></span>
        <span class="deck-gen-curve-bar" style="height:${heightPct}%"></span>
      </div>
      <span class="deck-gen-curve-label">${b}</span>
      <span class="deck-gen-curve-value">${actual}</span>
    </div>`;
  }).join("");
  return `<div class="deck-gen-curve">${bars}</div>`;
}

function renderRoleCounts(role_counts, role_target) {
  const rows = ROLE_ORDER.filter((r) => (role_target?.[r] != null) || (role_counts?.[r] || 0) > 0)
    .map((r) => {
      const actual = role_counts?.[r] || 0;
      const target = role_target?.[r];
      const off = (target != null) && (actual !== target);
      const cls = off ? "deck-gen-role-row deck-gen-role-row--off" : "deck-gen-role-row";
      const tgt = (target != null) ? `<span class="deck-gen-role-target">/ ${target}</span>` : "";
      return `<li class="${cls}">
        <span class="deck-gen-role-label">${escapeHtml(tGen("role_" + r) || r)}</span>
        <span class="deck-gen-role-actual">${actual}</span>
        ${tgt}
      </li>`;
    }).join("");
  return `<ul class="deck-gen-role-list">${rows}</ul>`;
}

function renderModifiers(modifiers) {
  if (!modifiers || typeof modifiers !== "object") return "";
  const items = Object.entries(modifiers).map(([key, val]) => {
    const amount = Number(val?.amount || 0);
    const sign = amount > 0 ? "+" : "";
    const cls = amount >= 0 ? "deck-gen-mod-pos" : "deck-gen-mod-neg";
    return `<li class="${cls}"><span>${escapeHtml(key)}</span><span>${sign}${amount}</span></li>`;
  }).join("");
  return `<ul class="deck-gen-mod-list">${items}</ul>`;
}

function renderCombos(combos) {
  if (!Array.isArray(combos) || combos.length === 0) {
    return `<p class="muted deck-gen-empty-combos">Aucune combo Spellbook détectée.</p>`;
  }
  const items = combos.map((c) => {
    const title = c.title || `Combo ${c.id || ""}`;
    const produces = c.produces ? ` — ${escapeHtml(c.produces)}` : "";
    const cards = (c.cards || []).map(escapeHtml).join(", ");
    return `<li class="deck-gen-combo">
      <strong>${escapeHtml(title)}</strong>${produces}
      <p class="muted">${cards}</p>
    </li>`;
  }).join("");
  return `<ul class="deck-gen-combo-list">${items}</ul>`;
}

function renderMatchupSignals(signals) {
  if (!Array.isArray(signals) || signals.length === 0) return "";
  const parts = signals
    .filter((s) => s && s.tool)
    .map((s) => {
      const delta = Number(s.delta || 0);
      const sign = delta > 0 ? "+" : "";
      return `${escapeHtml(s.tool)} ×${s.count || 0} (${sign}${delta})`;
    });
  if (parts.length === 0) return "";
  return `<span class="deck-gen-matchup-signals">${parts.join(" · ")}</span>`;
}

function renderMatchupList(items, kind) {
  if (!Array.isArray(items) || items.length === 0) {
    const msg = kind === "strong"
      ? "Pas de matchup nettement favorable détecté."
      : "Pas de matchup nettement défavorable détecté.";
    return `<p class="muted deck-gen-matchup-empty">${msg}</p>`;
  }
  const lis = items.map((m) => {
    const score = Number(m.score || 0);
    const sign = score > 0 ? "+" : "";
    return `<li class="deck-gen-matchup-item is-${kind}">
      <span class="deck-gen-matchup-score">${sign}${score}</span>
      <span class="deck-gen-matchup-label">${escapeHtml(m.label || m.archetype || "")}</span>
      ${renderMatchupSignals(m.signals)}
    </li>`;
  }).join("");
  return `<ul class="deck-gen-matchup-list">${lis}</ul>`;
}

function renderMatchups(matchups) {
  if (!matchups || typeof matchups !== "object") return "";
  const selfLabels = Array.isArray(matchups.self_archetype_labels)
    ? matchups.self_archetype_labels
    : [];
  const selfChips = selfLabels.length
    ? `<p class="deck-gen-matchup-self">Plan détecté : ${
        selfLabels.map((l) => `<span class="deck-gen-matchup-self-chip">${escapeHtml(l)}</span>`).join(" ")
      }</p>`
    : "";
  return `<div class="deck-gen-matchups-block">
    <h5>Matchups</h5>
    ${selfChips}
    <div class="deck-gen-matchups-grid">
      <div class="deck-gen-matchup-col">
        <h6 class="deck-gen-matchup-strong">Fort contre</h6>
        ${renderMatchupList(matchups.strong_against, "strong")}
      </div>
      <div class="deck-gen-matchup-col">
        <h6 class="deck-gen-matchup-weak">Faible contre</h6>
        ${renderMatchupList(matchups.weak_against, "weak")}
      </div>
    </div>
  </div>`;
}

function groupByRole(mainboard) {
  const groups = {};
  ROLE_ORDER.forEach((r) => { groups[r] = []; });
  (mainboard || []).forEach((c) => {
    const role = ROLE_ORDER.includes(c.slot_role) ? c.slot_role : "core";
    groups[role].push(c);
  });
  // Sort each group by score desc, then name.
  Object.keys(groups).forEach((r) => {
    groups[r].sort((a, b) => {
      const sa = Number(a.score || 0);
      const sb = Number(b.score || 0);
      if (sb !== sa) return sb - sa;
      return String(a.name || "").localeCompare(String(b.name || ""));
    });
  });
  return groups;
}

function buildDeckText(deck, ctx, opts = {}) {
  // Plain text deck list (Arena/MTGO-friendly).
  // Format:
  //   Commander
  //   1 Aclazotz, Deepest Betrayal
  //
  //   Deck
  //   1 Sol Ring
  //   1 Swamp
  //   ...
  const requiresCommander = deck.requires_commander != null
    ? !!deck.requires_commander
    : ctx?.requires_commander !== false;
  const commander = deck.commander || ctx.commander || {};
  const lines = [];
  if (requiresCommander && commander && commander.name) {
    lines.push("Commander");
    lines.push(`1 ${commander.name}`);
    lines.push("");
  }
  // Aggregate identical names (basic lands repeat).
  const counts = new Map();
  const order = [];
  (deck.mainboard || []).forEach((c) => {
    const name = c.name || "";
    if (!name) return;
    if (!counts.has(name)) { counts.set(name, 0); order.push(name); }
    counts.set(name, counts.get(name) + 1);
  });
  lines.push("Deck");
  order.forEach((name) => {
    lines.push(`${counts.get(name)} ${name}`);
  });
  return lines.join("\n");
}

function safeFileName(str) {
  return String(str || "deck")
    .normalize("NFD").replace(/[\u0300-\u036f]/g, "")
    .replace(/[^A-Za-z0-9_-]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 80) || "deck";
}

async function copyDeckToClipboard(deck, ctx, btn) {
  const text = buildDeckText(deck, ctx);
  try {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      await navigator.clipboard.writeText(text);
    } else {
      const ta = document.createElement("textarea");
      ta.value = text;
      ta.style.position = "fixed";
      ta.style.left = "-9999px";
      document.body.appendChild(ta);
      ta.select();
      document.execCommand("copy");
      document.body.removeChild(ta);
    }
    if (btn) {
      const prev = btn.textContent;
      btn.textContent = tGen("copied");
      btn.classList.add("is-success");
      setTimeout(() => { btn.textContent = prev; btn.classList.remove("is-success"); }, 1500);
    }
  } catch (err) {
    if (btn) {
      btn.textContent = tGen("error");
      setTimeout(() => { btn.textContent = tGen("copy"); }, 1500);
    }
  }
}

function exportDeckTxt(deck, ctx) {
  const text = buildDeckText(deck, ctx);
  const commanderName = (deck.commander || ctx.commander || {}).name || "deck";
  const fname = `${safeFileName(commanderName)}_v${deck.variant || 1}.txt`;
  const blob = new Blob([text], { type: "text/plain;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = fname;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  setTimeout(() => URL.revokeObjectURL(url), 0);
}

function renderDeckCard(deck, ctx) {
  const groups = groupByRole(deck.mainboard);
  const sections = ROLE_ORDER
    .filter((r) => groups[r].length > 0)
    .map((r) => renderRoleSection(r, groups[r]))
    .join("");

  const requiresCommander = deck.requires_commander != null
    ? !!deck.requires_commander
    : ctx?.requires_commander !== false;
  const commander = deck.commander || ctx.commander || {};

  // Per-deck config badge (shown when configs differ per deck in random mode).
  const cfgParts = [];
  if (deck.variant_format_label) cfgParts.push(deck.variant_format_label);
  if (Array.isArray(deck.variant_colors) && deck.variant_colors.length > 0) {
    cfgParts.push(deck.variant_colors.join(""));
  }
  if (Array.isArray(deck.variant_archetypes) && deck.variant_archetypes.length > 0) {
    cfgParts.push(deck.variant_archetypes.join(", "));
  }
  const cfgBadge = cfgParts.length > 0
    ? `<span class="deck-gen-variant-cfg">${escapeHtml(cfgParts.join(" · "))}</span>`
    : "";

  const cmdImg = scryfallImageUrl(commander.scryfall_id);
  const cmdHtml = requiresCommander
    ? `<div class="deck-gen-commander">
        ${cmdImg ? `<img src="${cmdImg}" alt="${escapeHtml(commander.name || "")}" loading="lazy">` : ""}
        <div class="deck-gen-commander-info">
          <h4>${escapeHtml(commander.name || "")}</h4>
          <p class="muted">${escapeHtml(commander.type_line || "")}</p>
        </div>
      </div>`
    : "";

  return `<article class="deck-gen-card" data-variant="${deck.variant}">
    <header class="deck-gen-card-head">
      <div class="deck-gen-card-head-left">
        <h3>Variante ${deck.variant}</h3>
        ${cfgBadge}
      </div>
      <div class="deck-gen-card-head-right">
        <div class="deck-gen-card-actions">
          <button type="button" class="deck-gen-action-btn" data-deck-action="copy" data-variant="${deck.variant}" title="Copier la liste de cartes">Copier</button>
          <button type="button" class="deck-gen-action-btn" data-deck-action="export" data-variant="${deck.variant}" title="Exporter en .txt">Exporter</button>
        </div>
        <div class="deck-gen-score">
          <span class="deck-gen-score-value">${deck.total_score ?? deck.score ?? 0}</span>
          <span class="deck-gen-score-label">/ 100</span>
        </div>
      </div>
    </header>

    ${cmdHtml}

    <div class="deck-gen-summary">
      <div class="deck-gen-summary-block">
        <h5>Score</h5>
        <p>Base: <strong>${deck.score_base ?? 0}</strong></p>
        ${renderModifiers(deck.score_modifiers)}
      </div>
      <div class="deck-gen-summary-block">
        <h5>Rôles</h5>
        ${renderRoleCounts(deck.role_counts, deck.role_target)}
      </div>
      <div class="deck-gen-summary-block">
        <h5>Courbe</h5>
        ${renderCurveBars(deck.curve_counts, deck.curve_target)}
      </div>
    </div>

    <div class="deck-gen-combos-block">
      <h5>Combos détectées</h5>
      ${renderCombos(deck.detected_combos)}
    </div>

    ${renderMatchups(deck.matchups)}

    <div class="deck-gen-mainboard">
      ${sections}
    </div>
  </article>`;
}

function renderResults(payload) {
  const container = $("deck-gen-results");
  if (!container) return;
  if (!payload || !payload.ok) {
    const err = (payload && payload.error) || "Erreur inconnue.";
    container.innerHTML = `<div class="deck-gen-error">${escapeHtml(err)}</div>`;
    return;
  }
  const ctx = {
    requires_commander: payload.requires_commander !== false,
    commander: payload.decks?.[0]?.commander || { name: payload.commander_name }
  };
  const isCommanderFormat = ctx.requires_commander && !payload.randomized;
  const collBadge = payload.using_collection
    ? ` · <span class="deck-gen-coll-badge">📦 collection</span>`
    : "";
  const meta = `<p class="muted">
    Format: <strong>${escapeHtml(payload.format_label || payload.format)}</strong>${
      payload.randomized
        ? " · chaque deck tire ses propres couleurs &amp; archétype"
        : isCommanderFormat
          ? ` · Commandant: <strong>${escapeHtml(payload.commander_name || "—")}</strong>`
          : ` · Carte d'ancrage: <strong>${escapeHtml(payload.commander_name || "—")}</strong>`
    }${payload.candidate_count ? ` · Candidats: <strong>${payload.candidate_count}</strong>` : ""}${collBadge}
  </p>`;
  const coreNames = Array.isArray(payload.core_card_names) ? payload.core_card_names : [];
  const coreBlock = coreNames.length > 0
    ? `<section class="deck-gen-core-banner">
        <h4>Cœur de jeu détecté</h4>
        <p class="muted">Ces ${coreNames.length} cartes définissent le plan de jeu. Toutes les autres cartes du deck sont sélectionnées pour les soutenir, les amplifier ou faciliter leur exécution.</p>
        <ul class="deck-gen-core-list">
          ${coreNames.map((n) => `<li>★ ${escapeHtml(n)}</li>`).join("")}
        </ul>
      </section>`
    : "";
  const decks = (payload.decks || []).map((d) => renderDeckCard(d, ctx)).join("");
  container.innerHTML = meta + coreBlock + `<div class="deck-gen-deck-grid">${decks}</div>`;
}

async function runGenerate() {
  if (state.busy) return;
  const format = $("deck-gen-format")?.value || "commander";
  const variants = Math.max(1, Math.min(5, Number($("deck-gen-variants")?.value || 3)));
  const commander = ($("deck-gen-commander")?.value || "").trim();
  const colors = selectedColors();
  const archetypes = selectedArchetypes();
  const useCollection = $("deck-gen-use-collection")?.checked;
  const collectionId = useCollection ? ($("deck-gen-collection-select")?.value || "") : "";

  if (useCollection && !collectionId) {
    setBusy(false, "Sélectionne une collection dans la liste.");
    return;
  }

  const payload = {
    format,
    color_identity: colors,
    archetype_filter: archetypes,
    variant_count: variants
  };
  if (commander) payload.commander = commander;
  if (collectionId) payload.collection_id = collectionId;

  state.lastPayload = payload;
  setBusy(true, "Génération en cours…");
  try {
    const result = await fetchSynergyDeckGenerate(payload);
    state.lastResult = result;
    renderResults(result);
    if (result?.ok) {
      setBusy(false, `${result.deck_count || 0} variante(s) générée(s).`);
    } else {
      setBusy(false, "Échec de génération.");
    }
  } catch (err) {
    renderResults({ ok: false, error: String(err?.message || err) });
    setBusy(false, "Erreur réseau.");
  }
}

function attachHandlers() {
  const runBtn = $("deck-gen-run-btn");
  if (runBtn) runBtn.addEventListener("click", runGenerate);
  const clearBtn = $("deck-gen-archetype-none");
  if (clearBtn) clearBtn.addEventListener("click", () => {
    state.selectedArchetypes.clear();
    renderArchetypeChips();
  });
  // Lazy-load archetype catalog when the tab is first activated.
  document.querySelectorAll('.side-tab[data-tab="generator"]').forEach((btn) => {
    btn.addEventListener("click", () => { ensureArchetypeCatalog(); }, { once: false });
  });
  // Collection toggle: show/hide picker + lazy-load collection list.
  const useCollCb = $("deck-gen-use-collection");
  const collPicker = $("deck-gen-collection-picker");
  if (useCollCb && collPicker) {
    useCollCb.addEventListener("change", () => {
      if (useCollCb.checked) {
        collPicker.classList.remove("is-hidden");
        state.collectionsLoaded = false;
        ensureCollections();
      } else {
        collPicker.classList.add("is-hidden");
      }
    });
  }
  // Delegated handler for per-deck Copy / Export buttons.
  const results = $("deck-gen-results");
  if (results) {
    results.addEventListener("click", (ev) => {
      const btn = ev.target.closest("[data-deck-action]");
      if (!btn) return;
      const variantId = Number(btn.dataset.variant);
      const decks = state.lastResult?.decks || [];
      const deck = decks.find((d) => Number(d.variant) === variantId);
      if (!deck) return;
      const ctx = {
        requires_commander: state.lastResult?.requires_commander !== false,
        commander: decks[0]?.commander || { name: state.lastResult?.commander_name }
      };
      const action = btn.dataset.deckAction;
      if (action === "copy") {
        copyDeckToClipboard(deck, ctx, btn);
      } else if (action === "export") {
        exportDeckTxt(deck, ctx);
      }
    });
  }
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", attachHandlers);
} else {
  attachHandlers();
}
