# Blog Post 5: GIS Data Visualization

This repository contains a reproducible geographic analysis of county
population change and domestic migration in the contiguous United States from
2020 to 2025.

## Research question

Where did county populations grow or shrink between 2020 and 2025, and how
closely did those changes line up with domestic migration?

## Repository structure

```text
.
├── analysis.R               # downloads, cleans, joins, projects, and plots data
├── index.qmd                # article and dynamically generated results
├── styles.css               # webpage styling
├── data/
│   ├── raw/                 # Census CSV and KML source snapshots
│   └── processed/           # analysis-ready attributes and map coordinates
├── figures/                 # two county maps, one scatterplot, and one component chart
├── docs/index.html          # publishable GitHub Pages webpage
├── SUBMISSION.md            # publishing and rubric checklist
└── README.md
```

## Data sources

The project downloads official public files without an API key:

- U.S. Census Bureau Vintage 2025 county population estimates and components
  of change (`co-est2025-alldata.csv`).
- U.S. Census Bureau 2025 county and state Cartographic Boundary Files at
  1:20,000,000 scale, distributed as KML.

Exact URLs are defined near the top of `analysis.R`. Raw snapshots are included
so the submitted version remains reproducible if a Census server is temporarily
unavailable.

## How to reproduce

1. Install R 4.3 or newer and either RStudio or Pandoc/Quarto.
2. Install the required packages once:

   ```r
   install.packages(c(
     "dplyr", "tidyr", "readr", "ggplot2", "scales",
     "xml2", "knitr"
   ))
   ```

3. From the repository root, render the Quarto article:

   ```bash
   quarto render index.qmd
   ```

The document sources `analysis.R`, which refreshes the Census files, creates
the processed datasets, and regenerates all four figures. To refresh only data
and figures, run `source("analysis.R")`.

## Main transformations

- County population growth is the percentage change from July 2020 to July
  2025.
- Domestic migration is the mean of the five annual Census net domestic
  migration rates, reported per 1,000 residents.
- Census KML coordinates are parsed programmatically and joined to estimates
  by the five-digit county GEOID.
- Coordinates are transformed with an equal-area Albers projection using
  standard parallels at 29.5 and 45.5 degrees north.
- Alaska, Hawaii, and territories are excluded from the maps so geographic
  scale and distance are not altered by inset repositioning.
- Color scales are capped for legibility; exact values remain in the CSV.

## Limitations

Population estimates are revised with each annual vintage. County averages can
hide substantial within-county differences. The association between migration
and population growth is descriptive rather than causal.

Data were accessed on October 18, 2026.
