# Run from the project root: Rscript code/analyze.R
suppressPackageStartupMessages({library(tidyverse); library(tidymodels); library(slider); library(xgboost)})
set.seed(123)
dir.create('results/figures', recursive=TRUE, showWarnings=FALSE)
if (!file.exists('data/raw/prices.csv')) stop('Run code/download.R first.')
p <- read_csv('data/raw/prices.csv',show_col_types=FALSE)
stopifnot(!anyDuplicated(p[c('symbol','date')]), all(p$adjusted>0))
# Exact classroom list has 95 names (despite the comment saying 100).
requested<-readLines('data/raw/requested_tickers.txt')
calendar<-sort(unique(p$date[p$symbol=='SPY']))
coverage<-p |> group_by(symbol) |> summarise(rows=n_distinct(date),.groups='drop')
usable<-coverage |> filter(rows==length(calendar),symbol!='SPY') |> pull(symbol)
status<-tibble(symbol=requested,status=ifelse(requested %in% usable,'included','unavailable or incomplete 2022-2025 coverage; excluded'))
write_csv(status,'results/universe_audit.csv')
p<-p |> filter(symbol %in% c(usable,'SPY'))
N<-length(usable);stopifnot(N>=70)
market <- p |> filter(symbol=='SPY') |> arrange(date) |> mutate(spy_ret=adjusted/lag(adjusted)-1, market_mom=adjusted/lag(adjusted,21)-1, market_vol=slide_dbl(spy_ret,sd,.before=20,.complete=TRUE)) |> select(date,spy_ret,market_mom,market_vol)
d <- p |> filter(symbol!='SPY') |> group_by(symbol) |> arrange(date,.by_group=TRUE) |> mutate(stock_return=adjusted/lag(adjusted)-1) |> ungroup() |> left_join(market,by='date') |> group_by(symbol) |> arrange(date,.by_group=TRUE) |> mutate(
 mom_1m=lag(adjusted,21)/lag(adjusted)-1,
 mom_3m=lag(adjusted,63)/lag(adjusted)-1,
 mom_6m=lag(adjusted,126)/lag(adjusted)-1,
 vol_1m=slide_dbl(lag(stock_return),sd,.before=21,.complete=TRUE),
 ret_5d=lag(adjusted,5)/lag(adjusted)-1,
 excess_ret=stock_return-spy_ret,
 ret_1d=stock_return,
 mom_recent=adjusted/lag(adjusted,21)-1,
 target=lead(adjusted,20)/lead(adjusted,1)-1,
 entry=lead(date,1),end=lead(date,20)) |> ungroup() |> drop_na()
signal_vars <- c('mom_1m','mom_3m','mom_6m','vol_1m','ret_5d','excess_ret')
# recipe(target ~ .) in the actual script retains OHLC, volume, adjusted price,
# return and spy_ret as well as six engineered signals; date and symbol are IDs.
base_vars <- c('open','high','low','close','volume','adjusted','stock_return','spy_ret',signal_vars)
new_vars <- c(signal_vars,'ret_1d','mom_recent','market_mom','market_vol','symbol')
fit_model <- function(dat, vars, trees=300, depth=5, rate=.05, min_n=10, sample=1) {
 rec <- recipe(reformulate(vars,response='target'),data=dat)
 if ('symbol' %in% vars) rec <- rec |> step_dummy(all_nominal_predictors())
 spec <- boost_tree(trees=trees,tree_depth=depth,learn_rate=rate,loss_reduction=0,min_n=min_n,sample_size=sample) |> set_engine('xgboost',nthread=1,seed=123) |> set_mode('regression')
 set.seed(123)
 workflow() |> add_recipe(rec) |> add_model(spec) |> fit(data=dat)
}
cutoff <- as.Date('2024-01-01')
# A label is usable only after its exit date. This purges the boundary.
tr <- d |> filter(date<cutoff,end<cutoff)
te <- d |> filter(date>=cutoff,end<=as.Date('2025-12-31'))
stopifnot(max(tr$end)<min(te$date))
# Tune on two forward validation blocks, never the test set.
grid <- expand_grid(trees=c(100L,300L),depth=c(1L,2L),rate=.03,min_n=50L,sample=.8)
folds <- tibble(start=as.Date(c('2023-01-01','2023-07-01')),stop=as.Date(c('2023-07-01','2024-01-01')))
scores <- list()
for(i in seq_len(nrow(grid))) {
 g<-grid[i,]; errors<-c()
 for(j in seq_len(nrow(folds))) {
  train_f <- d |> filter(end<folds$start[j])
  valid_f <- d |> filter(date>=folds$start[j],end<folds$stop[j])
  stopifnot(max(train_f$end)<min(valid_f$date))
  f<-fit_model(train_f,new_vars,g$trees,g$depth,g$rate,g$min_n,g$sample)
  errors<-c(errors,(predict(f,valid_f)$.pred-valid_f$target)^2)
 }
 scores[[i]]<-bind_cols(g,tibble(validation_rmse=sqrt(mean(errors))))
}
tuning<-bind_rows(scores) |> arrange(validation_rmse)
write_csv(tuning,'results/tuning.csv')
g<-tuning[1,]
original<-fit_model(tr,base_vars)
improved<-fit_model(tr,new_vars,g$trees,g$depth,g$rate,g$min_n,g$sample)
# Diagnostic only: literal classroom split contains labels realized in January 2024.
leaky_tr<-d |> filter(date<cutoff)
literal<-fit_model(leaky_tr,base_vars)
te<-te |> mutate(original=predict(original,te)$.pred,improved=predict(improved,te)$.pred,mean_benchmark=mean(tr$target),literal_classroom=predict(literal,te)$.pred)
write_csv(te,'data/processed/test_predictions.csv')
write_csv(d,'data/processed/model_data.csv')
base_mse<-mean((te$target-te$mean_benchmark)^2)
metrics<-map_dfr(c('mean_benchmark','original','improved','literal_classroom'),function(m) tibble(model=m,RMSE=sqrt(mean((te[[m]]-te$target)^2)),MAE=mean(abs(te[[m]]-te$target)),direction=mean((te[[m]]>0)==(te$target>0)),OOS_R2=1-mean((te[[m]]-te$target)^2)/base_mse))
write_csv(metrics,'results/prediction_metrics.csv')
# Signal after close t; trade at close t+1; exit at close t+20.
# Next signal t+19, next entry t+20: contiguous, nonoverlapping holdings.
all_dates<-sort(unique(p$date))
first_idx<-match(min(te$date),all_dates)
signal_dates<-all_dates[seq(first_idx,length(all_dates)-20,by=19)]
stopifnot(all(signal_dates %in% te$date))
models<-c('original','improved','equal_weight','SPY')
out<-list(); weights<-list()
for(m in models) {
 prev<-rep(0,N+1) # usable classroom universe plus SPY, initially all cash
 for(k in seq_along(signal_dates)) {
  z<-te |> filter(date==signal_dates[k]) |> arrange(symbol)
  stopifnot(nrow(z)==N)
  spy_entry<-p |> filter(symbol=='SPY',date==z$entry[1]) |> pull(adjusted)
  spy_exit<-p |> filter(symbol=='SPY',date==z$end[1]) |> pull(adjusted)
  asset_r<-c(z$target,spy_exit/spy_entry-1)
  if(m=='SPY') w<-c(rep(0,N),1) else if(m=='equal_weight') w<-c(rep(1/N,N),0) else {
   # Same top-ten positive-proportional allocation for both models.
   # Fix classroom scalar ifelse recycling: explicitly assign a length-ten vector.
   top<-order(-z[[m]],z$symbol)[1:10]
   positive<-pmax(z[[m]][top],0)
   w<-rep(0,N+1)
   w[top]<-if(sum(positive)==0) rep(.1,10) else positive/sum(positive)
  }
  stopifnot(abs(sum(w)-1)<1e-10,all(w>=0))
  traded<-sum(abs(w-prev)) # gross purchases plus sales per dollar of wealth
  gross<-sum(w*asset_r)
  # Deduct trading costs before investing. Final liquidation charged below.
  net<-(1-.001*traded)*(1+gross)-1
  if(k==length(signal_dates)) net<-(1+net)*(1-.001)-1
  out[[length(out)+1]]<-tibble(model=m,signal=signal_dates[k],entry=z$entry[1],end=z$end[1],gross=gross,net=net,traded=traded)
  weights[[length(weights)+1]]<-tibble(model=m,signal=signal_dates[k],symbol=c(z$symbol,'SPY'),weight=w)
  prev<-w*(1+asset_r)/(1+gross)
 }
}
back<-bind_rows(out) |> group_by(model) |> arrange(end,.by_group=TRUE) |> mutate(wealth=cumprod(1+net),gross_wealth=cumprod(1+gross)) |> ungroup()
stopifnot(all(back$net> -1),all(back$traded>=0))
# Include initial wealth in maximum drawdown. Risk-free assumption fixed at 4.32%.
annual_factor<-252/19
rf_period<-(1+.0432)^(19/252)-1
invest<-back |> group_by(model) |> summarise(periods=n(),gross_total=prod(1+gross)-1,net_total=prod(1+net)-1,CAGR=prod(1+net)^(annual_factor/n())-1,annual_vol=sd(net)*sqrt(annual_factor),Sharpe=mean(net-rf_period)/sd(net)*sqrt(annual_factor),max_drawdown=min(c(1,wealth)/cummax(c(1,wealth))-1),avg_traded=mean(traded),.groups='drop')
write_csv(back,'results/backtest.csv');write_csv(bind_rows(weights),'results/weights.csv');write_csv(invest,'results/investment_metrics.csv')
write_csv(tibble(item=c('universe_size','train_rows','test_rows','train_last_label','test_first_signal','test_last_signal','leaking_classroom_labels'),value=as.character(c(N,nrow(tr),nrow(te),as.character(max(tr$end)),as.character(min(te$date)),as.character(max(te$date)),sum(leaky_tr$end>=cutoff)))),'results/audit.csv')
writeLines(capture.output(sessionInfo()),'results/sessionInfo.txt')
# Figures use percentages and a consistent restrained palette.
cols<-c(original='#A65336',improved='#126E82',equal_weight='#747C80',SPY='#9569AD',mean_benchmark='#747C80')
label<-c(original='Original specification (purged)',improved='Improved XGBoost',equal_weight='Equal-weight stock universe',SPY='SPY',mean_benchmark='Training-mean forecast')
theme_set(theme_minimal(base_size=12)+theme(panel.grid.minor=element_blank(),plot.title=element_text(face='bold'),plot.background=element_rect(fill='white',color=NA)))
f1<-metrics |> filter(model!='literal_classroom') |> mutate(model=factor(model,levels=c('mean_benchmark','original','improved'))) |> ggplot(aes(model,RMSE*100,fill=model))+geom_col(width=.6)+geom_text(aes(label=sprintf('%.2f',RMSE*100)),vjust=-.5)+scale_fill_manual(values=cols)+scale_x_discrete(labels=label)+labs(title='Does a more cautious model forecast better?',subtitle='Held-out 2024-2025; lower error is better',x=NULL,y='RMSE (percentage points of holding-period return)',caption='Same stocks, target and test observations. Overlapping forecast labels are not independent.')+theme(legend.position='none',axis.text.x=element_text(size=10))+expand_limits(y=max(metrics$RMSE)*113)
ggsave('results/figures/01_forecast_error.png',f1,width=9,height=5,dpi=180)
curves<-bind_rows(back |> select(model,date=end,wealth),tibble(model=models,date=min(back$entry),wealth=1))
f2<-ggplot(curves,aes(date,wealth,color=model))+geom_line(linewidth=.9)+scale_color_manual(values=cols,labels=label)+labs(title='What would $1 have become?',subtitle='Identical execution dates; 10 bp per dollar traded, including entry and liquidation',x=NULL,y='Wealth after trading costs',color=NULL,caption='Retrospective simulation, fixed classroom stock universe. Forecast after close; enter next close.')+theme(legend.position='bottom',legend.text=element_text(size=9))+guides(color=guide_legend(nrow=2))
ggsave('results/figures/02_wealth.png',f2,width=9,height=5.5,dpi=180)
f3<-back |> group_by(model) |> arrange(end,.by_group=TRUE) |> mutate(drawdown=wealth/pmax(1,cummax(wealth))-1) |> ungroup() |> ggplot(aes(end,drawdown*100,color=model))+geom_line(linewidth=.9)+scale_color_manual(values=cols,labels=label)+labs(title='A high ending balance can hide substantial losses',x=NULL,y='Drawdown from previous peak (%)',color=NULL,caption='Net returns; peak includes the initial $1.')+theme(legend.position='bottom',legend.text=element_text(size=9))+guides(color=guide_legend(nrow=2))
ggsave('results/figures/03_drawdown.png',f3,width=9,height=5.5,dpi=180)
print(metrics); print(invest); print(tuning);cat('Usable stocks:',N,'\n')
