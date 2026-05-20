# query_feedback.R
# Stores user feedback to a local NDJSON file and optionally sends an email.
#
# Environment variables for email (all optional — file storage always happens):
#   FEEDBACK_SMTP_HOST     SMTP host, e.g. smtp.gmail.com
#   FEEDBACK_SMTP_PORT     SMTP port (default 587)
#   FEEDBACK_SMTP_USER     SMTP username / sender address
#   FEEDBACK_SMTP_PASS     SMTP password / app-password
#   FEEDBACK_EMAIL_FROM    From address (defaults to FEEDBACK_SMTP_USER)
#   FEEDBACK_EMAIL_TO      Recipient address (required for email dispatch)

#' @noRd
query_feedback_submit <- function(type, message, email, client_id) {
  message_text <- trimws(as.character(message %||% ""))
  if (!nzchar(message_text)) {
    return(list(ok = FALSE, error = "Message is required."))
  }

  valid_types <- c("bug", "suggestion", "other")
  type <- trimws(tolower(as.character(type %||% "other")))
  if (!type %in% valid_types) type <- "other"

  email     <- trimws(as.character(email      %||% ""))
  client_id <- trimws(as.character(client_id  %||% ""))

  # ── Build entry ────────────────────────────────────────────────────────────
  entry <- list(
    id         = paste0("fb-", format(Sys.time(), "%Y%m%d%H%M%S", tz = "UTC"),
                        "-", sample.int(9999L, 1L)),
    timestamp  = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    type       = type,
    message    = message_text,
    email      = email,
    client_id  = client_id
  )

  # ── Write to NDJSON file ───────────────────────────────────────────────────
  project_root <- Sys.getenv("MANA_ENGINE_API_PROJECT_DIR", unset = "")
  if (!nzchar(project_root)) {
    # Walk up from cwd to find project root (contains DESCRIPTION)
    cwd <- getwd()
    probe <- cwd
    for (i in seq_len(6L)) {
      if (file.exists(file.path(probe, "DESCRIPTION"))) { project_root <- probe; break }
      probe <- dirname(probe)
    }
    if (!nzchar(project_root)) project_root <- cwd
  }
  feedback_dir  <- file.path(project_root, "inst", "feedback")
  dir.create(feedback_dir, recursive = TRUE, showWarnings = FALSE)
  feedback_path <- file.path(feedback_dir, "feedback.ndjson")

  line <- jsonlite::toJSON(entry, auto_unbox = TRUE)
  tryCatch(
    write(line, file = feedback_path, append = TRUE),
    error = function(e) {
      warning("[feedback] could not write to file: ", conditionMessage(e))
    }
  )

  # ── Send email (best-effort, never blocks the response) ───────────────────
  tryCatch(
    query_feedback_send_email(entry),
    error = function(e) {
      message("[feedback] email skipped: ", conditionMessage(e))
    }
  )

  list(ok = TRUE, id = entry$id)
}

#' @noRd
query_feedback_send_email <- function(entry) {
  email_to  <- Sys.getenv("FEEDBACK_EMAIL_TO",   unset = "")
  smtp_host <- Sys.getenv("FEEDBACK_SMTP_HOST",  unset = "")
  smtp_user <- Sys.getenv("FEEDBACK_SMTP_USER",  unset = "")
  smtp_pass <- Sys.getenv("FEEDBACK_SMTP_PASS",  unset = "")

  if (!nzchar(email_to) || !nzchar(smtp_host)) return(invisible(NULL))
  if (!requireNamespace("emayili", quietly = TRUE)) {
    message("[feedback] emayili not available — install it to enable email dispatch")
    return(invisible(NULL))
  }

  smtp_port  <- as.integer(Sys.getenv("FEEDBACK_SMTP_PORT", unset = "587"))
  email_from <- Sys.getenv("FEEDBACK_EMAIL_FROM", unset = smtp_user)

  type_label <- switch(entry$type,
    bug        = "[Bug]",
    suggestion = "[Suggestion]",
    "[Feedback]"
  )
  subject <- paste0("[mana-engine] ", type_label, " ", substr(entry$message, 1L, 60L))

  body <- paste0(
    "Type      : ", entry$type, "\n",
    "From      : ", if (nzchar(entry$email)) entry$email else "(anonymous)", "\n",
    "Client-ID : ", entry$client_id, "\n",
    "Time      : ", entry$timestamp, "\n\n",
    "────────────────────────────────────────\n\n",
    entry$message
  )

  smtp <- emayili::server(
    host     = smtp_host,
    port     = smtp_port,
    username = smtp_user,
    password = smtp_pass
  )

  mail <- emayili::envelope() |>
    emayili::from(email_from) |>
    emayili::to(email_to) |>
    emayili::subject(subject) |>
    emayili::text(body)

  smtp(mail)
  message("[feedback] email sent to ", email_to)
  invisible(NULL)
}
