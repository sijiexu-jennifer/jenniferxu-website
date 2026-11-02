"""Reproduce every simulation, result table, and figure for Blog Post 8."""

from __future__ import annotations

import csv
import json
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / "results"
FIGURES = ROOT / "figures"

TRUE_MEAN = 1000.0
POP_SD = 250.0
SAMPLE_SIZE = 50
CONFIDENCE = 0.95
ALPHA = 1 - CONFIDENCE


def svg_start(width: int, height: int, title: str, subtitle: str) -> list[str]:
    return [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#fbfaf7"/>',
        '<style>text{font-family:Inter,Arial,sans-serif;fill:#17212b}.title{font-size:24px;font-weight:700}.sub{font-size:14px;fill:#56616b}.axis{font-size:12px;fill:#56616b}.note{font-size:13px}.grid{stroke:#dfe3e6;stroke-width:1}.axisline{stroke:#68737d;stroke-width:1.2}</style>',
        f'<text x="70" y="38" class="title">{title}</text>',
        f'<text x="70" y="62" class="sub">{subtitle}</text>',
    ]


def scale(value: float, low: float, high: float, a: float, b: float) -> float:
    return a + (value - low) * (b - a) / (high - low)


def histogram_svg(values: np.ndarray, path: Path, title: str, subtitle: str,
                  x_label: str, markers: list[tuple[float, str, str]],
                  tail_threshold: float | None = None,
                  pvalue_threshold: float | None = None) -> None:
    width, height = 900, 520
    left, right, top, bottom = 75, 855, 92, 430
    counts, edges = np.histogram(values, bins=45)
    ymax = counts.max() * 1.12
    parts = svg_start(width, height, title, subtitle)

    for frac in np.linspace(0, 1, 5):
        y = bottom - frac * (bottom - top)
        parts.append(f'<line x1="{left}" y1="{y:.1f}" x2="{right}" y2="{y:.1f}" class="grid"/>')
        parts.append(f'<text x="{left-12}" y="{y+4:.1f}" text-anchor="end" class="axis">{int(frac*ymax):,}</text>')

    for c, lo, hi in zip(counts, edges[:-1], edges[1:]):
        x = scale(lo, edges[0], edges[-1], left, right)
        x2 = scale(hi, edges[0], edges[-1], left, right)
        y = scale(c, 0, ymax, bottom, top)
        center = (lo + hi) / 2
        is_tail = tail_threshold is not None and abs(center) >= tail_threshold
        is_pvalue = pvalue_threshold is not None and abs(center) >= pvalue_threshold
        color = "#7b1e2b" if is_pvalue else ("#d95f5f" if is_tail else "#4f86c6")
        parts.append(f'<rect x="{x+1:.2f}" y="{y:.2f}" width="{max(1,x2-x-2):.2f}" height="{bottom-y:.2f}" fill="{color}" opacity="0.86"/>')

    parts += [
        f'<line x1="{left}" y1="{bottom}" x2="{right}" y2="{bottom}" class="axisline"/>',
        f'<line x1="{left}" y1="{top}" x2="{left}" y2="{bottom}" class="axisline"/>',
    ]
    for tick in np.linspace(edges[0], edges[-1], 6):
        x = scale(tick, edges[0], edges[-1], left, right)
        parts.append(f'<line x1="{x:.1f}" y1="{bottom}" x2="{x:.1f}" y2="{bottom+6}" class="axisline"/>')
        parts.append(f'<text x="{x:.1f}" y="{bottom+24}" text-anchor="middle" class="axis">{tick:,.1f}</text>')

    for value, label, color in markers:
        x = scale(value, edges[0], edges[-1], left, right)
        label_x = min(max(x, left + 48), right - 48)
        parts.append(f'<line x1="{x:.1f}" y1="{top}" x2="{x:.1f}" y2="{bottom}" stroke="{color}" stroke-width="2.5" stroke-dasharray="7 5"/>')
        parts.append(f'<text x="{label_x:.1f}" y="{top-8}" text-anchor="middle" font-size="12" font-weight="700" fill="{color}">{label}</text>')

    parts.append(f'<text x="{(left+right)/2}" y="{height-35}" text-anchor="middle" class="note">{x_label}</text>')
    parts.append(f'<text x="20" y="{(top+bottom)/2}" transform="rotate(-90 20 {(top+bottom)/2})" text-anchor="middle" class="note">Simulation count</text>')
    parts.append('</svg>')
    path.write_text("\n".join(parts), encoding="utf-8")


def coverage_svg(intervals: np.ndarray, covered: np.ndarray, overall: float, path: Path) -> None:
    width, height = 900, 640
    left, right, top, bottom = 115, 850, 105, 550
    shown = min(100, len(intervals))
    lo = min(intervals[:shown, 0].min(), TRUE_MEAN - 250)
    hi = max(intervals[:shown, 1].max(), TRUE_MEAN + 250)
    parts = svg_start(width, height, "What 95% coverage looks like", f"First {shown} of 2,000 repeated bootstrap intervals; overall coverage = {overall:.1%}")
    xtrue = scale(TRUE_MEAN, lo, hi, left, right)
    parts.append(f'<line x1="{xtrue:.1f}" y1="{top}" x2="{xtrue:.1f}" y2="{bottom}" stroke="#17212b" stroke-width="2" stroke-dasharray="6 5"/>')
    parts.append(f'<text x="{xtrue:.1f}" y="{top-12}" text-anchor="middle" font-size="13" font-weight="700">true mean = $1,000</text>')

    for i in range(shown):
        y = top + i * (bottom - top) / (shown - 1)
        x1 = scale(intervals[i, 0], lo, hi, left, right)
        x2 = scale(intervals[i, 1], lo, hi, left, right)
        xm = scale(intervals[i, 2], lo, hi, left, right)
        color = "#2f8f6b" if covered[i] else "#d95f5f"
        parts.append(f'<line x1="{x1:.2f}" y1="{y:.2f}" x2="{x2:.2f}" y2="{y:.2f}" stroke="{color}" stroke-width="2.2"/>')
        parts.append(f'<circle cx="{xm:.2f}" cy="{y:.2f}" r="2.2" fill="{color}"/>')

    parts.append(f'<line x1="{left}" y1="{bottom+16}" x2="{right}" y2="{bottom+16}" class="axisline"/>')
    for tick in np.linspace(lo, hi, 6):
        x = scale(tick, lo, hi, left, right)
        parts.append(f'<line x1="{x:.1f}" y1="{bottom+16}" x2="{x:.1f}" y2="{bottom+22}" class="axisline"/>')
        parts.append(f'<text x="{x:.1f}" y="{bottom+41}" text-anchor="middle" class="axis">${tick:,.0f}</text>')
    parts.append(f'<text x="{left}" y="{height-22}" class="note" fill="#2f8f6b">Green = interval contains truth</text>')
    parts.append(f'<text x="{left+360}" y="{height-22}" class="note" fill="#d95f5f">Red = interval misses truth</text>')
    parts.append('</svg>')
    path.write_text("\n".join(parts), encoding="utf-8")


def write_csv(path: Path, header: list[str], rows) -> None:
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(header)
        writer.writerows(rows)


def main() -> None:
    RESULTS.mkdir(parents=True, exist_ok=True)
    FIGURES.mkdir(parents=True, exist_ok=True)

    # Part 1: one sample and its bootstrap distribution.
    rng = np.random.default_rng(8048)
    sample = rng.normal(TRUE_MEAN, POP_SD, SAMPLE_SIZE)
    bootstrap_means = rng.choice(sample, size=(5000, SAMPLE_SIZE), replace=True).mean(axis=1)
    boot_ci = np.quantile(bootstrap_means, [ALPHA / 2, 1 - ALPHA / 2])
    write_csv(RESULTS / "bootstrap_means.csv", ["bootstrap_mean"], ((x,) for x in bootstrap_means))
    histogram_svg(
        bootstrap_means,
        FIGURES / "bootstrap_distribution.svg",
        "A bootstrap distribution from one sample",
        "5,000 resamples estimate how the sample mean would vary",
        "Bootstrap mean weekly earnings ($)",
        [(boot_ci[0], "2.5%", "#b04a4a"), (sample.mean(), "sample mean", "#17212b"), (boot_ci[1], "97.5%", "#b04a4a")],
    )

    # Part 2: repeat the full percentile-bootstrap procedure many times.
    rng_cov = np.random.default_rng(12345)
    simulations, boot_per_sim = 2000, 999
    intervals = np.empty((simulations, 3))
    for i in range(simulations):
        s = rng_cov.normal(TRUE_MEAN, POP_SD, SAMPLE_SIZE)
        means = rng_cov.choice(s, size=(boot_per_sim, SAMPLE_SIZE), replace=True).mean(axis=1)
        ci = np.quantile(means, [ALPHA / 2, 1 - ALPHA / 2])
        intervals[i] = ci[0], ci[1], s.mean()
    covered = (intervals[:, 0] <= TRUE_MEAN) & (TRUE_MEAN <= intervals[:, 1])
    coverage = float(covered.mean())
    write_csv(
        RESULTS / "coverage_intervals.csv",
        ["lower", "upper", "sample_mean", "covers_true_mean"],
        ((lo, hi, m, bool(c)) for (lo, hi, m), c in zip(intervals, covered)),
    )
    coverage_svg(intervals, covered, coverage, FIGURES / "coverage_intervals.svg")

    # Part 3: simulate a two-sided t test under H0: mu = $950.
    null_mean = 950.0
    rng_test = np.random.default_rng(42)
    observed = rng_test.normal(TRUE_MEAN, POP_SD, SAMPLE_SIZE)
    observed_t = (observed.mean() - null_mean) / (observed.std(ddof=1) / np.sqrt(SAMPLE_SIZE))
    null_samples = rng_test.normal(null_mean, POP_SD, size=(25000, SAMPLE_SIZE))
    null_t = (null_samples.mean(axis=1) - null_mean) / (null_samples.std(axis=1, ddof=1) / np.sqrt(SAMPLE_SIZE))
    critical = float(np.quantile(np.abs(null_t), 1 - ALPHA))
    p_value = float((np.abs(null_t) >= abs(observed_t)).mean())
    write_csv(RESULTS / "null_statistics.csv", ["null_t_statistic"], ((x,) for x in null_t))
    histogram_svg(
        null_t,
        FIGURES / "null_distribution.svg",
        "The test statistic under the null hypothesis",
        f"Red = 5% rejection region; dark red = outcomes at least as extreme as observed; p = {p_value:.3f}",
        "Simulated t statistic",
        [(-critical, "-critical", "#b04a4a"), (critical, "+critical", "#b04a4a"), (observed_t, "observed t", "#17212b")],
        tail_threshold=critical,
        pvalue_threshold=abs(observed_t),
    )

    summary = {
        "true_mean": TRUE_MEAN,
        "population_sd": POP_SD,
        "sample_size": SAMPLE_SIZE,
        "sample_mean": float(sample.mean()),
        "bootstrap_ci_lower": float(boot_ci[0]),
        "bootstrap_ci_upper": float(boot_ci[1]),
        "bootstrap_resamples": 5000,
        "coverage_simulations": simulations,
        "coverage_rate": coverage,
        "null_mean": null_mean,
        "observed_mean": float(observed.mean()),
        "observed_t": float(observed_t),
        "critical_value": critical,
        "p_value": p_value,
        "null_simulations": len(null_t),
    }
    (RESULTS / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()

