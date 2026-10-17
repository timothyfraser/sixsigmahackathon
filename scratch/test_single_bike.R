library(shiny)
all_bike_ids <- c("TAMPA-B0001", "TAMPA-B0002")
bike_map <- setNames(seq_len(length(all_bike_ids)) - 1L, all_bike_ids)

sel_b_named <- bike_map["TAMPA-B0001"]
sel_b_unnamed <- unname(bike_map["TAMPA-B0001"])
sel_b_as_int <- as.integer(unname(bike_map["TAMPA-B0001"]))

cat("shiny:::toJSON(list(single_bike = sel_b_named)):\n")
cat(as.character(shiny:::toJSON(list(single_bike = sel_b_named))), "\n\n")

cat("shiny:::toJSON(list(single_bike = sel_b_as_int)):\n")
cat(as.character(shiny:::toJSON(list(single_bike = sel_b_as_int))), "\n\n")

