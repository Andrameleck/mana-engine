\name{analyze_functional_synergies}
\alias{analyze_functional_synergies}
\title{Analyze Functional Synergy Candidates}
\usage{
analyze_functional_synergies(seed, candidates, context = analysis_context(),
  limit = 20L)
}
\arguments{
\item{seed}{Seed card list.}
\item{candidates}{List of candidate card lists.}
\item{context}{Validated analysis context.}
\item{limit}{Positive number of displayed candidates.}
}
\value{A versioned response with ranked relations, exclusions, and unknowns.}
\description{Ranks explainable functional relations after strict context filtering.}
