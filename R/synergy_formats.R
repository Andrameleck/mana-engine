# =============================================================================
# Format registry & legality helpers.
#
# Each format defines:
#   - legality_key: the key under card$legalities (Scryfall convention).
#   - singleton:    whether deck construction is singleton (Commander, Brawl).
#   - color_identity_strict: whether color identity is enforced (Commander, Brawl).
#   - accepted_status: legality values considered legal/playable.
#   - banlist_extra: additional banned card ids/names (rarely needed; the
#                    Scryfall legalities feed already encodes bans).
#
# Filtering is applied early in the synergy pipeline to remove illegal cards
# from the candidate pool, unless the user enables `allow_illegal`.
# =============================================================================

query_synergy_format_registry <- local({
  registry <- NULL
  function() {
    if (!is.null(registry)) return(registry)

    registry <<- list(
      commander = list(
        label = "Commander",
        legality_key = "commander",
        singleton = TRUE,
        color_identity_strict = TRUE,
        accepted_status = c("legal", "restricted")
      ),
      modern = list(
        label = "Modern",
        legality_key = "modern",
        singleton = FALSE,
        color_identity_strict = FALSE,
        accepted_status = c("legal", "restricted")
      ),
      legacy = list(
        label = "Legacy",
        legality_key = "legacy",
        singleton = FALSE,
        color_identity_strict = FALSE,
        accepted_status = c("legal", "restricted")
      ),
      vintage = list(
        label = "Vintage",
        legality_key = "vintage",
        singleton = FALSE,
        color_identity_strict = FALSE,
        accepted_status = c("legal", "restricted")
      ),
      pioneer = list(
        label = "Pioneer",
        legality_key = "pioneer",
        singleton = FALSE,
        color_identity_strict = FALSE,
        accepted_status = c("legal", "restricted")
      ),
      standard = list(
        label = "Standard",
        legality_key = "standard",
        singleton = FALSE,
        color_identity_strict = FALSE,
        accepted_status = c("legal", "restricted")
      ),
      pauper = list(
        label = "Pauper",
        legality_key = "pauper",
        singleton = FALSE,
        color_identity_strict = FALSE,
        accepted_status = c("legal", "restricted")
      ),
      brawl = list(
        label = "Brawl",
        legality_key = "brawl",
        singleton = TRUE,
        color_identity_strict = TRUE,
        accepted_status = c("legal", "restricted")
      ),
      historic = list(
        label = "Historic",
        legality_key = "historic",
        singleton = FALSE,
        color_identity_strict = FALSE,
        accepted_status = c("legal", "restricted")
      )
    )
    registry
  }
})

# Returns the format spec for a given key, or NULL when unknown.
query_synergy_format_spec <- function(format_name) {
  if (!is.character(format_name) || length(format_name) == 0L) return(NULL)
  key <- tolower(format_name[[1L]])
  reg <- query_synergy_format_registry()
  if (key %in% names(reg)) reg[[key]] else NULL
}

# Whether a card is legal in the requested format.
# - cards with no legalities entry are considered UNKNOWN; we treat them as
#   legal (better recall) unless allow_illegal is FALSE AND the format is
#   strict. To stay conservative without breaking older catalogs, we accept
#   unknowns as legal: the Scryfall feed populates `legalities` for nearly
#   every card.
query_synergy_card_legal_in_format <- function(card, format_name = "commander", allow_illegal = FALSE) {
  if (isTRUE(allow_illegal)) return(TRUE)
  spec <- query_synergy_format_spec(format_name)
  if (is.null(spec)) return(TRUE)
  legalities <- card$legalities
  if (!is.list(legalities) || length(legalities) == 0L) return(TRUE)
  status <- legalities[[spec$legality_key]]
  if (is.null(status) || !nzchar(status)) return(TRUE)
  tolower(status) %in% spec$accepted_status
}

# Public listing endpoint helper.
query_synergy_formats_list <- function() {
  reg <- query_synergy_format_registry()
  lapply(names(reg), function(key) {
    spec <- reg[[key]]
    list(
      key = key,
      label = query_api_scalar(spec$label, default = key),
      singleton = isTRUE(spec$singleton),
      color_identity_strict = isTRUE(spec$color_identity_strict)
    )
  })
}
