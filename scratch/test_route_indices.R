library(dplyr)
source("scratch/test_city_switch.R") # defines build_city_network

net_jc <- build_city_network("jersey_city")
cat("net_jc routes length:", length(net_jc$route_list), "\n")
cat("net_jc pair_to_route_idx length:", length(net_jc$pair_to_route_idx), "\n")
print(head(net_jc$pair_to_route_idx, 5))

# Check route 0
r0 <- net_jc$route_list[[1]]
cat("Route 0 structure:\n")
print(r0)
cat("Route 0 JSON:\n")
print(jsonlite::toJSON(r0, auto_unbox = TRUE))

