#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
CONFIG_FILE="$REPO_ROOT/scripts/config.sh"
MATLAB_BIN="${MATLAB_BIN:-matlab}"
MATLAB_SOURCE="$REPO_ROOT/scripts/05_erp_finalization/05_run_stern_erp_finalization.m"

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

if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 is required for source validation."
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
    echo "ERROR: required local ERP inputs are missing."
    exit 1
fi

mkdir -p "$STERN_RESULTS_DIR/logs"
timestamp="$(date +%Y%m%d_%H%M%S)"
log_file="$STERN_RESULTS_DIR/logs/erp_finalization_hotfix_${timestamp}.log"
ascii_script="$STERN_RESULTS_DIR/logs/05_run_stern_erp_finalization_ascii_${timestamp}.m"
ascii_audit="$STERN_RESULTS_DIR/logs/erp_finalization_ascii_audit_${timestamp}.txt"
preflight_script="$STERN_RESULTS_DIR/logs/matlab_ascii_preflight_${timestamp}.m"

python3 - "$MATLAB_SOURCE" "$ascii_script" "$ascii_audit" <<'PY'
from __future__ import annotations

import pathlib
import sys
import unicodedata

source_path = pathlib.Path(sys.argv[1])
out_path = pathlib.Path(sys.argv[2])
audit_path = pathlib.Path(sys.argv[3])

raw = source_path.read_bytes()
text = raw.decode("utf-8-sig", errors="strict")
text = text.replace("\r\n", "\n").replace("\r", "\n")

unicode_replacements = {
    "\u00a0": " ",
    "\u00b5": "u",
    "\u00d7": "x",
    "\u2010": "-",
    "\u2011": "-",
    "\u2012": "-",
    "\u2013": "-",
    "\u2014": "-",
    "\u2018": "'",
    "\u2019": "'",
    "\u201c": '"',
    "\u201d": '"',
    "\u2026": "...",
    "\u2212": "-",
}

changes: list[str] = []
out: list[str] = []

for index, char in enumerate(text):
    code = ord(char)
    line = text.count("\n", 0, index) + 1
    column = index - text.rfind("\n", 0, index)

    if char in ("\n", "\t"):
        out.append(char)
        continue

    if 32 <= code <= 126:
        out.append(char)
        continue

    if code < 32 or code == 127:
        changes.append(
            f"line={line} column={column} codepoint=U+{code:04X} "
            "kind=control replacement=''"
        )
        continue

    replacement = unicode_replacements.get(char)
    if replacement is None:
        replacement = unicodedata.normalize("NFKD", char).encode(
            "ascii", "ignore"
        ).decode("ascii")

    changes.append(
        f"line={line} column={column} codepoint=U+{code:04X} "
        f"kind=unicode replacement={replacement!r}"
    )
    out.append(replacement)

ascii_text = "".join(out)
ascii_bytes = ascii_text.encode("ascii", errors="strict")

allowed = set(range(32, 127)) | {9, 10}
invalid = [(i, byte) for i, byte in enumerate(ascii_bytes) if byte not in allowed]
if invalid:
    raise SystemExit(f"Disallowed bytes remain: {invalid[:20]}")

out_path.write_bytes(ascii_bytes)

audit_lines = [
    f"source={source_path}",
    f"ascii_copy={out_path}",
    f"source_bytes={len(raw)}",
    f"ascii_bytes={len(ascii_bytes)}",
    f"replacements={len(changes)}",
]
audit_lines.extend(changes)
audit_path.write_text("\n".join(audit_lines) + "\n", encoding="ascii")

print(f"ASCII_SCRIPT={out_path}")
print(f"ASCII_AUDIT={audit_path}")
print(f"SOURCE_BYTES={len(raw)}")
print(f"ASCII_BYTES={len(ascii_bytes)}")
print(f"REPLACEMENTS={len(changes)}")
PY

cat > "$preflight_script" <<'MATLAB'
fprintf('MATLAB_ASCII_PREFLIGHT_OK\n');
fprintf('MATLAB_VERSION=%s\n', version);
MATLAB

preflight_escaped="${preflight_script//\'/\'\'}"

set +e
"$MATLAB_BIN" -batch \
    "try; run('$preflight_escaped'); catch ME; disp(getReport(ME,'extended','hyperlinks','off')); exit(1); end; exit(0);"
preflight_status=$?
set -e

if [[ "$preflight_status" -ne 0 ]]; then
    echo "ERROR: MATLAB cannot run the minimal strict-ASCII preflight script."
    echo "Preflight: $preflight_script"
    exit "$preflight_status"
fi

matlab_script_escaped="${ascii_script//\'/\'\'}"

echo "Running renderer-safe ERP finalization..."
echo "MATLAB source: $MATLAB_SOURCE"
echo "Strict ASCII execution copy: $ascii_script"
echo "ASCII audit: $ascii_audit"
echo "Log: $log_file"

set +e
"$MATLAB_BIN" -batch \
    "try; run('$matlab_script_escaped'); catch ME; disp(getReport(ME,'extended','hyperlinks','off')); exit(1); end; exit(0);" \
    2>&1 | tee "$log_file"
matlab_status=${PIPESTATUS[0]}
set -e

if [[ "$matlab_status" -ne 0 ]]; then
    echo "ERROR: MATLAB validation or export failed."
    echo "Nothing should be committed. Inspect: $log_file"
    echo "ASCII audit: $ascii_audit"
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
printf '  %s\n' "${required_outputs[@]}"
echo
git -C "$REPO_ROOT" status --short
