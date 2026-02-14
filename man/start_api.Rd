\name{start_api}
\alias{start_api}
\title{Start the mtgcodex.api Plumber API}
\usage{
start_api(host = "0.0.0.0", port = 8000L, swagger = TRUE,
  hide_ui_from_swagger = TRUE, ...)
}
\arguments{
  \item{host}{Host interface to bind.}

  \item{port}{Integer TCP port in \code{[1, 65535]}.}

  \item{swagger}{Whether to expose the Swagger UI.}

  \item{hide_ui_from_swagger}{Whether to hide \code{/} and \code{/ui*} routes from the API spec.}

  \item{...}{Additional parameters forwarded to \code{plumber::pr_run()}.}
}
\description{
Validates startup inputs, loads \code{inst/plumber/plumber.R}, adds a root redirect
from \code{/} to \code{/ui}, optionally removes UI routes from Swagger, and starts
the HTTP server.
}
\value{
Invisibly returns \code{NULL}. The primary purpose is to start the HTTP server.
}
\examples{
\dontrun{
start_api(host = "0.0.0.0", port = 8000)
}
}
