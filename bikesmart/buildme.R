# buildme.R
# -------------------------------------------------------------------------
# PURPOSE: Developer workflow script for building and testing the bikesmart
# R package locally. This script is NOT part of the package itself (it is
# listed in .Rbuildignore). Run it interactively, section by section, in
# RStudio or from the repo root with Rscript.
#
# Prerequisites (install once if you haven't already):
#   install.packages(c("devtools", "roxygen2", "testthat"))
#
# IMPORTANT: Run this from the repository root, not from inside
# deliverables/bikesmart/. The setwd() line below handles that.
# -------------------------------------------------------------------------

# --- 0. Point R at the package directory ----------------------------------
# Change this path if your repo is in a different location.
PKG_DIR <- "bikesmart"
setwd(PKG_DIR)

# --- 1. Unload and remove any previously installed version ---------------
# (Safe to skip on first install; will warn if not installed yet.)
try(unloadNamespace("bikesmart"), silent = TRUE)
try(remove.packages("bikesmart"),  silent = TRUE)

# --- 2. Auto-document: turn roxygen2 comments into man/ pages and NAMESPACE
# Run this any time you add or change @param, @return, @export tags in R/.
devtools::document(".")

# --- 3. Load the package temporarily for interactive testing --------------
# This is faster than install + library() during development.
devtools::load_all(".")

# --- 4. Quick smoke tests -------------------------------------------------
# These should all produce results without errors.

# 4a. get_bike_availability: 1 bike, lam_out = lam_in = 1 -> ~0.6065
bikesmart::get_bike_availability(b0 = 1, lam_out = 1, lam_in = 1)

# 4b. get_slot_availability: 9 bikes, capacity 10, lam_out = lam_in = 1
bikesmart::get_slot_availability(b0 = 9, capacity = 10, lam_out = 1, lam_in = 1)

# 4c. recommend_dock: DockB (20 min, p=0.95) should win over DockA (10 min, p=0.61)
candidates <- data.frame(
  dock_id = c("DockA", "DockB"),
  minutes = c(10, 20),
  p       = c(0.61, 0.95)
)
bikesmart::recommend_dock(candidates, threshold = 0.90)

# 4d. dock_distances: filter the Atlantis grid (no internet needed)
grid <- read.csv("../../data/distances/atlantis.csv",
                  colClasses = c("character", "character", "numeric"))
bikesmart::dock_distances(grid, from = "Atlantis Dock 01", max_miles = 1)

# 4e. aggregate_snapshots: use a small RDS slice
movement <- readRDS("../../data/jersey_city.rds")
movement_small <- movement[movement$time == movement$time[1], ]
stations <- read.csv("../../data/stations/jersey_city.csv",
                      colClasses = "character")
bikesmart::aggregate_snapshots(movement_small, stations)

# --- 5. Unload before building -------------------------------------------
unloadNamespace("bikesmart")

# --- 6. Build the source tarball -----------------------------------------
# Creates bikesmart_0.1.0.tar.gz in deliverables/bikesmart/
devtools::document(".")
devtools::build(pkg = ".", path = getwd(), binary = FALSE, vignettes = FALSE)

# --- 7. Restart R (RStudio only) -----------------------------------------
# Clears the namespace so the fresh install is clean.
# rstudioapi::restartSession()   # uncomment if running in RStudio

# --- 8. Install from the built tarball ------------------------------------
install.packages("bikesmart_0.1.0.tar.gz", type = "source", repos = NULL)

# --- 9. Verify installed package ------------------------------------------
library("bikesmart")
bikesmart::get_bike_availability(b0 = 1, lam_out = 1, lam_in = 1)

# --- 10. Clean up ---------------------------------------------------------
unloadNamespace("bikesmart")
remove.packages("bikesmart")
rm(list = ls())
gc()

