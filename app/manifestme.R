# manifestme.R
#
# Write manifest.json (the Posit Connect deployment manifest) for the dashboard.
# Run from the repo root:  Rscript app/manifestme.R
# Re-run it after any package change or any change to the bundled files, and commit the result.

if (!requireNamespace("rsconnect", quietly = TRUE)) {
  stop("Please install 'rsconnect' first: install.packages('rsconnect')")
}

# Exactly these files are bundled: app.R, every R file that app.R sources (read from its
# source("...") calls, so a new file such as sim.R can never be forgotten), and the built-in
# scenario copies (app/data/*.csv.gz, written by app/make_app_data.R). The run/deploy scripts stay out.
app_code <- readLines(file.path("app", "app.R"), warn = FALSE)
src_calls <- regmatches(app_code, regexpr("source\\(\"[^\"]+\\.R\"", app_code))
sourced <- unique(sub("^source\\(\"", "", sub("\"$", "", src_calls)))
app_files <- c("app.R", sourced,
               file.path("data", list.files(file.path("app", "data"), pattern = "\\.csv\\.gz$")))
message("Bundling: ", paste(app_files, collapse = ", "))
missing <- app_files[!file.exists(file.path("app", app_files))]
if (length(missing) > 0) stop("Missing in app/: ", paste(missing, collapse = ", "))
if (!any(grepl("^data/", app_files))) {
  stop("No app/data/*.csv.gz: run Rscript app/make_app_data.R first, or the deployed app has no data.")
}

# The manifest stores an MD5 per file. git stores the R files with LF line endings
# (.gitattributes: *.R eol=lf), so a Windows working copy with CRLF would give checksums that
# do not match the committed files. Rewrite any CRLF to LF first; the content is unchanged.
for (f in file.path("app", app_files[grepl("\\.R$", app_files)])) {
  raw <- readBin(f, "raw", file.size(f))
  if (any(raw == as.raw(13))) {
    writeBin(raw[raw != as.raw(13)], f)
    message("Normalised line endings to LF: ", f)
  }
}

rsconnect::writeManifest(appDir = "app", appFiles = app_files)

message("Done. manifest.json created in: ", normalizePath("app", winslash = "/"))
