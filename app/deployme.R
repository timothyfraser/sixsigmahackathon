# deployme.R
#
# Deploy the dashboard to the course Posit Connect server (not Connect Cloud).
# Run from the repo root:  Rscript app/deployme.R
# Set two environment variables first (never write them into a file):
#   CONNECT_SERVER  the server URL        CONNECT_API_KEY  your publisher key

if (!requireNamespace("rsconnect", quietly = TRUE)) {
  stop("Please install 'rsconnect' first: install.packages('rsconnect')")
}

server_url <- Sys.getenv("CONNECT_SERVER")
api_key <- Sys.getenv("CONNECT_API_KEY")
if (server_url == "" || api_key == "") {
  stop("Set the CONNECT_SERVER and CONNECT_API_KEY environment variables first.")
}

rsconnect::addServer(url = server_url, name = "hackathon-connect")
rsconnect::connectApiUser(server = "hackathon-connect", apiKey = api_key)

rsconnect::writeManifest(appDir = "app")
rsconnect::deployApp(appDir = "app", server = "hackathon-connect")
