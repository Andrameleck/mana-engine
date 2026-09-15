\name{analyze_functional_groups}
\alias{analyze_functional_groups}
\title{Find Explainable Three-card Functional Groups}
\usage{
analyze_functional_groups(cards, context = analysis_context(), limit = 20L,
  max_pair_evaluations = 10000L)
}
\arguments{
\item{cards}{List of cards with unique canonical identifiers.}
\item{context}{Validated analysis context.}
\item{limit}{Maximum displayed groups.}
\item{max_pair_evaluations}{Maximum directed pairs evaluated.}
}
\value{A versioned response with groups and search budget information.}
\description{Builds three-card paths from two directed evidenced relations.}
