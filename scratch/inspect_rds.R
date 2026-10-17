movement <- readRDS('data/tampa.rds')
cat('Total rows:', nrow(movement), '\n')
cat('DOCID == 0 rows:', sum(movement$DOCID == '0'), '\n')
cat('DOCID != 0 rows:', sum(movement$DOCID != '0'), '\n')
sub <- movement[movement$BIKEID == 'TAMPA-B0001', ]
cat('Rows for B0001:', nrow(sub), '\n')
# Find where DOCID changes for B0001
diff_idx <- which(sub$DOCID[-1] != sub$DOCID[-nrow(sub)])
cat('Transitions for B0001:\n')
for (idx in head(diff_idx, 10)) {
  print(sub[max(1, idx-1):min(nrow(sub), idx+2), ])
  cat('---\n')
}

