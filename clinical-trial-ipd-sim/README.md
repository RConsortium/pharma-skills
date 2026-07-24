# clinical-trial-ipd-sim (R edition)

An R port of the `clinical-trial-ipd-sim` Claude skill. Given an NCT ID with
posted ClinicalTrials.gov results and a user-supplied protocol PDF, it emits
synthetic individual-patient-data (IPD) CRFs as CSV files whose **marginal
statistics match the published trial** while the **joint distribution follows
an explicit, cited causal DAG**. Alongside the CSVs it produces a validated
CDISC ODM v2.0 export and an interactive DAG/CRF HTML page.

## What it does

Most "synthetic IPD" tools draw each outcome from its own distribution given
the treatment arm. That reproduces headline numbers but throws away the
within-patient structure real analysts rely on — AE clusters share nothing,
labs and AEs are not linked, and endpoints (PFS/OS, remission) are sampled
directly instead of being read off a trajectory.

This skill instead runs a **g-formula forward simulator**. Every patient is
built one node at a time in causal order — baseline `L0` -> treatment `A` ->
time-varying state `Lt` -> outcomes `Yt` — and each node is conditioned on its
DAG parents. Latent per-patient frailties induce realistic correlation across
visits and AE/lab clusters. Endpoints are deterministic functions of the
simulated trajectory, never independent draws.

## Architecture (R6 + g-formula)

The engine is one shared R6 base class plus one subclass per trial:

- `R/trial_sim.R` — the `TrialSim` R6 base class. It owns the whole run:
  validate config/params, seed the RNG, loop over patients, write one CSV per
  form, run the DAG gates **fail-closed**, write the manifest, and render HTML.
- A trial subclass (e.g. `RaveSim`, `CathSim`) sets a few config fields and
  implements three generation hooks — `make_baseline()`, `simulate_trajectory()`,
  `derive_endpoints()`. That is the only per-trial generation code you write.
- Supporting modules under `R/`: `rng.R` (numpy-compatible draw wrappers plus
  the independent date-jitter substream), `validate.R` (validate-only config /
  param checks), `odm.R` + `render.R` (thin wrappers that shell out to the
  vendored Python toolchain), `calibrate.R` (the params-only calibration loop),
  `skill_root.R` (path + interpreter helpers).

The full module contract is in [`r_implementation.md`](r_implementation.md);
the calibration loop is in [`calibration.md`](calibration.md).

## The two worked examples

**RAVE (NCT00104299)** — the canonical reference. ANCA-associated vasculitis,
rituximab vs cyclophosphamide, a **binary complete-remission** endpoint. 12
CRFs, 6 DAG gates.

```
Rscript examples/autoimmune/rave/run_rave.R [N] [SEED] [OUT_DIR] [PARAMS.json]
# defaults: N=197, SEED=20100715, OUT_DIR=outputs/RAVE
```

**CATH (NCT00789880)** — the continuous-endpoint and ODM demo. A
change-from-baseline biomarker endpoint with a zero-serious-AE grading rule. 17
CRFs, 8 DAG gates, and the ODM v2.0 export.

```
Rscript examples/allergy/cath/run_cath.R [N] [SEED] [OUT_DIR]
# defaults: N=82, SEED=789880, OUT_DIR=outputs/CATH
```

Each script bootstraps itself — it walks up to find the skill root (the folder
holding `R/` and `vendor/`), sources the engine, sources its own example
modules, then calls `sim$run(...)`. Run from anywhere; paths are resolved for
you. `examples/stub/` is a minimal skeleton to copy when starting a new trial.

## Requirements

**R** 4.x with these packages (all used via `pkg::fn`; only `R6` is attached):

```
R6, dplyr, readr, tibble, jsonlite
```

That is enough to run the simulator, the gates, and the core tests.

**Python** — only the ODM export, the HTML render, and the NCI CDE search shell
out to a vendored Python toolchain under `vendor/python/`. Install its deps
once:

```
python3 -m pip install -r vendor/python/requirements.txt
# lxml, duckdb, pandas, pypdf, requests
```

Point the engine at that interpreter with `options(ctids.python = "...")`, the
`CTIDS_PYTHON` environment variable, or just have a suitable `python3` on your
`PATH`. Never hardcode a personal path. If no Python is configured the render
step is skipped (best-effort, non-fatal) and the ODM steps raise a clear error.

## Output bundle

A run writes everything under `<OUT_DIR>/`:

| Item | What it is |
|---|---|
| `crfs/` | one CSV per CRF form, e.g. `RAVE_CRF_DM.csv` (the primary deliverable) |
| `README.md` | the run manifest — folder-contents table, row counts, N/seed, gate pass/fail |
| `DAG.md`, `CRF_spec.md` | the cited causal DAG and CRF schema, staged into the bundle |
| `dag.json` | machine twin of the DAG (only if the trial defines `dag_structure()`) |
| `odm/` | `crf_spec.json`, blank `crf_template.xml`, filled `odm.xml` (CDISC ODM v2.0) |
| `index.html` | the interactive DAG/CRF page (best-effort render) |

The DAG gates run on the **emitted CSVs**, not on internal state, and the run
**stops** if any gate fails. The acceptance bar is: all gates pass, and the
marginals land within the trial's documented tolerance.

## Important: this is NOT byte-identical to the Python version

R's base RNG (Mersenne-Twister with inversion-method normals) **cannot**
reproduce NumPy's PCG64 bitstream. So this R port is **not** a byte-for-byte
match of the Python skill and is not meant to be. It is a faithful
re-implementation of the same **structure, logic, and gates**, with its own
**reproducible** draws (a fixed seed gives identical output every time) and
**re-calibrated in R** to the same published ClinicalTrials.gov targets.

The success criterion is never a byte match. It is: DAG gates all pass
(fail-closed) **and** marginals within the documented tolerance.

## Validated results

- **RAVE** — 12 CSVs; all 6 DAG gates pass; 8/8 calibrated marginals within
  `TOL = 0.07`; ODM v2.0 blank + filled both validate; `index.html` renders.
- **CATH** — 17 CSVs; all 8 DAG gates pass; `EX` emitted for all 82 subjects;
  dropouts carry no Day-21 data; ODM v2.0 validates; 79/83 marginals within
  CI-halfwidth tolerance (the 4 misses are small-cell SD/mean noise, expected
  and not a build failure — see [`calibration.md`](calibration.md)).

## For the R Consortium / pharmaverse skills PR

This folder is self-contained — the engine, both examples, the vendored Python
toolchain, and the CDISC XSD schemas all ship inside it, so the skill runs with
no network access. One caveat worth flagging: the NCI caDSR CDE index
(`vendor/python/parsed_forms/nci.duckdb`, ~64 MiB) is committed as a binary
asset. It is **only** needed for the ODM CDE-picker steps; the simulator, the
DAG gates, and the core tests all run without it. Package it with Git LFS or
document it as an optional download if the 64 MiB is a concern for the PR.
