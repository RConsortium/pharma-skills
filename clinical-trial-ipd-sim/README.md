# clinical-trial-ipd-sim

Claude Code skill for generating individual-patient-data (IPD) CRFs for a
registered clinical trial using an R/pharmaverse g-formula causal-DAG
simulator. Given an NCT ID with posted protocol and results, the skill
produces synthetic source CRFs, SDTM-style domains, ADaM analysis datasets,
TLGs, and export files whose marginal statistics match the published trial
AND whose joint distribution follows an explicit, identifiable causal DAG.

## Why this exists

Trial-summary reconstruction methods (digitized KM curves, marginal AE
proportions) reproduce headline numbers but lose all within-patient
structure. Most "synthetic IPD" generators draw outcomes from
independent parametric distributions conditional on arm — the resulting
data cannot support causal-inference methodology because:

- AE types are conditionally independent given arm (no shared frailty)
- Labs and AEs are not mechanistically linked
- Endpoints (PFS, OS) are sampled directly rather than derived from
  the longitudinal trajectory

This skill produces simulators where every node has explicit causal
parents, latent patient frailties induce realistic within-patient
correlation across the trajectory, and endpoints are deterministic
functionals of the simulated state.

## When the skill fires

Use this skill when the user provides, or asks you to identify, an NCT ID
and wants synthetic IPD, source CRFs, a digital-twin cohort, or a simulated
trial reconstruction. The skill assumes the trial has posted results and an
available protocol document, either on ClinicalTrials.gov, in a journal
supplement, or supplied by the user.

## Files in this skill

| File | Purpose |
|---|---|
| [`SKILL.md`](SKILL.md) | Main workflow — the six-step pipeline (intake -> CRF derivation -> SCM construction -> parameterization -> forward sim -> calibration). Includes causality invariants. |
| [`r_implementation.md`](r_implementation.md) | R implementation guide — package layout, pharmaverse package roles, SDTM/ADaM/TLG/export flow, and R validation rules. |
| [`calibration.md`](calibration.md) | Sub-skill for the iterative calibration loop. Tables of allowed vs. forbidden parameter knobs; gate-based fail-closed algorithm. |
| [`templates/scm_spec_template.md`](templates/scm_spec_template.md) | Rigorous SCM specification template. Forces per-variable dossiers covering DAG parents, mechanism, functional form, parameter priors with citations, identifiability checks, d-separation implications, and validation gates. |
| [`templates/crf_schema_template.md`](templates/crf_schema_template.md) | CDISC-aligned CRF schema template — visit grid, per-form dossier, variable list, SoA crosswalk. |

## Pipeline at a glance

```
NCT ID
  │
  ▼
Step 1 · Intake from ClinicalTrials.gov
  → trial design, eligibility, endpoints, AE table, protocol PDF
  ▼
Step 2 · Parse SoA → CRF schema
  → form × visit × variable matrix
  ▼
Step 3 · Build SCMs from literature + protocol
  → dag_spec.md per template
  ▼
Step 4 · Parameterize from CTGov results + literature
  → parameter table with citations
  ▼
Step 5 · g-formula forward simulation
  → per-patient: L₀ → A → L₁ → … → Lₜ → Yₜ
  → emit source CRFs, then SDTM/ADaM via pharmaverse packages
  ▼
Step 6 · Calibration loop (causality-preserving)
  → DAG gates pass before any param update is accepted
  → adjust scale/intercept/hazard/variance only
  → halt when marginals within tolerance OR causality regression detected
  ▼
Final CRFs + SDTM/ADaM + TLGs + exports + analysis report
```

## Causality invariants

The skill enforces these constraints throughout, especially during
calibration. They distinguish a true SCM-based simulator from a
marginal-effect simulator dressed up with extra forms:

1. **Endpoints are functionals of the trajectory**, never independent
   draws. `PFS_DAY = min(progression_day, death_day, ADMIN_CENSOR)` where
   `progression_day` comes from the simulated SLD trajectory hitting
   RECIST PD criteria.
2. **AEs derive from their causal parents**: heme AEs are CTCAE grades
   of simulated lab values; non-lab AEs are sampled from per-visit
   hazards depending on arm and shared latent frailties.
3. **Latent frailties are mandatory** for any cluster of correlated AE
   preferred terms or lab values. Their variances are tunable but
   cannot be set to zero (that would be a structural change, not
   calibration).
4. **No direct A → Y edges** that bypass the modeled mediators. All
   treatment-effect pathways flow through SLD trajectory, AEs, dose
   modifications, ECOG, and discontinuation.
5. **Deterministic CTCAE / RECIST rules are fixed**. Calibration tunes
   the *inputs* to those rules (lab dynamics, SLD trajectory), never
   the rules themselves.

The full list with worked counter-examples is in [`SKILL.md`](SKILL.md)
and [`calibration.md`](calibration.md).

## Suggested smoke test — FLAURA2 (NCT04035486)

FLAURA2 is a useful public smoke-test scenario because it has posted
ClinicalTrials.gov results, a published primary analysis, two treatment arms,
PFS, response endpoints, chemotherapy-associated lab toxicity, and a rich AE
profile. Use it to exercise the workflow end to end:

1. Fetch and persist the ClinicalTrials.gov v2 record.
2. Locate the protocol and schedule of activities.
3. Build the CRF schema and `dag_spec.md`.
4. Parameterize the SCM from CTGov results and cited literature.
5. Implement the simulator in R, following [`r_implementation.md`](r_implementation.md).
6. Calibrate to published PFS and AE targets while keeping all DAG gates
   passing.

The implementation should use pharmaverse packages for standards and outputs:

- `sdtm.oak` for SDTM-oriented domain construction.
- `admiral` for ADaM derivations.
- `haven` for SAS data interoperability where needed.
- `tidytlg` for TLGs.
- `xportr` for XPT metadata/export.
- `datasetjson` for Dataset-JSON export.

## Required tools

- R 4.3+ with `renv`
- R packages: `dplyr`, `tidyr`, `purrr`, `readr`, `tibble`, `lubridate`,
  `stringr`, `survival`, `flexsurv`, `broom`, `jsonlite`, `testthat`
- Pharmaverse/CDISC packages: `sdtm.oak`, `admiral`, `haven`, `tidytlg`,
  `xportr`, `datasetjson`
- `WebFetch` / `WebSearch` for ClinicalTrials.gov API and literature
- File-system access for CSV, XPT, Dataset-JSON, and TLG emission

## Limitations

- The skill does not address summary-level reconstruction (KM digitization,
  pure marginal sampling) — for those use cases, simpler IPD-from-summary
  methods are appropriate.
- ClinicalTrials.gov coverage is uneven; trials without posted protocols
  or with sparse AE tables will require user-supplied supplementary data.
- The calibration loop is a local search over parameter values; if the
  published marginals are inconsistent with the SCM structure (e.g.,
  effect sizes that imply unmodeled mediators), the loop will plateau
  and report a structural review recommendation rather than continue
  fitting.

## Extending

To adapt to a new disease area:

1. Replace the FLAURA2 AE catalog and frailty cluster definitions
   in `R/longitudinal.R` with the new disease's typical AE
   profile.
2. Replace the SLD-based RECIST tumor model with the disease's
   appropriate response criteria (e.g., IMWG for myeloma, Cheson for
   lymphoma).
3. Update `dag_spec.md` to reflect biomarker stratifiers relevant to
   the new indication.
4. Re-elicit parameter priors from the new indication's literature.

The g-formula structural skeleton (`baseline → arm → longitudinal →
endpoints` with latent frailties shared across the trajectory) is
disease-agnostic and should be preserved.

## In progress
1. ODM integration for structured CRF output
2. Paperclip search integration for literature-based evidence
