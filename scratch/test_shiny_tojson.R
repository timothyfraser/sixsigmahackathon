library(shiny)

# Shiny uses shiny:::toJSON or jsonlite with specific options
# Let's inspect shiny:::toJSON:
df <- data.frame(a = 1:3, b = c("x", "y", "z"))
m <- matrix(1:4, 2, 2)

cat("shiny:::toJSON(df):\n")
cat(as.character(shiny:::toJSON(df)), "\n\n")

cat("shiny:::toJSON(list(trips = df, dock_mat = m)):\n")
cat(as.character(shiny:::toJSON(list(trips = df, dock_mat = m))), "\n\n")

