\name{analysis_ability}
\alias{analysis_ability}
\title{Create a Functional Ability Annotation}
\usage{
analysis_ability(id, card_id, family, produces = list(), requires = list(),
  costs = list(), evidence = "",
  status = c("verified", "inferred", "unknown"),
  unknown_conditions = character(0))
}
\arguments{
\item{id}{Stable ability identifier.}
\item{card_id}{Canonical owner identifier.}
\item{family}{One of the supported functional families.}
\item{produces,requires,costs}{Lists of structured functional facts.}
\item{evidence}{Supporting Oracle fragment.}
\item{status}{Interpretation status.}
\item{unknown_conditions}{Unresolved restrictions.}
}
\value{A validated ability annotation.}
\description{Represents costs, requirements and outputs without merging their meanings.}
