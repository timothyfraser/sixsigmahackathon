# manifestme.R
#
# Write manifest.json (the Posit Connect deployment manifest) for the dashboard.
# Run from the repo root:  Rscript app/manifestme.R

if (!requireNamespace("rsconnect", quietly = TRUE)) {
  stop("Please install 'rsconnect' first: install.packages('rsconnect')")
}

# The app folder (app.R, qc.R, prep.R, plots.R) is what gets bundled.
rsconnect::writeManifest(appDir = "app")

message("Done. manifest.json created in: ", normalizePath("app", winslash = "/"))
