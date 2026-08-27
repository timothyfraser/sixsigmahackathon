# deployme.R
#
# Deploy Plumber API to Posit Connect.
# This script targets Posit Connect (not Connect Cloud).

if (!requireNamespace("rsconnect", quietly = TRUE)) {
  stop("Please install 'rsconnect' first: install.packages('rsconnect')")
}

# Run this script from the `demos/plumber` folder.

# Build manifest for this API.
rsconnect::writeManifest(appDir = ".")

# Option A: If server/account is already configured in rsconnect:
rsconnect::deployApp(appDir = ".")

# Option B (commented): explicit Connect server + API key.
# rsconnect::addServer(url = Sys.getenv("CONNECT_SERVER"), name = "hackathon-connect")
# rsconnect::connectApiUser(
#   server = "hackathon-connect",
#   apiKey = Sys.getenv("CONNECT_API_KEY")
# )
# rsconnect::deployApp(appDir = ".", server = "hackathon-connect")
