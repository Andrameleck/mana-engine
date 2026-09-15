\name{audit_oracle_coverage}
\alias{audit_oracle_coverage}
\title{Audit Oracle Parser Coverage}
\usage{
audit_oracle_coverage(cards)
}
\arguments{
\item{cards}{A list of card lists or a data frame containing card names and
Oracle text.}
}
\value{
A list with catalogue, clause, syntax, semantic, and unresolved coverage
counts, plus every unresolved clause.
}
\description{
Applies \code{parse_oracle_text()} to a catalogue and produces measurable
coverage suitable for guiding additions to the Oracle grammar.
}
