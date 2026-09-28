library(ggplot2)
library(scales)

data_dir <- file.path("data", "derived")
figure_dir <- "figures"
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)

theme_blog <- function() {
  theme_minimal(base_size = 12) +
    theme(
      plot.title = element_text(face = "bold", size = 16),
      plot.subtitle = element_text(color = "#444444"),
      plot.caption = element_text(color = "#666666", hjust = 0),
      legend.position = "bottom",
      panel.grid.minor = element_blank()
    )
}

age <- read.csv(
  file.path(data_dir, "annual_age_group_lfpr.csv"),
  check.names = FALSE,
  fileEncoding = "UTF-8"
)
age$age_group <- factor(age$age_group, levels = c("16–24", "25–54", "55–64", "65+"))

p1 <- ggplot(age, aes(year, lfpr, color = age_group)) +
  geom_line(linewidth = 1) +
  scale_color_manual(values = c("#0072B2", "#009E73", "#E69F00", "#CC79A7")) +
  scale_x_continuous(breaks = seq(2000, 2024, 4)) +
  scale_y_continuous(labels = percent_format(accuracy = 1), limits = c(0.1, 0.9)) +
  labs(
    title = "U.S. Labor-Force Participation Has Diverged by Age",
    subtitle = "Annual averages of monthly weighted estimates, 2000–2024",
    x = NULL,
    y = "Labor-force participation rate",
    color = "Age group",
    caption = "Source: IPUMS CPS Basic Monthly Samples. Estimates use WTFINL."
  ) +
  theme_blog()

ggsave(file.path(figure_dir, "figure1-age-group-trends.png"), p1,
       width = 8.5, height = 5.3, dpi = 300, bg = "white")

sex <- read.csv(file.path(data_dir, "annual_prime_age_sex_lfpr.csv"))
sex$sex <- factor(sex$sex, levels = c("Men", "Women"))

p2 <- ggplot(sex, aes(year, lfpr, color = sex)) +
  geom_line(linewidth = 1.05) +
  scale_color_manual(values = c("#0072B2", "#D55E00")) +
  scale_x_continuous(breaks = seq(2000, 2024, 4)) +
  scale_y_continuous(labels = percent_format(accuracy = 1), limits = c(0.72, 0.94)) +
  labs(
    title = "The Prime-Age Gender Participation Gap Narrowed",
    subtitle = "Adults ages 25–54; annual averages of monthly weighted estimates",
    x = NULL,
    y = "Labor-force participation rate",
    color = NULL,
    caption = "Source: IPUMS CPS Basic Monthly Samples. Estimates use WTFINL."
  ) +
  theme_blog()

ggsave(file.path(figure_dir, "figure2-prime-age-by-sex.png"), p2,
       width = 8.5, height = 5.3, dpi = 300, bg = "white")

profile <- read.csv(file.path(data_dir, "selected_year_age_profiles.csv"))
profile <- subset(profile, year %in% c(2000, 2019, 2020, 2024))
profile$year <- factor(profile$year, levels = c(2000, 2019, 2020, 2024))
profile$age_midpoint <- (profile$age_start + profile$age_end) / 2

p3 <- ggplot(profile, aes(age_midpoint, lfpr, color = year)) +
  geom_line(linewidth = 1) +
  geom_point(size = 1.8) +
  scale_color_manual(values = c("#666666", "#0072B2", "#D55E00", "#009E73")) +
  scale_x_continuous(breaks = c(17.5, 27, 37, 47, 57, 67, 77), labels = c("16–19", "25–29", "35–39", "45–49", "55–59", "65–69", "75–79")) +
  scale_y_continuous(labels = percent_format(accuracy = 1), limits = c(0, 1)) +
  labs(
    title = "Participation Follows a Clear Life-Cycle Pattern",
    subtitle = "Five-year age groups in selected years",
    x = "Age group",
    y = "Labor-force participation rate",
    color = "Year",
    caption = "Source: IPUMS CPS Basic Monthly Samples. Estimates use WTFINL."
  ) +
  theme_blog()

ggsave(file.path(figure_dir, "figure3-life-cycle-profiles.png"), p3,
       width = 8.5, height = 5.3, dpi = 300, bg = "white")
