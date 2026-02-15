query_collection_upload <- function(req, type, table = "", filename = "") {
  file_info <- query_collection_extract_uploaded_file(req, filename = filename)
  if (!isTRUE(file_info$ok)) {
    return(file_info)
  }

  source_type <- tolower(trimws(as.character(type)))
  if (!source_type %in% c("db", "csv", "text")) {
    source_type <- query_collection_guess_type_from_name(file_info$name)
  }

  if (!source_type %in% c("db", "csv", "text")) {
    return(list(
      ok = FALSE,
      error = "type must be one of: db, csv, text"
    ))
  }

  payload <- query_collection_load(
    type = source_type,
    path = file_info$path,
    table = table
  )

  if (!isTRUE(payload$ok)) {
    return(payload)
  }

  payload$uploaded_file <- file_info$name
  payload$path <- file_info$name
  payload
}

query_collection_extract_uploaded_file <- function(req, filename = "") {
  from_files <- query_collection_extract_from_req_files(req)
  if (isTRUE(from_files$ok)) {
    return(from_files)
  }

  from_multipart <- query_collection_extract_from_multipart_body(req)
  if (isTRUE(from_multipart$ok)) {
    return(from_multipart)
  }

  from_octet <- query_collection_extract_from_octet_body(req, filename = filename)
  if (isTRUE(from_octet$ok)) {
    return(from_octet)
  }

  list(
    ok = FALSE,
    error = "file is required"
  )
}

query_collection_extract_from_req_files <- function(req) {
  files <- req$files
  if (is.null(files) || length(files) == 0L) {
    return(list(ok = FALSE))
  }

  file_obj <- files[[1]]
  if (is.list(file_obj) &&
      !is.data.frame(file_obj) &&
      length(file_obj) == 1L &&
      is.list(file_obj[[1]])) {
    file_obj <- file_obj[[1]]
  }

  uploaded_path <- query_collection_find_upload_field(
    x = file_obj,
    keys = c("datapath", "tempfile", "path")
  )
  uploaded_name <- query_collection_find_upload_field(
    x = file_obj,
    keys = c("filename", "name", "originalname")
  )

  if (!nzchar(uploaded_path) || !file.exists(uploaded_path)) {
    return(list(ok = FALSE))
  }

  if (!nzchar(uploaded_name)) {
    uploaded_name <- basename(uploaded_path)
  }

  list(
    ok = TRUE,
    path = uploaded_path,
    name = uploaded_name
  )
}

query_collection_extract_from_multipart_body <- function(req) {
  body <- req$body
  if (!is.list(body) || length(body) == 0L || is.data.frame(body)) {
    return(list(ok = FALSE))
  }

  part <- NULL
  if (!is.null(body$file)) {
    part <- body$file
  } else {
    part <- body[[1]]
  }

  if (is.list(part) &&
      !is.data.frame(part) &&
      length(part) == 1L &&
      is.list(part[[1]])) {
    part <- part[[1]]
  }

  if (!is.list(part)) {
    return(list(ok = FALSE))
  }

  raw_content <- NULL
  if (!is.null(part$value) && is.raw(part$value)) {
    raw_content <- part$value
  } else if (!is.null(part$parsed) && is.raw(part$parsed)) {
    raw_content <- part$parsed
  }

  if (is.null(raw_content) || length(raw_content) == 0L) {
    return(list(ok = FALSE))
  }

  uploaded_name <- query_collection_find_upload_field(
    x = part,
    keys = c("filename", "name", "originalname")
  )
  if (!nzchar(uploaded_name)) {
    uploaded_name <- "upload.bin"
  }

  extension <- tools::file_ext(uploaded_name)
  if (nzchar(extension)) {
    extension <- paste0(".", extension)
  }
  temp_path <- tempfile(fileext = extension)
  writeBin(raw_content, temp_path)

  list(
    ok = TRUE,
    path = temp_path,
    name = uploaded_name
  )
}

query_collection_extract_from_octet_body <- function(req, filename = "") {
  raw_content <- NULL
  if (is.raw(req$body)) {
    raw_content <- req$body
  } else if (is.raw(req$bodyRaw)) {
    raw_content <- req$bodyRaw
  } else if (is.character(req$postBody) && length(req$postBody) == 1L) {
    raw_content <- charToRaw(req$postBody)
  }

  if (is.null(raw_content) || length(raw_content) == 0L) {
    return(list(ok = FALSE))
  }

  uploaded_name <- trimws(as.character(filename))
  if (!nzchar(uploaded_name) && !is.null(req$HTTP_X_FILENAME)) {
    uploaded_name <- trimws(as.character(req$HTTP_X_FILENAME))
  }
  if (!nzchar(uploaded_name)) {
    uploaded_name <- "upload.bin"
  }

  extension <- tools::file_ext(uploaded_name)
  if (nzchar(extension)) {
    extension <- paste0(".", extension)
  }
  temp_path <- tempfile(fileext = extension)
  writeBin(raw_content, temp_path)

  list(
    ok = TRUE,
    path = temp_path,
    name = uploaded_name
  )
}

query_collection_find_upload_field <- function(x, keys) {
  for (key in keys) {
    if (is.data.frame(x) && key %in% colnames(x)) {
      value <- as.character(x[[key]][[1]])
      if (!is.na(value) && nzchar(value)) {
        return(value)
      }
    }
    if (is.list(x) && !is.null(x[[key]])) {
      value <- as.character(x[[key]][[1]])
      if (!is.na(value) && nzchar(value)) {
        return(value)
      }
    }
  }

  ""
}

query_collection_guess_type_from_name <- function(file_name) {
  extension <- tolower(tools::file_ext(file_name))

  if (extension %in% c("db", "sqlite", "sqlite3")) {
    return("db")
  }
  if (extension %in% c("csv")) {
    return("csv")
  }
  if (extension %in% c("txt", "text", "tsv")) {
    return("text")
  }

  ""
}
