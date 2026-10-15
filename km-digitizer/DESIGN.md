# Design: km-digitizer

## Problem

Published oncology papers report survival results only as Kaplan-Meier figures. Meta-analyses, indirect comparisons, and trial design (e.g., piecewise hazard assumptions for a control arm) need the underlying patient-level time-to-event data, which is rarely shared.

## Scope

Digitize a two-arm KM plot from a PNG image, reconstruct individual patient data (IPD) with the Guyot-style algorithm implemented in `IPDfromKM`, verify the reconstruction against the digitized curve, and produce a Word report.

In scope:
- PNG/JPG images of KM plots with two distinctly colored curves
- Number-at-risk tables (required for IPD reconstruction)
- Calibration from survival values annotated on the figure
- Interactive (GUI click) or fully automated (agent-driven pixel scan) configuration

Out of scope:
- Same-colored or dashed-vs-solid monochrome curves
- Plots with more than two arms (digitizer tracks two curves)
- Cumulative incidence / competing-risk figures

## Inputs

- A KM plot image (local path or publication URL)
- Axis ranges, curve names, annotated survival values, number-at-risk table (read from the figure by the user via the wizard, or by the agent from the image)

## Outputs

- `km_digitized.json` — calibrated curve coordinates
- `ipd_<arm>.csv` / `ipd_combined.csv` — reconstructed patient-level `time, event, arm` data
- `verification.json` — per-arm MAE / max-deviation PASS/FAIL gate
- `reconstruction_report.docx` — KM comparison, survival statistics table, hazard rate plot

## Quality gate

Report generation is blocked until every arm passes verification: mean absolute error < 3 percentage points and maximum deviation < 5 percentage points between the digitized curve and the KM curve refit from the reconstructed IPD.
