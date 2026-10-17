# testme.R
#
# Start the dashboard locally with one command, run from the repo root:
#   Rscript app/testme.R
# Then open http://127.0.0.1:5763/ in a browser. Stop it with Ctrl+C.

shiny::runApp("app", host = "127.0.0.1", port = 5763, launch.browser = FALSE)
