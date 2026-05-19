/**
 * Shared card-tile shell builder.
 *
 * Builds the `article.collection-card > div.collection-card-art +
 * div.collection-card-meta` structure shared by the Collection grid (B1)
 * and the Card Explorer grid (B2).
 *
 * The caller is responsible for:
 *  - adding view-specific classes (e.g. `cf-card`, `data-row`)
 *  - appending extra DOM into `art` (qty badge, edit controls)
 *  - appending extra DOM into `metaDiv` (mana cost, price, color icons)
 *  - attaching event listeners
 *
 * Usage — Card Explorer:
 *   const { article, art, metaDiv } = buildCardTile({
 *     imageUrl, name: card.name, subtitle,
 *     onImageError: () => article.classList.add("is-image-missing")
 *   });
 *   article.classList.add("cf-card");
 *   article.addEventListener("click", () => renderCfViewer(card));
 *   metaDiv.appendChild(colorIconsEl);
 *
 * Usage — Collection:
 *   const { article, art, metaDiv } = buildCardTile({ imageUrl, name, subtitle });
 *   article.classList.add("data-row");
 *   bindRowPreviewEvents(article, rowData);
 *   art.appendChild(qtyBadge);
 */

function _escapeHtml(s) {
  return String(s || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/**
 * @param {object}  opts
 * @param {string}  [opts.imageUrl]      art-crop image URL (falsy = show fallback)
 * @param {string}  [opts.name]          card name (used for fallback text + img alt)
 * @param {string}  [opts.subtitle]      second line of meta text
 * @param {Function} [opts.onImageError] called when image fails to load
 * @returns {{ article: HTMLElement, art: HTMLElement, metaDiv: HTMLElement }}
 */
export function buildCardTile({ imageUrl = "", name = "", subtitle = "", onImageError = null } = {}) {
  const article = document.createElement("article");
  article.className = "collection-card";

  // Art frame
  const art = document.createElement("div");
  art.className = "collection-card-art";

  if (imageUrl) {
    const img = document.createElement("img");
    img.src = imageUrl;
    img.alt = name;
    img.loading = "lazy";
    img.decoding = "async";
    img.addEventListener("error", () => {
      art.innerHTML = `<span class="collection-card-fallback">${_escapeHtml(name)}</span>`;
      article.classList.add("is-image-missing");
      if (onImageError) onImageError();
    }, { once: true });
    art.appendChild(img);
  } else {
    art.innerHTML = `<span class="collection-card-fallback">${_escapeHtml(name)}</span>`;
    article.classList.add("is-image-missing");
  }

  // Meta frame
  const metaDiv = document.createElement("div");
  metaDiv.className = "collection-card-meta";
  metaDiv.innerHTML = `
    <p class="collection-card-name">${_escapeHtml(name)}</p>
    <p class="collection-card-line">${_escapeHtml(subtitle)}</p>
  `;

  article.append(art, metaDiv);
  return { article, art, metaDiv };
}
