\name{analysis_fact}
\alias{analysis_fact}
\title{Create a Functional Fact}
\usage{analysis_fact(kind, object = "", zone = "", controller = "you", qualifiers = character(0))}
\arguments{
\item{kind}{Fact kind.}
\item{object}{Canonical object or event name.}
\item{zone}{Relevant zone.}
\item{controller}{Relevant controller.}
\item{qualifiers}{Additional restrictions.}
}
\value{A functional fact list.}
\description{Creates a fact used in manual ability annotations.}
