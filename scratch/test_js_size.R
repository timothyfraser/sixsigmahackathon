library(jsonlite)
s <- toJSON(data.frame(a=1:27))
r <- toJSON(replicate(702, list(lats=c(1,2), lons=c(3,4), n=2, w1=1), simplify=FALSE))
cat('s size:', nchar(s), '\n')
cat('r size:', nchar(r), '\n')
js <- paste0('window.stationsData = ', s, ';\nwindow.routesData = ', r, ';')
cat('Total js size:', nchar(js), '\n')

