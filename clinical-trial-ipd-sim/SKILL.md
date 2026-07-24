---
name: clinical-trial-ipd-sim
description: End-to-end R workflow to simulate individual patient data (IPD) for a registered clinical trial using a g-formula causal-DAG simulator. Given an NCT ID with posted results and a protocol PDF, derives CRFs, builds an evidence-based causal DAG, parameterizes structural equations from ClinicalTrials.gov / literature priors, runs an R6 forward simulator, and calibrates marginal statistics to the published results without breaking causal identifiability. Emits CSV CRFs, a validated CDISC ODM v2.0 export, and an interactive DAG page.
metadata:
  when-to-use: User provides an NCT ID and asks for synthetic IPD / CRF simulation, trial reconstruction, or any phrase like "simulate trial X", "create CRFs for NCT…", "generate digital-twin patients for…".
---

# Clinical Trial IPD Causal-DAG Simulator (R)

End-to-end R workflow for generating individual-patient-level CRF data for a registered clinical
trial. The output is a set of CSV CRFs whose marginal statistics match the published trial AND whose
joint distribution follows an explicit causal DAG, plus a validated CDISC ODM v2.0 form + patients
and an interactive DAG page.

The engine is an R6 class `TrialSim` (`R/trial_sim.R`) that every trial subclasses. The **canonical
reference build — mirror it — is RAVE** (`examples/autoimmune/rave/`, binary endpoint); the
**continuous-change + ODM exemplar is CATH** (`examples/allergy/cath/`, NCT00789880). Consult the
closest-archetype example when building a new trial. See [r_implementation.md](r_implementation.md)
for the R module layout.

**Reproducible, not byte-identical to any Python build.** R's base RNG cannot reproduce NumPy's
bitstream, so this port re-implements the structure/logic/gates with its own reproducible draws
(fixed seed → identical output) and is **re-calibrated in R** to the same published targets. The bar
is: DAG gates all_pass (fail-closed) + marginals within tolerance — never a byte match.

## When to use

The user provides an NCT ID **and** the trial has both a protocol (user PDF or via find-protocol) and
posted results. Do **not** use for summary-level reconstruction (Cox HR / KM medians only) — use
tabular IPD reconstruction for that.

## Required environment

- **R 4.3+** with `R6`, `dplyr`, `readr`, `tibble`, `jsonlite` (base R otherwise).
- **A `python3`** with `vendor/python/requirements.txt` installed (`lxml`, `duckdb`, `pandas`,
  `pypdf`, `requests`) — used for the ODM steps, the DAG render, and find-protocol, all shelled out
  from R. Point the skill at it with `options(ctids.python="…")` or the `CTIDS_PYTHON` env var, else
  `python3` on PATH is used. **Never hardcode a personal interpreter path.**
- Network access for the ClinicalTrials.gov API (design + posted results only — never the protocol).
- **find-protocol** — vendored at `vendor/python/find_protocol/find_protocol.py`; see
  [find_protocol.md](find_protocol.md). **Paperclip** — the recommended evidence channel; see
  [paperclip.md](paperclip.md). Every cited claim carries a Source origin tag + verbatim quote.

## Citation format

Every evidence-backed row in `DAG.md`, the parameter table, and the SCM dossier carries its evidence
**inline, in two columns**:
- **Source** = an origin tag, exactly one of `ctgov: <field path>` / `paperclip: <id> <url>` /
  `model: <default>` (`model` is **flagged** — a foundation-model default with no external source).
- **Evidence** = the **verbatim** quote / exact field text the row rests on — **required on every row**.

## Workflow — eight steps

### Step 1 · Intake from ClinicalTrials.gov + protocol acquisition
1. Fetch `https://clinicaltrials.gov/api/v2/studies/{NCT}?format=json`; extract design (arms,
   allocation, stratifiers, endpoints), eligibility → baseline priors, the outcomes table, and the AE table.
2. **Results gate** — if `hasResults` is false / `resultsSection` is empty, **STOP and ask**; continue
   only with the user's explicit approval of an alternative calibration source (protocol design-stage
   assumptions and/or a publication), tagged as an assumption, not a result.
3. **Protocol** — use the user's PDF; else run find-protocol (HuggingFace `trialdesignbench/source`);
   else **STOP and ask — never scrape the web**. Read the Schedule of Activities (SoA) from it.
4. Persist intake to `{trial}_output/intake/{NCT}.json`.

### Step 2 · CRF derivation + blank ODM form
Define the CRF **once**, from the SoA: forms × visits × variables. Write the human view
`{trial}_output/CRF_spec.md` and the machine schema `{trial}_output/odm/crf_picks.json` (same field
set). Use [templates/crf_schema_template.md](templates/crf_schema_template.md) as the starting shape.

**Coverage rule — the SoA decides what EXISTS; the results table only decides what gets CALIBRATED.**
Put every variable the SoA collects into the frame (even with no posted result — it is emitted from
cited priors and left uncalibrated, `target: null`). Cross-check the field set against the SoA
row-by-row, then run the **CDISC SDTM completeness sweep** (checklist in
[templates/crf_schema_template.md](templates/crf_schema_template.md)): (1) tag every form with its
SDTM 2-letter domain code **and confirm the code matches the domain's real meaning** — map by content,
watch for collisions (a disease-activity form labelled `DA` is not Drug Accountability), and record
each code mismatch as its **own** mis-coded/collision finding (a clean gap list does not mean the
coding is clean); (2) confirm a **DM** form (the only mandatory domain); (3) sweep the collected-class
domains for anything the SoA collects but the form list dropped (**DV/HO/DA/DD/SC/SS/CO** are the usual
misses). A concept may ride on a related standard form (accountability on `EX`) — but a ride-along
counts as a home only if it is **lossless** (a fold that drops collected levels — e.g. only *former*
smokers get an MH row — is still a gap), and disease-specific clinical indices with no standard domain
(BVAS, PASI) go in a sponsor-defined Findings domain. The SoA cross-check and this sweep are both
**agent checks** — nothing downstream enforces them; the trial-design/derived scaffolding domains are
out of scope (we do not convert to SDTM).

**Applicability rule — some collected fields only EXIST for a sub-population.** A subject's
demographics/characteristics decide which measurements are even possible: lesional-skin readings need a
lesion, a pregnancy test needs a female subject, a disease-severity score needs that disease. Declare
these as `applicability_rules()` on the trial subclass — `list(form, cols, applicable = function(dm) …)`
— and the engine blanks those fields for the subjects a rule excludes, while the `g_logical_consistency`
gate (Step 6) re-checks it fail-closed: a value where the measurement cannot exist, or a blank where it
must, fails the build. Value-only invariants (age within eligibility, no pregnancy record for a male) go
in `consistency_rules()`. This is what keeps impossible demographic↔data combinations out of the CSVs —
declare the rule, never hand-blank per trial.

`crf_picks.json` shape: `study`, `metadata_oid/name`, `created`, `visits[]`, `forms[]` — each form has
`oid` (`FO.{NCT}.{FORM}`), `visits[]`, `section_oid/name`, `repeating` (`Simple` if >1 row/subject),
and `fields[]`. Each field OID is `IT.{NCT}.{FORM}.{COLUMN}` (trailing segment = the CSV column the
simulator emits) and is EITHER an NCI pick `{"oid":…, "cde":"<id>v<ver>"}` or custom
`{"oid":…, "custom":{"name":"…","type":"text|integer|float|date"}}`. For each field, search NCI and
bind a CDE **only** on a semantically exact top hit, else leave it custom (a wrong bind is worse than
custom; the library is oncology-skewed). From R:

```r
source("R/skill_root.R"); source("R/odm.R")            # (or run any run_*.R, which loads the engine)
nci_search("neutrophil count", 5)                       # picker aid
odm_build_template("{trial}_output/odm/crf_picks.json", "{trial}_output")   # build_spec→emit_odm→check_odm
```

`odm_build_template()` writes `odm/crf_spec.json` + `odm/crf_template.xml` and validates it fail-closed
(Gate 1 = official `ODM.xsd`, Gate 2 = references resolve). The field set is the **contract** the
simulator must emit.

### Step 3 · Build the evidence-based causal DAG
For every CRF variable, specify DAG parents + structural-equation form, categorized into the four
layers **L₀ baseline / A treatment / Lₜ time-varying / Yₜ endpoints** (endpoints are DERIVED from the
trajectory, never sampled). Gather every causal edge through paperclip (never from memory). Introduce
**latent frailties** per correlated AE/lab cluster (drawn once per patient, shared across equations —
this is what makes within-patient AEs correlated; never zeroed). Write `{trial}_output/DAG.md`
(one row per variable: parents · equation · Source · Evidence) using
[templates/scm_spec_template.md](templates/scm_spec_template.md). For a **non-randomized group** (e.g.
CATH's diagnosis strata), model it as a baseline stratum from a cited prior and randomize the arm
*within* it — argue exchangeability conditionally and flag the contrast **observational**; never a
silent coin-flip. You MAY also emit `{trial}_output/dag.json` (`{nodes, edges}`) to drive the render.

### Step 4 · Parameterize the structural equations
Set parameters from a priority hierarchy: (1) the CTGov results JSON, (2) fixed foundation-model rules
(CTCAE/FDA/RECIST grading — deterministic, **never tuned**), (3) literature priors via paperclip.
Uncalibrated variables (`target: null`) are parameterized from tiers 2–3 and flagged not-validated.
Pick the pattern for the endpoint archetype (time-to-event log-HR; continuous-change additive; binary
= threshold on the landmark trajectory). Parameters live in a per-trial params object (a list, or a
JSON snapshot the trial loads) — the **only** calibration surface. Multi-arm: one coefficient per
non-reference arm.

### Step 5 · G-formula forward simulation
Implement the trial as a `TrialSim` R6 subclass (mirror `examples/autoimmune/rave/rave.R`): set the
config (`prefix`, `nct`, `sched`, `admin_censor_day`, `emitters`, `default_n`, `default_seed`) and the
three hooks — `make_baseline(subj)`, `simulate_trajectory(patient, jit)`, `derive_endpoints(patient)`.
The base class supplies the per-patient loop, the CSV writer, the independent date-jitter substream
(`new_substream`, so the #182/#183 date fixes never shift the main draw order), and `reconcile_ae_ds`
(#184). Draw from the main stream via the `np_*` wrappers in `R/rng.R`; endpoints are read off the
trajectory. Run it:

```r
Rscript examples/<area>/<trial>/run_<trial>.R [N] [SEED] [OUT_DIR]
```

**Contract check** — as soon as the first CSVs exist, before calibrating:

```r
odm_check_columns("{trial}_output/odm/crf_picks.json", "{trial}_output/crfs")   # exit 0 required
```

It flags any drift between the schema and the emitted columns, both directions.

### Step 6 · Calibration loop (causality-preserving) + statistical review
Calibrate only features with a posted result; leave `target: null` features at their priors (they are
still simulated and still must pass every gate). Tune structural-equation **parameters only, never
structure** — see the invariants in [calibration.md](calibration.md). Each iteration: simulate →
`measure_marginals()` → run the two gate families and **assert them fail-closed**:
- **(a) machine realism/date gates** (visit-date variance #183, AE-onset dispersion #182,
  continuous-time discontinuation #183, AE↔DS traceability #184), and
- **(b) per-trial causal-structure gates** (the trial's `run_dag_gates` — AE↔lab linkage,
  arm→mediator direction, endpoint=trajectory, stratifier sign, frailty-cluster correlation), and
- **(c) logical-consistency gate** (`g_logical_consistency`) — the trial's `applicability_rules()` +
  `consistency_rules()` re-checked on the CSVs: every field is filled exactly when it applies to the
  subject, and no impossible demographic↔data combination appears (see Step 2).

Gates read the **emitted CSVs**, never engine state, and the AE↔DS gate keys on the emitted reason
field. `run()` already runs the trial's gates fail-closed (`stop()` on any failure). Use
`calibration_report(sim, …)` to simulate + compare an already-calibrated trial, or `calibrate(sim,
targets, knob_map, …)` for a new one (single-knob damped coordinate descent, ≤8 iters, reverts any
gate-breaking update). A many-small-cell continuous endpoint may not land every cell within tolerance
at small N — that is expected and does not fail the build; the verdict is gates all_pass.

**At the end of each trial run, run the statistical-reviewer skill** on the emitted bundle as an
independent realism check (do not hardcode fixes to pass it — feed its findings back as spec/parameter
improvements).

### Step 7 · Fill + validate ODM v2.0
Insert the final patients into the Step-2 blank form and re-validate (the form is not rebuilt):

```r
odm_fill("{trial}_output/odm/crf_template.xml", "{trial}_output/crfs", "{trial}_output/odm/odm.xml")
```

`odm_fill()` errors if any CSV column has no field in the template, then validates fail-closed
(`check_odm`: official XSD + references resolve). Output: `{trial}_output/odm/odm.xml`.

### Step 8 · Render the trial to HTML
`run(render_html=TRUE)` (the default) automatically renders `{trial}_output/index.html` — an
interactive Cytoscape DAG + the rendered `DAG.md`/`CRF_spec.md`/`README.md` — after the gates pass.
Best-effort: a missing `DAG.md`/renderer never breaks the run. The render also writes a secondary
copy under a sibling `docs/trials/` of the skill folder (a convenience for a docs dashboard, outside
the run bundle and harmless); `index.html` in the run folder is the deliverable. The page title comes
from the output-folder name, so name it `{TRIAL}_output`. Re-run `render_docs("{trial}_output")` to
refresh after writing `README.md` last or editing `DAG.md`.

## Concrete deliverables (`{trial}_output/`)
```
README.md          # run manifest (trial/NCT/N/seed/date + per-gate PASS) + folder map
intake/{NCT}.json  # step 1
CRF_spec.md        # step 2 (human view)
DAG.md             # step 3 (cited)
params/            # steps 4 & 6 snapshots
crfs/              # step 5/6 — {trial}_CRF_*.csv (the deliverable)
analysis/          # step 6 — marginals, sim-vs-published, gate results
odm/               # crf_picks.json + crf_spec.json + crf_template.xml (step 2) + odm.xml (step 7)
index.html         # step 8 — interactive DAG + rendered docs
```
`intake/`, `CRF_spec.md`, `DAG.md`, `params/`, and `odm/crf_picks.json` are **authored** across Steps
1–4 (for the shipped examples they live under `examples/<area>/<trial>/`); `crfs/`, `analysis/`,
`README.md`, `odm/*.xml`, and `index.html` are **generated**. The shipped `run_<trial>.R` entry points
stage the authored `DAG.md` + `odm/crf_picks.json` into the run folder and then build the ODM export
**best-effort** (skipped with a note if no ODM-deps python is configured), so a single
`Rscript examples/<area>/<trial>/run_<trial>.R` yields the full bundle. A brand-new trial authors those
inputs itself (Steps 2–4) and runs the ODM commands explicitly.

The engine (`R/` + `examples/<area>/<trial>/`) lives outside the run folder; `params/` + the RNG seed
make a run reproducible without copying code.

## Worked examples
- **RAVE** (`examples/autoimmune/rave/`, NCT00104299) — binary complete-remission-at-6-months; 12 forms,
  6 causal gates, calibrated marginals within TOL=0.07. `Rscript examples/autoimmune/rave/run_rave.R`.
- **CATH** (`examples/allergy/cath/`, NCT00789880) — continuous change-from-baseline biomarkers; 17
  forms, observational diagnosis strata, ~zero serious AEs by design, the ODM demo.
  `Rscript examples/allergy/cath/run_cath.R`.

## Common pitfalls
1. Calibrating without the DAG gates — it must be optimization *subject to* the gates.
2. Letting the visit grid run past the data cutoff — set `admin_censor_day` from the CTGov cutoff.
3. Drawing date jitter from the main RNG — it must come from `new_substream(seed, subj)`; drawing from
   the shared stream shifts every downstream draw and silently breaks calibration.
4. Drawing endpoints directly instead of deriving them from the trajectory.
5. Independent-draw AEs — always give an AE cluster a shared frailty, or types are independent given arm.
