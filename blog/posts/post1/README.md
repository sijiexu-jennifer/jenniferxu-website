# Blog Post 1: Omitted Variable Bias

This folder contains a self-contained simulation showing why a naive regression can give the wrong sign when an important confounder is omitted.

## Files

- `index.qmd`: blog post
- `bp1_gpa_ovb.R`: generates the simulated data, estimates the models, and creates the figure
- `bp1_gpa_simulated_data.csv`: generated fictional student data
- `bp1_gpa_ovb_figure.png`: figure used in the post

## Reproduce the analysis

Run these commands from this folder:

```r
install.packages(c("tidyverse", "xgboost"))
source("bp1_gpa_ovb.R")
```

Then render the post:

```bash
quarto render index.qmd
```

The simulation uses a fixed random seed, so rerunning the script reproduces the same dataset and estimates. All observations are fictional; no student records are used.
