# app/make_app_data.R - copy the H-02 scenario files into the app bundle (team 2027win)
#
# Posit Connect only receives the files inside app/, so the deployed app cannot read ../data/.
# This script writes gzip copies of the three formal scenario files into app/data/:
#   data/baseline.csv       -> app/data/baseline.csv.gz
#   data/planted_shift.csv  -> app/data/planted_shift.csv.gz
#   data/edge_case.csv      -> app/data/edge_case.csv.gz
# The only change is the compression (and LF line endings, which is what git stores); the
# app reads .csv.gz directly with the same loader. tests/test-prep.R checks that every copy
# still matches data/, so re-run this script whenever data/ changes, then re-write the
# manifest (Rscript app/manifestme.R).
#
# Run from the repo root:  Rscript app/make_app_data.R

scenarios <- c("baseline", "planted_shift", "edge_case")
if (!dir.exists("data") || !dir.exists("app")) stop("Run this from the repository root.")
dir.create(file.path("app", "data"), showWarnings = FALSE)

for (s in scenarios) {
  src <- file.path("data", paste0(s, ".csv"))
  dst <- file.path("app", "data", paste0(s, ".csv.gz"))
  if (!file.exists(src)) stop("Missing ", src, " (task H-02).")
  lines <- readLines(src, encoding = "UTF-8", warn = FALSE)   # drops CR as well as LF
  con <- gzfile(dst, open = "wb", compression = 9)
  writeLines(lines, con, sep = "\n", useBytes = TRUE)
  close(con)
  cat(sprintf("%-14s %8d lines  %10s bytes -> %9s bytes\n", s, length(lines),
              format(file.size(src), big.mark = ","), format(file.size(dst), big.mark = ",")))
}
