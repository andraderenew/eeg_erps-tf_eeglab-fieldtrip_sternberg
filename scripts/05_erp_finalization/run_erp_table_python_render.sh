#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
CONFIG_FILE="$REPO_ROOT/scripts/config.sh"
MATLAB_BIN="${MATLAB_BIN:-matlab}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
MATLAB_EXPORT_SCRIPT="$REPO_ROOT/scripts/05_erp_finalization/export_stern_erp_waveform_tables.m"
PYTHON_RENDER_SCRIPT="$REPO_ROOT/scripts/05_erp_finalization/render_stern_erp_figures.py"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: missing $CONFIG_FILE"
    exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

for var_name in STERN_PROJECT STERN_RESULTS_DIR; do
    if [[ -z "${!var_name:-}" ]]; then
        echo "ERROR: $var_name is not defined after sourcing $CONFIG_FILE"
        exit 1
    fi
done

if ! command -v "$MATLAB_BIN" >/dev/null 2>&1; then
    echo "ERROR: MATLAB command not found: $MATLAB_BIN"
    exit 1
fi

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
    echo "ERROR: Python command not found: $PYTHON_BIN"
    exit 1
fi

"$PYTHON_BIN" - <<'PY'
import importlib
for module in ("numpy", "matplotlib"):
    importlib.import_module(module)
print("PYTHON_RENDER_DEPENDENCIES_OK")
PY

required_inputs=(
    "$STERN_RESULTS_DIR/mat/stern_all_channel_subject_erp.mat"
    "$STERN_RESULTS_DIR/mat/stern_erp_cluster_Memorize_minus_Ignore.mat"
    "$STERN_RESULTS_DIR/mat/stern_erp_cluster_Probe_minus_Memorize.mat"
    "$STERN_RESULTS_DIR/mat/stern_erp_cluster_Probe_minus_Ignore.mat"
)

missing=0
for input_path in "${required_inputs[@]}"; do
    if [[ ! -f "$input_path" ]]; then
        echo "MISSING: $input_path"
        missing=1
    fi
done

if [[ "$missing" -ne 0 ]]; then
    echo "ERROR: required ERP inputs are missing."
    exit 1
fi

mkdir -p "$STERN_RESULTS_DIR/logs"
timestamp="$(date +%Y%m%d_%H%M%S)"
log_dir="$STERN_RESULTS_DIR/logs"
matlab_log="$log_dir/erp_waveform_table_export_${timestamp}.log"
python_log="$log_dir/erp_python_render_${timestamp}.log"
backup_dir="$log_dir/before_python_render_${timestamp}"
mkdir -p "$backup_dir"

for existing_output in \
    "$STERN_RESULTS_DIR/figures/stern_grand_average_erp_OZ_final.png" \
    "$STERN_RESULTS_DIR/figures/stern_grand_average_erp_OZ_final.svg" \
    "$STERN_RESULTS_DIR/figures/stern_erp_cluster_representative_waveforms_final.png" \
    "$STERN_RESULTS_DIR/figures/stern_erp_cluster_representative_waveforms_final.svg"
do
    if [[ -f "$existing_output" ]]; then
        cp -p "$existing_output" "$backup_dir/"
    fi
done

matlab_script_escaped="${MATLAB_EXPORT_SCRIPT//\'/\'\'}"

echo "Exporting validated ERP waveform tables with MATLAB..."
echo "MATLAB log: $matlab_log"

set +e
"$MATLAB_BIN" -batch \
    "try; run('$matlab_script_escaped'); catch ME; disp(getReport(ME,'extended','hyperlinks','off')); exit(1); end; exit(0);" \
    2>&1 | tee "$matlab_log"
matlab_status=${PIPESTATUS[0]}
set -e

if [[ "$matlab_status" -ne 0 ]]; then
    echo "ERROR: MATLAB waveform table export failed."
    echo "Nothing should be committed. Inspect: $matlab_log"
    exit "$matlab_status"
fi

required_tables=(
    "$STERN_RESULTS_DIR/tables/stern_OZ_grand_average_erp_final.tsv"
    "$STERN_RESULTS_DIR/tables/stern_erp_representative_waveforms_final.tsv"
)

for table_path in "${required_tables[@]}"; do
    if [[ ! -s "$table_path" ]]; then
        echo "ERROR: expected table missing or empty: $table_path"
        exit 1
    fi
done

echo
echo "Rendering ERP figures from TSV tables with Python/Matplotlib..."
echo "Python log: $python_log"

set +e
"$PYTHON_BIN" "$PYTHON_RENDER_SCRIPT" \
    --results-dir "$STERN_RESULTS_DIR" \
    2>&1 | tee "$python_log"
python_status=${PIPESTATUS[0]}
set -e

if [[ "$python_status" -ne 0 ]]; then
    echo "ERROR: Python ERP rendering failed."
    echo "Original MATLAB-rendered files were preserved in: $backup_dir"
    echo "Inspect: $python_log"
    exit "$python_status"
fi

required_outputs=(
    "$STERN_RESULTS_DIR/figures/stern_grand_average_erp_OZ_final.png"
    "$STERN_RESULTS_DIR/figures/stern_grand_average_erp_OZ_final.svg"
    "$STERN_RESULTS_DIR/figures/stern_erp_cluster_representative_waveforms_final.png"
    "$STERN_RESULTS_DIR/figures/stern_erp_cluster_representative_waveforms_final.svg"
)

for output_path in "${required_outputs[@]}"; do
    if [[ ! -s "$output_path" ]]; then
        echo "ERROR: expected rendered output missing or empty: $output_path"
        exit 1
    fi
done

echo
echo "ERP table export and Python rendering passed."
echo "Previous figures were preserved in: $backup_dir"
echo "Inspect the two new PNG files visually before copying them to Git."
printf '  %s\n' "${required_outputs[@]}"
