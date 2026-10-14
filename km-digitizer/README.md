# KM Plot Digitizer & IPD Reconstruction

Extracts survival curve data from published Kaplan-Meier plot images and reconstructs individual patient-level time-to-event data (IPD), producing a Word report with KM comparison plots, survival statistics, and hazard rate curves.

## Skill Structure

```
km-digitizer/
├── SKILL.md                     # Skill instructions and workflow
├── README.md                    # This file
├── DESIGN.md                    # Scope, inputs, and outputs (lifecycle design doc)
├── LICENSE                      # MIT
├── scripts/
│   ├── setup_wizard.py          # Interactive GUI to define axis boundaries and calibration points
│   ├── digitize_km.py           # Color-tracks curve pixels and calibrates pixel->data coordinates
│   ├── reconstruct_ipd.R        # Reconstructs individual patient TTE data via IPDfromKM
│   ├── verify_reconstruction.R  # Compares digitized vs reconstructed curves; PASS/FAIL gate
│   ├── plot_km_hazard.R         # KM comparison and B-spline hazard rate plots
│   ├── survival_stats.R         # Median and survival rates per arm
│   └── generate_report.py       # Assembles Word report from plots and statistics
└── evals/
    └── evals.json               # Evaluation scenarios
```

## Pipeline

```
PNG image
  → digitize_km.py          → km_digitized.json          (curve coordinates)
  → reconstruct_ipd.R       → ipd_combined.csv           (patient-level data)
  → verify_reconstruction.R → verification.json          (PASS/FAIL gate)
  → generate_report.py      → reconstruction_report.docx
```

The verification step is a hard gate: the report is only generated once the reconstructed KM curves match the digitized coordinates (MAE < 3 percentage points, max deviation < 5 percentage points per arm).

## Scripts

| Script | Language | Purpose |
|--------|----------|---------|
| `setup_wizard.py` | Python | Interactive GUI — click axis boundaries and calibration points to generate `config.json` |
| `digitize_km.py` | Python | Color-tracks curve pixels in the PNG; calibrates pixel→data coordinates; outputs digitized JSON |
| `reconstruct_ipd.R` | R | Reconstructs individual patient time-to-event data using `IPDfromKM::getIPD()` |
| `verify_reconstruction.R` | R | Compares digitized vs reconstructed curves per arm; PASS/FAIL verification gate |
| `plot_km_hazard.R` | R | KM comparison plot (digitized vs reconstructed) and B-spline hazard rate curve |
| `survival_stats.R` | R | Median and survival rates per arm via `survival::survfit()` |
| `generate_report.py` | Python | Assembles Word report from R-generated plots and survival statistics table |

## Quick Start

### 1. Obtain a KM plot of interest in PNG format and tell the agent where it is

### 2. Set up config

**Option A — Interactive wizard (manual clicks):**
```bash
python scripts/setup_wizard.py reference/KMPlot/<study>.png output/<study>/
```
The wizard opens a matplotlib window; click the axis boundaries and annotated calibration points, then enter number-at-risk values in the terminal.

**Option B — Automated (the agent does this when no display is available):** The agent reads the PNG to extract annotated values, runs a Python/OpenCV scan to find exact axis pixel positions, and writes `config.json` automatically. No user input required.

### 3. Digitize
```bash
python scripts/digitize_km.py output/<study>/config.json
```
Always inspect the `debug_image` output:
- **Green rectangle** — optimized plot region
- **Yellow dots** — tracked pixels for curve 0 (higher survival arm)
- **Magenta dots** — tracked pixels for curve 1 (lower survival arm)

### 4. Reconstruct IPD
```bash
Rscript scripts/reconstruct_ipd.R output/<study>/km_digitized.json output/<study>/
```

### 5. Verify reconstruction (mandatory gate)
```bash
Rscript scripts/verify_reconstruction.R \
  output/<study>/km_digitized.json \
  output/<study>/ipd_combined.csv \
  output/<study>/
```

### 6. Generate report
```bash
python scripts/generate_report.py \
  output/<study>/km_digitized.json \
  output/<study>/ipd_combined.csv \
  output/<study>/
```

## Report Contents

The generated `reconstruction_report.docx` contains:

1. **KM curve comparison** — digitized original (left) vs reconstructed from IPD (right)
2. **Survival statistics table** — N, Events n (%), median, and survival rates at NaR timepoints per arm
3. **Hazard rate plot** — B-spline smoothed hazard, truncated where any arm drops below 20% at risk
4. **Appendix** — original KM plot image

## Key Tips

- **Calibration is the biggest lever on accuracy** — use every annotated survival value printed on the plot, for both curves. RMSE < 1% is achievable with 5+ points per curve.
- **plot_region must come from pixel scanning**, not visual guessing — a few pixels of error in the left/right boundary translates to months of time shift.
- **number_at_risk keys must exactly match curve_names** — the reconstruction script matches by name.
- **Curves must be distinct colors** — the tracker cannot separate same-colored curves.

## Dependencies

**Python:** `opencv-python`, `numpy`, `python-docx`, `pandas`, `matplotlib`

**R packages:** `IPDfromKM`, `jsonlite`, `survival`, `survminer`, `bshazard`, `ggplot2`, `gridExtra`, `scales`

R is discovered via `PATH`; if `Rscript` is not on your `PATH`, set the `RSCRIPT_PATH` environment variable.
