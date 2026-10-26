"""Build the static listing thumbnail from the prepared monthly data."""

from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd


ROOT = Path(__file__).resolve().parents[1]
DATA_PATH = ROOT / "data" / "derived" / "us_macro_monthly.csv"
OUTPUT_PATH = ROOT / "figures" / "post7-preview.png"


def main() -> None:
    data = pd.read_csv(DATA_PATH, parse_dates=["date"])
    colors = {
        "2000–2007": "#8b949e",
        "2008–2019": "#2a7fa6",
        "2020–2021": "#f2a34a",
        "2022–latest": "#d34b5b",
    }

    plt.rcParams.update({"font.family": "DejaVu Sans", "axes.titleweight": "bold"})
    fig, ax = plt.subplots(figsize=(12.8, 7.2), dpi=125)
    background = "#fbfaf7"
    fig.patch.set_facecolor(background)
    ax.set_facecolor(background)

    for period, color in colors.items():
        subset = data.loc[data["period"] == period]
        ax.scatter(
            subset["unemployment"], subset["inflation"],
            s=26, alpha=0.72, color=color,
            edgecolors="white", linewidths=0.35, label=period,
        )

    ax.set_title(
        "The Phillips curve shifts across economic eras",
        loc="left", fontsize=24, color="#243552", pad=26,
    )
    ax.text(
        0, 1.015, "Monthly U.S. inflation and unemployment, 2000–2026",
        transform=ax.transAxes, fontsize=13, color="#68758a", va="bottom",
    )
    ax.set_xlabel("Unemployment rate", fontsize=14, color="#243552", labelpad=10)
    ax.set_ylabel("12-month CPI inflation", fontsize=14, color="#243552", labelpad=10)
    ax.xaxis.set_major_formatter(lambda value, position: f"{value:.0f}%")
    ax.yaxis.set_major_formatter(lambda value, position: f"{value:.0f}%")
    ax.grid(True, color="#e4e9ef", linewidth=1)
    ax.axhline(0, color="#b8c2cc", linewidth=1.1)
    ax.set_axisbelow(True)
    for spine in ax.spines.values():
        spine.set_visible(False)
    ax.tick_params(colors="#40506a", labelsize=12, length=0)
    ax.legend(
        loc="upper left", bbox_to_anchor=(0, 0.98), ncol=4,
        frameon=False, fontsize=11, handletextpad=0.4, columnspacing=1.5,
    )
    ax.text(
        1, -0.16, "Source: FRED · CPIAUCSL, UNRATE, FEDFUNDS",
        transform=ax.transAxes, ha="right", fontsize=9.5, color="#7a8799",
    )
    fig.subplots_adjust(left=0.1, right=0.97, top=0.82, bottom=0.18)
    fig.savefig(OUTPUT_PATH, facecolor=background)
    plt.close(fig)


if __name__ == "__main__":
    main()
