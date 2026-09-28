#!/usr/bin/env python3
"""Aggregate a fixed-width IPUMS CPS extract without loading it into memory."""

from pathlib import Path
import argparse
import csv
import numpy as np
import xml.etree.ElementTree as ET


START_YEAR = 2000
END_YEAR = 2024
SELECTED_YEARS = np.array([2000, 2010, 2019, 2020, 2024])
CHUNK = 2_000_000


VARIABLES = {
    "year": "YEAR",
    "month": "MONTH",
    "asecflag": "ASECFLAG",
    "weight": "WTFINL",
    "age": "AGE",
    "sex": "SEX",
    "laborforce": "LABFORCE",
}


def add_bincount(target, indices, weights, size):
    target += np.bincount(indices, weights=weights, minlength=size).reshape(target.shape)


def numeric(field, dtype):
    """Convert a fixed-width byte field, treating blank values as zero."""
    values = np.char.strip(field)
    values[values == b""] = b"0"
    return values.astype(dtype)


def write_csv(path, header, rows):
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(header)
        writer.writerows(rows)


def dtype_from_ddi(path):
    """Build a NumPy fixed-width layout from the IPUMS DDI XML file."""
    root = ET.parse(path).getroot()
    found = {}
    max_end = 0
    for var in root.iter():
        if var.tag.rsplit("}", 1)[-1] != "var":
            continue
        location = next(
            (child for child in var if child.tag.rsplit("}", 1)[-1] == "location"),
            None,
        )
        if location is None:
            continue
        end = int(location.attrib["EndPos"])
        max_end = max(max_end, end)
        name = var.attrib.get("name")
        if name in VARIABLES.values():
            found[name] = {
                "start": int(location.attrib["StartPos"]) - 1,
                "width": int(location.attrib["width"]),
                "decimals": int(var.attrib.get("dcml", 0)),
            }
    missing = set(VARIABLES.values()) - set(found)
    if missing:
        raise ValueError(f"Missing required variables in DDI: {sorted(missing)}")
    names = list(VARIABLES)
    formats = [f"S{found[VARIABLES[name]]['width']}" for name in names]
    offsets = [found[VARIABLES[name]]["start"] for name in names]
    # The IPUMS .dat file has one newline byte after each fixed-width record.
    dtype = np.dtype({"names": names, "formats": formats, "offsets": offsets, "itemsize": max_end + 1})
    return dtype, found["WTFINL"]["decimals"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("data", type=Path, help="Path to the IPUMS CPS .dat file")
    parser.add_argument("ddi", type=Path, help="Path to the matching IPUMS DDI .xml file")
    parser.add_argument("--output", type=Path, default=Path("data/derived"))
    args = parser.parse_args()

    args.output.mkdir(parents=True, exist_ok=True)
    dtype, weight_decimals = dtype_from_ddi(args.ddi)
    data = np.memmap(args.data, mode="r", dtype=dtype)

    # Last dimension: 0 = eligible population weight, 1 = labor-force weight.
    age_month = np.zeros((25, 12, 4, 2), dtype=np.float64)
    sex_month = np.zeros((25, 12, 2, 2), dtype=np.float64)
    profile_month = np.zeros((5, 12, 13, 2), dtype=np.float64)
    valid_records = 0
    asec_records = 0

    for start in range(0, len(data), CHUNK):
        block = data[start : start + CHUNK]
        year = numeric(block["year"], np.int16)
        month = numeric(block["month"], np.int8)
        age = numeric(block["age"], np.int16)
        sex = numeric(block["sex"], np.int8)
        lf = numeric(block["laborforce"], np.int8)
        weight = numeric(block["weight"], np.float64) / (10.0 ** weight_decimals)
        asec = block["asecflag"] == b"1"
        asec_records += int(asec.sum())

        valid = (
            (year >= START_YEAR)
            & (year <= END_YEAR)
            & (~asec)
            & (month >= 1)
            & (month <= 12)
            & (age >= 16)
            & ((lf == 1) | (lf == 2))
            & (weight > 0)
        )
        valid_records += int(valid.sum())

        y = year[valid] - START_YEAR
        m = month[valid] - 1
        a = age[valid]
        s = sex[valid]
        in_lf = (lf[valid] == 2).astype(np.float64)
        w = weight[valid]

        age_group = np.select(
            [a <= 24, a <= 54, a <= 64],
            [0, 1, 2],
            default=3,
        ).astype(np.int8)
        base_index = ((y * 12 + m) * 4 + age_group) * 2
        add_bincount(age_month, base_index, w, age_month.size)
        add_bincount(age_month, base_index + 1, w * in_lf, age_month.size)

        prime = (a >= 25) & (a <= 54) & ((s == 1) | (s == 2))
        sex_index = ((y[prime] * 12 + m[prime]) * 2 + (s[prime] - 1)) * 2
        add_bincount(sex_month, sex_index, w[prime], sex_month.size)
        add_bincount(sex_month, sex_index + 1, w[prime] * in_lf[prime], sex_month.size)

        selected_index = np.searchsorted(SELECTED_YEARS, year[valid])
        selected = (
            (selected_index < len(SELECTED_YEARS))
            & (SELECTED_YEARS[np.minimum(selected_index, len(SELECTED_YEARS) - 1)] == year[valid])
            & (a <= 79)
        )
        if selected.any():
            yi = selected_index[selected]
            mm = m[selected]
            band = ((a[selected] - 15) // 5).astype(np.int8)
            profile_index = ((yi * 12 + mm) * 13 + band) * 2
            add_bincount(profile_month, profile_index, w[selected], profile_month.size)
            add_bincount(
                profile_month,
                profile_index + 1,
                w[selected] * in_lf[selected],
                profile_month.size,
            )

    age_labels = ["16–24", "25–54", "55–64", "65+"]
    sex_labels = ["Men", "Women"]

    monthly_age_rows = []
    annual_age_rows = []
    for yi, year in enumerate(range(START_YEAR, END_YEAR + 1)):
        for gi, label in enumerate(age_labels):
            rates = []
            for mi in range(12):
                den, num = age_month[yi, mi, gi]
                rate = num / den
                rates.append(rate)
                monthly_age_rows.append([year, mi + 1, label, rate])
            annual_age_rows.append([year, label, float(np.mean(rates))])

    monthly_sex_rows = []
    annual_sex_rows = []
    for yi, year in enumerate(range(START_YEAR, END_YEAR + 1)):
        for si, label in enumerate(sex_labels):
            rates = []
            for mi in range(12):
                den, num = sex_month[yi, mi, si]
                rate = num / den
                rates.append(rate)
                monthly_sex_rows.append([year, mi + 1, label, rate])
            annual_sex_rows.append([year, label, float(np.mean(rates))])

    profile_rows = []
    for yi, year in enumerate(SELECTED_YEARS):
        for bi in range(13):
            rates = []
            for mi in range(12):
                den, num = profile_month[yi, mi, bi]
                rates.append(num / den)
            age_start = 16 if bi == 0 else 15 + bi * 5
            profile_rows.append([int(year), age_start, 19 + bi * 5, float(np.mean(rates))])

    write_csv(args.output / "monthly_age_group_lfpr.csv", ["year", "month", "age_group", "lfpr"], monthly_age_rows)
    write_csv(args.output / "annual_age_group_lfpr.csv", ["year", "age_group", "lfpr"], annual_age_rows)
    write_csv(args.output / "monthly_prime_age_sex_lfpr.csv", ["year", "month", "sex", "lfpr"], monthly_sex_rows)
    write_csv(args.output / "annual_prime_age_sex_lfpr.csv", ["year", "sex", "lfpr"], annual_sex_rows)
    write_csv(args.output / "selected_year_age_profiles.csv", ["year", "age_start", "age_end", "lfpr"], profile_rows)
    write_csv(
        args.output / "processing_summary.csv",
        ["total_records", "valid_basic_monthly_records_age_16_plus", "excluded_asec_records"],
        [[len(data), valid_records, asec_records]],
    )

    print(f"Total records: {len(data):,}")
    print(f"Valid Basic Monthly records age 16+: {valid_records:,}")
    print(f"Excluded ASEC records: {asec_records:,}")


if __name__ == "__main__":
    main()
