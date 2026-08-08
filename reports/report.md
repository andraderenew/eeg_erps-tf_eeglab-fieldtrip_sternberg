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

Final ERP and TF figures were audited separately from the statistical
computation. Numerical values and corrected-cluster masks are exported to TSV
before final Matplotlib rendering. TF inferential panels use exact
channel-specific corrected-cluster masks and exact peak-bin scalp snapshots;
descriptive sensor averages are kept separate from inferential overlays.

## Primary ERP result

- Positive cluster, 440–552 ms, 50 channels, corrected p = 0.015869.
- Negative cluster, 632–760 ms, 66 channels, corrected p = 0.000366.

## Primary time-frequency result

- Negative cluster, 4–26 Hz and 0.00–1.40 s, 69 channels, corrected p = 0.000610.
- Exact corrected-cluster peak used for the representative primary TF summary:
  CP3, 8 Hz, 0.40 s.

## Secondary task-phase results

- Probe − Memorize: negative cluster, 6–30 Hz and 0.00–1.40 s,
  corrected p < 0.000122.
- Probe − Ignore: negative cluster, 6–30 Hz and 0.00–1.40 s,
  corrected p < 0.000122.

## Interpretation

`Memorize − Ignore` is the primary event-matched letter-onset contrast. Probe
comparisons are secondary task-phase contrasts and should not be interpreted as
pure encoding effects.

Subject-level values extracted from a cluster selected using the same sample
are reported descriptively as post-selection summaries, not as independent
confirmatory inference.

## Quality control

Final ERP and TF arrays contained no non-finite values. Six statistical
structures passed validation. The public visualization set was subsequently
audited: misleading bounding-box TF topographies and mixed sensor-average/
cluster-mask displays were replaced by exact-mask/exact-peak summaries, and
superseded diagnostic figures were removed from the public figure directory.

## Limitations

The sample contains 13 participants. Cluster inference is cluster-level rather
than sample-level. Probe contrasts mix task phase and event type. Subject-level
cluster summaries are post-selection descriptive summaries. Raw EEG is not
redistributed.

## Reproducibility

See `scripts/`, `env/TOOL_VERSIONS.md`, `DATA_SOURCES.md`,
`results/summaries/stern_final_validation.txt`, and
`results/summaries/stern_tf_visualization_redesign_summary.txt`.
