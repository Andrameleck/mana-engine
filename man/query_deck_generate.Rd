\name{query_deck_generate}
\alias{query_deck_generate}
\title{Generate Commander Decks}
\usage{
query_deck_generate(payload)
}
\arguments{
\item{payload}{Request body containing a commander name, optional collection
identifier, and the requested number of variants.}
}
\value{
An API response containing legal, singleton, scored 99-card deck variants and
their commander, role balance, ownership information, and catalogue source.
}
\description{
Builds Commander decks from Scryfall candidates and the local card catalogue.
Cards owned in the selected collection receive a preference while unavailable
slots may be completed from the full catalogue.
}
