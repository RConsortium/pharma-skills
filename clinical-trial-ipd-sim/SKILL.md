---
name: clinical-trial-ipd-sim
description: End-to-end R/pharmaverse workflow to simulate individual patient data (IPD) for a registered clinical trial using a g-formula causal-DAG simulator. Given an NCT ID with posted protocol + results, derives SDTM-style CRFs, builds evidence-based structural causal models, parameterizes them from ClinicalTrials.gov / literature priors, runs forward simulation in R, creates SDTM/ADaM outputs with pharmaverse packages, and iteratively calibrates marginal statistics to the published results without breaking causal identifiability.
metadata:
  when-to-use: User provides an NCT ID and asks for synthetic IPD / CRF simulation, trial reconstruction, or any phrase like "simulate trial X", "create CRFs for NCT…", "generate digital-twin patients for…".
---

# Clinical Trial IPD Causal-DAG Simulator

End-to-end R workflow for generating individual-patient-level CRF data for a
registered clinical trial. The output is a set of CSV CRFs whose marginal
statistics match the published trial results AND whose joint distribution
follows an explicit causal DAG, so the data are usable for downstream
causal-inference methodology.

The implementation target is R-first and pharmaverse-compatible. The Python
FLAURA2 build used during development remains a worked example of the causal
logic, but new work should create an R package-style project unless the user
explicitly asks for Python. See [r_implementation.md](r_implementation.md)
for the R module layout and package roles.

This skill generalizes the FLAURA2 causal-DAG workflow into an
R/pharmaverse implementation target.

## When to use

The user provides an NCT ID **and** the trial has both a posted protocol and
posted results. Examples:

- "Simulate IPD for NCT04035486" → use this skill
- "Generate CRFs for the AEGEAN trial" → look up NCT, then use this skill
- "Create a digital-twin cohort for trial X" → use this skill
- "I need synthetic patients matching the published KM curves of …" → use this skill

Do **not** use when the user only wants summary-level reconstruction (Cox HR,
KM medians, AE proportions). For that, reach for tabular reconstruction
methods (e.g., reconstructed IPD from KM digitization).

## Required environment

- R 4.3+ with `renv` for dependency locking.
- Core simulation/analysis: `dplyr`, `tidyr`, `purrr`, `readr`, `tibble`,
  `lubridate`, `stringr`, `rlang`, `survival`, `flexsurv`, `broom`, `jsonlite`.
- Pharmaverse/CDISC stack:
  - `sdtm.oak` for SDTM-oriented CRF/domain construction from generated source records.
  - `admiral` for ADaM derivations such as ADSL, ADAE, ADLB, ADTTE.
  - `haven` for reading/writing SAS transport-adjacent inputs and SAS datasets when needed.
  - `tidytlg` for TLG generation from ADaM outputs.
  - `xportr` for XPT metadata handling and transport export.
  - `datasetjson` for Dataset-JSON export when requested.
- Network access for the ClinicalTrials.gov API (`https://clinicaltrials.gov/api/v2/studies/{nct}`)
- Citation-capable literature and standards lookup for causal-parent
  evidence, natural-history rates, priors, CTCAE, and RECIST references.
  Record stable source identifiers for all non-CTGov evidence; do not rely
  on model memory for cited claims.
- `WebFetch` or equivalent only for fetching specific known URLs
  (the ClinicalTrials.gov API, a protocol PDF, a publication supplement)

## Workflow — six steps

### Step 1 · Intake from ClinicalTrials.gov

1. Fetch the trial JSON record:
   `https://clinicaltrials.gov/api/v2/studies/{NCT_ID}?format=json`
2. Extract:
   - **Design**: arms, randomization ratio, stratification factors, primary/secondary endpoints
   - **Eligibility**: inclusion/exclusion criteria → baseline population priors
   - **Outcomes table**: per-arm event counts, medians, hazard ratios with 95% CIs
   - **Adverse events table**: per-arm SOC/PT counts at any-grade, Gr ≥3, SAE
   - **Protocol document URL** (under `ProtocolSection.IPDSharingStatementModule` or `LargeDocumentsModule`)
3. Locate the **schedule of activities (SoA)** in the protocol PDF/HTML.
   If the SoA cannot be parsed automatically, ask the user to point at the
   relevant pages, or scaffold a default visit grid based on the dosing schedule.
   If ClinicalTrials.gov does not provide a protocol, search for the protocol
   or supplementary appendix in the New England Journal of Medicine (NEJM).
   If neither source has a protocol, ask the user to provide one and do not
   proceed until it is available.
4. Persist the intake to `intake/{NCT_ID}.json` so later steps don't re-fetch.

**Output of step 1**: structured trial summary with design, endpoint targets,
AE targets, and SoA visit grid.

### Step 2 · CRF derivation from the protocol

Read the protocol's SoA and generate a CDISC-style CRF schema:

| Form | Visits collected | Variables | Source |
|---|---|---|---|
| Demographics | Screening | AGE, SEX, RACE, COUNTRY, ARM | Protocol §X |
| Cancer/Disease History | Screening | Diagnosis, stage, biomarker stratifiers | Protocol §X |
| Lab Hematology | Cycle days, maintenance | WBC, ANC, HGB, PLT, LYMPH | SoA |
| Tumor Assessment | q6w (or per protocol) | SLD, response, new lesions | RECIST 1.1 |
| Adverse Events | Each visit | AE term, grade, severity, action, relatedness | CTCAE |
| Disposition | EOT | Reason for discontinuation | SoA |
| Survival Follow-Up | Survival period | PFS time/event, OS time/event | Endpoint definitions |
| … | … | … | … |

Use [templates/crf_schema_template.md](templates/crf_schema_template.md) as
the starting structure. Defer to the protocol's SoA when present; fall back
to FLAURA2-style defaults when the user accepts.

**Output of step 2**: a `crf_schema.md` listing each form, its column set,
and the visit grid at which each form is collected. For R builds, also
create `metadata/sdtm_spec.csv` and `metadata/adam_spec.csv` stubs that can
drive `sdtm.oak`, `admiral`, `xportr`, and `datasetjson`.

### Step 3 · Build evidence-based structural causal models

For every variable in the CRF schema, specify its DAG parents and the
functional form of its structural equation.

**Process:**
1. Categorize variables into the four DAG layers:
   - **L₀ — Baseline** (eligibility-shaped covariates and patient frailties)
   - **A — Treatment** (arm assignment, randomization)
   - **Lₜ — Time-varying state** (labs, tumor, AEs, dose modifications, ECOG)
   - **Yₜ — Endpoints** (PFS, OS, response — derived from trajectory)
2. For each variable, gather cited evidence on its causal parents. Never
   assert a causal edge from memory. Look for:
   - Trial protocol (stratification factors → baseline parent edges)
   - Disease-area review papers (e.g., for NSCLC: TP53 → response, EGFR-type → PFS)
   - Drug mechanism papers (e.g., chemo → myelosuppression timing/depth)
   - CTCAE / RECIST documents (deterministic rules from labs/SLD → AE/response)
   - Prior published simulators or natural-history models
3. Document the DAG using [templates/scm_spec_template.md](templates/scm_spec_template.md).
   Each row: `variable | parents | functional form | evidence source`.
4. Introduce **latent frailty random effects** for any cluster of related
   AE preferred terms or correlated lab values that share a biological
   pathway. Examples:
   - `f_heme` shared by ANC/HGB/PLT (myelosuppression susceptibility)
   - `f_GI` shared by nausea/vomiting/diarrhea/stomatitis (chemo emesis)
   - `f_ILD` for the rare-but-irreversible class effect of EGFR-TKIs
   - `f_dropout` for unobserved patient-level dropout propensity
   These frailties are the mechanism that makes the simulated AEs
   correlated within patient — without them, AE types are independent
   draws conditional on arm, which is the bug we fixed in the FLAURA2
   v6 simulator.

**Output of step 3**: `dag_spec.md` with one row per variable, parents,
structural equation, and source.

### Step 4 · Parameterize the SCMs

For each structural equation, set its parameters from a hierarchy of priors:

1. **ClinicalTrials.gov results JSON** (highest priority; closest to ground truth)
   - Per-arm AE preferred-term counts → mono and combo per-visit hazards
   - Per-arm SAE rates → severity multipliers
   - Per-arm KM medians, HR with 95% CI → time-to-resistance scale + treatment effect
   - Discontinuation rates by reason → discontinuation-hazard intercepts
2. **Foundation-model knowledge** (sanity-check defaults)
   - CTCAE thresholds for lab grading (deterministic, never tuned)
   - RECIST 1.1 rules for response classification (deterministic)
   - Standard drug mechanism timing (e.g., pemetrexed nadir at day 8–10)
3. **Literature priors** (filling gaps) — gather these from cited
   publications, protocol supplements, or standards documents; never from
   uncited memory:
   - natural-history rates, incidence baselines
   - disease-area review articles
   - keep each record's `source_id` alongside the parameter value

**Implementation pattern (R version)**:

```r
# log-scale parameterization makes treatment effects multiplicative
log_scale <- log(BASE_DAYS_TO_EVENT) +
  LOG_HR_FROM_CTGOV * as.numeric(arm == "combo") +
  STRATIFIER_LOG_EFFECT * stratifier +
  FRAILTY_LOADING * latent_frailty
```

**Output of step 4**: a parameter table where each row maps parameter name
→ value → derivation source (CTGov field path, or PMID, or sanity default).

### Step 5 · G-formula forward simulation

Implement the simulator in R with strict topological propagation:

```r
For each patient:
    1. Sample L₀ (baseline + latent frailties) from priors
    2. Sample A (treatment arm) from randomization
    3. For each visit t in chronological order:
        a. Update drug-exposure indicators from prior dose state
        b. Sample Lₜ from f(Lₜ₋₁, A, drug_exposure, frailties)   # labs, SLD
        c. Derive AEs from Lₜ where deterministic (CTCAE on labs);
           sample non-deterministic AEs from frailty + arm hazard
        d. Apply dose-modification rules from AE thresholds
        e. Update ECOG and discontinuation hazards
    4. Derive Yₜ = endpoints from trajectory
        - PFS_DAY = first(progression_day, death_day, admin_censor)
        - PFS_EVENT = 1 iff event observed before censor
    5. Project trajectory → CRF rows (pure projection, no fresh sampling)
```

R module layout:
- `R/dag_state.R` — patient state as tibbles/lists, frailty draws, visit grid.
- `R/baseline.R` — L₀ generation.
- `R/longitudinal.R` — Lₜ propagation.
- `R/outcomes.R` — Yₜ derivation from trajectory.
- `R/emit_source.R` — pure trajectory projection to source-style CRF records.
- `R/sdtm.R` — SDTM domain construction, using `sdtm.oak` patterns where possible.
- `R/adam.R` — ADaM derivations with `admiral`.
- `R/tlg.R` — analysis tables/listings/graphs with `tidytlg`.
- `R/export.R` — CSV, XPT via `xportr`, Dataset-JSON via `datasetjson`.
- `R/run.R` — orchestrator.

Read [r_implementation.md](r_implementation.md) before writing or editing
the R implementation.

**Output of step 5**: populated source CRFs, SDTM-style domains, ADaM
datasets, and requested export formats for the requested N.

### Step 6 · Calibration loop (with causality preservation)

This is the most subtle step. The naïve approach — "the AE rate is too low,
add a bigger constant to the AE probability" — works to fix marginals but
**often violates causality** if it bypasses the parent variables. The
calibration loop must change parameters of structural equations, never
their structure.

#### Calibration invariants — **DO NOT VIOLATE**

The following are forbidden during calibration regardless of how much
discrepancy the marginal stats show:

1. ❌ **Do not draw an endpoint independently of its trajectory parents.**
   Example violation: drawing PFS_TIME from a Weibull conditioned only on
   arm to "fix" the median PFS. Correct: tighten `time_to_resistance`
   scale/shape so the SLD trajectory hits PD criteria at the right time.
2. ❌ **Do not add new direct edges from arm to outcomes** that bypass the
   intermediate variables (labs, AEs, dose, response). All treatment-effect
   pathways must flow through the modeled mediators.
3. ❌ **Do not derive a child node's value from its own descendants**
   (cycles in the DAG).
4. ❌ **Do not collapse independence across patient-shared frailties** —
   e.g., do not set `f_heme = 0` for all patients to "remove" a correlation;
   instead change the variance of `f_heme` if its effect is too strong.
5. ❌ **Do not turn a deterministic CTCAE/RECIST rule into a random draw**
   to inflate AE rates. The grading function is fixed; the lab value
   distribution is what's tunable.

#### Calibration loop — allowed knobs

For each marginal mismatch, the loop adjusts only structural-equation
*parameters*, never the *structure*. Allowed adjustments:

| Mismatch direction | Allowed knob |
|---|---|
| Median PFS too short / long | Scale and shape of `time_to_resistance` Weibull, post-resistance growth rate `g`, RECIST nadir-detection lag |
| HR too weak / strong | Treatment-arm coefficient on `time_to_resistance` (the only direct A-edge) |
| AE rate too high / low | Per-visit hazard `base_haz`, frailty variance, reporting probability `p_report` |
| Severe-AE share too high / low | `p_severe` parameter of non-lab AE generator; CTCAE thresholds untouched |
| Lab toxicity too deep / shallow | Drug-induced drag in lab AR(1) equations; AR coefficients α to control cascading |
| Discontinuation rate too high / low | Intercept and AE-burden coefficient in discontinuation hazard |
| AE-AE correlation too low | Increase frailty variance for the relevant cluster (e.g., `f_GI`) |
| Within-patient lab autocorrelation | AR(1) coefficient α (closer to 1 → more cascade) |

#### Loop algorithm

```
LOAD targets = ctgov_results(NCT)
LOAD invariants = ["all DAG edges in dag_spec.md"]

REPEAT up to N_iter (default 8):
    SIMULATE current_params → CSVs
    METRICS = compute_marginals(CSVs)
        - per-arm median PFS + 95% CI
        - HR (Cox) with 95% CI
        - Any AE / Gr ≥3 AE / SAE / discontinuation rates per arm
        - Top 10 PT-level AE rates per arm
    GATES = run_dag_gates(CSVs)
        - AE↔lab linkage (deterministic AEs)
        - Within-patient AE-AE correlation (frailty cluster)
        - PFS_DAY = trajectory progression (correlation = 1.0)
        - Stratifier → endpoint effects in expected direction

    ASSERT GATES all pass            # NEVER break causality
    IF MAX_DISCREPANCY(METRICS, targets) < TOL: BREAK

    PROPOSE param updates that move METRICS toward targets, restricted
    to the "allowed knobs" table. Prefer single-parameter changes with
    clear marginal effect; avoid coupled changes that could mask DAG bugs.

    APPLY updates → params_next
    LOG params_next, METRICS, gate results
```

The loop **fails closed** — if any DAG gate fails after a parameter update,
the update is reverted and the loop reports a structural problem rather
than continuing to chase marginals. Causal identification is paramount.

**Output of step 6**: final calibrated CSVs, parameter audit trail, gate
results, and a side-by-side table comparing simulated vs. published
metrics.

## Concrete deliverables

When this skill completes, the working directory contains:

- `intake/{NCT}.json` — raw and parsed CTGov record
- `crf_schema.md` — list of forms × visits × variables
- `dag_spec.md` — variable / parents / structural equation / evidence
- `params/` — per-iteration parameter snapshots (audit trail)
- `R/` — R modules implementing the simulator and SDTM/ADaM/export pipeline
- `metadata/` — SDTM/ADaM/export metadata specs for `sdtm.oak`, `admiral`,
  `xportr`, and `datasetjson`
- `renv.lock` — reproducible R dependency lockfile
- `<output>/source/*.csv` — source-style generated CRFs
- `<output>/sdtm/*.csv` and, when requested, `.xpt` / Dataset-JSON exports
- `<output>/adam/*.csv` and, when requested, `.xpt` / Dataset-JSON exports
- `<output>/analysis/` — KM curves, primary endpoint analysis, AE tables, calibration report

## Worked example

The FLAURA2 build (NCT04035486) used during development demonstrates the
causal model and calibration targets. Treat it as a reference to port into R:

- Intake JSON fields used: `Outcomes`, `AdverseEvents`, `EligibilityCriteria`, `ArmsInterventions`
- CRF schema: 26 forms across screening / treatment / follow-up
- DAG: represented in the generated `dag_spec.md` format, with one row per
  node documenting parents, structural equation, and evidence source
- Parameters: calibrated to median PFS combo 23.5 mo (pub 25.5), mono 19.3 mo (pub 16.7), HR 0.64 (pub 0.62)
- Gates passed: AE↔lab linkage (mean ANC at Neutropenia AE = 0.52 vs 4.29 without), GI AE within-patient r ≈ 0.28, PFS↔trajectory r = 1.000

Refer to it as a causal template; do not copy code blindly. New
implementation work should port the same structure into `R/` and should use
pharmaverse packages for standards, ADaM derivations, TLGs, and exports.
Every trial has its own SoA, biomarker stratifiers, and AE profile.

## Common pitfalls

1. **Treating the calibration loop as parameter optimization without DAG
   constraints.** It must be optimization *subject to* the DAG gates.
2. **Letting the visit grid extend past the data cutoff.** Set
   `ADMIN_CENSOR_DAY` from CTGov's data-cutoff date so PFS censoring
   matches the published analysis.
3. **Using global RNG state in ad hoc R code and expecting reproducibility
   across calibration iterations.** Use one controlled seed and consume RNG
   in a fixed order; otherwise minor parameter changes will appear to cause
   large output changes simply from RNG-state shifts.
4. **Independent-draw shortcut for non-lab AEs.** Without a shared
   frailty, every AE type is conditionally independent given arm — the
   bug fixed in v6. Always introduce a frailty per AE cluster.
5. **Drawing endpoints directly.** PFS_TIME must be derived from the
   trajectory, not sampled from a parametric distribution conditioned
   on arm. The original FLAURA2 v6 sim violated this; the current
   causal reference build does not.

## Companion skills / hooks

- `crf-calibration-loop` (sub-skill at [calibration.md](calibration.md)) —
  the iterative loop with causality-preserving parameter updates,
  invocable independently when the user wants to tune an existing run.
- Verification gate functions live alongside the simulator code as
  `verify_dag_*.R`; they should be runnable as a pre-commit-style hook
  before any CSVs are released.
