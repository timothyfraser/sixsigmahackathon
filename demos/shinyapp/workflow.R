<<<<<<< HEAD


# test input data

input = list(n = 30, type = "chihuahua")
output = list(mydogs = NULL)


=======
# workflow.R

# An optional script that you use to linearly test your functions before you put them into a ShinyApp dashboard in app.R

# Start by creating a list object for `input` and `output`
# then fill them with test input and test output data.

# test input data
input = list(n = 30, type = "chihuahua")

# test output data
output = list(mydogs = NULL)

# your function
>>>>>>> 5eb5c25bfe39982f47746d6ad9b94d511ffc1e52
count_my_dogs = function(n, type){
  paste0(n, " ", type, "s")

}
<<<<<<< HEAD

output$mydogs = count_my_dogs(n = input$n, type = input$type)

=======
# perform the operation
output$mydogs = count_my_dogs(n = input$n, type = input$type)

# Check your output object
>>>>>>> 5eb5c25bfe39982f47746d6ad9b94d511ffc1e52
output
