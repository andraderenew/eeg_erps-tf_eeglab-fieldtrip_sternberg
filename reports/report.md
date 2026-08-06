# Scientific report

## Aim

To characterize condition-related ERP and oscillatory-power changes in the
EEGLAB STERN task using paired cluster-based permutation tests.

## Data

The analysis used 13 participants, 39 datasets, 9,678 epochs, 20,697 events,
69 scalp channels, and 125-Hz sampling.

## Methods

Pre-marked ICA components were removed and missing channels were interpolated.
ERPs used a −200 to 0 ms baseline. Time-frequency power used four-cycle
Hanning-window convolution from 4–30 Hz and a −0.48 to −0.16 s dB baseline.
All 8,192 paired permutations were evaluated.

## Primary ERP result

- Positive cluster, 440–552 ms, 50 channels, corrected p = 0.015869.
- Negative cluster, 632–760 ms, 66 channels, corrected p = 0.000366.

## Primary time-frequency result

- Negative cluster, 4–26 Hz and 0.00–1.40 s, 69 channels, corrected p = 0.000610.

## Interpretation

`Memorize − Ignore` is the primary event-matched letter-onset contrast. Probe
comparisons are secondary task-phase contrasts.

## Quality control

Final ERP and TF arrays contained no non-finite values. Six statistical
structures and the required public outputs passed final validation.

## Limitations

The sample contains 13 participants. Cluster inference is cluster-level rather
than sample-level. Probe contrasts mix task phase and event type. Raw EEG is
not redistributed.

## Reproducibility

See `scripts/`, `env/TOOL_VERSIONS.md`, `DATA_SOURCES.md`, and
`results/summaries/stern_final_validation.txt`.
