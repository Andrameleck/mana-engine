#!/usr/bin/env Rscript

suppressMessages(devtools::load_all(".", quiet = TRUE))

db_dir <- file.path("inst", "decks", "lotusnoir")
dir.create(db_dir, recursive = TRUE, showWarnings = FALSE)
db_path <- Sys.getenv(
  "LOTUSNOIR_DB_PATH",
  unset = file.path(db_dir, "lotusnoir.sqlite")
)

max_decks_raw <- trimws(Sys.getenv("LOTUSNOIR_MAX_DECKS", unset = ""))
max_decks <- suppressWarnings(as.integer(max_decks_raw))
if (!nzchar(max_decks_raw) || !is.finite(max_decks) || is.na(max_decks) || max_decks < 1L) {
  max_decks <- NA_integer_
}

request_delay <- suppressWarnings(as.numeric(Sys.getenv("LOTUSNOIR_REQUEST_DELAY", unset = "5")))
if (!is.finite(request_delay) || is.na(request_delay) || request_delay < 0) {
  request_delay <- 5
}

refresh_urls <- tolower(Sys.getenv("LOTUSNOIR_REFRESH_URLS", unset = "false")) %in% c("1", "true", "yes", "y", "on")
overwrite_existing <- tolower(Sys.getenv("LOTUSNOIR_OVERWRITE", unset = "false")) %in% c("1", "true", "yes", "y", "on")
probe_radius <- suppressWarnings(as.integer(Sys.getenv("LOTUSNOIR_PROBE_RADIUS", unset = "0")))
if (!is.finite(probe_radius) || is.na(probe_radius) || probe_radius < 0L) {
  probe_radius <- 0L
}
probe_max_dids <- suppressWarnings(as.integer(Sys.getenv("LOTUSNOIR_PROBE_MAX_DIDS", unset = "0")))
if (!is.finite(probe_max_dids) || is.na(probe_max_dids) || probe_max_dids < 0L) {
  probe_max_dids <- 0L
}
test_card <- trimws(Sys.getenv("LOTUSNOIR_TEST_CARD", unset = ""))
test_format <- trimws(Sys.getenv("LOTUSNOIR_TEST_FORMAT", unset = ""))
test_top_n <- suppressWarnings(as.integer(Sys.getenv("LOTUSNOIR_TEST_TOP_N", unset = "10")))
if (!is.finite(test_top_n) || is.na(test_top_n) || test_top_n < 1L) {
  test_top_n <- 10L
}
test_deck_limit <- suppressWarnings(as.integer(Sys.getenv("LOTUSNOIR_TEST_DECK_LIMIT", unset = "5")))
if (!is.finite(test_deck_limit) || is.na(test_deck_limit) || test_deck_limit < 1L) {
  test_deck_limit <- 5L
}

cat(sprintf("LotusNoir DB  : %s\n", db_path))
cat(sprintf(
  "Max decks     : %s\n",
  if (is.na(max_decks)) "all discovered" else as.character(max_decks)
))
cat(sprintf("Request delay : %.1f seconds\n", request_delay))
cat(sprintf("Refresh URLs  : %s\n", if (refresh_urls) "TRUE" else "FALSE"))
cat(sprintf("Probe radius  : %d\n", probe_radius))
cat(sprintf("Probe max did : %d\n", probe_max_dids))
cat(sprintf("Overwrite     : %s\n\n", if (overwrite_existing) "TRUE" else "FALSE"))

out <- query_lotusnoir_download_decks_sqlite(
  db_path = db_path,
  max_decks = max_decks,
  request_delay = request_delay,
  refresh_urls = refresh_urls,
  probe_radius = probe_radius,
  probe_max_dids = probe_max_dids,
  overwrite_existing = overwrite_existing,
  verbose = TRUE
)

if (!isTRUE(out$ok)) {
  stop(sprintf("LotusNoir download failed: %s", query_api_scalar(out$error, default = "unknown")))
}

cat("\n=== Lotus Noir SQLite summary ===\n")
cat(sprintf("Discovered deck URLs : %d\n", query_synergy_as_int(out$discovered_deck_urls, default = 0L, min_value = 0L, max_value = 10000000L)))
if (is.list(out$probe)) {
  cat(sprintf("Probe tested         : %d\n", query_synergy_as_int(out$probe$tested, default = 0L, min_value = 0L, max_value = 10000000L)))
  cat(sprintf("Probe hits           : %d\n", query_synergy_as_int(out$probe$hits, default = 0L, min_value = 0L, max_value = 10000000L)))
  cat(sprintf("Probe inserted URLs  : %d\n", query_synergy_as_int(out$probe$inserted_urls, default = 0L, min_value = 0L, max_value = 10000000L)))
}
cat(sprintf("Processed decks      : %d\n", query_synergy_as_int(out$processed_decks, default = 0L, min_value = 0L, max_value = 10000000L)))
cat(sprintf("Skipped decks        : %d\n", query_synergy_as_int(out$skipped_decks, default = 0L, min_value = 0L, max_value = 10000000L)))
cat(sprintf("Stored rows          : %d\n", query_synergy_as_int(out$stored_rows, default = 0L, min_value = 0L, max_value = 100000000L)))
cat(sprintf("Failed decks         : %d\n", length(query_synergy_to_list(out$failed))))

if (length(query_synergy_to_list(out$failed)) > 0L) {
  cat("\nFirst failures:\n")
  for (entry in head(query_synergy_to_list(out$failed), 10L)) {
    cat(sprintf(
      " - %s :: %s\n",
      query_api_scalar(entry$deck_url, default = ""),
      query_api_scalar(entry$error, default = "unknown")
    ))
  }
}

if (nzchar(test_card)) {
  cat("\n=== Lotus Noir card stats ===\n")
  cat(sprintf("Card          : %s\n", test_card))
  if (nzchar(test_format)) {
    cat(sprintf("Format filter : %s\n", test_format))
  }

  stats_out <- query_lotusnoir_card_stats(
    card_name = test_card,
    db_path = db_path,
    format_name = test_format,
    top_n = test_top_n,
    deck_limit = test_deck_limit
  )

  if (!isTRUE(stats_out$ok)) {
    cat(sprintf("Stats ERROR   : %s\n", query_api_scalar(stats_out$error, default = "unknown")))
  } else {
    cat(sprintf("Deck count    : %d\n", query_synergy_as_int(stats_out$stats$deck_count, default = 0L, min_value = 0L, max_value = 100000000L)))
    cat(sprintf("Total qty     : %d\n", query_synergy_as_int(stats_out$stats$total_quantity, default = 0L, min_value = 0L, max_value = 100000000L)))
    cat(sprintf("Avg qty/deck  : %.3f\n", query_synergy_as_num(stats_out$stats$average_quantity_per_deck, default = 0, min_value = 0)))

    if (is.data.frame(stats_out$formats) && nrow(stats_out$formats) > 0L) {
      cat("\nFormats:\n")
      for (index in seq_len(nrow(stats_out$formats))) {
        row <- stats_out$formats[index, , drop = FALSE]
        cat(sprintf(
          " - %-24s decks=%d total_qty=%d\n",
          query_api_scalar(row$format, default = "(unknown)"),
          query_synergy_as_int(row$deck_count, default = 0L, min_value = 0L, max_value = 100000000L),
          query_synergy_as_int(row$total_quantity, default = 0L, min_value = 0L, max_value = 100000000L)
        ))
      }
    }

    if (is.data.frame(stats_out$cooccurrences) && nrow(stats_out$cooccurrences) > 0L) {
      cat("\nTop cooccurrences:\n")
      for (index in seq_len(min(nrow(stats_out$cooccurrences), test_top_n))) {
        row <- stats_out$cooccurrences[index, , drop = FALSE]
        cat(sprintf(
          " - %-28s decks=%d share=%.3f avg_qty=%.3f\n",
          query_api_scalar(row$card_name, default = query_api_scalar(row$normalized_name, default = "")),
          query_synergy_as_int(row$cooccur_deck_count, default = 0L, min_value = 0L, max_value = 100000000L),
          query_synergy_as_num(row$share_of_seed_decks, default = 0, min_value = 0, max_value = 1),
          query_synergy_as_num(row$average_quantity_per_deck, default = 0, min_value = 0)
        ))
      }
    }

    if (is.data.frame(stats_out$decks) && nrow(stats_out$decks) > 0L) {
      cat("\nExample decks:\n")
      for (index in seq_len(min(nrow(stats_out$decks), test_deck_limit))) {
        row <- stats_out$decks[index, , drop = FALSE]
        cat(sprintf(
          " - %s | %s | %s\n",
          query_api_scalar(row$title, default = "(untitled)"),
          query_api_scalar(row$format, default = "(unknown)"),
          query_api_scalar(row$deck_url, default = "")
        ))
      }
    }
  }
}
