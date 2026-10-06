# Clean the World Bank panel, calculate summary statistics, and recreate figures.

library(dplyr)
library(tidyr)
library(readr)
library(ggplot2)
library(scales)

post_dir <- file.path("blog", "posts", "post4")
raw_file <- file.path(post_dir, "data", "raw", "wdi_download.csv")
derived_dir <- file.path(post_dir, "data", "derived")
figure_dir <- file.path(post_dir, "figures")

dir.create(derived_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)

wdi_raw <- read_csv(raw_file, show_col_types = FALSE)

panel <- wdi_raw |>
  filter(region != "Aggregates") |>
  transmute(
    iso3 = iso3c,
    country,
    year,
    region,
    income_group = income,
    gdp_per_capita,
    life_expectancy,
    population
  ) |>
  arrange(country, year)

stopifnot(anyDuplicated(panel[c("iso3", "year")]) == 0)
stopifnot(is.numeric(panel$gdp_per_capita))
stopifnot(is.numeric(panel$life_expectancy))
stopifnot(is.numeric(panel$population))

write_csv(panel, file.path(derived_dir, "world_bank_panel.csv"), na = "")

region_colors <- c(
  "East Asia & Pacific" = "#2A6F97",
  "Europe & Central Asia" = "#6A4C93",
  "Latin America & Caribbean" = "#D97706",
  "Middle East, North Africa, Afghanistan & Pakistan" = "#B23A48",
  "North America" = "#4D908E",
  "South Asia" = "#7F8F3A",
  "Sub-Saharan Africa" = "#777777"
)

theme_blog <- function() {
  theme_minimal(base_size = 12) +
    theme(
      plot.background = element_rect(fill = "#FFFDF8", color = NA),
      panel.background = element_rect(fill = "#FFFDF8", color = NA),
      plot.title = element_text(size = 18, face = "bold", margin = margin(b = 5)),
      plot.subtitle = element_text(color = "#666666", margin = margin(b = 14)),
      plot.caption = element_text(color = "#666666", hjust = 0),
      panel.grid.minor = element_blank(),
      panel.grid.major = element_line(color = "#DED8CC", linewidth = 0.35),
      legend.title = element_blank()
    )
}

# Figure 1: cross-sectional relationship in 2023.
latest <- panel |>
  filter(
    year == 2023,
    population >= 1e6,
    between(life_expectancy, 35, 90)
  ) |>
  drop_na(gdp_per_capita, life_expectancy, population)

label_countries <- c("USA", "CHN", "IND", "JPN", "BRA", "NGA", "ZAF", "DEU")

p1 <- ggplot(latest, aes(gdp_per_capita, life_expectancy)) +
  geom_point(
    aes(size = population, color = region),
    alpha = 0.72,
    stroke = 0.25
  ) +
  geom_text(
    data = latest |> filter(iso3 %in% label_countries),
    aes(label = country),
    size = 3.1,
    nudge_y = 0.55,
    check_overlap = TRUE,
    show.legend = FALSE
  ) +
  scale_x_log10(labels = label_dollar(scale_cut = cut_short_scale())) +
  scale_size_continuous(range = c(2, 19), guide = "none") +
  scale_color_manual(values = region_colors) +
  labs(
    title = "Richer countries tend to live longer, but the curve flattens",
    subtitle = "Countries with at least 1 million people, 2023",
    x = "GDP per capita, constant 2021 international dollars (log scale)",
    y = "Life expectancy at birth (years)"
  ) +
  theme_blog() +
  theme(legend.position = "bottom", legend.text = element_text(size = 8)) +
  guides(color = guide_legend(nrow = 2, byrow = TRUE))

ggsave(
  file.path(figure_dir, "01_income_life_expectancy.png"),
  p1,
  width = 10.5,
  height = 7,
  dpi = 180,
  bg = "#FFFDF8"
)

# Figure 2: change in life expectancy among the ten largest countries.
largest_changes <- panel |>
  filter(year %in% c(2000, 2023)) |>
  select(iso3, country, year, population, life_expectancy) |>
  pivot_wider(
    names_from = year,
    values_from = c(population, life_expectancy),
    names_glue = "{.value}_{year}"
  ) |>
  drop_na(life_expectancy_2000, life_expectancy_2023, population_2023) |>
  filter(
    between(life_expectancy_2000, 35, 90),
    between(life_expectancy_2023, 35, 90)
  ) |>
  slice_max(population_2023, n = 10, with_ties = FALSE) |>
  mutate(
    gain = life_expectancy_2023 - life_expectancy_2000,
    country = reorder(country, life_expectancy_2023)
  )

p2 <- ggplot(largest_changes, aes(y = country)) +
  geom_segment(
    aes(x = life_expectancy_2000, xend = life_expectancy_2023, yend = country),
    linewidth = 1.5,
    color = "#C8C2B8"
  ) +
  geom_point(aes(x = life_expectancy_2000, color = "2000"), size = 3.3) +
  geom_point(aes(x = life_expectancy_2023, color = "2023"), size = 3.7) +
  geom_text(
    aes(x = life_expectancy_2023, label = sprintf("%+.1f", gain)),
    hjust = -0.25,
    size = 3.2,
    color = "#176B5B"
  ) +
  scale_color_manual(values = c("2000" = "#999990", "2023" = "#176B5B")) +
  scale_x_continuous(expand = expansion(mult = c(0.04, 0.12))) +
  labs(
    title = "Most large countries added years of life",
    subtitle = "The ten most populous countries in 2023; labels show change since 2000",
    x = "Life expectancy at birth (years)",
    y = NULL
  ) +
  theme_blog() +
  theme(legend.position = c(0.93, 0.12), panel.grid.major.y = element_blank())

ggsave(
  file.path(figure_dir, "02_largest_country_changes.png"),
  p2,
  width = 9.4,
  height = 6.3,
  dpi = 180,
  bg = "#FFFDF8"
)

# Figure 3: changes in income and life expectancy from 2000 to 2023.
changes <- panel |>
  filter(year %in% c(2000, 2023)) |>
  select(iso3, country, region, year, gdp_per_capita, life_expectancy, population) |>
  pivot_wider(
    names_from = year,
    values_from = c(gdp_per_capita, life_expectancy, population),
    names_glue = "{.value}_{year}"
  ) |>
  drop_na(
    gdp_per_capita_2000,
    gdp_per_capita_2023,
    life_expectancy_2000,
    life_expectancy_2023,
    population_2023
  ) |>
  filter(
    population_2023 >= 1e6,
    gdp_per_capita_2000 > 0,
    between(life_expectancy_2000, 35, 90),
    between(life_expectancy_2023, 35, 90)
  ) |>
  mutate(
    gdp_growth_pct = (gdp_per_capita_2023 / gdp_per_capita_2000 - 1) * 100,
    life_gain = life_expectancy_2023 - life_expectancy_2000
  ) |>
  filter(between(gdp_growth_pct, -80, 1200))

change_labels <- bind_rows(
  changes |> slice_max(life_gain, n = 3),
  changes |> slice_min(life_gain, n = 3),
  changes |> filter(iso3 %in% c("CHN", "IND", "USA"))
) |>
  distinct(iso3, .keep_all = TRUE)

p3 <- ggplot(changes, aes(gdp_growth_pct, life_gain)) +
  geom_hline(yintercept = 0, color = "#AAA59C", linewidth = 0.4) +
  geom_point(aes(color = region), size = 2.7, alpha = 0.75) +
  geom_smooth(method = "lm", se = FALSE, linetype = "dashed", color = "#2F2F2F", linewidth = 0.7) +
  geom_text(
    data = change_labels,
    aes(label = country),
    nudge_y = 0.45,
    size = 3.1,
    check_overlap = TRUE,
    show.legend = FALSE
  ) +
  scale_color_manual(values = region_colors, guide = "none") +
  labs(
    title = "Income growth alone does not predict health gains very well",
    subtitle = "Countries with at least 1 million people in 2023",
    x = "Change in real GDP per capita, 2000-2023 (%)",
    y = "Change in life expectancy, 2000-2023 (years)"
  ) +
  theme_blog()

ggsave(
  file.path(figure_dir, "03_growth_vs_health.png"),
  p3,
  width = 10.5,
  height = 6.3,
  dpi = 180,
  bg = "#FFFDF8"
)

summary_statistics <- tibble(
  statistic = c(
    "cross_section_year",
    "cross_section_countries",
    "income_life_expectancy_correlation",
    "change_countries",
    "growth_health_correlation",
    "largest_country_median_gain_years"
  ),
  value = c(
    2023,
    nrow(latest),
    cor(latest$gdp_per_capita, latest$life_expectancy),
    nrow(changes),
    cor(changes$gdp_growth_pct, changes$life_gain),
    median(largest_changes$gain)
  )
)

write_csv(summary_statistics, file.path(derived_dir, "summary_statistics.csv"))

print(summary_statistics)
