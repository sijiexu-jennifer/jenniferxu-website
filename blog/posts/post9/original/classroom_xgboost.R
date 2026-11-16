# ============================================================
# XGBOOST STOCK PORTFOLIO
# Stocks: AAPL, TSLA, META, NVDA, GOOG
# ============================================================

# Run this once in Console if packages are not installed:
# install.packages(c(
#   "tidyverse", "tidyquant", "tidymodels",
#   "lubridate", "slider", "xgboost"
# ))

# ============================================================
# 1. LOAD PACKAGES
# ============================================================

library(tidyverse)
library(tidyquant)
library(tidymodels)
library(lubridate)
library(slider)
library(xgboost)

set.seed(123)


# ============================================================
# 2. SELECT STOCKS
# ============================================================

tickers <- c(
  "AAPL",
  "TSLA",
  "META",
  "NVDA",
  "GOOG"
)


# ============================================================
# 3. DOWNLOAD STOCK PRICES
# ============================================================

prices <- tq_get(
  tickers,
  get = "stock.prices",
  from = "2022-01-01",
  to = Sys.Date()
)

print(head(prices))


# ============================================================
# 4. DOWNLOAD S&P 500 DATA
# ============================================================

spy <- tq_get(
  "SPY",
  get = "stock.prices",
  from = "2022-01-01",
  to = Sys.Date()
) %>%
  select(
    date,
    spy_price = adjusted
  ) %>%
  arrange(date) %>%
  mutate(
    spy_ret = spy_price / lag(spy_price) - 1
  )


# ============================================================
# 5. CREATE PREDICTIVE FEATURES
# ============================================================

features <- prices %>%
  group_by(symbol) %>%
  arrange(date, .by_group = TRUE) %>%
  mutate(
    # Daily stock return
    stock_return = adjusted / lag(adjusted) - 1
  ) %>%
  ungroup() %>%
  
  # Add S&P 500 daily return
  left_join(
    spy %>% select(date, spy_ret),
    by = "date"
  ) %>%
  
  group_by(symbol) %>%
  arrange(date, .by_group = TRUE) %>%
  mutate(
    # One-month momentum
    mom_1m = lag(adjusted, 1) /
      lag(adjusted, 21) - 1,
    
    # Three-month momentum
    mom_3m = lag(adjusted, 1) /
      lag(adjusted, 63) - 1,
    
    # Six-month momentum
    mom_6m = lag(adjusted, 1) /
      lag(adjusted, 126) - 1,
    
    # Historical one-month volatility
    vol_1m = slide_dbl(
      lag(stock_return),
      sd,
      .before = 20,
      .complete = TRUE
    ),
    
    # Five-day return
    ret_5d = lag(adjusted, 1) /
      lag(adjusted, 5) - 1,
    
    # Return relative to the market
    excess_ret = stock_return - spy_ret
  ) %>%
  ungroup() %>%
  drop_na(
    mom_1m,
    mom_3m,
    mom_6m,
    vol_1m,
    ret_5d,
    excess_ret
  )


# ============================================================
# 6. CREATE TARGET
# Predict return from the next trading day through day 20
# ============================================================

model_data <- features %>%
  group_by(symbol) %>%
  arrange(date, .by_group = TRUE) %>%
  mutate(
    target = lead(adjusted, 20) /
      lead(adjusted, 1) - 1
  ) %>%
  ungroup() %>%
  drop_na(target)


# ============================================================
# 7. TRAIN AND TEST DATA
# ============================================================

train <- model_data %>%
  filter(date < as.Date("2024-01-01"))

test <- model_data %>%
  filter(date >= as.Date("2024-01-01"))

cat("\nTraining observations:", nrow(train))
cat("\nTesting observations:", nrow(test), "\n")


# ============================================================
# 8. PREPROCESSING
# ============================================================

xgb_recipe <- recipe(
  target ~
    mom_1m +
    mom_3m +
    mom_6m +
    vol_1m +
    ret_5d +
    excess_ret,
  data = train
)


# ============================================================
# 9. DEFINE XGBOOST MODEL
# ============================================================

xgb_spec <- boost_tree(
  trees = 300,
  tree_depth = 5,
  learn_rate = 0.05,
  loss_reduction = 0,
  min_n = 10
) %>%
  set_engine("xgboost") %>%
  set_mode("regression")


# ============================================================
# 10. TRAIN MODEL
# ============================================================

xgb_workflow <- workflow() %>%
  add_recipe(xgb_recipe) %>%
  add_model(xgb_spec)

xgb_fit <- fit(
  xgb_workflow,
  data = train
)

cat("\nXGBoost model training completed.\n")


# ============================================================
# 11. TEST-PERIOD PREDICTIONS
# ============================================================

preds <- predict(
  xgb_fit,
  new_data = test
) %>%
  bind_cols(test)


# ============================================================
# 12. CURRENT PREDICTIONS
# ============================================================

latest_features <- features %>%
  group_by(symbol) %>%
  slice_max(
    order_by = date,
    n = 1,
    with_ties = FALSE
  ) %>%
  ungroup()

latest_predictions <- predict(
  xgb_fit,
  new_data = latest_features
) %>%
  bind_cols(
    latest_features %>%
      select(date, symbol)
  ) %>%
  arrange(desc(.pred))


# ============================================================
# 13. CALCULATE XGBOOST PORTFOLIO WEIGHTS
# ============================================================

xgb_portfolio <- latest_predictions %>%
  slice_head(n = 5) %>%
  mutate(
    # Negative predictions receive zero weight
    positive_prediction = pmax(.pred, 0)
  )

positive_total <- sum(
  xgb_portfolio$positive_prediction
)

if (positive_total == 0) {
  
  # Use equal weights if every prediction is negative
  xgb_portfolio <- xgb_portfolio %>%
    mutate(weight = 1 / n())
  
} else {
  
  # Otherwise, weights are proportional to predicted returns
  xgb_portfolio <- xgb_portfolio %>%
    mutate(
      weight = positive_prediction /
        positive_total
    )
}


# ============================================================
# 14. CONVERT WEIGHTS TO $100,000
# ============================================================

total_amount <- 100000

xgb_allocation <- xgb_portfolio %>%
  transmute(
    Stock = symbol,
    Prediction_Date = date,
    Predicted_Return = round(.pred, 4),
    Weight = round(weight, 4),
    Percentage = round(weight * 100, 2),
    Dollar_Amount = round(
      weight * total_amount,
      2
    )
  )

# Correct any small rounding difference
xgb_allocation$Dollar_Amount[
  nrow(xgb_allocation)
] <- total_amount -
  sum(
    xgb_allocation$Dollar_Amount[
      -nrow(xgb_allocation)
    ]
  )

cat("\n")
cat("========================================\n")
cat("XGBOOST RECOMMENDED PORTFOLIO\n")
cat("========================================\n")

print(xgb_allocation)

cat(
  "\nTotal Investment: $",
  sum(xgb_allocation$Dollar_Amount),
  "\n"
)


# ============================================================
# 15. MONTHLY BACKTEST
# ============================================================

backtest <- preds %>%
  mutate(
    month = floor_date(date, "month")
  ) %>%
  group_by(month) %>%
  
  # Use the first trading day of each month
  filter(date == min(date)) %>%
  
  arrange(desc(.pred), .by_group = TRUE) %>%
  slice_head(n = 5) %>%
  
  mutate(
    positive_prediction = pmax(.pred, 0),
    positive_total = sum(positive_prediction),
    
    weight = if_else(
      positive_total == 0,
      1 / n(),
      positive_prediction / positive_total
    )
  ) %>%
  ungroup()


# ============================================================
# 16. CALCULATE BACKTEST RETURNS
# ============================================================

portfolio_returns <- backtest %>%
  group_by(month) %>%
  summarise(
    portfolio_return = sum(
      weight * target,
      na.rm = TRUE
    ),
    .groups = "drop"
  ) %>%
  arrange(month) %>%
  mutate(
    cumulative_return =
      cumprod(1 + portfolio_return)
  )


# ============================================================
# 17. CALCULATE SPY MONTHLY RETURNS
# ============================================================

spy_monthly <- spy %>%
  mutate(
    month = floor_date(date, "month")
  ) %>%
  group_by(month) %>%
  summarise(
    spy_return = prod(
      1 + replace_na(spy_ret, 0)
    ) - 1,
    .groups = "drop"
  ) %>%
  arrange(month) %>%
  mutate(
    spy_cumulative =
      cumprod(1 + spy_return)
  )


# ============================================================
# 18. JOIN PORTFOLIO AND SPY
# ============================================================

performance <- portfolio_returns %>%
  left_join(
    spy_monthly,
    by = "month"
  ) %>%
  drop_na(spy_return)


# ============================================================
# 19. PERFORMANCE STATISTICS
# ============================================================

rf_annual <- 0.0432

rf_monthly <- (
  1 + rf_annual
)^(1 / 12) - 1

xgb_sharpe_monthly <- mean(
  performance$portfolio_return -
    rf_monthly,
  na.rm = TRUE
) /
  sd(
    performance$portfolio_return,
    na.rm = TRUE
  )

xgb_sharpe_annualized <-
  xgb_sharpe_monthly * sqrt(12)

capm_model <- lm(
  I(portfolio_return - rf_monthly) ~
    I(spy_return - rf_monthly),
  data = performance
)

xgb_alpha_monthly <- coef(capm_model)[1]
xgb_beta <- coef(capm_model)[2]

xgb_alpha_annualized <-
  (1 + xgb_alpha_monthly)^12 - 1

cat("\n")
cat("========================================\n")
cat("XGBOOST PERFORMANCE RESULTS\n")
cat("========================================\n")

cat(
  "Expected Monthly Return:",
  round(
    mean(
      performance$portfolio_return,
      na.rm = TRUE
    ),
    4
  ),
  "\n"
)

cat(
  "Monthly Volatility:",
  round(
    sd(
      performance$portfolio_return,
      na.rm = TRUE
    ),
    4
  ),
  "\n"
)

cat(
  "Monthly Sharpe Ratio:",
  round(xgb_sharpe_monthly, 4),
  "\n"
)

cat(
  "Annualized Sharpe Ratio:",
  round(xgb_sharpe_annualized, 4),
  "\n"
)

cat(
  "CAPM Beta:",
  round(xgb_beta, 4),
  "\n"
)

cat(
  "Annualized Alpha:",
  round(xgb_alpha_annualized, 4),
  "\n"
)


# ============================================================
# 20. CUMULATIVE RETURN GRAPH
# ============================================================

ggplot(
  performance,
  aes(x = month)
) +
  geom_line(
    aes(
      y = cumulative_return,
      color = "XGBoost Portfolio"
    ),
    linewidth = 1.2
  ) +
  geom_line(
    aes(
      y = spy_cumulative,
      color = "S&P 500 (SPY)"
    ),
    linewidth = 1.2
  ) +
  labs(
    title = "XGBoost Portfolio vs. S&P 500",
    subtitle = "Out-of-Sample Backtest",
    x = "Date",
    y = "Growth of $1",
    color = ""
  ) +
  theme_minimal()

