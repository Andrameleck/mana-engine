query_db_rows_to_records <- function(df) {
  if (!is.data.frame(df) || nrow(df) == 0L) {
    return(list())
  }

  lapply(seq_len(nrow(df)), function(i) {
    row <- df[i, , drop = FALSE]
    values <- lapply(row, function(col) {
      value <- col[[1]]
      if (is.factor(value)) {
        return(as.character(value))
      }
      value
    })
    names(values) <- names(row)
    values
  })
}
