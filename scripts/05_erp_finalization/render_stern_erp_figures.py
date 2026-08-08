#!/usr/bin/env python3
"""Render publication-ready STERN ERP figures from auditable TSV tables."""

from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path
from typing import Dict, List

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np


CONDITIONS = ("Ignore", "Memorize", "Probe")
CONTRASTS = (
    "Memorize_minus_Ignore",
    "Probe_minus_Memorize",
    "Probe_minus_Ignore",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--results-dir",
        required=True,
        type=Path,
        help="STERN results directory containing tables/ and figures/",
    )
    return parser.parse_args()


def read_tsv(path: Path) -> List[Dict[str, str]]:
    if not path.is_file():
        raise FileNotFoundError(f"Missing TSV: {path}")

    with path.open("r", encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))

    if not rows:
        raise ValueError(f"TSV is empty: {path}")

    return rows


def numeric(rows: List[Dict[str, str]], column: str) -> np.ndarray:
    try:
        values = np.asarray([float(row[column]) for row in rows], dtype=float)
    except (KeyError, TypeError, ValueError) as exc:
        raise ValueError(f"Invalid numeric column {column!r}") from exc

    if not np.all(np.isfinite(values)):
        raise ValueError(f"Column {column!r} contains non-finite values")

    return values


def symmetric_limit(*arrays: np.ndarray) -> float:
    maximum = max(float(np.max(np.abs(array))) for array in arrays)
    if not math.isfinite(maximum) or maximum <= 0:
        maximum = 1.0
    return max(1.0, math.ceil(maximum * 1.15 * 2.0) / 2.0)


def validate_time(time_ms: np.ndarray) -> None:
    if time_ms.shape != (151,):
        raise ValueError(f"Expected 151 time samples, found {time_ms.shape}")
    if not np.all(np.diff(time_ms) > 0):
        raise ValueError("Time vector is not strictly increasing")
    if abs(float(time_ms[0]) + 200.0) > 1e-6:
        raise ValueError("Unexpected first ERP time")
    if abs(float(time_ms[-1]) - 1000.0) > 1e-6:
        raise ValueError("Unexpected final ERP time")


def save_figure(fig: plt.Figure, png_path: Path, svg_path: Path) -> None:
    png_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(png_path, dpi=300, bbox_inches="tight", facecolor="white")
    fig.savefig(svg_path, bbox_inches="tight", facecolor="white")
    plt.close(fig)

    if not png_path.is_file() or png_path.stat().st_size < 50_000:
        raise RuntimeError(f"PNG export missing or unexpectedly small: {png_path}")
    if not svg_path.is_file() or svg_path.stat().st_size < 5_000:
        raise RuntimeError(f"SVG export missing or unexpectedly small: {svg_path}")


def render_oz(results_dir: Path) -> None:
    table_path = results_dir / "tables" / "stern_OZ_grand_average_erp_final.tsv"
    rows = read_tsv(table_path)

    if len(rows) != 151:
        raise ValueError(f"Expected 151 Oz rows, found {len(rows)}")

    time_ms = numeric(rows, "time_ms")
    validate_time(time_ms)

    means: Dict[str, np.ndarray] = {}
    sems: Dict[str, np.ndarray] = {}

    for condition in CONDITIONS:
        means[condition] = numeric(rows, f"{condition}_mean_uv")
        sems[condition] = numeric(rows, f"{condition}_sem_uv")
        if means[condition].shape != (151,) or sems[condition].shape != (151,):
            raise ValueError(f"Unexpected Oz shape for {condition}")
        if np.any(sems[condition] < 0):
            raise ValueError(f"Negative SEM for {condition}")

    if max(float(np.max(np.abs(value))) for value in means.values()) >= 100:
        raise ValueError("Oz grand-average amplitude exceeds safety threshold")

    fig, ax = plt.subplots(figsize=(12.5, 7.6), constrained_layout=True)

    for condition in CONDITIONS:
        mean = means[condition]
        sem = sems[condition]
        line = ax.plot(time_ms, mean, linewidth=2.2, label=condition)[0]
        ax.fill_between(
            time_ms,
            mean - sem,
            mean + sem,
            alpha=0.16,
            color=line.get_color(),
            linewidth=0,
        )

    ax.axvline(0, linestyle="--", linewidth=1.0)
    ax.axhline(0, linestyle=":", linewidth=0.9)
    ax.set_xlim(-200, 1000)
    limit_value = symmetric_limit(*means.values())
    ax.set_ylim(-limit_value, limit_value)
    ax.set_xlabel("Time (ms)")
    ax.set_ylabel("Amplitude (uV)")
    ax.set_title("STERN grand-average ERP at Oz (N = 13)", weight="bold")
    ax.legend(loc="upper right", frameon=True)
    ax.grid(True, alpha=0.25)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)

    figures_dir = results_dir / "figures"
    save_figure(
        fig,
        figures_dir / "stern_grand_average_erp_OZ_final.png",
        figures_dir / "stern_grand_average_erp_OZ_final.svg",
    )


def render_representative(results_dir: Path) -> None:
    table_path = (
        results_dir / "tables" / "stern_erp_representative_waveforms_final.tsv"
    )
    rows = read_tsv(table_path)

    expected_rows = 3 * 2 * 151
    if len(rows) != expected_rows:
        raise ValueError(
            f"Expected {expected_rows} representative rows, found {len(rows)}"
        )

    fig, axes = plt.subplots(
        3,
        1,
        figsize=(13.5, 10.5),
        sharex=True,
        constrained_layout=True,
    )

    for axis, contrast in zip(axes, CONTRASTS):
        contrast_rows = [row for row in rows if row["contrast"] == contrast]
        if len(contrast_rows) != 2 * 151:
            raise ValueError(f"Unexpected row count for {contrast}")

        contrast_label = contrast_rows[0]["contrast_label"]
        channel = contrast_rows[0]["channel"]
        selection = contrast_rows[0]["selection"]
        selected_time_ms = float(contrast_rows[0]["selected_time_ms"])

        plotted_means: List[np.ndarray] = []

        condition_order: List[str] = []
        for row in contrast_rows:
            condition = row["condition"]
            if condition not in condition_order:
                condition_order.append(condition)

        if len(condition_order) != 2:
            raise ValueError(f"Expected two conditions for {contrast}")

        for condition in condition_order:
            condition_rows = [
                row for row in contrast_rows if row["condition"] == condition
            ]
            condition_rows.sort(key=lambda row: float(row["time_ms"]))

            if len(condition_rows) != 151:
                raise ValueError(
                    f"Expected 151 samples for {contrast}/{condition}"
                )

            time_ms = numeric(condition_rows, "time_ms")
            mean_uv = numeric(condition_rows, "mean_uv")
            sem_uv = numeric(condition_rows, "sem_uv")
            validate_time(time_ms)

            if np.any(sem_uv < 0):
                raise ValueError(f"Negative SEM for {contrast}/{condition}")

            line = axis.plot(
                time_ms,
                mean_uv,
                linewidth=2.0,
                label=condition,
            )[0]
            axis.fill_between(
                time_ms,
                mean_uv - sem_uv,
                mean_uv + sem_uv,
                alpha=0.14,
                color=line.get_color(),
                linewidth=0,
            )
            plotted_means.append(mean_uv)

        axis.axvline(0, linestyle="--", linewidth=0.9)
        axis.axvline(selected_time_ms, linestyle=":", linewidth=1.0)
        axis.axhline(0, linestyle=":", linewidth=0.8)
        axis.set_xlim(-200, 1000)
        limit_value = symmetric_limit(*plotted_means)
        axis.set_ylim(-limit_value, limit_value)
        axis.set_ylabel("Amplitude (uV)")
        axis.set_title(
            f"{contrast_label} at {channel} ({selection}; "
            f"peak {selected_time_ms:.0f} ms)",
            weight="bold",
        )
        axis.legend(loc="upper right", frameon=True)
        axis.grid(True, alpha=0.25)
        axis.spines["top"].set_visible(False)
        axis.spines["right"].set_visible(False)

    axes[-1].set_xlabel("Time (ms)")
    fig.suptitle(
        "STERN representative paired ERP waveforms (N = 13)",
        fontsize=15,
        weight="bold",
    )

    figures_dir = results_dir / "figures"
    save_figure(
        fig,
        figures_dir / "stern_erp_cluster_representative_waveforms_final.png",
        figures_dir / "stern_erp_cluster_representative_waveforms_final.svg",
    )


def main() -> None:
    args = parse_args()
    results_dir = args.results_dir.expanduser().resolve()

    if not results_dir.is_dir():
        raise NotADirectoryError(f"Results directory not found: {results_dir}")

    render_oz(results_dir)
    render_representative(results_dir)

    print("PYTHON_ERP_RENDER_PASSED")
    print(
        "OZ_PNG="
        + str(results_dir / "figures" / "stern_grand_average_erp_OZ_final.png")
    )
    print(
        "REPRESENTATIVE_PNG="
        + str(
            results_dir
            / "figures"
            / "stern_erp_cluster_representative_waveforms_final.png"
        )
    )


if __name__ == "__main__":
    main()
