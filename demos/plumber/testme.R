# testme.R
#
# Run the local Plumber API from this demo folder.
# Run this script from the `demos/plumber` folder.

library(plumber)
plumb("plumber.R") %>% pr_run(port = 5762)