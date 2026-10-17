library(dplyr)
st <- read.csv("data/stations/jersey_city.csv")
print(st[, c("dockID", "lat", "lon")])

