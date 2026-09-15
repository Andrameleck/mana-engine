\name{parse_oracle_text}
\alias{parse_oracle_text}
\title{Parse Oracle Text into a General Intermediate Representation}
\usage{
parse_oracle_text(card)
}
\arguments{
\item{card}{Card list with an id or name and \code{oracle_text}.}
}
\value{
A structured record containing clauses, triggers, costs, effects, normalized
facts, modifiers, exact evidence, and syntax and semantic coverage metrics.
}
\description{
Splits Oracle text into abilities. Every clause is represented by functional
facts, classified as syntax-only, or returned explicitly as unresolved.
}
