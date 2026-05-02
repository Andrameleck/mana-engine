devtools::load_all(".", quiet = TRUE)
reg <- query_synergy_event_registry_default()

raffine <- list(
  name = "Raffine, Scheming Seer",
  oracle_text = "Flying, ward {1}\nWhenever you attack, target attacking creature you control connives X, where X is the number of attacking creatures.",
  type_line = "Legendary Creature - Sphinx",
  mana_cost = "{W}{U}{B}", cmc = 3,
  colors = c("W","U","B"), color_identity = c("W","U","B"),
  keywords = c("Flying","Ward","Connive")
)
sheoldred <- list(
  name = "Sheoldred, the Apocalypse",
  oracle_text = "Deathtouch\nWhenever you draw a card, you gain 2 life.\nWhenever an opponent draws a card, they lose 2 life.",
  type_line = "Legendary Creature - Phyrexian Praetor",
  mana_cost = "{2}{B}{B}", cmc = 4,
  colors = "B", color_identity = "B",
  keywords = "Deathtouch"
)

for (card in list(raffine, sheoldred)) {
  n <- query_synergy_normalize_card(card, registry = reg)
  cat("\n=== ", n$name, " ===\n", sep = "")
  cat("mechanics : ", paste(n$mechanics, collapse = ", "), "\n", sep = "")
  cat("keywords  : ", paste(n$keywords, collapse = ", "), "\n", sep = "")
  cat("produced  : ", paste(n$produced_events, collapse = ", "), "\n", sep = "")
  cat("consumed  : ", paste(n$consumed_events, collapse = ", "), "\n", sep = "")
  cat("replaced  : ", paste(n$replaced_events, collapse = ", "), "\n", sep = "")
  cat("setup     : ", paste(n$setup_events, collapse = ", "), "\n", sep = "")
  cat("finisher  : ", paste(n$finisher_events, collapse = ", "), "\n", sep = "")
  cat("strategy  : ", paste(n$strategy_tags, collapse = ", "), "\n", sep = "")
  cat("roles     : ", paste(n$roles, collapse = ", "), "\n", sep = "")
  cat("target_r  : ", paste(n$target_roles, collapse = ", "), "\n", sep = "")
  cat("anti_tags : ", paste(n$anti_tags, collapse = ", "), "\n", sep = "")
}
