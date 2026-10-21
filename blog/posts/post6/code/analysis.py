"""Reproduce Blog Post 6 with public-use PSID parent-child data."""

from pathlib import Path
import os
import re
import sqlite3

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import statsmodels.api as sm


ROOT = Path(__file__).resolve().parents[1]
FIGURE_DIR = ROOT / "figures"
RESULTS_DIR = ROOT / "results"
for directory in (FIGURE_DIR, RESULTS_DIR):
    directory.mkdir(parents=True, exist_ok=True)

DEFAULT_DOWNLOADS = Path.home() / "Downloads"
IND_DIR = Path(os.environ.get("PSID_IND_DIR", DEFAULT_DOWNLOADS / "ind2023er"))
PID_DIR = Path(os.environ.get("PSID_PID_DIR", DEFAULT_DOWNLOADS / "pid23"))

# Income year -> variable in the 1968-2023 Cross-year Individual File.
# The concepts evolve from money income to taxable income, labor income, and
# annual earnings; all measure the individual's own market income/earnings.
INCOME_VARIABLES = {
    1967: "ER30012",
    1968: "ER30033",
    1969: "ER30057",
    1970: "ER30081",
    1971: "ER30106",
    1972: "ER30130",
    1973: "ER30152",
    1974: "ER30173",
    1975: "ER30202",
    1976: "ER30231",
    1977: "ER30268",
    1978: "ER30298",
    1979: "ER30328",
    1980: "ER30358",
    1981: "ER30386",
    1982: "ER30415",
    1983: "ER30445",
    1984: "ER30480",
    1985: "ER30515",
    1986: "ER30551",
    1987: "ER30586",
    1988: "ER30622",
    1989: "ER30659",
    1990: "ER30705",
    1991: "ER30750",
    1992: "ER30821",
    1997: "ER33537N",
    1999: "ER33628N",
    2001: "ER33728N",
}

# Annual CPI-U, U.S. city average (1982-84=100), BLS series CUUR0000SA0.
CPI_U = {
    1967: 33.4,
    1968: 34.8,
    1969: 36.7,
    1970: 38.8,
    1971: 40.5,
    1972: 41.8,
    1973: 44.4,
    1974: 49.3,
    1975: 53.8,
    1976: 56.9,
    1977: 60.6,
    1978: 65.2,
    1979: 72.6,
    1980: 82.4,
    1981: 90.9,
    1982: 96.5,
    1983: 99.6,
    1984: 103.9,
    1985: 107.6,
    1986: 109.6,
    1987: 113.6,
    1988: 118.3,
    1989: 124.0,
    1990: 130.7,
    1991: 136.2,
    1992: 140.3,
    1997: 160.5,
    1999: 166.6,
    2001: 177.1,
    2023: 304.7,
}


def parse_stata_colspecs(do_file):
    """Read fixed-width positions from a PSID-provided Stata import file."""
    header = Path(do_file).read_text(errors="ignore").split("using [path]")[0]
    matches = re.finditer(
        r"(?:long\s+)?([A-Z][A-Z0-9]+)\s+(\d+)\s+-\s+(\d+)", header
    )
    return {
        match.group(1): (int(match.group(2)) - 1, int(match.group(3)))
        for match in matches
    }


def read_fixed_width_subset(txt_file, colspecs, variables):
    """Read selected columns without loading the 500+ MB source file at once."""
    specs = [colspecs[variable] for variable in variables]
    rows = []
    with Path(txt_file).open() as source:
        for line in source:
            rows.append([line[start:end].strip() for start, end in specs])
    return pd.DataFrame(rows, columns=variables).apply(pd.to_numeric, errors="coerce")


def load_individual_file():
    """Create person and person-year income tables from IND2023ER."""
    do_file = IND_DIR / "IND2023ER.do"
    txt_file = IND_DIR / "IND2023ER.txt"
    if not do_file.exists() or not txt_file.exists():
        raise FileNotFoundError(
            "Download and extract PSID Cross-year Individual 1968-2023, then "
            "set PSID_IND_DIR or place it in ~/Downloads/ind2023er."
        )

    colspecs = parse_stata_colspecs(do_file)
    variables = [
        "ER30001",
        "ER30002",
        "ER32000",
        "ER30811",
        "ER33506",
        "ER35106",
        *INCOME_VARIABLES.values(),
    ]
    raw = read_fixed_width_subset(txt_file, colspecs, variables)
    raw["person_id"] = (
        raw["ER30001"].astype("Int64") * 1000 + raw["ER30002"].astype("Int64")
    )

    birth_year = pd.Series(np.nan, index=raw.index)
    for variable in ("ER35106", "ER33506", "ER30811"):
        candidate = raw[variable].where(raw[variable].between(1900, 1990))
        birth_year = birth_year.fillna(candidate)
    raw["birth_year"] = birth_year

    people = (
        raw[["person_id", "birth_year", "ER32000"]]
        .rename(columns={"ER32000": "sex"})
        .dropna(subset=["person_id", "birth_year"])
        .astype({"person_id": "int64", "birth_year": "int64"})
    )

    income_frames = []
    for year, variable in INCOME_VARIABLES.items():
        width = colspecs[variable][1] - colspecs[variable][0]
        missing_code = 10**width - 1
        frame = raw[["person_id", variable]].rename(columns={variable: "income"}).dropna()
        # Negative values cannot enter logs. An all-9 value is PSID's missing
        # code; the value immediately below it may be a valid top code.
        frame = frame[(frame["income"] > 0) & (frame["income"] < missing_code)]
        frame["year"] = year
        frame["income_real"] = frame["income"] * CPI_U[2023] / CPI_U[year]
        income_frames.append(frame[["person_id", "year", "income_real"]])

    income = pd.concat(income_frames, ignore_index=True)
    income["person_id"] = income["person_id"].astype("int64")
    return people, income


def load_parent_links():
    """Create child-parent links from the 2023 Parent Identification File."""
    do_file = PID_DIR / "PID23.do"
    txt_file = PID_DIR / "PID23.txt"
    if not do_file.exists() or not txt_file.exists():
        raise FileNotFoundError(
            "Download and extract PSID Parent Identification 2023, then set "
            "PSID_PID_DIR or place it in ~/Downloads/pid23."
        )

    colspecs = parse_stata_colspecs(do_file)
    variables = ["PID2", "PID3", "PID4", "PID5", "PID23", "PID24"]
    raw = read_fixed_width_subset(txt_file, colspecs, variables)
    raw["child_id"] = raw["PID2"].astype("Int64") * 1000 + raw["PID3"].astype("Int64")

    links = []
    for parent_type, interview, person in (
        ("mother", "PID4", "PID5"),
        ("father", "PID23", "PID24"),
    ):
        frame = raw[["child_id", interview, person]].copy()
        frame["parent_id"] = (
            frame[interview].astype("Int64") * 1000 + frame[person].astype("Int64")
        )
        frame["parent_type"] = parent_type
        frame = frame[
            (frame[interview] > 0)
            & (frame[person] > 0)
            & (frame["parent_id"] != frame["child_id"])
        ]
        links.append(frame[["child_id", "parent_id", "parent_type"]])

    return (
        pd.concat(links, ignore_index=True)
        .drop_duplicates()
        .astype({"child_id": "int64", "parent_id": "int64"})
    )


def load_psid_source_files():
    """Public helper used by the tutorial's setup example."""
    people, income = load_individual_file()
    parent_links = load_parent_links()
    return people, parent_links, income


MATCH_QUERY = """
SELECT
    l.child_id,
    l.parent_id,
    l.parent_type,
    c.birth_year AS child_birth_year,
    p.birth_year AS parent_birth_year
FROM parent_links AS l
JOIN people AS c ON l.child_id = c.person_id
JOIN people AS p ON l.parent_id = p.person_id
WHERE c.birth_year BETWEEN 1945 AND 1972
  AND p.birth_year < c.birth_year - 12
"""


INCOME_QUERY = """
WITH parent_year AS (
    SELECT
        m.child_id,
        i.year,
        SUM(i.income_real) AS parent_income,
        MAX(i.year - m.child_birth_year) AS child_age
    FROM matches AS m
    JOIN income AS i ON m.parent_id = i.person_id
    WHERE i.income_real >= 1000
    GROUP BY m.child_id, i.year
),
parent_measures AS (
    SELECT
        child_id,
        MAX(CASE WHEN child_age = 14 THEN parent_income END)
            AS parent_income_single,
        AVG(CASE WHEN child_age BETWEEN 10 AND 18 THEN parent_income END)
            AS parent_income_multi,
        COUNT(DISTINCT CASE WHEN child_age BETWEEN 10 AND 18 THEN year END)
            AS parent_years
    FROM parent_year
    GROUP BY child_id
),
child_measures AS (
    SELECT
        c.person_id AS child_id,
        MAX(CASE
            WHEN i.year - c.birth_year = 25 AND i.income_real >= 1000
            THEN i.income_real END) AS child_income_single,
        AVG(CASE
            WHEN i.year - c.birth_year BETWEEN 30 AND 35
             AND i.income_real >= 1000
            THEN i.income_real END) AS child_income_multi,
        COUNT(DISTINCT CASE
            WHEN i.year - c.birth_year BETWEEN 30 AND 35
             AND i.income_real >= 1000
            THEN i.year END) AS child_years
    FROM (SELECT DISTINCT child_id FROM matches) AS k
    JOIN people AS c ON k.child_id = c.person_id
    LEFT JOIN income AS i ON c.person_id = i.person_id
    GROUP BY c.person_id
)
SELECT p.*, c.child_income_single, c.child_income_multi, c.child_years
FROM parent_measures AS p
JOIN child_measures AS c USING (child_id)
WHERE p.parent_years >= 5
  AND c.child_years >= 3
  AND p.parent_income_single IS NOT NULL
  AND c.child_income_single IS NOT NULL
"""


AGE_PROFILE_QUERY = """
WITH parent_year AS (
    SELECT
        m.child_id,
        i.year,
        SUM(i.income_real) AS parent_income,
        MAX(i.year - m.child_birth_year) AS child_age
    FROM matches AS m
    JOIN income AS i ON m.parent_id = i.person_id
    WHERE i.income_real >= 1000
    GROUP BY m.child_id, i.year
),
parent_measures AS (
    SELECT
        child_id,
        AVG(CASE WHEN child_age BETWEEN 10 AND 18 THEN parent_income END)
            AS parent_income_multi,
        COUNT(DISTINCT CASE WHEN child_age BETWEEN 10 AND 18 THEN year END)
            AS parent_years
    FROM parent_year
    GROUP BY child_id
)
SELECT
    p.child_id,
    p.parent_income_multi,
    i.year - c.birth_year AS child_age,
    i.income_real AS child_income
FROM parent_measures AS p
JOIN people AS c ON p.child_id = c.person_id
JOIN income AS i ON p.child_id = i.person_id
WHERE p.parent_years >= 5
  AND i.year - c.birth_year BETWEEN 22 AND 35
  AND i.income_real >= 1000
"""


def estimate_ige(frame, parent_col, child_col):
    """Estimate a log-log IGE with HC1 robust standard errors."""
    sample = frame[[parent_col, child_col]].dropna()
    x = np.log(sample[parent_col])
    y = np.log(sample[child_col])
    model = sm.OLS(y, sm.add_constant(x)).fit(cov_type="HC1")
    return {
        "estimate": model.params.iloc[1],
        "std_error": model.bse.iloc[1],
        "ci_low": model.conf_int().iloc[1, 0],
        "ci_high": model.conf_int().iloc[1, 1],
        "n": int(model.nobs),
        "r_squared": model.rsquared,
    }


def main():
    people, parent_links, income = load_psid_source_files()

    with sqlite3.connect(":memory:") as connection:
        people.to_sql("people", connection, index=False, if_exists="replace")
        parent_links.to_sql("parent_links", connection, index=False, if_exists="replace")
        income.to_sql("income", connection, index=False, if_exists="replace")
        matches = pd.read_sql_query(MATCH_QUERY, connection)
        matches.to_sql("matches", connection, index=False, if_exists="replace")
        matched = pd.read_sql_query(INCOME_QUERY, connection)
        age_profile = pd.read_sql_query(AGE_PROFILE_QUERY, connection)

    specifications = {
        "Single-year earnings": ("parent_income_single", "child_income_single"),
        "Multi-year average earnings": ("parent_income_multi", "child_income_multi"),
    }
    results = pd.DataFrame(
        [
            {"specification": label, **estimate_ige(matched, parent_col, child_col)}
            for label, (parent_col, child_col) in specifications.items()
        ]
    )
    results.to_csv(RESULTS_DIR / "ige_estimates.csv", index=False)

    age_results = []
    for age, group in age_profile.groupby("child_age"):
        if len(group) >= 50:
            age_results.append(
                {
                    "child_age": int(age),
                    **estimate_ige(group, "parent_income_multi", "child_income"),
                }
            )
    age_results = pd.DataFrame(age_results).sort_values("child_age")
    age_results.to_csv(RESULTS_DIR / "ige_by_child_age.csv", index=False)

    pd.DataFrame(
        {
            "measure": [
                "common matched sample",
                "minimum parent income years",
                "minimum child income years",
                "parent links before income restrictions",
            ],
            "value": [len(matched), 5, 3, len(matches)],
        }
    ).to_csv(RESULTS_DIR / "sample_summary.csv", index=False)

    plt.style.use("seaborn-v0_8-whitegrid")
    fig, axes = plt.subplots(1, 2, figsize=(11, 4.6), sharey=True)
    for ax, (label, (parent_col, child_col)) in zip(axes, specifications.items()):
        x = np.log(matched[parent_col])
        y = np.log(matched[child_col])
        ax.scatter(x, y, s=13, alpha=0.23, color="#277da1", edgecolor="none")
        fit = np.polyfit(x, y, 1)
        x_line = np.linspace(x.min(), x.max(), 100)
        ax.plot(x_line, fit[0] * x_line + fit[1], color="#d1495b", linewidth=2.5)
        estimate = results.loc[results["specification"] == label, "estimate"].iloc[0]
        ax.set_title(f"{label}\nIGE = {estimate:.3f}")
        ax.set_xlabel("Log parental earnings")
    axes[0].set_ylabel("Log child earnings")
    fig.suptitle("PSID estimates depend on how income is measured", fontsize=14)
    fig.tight_layout()
    fig.savefig(FIGURE_DIR / "ige_comparison.png", dpi=200, bbox_inches="tight")
    plt.close(fig)

    fig, ax = plt.subplots(figsize=(8.5, 4.8))
    ax.fill_between(
        age_results["child_age"],
        age_results["ci_low"],
        age_results["ci_high"],
        color="#277da1",
        alpha=0.18,
        label="95% confidence interval",
    )
    ax.plot(
        age_results["child_age"],
        age_results["estimate"],
        color="#277da1",
        marker="o",
        linewidth=2.5,
        label="Single-year IGE",
    )
    ax.set(
        title="The estimated IGE generally rises as adult children age",
        xlabel="Child age when annual earnings are measured",
        ylabel="Estimated IGE",
        xticks=np.arange(22, 36),
        ylim=(0, max(0.42, age_results["ci_high"].max() + 0.03)),
    )
    ax.legend(frameon=False, loc="lower right")
    fig.tight_layout()
    fig.savefig(FIGURE_DIR / "ige_by_child_age.png", dpi=200, bbox_inches="tight")
    plt.close(fig)

    print(results.to_string(index=False, float_format=lambda value: f"{value:.3f}"))
    print(f"\nCommon matched sample: {len(matched):,} parent-child observations")


if __name__ == "__main__":
    main()
