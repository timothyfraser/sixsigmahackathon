# H-02: deterministic simulated scenario generator. Run: Rscript data/generate_data.R
set.seed(20261016)
out <- if (dir.exists('data')) 'data' else '.'
cols <- c('table','data_source','station_id','station_name','latitude','longitude','capacity','region','timestamp','bikes_available','docks_available','is_renting','is_returning','attempt_id','attempt_type','success','failure_reason','task_id','van_id','source_station_id','destination_station_id','planned_quantity','actual_quantity','assigned_at','arrived_at','completed_at','status')
# Mutable row storage avoids repeatedly copying a growing list.
rows <- new.env(hash=TRUE, parent=emptyenv()); row_count <- 0L
add <- function(...) { x <- as.list(c(...)); y <- setNames(as.list(rep('',length(cols))),cols); for(k in names(x)) y[[k]] <- as.character(x[[k]]); y$table <- as.character(x$table); y$data_source <- 'simulated'; row_count <<- row_count + 1L; assign(as.character(row_count), y, envir=rows) }
# ISO 8601 with a +-HH:MM offset (e.g. -04:00), as docs/methods.md section 7 requires; %z alone gives -0400.
fmt <- function(t) sub('([+-][0-9]{2})([0-9]{2})$','\\1:\\2',format(t,'%Y-%m-%dT%H:%M:%S%z',tz='America/New_York'))
dates <- seq(as.Date('2026-09-21'),as.Date('2026-10-16'),by='day'); dates <- dates[as.POSIXlt(dates)$wday %in% 1:5]
run <- function(scenario) {
 rows <<- new.env(hash=TRUE, parent=emptyenv()); row_count <<- 0L; edge <- scenario=='edge_case'; n <- if(edge) 2L else 25L; ds <- if(edge) dates[1] else dates
 cap <- rep(20L,n); ids <- sprintf('S%03d',seq_len(n)); regions <- rep(c('Residential','Office','Mixed'),length.out=n)
 for(s in seq_len(n)) add(table='stations',station_id=ids[s],station_name=paste('Demo Station',s),latitude=sprintf('%.5f',42.4400+(s%%5)*.004),longitude=sprintf('%.5f',-76.5000+(s%/%5)*.004),capacity=cap[s],region=regions[s])
 aid <- 0L; tid <- 0L
 for(d in seq_along(ds)) {
  day <- ds[d]; start <- as.POSIXct(paste(day,'06:00:00'),tz='America/New_York')
  # Each station shares the same minute timestamps; format them once per day.
  stamps <- vapply(0:300, function(m) fmt(start+m*60), character(1))
  for(s in seq_len(n)) {
   bike <- if(edge) if(s==1) 10L else 1L else if(regions[s]=='Office') 14L else 8L
   for(m in 0:300) {
    tm <- start+m*60; hh <- 6L + m %/% 60L
    rush <- hh>=7 && hh<10
    shifted <- scenario=='planted_shift' && d>=11 && rush
    if(m>0 && m<300) {
     change <- sample(c(-1L,0L,1L),1,prob=if(shifted) c(.72,.23,.05) else if(rush && regions[s]=='Residential') c(.42,.48,.10) else c(.17,.66,.17))
     bike <- max(0L,min(20L,bike+change))
    }
    renting <- TRUE; returning <- !(shifted && s<=8 && m>=75 && m<240)
    if(shifted && s<=8 && rush) bike <- 20L
    if(edge && s==1) bike <- 10L
    # edge: missing snapshot, a conflicting pair, and a stale gap
    if(edge && s==2 && m %in% c(65L,70L,71L,72L,73L)) next
    add(table='status',station_id=ids[s],timestamp=stamps[m+1L],bikes_available=bike,docks_available=20L-bike,is_renting=renting,is_returning=returning)
    if(edge && s==2 && m==66L) add(table='status',station_id=ids[s],timestamp=stamps[m+1L],bikes_available=2L,docks_available=18L,is_renting=TRUE,is_returning=TRUE)
    if(edge && s==2 && m==66L) add(table='status',station_id=ids[s],timestamp=stamps[m+1L],bikes_available=3L,docks_available=17L,is_renting=TRUE,is_returning=TRUE)
    if(m>=60 && m<240) {
     attempts_n <- if(edge) 1L else if(shifted) 3L else sample(0:2,1)
     for(j in seq_len(attempts_n)) {
      aid <- aid+1L; typ <- if(j%%2==1) 'rent' else 'return'
      reason <- if(typ=='rent' && bike==0L) 'no_bike' else if(typ=='return' && (bike==20L || !returning)) if(!returning) 'station_closed' else 'no_dock' else ''
      # Planted return failures, with a clear maintenance cause
      if(shifted && s<=8 && typ=='return') reason <- 'dock_fault'
      add(table='attempts',station_id=ids[s],attempt_id=sprintf('A%08d',aid),timestamp=stamps[m+1L],attempt_type=typ,success=if(reason=='') 'TRUE' else 'FALSE',failure_reason=reason)
     }
    }
   }
  }
  if(!edge) for(v in 1:3) {
   tid <- tid+1L; t0 <- as.POSIXct(paste(day,sprintf('08:%02d:00',v*10)),tz='America/New_York')
   add(table='tasks',task_id=sprintf('T%05d',tid),van_id=paste0('V',((v-1)%%2)+1),source_station_id=ids[20+v],destination_station_id=ids[v],planned_quantity=3L,actual_quantity=3L,assigned_at=fmt(t0),arrived_at=fmt(t0+60*(8+v)),completed_at=fmt(t0+60*(13+v)),status='completed')
  }
 }
 df <- as.data.frame(do.call(rbind,lapply(mget(as.character(seq_len(row_count)), envir=rows, inherits=FALSE),function(x) unlist(x[cols]))),stringsAsFactors=FALSE); names(df) <- cols
 write.table(df,file=file.path(out,paste0(scenario,'.csv')),sep=',',row.names=FALSE,col.names=TRUE,quote=TRUE,na='',fileEncoding='UTF-8')
 cat(scenario,nrow(df),'rows\n')
}
for(s in c('baseline','planted_shift','edge_case')) run(s)
