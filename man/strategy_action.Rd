\name{strategy_action}
\alias{strategy_action}
\title{Create a Typed Strategy Action}
\usage{strategy_action(id, card_id, action_type, consumes = list(), requires = list(), produces = list(), from_zone = "", to_zone = "", selector = "", evidence = "", status = c("inferred", "verified", "unknown"), unknown_conditions = character(0))}
\description{Creates a typed, evidenced card action used by the strategy engine.}
