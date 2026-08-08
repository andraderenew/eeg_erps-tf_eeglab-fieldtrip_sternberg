#!/usr/bin/env python3
from pathlib import Path
import os

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.colors import TwoSlopeNorm
from matplotlib.patches import Circle, Polygon, Arc
from scipy.interpolate import Rbf

results = Path(os.environ['STERN_RESULTS_DIR'])
table_dir = results / 'tables'
figure_dir = results / 'figures'
figure_dir.mkdir(parents=True, exist_ok=True)

rep = pd.read_csv(table_dir / 'stern_tf_visualization_representative_tfr.tsv', sep='\t')
topo = pd.read_csv(table_dir / 'stern_tf_visualization_peak_topographies.tsv', sep='\t')
subj = pd.read_csv(table_dir / 'stern_tf_visualization_subject_cluster_values.tsv', sep='\t')
count = pd.read_csv(table_dir / 'stern_tf_visualization_channel_count.tsv', sep='\t')
sensor = pd.read_csv(table_dir / 'stern_tf_visualization_sensor_average_descriptive.tsv', sep='\t')
meta = pd.read_csv(table_dir / 'stern_tf_visualization_metadata.tsv', sep='\t')
bw = pd.read_csv(table_dir / 'stern_tf_visualization_band_window_descriptive.tsv', sep='\t')

PRIMARY = 'Memorize_minus_Ignore'
SECONDARY = ['Probe_minus_Memorize', 'Probe_minus_Ignore']


def matrix_from_long(df, value):
    times = np.sort(df.time_s.unique())
    freqs = np.sort(df.frequency_hz.unique())
    mat = (
        df.pivot(index='frequency_hz', columns='time_s', values=value)
        .loc[freqs, times]
        .to_numpy()
    )
    return times, freqs, mat


def symmetric_limit(values):
    m = float(np.nanmax(np.abs(values)))
    return m if m > 0 else 1.0


def scalp_xy(df):
    theta = np.deg2rad(df.theta_deg.to_numpy(float))
    radius = df.radius.to_numpy(float)
    x = radius * np.cos(theta)
    y = radius * np.sin(theta)
    scale = max(np.nanmax(np.sqrt(x * x + y * y)), 1e-9)
    return x / scale, y / scale


def draw_head(ax):
    ax.add_patch(Circle((0, 0), 1.0, fill=False, lw=1.8, color='black'))
    ax.add_patch(
        Polygon(
            [(-0.12, 0.98), (0, 1.14), (0.12, 0.98)],
            closed=False,
            fill=False,
            lw=1.8,
            color='black',
        )
    )
    ax.add_patch(Arc((-1.0, 0), .22, .42, theta1=75, theta2=285, lw=1.6, color='black'))
    ax.add_patch(Arc((1.0, 0), .22, .42, theta1=-105, theta2=105, lw=1.6, color='black'))
    ax.set_aspect('equal')
    ax.set_xlim(-1.18, 1.18)
    ax.set_ylim(-1.12, 1.20)
    ax.axis('off')


def smooth_scalp_field(x, y, z):
    """Smooth display-only interpolation across the circular scalp.

    The electrode values themselves are not changed. The RBF is used only to
    render the field between electrodes and avoids polygonal nearest-neighbour
    wedges at the outer scalp boundary.
    """
    grid = np.linspace(-1.0, 1.0, 240)
    gx, gy = np.meshgrid(grid, grid)
    interpolator = Rbf(x, y, z, function='thin_plate', smooth=0.0)
    gz = interpolator(gx, gy)

    # Prevent display interpolation from overshooting the observed electrode
    # range. This affects only the rendered field, not any numerical result.
    gz = np.clip(gz, np.nanmin(z), np.nanmax(z))
    gz[gx * gx + gy * gy > 1.0] = np.nan
    return gx, gy, gz


def plot_topography(ax, df, title, limit=None):
    x, y = scalp_xy(df)
    z = df.difference_db_at_peak.to_numpy(float)
    sig = df.in_corrected_cluster_at_peak.astype(bool).to_numpy()
    gx, gy, gz = smooth_scalp_field(x, y, z)

    lim = symmetric_limit(z) if limit is None else float(limit)
    im = ax.pcolormesh(
        gx,
        gy,
        gz,
        shading='auto',
        cmap='RdBu_r',
        norm=TwoSlopeNorm(vmin=-lim, vcenter=0, vmax=lim),
    )

    n_sig = int(sig.sum())
    n_all = len(sig)
    nonsig = ~sig

    if np.any(nonsig):
        ax.scatter(x[nonsig], y[nonsig], s=8, c='0.60', alpha=0.55, zorder=3)

    if 0 < n_sig < n_all:
        ax.scatter(
            x[sig], y[sig],
            s=42,
            facecolors='none',
            edgecolors='black',
            linewidths=1.15,
            zorder=4,
        )
    elif n_sig == n_all:
        ax.scatter(x, y, s=8, c='0.30', alpha=0.60, zorder=3)

    draw_head(ax)
    ax.set_title(title, fontsize=11, fontweight='bold')
    return im, n_sig, n_all


def plot_rep_tfr(ax, contrast, title=None, limit=None):
    d = rep[rep.contrast == contrast]
    times, freqs, z = matrix_from_long(d, 'difference_db')
    _, _, membership = matrix_from_long(d, 'in_corrected_cluster')
    lim = symmetric_limit(z) if limit is None else float(limit)

    im = ax.pcolormesh(
        times,
        freqs,
        z,
        shading='auto',
        cmap='RdBu_r',
        norm=TwoSlopeNorm(vmin=-lim, vcenter=0, vmax=lim),
    )
    ax.contourf(
        times,
        freqs,
        membership.astype(float),
        levels=[0.5, 1.5],
        colors='none',
        hatches=['////'],
    )

    md = meta[meta.contrast == contrast].iloc[0]
    ax.scatter(
        [md.peak_time_s], [md.peak_frequency_hz],
        marker='o', s=42,
        facecolors='white', edgecolors='black', zorder=5,
    )
    ax.axvline(0, ls='--', lw=1, color='0.35')
    ax.set_xlabel('Time (s)')
    ax.set_ylabel('Frequency (Hz)')
    if title is None:
        title = f"{md['contrast_pretty']} at {md.peak_channel}"
    ax.set_title(title, fontsize=11, fontweight='bold')
    return im


# -------------------------------------------------------------------------
# Primary inferential/descriptive summary
# -------------------------------------------------------------------------
pm = meta[meta.contrast == PRIMARY].iloc[0]
fig = plt.figure(figsize=(16.5, 5.6), constrained_layout=True)
gs = fig.add_gridspec(1, 3, width_ratios=[1.35, 1.0, 1.0])

ax1 = fig.add_subplot(gs[0, 0])
im1 = plot_rep_tfr(
    ax1,
    PRIMARY,
    f"A. Representative channel {pm.peak_channel} | peak {pm.peak_frequency_hz:.0f} Hz, {pm.peak_time_s:.2f} s",
)
fig.colorbar(im1, ax=ax1, label='Memorize - Ignore (dB)')
ax1.text(
    0.01, -0.18,
    'Hatching = exact corrected-cluster membership at this channel',
    transform=ax1.transAxes,
    fontsize=9,
)

ax2 = fig.add_subplot(gs[0, 1])
tp = topo[topo.contrast == PRIMARY]
im2, n_sig, n_all = plot_topography(
    ax2,
    tp,
    f"B. Spatial snapshot at cluster peak\n{pm.peak_frequency_hz:.0f} Hz, {pm.peak_time_s:.2f} s",
)
fig.colorbar(im2, ax=ax2, shrink=.82, label='Memorize - Ignore (dB)')
if n_sig == n_all:
    membership_note = f'All {n_all} channels belong to the corrected cluster at the exact peak bin'
else:
    membership_note = f'Open circles = corrected-cluster channels at exact peak ({n_sig}/{n_all})'
ax2.text(.5, -.06, membership_note, transform=ax2.transAxes, ha='center', fontsize=8.5)

ax3 = fig.add_subplot(gs[0, 2])
s = subj[subj.contrast == PRIMARY]
y = s.cluster_mean_difference_db.to_numpy(float)
x = np.arange(1, len(y) + 1)
ax3.scatter(x, y, s=34)
ax3.plot(x, y, lw=.8, alpha=.5)
ax3.axhline(0, ls=':', lw=1, color='0.35')
ax3.axhline(y.mean(), ls='--', lw=1, color='0.35')
ax3.set_xticks(x)
ax3.set_xticklabels(s.subject, rotation=45)
ax3.set_ylabel('Cluster-mean difference (dB)')
ax3.set_xlabel('Subject')
ax3.set_title('C. Subject-level cluster summary', fontsize=11, fontweight='bold')
ax3.text(
    .03, .03,
    'Descriptive post-selection summary\n(not an independent inferential test)',
    transform=ax3.transAxes,
    fontsize=8.5,
    va='bottom',
    bbox=dict(boxstyle='round,pad=0.25', facecolor='white', alpha=0.75, edgecolor='0.75'),
)

fig.suptitle(
    f"STERN primary TF effect: Memorize - Ignore | corrected cluster p = {pm.cluster_p_display}",
    fontsize=15,
    fontweight='bold',
)
for ext in ('png', 'svg'):
    fig.savefig(
        figure_dir / f'stern_tf_Memorize_minus_Ignore_primary_summary_final.{ext}',
        dpi=300 if ext == 'png' else None,
    )
plt.close(fig)


# -------------------------------------------------------------------------
# Primary QC/descriptive summary
# -------------------------------------------------------------------------
fig, axes = plt.subplots(2, 2, figsize=(13.5, 9.2), constrained_layout=True)

d = sensor[sensor.contrast == PRIMARY]
times, freqs, z = matrix_from_long(d, 'sensor_average_difference_db')
lim = symmetric_limit(z)
im = axes[0, 0].pcolormesh(
    times, freqs, z,
    shading='auto', cmap='RdBu_r',
    norm=TwoSlopeNorm(vmin=-lim, vcenter=0, vmax=lim),
)
axes[0, 0].axvline(0, ls='--', lw=1, color='0.35')
axes[0, 0].set_xlabel('Time (s)')
axes[0, 0].set_ylabel('Frequency (Hz)')
axes[0, 0].set_title('A. Sensor-average difference (descriptive; no inferential overlay)', fontweight='bold')
fig.colorbar(im, ax=axes[0, 0], label='dB')

d = count[count.contrast == PRIMARY]
times, freqs, z = matrix_from_long(d, 'cluster_member_channel_count')
im = axes[0, 1].pcolormesh(times, freqs, z, shading='nearest', cmap='viridis', vmin=0, vmax=69)
axes[0, 1].set_xlabel('Time (s)')
axes[0, 1].set_ylabel('Frequency (Hz)')
axes[0, 1].set_title('B. Corrected-cluster membership count (QC)', fontweight='bold')
fig.colorbar(im, ax=axes[0, 1], label='Channels (0-69)')

bands = ['theta', 'alpha', 'beta']
windows = ['0-0.3 s', '0.3-0.8 s', '0.8-1.4 s']
mean = np.full((3, 3), np.nan)
neg = np.full((3, 3), np.nan)
for i, band in enumerate(bands):
    for j, window in enumerate(windows):
        row = bw[(bw.band == band) & (bw.window == window)].iloc[0]
        mean[i, j] = row.group_mean_difference_db
        neg[i, j] = row.subjects_memorize_lt_ignore

lim = symmetric_limit(mean)
im = axes[1, 0].imshow(
    mean, aspect='auto', cmap='RdBu_r',
    norm=TwoSlopeNorm(vmin=-lim, vcenter=0, vmax=lim),
)
axes[1, 0].set_xticks(range(3), windows)
axes[1, 0].set_yticks(range(3), bands)
axes[1, 0].set_title('C. Band/window sensitivity: group mean (descriptive)', fontweight='bold')
for i in range(3):
    for j in range(3):
        axes[1, 0].text(j, i, f'{mean[i, j]:.2f}', ha='center', va='center', fontsize=10)
fig.colorbar(im, ax=axes[1, 0], label='dB')

im = axes[1, 1].imshow(neg, aspect='auto', cmap='viridis', vmin=0, vmax=13)
axes[1, 1].set_xticks(range(3), windows)
axes[1, 1].set_yticks(range(3), bands)
axes[1, 1].set_title('D. Subjects with Memorize < Ignore (descriptive)', fontweight='bold')
for i in range(3):
    for j in range(3):
        axes[1, 1].text(j, i, f'{int(neg[i, j])}/13', ha='center', va='center', fontsize=10)
fig.colorbar(im, ax=axes[1, 1], label='Subjects')

fig.suptitle('STERN primary TF descriptive/QC summaries', fontsize=15, fontweight='bold')
for ext in ('png', 'svg'):
    fig.savefig(
        figure_dir / f'stern_tf_Memorize_minus_Ignore_qc_summary_final.{ext}',
        dpi=300 if ext == 'png' else None,
    )
plt.close(fig)


# -------------------------------------------------------------------------
# Secondary summary: use common symmetric scales across contrasts
# -------------------------------------------------------------------------
secondary_rep_limit = 0.0
secondary_topo_limit = 0.0
for contrast in SECONDARY:
    d = rep[rep.contrast == contrast]
    _, _, z = matrix_from_long(d, 'difference_db')
    secondary_rep_limit = max(secondary_rep_limit, symmetric_limit(z))
    dtop = topo[topo.contrast == contrast]
    secondary_topo_limit = max(
        secondary_topo_limit,
        symmetric_limit(dtop.difference_db_at_peak.to_numpy(float)),
    )

fig, axes = plt.subplots(2, 2, figsize=(14, 10), constrained_layout=True)
for row, contrast in enumerate(SECONDARY):
    md = meta[meta.contrast == contrast].iloc[0]

    im = plot_rep_tfr(
        axes[row, 0],
        contrast,
        f"{md.contrast_pretty} at {md.peak_channel} | peak {md.peak_frequency_hz:.0f} Hz, {md.peak_time_s:.2f} s",
        limit=secondary_rep_limit,
    )
    fig.colorbar(im, ax=axes[row, 0], label='Difference (dB)')

    tp = topo[topo.contrast == contrast]
    im2, n_sig, n_all = plot_topography(
        axes[row, 1],
        tp,
        f"Spatial snapshot at peak | corrected p {md.cluster_p_display}",
        limit=secondary_topo_limit,
    )
    fig.colorbar(im2, ax=axes[row, 1], shrink=.82, label='Difference (dB)')

    if n_sig == n_all:
        membership_note = f'All {n_all} channels belong to the corrected cluster at the exact peak bin'
    else:
        membership_note = f'Corrected-cluster channels at exact peak: {n_sig}/{n_all}'
    axes[row, 1].text(.5, -.06, membership_note, transform=axes[row, 1].transAxes, ha='center', fontsize=8.5)

fig.suptitle(
    'STERN secondary task-phase TF effects: exact peak snapshots and channel-specific masks',
    fontsize=15,
    fontweight='bold',
)
for ext in ('png', 'svg'):
    fig.savefig(
        figure_dir / f'stern_tf_secondary_phase_summary_final.{ext}',
        dpi=300 if ext == 'png' else None,
    )
plt.close(fig)


print('TF_VISUALIZATION_RENDER_PASSED')
for name in [
    'stern_tf_Memorize_minus_Ignore_primary_summary_final.png',
    'stern_tf_Memorize_minus_Ignore_qc_summary_final.png',
    'stern_tf_secondary_phase_summary_final.png',
]:
    path = figure_dir / name
    if not path.is_file() or path.stat().st_size < 10000:
        raise RuntimeError(f'Output missing or too small: {path}')
    print(f'OUTPUT={path}')
