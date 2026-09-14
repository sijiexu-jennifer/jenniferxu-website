# Run once if needed:
# install.packages(c("dplyr", "ggplot2", "patchwork", "xgboost"))

library(dplyr)
library(ggplot2)
library(patchwork)
library(xgboost)

set.seed(20260914)
n <- 3000

# -----------------------------------------------------------------------------
# Simulate student data
# -----------------------------------------------------------------------------
# This is a simulated dataset, not real student records. In the data-generating
# process, one extra study hour truly raises college GPA by 0.075 points.

students <- tibble(
  student_id = 1:n,
  high_school_gpa = 2 + 2 * rbeta(n, shape1 = 3.5, shape2 = 2.8),
  sleep_hours = pmin(9, pmax(4.5, rnorm(n, mean = 7, sd = 0.8))),
  stress = rnorm(n)
) |>
  mutate(
    attendance = pmin(
      100,
      pmax(55, 74 + 7 * (high_school_gpa - 3) - 2 * stress + rnorm(n, 0, 7))
    ),
    # Students with weaker preparation or lower attendance tend to study more.
    study_hours = 28 - 6 * high_school_gpa +
      0.06 * (100 - attendance) +
      0.8 * stress +
      0.7 * (sleep_hours - 7)^2 +
      rnorm(n, 0, 1.6),
    study_hours = pmin(24, pmax(1, study_hours)),
    # The true causal effect of study_hours is positive: +0.075 per hour.
    college_gpa_raw = -1.25 +
      0.075 * study_hours +
      0.95 * high_school_gpa +
      0.006 * attendance +
      0.06 * sleep_hours -
      0.05 * stress^2 +
      rnorm(n, 0, 0.25),
    college_gpa = pmin(4, pmax(0, college_gpa_raw)),
    preparation_group = cut(
      high_school_gpa,
      breaks = quantile(high_school_gpa, probs = c(0, 1/3, 2/3, 1)),
      include.lowest = TRUE,
      labels = c("Lower prior GPA", "Middle prior GPA", "Higher prior GPA")
    )
  )

# -----------------------------------------------------------------------------
# Naive and adjusted regressions
# -----------------------------------------------------------------------------
naive_model <- lm(college_gpa ~ study_hours, data = students)

adjusted_model <- lm(
  college_gpa ~ study_hours + high_school_gpa + attendance +
    sleep_hours + I((sleep_hours - 7)^2) + stress + I(stress^2),
  data = students
)

cat("\nNaive regression:\n")
print(summary(naive_model)$coefficients["study_hours", ])

cat("\nAdjusted regression:\n")
print(summary(adjusted_model)$coefficients["study_hours", ])

# -----------------------------------------------------------------------------
# Double machine learning, written out explicitly
# -----------------------------------------------------------------------------
# DML first predicts GPA and study hours from the observed background variables.
# Cross-fitting means each prediction is made by a model that did not train on
# that student's observation.

X <- model.matrix(
  ~ high_school_gpa + attendance + sleep_hours + stress - 1,
  data = students
)
Y <- students$college_gpa
D <- students$study_hours

set.seed(20260914)
K <- 5
fold_id <- sample(rep(1:K, length.out = n))
y_residual <- rep(NA_real_, n)
d_residual <- rep(NA_real_, n)

xgb_params <- list(
  objective = "reg:squarederror",
  max_depth = 3,
  eta = 0.05,
  subsample = 0.8,
  colsample_bytree = 0.9,
  nthread = 1
)

for (k in 1:K) {
  train_index <- fold_id != k
  test_index <- fold_id == k

  y_model <- xgb.train(
    params = xgb_params,
    data = xgb.DMatrix(X[train_index, ], label = Y[train_index]),
    nrounds = 150,
    verbose = 0
  )

  d_model <- xgb.train(
    params = xgb_params,
    data = xgb.DMatrix(X[train_index, ], label = D[train_index]),
    nrounds = 150,
    verbose = 0
  )

  y_residual[test_index] <- Y[test_index] -
    predict(y_model, xgb.DMatrix(X[test_index, ]))
  d_residual[test_index] <- D[test_index] -
    predict(d_model, xgb.DMatrix(X[test_index, ]))
}

# The DML estimate is the relationship between the two cross-fitted residuals.
dml_estimate <- sum(d_residual * y_residual) / sum(d_residual^2)
dml_score <- d_residual * (y_residual - dml_estimate * d_residual)
dml_se <- sqrt(
  mean(dml_score^2) /
    (n * mean(d_residual^2)^2)
)

cat("\nDML estimate:", round(dml_estimate, 3), "\n")
cat("DML 95% CI:",
    round(dml_estimate - 1.96 * dml_se, 3), "to",
    round(dml_estimate + 1.96 * dml_se, 3), "\n")

# -----------------------------------------------------------------------------
# Figures
# -----------------------------------------------------------------------------
p1 <- ggplot(
  students,
  aes(x = study_hours, y = college_gpa, color = preparation_group)
) +
  geom_point(alpha = 0.28, size = 1.6) +
  geom_smooth(
    aes(group = 1),
    method = "lm",
    formula = y ~ x,
    se = FALSE,
    color = "#D73027",
    linewidth = 1.3
  ) +
  scale_color_manual(values = c("#E69F00", "#56B4E9", "#0072B2")) +
  labs(
    title = "Do more study hours really lower GPA?",
    subtitle = "The red line is the misleading relationship from a naive regression",
    x = "Weekly study hours",
    y = "College GPA",
    color = "Academic preparation"
  ) +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom")

extract_estimate <- function(model, label) {
  estimate <- coef(model)["study_hours"]
  interval <- confint(model, "study_hours", level = 0.95)
  tibble(
    method = label,
    estimate = unname(estimate),
    lower = interval[1],
    upper = interval[2]
  )
}

estimates <- bind_rows(
  extract_estimate(naive_model, "Naive regression"),
  extract_estimate(adjusted_model, "Adjusted regression"),
  tibble(
    method = "Double machine learning",
    estimate = dml_estimate,
    lower = dml_estimate - 1.96 * dml_se,
    upper = dml_estimate + 1.96 * dml_se
  ),
  tibble(
    method = "True effect used in simulation",
    estimate = 0.075,
    lower = 0.075,
    upper = 0.075
  )
) |>
  mutate(method = factor(method, levels = rev(method)))

p2 <- ggplot(estimates, aes(x = estimate, y = method)) +
  geom_vline(xintercept = 0, color = "grey65", linetype = "dashed") +
  geom_errorbar(
    aes(xmin = lower, xmax = upper),
    width = 0.18,
    orientation = "y"
  ) +
  geom_point(size = 3, color = "#0072B2") +
  labs(
    title = "The sign flips after accounting for background",
    subtitle = "Estimated GPA change from one additional weekly study hour",
    x = "Estimated effect on college GPA",
    y = NULL
  ) +
  theme_minimal(base_size = 12)

final_figure <- p1 / p2 + plot_annotation(
  title = "A lesson in omitted variable bias"
)

print(final_figure)
ggsave("bp1_gpa_ovb_figure.png", final_figure, width = 9, height = 9, dpi = 300)

# Save the simulated data so the analysis can be reproduced exactly.
write.csv(students, "bp1_gpa_simulated_data.csv", row.names = FALSE)
