# Reproducible analysis scripts

The public scripts are the final MATLAB implementations used for the portfolio
analysis. Machine-specific paths were removed.

## Configuration

```bash
cp scripts/config.example.sh scripts/config.sh
nano scripts/config.sh
source scripts/config.sh
```

Raw EEG and large intermediate MAT/STUDY files are intentionally excluded from
GitHub.

## Analysis order

1. `01_audit/audit_stern_study.m`
2. `02_erp/02_run_stern_erp_analysis.m`
3. `03_erp_qc/03_run_stern_erp_qc.m`
4. `04_erp_statistics/04_run_stern_erp_cluster_statistics.m`
5. `05_erp_finalization/05_run_stern_erp_finalization.m`
6. `06_time_frequency/06_run_stern_tf_stage1.m`
7. `07_tf_primary_statistics/07_run_stern_tf_primary_cluster_statistics.m`
8. `08_tf_robustness/08_run_stern_tf_primary_robustness_qc.m`
9. `09_tf_secondary_statistics/09_run_stern_tf_secondary_phase_statistics.m`

## ERP finalization safeguards

The ERP finalization step now stops before figure export unless all of the
following checks pass:

- the all-channel ERP array has the expected `3 × 13 × 69 × 151` structure;
- all ERP values and time samples are finite and correctly ordered;
- the Oz slice from the all-channel MAT file exactly reproduces the independent
  subject-level Oz table created by script 02;
- baseline residuals, absolute amplitudes, and adjacent-sample changes remain
  below broad safety thresholds;
- every plotted line object contains the complete 151-sample waveform;
- waveform figures are successfully exported with MATLAB `painters` to both
  vector SVG and 300-dpi PNG;
- the exported PNG is non-empty and passes a basic raster-content check.

The script also writes
`results/tables/stern_OZ_grand_average_erp_final.tsv`, containing the complete
grand mean and SEM series used for the final Oz figure. This table should be
inspected together with the regenerated SVG and PNG before a maintenance
release is published.
