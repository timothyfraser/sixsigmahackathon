# test_all.R - Package Test Runner for bikesmart
# Can be run directly from repo root or deliverables/bikesmart
library(dplyr)

if (file.exists("bikesmart/R")) {
  pkg_r <- "bikesmart/R"
  test_dir <- "bikesmart/tests/testthat"
} else if (file.exists("deliverables/bikesmart/R")) {
  pkg_r <- "deliverables/bikesmart/R"
  test_dir <- "deliverables/bikesmart/tests/testthat"
} else if (file.exists("R")) {
  pkg_r <- "R"
  test_dir <- "tests/testthat"
} else {
  stop("Cannot locate package R directory")
}

r_files <- list.files(pkg_r, pattern = "\\.[rR]$", full.names = TRUE)
for (f in r_files) {
  source(f)
}

test_files <- list.files(test_dir, pattern = "^test.*\\.[rR]$", full.names = TRUE)
cat(sprintf("Running %d test suites in %s...\n", length(test_files), test_dir))

for (tf in test_files) {
  cat(sprintf("\n=== Testing %s ===\n", basename(tf)))
  source(tf)
}

cat("\n=======================================================\n")
cat("ALL BIKESMART PACKAGE TESTS PASSED SUCCESSFULLY!\n")
cat("=======================================================\n")
