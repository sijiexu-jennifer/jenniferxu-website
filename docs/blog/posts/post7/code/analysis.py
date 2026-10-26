"""Download FRED data and build the interactive figure for Blog Post 7."""

from io import StringIO
from pathlib import Path

import pandas as pd
import matplotlib.pyplot as plt
import plotly.graph_objects as go
import requests
from plotly.subplots import make_subplots


ROOT = Path(__file__).resolve().parents[1]
RAW_DIR = ROOT / "data" / "raw"
DERIVED_DIR = ROOT / "data" / "derived"
FIGURE_DIR = ROOT / "figures"
RESULTS_DIR = ROOT / "results"

for directory in (RAW_DIR, DERIVED_DIR, FIGURE_DIR, RESULTS_DIR):
    directory.mkdir(parents=True, exist_ok=True)

SERIES = {
    "CPIAUCSL": "cpi",
    "UNRATE": "unemployment",
    "FEDFUNDS": "fed_funds",
}

FRED_URL = "https://fred.stlouisfed.org/graph/fredgraph.csv?id={series_id}"


def download_fred_series(series_id: str, column_name: str) -> pd.DataFrame:
    """Download one public monthly FRED series and save an auditable raw copy."""
    response = requests.get(FRED_URL.format(series_id=series_id), timeout=60)
    response.raise_for_status()
    (RAW_DIR / f"{series_id}.csv").write_bytes(response.content)

    frame = pd.read_csv(StringIO(response.text), na_values=".")
    frame.columns = ["date", column_name]
    frame["date"] = pd.to_datetime(frame["date"])
    frame[column_name] = pd.to_numeric(frame[column_name], errors="coerce")
    return frame


def prepare_data() -> pd.DataFrame:
    """Merge the series, calculate year-over-year inflation, and label eras."""
    frames = [download_fred_series(series_id, name) for series_id, name in SERIES.items()]
    data = frames[0]
    for frame in frames[1:]:
        data = data.merge(frame, on="date", how="outer")

    data = data.sort_values("date")
    data["inflation"] = data["cpi"].pct_change(12, fill_method=None) * 100
    data = data.loc[data["date"] >= "2000-01-01"].copy()

    data["period"] = "2022–latest"
    data.loc[data["date"] < "2022-01-01", "period"] = "2020–2021"
    data.loc[data["date"] < "2020-01-01", "period"] = "2008–2019"
    data.loc[data["date"] < "2008-01-01", "period"] = "2000–2007"

    complete = data.dropna(subset=["inflation", "unemployment", "fed_funds"]).copy()
    complete.to_csv(DERIVED_DIR / "us_macro_monthly.csv", index=False)
    return complete


def make_figure(data: pd.DataFrame) -> go.Figure:
    """Create a linked two-panel Plotly figure with an era filter."""
    periods = ["2000–2007", "2008–2019", "2020–2021", "2022–latest"]
    period_colors = {
        "2000–2007": "#6c757d",
        "2008–2019": "#277da1",
        "2020–2021": "#f8961e",
        "2022–latest": "#d1495b",
    }
    indicators = [
        ("Inflation", "inflation", "#d1495b"),
        ("Unemployment", "unemployment", "#277da1"),
        ("Fed funds rate", "fed_funds", "#6f4e7c"),
    ]

    figure = make_subplots(
        rows=2,
        cols=1,
        row_heights=[0.54, 0.46],
        vertical_spacing=0.18,
        subplot_titles=(
            "Rates over time",
            "Inflation versus unemployment",
        ),
    )

    # The overview uses three continuous traces. Period-specific traces remain
    # hidden until selected, preventing visual breaks at era boundaries.
    overview_custom = data[["unemployment", "inflation", "fed_funds"]].to_numpy()
    for indicator_name, column, color in indicators:
        figure.add_trace(
            go.Scatter(
                x=data["date"],
                y=data[column],
                mode="lines",
                name=indicator_name,
                legendgroup=indicator_name,
                showlegend=True,
                visible=True,
                line={"color": color, "width": 2.2},
                customdata=overview_custom,
                hovertemplate=(
                    "%{x|%b %Y}<br>"
                    "Inflation: %{customdata[1]:.1f}%<br>"
                    "Unemployment: %{customdata[0]:.1f}%<br>"
                    "Fed funds: %{customdata[2]:.2f}%<extra></extra>"
                ),
            ),
            row=1,
            col=1,
        )

    overview_trace_count = len(indicators)
    traces_per_period = 4
    for period_index, period in enumerate(periods):
        subset = data.loc[data["period"] == period]
        for indicator_name, column, color in indicators:
            custom = subset[["unemployment", "inflation", "fed_funds"]].to_numpy()
            figure.add_trace(
                go.Scatter(
                    x=subset["date"],
                    y=subset[column],
                    mode="lines",
                    name=indicator_name,
                    legendgroup=indicator_name,
                    showlegend=True,
                    visible=False,
                    line={"color": color, "width": 2.2},
                    customdata=custom,
                    hovertemplate=(
                        "%{x|%b %Y}<br>"
                        "Inflation: %{customdata[1]:.1f}%<br>"
                        "Unemployment: %{customdata[0]:.1f}%<br>"
                        "Fed funds: %{customdata[2]:.2f}%<extra></extra>"
                    ),
                ),
                row=1,
                col=1,
            )

        custom = subset[["date", "fed_funds"]].copy()
        custom["date"] = custom["date"].dt.strftime("%b %Y")
        figure.add_trace(
            go.Scatter(
                x=subset["unemployment"],
                y=subset["inflation"],
                mode="markers",
                name=period,
                legendgroup=f"period-{period}",
                marker={
                    "color": period_colors[period],
                    "size": 7,
                    "opacity": 0.72,
                    "line": {"width": 0},
                },
                showlegend=False,
                customdata=custom.to_numpy(),
                hovertemplate=(
                    "%{customdata[0]}<br>"
                    "Unemployment: %{x:.1f}%<br>"
                    "Inflation: %{y:.1f}%<br>"
                    "Fed funds: %{customdata[1]:.2f}%<extra></extra>"
                ),
            ),
            row=2,
            col=1,
        )

    trace_count = overview_trace_count + len(periods) * traces_per_period
    all_periods_visible = [True] * overview_trace_count
    for _ in periods:
        all_periods_visible.extend([False, False, False, True])
    buttons = [
        {
            "label": "All periods",
            "method": "update",
            "args": [
                {"visible": all_periods_visible},
                {},
            ],
        }
    ]
    for period_index, period in enumerate(periods):
        visible = [False] * trace_count
        start = overview_trace_count + period_index * traces_per_period
        for index in range(start, start + traces_per_period):
            visible[index] = True
        buttons.append(
            {
                "label": period,
                "method": "update",
                "args": [
                    {"visible": visible},
                    {},
                ],
            }
        )

    figure.update_layout(
        template="plotly_white",
        height=720,
        margin={"l": 76, "r": 28, "t": 90, "b": 62},
        font={"family": "Arial, sans-serif", "size": 12, "color": "#243552"},
        hovermode="closest",
        paper_bgcolor="rgba(0,0,0,0)",
        plot_bgcolor="rgba(0,0,0,0)",
        legend={
            "orientation": "h",
            "yanchor": "bottom",
            "y": 1.055,
            "xanchor": "left",
            "x": 0,
            "font": {"size": 11},
            "entrywidth": 125,
            "entrywidthmode": "pixels",
        },
        updatemenus=[
            {
                "buttons": buttons,
                "direction": "down",
                "showactive": True,
                "x": 1,
                "xanchor": "right",
                "y": 1.095,
                "yanchor": "top",
                "bgcolor": "white",
                "bordercolor": "#b8c2cc",
                "font": {"size": 11},
            }
        ],
        annotations=list(figure.layout.annotations)
        + [
            {
                "text": (
                    "Point color by era: 2000–07 gray · 2008–19 blue · "
                    "2020–21 amber · 2022–latest red"
                ),
                "xref": "paper",
                "yref": "paper",
                "x": 0,
                "y": 0.43,
                "xanchor": "left",
                "showarrow": False,
                "font": {"size": 10, "color": "#68758a"},
            },
        ],
    )
    for annotation in figure.layout.annotations[:2]:
        annotation.update(font={"size": 16, "color": "#172b4d"})

    figure.update_xaxes(title_text="Date", row=1, col=1)
    figure.update_yaxes(title_text="Rate", ticksuffix="%", row=1, col=1)
    figure.update_xaxes(title_text="Unemployment rate", ticksuffix="%", row=2, col=1)
    figure.update_yaxes(title_text="12-month CPI inflation", ticksuffix="%", row=2, col=1)
    figure.update_xaxes(
        showgrid=True,
        gridcolor="#e8edf3",
        zeroline=False,
        linecolor="#c7d0dc",
    )
    figure.update_yaxes(
        showgrid=True,
        gridcolor="#e8edf3",
        zeroline=True,
        zerolinecolor="#c7d0dc",
        linecolor="#c7d0dc",
    )
    return figure


def make_preview(data: pd.DataFrame) -> None:
    """Save a compact static preview for the blog listing page."""
    period_colors = {
        "2000–2007": "#8b949e",
        "2008–2019": "#2a7fa6",
        "2020–2021": "#f2a34a",
        "2022–latest": "#d34b5b",
    }

    plt.rcParams.update({
        "font.family": "DejaVu Sans",
        "axes.titleweight": "bold",
    })
    fig, ax = plt.subplots(figsize=(12.8, 7.2), dpi=125)
    background = "#fbfaf7"
    fig.patch.set_facecolor(background)
    ax.set_facecolor(background)

    for period, color in period_colors.items():
        subset = data.loc[data["period"] == period]
        ax.scatter(
            subset["unemployment"],
            subset["inflation"],
            s=26,
            alpha=0.72,
            color=color,
            edgecolors="white",
            linewidths=0.35,
            label=period,
        )

    ax.set_title(
        "The Phillips curve shifts across economic eras",
        loc="left",
        fontsize=24,
        color="#243552",
        pad=26,
    )
    ax.text(
        0,
        1.015,
        "Monthly U.S. inflation and unemployment, 2000–2026",
        transform=ax.transAxes,
        fontsize=13,
        color="#68758a",
        va="bottom",
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
        loc="upper left",
        bbox_to_anchor=(0, 0.98),
        ncol=4,
        frameon=False,
        fontsize=11,
        handletextpad=0.4,
        columnspacing=1.5,
    )
    ax.text(
        1,
        -0.16,
        "Source: FRED · CPIAUCSL, UNRATE, FEDFUNDS",
        transform=ax.transAxes,
        ha="right",
        fontsize=9.5,
        color="#7a8799",
    )
    fig.subplots_adjust(left=0.1, right=0.97, top=0.82, bottom=0.18)
    fig.savefig(FIGURE_DIR / "post7-preview.png", facecolor=background)
    plt.close(fig)


def save_summary(data: pd.DataFrame) -> pd.DataFrame:
    """Save period-level statistics used in the written interpretation."""
    summary = (
        data.groupby("period", sort=False)
        .agg(
            start=("date", "min"),
            end=("date", "max"),
            mean_inflation=("inflation", "mean"),
            mean_unemployment=("unemployment", "mean"),
            inflation_unemployment_correlation=(
                "inflation",
                lambda values: values.corr(data.loc[values.index, "unemployment"]),
            ),
        )
        .reset_index()
    )
    summary.to_csv(RESULTS_DIR / "period_summary.csv", index=False)

    peak_inflation = data.loc[data["inflation"].idxmax()]
    peak_unemployment = data.loc[data["unemployment"].idxmax()]
    latest = data.iloc[-1]
    key_results = pd.DataFrame(
        [
            {
                "statistic": "Peak inflation",
                "date": peak_inflation["date"],
                "value": peak_inflation["inflation"],
                "unit": "percent",
            },
            {
                "statistic": "Peak unemployment",
                "date": peak_unemployment["date"],
                "value": peak_unemployment["unemployment"],
                "unit": "percent",
            },
            {
                "statistic": "Latest inflation",
                "date": latest["date"],
                "value": latest["inflation"],
                "unit": "percent",
            },
            {
                "statistic": "Latest unemployment",
                "date": latest["date"],
                "value": latest["unemployment"],
                "unit": "percent",
            },
            {
                "statistic": "Latest federal funds rate",
                "date": latest["date"],
                "value": latest["fed_funds"],
                "unit": "percent",
            },
        ]
    )
    key_results.to_csv(RESULTS_DIR / "key_results.csv", index=False)
    return summary


def main() -> None:
    data = prepare_data()
    figure = make_figure(data)
    figure.write_html(
        FIGURE_DIR / "interactive_macro_dashboard.html",
        include_plotlyjs=True,
        full_html=True,
        config={"displaylogo": False, "responsive": True},
    )
    make_preview(data)
    summary = save_summary(data)
    print(summary.to_string(index=False))


if __name__ == "__main__":
    main()
