query_validate_check_inputs <- function(card_name, deck_name) {
  if (!nzchar(card_name)) {
    return(list(
      ok = FALSE,
      error = "card_name is required"
    ))
  }

  if (!nzchar(deck_name)) {
    return(list(
      ok = FALSE,
      error = "deck_name is required"
    ))
  }

  list(ok = TRUE)
}
