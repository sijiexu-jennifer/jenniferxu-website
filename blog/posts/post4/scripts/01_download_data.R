# Download World Bank indicators and preserve an unedited raw snapshot.

library(WDI)
library(dplyr)
library(readr)

post_dir <- file.path("blog", "posts", "post4")
raw_dir <- file.path(post_dir, "data", "raw")
derived_dir <- file.path(post_dir, "data", "derived")
figure_dir <- file.path(post_dir, "figures")

dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(derived_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)

indicators <- c(
  gdp_per_capita = "NY.GDP.PCAP.PP.KD",
  life_expectancy = "SP.DYN.LE00.IN",
  population = "SP.POP.TOTL"
)

wdi_raw <- WDI(
  country = "all",
  indicator = indicators,
  start = 2000,
  end = 2023,
  extra = TRUE
)

write_csv(wdi_raw, file.path(raw_dir, "wdi_download.csv"), na = "")

metadata <- tibble(
  source = "World Bank World Development Indicators",
  source_url = "https://api.worldbank.org/v2",
  accessed_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
  variable = names(indicators),
  indicator = unname(indicators),
  start_year = 2000,
  end_year = 2023,
  access_method = "WDI R package"
)

write_csv(metadata, file.path(raw_dir, "metadata.csv"))

# Immediate validation, following the workflow discussed in Class 5.
country_rows <- wdi_raw |> filter(region != "Aggregates")

validation_checks <- tibble(
  check = c(
    "download_has_rows",
    "year_range_is_2000_to_2023",
    "country_year_keys_are_unique",
    "gdp_missing_share",
    "life_expectancy_missing_share",
    "population_missing_share"
  ),
  value = c(
    nrow(wdi_raw) > 0,
    min(wdi_raw$year, na.rm = TRUE) == 2000 & max(wdi_raw$year, na.rm = TRUE) == 2023,
    anyDuplicated(country_rows[c("iso3c", "year")]) == 0,
    mean(is.na(country_rows$gdp_per_capita)),
    mean(is.na(country_rows$life_expectancy)),
    mean(is.na(country_rows$population))
  )
)

stopifnot(validation_checks$value[1] == 1)
stopifnot(validation_checks$value[2] == 1)
stopifnot(validation_checks$value[3] == 1)

write_csv(validation_checks, file.path(raw_dir, "validation_checks.csv"))

writeLines(capture.output(sessionInfo()), file.path(raw_dir, "session_info.txt"))
