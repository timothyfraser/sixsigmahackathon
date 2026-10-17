dist_mke <- read.csv("data/distances/milwaukee.csv")
st_mke <- read.csv("data/stations/milwaukee.csv")

N <- nrow(st_mke)
dmat <- matrix(Inf, N, N)
diag(dmat) <- 0

for (k in 1:nrow(dist_mke)) {
  i <- which(st_mke$dockID == dist_mke$dockID1[k])
  j <- which(st_mke$dockID == dist_mke$dockID2[k])
  if (length(i) == 1 && length(j) == 1) {
    dmat[i, j] <- dist_mke$distance[k]
  }
}

direct_count <- 0
one_intermediate_count <- 0

for (i in 1:N) {
  for (j in 1:N) {
    if (i == j) next
    d_direct <- dmat[i, j]
    best_diff <- Inf
    for (k in 1:N) {
      if (k != i && k != j) {
        diff <- (dmat[i, k] + dmat[k, j]) - d_direct
        if (diff < best_diff) {
          best_diff <- diff
        }
      }
    }
    if (best_diff < 0.05) {
      one_intermediate_count <- one_intermediate_count + 1
    } else {
      direct_count <- direct_count + 1
    }
  }
}

cat("Milwaukee: out of 702 pairs:\n")
cat("Direct/adjacent street pairs:", direct_count, "\n")
cat("Turn/via intermediate station pairs:", one_intermediate_count, "\n")

