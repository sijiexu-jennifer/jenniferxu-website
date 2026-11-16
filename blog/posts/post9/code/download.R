suppressPackageStartupMessages({library(tidyquant);library(tidyverse)})
requested<-c(readLines('data/raw/requested_tickers.txt'),'SPY')
p<-if(file.exists('data/raw/prices.csv')) read_csv('data/raw/prices.csv',show_col_types=FALSE) else tibble()
failures<-list()
for(sym in setdiff(requested,unique(p$symbol))) {
 cat('Downloading ',sym,'\n');flush.console()
 z<-tryCatch(tq_get(sym,from='2022-01-01',to='2026-01-01'),error=function(e) NULL)
 if(is.data.frame(z) && nrow(z)>0 && 'adjusted' %in% names(z)) {
  p<-bind_rows(p,z);write_csv(p,'data/raw/prices.csv')
 } else failures[[length(failures)+1]]<-tibble(symbol=sym,status='Unavailable from Yahoo at retrieval; excluded, not replaced')
}
write_csv(bind_rows(failures),'data/raw/download_failures.csv')
write_csv(p |> group_by(symbol) |> summarise(rows=n(),first=min(date),last=max(date),.groups='drop'),'data/raw/coverage.csv')
cat('Downloaded symbols:',n_distinct(p$symbol),'Rows:',nrow(p),'\n')
