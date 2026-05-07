test_that("spellbook validation scores direct entries and groups separately", {
  variants <- list(
    list(
      id = "v1",
      popularity = 100,
      uses = list(
        list(card = list(name = "Sheoldred, the Apocalypse")),
        list(card = list(name = "Raffine, Scheming Seer")),
        list(card = list(name = "Engine of Insight"))
      )
    ),
    list(
      id = "v2",
      popularity = 20,
      uses = list(
        list(card = list(name = "Sheoldred, the Apocalypse")),
        list(card = list(name = "Raffine, Scheming Seer"))
      )
    ),
    list(
      id = "v3",
      popularity = 10,
      uses = list(
        list(card = list(name = "Sheoldred, the Apocalypse")),
        list(card = list(name = "Hill Giant"))
      )
    )
  )

  out <- mtgcodex.api:::query_synergy_validate_spellbook(
    seed_name = "Sheoldred, the Apocalypse",
    entries = list(
      list(name = "Raffine, Scheming Seer"),
      list(name = "Hill Giant")
    ),
    groups = list(
      list(
        id = "grp1",
        members = list(
          list(name = "Sheoldred, the Apocalypse"),
          list(name = "Raffine, Scheming Seer"),
          list(name = "Engine of Insight")
        )
      )
    ),
    variants = variants
  )

  expect_true(isTRUE(out$ok))
  expect_identical(out$variant_count, 3L)

  raffine <- Filter(function(entry) identical(entry$name, "Raffine, Scheming Seer"), out$entries)[[1]]
  hill <- Filter(function(entry) identical(entry$name, "Hill Giant"), out$entries)[[1]]
  group <- out$groups[[1]]

  expect_identical(raffine$refs, 2L)
  expect_gt(raffine$score, hill$score)
  expect_true(isTRUE(raffine$cooccurs_with_seed))

  expect_identical(group$full_match_refs, 1L)
  expect_identical(group$partial_match_refs, 2L)
  expect_gt(group$score, 0)
})

test_that("lotusnoir validation scores co-mentions without changing heuristic score", {
  posts <- list(
    list(
      id = "p1",
      title = "Sheoldred, the Apocalypse with Raffine, Scheming Seer",
      snippet = "Engine of Insight also appears here."
    ),
    list(
      id = "p2",
      title = "Deck tech: Sheoldred, the Apocalypse",
      snippet = "Raffine, Scheming Seer closes games."
    ),
    list(
      id = "p3",
      title = "Sheoldred, the Apocalypse control shell",
      snippet = "No Raffine in this one."
    )
  )

  out <- mtgcodex.api:::query_synergy_validate_lotusnoir(
    seed_name = "Sheoldred, the Apocalypse",
    entries = list(
      list(name = "Raffine, Scheming Seer"),
      list(name = "Hill Giant")
    ),
    groups = list(
      list(
        id = "grp1",
        members = list(
          list(name = "Sheoldred, the Apocalypse"),
          list(name = "Raffine, Scheming Seer"),
          list(name = "Engine of Insight")
        )
      )
    ),
    posts = posts
  )

  expect_true(isTRUE(out$ok))
  expect_identical(out$post_count, 3L)

  raffine <- Filter(function(entry) identical(entry$name, "Raffine, Scheming Seer"), out$entries)[[1]]
  hill <- Filter(function(entry) identical(entry$name, "Hill Giant"), out$entries)[[1]]

  expect_identical(raffine$refs, 2L)
  expect_identical(hill$refs, 0L)
  expect_gt(raffine$score, hill$score)
  expect_identical(out$groups[[1]]$full_match_refs, 1L)
})

test_that("synergy finder can attach external validations from payload overrides", {
  catalog <- list(
    list(
      id = "sheoldred",
      name = "Sheoldred, the Apocalypse",
      oracle_text = "Whenever you draw a card, you gain 2 life. Whenever an opponent draws a card, they lose 2 life.",
      colors = c("B"),
      color_identity = c("B"),
      cmc = 4,
      legalities = list(commander = "legal")
    ),
    list(
      id = "raffine",
      name = "Raffine, Scheming Seer",
      oracle_text = "Flying, ward 1. Whenever you attack, target attacking creature connives X.",
      colors = c("W", "U", "B"),
      color_identity = c("W", "U", "B"),
      cmc = 3,
      legalities = list(commander = "legal")
    ),
    list(
      id = "engine",
      name = "Engine of Insight",
      oracle_text = "Draw two cards, then discard a card.",
      colors = c("U"),
      color_identity = c("U"),
      cmc = 2,
      legalities = list(commander = "legal")
    ),
    list(
      id = "vanilla",
      name = "Hill Giant",
      oracle_text = "",
      colors = c("R"),
      color_identity = c("R"),
      cmc = 4,
      legalities = list(commander = "legal")
    )
  )

  payload_base <- list(
    card_name = "Sheoldred, the Apocalypse",
    format = "commander",
    max_results = 5
  )

  baseline <- mtgcodex.api:::query_synergy_find_in_catalog(payload_base, catalog)
  enriched <- mtgcodex.api:::query_synergy_find_in_catalog(
    c(payload_base, list(
      include_spellbook = TRUE,
      include_lotusnoir = TRUE,
      spellbook_variants = list(
        list(
          id = "v1",
          popularity = 80,
          uses = list(
            list(card = list(name = "Sheoldred, the Apocalypse")),
            list(card = list(name = "Raffine, Scheming Seer"))
          )
        )
      ),
      lotusnoir_posts = list(
        list(
          id = "p1",
          title = "Sheoldred, the Apocalypse and Raffine, Scheming Seer",
          snippet = "Community shell."
        )
      )
    )),
    catalog
  )

  expect_true(isTRUE(enriched$ok))
  expect_true(is.list(enriched$external_validation))

  base_raffine <- Filter(function(entry) identical(entry$name, "Raffine, Scheming Seer"), baseline$best_matches)[[1]]
  enriched_raffine <- Filter(function(entry) identical(entry$name, "Raffine, Scheming Seer"), enriched$best_matches)[[1]]

  expect_identical(enriched_raffine$score, base_raffine$score)
  expect_true("heuristic" %in% enriched_raffine$provenance_tags)
  expect_true("spellbook" %in% enriched_raffine$provenance_tags)
  expect_true("lotus_noir" %in% enriched_raffine$provenance_tags)
  expect_gt(enriched_raffine$external_validation$spellbook$score, 0)
  expect_gt(enriched_raffine$external_validation$lotusnoir$score, 0)
})
