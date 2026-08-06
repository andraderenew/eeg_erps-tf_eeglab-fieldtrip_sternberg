#!/usr/bin/env bash

# Copy to scripts/config.sh and edit for your system.
export STERN_PROJECT="/path/to/eeg_erps-tf_eeglab-fieldtrip_sternberg"
export EEGLAB_DIR="/path/to/eeglab2025.1.0"
export FIELDTRIP_DIR="/path/to/fieldtrip-20251218"

export STERN_DATA_ROOT="$STERN_PROJECT/raw/STUDYstern"
export STERN_WORK_DATA="$STERN_PROJECT/work/study_datasets"
export STERN_STUDY_DIR="$STERN_PROJECT/work/eeglab_study"
export STERN_RESULTS_DIR="$STERN_PROJECT/results"
export STERN_LOG_DIR="$STERN_PROJECT/logs"
export STERN_AUDIT_DIR="$STERN_PROJECT/work/audit"
