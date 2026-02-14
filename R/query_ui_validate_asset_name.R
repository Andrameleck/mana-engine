query_ui_validate_asset_name <- function(file_name) {
  if (!nzchar(file_name)) {
    return(FALSE)
  }

  grepl("^[A-Za-z0-9._-]+$", file_name)
}
