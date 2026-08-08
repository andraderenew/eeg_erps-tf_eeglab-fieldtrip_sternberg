# Reproducible analysis scripts

The public scripts reproduce the final portfolio analysis with machine-specific paths removed.

## Configuration

```bash
cp scripts/config.example.sh scripts/config.sh
nano scripts/config.sh
source scripts/config.sh
```

Raw EEG and large intermediate MAT/STUDY files are intentionally excluded from GitHub.

## Analysis order

1. `01_audit/audit_stern_study.m`
2. `02_erp/02_run_stern_erp_analysis.m`
3. `03_erp_qc/03_run_stern_erp_qc.m`
4. `04_erp_statistics/04_run_stern_erp_cluster_statistics.m`
5. `05_erp_finalization/run_erp_table_python_render.sh`
6. `06_time_frequency/06_run_stern_tf_stage1.m`
7. `07_tf_primary_statistics/07_run_stern_tf_primary_cluster_statistics.m`
8. `08_tf_robustness/08_run_stern_tf_primary_robustness_qc.m`
9. `09_tf_secondary_statistics/09_run_stern_tf_secondary_phase_statistics.m`
10. `10_tf_visualization_redesign/run_tf_visualization_redesign.sh`

## ERP finalization

The final ERP stage deliberately separates numerical validation from figure rendering.

`export_stern_erp_waveform_tables.m` runs in MATLAB and:

- checks the expected `3 x 13 x 69 x 151` ERP structure;
- requires finite, ordered samples spanning -200 to 1000 ms;
- independently reconstructs Oz from `stern_OZ_subject_level_erp.tsv`;
- requires the all-channel Oz slice and the independently exported Oz table to agree within a `1e-5 uV` TSV round-trip tolerance;
- checks baseline residuals, absolute amplitudes, and adjacent-sample changes against broad safety thresholds;
- exports complete grand-mean/SEM and representative-waveform TSV tables;
- regenerates the final cluster table and ERP finalization summary.

`render_stern_erp_figures.py` then reads only the validated TSV waveform tables and renders the final ERP PNG and SVG figures with Matplotlib. MATLAB is not used to render the final ERP waveforms.

The canonical wrapper is:

```bash
bash scripts/05_erp_finalization/run_erp_table_python_render.sh
```

The final waveform tables are:

- `results/tables/stern_OZ_grand_average_erp_final.tsv`
- `results/tables/stern_erp_representative_waveforms_final.tsv`

The final waveform figures are:

- `results/figures/stern_grand_average_erp_OZ_final.png`
- `results/figures/stern_grand_average_erp_OZ_final.svg`
- `results/figures/stern_erp_cluster_representative_waveforms_final.png`
- `results/figures/stern_erp_cluster_representative_waveforms_final.svg`

The tables are the auditable numerical source for the final figures.

## TF visualization redesign

The final TF visualization stage also separates numerical extraction from rendering. It does not rerun the TFR computation or the cluster-permutation statistics.

`export_stern_tf_visualization_tables.m` runs in MATLAB and:

- reads the validated subject-level TFR array and the three saved TF statistical structures;
- reconstructs corrected significant-cluster masks from the stored cluster labels/probabilities;
- verifies the expected TFR/statistical dimensions and finite values;
- identifies the exact peak channel, frequency, and time inside each corrected cluster;
- exports the representative-channel TFR values together with the exact channel-specific corrected-cluster mask;
- exports spatial values and cluster membership at the exact peak bin, rather than averaging a large bounding rectangle around the cluster extent;
- exports descriptive sensor-average, channel-count, subject-level cluster, and band/window QC tables;
- labels subject-level summaries as descriptive post-selection summaries rather than independent inferential tests.

`render_stern_tf_visualizations.py` then reads only these TSV tables and renders the final TF PNG/SVG figures with Matplotlib. The inferential panels keep statistical masks separate from descriptive sensor averages.

The canonical wrapper is:

```bash
bash scripts/10_tf_visualization_redesign/run_tf_visualization_redesign.sh
```

The main TF figures are:

- `results/figures/stern_tf_Memorize_minus_Ignore_primary_summary_final.png`
- `results/figures/stern_tf_Memorize_minus_Ignore_primary_summary_final.svg`
- `results/figures/stern_tf_secondary_phase_summary_final.png`
- `results/figures/stern_tf_secondary_phase_summary_final.svg`

The descriptive/QC summary is:

- `results/figures/stern_tf_Memorize_minus_Ignore_qc_summary_final.png`
- `results/figures/stern_tf_Memorize_minus_Ignore_qc_summary_final.svg`

The exported TF visualization tables are the auditable numerical source for these figures.
