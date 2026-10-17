# deployme.R - Deploy bikesmart documentation to Posit Connect
# Reads credentials from gitignored .env (never commit credentials!)

env_file <- if (file.exists(".env")) ".env" else "../.env"
if (file.exists(env_file)) {
  readRenviron(env_file)
}

server_url <- Sys.getenv("CONNECT_SERVER")
api_key <- Sys.getenv("CONNECT_API_KEY")

if (server_url == "" || api_key == "") {
  stop("CONNECT_SERVER and CONNECT_API_KEY must be set in your .env file or environment.")
}

if (!requireNamespace("rsconnect", quietly = TRUE)) {
  stop("Please install 'rsconnect': install.packages('rsconnect')")
}

docs_dir <- if (dir.exists("docs")) "docs" else "bikesmart/docs"
if (!file.exists(file.path(docs_dir, "manifest.json"))) {
  stop("manifest.json not found in ", docs_dir, ". Run manifestme.R first.")
}

server_name <- "hackathon-connect"
rsconnect::addServer(url = server_url, name = server_name, quiet = TRUE)
rsconnect::connectApiUser(server = server_name, apiKey = api_key, quiet = TRUE)

message("Deploying documentation to Posit Connect...")
deploy_res <- rsconnect::deployApp(
  appDir = docs_dir,
  server = server_name,
  appName = "bikesmart-docs",
  appTitle = "bikesmart R Package Documentation",
  appMode = "static",
  lint = FALSE,
  launch.browser = FALSE
)

message("Deployment completed successfully!")

