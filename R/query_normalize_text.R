query_normalize_text <- function(x) {
  text <- trimws(as.character(x))
  tolower(text)
}
