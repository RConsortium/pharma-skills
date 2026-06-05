# R Implementation Guide

Use this guide whenever the IPD simulator is implemented or ported in R.
The causal engine remains a g-formula SCM; the pharmaverse stack is used
to standardize, derive, report, and export the simulated records.

## Package Roles

| Package | Use in this skill | Do not use for |
|---|---|---|
| `sdtm.oak` | Build SDTM-oriented domains from generated source records and metadata-driven mappings. | Causal simulation logic. |
| `admiral` | Derive ADaM datasets such as ADSL, ADAE, ADLB, ADTTE from SDTM/source domains. | Raw longitudinal state generation. |
| `haven` | Read user-supplied SAS datasets or write SAS-compatible intermediate files when needed. | Primary XPT regulatory export when `xportr` is available. |
| `tidytlg` | Generate tables, listings, and graphs from ADaM outputs. | Data derivation or causal calibration. |
| `xportr` | Apply metadata and write XPT transport files for SDTM/ADaM deliverables. | Simulation or analysis modeling. |
| `datasetjson` | Emit Dataset-JSON deliverables from SDTM/ADaM datasets when requested. | CSV-only exploratory output. |

Official references:

- `sdtm.oak`: https://pharmaverse.github.io/sdtm.oak/
- `admiral`: https://pharmaverse.github.io/admiral/
- `haven`: https://haven.tidyverse.org/
- `tidytlg`: https://pharmaverse.github.io/tidytlg/
- `xportr`: https://pharmaverse.github.io/xportr/
- `datasetjson`: https://cran.r-universe.dev/datasetjson/doc/datasetjson.html

Core non-pharmaverse packages:

- `dplyr`, `tidyr`, `purrr`, `tibble`, `readr`, `stringr`, `lubridate`,
  `rlang` for data manipulation and orchestration.
- `survival`, `flexsurv`, `broom` for KM, Cox, and parametric survival
  calibration summaries.
- `jsonlite` for ClinicalTrials.gov intake and parameter snapshots.
- `testthat` for DAG gates and regression tests.

## Project Layout

Create an R package-style repository unless the user provides a different
structure.

```text
.
├── DESCRIPTION
├── renv.lock
├── R/
│   ├── dag_state.R
│   ├── baseline.R
│   ├── longitudinal.R
│   ├── outcomes.R
│   ├── emit_source.R
│   ├── sdtm.R
│   ├── adam.R
│   ├── tlg.R
│   ├── export.R
│   ├── calibrate.R
│   └── run.R
├── data-raw/
│   └── intake/
├── metadata/
│   ├── crf_schema.csv
│   ├── sdtm_spec.csv
│   ├── adam_spec.csv
│   ├── define_spec.csv
│   └── export_spec.csv
├── tests/testthat/
│   ├── test-dag-gates.R
│   ├── test-endpoints.R
│   ├── test-sdtm.R
│   └── test-adam.R
└── output/
    ├── source/
    ├── sdtm/
    ├── adam/
    ├── tlg/
    └── analysis/
```

## Data Flow

Keep the causal simulator separate from standards derivation:

```text
ClinicalTrials.gov + protocol + literature
  -> intake JSON and parameter tables
  -> source simulation tibbles
  -> SDTM domains with sdtm.oak-style metadata mappings
  -> ADaM datasets with admiral
  -> TLGs with tidytlg
  -> CSV/XPT/Dataset-JSON exports with readr/xportr/datasetjson
```

The source simulator owns all randomness. SDTM, ADaM, TLG, and export
steps are deterministic projections or derivations from simulated source
records.

## R Module Contract

`R/dag_state.R`

- Define visit grid, administrative censor day, CTCAE/RECIST constants,
  and helper constructors.
- Return tibbles or named lists with stable columns. Avoid S4/R6 unless
  there is a clear package reason.
- Store frailties once per subject and pass them through longitudinal
  generation.

`R/baseline.R`

- `make_baseline(subject_id, params, rng_stream)` samples L0 and treatment.
- Sample baseline variables in topological order.
- Treatment is randomized according to protocol ratio and stratification.

`R/longitudinal.R`

- `simulate_trajectory(patient, params, visit_grid)` returns one row per
  subject-visit with latent and observed state.
- Update in this order: exposure, labs, tumor/RECIST, AEs, dose actions,
  ECOG, discontinuation.
- Lab AEs must derive from lab values through fixed CTCAE rules plus a
  reporting model.
- Non-lab AEs use per-visit hazards with arm, exposure, recurrence, and
  frailty parents.

`R/outcomes.R`

- `derive_endpoints(patient, trajectory, params)` derives PFS/OS from
  trajectory. Never draw PFS directly from arm.
- PFS is `min(progression_day, death_day, admin_censor_day)`.

`R/emit_source.R`

- Convert simulated patient and trajectory objects into source CRF-style
  tibbles.
- No fresh random draws in this layer. If a field needs stochastic
  variation, generate it upstream in `baseline.R` or `longitudinal.R`.

`R/sdtm.R`

- Build SDTM-style domains from source records and `metadata/sdtm_spec.csv`.
- Prefer `sdtm.oak` patterns for metadata-driven mappings where they fit.
- Preserve traceability columns back to source rows where practical.

`R/adam.R`

- Use `admiral` derivation functions where practical.
- At minimum, derive:
  - `ADSL`: subject-level demographics, arm, stratifiers, baseline status.
  - `ADAE`: AE analysis records, severity flags, treatment-emergent flags.
  - `ADLB`: lab analysis values, baseline/change, toxicity grades.
  - `ADTTE`: PFS/OS time-to-event parameters.

`R/tlg.R`

- Use `tidytlg` for AE summaries, PFS/KM tables, disposition summaries,
  and calibration comparison tables.

`R/export.R`

- Write CSV with `readr`.
- Use `xportr` for XPT outputs using `metadata/export_spec.csv`.
- Use `datasetjson` for Dataset-JSON outputs when requested.

`R/calibrate.R`

- Implement the causality-preserving loop from `calibration.md`.
- Each accepted parameter update must pass DAG gates.

## Metadata Stubs

Create these files early, even if incomplete:

- `metadata/crf_schema.csv`: form, visit, variable, type, required,
  source, SCM node.
- `metadata/sdtm_spec.csv`: domain, source dataset, source variable,
  target variable, derivation, codelist, role.
- `metadata/adam_spec.csv`: dataset, parameter, source domain, derivation,
  analysis flag, population flag.
- `metadata/export_spec.csv`: dataset, variable, label, type, length,
  controlled terminology, origin.

Keep metadata human-readable and version-controlled. Do not bury
standards mappings inside procedural R code.

## Validation

Implement `tests/testthat/test-dag-gates.R` with gates equivalent to the
calibration spec:

- Lab AE linkage: neutropenia records occur when ANC is low; anemia records
  occur when HGB is low.
- AE cluster correlation: shared frailties induce positive within-patient
  correlation for relevant AE clusters.
- Endpoint linkage: PFS event days match progression/death trajectory
  records.
- Stratifier direction: biomarker prognostic effects move endpoints in the
  expected direction.
- Standards checks: SDTM/ADaM required variables are present; XPT/Dataset-
  JSON exports are deterministic from final datasets.

Do not accept a marginal calibration improvement if any DAG gate regresses.

## R Coding Rules

- Use explicit parameters objects (`params` lists/tibbles) instead of
  hard-coded constants scattered through functions.
- Keep random number generation in `baseline.R` and `longitudinal.R`.
- Return tibbles with stable column names; avoid implicit row ordering as
  a contract.
- Prefer vectorized tidyverse code for domain derivations, but use clear
  per-patient loops for longitudinal state propagation when causal order is
  easier to audit.
- Every non-trivial causal edge and parameter prior needs a source in
  `dag_spec.md` or the parameter table.
