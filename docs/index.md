# EEG: ERPs & Time–Frequency (EEGLAB/FieldTrip, Sternberg)

**Goal:** Preprocess EEG, compute ERPs and time–frequency (TF), and test condition differences with cluster-based permutation.

---

## Snapshot
- **Dataset:** EEGLAB Sternberg (multi-subject tutorial)
- **Local subset:** <N subjects> · **Disk:** ~0.4–1 GB depending on subset
- **Tools:** EEGLAB (preproc/ERPs), FieldTrip (TF + cluster stats)
- **Status:** <planned / in progress / complete>
- **Last updated:** <YYYY-MM-DD>

---

## Data
- **Source:** EEGLAB tutorial dataset.  
- **What I downloaded:** list subjects/sessions.  
- **Layout:** subject folders; note montage/reference.

---

## Pipeline (high-level)
1) Filter, bad channel handling, ICA artifact removal  
2) Epoching by condition → ERPs  
3) TF (wavelets or multitaper)  
4) Cluster-based permutation for condition effects

---

## Results (to be filled)
- Figure: ERP grand-average + topomaps  
- Figure: TF difference map with significant clusters

---

## Reproducibility
- Versions in `env/TOOL_VERSIONS.md`.  
- Steps: “EEGLAB preproc → ERPs → TF → FieldTrip stats → export figures.”  
- Limitations: small sample; montage differences.

---

**Author:** Rene Andrade Rey · 🧪 ORCID: https://orcid.org/0000-0001-5627-579X · 🌐 Scholar: https://scholar.google.es/citations?hl=es&user=Nl3ApFEAAAAJ
