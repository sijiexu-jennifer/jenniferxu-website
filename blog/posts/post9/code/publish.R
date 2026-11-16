# Generate the Quarto article directly from computed CSV results.
suppressPackageStartupMessages({library(tidyverse);library(glue)})
a<-read_csv('results/prediction_metrics.csv',show_col_types=FALSE)
b<-read_csv('results/investment_metrics.csv',show_col_types=FALSE)
g<-read_csv('results/tuning.csv',show_col_types=FALSE)[1,]
u<-read_csv('results/universe_audit.csv',show_col_types=FALSE)
N<-sum(u$status=='included')
f<-function(m,col) sprintf('%.2f',100*a[a$model==m,col,drop=TRUE])
v<-function(m,col) sprintf('%.1f',100*b[b$model==m,col,drop=TRUE])
s<-function(m) sprintf('%.2f',b$Sharpe[b$model==m])
num_test<-nrow(read_csv('data/processed/test_predictions.csv',show_col_types=FALSE))
leaking<-read_csv('results/audit.csv',show_col_types=FALSE) |> filter(item=='leaking_classroom_labels') |> pull(value)
rows<-paste(vapply(c('mean_benchmark','original','improved'),function(m) paste0('| ',c(mean_benchmark='Training mean',original='Classroom model, purged',improved='Improved XGBoost')[[m]],' | ',f(m,'RMSE'),' | ',f(m,'MAE'),' | ',f(m,'direction'),'% | ',sprintf('%.3f',a$OOS_R2[a$model==m]),' |'),character(1)),collapse='\n')
invrows<-paste(vapply(c('original','improved','equal_weight','SPY'),function(m) paste0('| ',c(original='Classroom model, purged',improved='Improved',equal_weight='Equal-weight 95 stocks',SPY='SPY')[[m]],' | ',v(m,'net_total'),'% | ',s(m),' | ',v(m,'max_drawdown'),'% |'),character(1)),collapse='\n')
article<-glue('---
title: "Better Forecasts, Better Investments?"
subtitle: "Revisiting our Investopedia experiment with gradient boosting"
author: "Jennifer Xu"
date: "2026-11-11"
image: results/figures/01_forecast_error.png
categories:
  - Machine Learning
  - Finance
  - R
page-layout: article
navbar: false
page-footer: false
format:
  html:
    toc: false
    code-fold: true
    code-tools: true
    css: styles.css
    fig-cap-location: bottom
execute:
  eval: false
resources:
  - code/**
  - data/**
  - results/**
  - README.txt
  - replication.zip
---

::: {.eyebrow}
STOCK RETURNS AND MACHINE LEARNING
:::

Our classroom project used **Investopedia Simulator** to compare two virtual portfolios, each starting with **$100,000**, over a planned two-month horizon. One used intuition; the other used financial analysis. Our group used the supplied broad-universe XGBoost script for the analytical portfolio. Reported final values were **$99,093.21** and **$97,108.55**: returns of -0.91% and -2.89%. Analysis trailed by 1.98 percentage points. Could a more cautious model improve its predictions and investment decisions?

The class workbook provides context: analysis finished ahead for 30 of 45 teams, but teams could use different indicators or methods. Without their holdings and exact execution dates, these outcomes cannot isolate XGBoost skill. The historical backtest below is a separate experiment, not a reconstruction of our simulator trades.

## What the classroom model actually does

The confirmed script lists **95 stocks across multiple sectors**, despite a comment describing 100. Its recipe retains open, high, low, close, volume, adjusted price, daily return and SPY return, alongside six engineered momentum, volatility and relative-return signals. Stock identity and date are excluded from prediction. The target is adjusted price at t+20 divided by price at t+1, minus one: **19 trading intervals**.

Gradient boosting adds trees sequentially to correct the existing ensemble. The classroom model uses 300 trees, depth five and learning rate 0.05. It ranks stocks, selects the top ten, and assigns weights proportional to positive forecasts; all-negative selections receive equal weights.

## Why try a simpler model?

The concern is overfitting, not a prior conclusion that the original model fails. Although pooling stocks produces many rows, training covers only 2022-2023; common market shocks and overlapping return windows reduce independent information. Complex trees may learn temporary patterns rather than stable relationships.

I remove raw price levels and volume, retaining return-based signals and adding stock identity, current-day return, current 21-day momentum, and market momentum and volatility. These provide stock-specific and market context without relying on nominal price scales. Shallower trees allow fewer interacting conditions; smaller updates and stricter split requirements restrain noise fitting.

Two forward validation blocks in 2023 compare 100 or 300 trees at depth one or two, selecting **<<g$trees>> trees, depth <<g$depth>>**. Learning rate 0.03, minimum child weight 50 and 80% row subsampling are preset conservative choices, not exhaustively tuned. The 2024-2025 test set does not select parameters.

## Evaluating without looking ahead

Yahoo Finance data cover 2022-2025; all <<N>> requested stocks have complete coverage. The main classroom-model comparator preserves its inputs, formulas and hyperparameters, but removes <<leaking>> training labels whose outcomes cross into 2024. Validation boundaries are purged similarly. A literal classroom-split diagnostic is saved separately.

Both strategies form signals after close, enter at the next close and hold for 19 intervals. Holdings are contiguous and nonoverlapping. I correct the original scalar `ifelse` weight-recycling issue so weights sum to one, align SPY holding windows, and use holding-period rather than daily annualization. These shared evaluation repairs are distinct from changing the prediction model.

## What changed in predictive performance?

Across **<<format(num_test,big.mark=",",trim=TRUE)>> held-out stock-date forecasts**, RMSE falls from **<<f("original","RMSE")>>** to **<<f("improved","RMSE")>> percentage points**. RMSE penalizes large errors. The training-mean benchmark achieves **<<f("mean_benchmark","RMSE")>>** points, so improvement over this simple rule is small: out-of-sample R-squared is **<<sprintf("%.3f",a$OOS_R2[a$model=="improved"])>>**, about 0.9% less squared error. Direction accuracy still trails the always-positive mean forecast. This is limited descriptive evidence, not proof of persistent predictability.

| Forecast | RMSE (pp) | MAE (pp) | Direction accuracy | OOS R² |
|:--|--:|--:|--:|--:|
<<rows>>

::: {.column-screen-inset}
![Forecast errors on the same held-out stock-date observations. Daily target windows overlap.](results/figures/01_forecast_error.png)
:::

## Do better forecasts make better investments?

Both models retain the top-ten allocation rule. Benchmarks hold the entire stock universe equally weighted, rebalanced on the same dates, or SPY. Costs are **10 basis points per dollar bought or sold**, including initial entry and final liquidation, using drifted pretrade weights. There are 26 holdings, January 3, 2024 through December 22, 2025.

Net returns are **<<v("original","net_total")>>%** for the classroom model and **<<v("improved","net_total")>>%** for the improved model, versus **<<v("equal_weight","net_total")>>%** for equal-weight stocks and **<<v("SPY","net_total")>>%** for SPY. Annualized Sharpe ratios are **<<s("original")>>** and **<<s("improved")>>**, assuming a fixed 4.32% annual risk-free rate. Better average prediction accuracy did not produce a better portfolio: the strategy depends on ranking and weighting just ten stocks, while RMSE evaluates every forecast.

| Strategy | Net total return | Annualized Sharpe | Holding-boundary max drawdown |
|:--|--:|--:|--:|
<<invrows>>

::: {.column-screen-inset}
![Growth of $1 after assumed trading costs, using identical execution dates.](results/figures/02_wealth.png)
:::

::: {.column-screen-inset}
![Drawdowns measured at holding boundaries; losses between boundaries can be deeper.](results/figures/03_drawdown.png)
:::

## Takeaway

Unexpected news, competition and changing relationships make returns difficult to forecast. The broad input universe does not guarantee a diversified top-ten portfolio; sector and position concentration require the actual holdings. Without simulator trade records, I cannot attribute our classroom loss to technology exposure or an AI-related shock.

This retrospective test uses a fixed list of surviving companies and only 26 investment periods. Historical adjustments and assumed closing-price execution also limit realism. The more conservative model improves forecast error, but lowers realized return and Sharpe. Model complexity, forecast accuracy and investment usefulness are different questions—and each needs its own benchmark.

## Data and reproducibility

Prices: [Yahoo Finance](https://finance.yahoo.com/quote/SPY/history/), retrieved November 16, 2026, archived for 2022-2025. Adjusted close reflects [splits and dividends](https://in.help.yahoo.com/kb/adjusted-close-sln28256.html). See [XGBoost parameters](https://xgboost.readthedocs.io/en/stable/parameter.html).

The original source is `original/instructor_broad_universe_xgboost.R`, confirmed as the script used for our simulator project. `R_Crash_Course_Assignment.pdf` specifies the project design. The earlier five-stock adaptation is retained only as background and is not used for these results. The 113-team example in the assignment describes a previous semester; the supplied workbook contains 45 teams.

[Download the complete replication project](replication.zip), [README](README.txt), [analysis code](code/analyze.R), [forecast results](results/prediction_metrics.csv), [investment results](results/investment_metrics.csv), or [portfolio holdings](results/weights.csv). Source: [my website repository](https://github.com/sijiexu-jennifer/jenniferxu-website).

```bash
Rscript code/analyze.R
Rscript code/classroom.R
Rscript code/publish.R
quarto render index.qmd
```

No new download is needed. `publish.R` generates this Quarto source from saved results; render it in the existing website to retain its established styling. Holdings and entry/exit dates are saved. Sharpe annualization uses 252/19 periods per year; drawdown is sampled at holding ends. Initial and final costs are charged to every strategy. No formal significance or causal-alpha claim is made.
',.open='<<',.close='>>')
writeLines(article,'index.qmd')
writeLines(article,'blog_post9_text.txt')
write_csv(tibble(portfolio=c('Intuition','Analysis using XGBoost'),initial_value=100000,ending_value=c(99093.21,97108.55),return=c(99093.21,97108.55)/100000-1),'results/classroom_results.csv')
cat('Quarto source rebuilt from the corrected classroom experiment.\n')
