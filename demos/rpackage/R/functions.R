# functions.R
# A script for containing your functions.

#' @name plus_one
#' @title Plus One
#' @description Function to add 1 to a numeric input vector and return a data.frame.
#' @author Tim Fraser, PhD
#' @param x (numeric) vector of 1 or more numeric values.
#' @note Adding `@import` below means this package will become accessible by package users
#' @import dplyr
#' @note Adding `@export` below means this function will become accessible by package users, rather than being an internal-only function.
#' @export
plus_one = function(x){
  output = tibble(y = x + 1)
  return(output)
} 