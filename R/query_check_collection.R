query_check_collection <- function(card_name, deck_name) {
  normalized_card <- query_normalize_text(card_name)
  normalized_deck <- query_normalize_text(deck_name)

  validation <- query_validate_check_inputs(
    card_name = normalized_card,
    deck_name = normalized_deck
  )

  if (!isTRUE(validation$ok)) {
    return(validation)
  }

  match_result <- query_fetch_collection_match(
    card_name = normalized_card,
    deck_name = normalized_deck
  )

  list(
    ok = TRUE,
    data = match_result
  )
}
