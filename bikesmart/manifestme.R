# manifestme.R - Build docs and generate manifest.json for Posit Connect
# Run from repo root or package root:
pkg_dir <- if (file.exists("DESCRIPTION")) "." else "bikesmart"
docs_dir <- file.path(pkg_dir, "docs")

if (!requireNamespace("pkgdown", quietly = TRUE)) {
  stop("Please install 'pkgdown': install.packages('pkgdown')")
}
if (!requireNamespace("rsconnect", quietly = TRUE)) {
  stop("Please install 'rsconnect': install.packages('rsconnect')")
}

# Ensure pandoc is available if running under Positron / RStudio
if (Sys.getenv("RSTUDIO_PANDOC") == "") {
  positron_pandoc <- file.path(Sys.getenv("LOCALAPPDATA"), "Programs", "Positron", "resources", "app", "quarto", "bin", "tools")
  if (dir.exists(positron_pandoc)) {
    Sys.setenv(RSTUDIO_PANDOC = positron_pandoc)
  }
}

message("1. Building pkgdown site for ", pkg_dir, "...")
pkgdown::build_site(pkg = pkg_dir)

message("2. Generating manifest.json for ", docs_dir, "...")
rsconnect::writeManifest(appDir = docs_dir, appMode = "static")
message("Manifest generated successfully at ", file.path(docs_dir, "manifest.json"))

