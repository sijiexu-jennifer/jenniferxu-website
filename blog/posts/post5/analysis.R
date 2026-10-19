#!/usr/bin/env Rscript

# Blog Post 5: GIS Data Visualization
# Downloads official Census county estimates and cartographic boundaries,
# constructs county growth and migration measures, and creates all figures.

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(ggplot2)
  library(scales)
  library(xml2)
})

dir.create("data/raw", recursive = TRUE, showWarnings = FALSE)
dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
dir.create("figures", recursive = TRUE, showWarnings = FALSE)

urls <- c(
  population = paste0(
    "https://www2.census.gov/programs-surveys/popest/datasets/",
    "2020-2025/counties/totals/co-est2025-alldata.csv"
  ),
  counties = paste0(
    "https://www2.census.gov/geo/tiger/GENZ2025/kml/",
    "cb_2025_us_county_20m.zip"
  ),
  states = paste0(
    "https://www2.census.gov/geo/tiger/GENZ2025/kml/",
    "cb_2025_us_state_20m.zip"
  )
)

destinations <- c(
  population = "data/raw/co-est2025-alldata.csv",
  counties = "data/raw/cb_2025_us_county_20m.zip",
  states = "data/raw/cb_2025_us_state_20m.zip"
)

download_with_snapshot <- function(url, destination) {
  temporary <- tempfile(pattern = "census_", tmpdir = "data/raw")
  downloaded <- tryCatch({
    download.file(url, temporary, mode = "wb", quiet = TRUE)
    if (file.info(temporary)$size == 0) stop("Empty download")
    file.rename(temporary, destination)
    TRUE
  }, error = function(e) FALSE, warning = function(w) FALSE)
  if (file.exists(temporary)) unlink(temporary)

  if (!downloaded && !file.exists(destination)) {
    stop("Download failed and no saved snapshot exists: ", destination)
  }
  if (!downloaded) message("Using saved snapshot: ", destination)
}

invisible(Map(download_with_snapshot, urls, destinations))

county_kml <- "data/raw/cb_2025_us_county_20m.kml"
state_kml <- "data/raw/cb_2025_us_state_20m.kml"
if (!file.exists(county_kml)) {
  unzip(destinations[["counties"]], files = basename(county_kml), exdir = "data/raw")
}
if (!file.exists(state_kml)) {
  unzip(destinations[["states"]], files = basename(state_kml), exdir = "data/raw")
}

# County measures. SUMLEV 050 selects counties; county 000 rows are state totals.
# Rates are annual averages across the five complete intervals, 2020-21 through
# 2024-25. Census component rates are already expressed per 1,000 residents.
county_data <- read_csv(destinations[["population"]],
                        locale = locale(encoding = "windows-1252"),
                        col_types = cols(.default = col_double(),
                                         STNAME = col_character(),
                                         CTYNAME = col_character())) |>
  filter(SUMLEV == 50, !STATE %in% c(2, 15, 60, 66, 69, 72, 78)) |>
  mutate(
    geoid = sprintf("%02d%03d", STATE, COUNTY),
    pop_growth_pct = 100 * (POPESTIMATE2025 / POPESTIMATE2020 - 1),
    annual_domestic_rate = rowMeans(pick(RDOMESTICMIG2021:RDOMESTICMIG2025)),
    annual_international_rate = rowMeans(pick(RINTERNATIONALMIG2021:RINTERNATIONALMIG2025)),
    annual_natural_rate = rowMeans(pick(RNATURALCHG2021:RNATURALCHG2025)),
    region_name = factor(REGION, levels = 1:4,
                         labels = c("Northeast", "Midwest", "South", "West")),
    short_name = sub(" County$| Parish$| Borough$| Census Area$| Municipality$", "", CTYNAME)
  ) |>
  select(geoid, state = STNAME, county = CTYNAME, short_name, region_name,
         pop_2020 = POPESTIMATE2020, pop_2025 = POPESTIMATE2025,
         pop_growth_pct, annual_domestic_rate, annual_international_rate,
         annual_natural_rate)

write_csv(county_data, "data/processed/county_population_migration_2020_2025.csv")

# Parse Census KML directly so the project does not require heavy GIS packages.
# Each outer boundary becomes one polygon piece. Interior water holes are not
# needed at the national scale used here.
parse_kml_polygons <- function(path, id_field) {
  doc <- read_xml(path)
  ns <- xml_ns(doc)
  placemarks <- xml_find_all(doc, ".//d1:Placemark", ns)

  pieces <- lapply(seq_along(placemarks), function(i) {
    pm <- placemarks[[i]]
    fields <- xml_find_all(pm, ".//d1:SimpleData", ns)
    names <- xml_attr(fields, "name")
    values <- xml_text(fields)
    id <- values[match(id_field, names)]
    state_fp <- values[match("STATEFP", names)]
    if (is.na(state_fp)) state_fp <- values[match("STATEFP20", names)]
    if (state_fp %in% c("02", "15", "60", "66", "69", "72", "78")) return(NULL)

    coordinates <- xml_find_all(pm, ".//d1:outerBoundaryIs//d1:coordinates", ns)
    if (length(coordinates) == 0) return(NULL)
    lapply(seq_along(coordinates), function(j) {
      tokens <- strsplit(trimws(xml_text(coordinates[[j]])), "[[:space:]]+")[[1]]
      matrix_values <- do.call(rbind, strsplit(tokens, ",", fixed = TRUE))
      tibble(
        id = id,
        piece = paste(i, j, sep = "-"),
        order = seq_len(nrow(matrix_values)),
        lon = as.numeric(matrix_values[, 1]),
        lat = as.numeric(matrix_values[, 2])
      )
    }) |> bind_rows()
  })
  bind_rows(pieces)
}

# Spherical Albers equal-area projection for the contiguous United States.
# Parameters follow the common U.S. Albers setup (standard parallels 29.5/45.5).
project_albers <- function(data) {
  rad <- pi / 180
  phi <- data$lat * rad
  lambda <- data$lon * rad
  phi1 <- 29.5 * rad
  phi2 <- 45.5 * rad
  phi0 <- 37.5 * rad
  lambda0 <- -96 * rad
  n <- 0.5 * (sin(phi1) + sin(phi2))
  c_value <- cos(phi1)^2 + 2 * n * sin(phi1)
  rho <- sqrt(c_value - 2 * n * sin(phi)) / n
  rho0 <- sqrt(c_value - 2 * n * sin(phi0)) / n
  theta <- n * (lambda - lambda0)
  data |>
    mutate(x = rho * sin(theta), y = rho0 - rho * cos(theta))
}

county_shapes <- parse_kml_polygons(county_kml, "GEOID") |> project_albers()
state_shapes <- parse_kml_polygons(state_kml, "STATEFP") |> project_albers()

map_data <- county_shapes |>
  left_join(county_data, by = c("id" = "geoid")) |>
  filter(!is.na(pop_growth_pct))

write_csv(county_shapes, "data/processed/county_boundaries_plot_data.csv")

theme_blog <- function() {
  theme_minimal(base_size = 12, base_family = "sans") +
    theme(
      plot.title.position = "plot",
      plot.title = element_text(face = "bold", size = 17, colour = "#172B4D"),
      plot.subtitle = element_text(size = 11, colour = "#42526E", margin = margin(b = 10)),
      plot.caption = element_text(size = 8.5, colour = "#6B778C", hjust = 0, margin = margin(t = 9)),
      axis.text = element_text(colour = "#42526E"),
      axis.title = element_text(colour = "#42526E"),
      panel.grid.minor = element_blank(),
      panel.grid.major = element_line(colour = "#EBECF0", linewidth = 0.35),
      legend.position = "top",
      legend.justification = "left",
      legend.title = element_text(face = "bold", size = 9),
      legend.text = element_text(size = 9),
      plot.margin = margin(12, 18, 12, 12)
    )
}

theme_map <- function() {
  theme_void(base_size = 12, base_family = "sans") +
    theme(
      plot.title.position = "plot",
      plot.title = element_text(face = "bold", size = 17, colour = "#172B4D"),
      plot.subtitle = element_text(size = 11, colour = "#42526E", margin = margin(b = 10)),
      plot.caption = element_text(size = 8.5, colour = "#6B778C", hjust = 0, margin = margin(t = 9)),
      legend.position = "bottom",
      legend.justification = "left",
      legend.title = element_text(face = "bold", size = 9),
      legend.text = element_text(size = 9),
      plot.margin = margin(12, 18, 12, 12)
    )
}

save_plot <- function(plot, filename, height = 5.8) {
  ggsave(file.path("figures", paste0(filename, ".png")), plot,
         width = 9.4, height = height, dpi = 220, bg = "white")
}

# Figure 1: county population growth. Squish the fill scale to keep outliers
# from obscuring most counties; exact unclipped values remain in the CSV.
fig1 <- ggplot(map_data, aes(x, y, group = piece, fill = pop_growth_pct)) +
  geom_polygon(colour = "white", linewidth = 0.06) +
  geom_path(data = state_shapes, aes(x, y, group = piece),
            inherit.aes = FALSE, colour = "#5E6C84", linewidth = 0.35) +
  coord_equal() +
  scale_fill_gradient2(
    low = "#2A6F97", mid = "#F7F7F2", high = "#D1495B", midpoint = 0,
    limits = c(-5, 15), oob = squish,
    breaks = c(-5, 0, 5, 15),
    labels = c("≤ -5%", "0%", "5%", "≥ 15%"),
    name = "Population change, 2020-2025",
    guide = guide_colorbar(title.position = "top", title.hjust = 0.5,
                           barwidth = grid::unit(9, "cm"),
                           barheight = grid::unit(0.42, "cm"))
  ) +
  labs(
    title = "Population growth concentrated in the South and Mountain West",
    subtitle = "County population change from July 2020 to July 2025; contiguous United States",
    caption = paste0("Source: U.S. Census Bureau, Vintage 2025 Population Estimates and 2025 ",
                     "Cartographic Boundary Files. Equal-area Albers projection.")
  ) + theme_map()
save_plot(fig1, "figure1_county_population_growth")

# Figure 2: domestic migration rate. Same diverging palette, centered on zero.
fig2 <- ggplot(map_data, aes(x, y, group = piece, fill = annual_domestic_rate)) +
  geom_polygon(colour = "white", linewidth = 0.06) +
  geom_path(data = state_shapes, aes(x, y, group = piece),
            inherit.aes = FALSE, colour = "#5E6C84", linewidth = 0.35) +
  coord_equal() +
  scale_fill_gradient2(
    low = "#2A6F97", mid = "#F7F7F2", high = "#D1495B", midpoint = 0,
    limits = c(-15, 30), oob = squish,
    breaks = c(-15, 0, 15, 30),
    labels = c("≤ -15", "0", "15", "≥ 30"),
    name = "Average annual domestic migration per 1,000 residents",
    guide = guide_colorbar(title.position = "top", title.hjust = 0.5,
                           barwidth = grid::unit(9, "cm"),
                           barheight = grid::unit(0.42, "cm"))
  ) +
  labs(
    title = "Domestic migration reinforced the same broad geography",
    subtitle = "Average annual net domestic migration rate, 2020-2025; contiguous United States",
    caption = paste0("Source: U.S. Census Bureau, Vintage 2025 Population Estimates and 2025 Cartographic Boundary Files.\n",
                     "Positive values indicate net inflow from other U.S. counties.")
  ) + theme_map()
save_plot(fig2, "figure2_county_domestic_migration")

# Figure 3: relationship between migration and population change. Restrict the
# labeled analysis to counties with at least 20,000 residents to reduce volatile
# percentage changes in very small counties; all mapped counties remain shown.
scatter_data <- county_data |> filter(pop_2020 >= 20000)
label_data <- bind_rows(
  scatter_data |> slice_max(pop_growth_pct, n = 2, with_ties = FALSE),
  scatter_data |> slice_min(pop_growth_pct, n = 1, with_ties = FALSE)
) |>
  distinct(geoid, .keep_all = TRUE) |>
  mutate(label_hjust = if_else(annual_domestic_rate > 35, 1.05, -0.05),
         label_vjust = if_else(pop_growth_pct < 0, -0.45, -0.35))

fit <- lm(pop_growth_pct ~ annual_domestic_rate, data = scatter_data)
scatter_correlation <- cor(scatter_data$pop_growth_pct,
                           scatter_data$annual_domestic_rate)

fig3 <- ggplot(scatter_data, aes(annual_domestic_rate, pop_growth_pct)) +
  geom_hline(yintercept = 0, colour = "#B3BAC5", linewidth = 0.5) +
  geom_vline(xintercept = 0, colour = "#B3BAC5", linewidth = 0.5) +
  geom_point(aes(size = pop_2025, colour = region_name), alpha = 0.48) +
  geom_smooth(method = "lm", se = FALSE, colour = "#172B4D", linewidth = 0.9) +
  geom_text(data = label_data,
            aes(label = paste0(short_name, ", ", state)),
            size = 2.7, check_overlap = TRUE,
            hjust = label_data$label_hjust, vjust = label_data$label_vjust,
            colour = "#172B4D", show.legend = FALSE) +
  scale_colour_manual(values = c("Northeast" = "#6C5B7B", "Midwest" = "#2A6F97",
                                 "South" = "#D1495B", "West" = "#E09F3E"),
                      name = "Census region") +
  scale_size_area(max_size = 8, labels = label_number(scale_cut = cut_short_scale()),
                  name = "2025 population") +
  scale_x_continuous(labels = label_number(accuracy = 1)) +
  scale_y_continuous(labels = label_percent(scale = 1, accuracy = 1)) +
  labs(
    title = "Counties gaining domestic migrants usually grew faster",
    subtitle = paste0("Counties with at least 20,000 residents; correlation = ",
                      round(scatter_correlation, 2)),
    x = "Average annual net domestic migration per 1,000 residents",
    y = "Population change, 2020-2025",
    caption = paste0("Source: U.S. Census Bureau, Vintage 2025 Population Estimates. ",
                     "Line is a descriptive linear fit; it does not establish causality.")
  ) + theme_blog() +
  theme(legend.box = "vertical", legend.key.height = grid::unit(0.35, "cm"))
save_plot(fig3, "figure3_migration_and_growth", height = 6.0)

# Figure 4: decomposition for illustrative counties. These counties are chosen
# to show both the dominant pattern (domestic inflow and growth) and an
# important exception (growth despite domestic outflow).
case_counties <- county_data |>
  filter(
    (state == "Texas" & short_name %in% c("Kaufman", "Harris")) |
      (state == "Arizona" & short_name == "Pinal") |
      (state == "South Carolina" & short_name == "Horry") |
      (state == "Florida" & short_name == "Miami-Dade") |
      (state == "Missouri" & short_name == "St. Louis city")
  ) |>
  mutate(
    case_label = case_when(
      short_name == "Kaufman" ~ "Kaufman, TX",
      short_name == "Pinal" ~ "Pinal, AZ",
      short_name == "Horry" ~ "Horry, SC",
      short_name == "Miami-Dade" ~ "Miami-Dade, FL",
      short_name == "Harris" ~ "Harris, TX",
      short_name == "St. Louis city" ~ "St. Louis city, MO"
    ),
    case_label = factor(case_label,
                        levels = c("Kaufman, TX", "Pinal, AZ", "Horry, SC",
                                   "Miami-Dade, FL", "Harris, TX", "St. Louis city, MO")),
    total_component_rate = annual_domestic_rate + annual_international_rate + annual_natural_rate
  )

case_components <- case_counties |>
  select(case_label, annual_domestic_rate, annual_international_rate, annual_natural_rate) |>
  pivot_longer(-case_label, names_to = "component", values_to = "rate") |>
  mutate(component = recode(
    component,
    annual_domestic_rate = "Domestic migration",
    annual_international_rate = "International migration",
    annual_natural_rate = "Natural change"
  ))

fig4 <- ggplot(case_components, aes(case_label, rate, fill = component)) +
  geom_hline(yintercept = 0, colour = "#B3BAC5", linewidth = 0.5) +
  geom_col(width = 0.7) +
  geom_text(
    data = case_counties,
    aes(
      x = case_label,
      y = if_else(total_component_rate >= 0, total_component_rate + 2.4,
                  total_component_rate - 2.4),
      label = paste0("Total: ", sprintf("%+.1f", total_component_rate))
    ),
    inherit.aes = FALSE,
    size = 3,
    colour = "#172B4D",
    vjust = if_else(case_counties$total_component_rate >= 0, 0, 1)
  ) +
  scale_fill_manual(
    values = c(
      "Domestic migration" = "#D1495B",
      "International migration" = "#E09F3E",
      "Natural change" = "#2A6F97"
    ),
    name = NULL
  ) +
  labs(
    title = "Population change came from different sources",
    subtitle = "Average annual components of change in six illustrative counties, 2020-2025",
    x = NULL,
    y = "Average annual contribution per 1,000 residents",
    caption = paste0("Source: U.S. Census Bureau, Vintage 2025 Population Estimates. ",
                     "Totals may not equal five-year growth exactly because Census rates are annualized.")
  ) +
  theme_blog() +
  theme(
    legend.position = "top",
    axis.text.x = element_text(angle = 25, hjust = 1),
    plot.margin = margin(12, 18, 20, 12)
  )
save_plot(fig4, "figure4_population_change_components", height = 6.2)

# Small summary table used for transparent, programmatic claims in the article.
summary_stats <- tibble(
  statistic = c("county_count", "scatter_count", "correlation",
                "share_growing", "median_growth", "median_domestic_rate"),
  value = c(nrow(county_data), nrow(scatter_data), scatter_correlation,
            mean(county_data$pop_growth_pct > 0),
            median(county_data$pop_growth_pct),
            median(county_data$annual_domestic_rate))
)
write_csv(summary_stats, "data/processed/summary_statistics.csv")

message("Analysis complete: ", nrow(county_data),
        " contiguous-U.S. counties and county equivalents.")
