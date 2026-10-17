# Private API adapter. Input JSON arrives on stdin; output uses package functions.
suppressPackageStartupMessages(library(jsonlite))
source("bikesmart/R/failure_factor.R")
request <- fromJSON(file("stdin"))
rates <- unlist(request$rates)
if (!length(rates)) rates <- setNames(numeric(0), character(0))
stopifnot(length(rates) <= 20, all(is.finite(rates)))
projected <- as.numeric(request$projected)
stopifnot(length(projected) == 1, is.finite(projected), projected >= 0)
result <- list(factor = failure_factor(rates), breakdown = failure_breakdown(rates),
  usable_bikes = apply_failure_factor(projected, rates), projected = projected)
cat(toJSON(result, auto_unbox = TRUE, dataframe = "rows", digits = 15))
