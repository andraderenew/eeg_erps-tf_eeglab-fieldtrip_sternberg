# Reproducible analysis scripts

The public scripts are the final successful MATLAB implementations used for
the portfolio analysis. Machine-specific paths were removed.

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
