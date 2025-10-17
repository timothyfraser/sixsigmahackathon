

# test input data

input = list(n = 30, type = "chihuahua")
output = list(mydogs = NULL)


count_my_dogs = function(n, type){
  paste0(n, " ", type, "s")

}

output$mydogs = count_my_dogs(n = input$n, type = input$type)

output
