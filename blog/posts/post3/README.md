# U.S. Labor-Force Participation by Age, 2000–2024

This repository contains the code, derived statistics, figures, and Quarto post for a descriptive analysis of U.S. labor-force participation using IPUMS CPS Basic Monthly Samples.

## Research question

How did labor-force participation change across age groups between 2000 and 2024, and how did the prime-age gender gap change over the same period?

## Data

Source: [IPUMS CPS](https://cps.ipums.org/cps/).

The extract uses all Basic Monthly samples from January 2000 through December 2024 and the variables `YEAR`, `MONTH`, `AGE`, `SEX`, `LABFORCE`, and `WTFINL`. IPUMS also automatically included several identifying and technical variables. ASEC supplement records are excluded by the processing script.

The raw IPUMS microdata are not included in this repository. Registered IPUMS users can request the same extract and place the `.dat` and matching DDI `.xml` files in `data/raw/`.

## Reproduce the analysis

Requirements:

- Python 3 with NumPy
- R with ggplot2 and scales
- Quarto to render the post

Run from the repository root:

```bash
python3 scripts/01_process_cps.py \
  data/raw/cps_00001.dat \
  data/raw/cps_00001.xml \
  --output data/derived

Rscript scripts/02_make_figures.R
quarto render index.qmd
```

The Python script reads the large fixed-width extract in chunks, obtains column locations from the DDI metadata, removes ASEC records, applies `WTFINL`, and writes compact aggregate CSV files. The R script generates the three figures used in the post.

## Repository structure

```text
.
├── index.qmd
├── README.md
├── scripts/
│   ├── 01_process_cps.py
│   └── 02_make_figures.R
├── data/
│   ├── raw/          # Not committed
│   └── derived/
└── figures/
```

## Weighting

Monthly participation rates are weighted using the CPS final person weight, `WTFINL`. Annual estimates are the arithmetic mean of the 12 monthly weighted rates. The analysis includes civilians age 16 and older with `LABFORCE` equal to 1 or 2.

## Citation

Flood, Sarah, Miriam King, Renae Rodgers, Steven Ruggles, J. Robert Warren, Daniel Backman, Etienne Breton, Grace Cooper, Julia A. Rivera Drew, Stephanie Richards, David Van Riper, and Kari C.W. Williams. *IPUMS CPS: Version 13.0* [dataset]. Minneapolis, MN: IPUMS, 2025. https://doi.org/10.18128/D030.V13.0
