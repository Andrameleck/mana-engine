# Format rules are separate from card mechanics and from the recommendation model.
.deck_format_rules <- function(format = "commander") {
  format <- tolower(.deck_scalar(format, "commander"))
  constructed <- c("standard", "modern", "pioneer", "legacy", "vintage", "pauper", "historic", "explorer", "timeless", "alchemy")
  if (!format %in% c("commander", constructed)) stop("Unsupported deck format; no implicit Commander fallback", call. = FALSE)
  commander <- format == "commander"
  list(format = format, requires_commander = commander,
    deck_size = if (commander) 100L else 60L,
    mainboard_size = if (commander) 99L else 60L,
    max_copies = if (commander) 1L else 4L,
    land_target = if (commander) 36L else 24L,
    sideboard_generated = FALSE)
}

.deck_copy_limit <- function(card, rules) {
  if (grepl("^basic\\b", tolower(card$type_line %||% ""))) return(rules$mainboard_size)
  if (.deck_legality_status(card, rules$format) == "restricted") return(1L)
  text <- tolower(card$oracle_text %||% "")
  if (grepl("a deck can have any number of cards named", text, fixed = TRUE)) return(rules$mainboard_size)
  number <- regmatches(text, regexec("a deck can have up to ([a-z]+|[0-9]+) cards named", text))[[1]]
  if (length(number) > 1L) {
    words <- c(one = 1L, two = 2L, three = 3L, four = 4L, five = 5L, six = 6L, seven = 7L, eight = 8L, nine = 9L)
    value <- if (number[[2]] %in% names(words)) words[[number[[2]]]] else suppressWarnings(as.integer(number[[2]]))
    if (is.finite(value)) return(min(value, rules$mainboard_size))
  }
  rules$max_copies
}

.deck_role_targets <- function(rules) {
  targets <- if (rules$requires_commander) c(land = 36L, ramp = 10L, card_draw = 10L, removal = 10L, threat = 8L, core = 25L) else
    c(land = 24L, ramp = 4L, card_draw = 6L, removal = 8L, threat = 6L, core = 12L)
  targets
}
