#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${STERN_PROJECT:-$HOME/github/eeg_erps-tf_eeglab-fieldtrip_sternberg}"
RESULTS_DIR="${STERN_RESULTS_DIR:-}"
MATLAB_BIN="${MATLAB_BIN:-/usr/local/bin/matlab}"
PYTHON_BIN="${PYTHON_BIN:-$(command -v python3 || true)}"

if [[ -f "$PROJECT_DIR/scripts/config.sh" ]]; then
  # shellcheck disable=SC1090
  source "$PROJECT_DIR/scripts/config.sh"
  RESULTS_DIR="${STERN_RESULTS_DIR:-$RESULTS_DIR}"
fi

: "${RESULTS_DIR:?STERN_RESULTS_DIR is required}"
[[ -x "$MATLAB_BIN" ]] || { echo "ERROR: MATLAB not executable: $MATLAB_BIN"; exit 1; }
[[ -n "$PYTHON_BIN" && -x "$PYTHON_BIN" ]] || { echo "ERROR: python3 not found"; exit 1; }

export STERN_PROJECT="$PROJECT_DIR"
export STERN_RESULTS_DIR="$RESULTS_DIR"

REQ=(
  "$RESULTS_DIR/mat/stern_subject_level_tfr_db.mat"
  "$RESULTS_DIR/mat/stern_all_channel_subject_erp.mat"
  "$RESULTS_DIR/mat/stern_tf_cluster_Memorize_minus_Ignore.mat"
  "$RESULTS_DIR/mat/stern_tf_cluster_Probe_minus_Memorize.mat"
  "$RESULTS_DIR/mat/stern_tf_cluster_Probe_minus_Ignore.mat"
)
for f in "${REQ[@]}"; do
  [[ -s "$f" ]] || { echo "ERROR: missing required input: $f"; exit 1; }
done

"$PYTHON_BIN" - <<'PY'
import importlib
for name in ('numpy','pandas','matplotlib','scipy'):
    importlib.import_module(name)
print('PYTHON_TF_RENDER_DEPENDENCIES_OK')
PY

EXPORTER="$PROJECT_DIR/scripts/10_tf_visualization_redesign/export_stern_tf_visualization_tables.m"
RENDERER="$PROJECT_DIR/scripts/10_tf_visualization_redesign/render_stern_tf_visualizations.py"
[[ -s "$EXPORTER" ]] || { echo "ERROR: missing exporter: $EXPORTER"; exit 1; }
[[ -s "$RENDERER" ]] || { echo "ERROR: missing renderer: $RENDERER"; exit 1; }

mkdir -p "$RESULTS_DIR/logs" "$RESULTS_DIR/figures" "$RESULTS_DIR/tables" "$RESULTS_DIR/summaries"
STAMP="$(date +%Y%m%d_%H%M%S)"
MATLOG="$RESULTS_DIR/logs/tf_visualization_export_${STAMP}.log"
PYLOG="$RESULTS_DIR/logs/tf_visualization_render_${STAMP}.log"

printf '\n=== EXPORTING VALIDATED TF VISUALIZATION TABLES ===\n'
"$MATLAB_BIN" -batch "run('$EXPORTER')" 2>&1 | tee "$MATLOG"
grep -q 'TF_VISUALIZATION_TABLE_EXPORT_PASSED' "$MATLOG" || { echo "ERROR: MATLAB table export did not pass"; exit 1; }

printf '\n=== RENDERING REDESIGNED TF FIGURES ===\n'
"$PYTHON_BIN" "$RENDERER" 2>&1 | tee "$PYLOG"
grep -q 'TF_VISUALIZATION_RENDER_PASSED' "$PYLOG" || { echo "ERROR: Python rendering did not pass"; exit 1; }

OUT=(
  "$RESULTS_DIR/figures/stern_tf_Memorize_minus_Ignore_primary_summary_final.png"
  "$RESULTS_DIR/figures/stern_tf_Memorize_minus_Ignore_primary_summary_final.svg"
  "$RESULTS_DIR/figures/stern_tf_Memorize_minus_Ignore_qc_summary_final.png"
  "$RESULTS_DIR/figures/stern_tf_Memorize_minus_Ignore_qc_summary_final.svg"
  "$RESULTS_DIR/figures/stern_tf_secondary_phase_summary_final.png"
  "$RESULTS_DIR/figures/stern_tf_secondary_phase_summary_final.svg"
  "$RESULTS_DIR/tables/stern_tf_visualization_representative_tfr.tsv"
  "$RESULTS_DIR/tables/stern_tf_visualization_peak_topographies.tsv"
  "$RESULTS_DIR/tables/stern_tf_visualization_subject_cluster_values.tsv"
  "$RESULTS_DIR/tables/stern_tf_visualization_channel_count.tsv"
  "$RESULTS_DIR/tables/stern_tf_visualization_sensor_average_descriptive.tsv"
  "$RESULTS_DIR/tables/stern_tf_visualization_metadata.tsv"
  "$RESULTS_DIR/tables/stern_tf_visualization_band_window_descriptive.tsv"
  "$RESULTS_DIR/summaries/stern_tf_visualization_redesign_summary.txt"
)
for f in "${OUT[@]}"; do
  [[ -s "$f" ]] || { echo "ERROR: expected output missing: $f"; exit 1; }
done

printf '\nTF_VISUALIZATION_REDESIGN_PASSED\n'
printf 'MATLAB_LOG=%s\n' "$MATLOG"
printf 'PYTHON_LOG=%s\n' "$PYLOG"
printf '\nInspect these three PNG files before any Git commit:\n'
printf '  %s\n' \
  "$RESULTS_DIR/figures/stern_tf_Memorize_minus_Ignore_primary_summary_final.png" \
  "$RESULTS_DIR/figures/stern_tf_Memorize_minus_Ignore_qc_summary_final.png" \
  "$RESULTS_DIR/figures/stern_tf_secondary_phase_summary_final.png"
