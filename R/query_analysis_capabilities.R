query_analysis_capabilities <- function() {
  formats <- c("commander", "standard", "modern", "pioneer", "legacy", "vintage", "pauper", "historic", "explorer", "timeless", "alchemy")
  list(ok = TRUE, formats = lapply(formats, .deck_format_rules),
    controls = list(anchor = TRUE, colors = TRUE, collection_only = TRUE, exclude_banned = TRUE,
      archetype_filter = FALSE, creature_theme = FALSE, power_score = FALSE, sideboard = FALSE),
    analysis = list(accepts_all_card_types = TRUE, executes_full_rules = FALSE,
      arbitrary_annotated_interfaces = TRUE, automatic_oracle_coverage = "partial",
      missing_relation_means = "not_detected_not_disproved"))
}
