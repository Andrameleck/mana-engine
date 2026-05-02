devtools::load_all(".", quiet = TRUE)

raffine <- query_synergy_normalize_card(list(
  id = "raffine", name = "Raffine, Scheming Seer",
  oracle_text = "Flying, ward {1}\nWhenever you attack, target attacking creature you control connives X, where X is the number of attacking creatures.",
  type_line = "Legendary Creature - Sphinx",
  cmc = 3, colors = c("W","U","B"), color_identity = c("W","U","B"),
  keywords = c("Flying","Ward","Connive")
))

sheoldred <- query_synergy_normalize_card(list(
  id = "sheoldred", name = "Sheoldred, the Apocalypse",
  oracle_text = "Deathtouch\nWhenever you draw a card, you gain 2 life.\nWhenever an opponent draws a card, they lose 2 life.",
  type_line = "Legendary Creature - Phyrexian Praetor",
  cmc = 4, colors = "B", color_identity = "B",
  keywords = "Deathtouch"
))

cat("--- direct calls (asymmetric) ---\n")
cat("score_pair(Raffine, Sheoldred):", query_synergy_score_pair(raffine, sheoldred)$score, "\n")
cat("score_pair(Sheoldred, Raffine):", query_synergy_score_pair(sheoldred, raffine)$score, "\n")

cat("\n--- engine logic (max of both directions) ---\n")
fwd <- query_synergy_score_pair(sheoldred, raffine)
bwd <- query_synergy_score_pair(raffine, sheoldred)
chosen <- if (isTRUE(bwd$score > fwd$score)) bwd else fwd
cat("Sheoldred-as-seed -> Raffine final score (engine output):", chosen$score, "\n")
cat("primary_bucket:", chosen$primary_bucket, "\n")
cat("relation_classes:", paste(chosen$relation_classes, collapse=", "), "\n")
