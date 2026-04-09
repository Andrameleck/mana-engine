source("R/bridge_synergy.R")

records_to_df <- function(records) {
  if (length(records) == 0L) {
    return(data.frame(stringsAsFactors = FALSE))
  }

  cols <- sort(unique(unlist(lapply(records, names), use.names = FALSE)))
  rows <- lapply(records, function(r) {
    x <- setNames(vector("list", length(cols)), cols)
    for (nm in cols) {
      x[[nm]] <- if (!is.null(r[[nm]])) r[[nm]] else ""
    }
    as.data.frame(x, stringsAsFactors = FALSE, check.names = FALSE)
  })

  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

normalize_name <- function(x) {
  tolower(trimws(as.character(x)))
}

parse_colors <- function(mana_cost) {
  s <- toupper(ifelse(is.na(mana_cost), "", as.character(mana_cost)))
  hits <- regmatches(s, gregexpr("\\{[WUBRG]\\}", s, perl = TRUE))[[1]]
  if (length(hits) == 0L) {
    return(character(0))
  }
  unique(gsub("[{}]", "", hits))
}

extract_features <- function(oracle_text = "", keywords = "") {
  txt <- tolower(paste(oracle_text, keywords, sep = " "))
  count_pat <- function(pat) {
    hits <- gregexpr(pat, txt, perl = TRUE)[[1]]
    if (length(hits) == 0L || identical(hits[1], -1L)) {
      return(0)
    }
    length(hits)
  }

  f <- c(
    graveyard = count_pat("\\bgraveyard\\b|\\bmill\\b|\\bdredge\\b|descend"),
    reanimate = count_pat("return target .*graveyard.*battlefield|return .* from your graveyard to the battlefield|reanimate|\\bresurrect\\b"),
    entomb_line = count_pat("search your library .* put .* graveyard|put .* from your library .* graveyard"),
    tutor = count_pat("search your library|surveil|tutor"),
    discard = count_pat("\\bdiscard\\b|loot|connive"),
    draw = count_pat("\\bdraw\\b"),
    sac = count_pat("\\bsacrifice\\b"),
    etb = count_pat("enters the battlefield|\\betb\\b"),
    token = count_pat("\\btoken\\b|create .* token"),
    removal = count_pat("destroy target|exile target|sacrifice target"),
    combo = count_pat("whenever .* dies|dies,|from your graveyard"),
    recursion = count_pat("return .* from your graveyard to your hand|flashback|escape"),
    cheat = count_pat("without paying its mana cost|from your graveyard")
  )

  # Make core reanimator signals more discriminative.
  f["reanimate"] <- f["reanimate"] * 2
  f["entomb_line"] <- f["entomb_line"] * 2

  f[f > 0]
}

rows_to_cards <- function(df) {
  df$name <- trimws(as.character(df$name))
  df <- df[nzchar(df$name), , drop = FALSE]
  df <- df[!duplicated(normalize_name(df$name)), , drop = FALSE]

  ids <- make.unique(gsub("[^a-z0-9]+", "_", normalize_name(df$name)))
  cards <- vector("list", nrow(df))

  for (i in seq_len(nrow(df))) {
    oracle_text <- if ("oracle_text" %in% names(df)) as.character(df$oracle_text[i]) else ""
    keywords <- if ("keywords" %in% names(df)) as.character(df$keywords[i]) else ""
    mana_cost <- if ("mana_cost" %in% names(df)) as.character(df$mana_cost[i]) else ""

    cards[[i]] <- list(
      id = ids[i],
      name = as.character(df$name[i]),
      features = extract_features(oracle_text, keywords),
      constraints = list(
        colors = parse_colors(mana_cost),
        legal = TRUE,
        format = "commander"
      )
    )
  }

  cards
}

apply_idf_to_cards <- function(cards) {
  n <- length(cards)
  if (n == 0L) {
    return(cards)
  }

  all_features <- sort(unique(unlist(lapply(cards, function(card) names(card$features)), use.names = FALSE)))
  if (length(all_features) == 0L) {
    return(cards)
  }

  dfreq <- setNames(integer(length(all_features)), all_features)
  for (i in seq_len(n)) {
    f <- cards[[i]]$features
    if (length(f) == 0L) {
      next
    }
    present <- unique(names(f)[f > 0])
    if (length(present) > 0L) {
      dfreq[present] <- dfreq[present] + 1L
    }
  }

  idf <- log((n + 1) / (dfreq + 1)) + 1
  for (i in seq_len(n)) {
    f <- cards[[i]]$features
    if (length(f) == 0L) {
      next
    }
    cards[[i]]$features <- f * idf[names(f)]
  }

  cards
}

filter_cards_by_seed_colors <- function(cards, seed_name) {
  n <- length(cards)
  if (n == 0L) {
    return(cards)
  }

  card_names <- normalize_name(vapply(cards, `[[`, "", "name"))
  seed_idx <- which(card_names == normalize_name(seed_name))[1]
  if (is.na(seed_idx)) {
    return(cards)
  }

  seed_colors <- cards[[seed_idx]]$constraints$colors
  seed_colors <- unique(toupper(as.character(seed_colors)))
  seed_colors <- seed_colors[nzchar(seed_colors)]
  if (length(seed_colors) == 0L) {
    return(cards)
  }

  keep <- logical(n)
  keep[seed_idx] <- TRUE
  for (i in seq_len(n)) {
    if (i == seed_idx) {
      next
    }
    cols <- cards[[i]]$constraints$colors
    cols <- unique(toupper(as.character(cols)))
    cols <- cols[nzchar(cols)]
    keep[i] <- length(intersect(cols, seed_colors)) > 0L
  }

  cards[keep]
}

fetch_edhrec_json <- function(slug) {
  url <- sprintf("https://json.edhrec.com/pages/cards/%s.json", slug)
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("jsonlite est requis pour lire EDHREC JSON")
  }

  txt <- tryCatch(
    paste(readLines(url, warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
    error = function(e) ""
  )
  if (!nzchar(txt)) {
    return(NULL)
  }

  tryCatch(jsonlite::fromJSON(txt), error = function(e) NULL)
}

extract_edhrec_cardviews <- function(payload, tags) {
  if (is.null(payload) || is.null(payload$container) || is.null(payload$container$json_dict)) {
    return(data.frame(name = character(0), num_decks = numeric(0), synergy = numeric(0), tag = character(0), stringsAsFactors = FALSE))
  }

  cardlists <- payload$container$json_dict$cardlists
  if (is.null(cardlists) || length(cardlists) == 0L) {
    return(data.frame(name = character(0), num_decks = numeric(0), synergy = numeric(0), tag = character(0), stringsAsFactors = FALSE))
  }

  out <- list()
  idx <- 0L
  for (i in seq_len(nrow(cardlists))) {
    tag <- as.character(cardlists$tag[i])
    if (!tag %in% tags) {
      next
    }

    views <- cardlists$cardviews[[i]]
    if (is.null(views) || nrow(views) == 0L) {
      next
    }

    idx <- idx + 1L
    out[[idx]] <- data.frame(
      name = as.character(views$name),
      num_decks = as.numeric(views$num_decks),
      synergy = as.numeric(views$synergy),
      tag = tag,
      stringsAsFactors = FALSE
    )
  }

  if (idx == 0L) {
    return(data.frame(name = character(0), num_decks = numeric(0), synergy = numeric(0), tag = character(0), stringsAsFactors = FALSE))
  }

  do.call(rbind, out)
}

collect_net_staples <- function(seed_slugs, max_cards = 140L) {
  tags <- c("topcards", "highsynergycards", "highliftcards", "enchantments", "sorceries", "instants", "creatures")
  rows <- list()
  idx <- 0L

  for (slug in seed_slugs) {
    payload <- fetch_edhrec_json(slug)
    df <- extract_edhrec_cardviews(payload, tags = tags)
    if (nrow(df) == 0L) {
      next
    }
    df$seed_slug <- slug
    idx <- idx + 1L
    rows[[idx]] <- df
  }

  if (idx == 0L) {
    return(character(0))
  }

  net <- do.call(rbind, rows)
  net <- net[nzchar(net$name), , drop = FALSE]
  net$name_norm <- normalize_name(net$name)

  split_names <- split(seq_len(nrow(net)), net$name_norm)
  agg <- lapply(split_names, function(ix) {
    data.frame(
      name = net$name[ix][1],
      name_norm = net$name_norm[ix][1],
      max_num_decks = max(net$num_decks[ix], na.rm = TRUE),
      max_synergy = max(net$synergy[ix], na.rm = TRUE),
      pages_seen = length(unique(net$seed_slug[ix])),
      tags_seen = length(unique(net$tag[ix])),
      stringsAsFactors = FALSE
    )
  })
  agg_df <- do.call(rbind, agg)

  agg_df$max_num_decks[!is.finite(agg_df$max_num_decks)] <- 0
  agg_df$max_synergy[!is.finite(agg_df$max_synergy)] <- 0

  agg_df <- agg_df[
    agg_df$max_num_decks >= 12000 & agg_df$max_synergy >= 0,
    ,
    drop = FALSE
  ]

  # Favor cards present on multiple pages, then highly played, then synergy.
  ord <- order(-agg_df$pages_seen, -agg_df$max_num_decks, -agg_df$max_synergy, agg_df$name_norm)
  agg_df <- agg_df[ord, , drop = FALSE]

  if (nrow(agg_df) > max_cards) {
    agg_df <- agg_df[seq_len(max_cards), , drop = FALSE]
  }

  as.character(agg_df$name)
}

build_competitive_combo_catalog <- function() {
  list(
    list(
      combo_id = "legacy_reanimator_nalcs_2025",
      label = "Entomb + Reanimate/Animate Dead + Griselbrand/Archon",
      pieces = c("Entomb", "Reanimate", "Animate Dead", "Griselbrand", "Archon of Cruelty"),
      source = "https://mtgtop8.com/event?d=769218&e=75011&f=LE",
      source_note = "North America Legacy Champs 2025 (Adam Kulp, Reanimator)"
    ),
    list(
      combo_id = "legacy_worldgorger_azms_2025",
      label = "Entomb + Animate Dead/Dance of the Dead + Worldgorger Dragon",
      pieces = c("Entomb", "Animate Dead", "Dance of the Dead", "Worldgorger Dragon", "Reanimate"),
      source = "https://www.mtgtop8.com/event?d=707964&e=67144&f=LE&switch=visual",
      source_note = "AZMS Qualifier #3 2025 (Worldgorger Dragon Reanimator)"
    ),
    list(
      combo_id = "legacy_chain_smog_hareruya_2025",
      label = "Chain of Smog + Witherbloom Apprentice (+ Entomb/Reanimate package)",
      pieces = c("Chain of Smog", "Witherbloom Apprentice", "Entomb", "Reanimate", "Animate Dead"),
      source = "https://www.mtgtop8.com/event?e=73734",
      source_note = "The Last Sun 2025 Qualifier (Hareruya Takamatsu)"
    )
  )
}

competitive_combo_cards <- function(combo_catalog) {
  if (length(combo_catalog) == 0L) {
    return(character(0))
  }
  sort(unique(unlist(lapply(combo_catalog, function(x) as.character(x$pieces)), use.names = FALSE)))
}

evaluate_competitive_combo_detection <- function(
    combo_catalog,
    collection_names,
    seed_df,
    bridge_df,
    package_names) {
  if (length(combo_catalog) == 0L) {
    return(data.frame(stringsAsFactors = FALSE))
  }

  collection_norm <- normalize_name(collection_names)
  seed_norm <- if (is.data.frame(seed_df) && nrow(seed_df) > 0L) normalize_name(seed_df$name) else character(0)
  bridge_norm <- if (is.data.frame(bridge_df) && nrow(bridge_df) > 0L) normalize_name(bridge_df$name) else character(0)
  package_norm <- normalize_name(package_names)

  out <- vector("list", length(combo_catalog))
  for (i in seq_along(combo_catalog)) {
    combo <- combo_catalog[[i]]
    pieces <- as.character(combo$pieces)
    pieces_norm <- normalize_name(pieces)

    seed_rank <- match(pieces_norm, seed_norm)
    bridge_rank <- match(pieces_norm, bridge_norm)

    in_collection <- pieces_norm %in% collection_norm
    in_packages <- pieces_norm %in% package_norm
    in_seed_top25 <- !is.na(seed_rank) & seed_rank <= 25L
    in_seed_top60 <- !is.na(seed_rank) & seed_rank <= 60L
    in_bridge_top25 <- !is.na(bridge_rank) & bridge_rank <= 25L

    detected <- (sum(in_seed_top60) >= 2L) || (sum(in_bridge_top25) >= 2L) || (sum(in_packages) >= 2L)

    out[[i]] <- data.frame(
      combo_id = as.character(combo$combo_id),
      combo_label = as.character(combo$label),
      pieces_total = length(pieces),
      pieces_in_collection = sum(in_collection),
      pieces_seed_top25 = sum(in_seed_top25),
      pieces_seed_top60 = sum(in_seed_top60),
      pieces_bridge_top25 = sum(in_bridge_top25),
      pieces_in_packages = sum(in_packages),
      detected = detected,
      source = as.character(combo$source),
      source_note = as.character(combo$source_note),
      stringsAsFactors = FALSE
    )
  }

  do.call(rbind, out)
}

fetch_scryfall_details <- function(card_name) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    return(list(ok = FALSE))
  }

  encoded <- utils::URLencode(card_name, reserved = TRUE)
  url <- sprintf("https://api.scryfall.com/cards/named?exact=%s", encoded)

  txt <- tryCatch(
    paste(readLines(url, warn = FALSE, encoding = "UTF-8"), collapse = "\n"),
    error = function(e) ""
  )
  if (!nzchar(txt)) {
    return(list(ok = FALSE))
  }

  payload <- tryCatch(jsonlite::fromJSON(txt), error = function(e) NULL)
  if (is.null(payload) || (!is.null(payload$object) && identical(payload$object, "error"))) {
    return(list(ok = FALSE))
  }

  list(
    ok = TRUE,
    name = if (!is.null(payload$name)) as.character(payload$name) else card_name,
    mana_cost = if (!is.null(payload$mana_cost)) as.character(payload$mana_cost) else "",
    oracle_text = if (!is.null(payload$oracle_text)) as.character(payload$oracle_text) else "",
    keywords = if (!is.null(payload$keywords) && length(payload$keywords) > 0L) paste(as.character(payload$keywords), collapse = ", ") else "",
    scryfall_id = if (!is.null(payload$id)) as.character(payload$id) else ""
  )
}

build_net_rows <- function(card_names) {
  if (length(card_names) == 0L) {
    return(data.frame(stringsAsFactors = FALSE))
  }

  out <- vector("list", length(card_names))
  out_idx <- 0L

  for (i in seq_along(card_names)) {
    details <- fetch_scryfall_details(card_names[i])
    if (!isTRUE(details$ok)) {
      next
    }

    out_idx <- out_idx + 1L
    out[[out_idx]] <- data.frame(
      row_index = i,
      quantity = 1,
      name = details$name,
      set_code = "",
      collector_number = "",
      mana_cost = details$mana_cost,
      oracle_text = details$oracle_text,
      keywords = details$keywords,
      language = "en",
      finish = "",
      card_condition = "",
      scryfall_id = details$scryfall_id,
      notes = "added_from_edhrec",
      stringsAsFactors = FALSE
    )

    Sys.sleep(0.12)
  }

  if (out_idx == 0L) {
    return(data.frame(stringsAsFactors = FALSE))
  }

  do.call(rbind, out[seq_len(out_idx)])
}

run_reco <- function(cards, A_name = "entomb") {
  card_names <- vapply(cards, `[[`, "", "name")
  idx_A <- which(normalize_name(card_names) == normalize_name(A_name))[1]
  if (is.na(idx_A)) {
    stop(sprintf("Carte seed '%s' absente", A_name))
  }
  A_id <- cards[[idx_A]]$id

  target_names <- c("reanimate", "animate dead", "necromancy", "victimize", "exhume", "persist", "buried alive")
  idx_B <- match(target_names, normalize_name(card_names))
  idx_B <- idx_B[!is.na(idx_B)][1]
  if (is.na(idx_B)) {
    prop <- propagate_scores(
      seed_id = A_id,
      cards = cards,
      depth_N = 3L,
      top_k = 40L,
      gamma = 0.65,
      options = list(unique_nodes = TRUE, max_candidates = 2000L, enforce_color_identity = TRUE)
    )
    best_id <- names(prop$scores)[1]
    idx_B <- match(best_id, vapply(cards, `[[`, "", "id"))
  }

  B_id <- cards[[idx_B]]$id

  rec <- compute_bridge_recommendations(
    cards = cards,
    A_id = A_id,
    B_id = B_id,
    depth_N = 3L,
    top_k = 40L,
    gamma = 0.65,
    topN = 25L,
    topChains = 7L,
    topPackages = 5L,
    options = list(
      enforce_color_identity = TRUE,
      unique_nodes = TRUE,
      max_candidates = 3000L,
      max_chain_len = 6L,
      support_k = 2L
    )
  )

  list(rec = rec, A_name = cards[[idx_A]]$name, B_name = cards[[idx_B]]$name)
}

top_seed_recos <- function(cards, seed_name = "entomb", top_n = 25L) {
  card_names <- normalize_name(vapply(cards, `[[`, "", "name"))
  seed_idx <- which(card_names == normalize_name(seed_name))[1]
  if (is.na(seed_idx)) {
    stop(sprintf("Carte seed '%s' absente", seed_name))
  }

  seed_id <- cards[[seed_idx]]$id
  prop <- propagate_scores(
    seed_id = seed_id,
    cards = cards,
    depth_N = 3L,
    top_k = 40L,
    gamma = 0.65,
    options = list(
      enforce_color_identity = TRUE,
      unique_nodes = TRUE,
      max_candidates = 3000L
    )
  )

  id_to_name <- setNames(vapply(cards, `[[`, "", "name"), vapply(cards, `[[`, "", "id"))
  out <- data.frame(
    id = names(prop$scores),
    name = unname(id_to_name[names(prop$scores)]),
    score = as.numeric(prop$scores),
    stringsAsFactors = FALSE
  )
  if (nrow(out) > top_n) {
    out <- out[seq_len(top_n), , drop = FALSE]
  }
  out
}

ids_to_names <- function(ids, id_name_map) {
  if (length(ids) == 0L) {
    return(character(0))
  }
  out <- id_name_map[ids]
  out <- ifelse(is.na(out) | !nzchar(out), ids, out)
  as.character(out)
}

print_combination_options <- function(
    rec,
    seed_top,
    cards,
    seed_a_name,
    seed_b_name = "",
    max_pairs = 12L,
    max_packages = 6L) {
  id_name_map <- setNames(vapply(cards, `[[`, "", "name"), vapply(cards, `[[`, "", "id"))

  cat("\n[1] Combinaisons directes autour de", seed_a_name, "\n")
  top_df <- seed_top
  if (is.data.frame(top_df) && nrow(top_df) > 0L) {
    top_df <- top_df[normalize_name(top_df$name) != normalize_name(seed_a_name), , drop = FALSE]
    if (nrow(top_df) > max_pairs) {
      top_df <- top_df[seq_len(max_pairs), , drop = FALSE]
    }
    for (i in seq_len(nrow(top_df))) {
      cat(sprintf(
        "%2d) %s + %s  (score seed=%.3f)\n",
        i,
        seed_a_name,
        as.character(top_df$name[i]),
        as.numeric(top_df$score[i])
      ))
    }
  } else {
    cat("- aucune combinaison directe disponible\n")
  }

  cat("\n[2] Packages de combinaison (bridge)\n")
  if (!is.list(rec$packages) || length(rec$packages) == 0L) {
    cat("- aucun package disponible\n")
    return(invisible(NULL))
  }

  n_pkg <- min(length(rec$packages), as.integer(max_packages))
  for (i in seq_len(n_pkg)) {
    pkg <- rec$packages[[i]]
    bridge_id <- if (!is.null(pkg$bridge_id)) as.character(pkg$bridge_id) else ""
    bridge_name <- ids_to_names(bridge_id, id_name_map)
    bridge_name <- if (length(bridge_name) == 0L) bridge_id else bridge_name[[1]]

    combo_names <- ids_to_names(as.character(pkg$cards), id_name_map)
    combo_names <- unique(combo_names[nzchar(combo_names)])

    chainA_names <- ids_to_names(as.character(pkg$chainA), id_name_map)
    chainB_names <- ids_to_names(as.character(pkg$chainB), id_name_map)

    cat(sprintf("%2d) Bridge: %s\n", i, bridge_name))
    cat("   Combo:", paste(combo_names, collapse = " + "), "\n")
    if (length(chainA_names) > 0L) {
      cat("   Chaine A:", paste(chainA_names, collapse = " -> "), "\n")
    }
    if (length(chainB_names) > 0L) {
      cat("   Chaine B:", paste(chainB_names, collapse = " -> "), "\n")
    }
    if (nzchar(seed_b_name)) {
      cat("   Seeds:", seed_a_name, "|", seed_b_name, "\n")
    }
  }

  invisible(NULL)
}

collections <- mtgcodex.api:::query_collections_list()
stopifnot(isTRUE(collections$ok), length(collections$collections) > 0)

collection_id <- collections$collections[[1]]$id
payload <- mtgcodex.api:::query_collections_get(collection_id)
stopifnot(isTRUE(payload$ok))

base_rows <- records_to_df(payload$rows)
stopifnot("name" %in% names(base_rows))

base_cards <- apply_idf_to_cards(rows_to_cards(base_rows))
base_cards <- filter_cards_by_seed_colors(base_cards, "entomb")
base_run <- run_reco(base_cards, A_name = "entomb")
base_seed_top <- top_seed_recos(base_cards, seed_name = "entomb", top_n = 25L)

cat("\n=== Baseline ===\n")
cat("Seed A:", base_run$A_name, "| Seed B:", base_run$B_name, "\n")
print(head(base_run$rec$bridges, 12L))
cat("\nTop seed Entomb (baseline):\n")
print(base_seed_top)

seed_pages <- c("entomb", "reanimate", "buried-alive", "animate-dead", "necromancy", "victimize")
net_staples <- collect_net_staples(seed_pages, max_cards = 120L)

if (length(net_staples) == 0L) {
  stop("Aucune carte recuperee depuis EDHREC")
}

# Add an explicit reanimator safety list (still net-driven archetype staples).
manual_reanimator <- c(
  "Reanimate", "Animate Dead", "Necromancy", "Dance of the Dead", "Exhume",
  "Victimize", "Buried Alive", "Unmarked Grave", "Persist", "Living Death",
  "Entomb", "Dark Ritual", "Faithless Looting"
)

competitive_combos <- build_competitive_combo_catalog()
competitive_cards <- competitive_combo_cards(competitive_combos)

wanted_additions <- unique(c(net_staples, manual_reanimator, competitive_cards))
base_name_norm <- unique(normalize_name(base_rows$name))
missing_names <- wanted_additions[!normalize_name(wanted_additions) %in% base_name_norm]

cat("\nCartes EDHREC candidates:", length(net_staples), "\n")
cat("Cartes manquantes a ajouter:", length(missing_names), "\n")

added_rows <- build_net_rows(missing_names)
if (nrow(added_rows) == 0L) {
  warning("Aucune carte ajoutee via Scryfall (API inaccessible ?). On continue avec la base.")
}

aug_rows <- base_rows
if (nrow(added_rows) > 0L) {
  # Align columns safely.
  all_cols <- sort(unique(c(names(base_rows), names(added_rows))))
  for (nm in setdiff(all_cols, names(base_rows))) aug_rows[[nm]] <- ""
  for (nm in setdiff(all_cols, names(added_rows))) added_rows[[nm]] <- ""
  aug_rows <- rbind(aug_rows[, all_cols, drop = FALSE], added_rows[, all_cols, drop = FALSE])
}

aug_rows <- aug_rows[!duplicated(normalize_name(aug_rows$name)), , drop = FALSE]
aug_cards <- apply_idf_to_cards(rows_to_cards(aug_rows))
aug_cards <- filter_cards_by_seed_colors(aug_cards, "entomb")
aug_run <- run_reco(aug_cards, A_name = "entomb")
aug_seed_top <- top_seed_recos(aug_cards, seed_name = "entomb", top_n = 25L)

cat("\n=== Augmented ===\n")
cat("Seed A:", aug_run$A_name, "| Seed B:", aug_run$B_name, "\n")
print(head(aug_run$rec$bridges, 20L))
cat("\nTop seed Entomb (augmented):\n")
print(aug_seed_top)

staples_check <- c("reanimate", "animate dead", "necromancy", "buried alive", "victimize", "dance of the dead", "unmarked grave", "living death")
base_top <- normalize_name(head(base_run$rec$bridges$name, 20L))
aug_top <- normalize_name(head(aug_run$rec$bridges$name, 20L))
base_top_seed <- normalize_name(base_seed_top$name)
aug_top_seed <- normalize_name(aug_seed_top$name)

report <- data.frame(
  staple = staples_check,
  baseline_top20 = staples_check %in% base_top,
  augmented_top20 = staples_check %in% aug_top,
  baseline_seed_top25 = staples_check %in% base_top_seed,
  augmented_seed_top25 = staples_check %in% aug_top_seed,
  stringsAsFactors = FALSE
)

cat("\n=== Staples detectees (top20 bridges) ===\n")
print(report)

cat("\n=== Possibilites de combinaison (console lisible) ===\n")
print_combination_options(
  rec = aug_run$rec,
  seed_top = aug_seed_top,
  cards = aug_cards,
  seed_a_name = aug_run$A_name,
  seed_b_name = aug_run$B_name,
  max_pairs = 12L,
  max_packages = 6L
)

id_name_map <- setNames(vapply(aug_cards, `[[`, "", "name"), vapply(aug_cards, `[[`, "", "id"))
package_names <- unique(unlist(
  lapply(
    aug_run$rec$packages,
    function(pkg) ids_to_names(as.character(pkg$cards), id_name_map)
  ),
  use.names = FALSE
))
seed_top60 <- top_seed_recos(aug_cards, seed_name = "entomb", top_n = 60L)
combo_report <- evaluate_competitive_combo_detection(
  combo_catalog = competitive_combos,
  collection_names = aug_rows$name,
  seed_df = seed_top60,
  bridge_df = aug_run$rec$bridges,
  package_names = package_names
)

cat("\n=== Combos competitifs (web) et detection ===\n")
print(combo_report[, c(
  "combo_label",
  "pieces_in_collection",
  "pieces_total",
  "pieces_seed_top25",
  "pieces_seed_top60",
  "pieces_bridge_top25",
  "pieces_in_packages",
  "detected"
)])

output_dir <- file.path("dev", "scritp", "output")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

out_aug_csv <- file.path(output_dir, "entomb_collection_augmented.csv")
out_bridges_csv <- file.path(output_dir, "entomb_augmented_bridges_top25.csv")
out_seed_csv <- file.path(output_dir, "entomb_augmented_seed_top25.csv")
out_combo_report_csv <- file.path(output_dir, "entomb_competitive_combo_report.csv")

utils::write.csv(aug_rows, out_aug_csv, row.names = FALSE)
utils::write.csv(aug_run$rec$bridges, out_bridges_csv, row.names = FALSE)
utils::write.csv(aug_seed_top, out_seed_csv, row.names = FALSE)
utils::write.csv(combo_report, out_combo_report_csv, row.names = FALSE)

cat("\nFichiers ecrits:\n")
cat("-", out_aug_csv, "\n")
cat("-", out_bridges_csv, "\n")
cat("-", out_seed_csv, "\n")
cat("-", out_combo_report_csv, "\n")
