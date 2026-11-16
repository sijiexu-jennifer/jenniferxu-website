BLOG POST 9 - Corrected classroom baseline

WHAT THIS VERSION DOES
This version evaluates the broad-universe instructor script confirmed by the user
as the code used for their Investopedia Simulator project. It replaces the earlier
five-stock analysis. The earlier files in original/ are background only.
The actual stock vector contains 95 names, despite its comment saying 100.
All 95 plus SPY were obtained with complete 2022-2025 daily coverage.
Data were retrieved November 16, 2026. Requested symbols and coverage are archived.

WEBSITE AND REPLICATION
index.qmd is the canonical article, using the same Quarto layout/CSS as Blog 6-8.
The article is generated from result CSVs by code/publish.R, not manually keyed.
Open the rendered website article at docs/blog/posts/post9/index.html.

Requirements: R, tidyverse, tidymodels, slider, xgboost, glue and readxl.
Optional fresh download: tidyquant (including quantmod). Rendering: Quarto.
Run from this post folder:
  Rscript code/analyze.R
  Rscript code/classroom.R
  Rscript code/publish.R
Then from the website root:
  quarto render blog/posts/post9/index.qmd --no-clean
The blog listing is updated by Quarto. Archived data require no network access.
Software versions are saved in results/sessionInfo.txt. Reference versions include
R 4.5.3, xgboost 3.2.1.1 and tidymodels 1.5.0. Seed 123 and one XGBoost thread.

FILES
  original/instructor_broad_universe_xgboost.R  Actual confirmed classroom source
  original/R_Crash_Course_Assignment.pdf       Classroom project design
  original/classroom_xgboost.R                Earlier five-stock file, not evaluated
  data/raw/prices.csv                         95 stocks + SPY, 96,288 rows
  data/raw/requested_tickers.txt              Exact classroom stock vector
  data/raw/coverage.csv                       Source coverage by ticker
  data/raw/classroom_results.xlsx             Supplied 45-team result workbook
  data/processed/model_data.csv               Features, targets and execution dates
  data/processed/test_predictions.csv         All held-out forecasts
  results/universe_audit.csv                  Included/excluded stocks
  results/audit.csv                           Temporal-boundary and sample audit
  results/tuning.csv                          Four preset validation candidates
  results/prediction_metrics.csv              Original, improved and mean forecasts
  results/weights.csv                         Each strategy/date/asset allocation
  results/backtest.csv                        Gross/net returns and wealth
  results/investment_metrics.csv              Investment performance statistics
  results/figures/                            Three article figures

ORIGINAL MODEL, SHARED REPAIRS AND IMPROVEMENT
The original model reproduces the actual script's 300 trees, depth 5, learning
rate .05, min child weight 10, gamma 0, and 14 actual recipe predictors:
open/high/low/close/volume/adjusted, stock return, SPY return, and six signals.
The original formula uses lagged past price / lagged recent price - 1, not the
opposite momentum ratio used in the earlier five-stock adaptation. It is preserved.
Volatility uses 22 lagged returns (.before=21), also preserved.
The recipe excludes date and symbol; stock_return renames the source's return.

Common main evaluation repairs:
* Labels must finish before the next training/validation/test boundary.
  1,900 source training labels otherwise finish in 2024. Purged final training has
  33,725 rows; the held-out test has 45,790 stock-date observations.
* Both models use top-ten selection, descending forecast, ticker tie-break.
  Positive forecasts determine weights; all-negative selections get 10% each.
* The source's scalar ifelse can recycle only its first calculated positive weight
  across the ten rows. We explicitly construct a normalized vector; no strategy
  is permitted to have weights summing to anything other than one.
* Signal close t, entry close t+1, exit close t+20; target has 19 return intervals.
  Signal dates are 19 trading intervals apart: contiguous holdings, no overlapping
  capital. All strategies use the same dates and market-price observations.
* SPY and stocks use identical holdings instead of mismatched calendar months.
* Annualization uses 252/19 periods/year, not sqrt(252) for monthly observations.
  Original diagnostic predictions preserve the unpurged classroom date split,
  named literal_classroom, and are not presented as valid out-of-sample evidence.

The improved model removes nominal price/volume inputs; keeps the six original
signals; adds current return, current 21-day momentum, SPY momentum/volatility,
and stock dummies. Two forward blocks Jan-Jun and Jul-Dec 2023 compare 100/300
trees x depths 1/2. Eta .03, min child weight 50 and subsample .8 are preset,
not test-tuned or exhaustively optimized. The selected model has 100 depth-one
trees. It is refitted once before testing. No adaptive test-period retraining.
This bundles feature changes and regularization, so their separate causal effects
cannot be inferred. Dates are a historical holdout, not a prospective deployment.

BENCHMARKS AND INVESTMENT METRICS
Forecast benchmark: pooled purged-training mean return. Investment benchmarks:
95-stock equal weights, rebalanced every holding period; and buy-and-hold SPY.
The positive common mean forecast would imply all-universe equal weighting if
applied without the arbitrary top-ten tie restriction; this is an independent
simple portfolio benchmark, not a claimed literal mean-forecast top-ten strategy.
All holdings are long-only, fully invested, unleveraged.
Cost = .001 x gross dollar purchases plus sales / wealth, using drifted holdings.
The cost is deducted before investing, with final liquidation charged as well.
Net period return = (1 - cost) x (1 + gross return) - 1.
There are 26 periods, Jan 3, 2024 - Dec 22, 2025. Forecast labels continue through
Dec 2, 2025; their exit prices are available through Dec 31.
Sharpe: period excess mean / period standard deviation x sqrt(252/19), using a
fixed 4.32% annual risk-free assumption converted to a 19-interval rate.
CAGR uses trading-time annualization. Drawdown includes starting wealth, sampled
at holding ends; daily drawdown may be worse. These are descriptive estimates,
not statistical proof or causal CAPM alpha.

SIMULATOR CONTEXT
The assignment specifies two virtual $100,000 portfolios and a planned two-month
horizon: intuition vs financial analysis, optimal weights and/or XGBoost.
The user confirms using the broad-universe XGBoost code for the analyzed portfolio.
User's group reported $99,093.21 vs $97,108.55. Execution dates, fills and final
simulator holdings are not supplied. No historical backtest reconstructs them.
Full-class workbook has 45 numeric pairs; its summaries are context only. The
113-team example in the PDF refers to a previous semester. Other teams' models
and holdings are unknown. Neither an AI shock nor technology concentration is
established as the explanation of this group's simulator loss.

LIMITATIONS
Fixed retrospectively selected surviving universe, revised adjusted prices,
assumed closing fills, no liquidity or spread model beyond stated costs, only
26 investment periods and overlapping daily forecast labels. The top-ten holdings
can remain concentrated despite the broad input universe. The improved model
slightly beats the forecast mean but has lower investment return and Sharpe than
the purged classroom model. Do not reuse the superseded five-stock conclusions.

SOURCES
https://finance.yahoo.com/quote/SPY/history/
https://in.help.yahoo.com/kb/adjusted-close-sln28256.html
https://xgboost.readthedocs.io/en/stable/parameter.html
User-supplied source files are retained in original/.
Local changes only: publication to GitHub is a separate step.
