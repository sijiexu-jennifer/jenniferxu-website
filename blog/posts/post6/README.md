# Blog Post 6: Matching Parents and Children with SQL in Python

This folder contains a Quarto tutorial that uses public-use Panel Study of Income Dynamics (PSID) data to construct biological parent-child links, create longitudinal earnings measures, and estimate the intergenerational elasticity of income (IGE).

## Project structure

- `index.qmd`: Quarto source for the post
- `code/analysis.py`: PSID parser, SQL matching and aggregation, estimation, and figures
- `figures/`: generated comparison and life-cycle-bias figures
- `results/`: generated aggregate estimates and sample counts
- `styles.css`: post-specific webpage styling
- `SUBMISSION.md`: publishing and rubric checklist

Raw PSID microdata are not committed or redistributed. They are available free to registered researchers under the PSID Conditions of Use.

## Download the source data

1. Register or log in at the [PSID Data Center](https://simba.isr.umich.edu/U/Login.aspx).
2. Open [Main and Supplemental Study Packaged Data](https://simba.isr.umich.edu/Zips/ZipMain.aspx).
3. Download **Cross-year Individual: 1968-2023** and extract it as `~/Downloads/ind2023er/`.
4. Download **Parent Identification: 2023** and extract it as `~/Downloads/pid23/`.

The script expects `IND2023ER.do`, `IND2023ER.txt`, `PID23.do`, and `PID23.txt`. Alternative locations can be supplied with `PSID_IND_DIR` and `PSID_PID_DIR`.

## Reproduce the analysis

From the website repository root:

```bash
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -r blog/posts/post6/requirements.txt
python3 blog/posts/post6/code/analysis.py
quarto render blog/posts/post6/index.qmd
```

The analysis reads only the required fixed-width columns, removes PSID special missing values, converts nominal earnings to 2023 dollars using BLS CPI-U, and loads the resulting person, parent-link, and person-year tables into an in-memory SQLite database. It does not save row-level identifiers or income records.

## Analytical sample

- Parent-child links use biological mother and father identifiers from PID23.
- Parental earnings sum available linked-parent earnings within each year.
- The single-year specification uses parental earnings when the child was 14 and child earnings at age 25.
- The multi-year specification averages parental earnings while the child was 10-18 and child earnings at ages 30-35.
- The common sample requires at least five parental years, three adult-child years, and annual real earnings of at least $1,000.
- Estimates are unweighted and descriptive, not nationally representative or causal.

## Sources

- [Panel Study of Income Dynamics](https://psidonline.isr.umich.edu/)
- [PSID packaged data](https://simba.isr.umich.edu/Zips/ZipMain.aspx)
- [BLS CPI-U series CUUR0000SA0](https://data.bls.gov/timeseries/CUUR0000SA0)
