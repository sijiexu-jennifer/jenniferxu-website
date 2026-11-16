library(readxl)
library(ggplot2)
library(tidyverse)
results <- read_excel("/Users/yisroelcahn/Documents/BEPP 2800/Full_Results copy.xlsx")

#fix format
results$portfolio1 <- as.numeric(as.character(results$portfolio1))
results$portfolio2 <- as.numeric(as.character(results$portfolio2))

#boxplot
plot_data <- results |>
  pivot_longer(
    cols = c(portfolio1, portfolio2),
    names_to = "Portfolio",
    values_to = "Value"
  )

ggplot(plot_data, aes(x = Portfolio, y = Value)) +
  geom_boxplot(fill = "lightgray", width = 0.5) +
  labs(
    title = "Final Portfolio Values",
    x = "",
    y = "Portfolio Value ($)"
  ) +
  theme_classic(base_size = 14)

cor_results=cor(results$portfolio1,results$portfolio2)

plot(
  results$portfolio1,
  results$portfolio2,
  pch = 19,
  col = "gray40",
  xlab = "Intuition-Based Portfolio",
  ylab = "Indicator-Based Portfolio",
  main = "Relationship Between Portfolio Outcomes"
)

abline(lm(portfolio2 ~ portfolio1, data = results), lwd = 2)

legend(
  "topleft",
  legend = paste("Correlation =", round(cor_results, 2)),
  bty = "n"
)

#table
# Summary statistics
n <- sum(complete.cases(results$portfolio1, results$portfolio2))

mean1 <- mean(results$portfolio1, na.rm = TRUE)
sd1 <- sd(results$portfolio1, na.rm = TRUE)
median1 <- median(results$portfolio1, na.rm = TRUE)

mean2 <- mean(results$portfolio2, na.rm = TRUE)
sd2 <- sd(results$portfolio2, na.rm = TRUE)
median2 <- median(results$portfolio2, na.rm = TRUE)

# Correlation
corr <- cor(results$portfolio1, results$portfolio2, use = "complete.obs")

# Paired t-test
tt <- t.test(results$portfolio1,
             results$portfolio2,
             paired = TRUE)

# Display results
cat("Number of Teams:", n, "\n\n")

cat("Portfolio 1\n")
cat("Mean:", mean1, "\n")
cat("SD:", sd1, "\n")
cat("Median:", median1, "\n\n")

cat("Portfolio 2\n")
cat("Mean:", mean2, "\n")
cat("SD:", sd2, "\n")
cat("Median:", median2, "\n\n")

cat("Correlation:", corr, "\n\n")

cat("Paired t-test\n")
print(tt)

#differences
# Create difference variables
results$difference  <- results$portfolio2 - results$portfolio1 

# Compute means and sample sizes
diff_summary <- data.frame(
  School = c("results"),
  Mean_Difference = c(mean(results$difference, na.rm = TRUE)),
  N = c(sum(!is.na(results$difference)))
)

# View table
print(diff_summary)

# results paired t-test
t_results <- t.test(results$portfolio2, results$portfolio1,
                paired = TRUE,
                alternative = "greater")

# View results
t_results

#regression
values <- c(results$portfolio1, results$portfolio2)

# Create dummy variable D: 0 for portfolio1, 1 for portfolio2
D <- c(rep(0, nrow(results)), rep(1, nrow(results)))

# Create a new data frame for regression
data <- data.frame(values, D)

# Run the regression of returns on D
model <- lm(values ~ D, data = data)

# View the summary of the regression
summary(model)

plot(D, values, 
     xlab = "Portfolio (0 = portfolio1, 1 = portfolio2)", 
     ylab = "Values", 
     main = "Values vs Portfolio Dummy", 
     pch = 16, col = "blue")

# Add regression line
abline(model, col = "red", lwd = 2)

#unpaired
t_test <- t.test(results$portfolio1, results$portfolio2, 
                 alternative = "two.sided", var.equal = FALSE)

t_test


# Bootstrap standard error for the mean difference
set.seed(123)
B <- 10000

# Paired differences (Portfolio 2 - Portfolio 1)
diff <- results$portfolio2 - results$portfolio1
n <- length(diff)

# Bootstrap the mean difference
boot_means <- replicate(B, {
  sample_diff <- sample(diff, size = n, replace = TRUE)
  mean(sample_diff)
})

# Results
cat("Mean Difference:", mean(diff), "\n")
cat("Bootstrap SE:", sd(boot_means), "\n")
cat("95% Bootstrap CI:", quantile(boot_means, c(0.025, 0.975)), "\n")

#2-sided p-value
observed_diff <- mean(diff)

p_value <- mean(
  abs(boot_means - observed_diff) >= abs(observed_diff)
)

cat("Bootstrap p-value:", p_value, "\n")

#1-sided p-value
p_value <- mean(
  boot_means - observed_diff >= observed_diff
)

cat("One-sided bootstrap p-value:", p_value, "\n")




