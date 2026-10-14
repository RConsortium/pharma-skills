---
name: km-digitizer
description: Digitize Kaplan-Meier survival curves from PNG images, reconstruct individual patient-level time-to-event data (IPDfromKM), and generate Word reports with KM comparison plots, survival statistics, and hazard rate curves. Use this skill whenever the user wants to extract data from a KM plot image, digitize a survival curve, convert a KM plot to numbers/CSV/JSON, read survival data from a published figure, reconstruct IPD from a KM curve, or reverse-engineer patient-level data from published KM plots. Also use this skill when the user wants an interactive setup wizard to click axis limits or calibration points on a KM figure.
---

# KM Plot Digitizer & IPD Reconstruction

Full pipeline: PNG image -> digitized coordinates -> individual patient data -> Word report.

## Ask User First

Before starting, ask the user: **"What is the KM plot and where is the PNG file located? (You can provide a local file path or a URL to a publication.)"**

Wait for their answer before proceeding. You need to know the file path and what the plot shows (endpoint, treatment arms, axis ranges) to set up the config correctly.

### If the user provides a publication URL

1. Use WebFetch to load the page HTML
2. Look for figure image URLs — search for `<img>` tags or `<figure>` elements containing KM/survival/Kaplan-Meier references. Common patterns:
   - NEJM: look for image URLs containing `/full/` or `/figure/`
   - Lancet/JCO: look for high-res figure links, often ending in `.jpg` or `.png`
   - PubMed Central: figures are usually at predictable URLs like `https://www.ncbi.nlm.nih.gov/pmc/articles/PMC.../figure/...`
3. Download the KM plot image and save to `reference/KMPlot/<study_name>.png`
4. If the page is paywalled or the image can't be found, ask the user to download the figure manually and provide the local file path
5. If the KM plot is inside a PDF, use the pdf skill to extract the page as an image first

## Pipeline Overview

```
PNG image
  -> digitize_km.py        -> output/<study>/km_digitized.json    (coordinates)
  -> reconstruct_ipd.R     -> output/<study>/ipd_combined.csv     (patient-level data)
  -> verify_reconstruction.R -> output/<study>/verification.json  (PASS/FAIL gate)
  -> generate_report.py    -> output/<study>/reconstruction_report.docx
```

**The verification step is a hard gate: do not proceed to the report if it fails.**

**Scripts** (all in the skill's `scripts/` directory):

| Script | Purpose |
|--------|---------|
| `setup_wizard.py` | **Interactive setup** — click axis boundaries + calibration points to generate config.json |
| `digitize_km.py` | Extract curve coordinates from PNG via color detection + tracking |
| `reconstruct_ipd.R` | Reverse-engineer individual patient TTE data using `IPDfromKM` |
| `verify_reconstruction.R` | **Verification** — compare digitized vs reconstructed curves; PASS/FAIL gate |
| `plot_km_hazard.R` | KM comparison (survfit/ggsurvplot) and hazard rate (bshazard) plots |
| `survival_stats.R` | Median and survival rates per arm via `survival::survfit()` |
| `generate_report.py` | Word report assembling R-generated plots and survival stats table |

## Step 1: Create config — via wizard (preferred) or manually

### Option A: Interactive wizard (preferred)

Run the setup wizard. The user clicks directly on the image to mark the axis boundaries and calibration points:

```bash
python scripts/setup_wizard.py \
  reference/KMPlot/<study>.png \
  output/<study>/
```

The wizard will:
1. Display the image in a matplotlib window
2. Ask the user to click: left edge, right edge, 100% gridline, x-axis (4 clicks)
3. Ask the user to click annotated calibration points and type their time/survival% values
4. Collect number-at-risk table values via terminal prompts
5. Write `config.json` and optionally run `digitize_km.py` immediately

**Offer this wizard whenever a new KM plot is being set up.**

### Option B: Automated config creation (Claude runs this)

When the wizard is not available (no GUI/display), Claude constructs the config automatically:
1. Use the Read tool to view the PNG and extract all annotated survival values, curve names, axis ranges, and number-at-risk table
2. Run a Python/OpenCV scan to find exact axis pixel positions (left, top, right, bottom)
3. Write config.json — no user input required

Read the PNG file to visually identify:
- **Axis ranges**: X-axis (time) min/max and Y-axis (survival%) min/max
- **Plot region**: scan for the dark y-axis line (vertical) and x-axis line (horizontal) to get exact pixel coordinates. **Never visually estimate** — use the pixel scan approach to find the actual axis lines.
- **Calibration points**: use the Read tool to view the PNG, then transcribe **every survival percentage printed on the plot** for **BOTH curves** — collect all labeled timepoints visible (e.g., values at 12, 24, 36, 48, 60 months), not just the minimum 2. These numbers are usually printed directly beside the curves at vertical gridlines. More anchor points tighten the calibration optimizer's fit and are especially important for accuracy in the early overlap zone where both curves are still near 100%.
- **Curve names**: identify the treatment arms from the legend
- **Number at risk**: read the number-at-risk table below the plot (required for IPD reconstruction)

## Step 2: Config JSON reference (wizard users can skip — wizard writes this)

If using the wizard, config.json is written automatically. This section is for manual creation (Option B) or for editing a wizard-generated config.

```json
{
    "image_path": "reference/KMPlot/os_407.PNG",
    "plot_region": {"left": 220, "top": 98, "right": 1232, "bottom": 516},
    "x_range": [0, 72],
    "y_range": [0, 100],
    "x_label": "Time (months)",
    "y_label": "OS (%)",
    "calibration_points": [
        {"month": 12, "survival": 64.7, "curve": 0},
        {"month": 60, "survival": 18.4, "curve": 0},
        {"month": 12, "survival": 49.6, "curve": 1},
        {"month": 60, "survival": 9.7,  "curve": 1}
    ],
    "number_at_risk": {
        "times": [0, 12, 24, 36, 48, 60, 72],
        "counts": {
            "Pembrolizumab plus chemo": [278, 180, 100, 83, 60, 10, 0],
            "Placebo plus chemo": [281, 137, 84, 50, 33, 7, 0]
        }
    },
    "curve_names": ["Pembrolizumab plus chemo", "Placebo plus chemo"],
    "output_path": "output/kn407_os/km_digitized.json",
    "debug_image": "output/kn407_os/km_debug.png",
    "y_tolerance": 1.5
}
```

**Config fields:**

| Field | Required | Description |
|-------|----------|-------------|
| `image_path` | Yes | Path to the KM plot PNG |
| `plot_region` | Yes | Exact pixel coordinates of the data area: `left` = y-axis column, `right` = rightmost tick column, `top` = 100% survival row, `bottom` = x-axis row. Use the wizard or scan for dark axis lines — visual estimates cause systematic time errors. |
| `x_range` | Yes | Data-space X-axis limits, e.g., `[0, 72]` |
| `y_range` | Yes | Data-space Y-axis limits, e.g., `[0, 100]` |
| `calibration_points` | Recommended | Known (month, survival%) values. `curve`: 0=top, 1=bottom. **Collect ALL annotated timepoints from BOTH curves** — don't stop at 2. Using every labeled point (typically 5+ per curve) dramatically improves accuracy, especially for early time points in the overlap zone. |
| `number_at_risk` | For IPD | Number-at-risk table. `times`: timepoints, `counts`: dict mapping curve name -> array of counts. Required for `reconstruct_ipd.R`. |
| `curve_names` | Optional | Labels in survival-rank order (highest first). Must match `number_at_risk.counts` keys. |
| `output_path` | Yes | Where to save the digitized JSON |
| `debug_image` | Optional | Path for debug overlay image |
| `y_tolerance` | Optional | Min survival% change to register as a step (default: 1.0) |

## Step 3: Run the digitizer

```bash
python scripts/digitize_km.py config.json
```

Always generate a `debug_image` and visually inspect it. The overlay shows:
- Green rectangle: optimized plot region
- **Yellow dots**: tracked pixels for curve 0 (top/higher survival arm)
- **Magenta dots**: tracked pixels for curve 1 (bottom/lower survival arm)

If tracking looks wrong (dots missing, crossing to wrong curve, or gaps), adjust `plot_region` or add more calibration points.

## Step 4: Reconstruct IPD

```bash
Rscript scripts/reconstruct_ipd.R \
  output/<study>/km_digitized.json \
  output/<study>/
```

Reads the digitized JSON (requires `number_at_risk`), uses `IPDfromKM::getIPD()` to reconstruct individual patient time-to-event data. Outputs:
- `ipd_<arm_name>.csv` — per-arm IPD (columns: `time`, `event`, `arm`)
- `ipd_combined.csv` — all arms combined

## Step 4.5: Verify reconstruction quality (mandatory gate)

```bash
Rscript scripts/verify_reconstruction.R \
  output/<study>/km_digitized.json \
  output/<study>/ipd_combined.csv \
  output/<study>/
```

This compares the digitized curve coordinates against the reconstructed KM curves from the IPD. For each arm it reports:

| Metric | Pass threshold | Meaning |
|--------|---------------|---------|
| MAE (mean absolute error) | < 3 percentage points | Average gap across all digitized timepoints |
| MaxDev (maximum deviation) | < 5 percentage points | Worst-case single-point gap |

**If any arm FAILs, stop and diagnose before proceeding to the report.** Do not generate the Word report on a failed reconstruction — the statistics will be unreliable.

### Diagnosing a FAIL

Work through these in order until verification passes:

1. **Debug overlay** — open `km_debug.png`. Are the colored tracking dots following the correct curve? Crossover or missing dots in the early period indicate a `plot_region` or color-detection problem.
2. **Add calibration points** — re-read the PNG and transcribe more annotated survival values, especially in the early time period (first 12–24 months) where both curves are close together. Aim for 5+ per arm. Update `config.json` and re-run the digitizer.
3. **Correct plot_region** — if the debug dots appear shifted in time vs the original plot, the pixel-to-time mapping is off. Re-scan for the exact dark axis line positions and update `plot_region` in `config.json`.
4. **Check number_at_risk keys** — keys in `number_at_risk.counts` must match `curve_names` exactly (case-sensitive). Mismatches cause the IPD reconstruction to use the wrong N, which widens the gap.

After any config change, re-run Steps 3 → 4 → 4.5 and check verification again.

**Only proceed to Step 5 once verification outputs `Overall: PASS`.**

## Step 5: Generate report

```bash
python scripts/generate_report.py \
  output/<study>/km_digitized.json \
  output/<study>/ipd_combined.csv \
  output/<study>/
```

Generates `reconstruction_report.docx` containing:
1. **KM curve comparison** — side-by-side: digitized original vs reconstructed from IPD (via `survival::survfit()` + `survminer::ggsurvplot()`). Both panels share the same x-axis range and tick marks, which match the NaR timepoints from the source plot.
2. **Survival statistics table** — N (patients), Events n (%), median, and survival rates at number-at-risk timepoints per arm (via `survival::survfit()`)
3. **Hazard rate plot** — B-spline smoothed hazard over time (via `bshazard`), truncated where any arm drops below 20% at risk. X-axis ticks match NaR timepoints up to the cutoff.
4. **Appendix** — original KM plot image

## Built-in Safeguards

The digitizer automatically handles five common problem areas:

1. **Overlap zone at start** — Both curves start at 100% and overlap for the first few months. Color-specific tracking cannot start until the curves separate enough to be distinguishable by hue. Non-white pixels visible before that point (e.g., from horizontal curve segments at later survival levels crossing early columns) do not represent the curve at those early times and are intentionally ignored. The digitizer inserts a `(0, 100%)` anchor and lets `IPDfromKM` interpolate the early period using the number-at-risk table.

2. **Monotonicity enforcement** — Censoring tick marks and legend artifacts can cause the tracker to jump to the wrong curve at the tail, creating upward spikes. The digitizer enforces monotonic non-increasing survival: any point that jumps above the previous value is automatically discarded.

3. **Tail truncation** — Beyond the last number-at-risk timepoint with count > 0, pixel data is unreliable (dense censoring ticks, curve overlap). When `number_at_risk` is provided, the digitizer truncates each curve at the last timepoint with patients at risk (+ 1 month buffer).

4. **Flat tail extension** — After tail truncation, the tracker sometimes loses pixels in the dense censoring-tick region before reaching the plot's right edge. The digitizer automatically extends the last tracked survival value flat to `x_range[1]`, so the digitized JSON always spans the full plot width. No gap between the last tracked point and the x-axis maximum.

5. **Tail censoring redistribution** — `IPDfromKM::getIPD()` heaps all late-censored patients at the final event time when the survival curve is flat in the tail. `reconstruct_ipd.R` detects this and redistributes those patients across the remaining NaR intervals (e.g., [12, 15] and [15, 18] months) using the number-at-risk table, so the reconstructed KM curve extends to the correct follow-up horizon.

## Tips

- **Use the wizard for plot_region** — visual estimates of axis pixel positions cause systematic 7+ month time shifts. The wizard clicks directly on the axis lines; or scan the image programmatically for dark lines if doing it manually.
- **Calibration points from BOTH curves** are the key to accuracy (<1% MAE). Collect ALL annotated timepoints visible on the plot — don't stop at 2 per curve. For a plot labeled at 12, 24, 36, 48, 60 months, include all 10 points (5 per curve). This is especially critical for the early overlap zone.
- **number_at_risk keys must match curve_names** — the IPD script matches by name.
- **number_at_risk also controls tail quality** — provide it even if not running IPD reconstruction, as it drives tail truncation.
- **Curves must be distinct colors** — the tool cannot separate same-colored curves.

## Dependencies

**Python**: `opencv-python`, `numpy`, `python-docx`, `pandas`, `matplotlib` (for setup_wizard.py)

**R packages**: `IPDfromKM`, `jsonlite`, `survival`, `survminer`, `bshazard`, `ggplot2`, `gridExtra`, `scales`
