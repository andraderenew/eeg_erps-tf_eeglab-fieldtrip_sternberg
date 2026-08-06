#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
CONFIG_FILE="$REPO_ROOT/scripts/config.sh"
MATLAB_BIN="${MATLAB_BIN:-matlab}"
MATLAB_SCRIPT="$REPO_ROOT/scripts/05_erp_finalization/05_run_stern_erp_finalization.m"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: missing $CONFIG_FILE"
    echo "Copy scripts/config.example.sh to scripts/config.sh and set the local paths."
    exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

required_vars=(
    STERN_PROJECT
    STERN_RESULTS_DIR
)

for var_name in "${required_vars[@]}"; do
    if [[ -z "${!var_name:-}" ]]; then
        echo "ERROR: $var_name is not defined after sourcing $CONFIG_FILE"
        exit 1
    fi
done

if ! command -v "$MATLAB_BIN" >/dev/null 2>&1; then
    echo "ERROR: MATLAB command not found: $MATLAB_BIN"
    echo "Set MATLAB_BIN to the full MATLAB executable path if necessary."
    exit 1
fi

required_inputs=(
    "$STERN_RESULTS_DIR/mat/stern_all_channel_subject_erp.mat"
    "$STERN_RESULTS_DIR/mat/stern_erp_cluster_Memorize_minus_Ignore.mat"
    "$STERN_RESULTS_DIR/mat/stern_erp_cluster_Probe_minus_Memorize.mat"
    "$STERN_RESULTS_DIR/mat/stern_erp_cluster_Probe_minus_Ignore.mat"
    "$STERN_RESULTS_DIR/tables/stern_OZ_subject_level_erp.tsv"
    "$STERN_RESULTS_DIR/tables/stern_erp_cluster_results.tsv"
)

missing=0
for input_path in "${required_inputs[@]}"; do
    if [[ ! -f "$input_path" ]]; then
        echo "MISSING: $input_path"
        missing=1
    fi
done

if [[ "$missing" -ne 0 ]]; then
    echo
    echo "ERROR: required local ERP inputs are missing."
    echo "Do not publish or regenerate a release."
    echo "Rerun scripts 02–04 as needed, then execute this validation again."
    exit 1
fi

mkdir -p "$STERN_RESULTS_DIR/logs"
timestamp="$(date +%Y%m%d_%H%M%S)"
log_file="$STERN_RESULTS_DIR/logs/erp_finalization_hotfix_${timestamp}.log"

matlab_script_escaped="${MATLAB_SCRIPT//\'/\'\'}"

echo "Running renderer-safe ERP finalization..."
echo "Log: $log_file"

set +e
"$MATLAB_BIN" -batch \
    "try; run('$matlab_script_escaped'); catch ME; disp(getReport(ME,'extended','hyperlinks','off')); exit(1); end; exit(0);" \
    2>&1 | tee "$log_file"
matlab_status=${PIPESTATUS[0]}
set -e

if [[ "$matlab_status" -ne 0 ]]; then
    echo
    echo "ERROR: MATLAB validation or export failed."
    echo "Nothing should be committed. Inspect: $log_file"
    exit "$matlab_status"
fi

required_outputs=(
    "$STERN_RESULTS_DIR/figures/stern_grand_average_erp_OZ_final.png"
    "$STERN_RESULTS_DIR/figures/stern_grand_average_erp_OZ_final.svg"
    "$STERN_RESULTS_DIR/figures/stern_erp_cluster_representative_waveforms_final.png"
    "$STERN_RESULTS_DIR/figures/stern_erp_cluster_representative_waveforms_final.svg"
    "$STERN_RESULTS_DIR/tables/stern_OZ_grand_average_erp_final.tsv"
    "$STERN_RESULTS_DIR/summaries/stern_erp_finalization_summary.txt"
)

for output_path in "${required_outputs[@]}"; do
    if [[ ! -s "$output_path" ]]; then
        echo "ERROR: expected output missing or empty: $output_path"
        exit 1
    fi
done

echo
echo "ERP finalization passed all numeric and export checks."
echo "Inspect both waveform PNG files visually before committing."
echo
printf '  %s\n' "${required_outputs[@]}"
echo
git -C "$REPO_ROOT" status --short
