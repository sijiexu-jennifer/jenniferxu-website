# Income and Life Expectancy, 2000–2023

This folder contains Blog Post 4 for the Jennifer Xu Quarto website. It follows the same structure as `blog/posts/post3` and is designed to be copied directly into `blog/posts/` as the `post4` folder.

## Research question

Do richer countries have longer life expectancy, and did countries with faster real GDP-per-capita growth from 2000 to 2023 also experience larger gains in longevity?

## Data

Source: [World Bank World Development Indicators](https://databank.worldbank.org/source/world-development-indicators), downloaded through the official API with the `WDI` R package.

Indicators:

- `NY.GDP.PCAP.PP.KD`: GDP per capita, PPP, constant 2021 international dollars
- `SP.DYN.LE00.IN`: life expectancy at birth, total
- `SP.POP.TOTL`: total population

## Reproduce the analysis

First, install the required R packages:

```r
install.packages(c(
  "WDI",
  "dplyr",
  "tidyr",
  "readr",
  "ggplot2",
  "scales"
))
```

Run these commands from the website repository root:

```r
source("blog/posts/post4/scripts/01_download_data.R")
source("blog/posts/post4/scripts/02_make_figures.R")
```

Then render the full website:

```bash
quarto render
```

Required R packages are `WDI`, `dplyr`, `tidyr`, `readr`, `ggplot2`, and `scales`.

## Folder structure

```text
post4/
├── index.qmd
├── README.md
├── scripts/
│   ├── 01_download_data.R
│   └── 02_make_figures.R
├── data/
│   ├── raw/
│   └── derived/
└── figures/
```

The raw API response and metadata are preserved in `data/raw/`. Cleaned data and summary statistics are in `data/derived/`. The three PNG files in `figures/` are used by `index.qmd`.
