library(shiny)
m <- matrix(0L, nrow=3, ncol=4)
m[1, 2] <- 99L
cat("shiny:::toJSON(m):\n")
cat(as.character(shiny:::toJSON(m)), "\n")

