dist_jc <- read.csv("data/distances/jersey_city.csv")
st_jc <- read.csv("data/stations/jersey_city.csv")

N <- nrow(st_jc)
dmat <- matrix(Inf, N, N)
diag(dmat) <- 0

for (k in 1:nrow(dist_jc)) {
  i <- which(st_jc$dockID == dist_jc$dockID1[k])
  j <- which(st_jc$dockID == dist_jc$dockID2[k])
  if (length(i) == 1 && length(j) == 1) {
    dmat[i, j] <- dist_jc$distance[k]
  }
}

# For all 702 pairs:
direct_count <- 0
one_intermediate_count <- 0
multi_intermediate_count <- 0

for (i in 1:N) {
  for (j in 1:N) {
    if (i == j) next
    d_direct <- dmat[i, j]
    # find best intermediate
    best_diff <- Inf
    best_k <- -1
    for (k in 1:N) {
      if (k != i && k != j) {
        diff <- (dmat[i, k] + dmat[k, j]) - d_direct
        if (diff < best_diff) {
          best_diff <- diff
          best_k <- k
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

cat("Jersey City: out of 702 pairs:\n")
cat("Direct/adjacent street pairs:", direct_count, "\n")
cat("Turn/via intermediate station pairs:", one_intermediate_count, "\n")

