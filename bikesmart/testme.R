# testme.R - Run tests locally with one command
if (!requireNamespace("testthat", quietly = TRUE)) {
  stop("Please install 'testthat': install.packages('testthat')")
}
source("tests/test_all.R")

