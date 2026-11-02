# Blog Post 8: Does 95% Really Mean 95%?

This folder contains a reproducible Quarto blog post explaining bootstrap confidence intervals, confidence-interval coverage, rejection regions, and p-values through simulation.

## Research question

How can repeated simulation make the frequentist meaning of a 95% confidence interval and a hypothesis-test p-value visible?

## Project structure

```text
post8/
├── index.qmd
├── README.md
├── SUBMISSION.md
├── requirements.txt
├── styles.css
├── code/
│   └── analysis.py
├── data/
│   └── README.md
├── figures/
│   ├── bootstrap_distribution.svg
│   ├── coverage_intervals.svg
│   └── null_distribution.svg
├── interactive/
│   └── bootstrap_explorer.html
└── results/
    ├── summary.json
    ├── bootstrap_means.csv
    ├── coverage_intervals.csv
    └── null_statistics.csv
```

## Reproduce the analysis

Run the following commands from `blog/posts/post8/`:

```bash
python3 -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
python3 -m pip install -r requirements.txt
python3 code/analysis.py
quarto render index.qmd
```

The Python script recreates all CSV results, the JSON summary, and all three SVG figures. Fixed NumPy random seeds make the checked-in results reproducible with the listed dependency version. The interactive HTML file is self-contained and does not require a server or internet connection.

## Simulation design

- Synthetic population: weekly earnings distributed Normal($1,000, $250)
- Initial sample: 50 workers
- Bootstrap demonstration: 5,000 percentile-bootstrap resamples
- Coverage experiment: 2,000 samples with 999 bootstrap resamples per sample
- Hypothesis test: two-sided test of `H0: mean = $950` using 25,000 simulated null samples

## Data note

No external data are used. The earnings values are an illustrative teaching device, not estimates for a real population. Generated simulation output is stored in `results/`; the source and parameter definitions are in `code/analysis.py`.

