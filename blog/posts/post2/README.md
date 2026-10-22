# Blog Post 2: Scraping a Book Catalog

This folder contains a reproducible `rvest` analysis of the fictional [Books to Scrape](https://books.toscrape.com/) catalog.

## Files

- `index.md`: blog post
- `scrape_analyze.R`: scraper, cleaning steps, validation checks, analysis, and figure generation
- `data/books.csv`: cleaned catalog
- `data/category_summary.csv`: category-level statistics
- `data/recommendations.csv`: in-stock books meeting the price and rating rule
- `figures/category_value.png`: ranking figure used in the post

## Reproduce the analysis

Run these commands from this folder:

```r
install.packages(c("rvest", "tidyverse", "scales"))
source("scrape_analyze.R")
```

Then render the post:

```bash
quarto render index.md
```

The script follows category pagination, pauses between requests, retries temporary failures, removes duplicate URLs, and checks for the expected 1,000-book catalog. Because the website is designed for scraping practice, the workflow does not bypass a login, CAPTCHA, or access restriction.

The site contains fictional prices and ratings and does not report review counts. The results demonstrate a decision method rather than a current real-world shopping recommendation.
