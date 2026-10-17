mov_m <- readRDS("data/milwaukee.rds")
print(head(mov_m$time, 5))
cat("Class of time:", class(mov_m$time), "\n")
cat("Attr tzone:", attr(mov_m$time, "tzone"), "\n")
mov_j <- readRDS("data/jersey_city.rds")
cat("JC Attr tzone:", attr(mov_j$time, "tzone"), "\n")
mov_t <- readRDS("data/tampa.rds")
cat("Tampa Attr tzone:", attr(mov_t$time, "tzone"), "\n")

