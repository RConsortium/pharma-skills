# R Implementation Guide

How the R edition is built, so you can read the engine and add a new trial
without re-deriving it. The engine is a g-formula structural-causal-model
simulator on R6: one shared base class, one subclass per trial, plus a small
set of support modules and a vendored Python toolchain the engine shells out to.

## Packages

- `R6` — the `TrialSim` base class and every per-trial subclass (attached).
- `dplyr`, `readr`, `tibble` — row-binding, CSV writing, tibble emitters
  (used as `pkg::fn`, not attached).
- `jsonlite` — parameter snapshots, `dag.json`, ODM `crf_picks.json`.

The simulator, gates, and core tests need nothing else. The ODM / render /
NCI-search steps shell out to Python (see below).

## Module layout

```text
R/                         # the shared engine — never edited to add a trial
├── skill_root.R           # skill_root()/skill_file()/skill_python(), %||%, clip, expit, ct_rec, .or_blank
├── rng.R                  # numpy-compat np_* draw wrappers + new_substream() jitter stream
├── validate.R             # validate_config() / validate_params() — validate-only
├── trial_sim.R            # the TrialSim R6 base class (the whole run loop)
├── gates.R                # shared reference realism/date-gate harness: gate_config() + run_realism_gates() (#182/#183/#184); a new trial adapts it (CATH did -> cath_gates.R)
├── odm.R                  # odm_build_template/odm_check_columns/odm_fill/nci_search (shell out)
├── render.R               # render_docs() (shell out, best-effort)
└── calibrate.R            # calibrate() + calibration_report()
examples/<area>/<trial>/   # one folder per trial (canonical: autoimmune/rave/)
vendor/python/             # the vendored Python toolchain (ODM, render, find-protocol, nci.duckdb)
```

## The `TrialSim` R6 base class

Identical for every trial; a subclass sets config and fills hooks.

**Config fields a subclass sets:**

- `prefix` — CSV file prefix, e.g. `"RAVE"` -> `RAVE_CRF_DM.csv`.
- `nct` — the ClinicalTrials.gov ID (for the manifest).
- `sched` — the visit schedule: a list of `list(key, visitnum, day, label)`.
- `admin_censor_day` — the data-cutoff day.
- `emitters` — a **named** list, `form -> function(patient) -> tibble` of rows.
- `default_n`, `default_seed` — defaults for `run()`.
- `allowed_params` / `param_checks` — optional validate-only typo net.
- `fixed_n` — optional; set when the roster is fixed (real-covariate bootstrap),
  so the calibrator honours it instead of resampling N.

**Methods a subclass inherits unchanged:**

- `run(n_patients, seed, out_dir, verify=TRUE, render_html=TRUE, manifest=TRUE)`
  — the whole build. It (1) validates config + params **before any RNG**, (2)
  sets the one main RNG stream with `set.seed(seed)`, (3) loops over patients,
  (4) writes one CSV per form under `<out_dir>/crfs/`, (5) runs the DAG gates
  **fail-closed** (`stop()` unless `all_pass`), (6) writes the `README.md`
  manifest and optional `dag.json`, (7) best-effort renders `index.html`.
- `simulate_one()` — one patient in topological order: `make_baseline` ->
  `new_substream` (jitter) -> `simulate_trajectory` -> `derive_endpoints` ->
  `reconcile_ae_ds`.
- `emit_all()` — project a finished patient into CRF tibbles via `emitters`.
- `between()` / `clamp_actual_day()` — the shared date helpers (issues #182/#183).
- `reconcile_ae_ds()` — the AE<->disposition traceability fix (issue #184).
- `write_manifest()` / `write_dag_json()` — the run bundle files.

## The three hooks a subclass implements

Keep the causal topological order and condition every node on its DAG parents.

- `make_baseline(subj_num)` — sample `L0`, randomize treatment by the protocol
  ratio/stratification, and **draw the patient's frailties once here**; carry
  them through the trajectory. Return the patient record.
- `simulate_trajectory(patient, jit)` — walk the visit grid, updating labs,
  disease state, AEs, dose actions, and discontinuation in causal order. Lab
  AEs derive from lab values via fixed CTCAE/FDA grade rules plus a reporting
  model; non-lab AEs use per-visit hazards with arm, exposure, and frailty
  parents. `jit` is the injected date-jitter stream (see below).
- `derive_endpoints(patient)` — derive endpoints from the trajectory, never
  drawn directly from arm (binary remission read off the endpoint-visit row;
  time-to-event as `min(progression, death, admin_censor_day)`; continuous as
  landmark-minus-baseline).

**Optional overrides:** `default_params()`, `seed_emit(seed)` (if the emit
layer has its own RNG), `run_dag_gates(crfs_dir)` (the trial's gate harness),
`measure_marginals(out_dir)` (read marginals back from the emitted CSVs),
`dag_structure()` (so `dag.json` is written).

## The RNG layer — the one load-bearing invariant

`R/rng.R` has two parts:

1. **numpy-compat single-draw wrappers** — `np_normal`, `np_uniform`,
   `np_integers`, `np_choice`, `np_bernoulli`, `np_exponential`, `np_binomial`,
   `np_poisson`, `np_gamma`, `np_beta`, `np_lognormal`. Each maps 1:1 to a
   NumPy call and consumes one draw, so an R hook line reads directly against
   the Python and frailties stay shared across equations in the right order.
2. **`new_substream(seed, subj_num)`** — an **independent** per-patient
   date-jitter stream, keyed on `(seed, subj_num)`. Its `$draw(fn)` swaps in a
   private RNG state, runs `fn()`, then **saves and restores the global
   `.Random.seed`**. So adding, removing, or changing a date-jitter call never
   shifts a single main-stream draw. This is the single load-bearing
   correctness invariant of the port — the date fixes cannot disturb the
   calibrated marginals.

**Non-identity note (state it plainly).** R's Mersenne-Twister + inversion
normals cannot reproduce NumPy's PCG64 bitstream. This port is therefore
**not** byte-identical to the Python — it is a faithful re-implementation of
the structure/logic/gates with its own **reproducible** draws (fixed seed ->
identical output), re-calibrated in R to the same published targets.

## Records are environments (reference semantics)

Patient / visit / AE records are R **environments** (built with `ct_rec(...)`),
not lists. That gives them reference semantics, so `reconcile_ae_ds()` can flip
AE actions **in place** after the trajectory is final. `reconcile_ae_ds()`
makes the disposition reason and the `DRUG WITHDRAWN` AE agree; it carries a
**0-SAE fallback** — when there is no serious AE on/before exit (as in a
zero-serious-AE trial like CATH), it falls back to the most recent AE so the
link still traces. This is centralized in `simulate_one()`, so every trial gets
the #184 guarantee and no hook double-calls it.

## Validation is validate-only

`validate_config(sim)` and `validate_params(params, allowed, checks)` are the R
analogue of the Python pydantic models: they **fail loudly** on a bad config or
an unknown/out-of-range param, but **return the input unchanged**. The engine
keeps reading the original list, so a calibrated param set is never silently
coerced. They run at the top of `run()`, before any RNG.

## Gates are fail-closed and read the emitted CSVs

Each trial provides `run_dag_gates(crfs_dir)` returning a list with a boolean
`$pass` per gate and a top-level `$all_pass`. The gates read the **emitted
CSVs**, never internal state. `run()` calls them fail-closed and `stop()`s the
build unless `all_pass`.

- **RAVE** — `rave_metrics.R`: gates `g1`..`g6` (AE<->lab linkage,
  arm->myelosuppression, within-patient GI correlation, endpoint-is-trajectory,
  stratifier sign, AE<->DS traceability), plus `RAVE_TARGETS` and `RAVE_TOL = 0.07`.
- **CATH** — `cath_gates.R`: four date/traceability gates (visit-date variance,
  AE-onset dispersion, continuous discontinuation, AE<->DS traceability) + four
  causal gates (endpoint-from-trajectory, arm->mediator direction, stratifier
  sign, frailty-cluster correlation), plus a high-N confirmation diagnostic for
  the checks that are under-powered at N=82.

## ODM / render / NCI search — shell out to vendored Python

Locked design: the whole CDISC ODM v2.0 toolchain stays Python and is called
from R via base `system2`, **fail-closed** on a non-zero exit. R only (a)
authors `crf_picks.json` and (b) emits the CSVs.

- `odm_build_template(picks_path, out_dir)` — build + validate the **blank**
  form (`build_spec.py` -> `emit_odm.py` -> `check_odm.py`).
- `odm_check_columns(picks_path, crfs_dir)` — contract check that emitted CSV
  columns match the picks both ways.
- `odm_fill(template, crfs_dir, out_xml)` — fill the blank template with the
  CSVs and re-validate (`emit_clinicaldata.py` -> `check_odm.py`).
- `nci_search(query, k)` — BM25 search of the NCI CDE index, the Step-2 picker aid.
- `render_docs(out_dir)` — best-effort HTML render (`render_trial_docs.py`); a
  missing `DAG.md`, missing Python, or render error just prints a note.

The vendored scripts self-locate the duckdb index (`parsed_forms/nci.duckdb`)
and the XSD (`xsd_v2/ODM.xsd`) by relative path, so no path arguments and no
edits are needed. The interpreter comes from `options(ctids.python=)`, the
`CTIDS_PYTHON` env var, or `python3` on `PATH` — never a hardcoded personal
path. The 64 MiB duckdb index is only needed for the ODM CDE steps.

## Per-trial module layout

A trial folder splits the subclass across small files sourced in dependency
order by its `run_*.R` entry point (see `run_rave.R` / `run_cath.R`):

```text
examples/<area>/<trial>/
├── <trial>_dag_state.R    # record constructors / DAG state helpers
├── <trial>_params.R       # default_params() (+ loader for a frozen params JSON)
├── <trial>_baseline.R     # make_baseline() hook
├── <trial>_longitudinal.R # simulate_trajectory() hook
├── <trial>_outcomes.R     # derive_endpoints() hook
├── <trial>_graders.R      # (optional) fixed CTCAE/FDA grade functions
├── <trial>_emit.R         # the CRF emitters (RNG-free projections)
├── <trial>_gates.R / _metrics.R  # run_dag_gates() + measure_marginals()
├── <trial>.R              # the R6 subclass wiring the config + hooks together
├── run_<trial>.R          # entry point: bootstrap skill root, source modules, run()
├── DAG.md, odm/crf_picks.json, params/, intake/   # authored inputs
```

## R coding rules

- Build every trial as an R6 subclass of `TrialSim`; never fork the base class.
- Keep all randomness in the two generation hooks; **emitters are RNG-free**
  projections. Use the injected `jit` substream for any date jitter.
- Expose only intended calibration knobs in `params`; keep grade rules and
  frailty SDs unreachable from the tunable set. Cite every causal edge / prior
  in `DAG.md`.
- Keep a "number or blank" CRF column a single character type (use `.or_blank`)
  so cross-patient row-binding never hits a type clash.
