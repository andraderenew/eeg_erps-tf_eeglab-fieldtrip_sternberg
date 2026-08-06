#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
CONFIG_FILE="$REPO_ROOT/scripts/config.sh"
MATLAB_BIN="${MATLAB_BIN:-matlab}"
MATLAB_SOURCE="$REPO_ROOT/scripts/05_erp_finalization/05_run_stern_erp_finalization.m"

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

if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 is required for the strict ASCII source check."
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
    echo "Rerun scripts 02-04 as needed, then execute this validation again."
    exit 1
fi

mkdir -p "$STERN_RESULTS_DIR/logs"
timestamp="$(date +%Y%m%d_%H%M%S)"
log_file="$STERN_RESULTS_DIR/logs/erp_finalization_hotfix_${timestamp}.log"
ascii_script="$STERN_RESULTS_DIR/logs/05_run_stern_erp_finalization_ascii_${timestamp}.m"
ascii_audit="$STERN_RESULTS_DIR/logs/erp_finalization_ascii_audit_${timestamp}.txt"

# MATLAB installations can reject otherwise valid UTF-8 source when a script
# contains an invisible non-ASCII character. Build an auditable strict-ASCII
# execution copy. Numeric data and paths are not transformed.
python3 - "$MATLAB_SOURCE" "$ascii_script" "$ascii_audit" <<'PY'
from __future__ import annotations

import pathlib
import sys
import unicodedata

source_path = pathlib.Path(sys.argv[1])
out_path = pathlib.Path(sys.argv[2])
audit_path = pathlib.Path(sys.argv[3])

text = source_path.read_text(encoding="utf-8-sig")

replacements = {
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
normalized_parts: list[str] = []

for index, char in enumerate(text):
    if ord(char) < 128:
        normalized_parts.append(char)
        continue

    replacement = replacements.get(char)
    if replacement is None:
        replacement = unicodedata.normalize("NFKD", char).encode(
            "ascii", "ignore"
        ).decode("ascii")

    line = text.count("\n", 0, index) + 1
    column = index - text.rfind("\n", 0, index)
    changes.append(
        f"line={line} column={column} "
        f"codepoint=U+{ord(char):04X} replacement={replacement!r}"
    )
    normalized_parts.append(replacement)

ascii_text = "".join(normalized_parts)

try:
    ascii_bytes = ascii_text.encode("ascii", "strict")
except UnicodeEncodeError as exc:
    raise SystemExit(f"ASCII conversion failed: {exc}") from exc

out_path.write_bytes(ascii_bytes)

audit_lines = [
    f"source={source_path}",
    f"ascii_copy={out_path}",
    f"source_characters={len(text)}",
    f"ascii_bytes={len(ascii_bytes)}",
    f"non_ascii_replacements={len(changes)}",
]
audit_lines.extend(changes)
audit_path.write_text("\n".join(audit_lines) + "\n", encoding="ascii")

print(f"ASCII_SCRIPT={out_path}")
print(f"ASCII_AUDIT={audit_path}")
print(f"NON_ASCII_REPLACEMENTS={len(changes)}")
PY

if [[ ! -s "$ascii_script" ]]; then
    echo "ERROR: strict ASCII MATLAB copy was not created."
    exit 1
fi

if LC_ALL=C grep -n '[^ -~	]' "$ascii_script" >/dev/null 2>&1; then
    echo "ERROR: non-ASCII bytes remain in $ascii_script"
    exit 1
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
    echo
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
echo
printf '  %s\n' "${required_outputs[@]}"
echo
git -C "$REPO_ROOT" status --short
