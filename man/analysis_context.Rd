\name{analysis_context}
\alias{analysis_context}
\title{Create a Functional Analysis Context}
\usage{
analysis_context(
  format = "", rules_version = "", allowed_colors = NULL,
  mode = c("explore", "deck", "sequence"), objective = "",
  inventory = NULL
)
}
\arguments{
\item{format}{Optional format name.}
\item{rules_version}{Rules snapshot identifier.}
\item{allowed_colors}{Allowed WUBRG identity symbols, or \code{NULL}.}
\item{mode}{Analysis mode.}
\item{objective}{Optional supported functional family used as the objective.}
\item{inventory}{Optional named non-negative quantity vector.}
}
\value{A validated functional analysis context.}
\description{Defines explicit constraints and unknown fields for an analysis.}
