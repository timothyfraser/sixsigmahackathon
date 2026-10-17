dist_jc <- read.csv("data/distances/jersey_city.csv")
st_jc <- read.csv("data/stations/jersey_city.csv")

# Create a distance lookup matrix
dmat <- matrix(0, 27, 27)
for (k in 1:nrow(dist_jc)) {
  i <- which(st_jc$dockID == dist_jc$dockID1[k])
  j <- which(st_jc$dockID == dist_jc$dockID2[k])
  if (length(i) == 1 && length(j) == 1) {
    dmat[i, j] <- dist_jc$distance[k]
  }
}

# For any pair (i, j), check if there is an intermediate station k that is on the path
# i.e. d(i, k) + d(k, j) is close to d(i, j)
cat("Sample pair City Hall (1) to Newport PATH (27):\n")
cat("Direct distance:", dmat[1, 27], "\n")
intermediates <- c()
for (k in 1:27) {
  if (k != 1 && k != 27) {
    diff <- (dmat[1, k] + dmat[k, 27]) - dmat[1, 27]
    if (diff < 0.05) { # within 0.05 miles of optimal!
      intermediates <- c(intermediates, paste0(st_jc$dockID[k], " (diff=", round(diff, 4), ")"))
    }
  }
}
cat("Intermediates on path:\n")
print(intermediates)

