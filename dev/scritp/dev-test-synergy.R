# 1) Charger le pipeline (fichier que tu as dans le repo)
source("R/bridge_synergy.R")

# 2) Récupérer ta collection stockée par l'API (base interne)
#    (fonctions internes du package)
collections <- mtgcodex.api:::query_collections_list()
stopifnot(isTRUE(collections$ok), length(collections$collections) > 0)

# Prend la collection la plus récente (ou remplace par ton id)
collection_id <- collections$collections[[1]]$id
payload <- mtgcodex.api:::query_collections_get(collection_id)
stopifnot(isTRUE(payload$ok))

# 3) Convertir records -> data.frame
records_to_df <- function(records) {
  if (length(records) == 0L) return(data.frame(stringsAsFactors = FALSE))
  cols <- sort(unique(unlist(lapply(records, names), use.names = FALSE)))
  rows <- lapply(records, function(r) {
    x <- setNames(vector("list", length(cols)), cols)
    for (nm in cols) x[[nm]] <- if (!is.null(r[[nm]])) r[[nm]] else ""
    as.data.frame(x, stringsAsFactors = FALSE, check.names = FALSE)
  })
  do.call(rbind, rows)
}

rows <- records_to_df(payload$rows)
stopifnot("name" %in% names(rows))

# 4) Feature engineering simple (base R)
parse_colors <- function(mana_cost) {
  s <- toupper(ifelse(is.na(mana_cost), "", as.character(mana_cost)))
  hits <- regmatches(s, gregexpr("\\{[WUBRG]\\}", s, perl = TRUE))[[1]]
  if (length(hits) == 0L) return(character(0))
  unique(gsub("[{}]", "", hits))
}

extract_features <- function(oracle_text = "", keywords = "") {
  txt <- tolower(paste(oracle_text, keywords, sep = " "))
  has <- function(pat) as.numeric(grepl(pat, txt, perl = TRUE))

  f <- c(
    graveyard = has("\\bgraveyard\\b"),
    reanimate = has("return target .*graveyard.*battlefield|reanimate"),
    tutor = has("search your library"),
    discard = has("\\bdiscard\\b"),
    draw = has("\\bdraw\\b"),
    sac = has("\\bsacrifice\\b"),
    etb = has("enters the battlefield|\\betb\\b"),
    token = has("\\btoken\\b"),
    mill = has("\\bmill\\b|put .* into .*graveyard")
  )
  f[f > 0]
}

rows_to_cards <- function(df) {
  df$name <- trimws(as.character(df$name))
  df <- df[nzchar(df$name), , drop = FALSE]
  df <- df[!duplicated(tolower(df$name)), , drop = FALSE]

  ids <- make.unique(gsub("[^a-z0-9]+", "_", tolower(df$name)))
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

cards <- rows_to_cards(rows)

# 5) Trouver Entomb
card_names <- vapply(cards, `[[`, "", "name")
idx_A <- which(tolower(card_names) == "entomb")[1]
stopifnot(!is.na(idx_A))
A_id <- cards[[idx_A]]$id

# 6) Recommandations "A seul" (B, C, D... autour de Entomb)
prop <- propagate_scores(
  seed_id = A_id,
  cards = cards,
  depth_N = 3L,
  top_k = 40L,
  gamma = 0.65,
  options = list(unique_nodes = TRUE, max_candidates = 2000L)
)

id_to_name <- setNames(vapply(cards, `[[`, "", "name"), vapply(cards, `[[`, "", "id"))
top_entomb <- head(data.frame(
  id = names(prop$scores),
  name = unname(id_to_name[names(prop$scores)]),
  score = as.numeric(prop$scores),
  stringsAsFactors = FALSE
), 15)
print(top_entomb)

# 7) Option "bridge" Entomb -> payoff (ex: Reanimate si présent)
target_names <- c("reanimate", "animate dead", "necromancy", "victimize", "exhume", "persist")
idx_B <- match(target_names, tolower(card_names))
idx_B <- idx_B[!is.na(idx_B)][1]

if (is.na(idx_B)) {
  # fallback: le meilleur voisin d'Entomb
  best_id <- names(prop$scores)[1]
  idx_B <- match(best_id, vapply(cards, `[[`, "", "id"))
}

B_id <- cards[[idx_B]]$id
cat("Seed A:", cards[[idx_A]]$name, "| Seed B:", cards[[idx_B]]$name, "\n")

rec <- compute_bridge_recommendations(
  cards = cards,
  A_id = A_id,
  B_id = B_id,
  depth_N = 3L,
  top_k = 40L,
  gamma = 0.65,
  topN = 20L,
  topChains = 5L,
  topPackages = 5L,
  options = list(
    enforce_color_identity = FALSE,
    unique_nodes = TRUE,
    max_candidates = 2000L,
    max_chain_len = 6L,
    support_k = 2L
  )
)

print(rec$bridges)
print(rec$chains[[1]])
print(rec$packages[[1]])
