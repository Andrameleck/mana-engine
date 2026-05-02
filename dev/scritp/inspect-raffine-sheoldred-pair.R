devtools::load_all(".", quiet = TRUE)
reg <- query_synergy_event_registry_default()

raffine <- query_synergy_normalize_card(list(
  name = "Raffine, Scheming Seer",
  oracle_text = "Flying, ward {1}\nWhenever you attack, target attacking creature you control connives X, where X is the number of attacking creatures.",
  type_line = "Legendary Creature - Sphinx",
  cmc = 3, colors = c("W","U","B"), color_identity = c("W","U","B"),
  keywords = c("Flying","Ward","Connive")
), registry = reg)

sheoldred <- query_synergy_normalize_card(list(
  name = "Sheoldred, the Apocalypse",
  oracle_text = "Deathtouch\nWhenever you draw a card, you gain 2 life.\nWhenever an opponent draws a card, they lose 2 life.",
  type_line = "Legendary Creature - Phyrexian Praetor",
  cmc = 4, colors = "B", color_identity = "B",
  keywords = "Deathtouch"
), registry = reg)

res <- query_synergy_score_pair(raffine, sheoldred)
cat("score: ", res$score, "\n", sep = "")
cat("reasons:\n")
for (r in res$reasons) cat(" - ", r, "\n", sep = "")
cat("\nmatched_events:\n")
str(res$matched_events)
