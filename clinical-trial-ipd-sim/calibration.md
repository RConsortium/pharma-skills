# Calibration Sub-Skill — Causality-Preserving Marginal Tuning

The Step-6 loop that pulls a simulator's marginal statistics toward the
published ClinicalTrials.gov results **without breaking the causal DAG**. It is
shipped as runnable R in [`R/calibrate.R`](R/calibrate.R), not just described
here. It tunes structural-equation **parameters only** — never structure — and
re-runs the trial's DAG gates on every candidate, reverting anything that
breaks a gate or raises an error.

## Two entry points

- **`calibration_report(sim, n, seed, compare_fn)`** — simulate once (gates
  fail-closed), measure the marginals, and optionally compare them to targets
  via `compare_fn(marg)`. This is the common Step-6 path for a trial whose
  params are **already calibrated**: you just want to verify the gates pass and
  print the marginals-vs-targets table.
- **`calibrate(sim, targets, knob_map, scales, max_iter=8, tol=0.05, n, seed)`**
  — the iterative loop for a **new** trial that still needs tuning.

## Inputs

- `sim` — a `TrialSim` subclass instance. It supplies `run()`, `run_dag_gates()`
  (fail-closed), `measure_marginals()`, and the mutable `sim$params` list.
- `targets` — a named numeric vector, one entry per marginal you are fitting
  (e.g. `cr6mo_RTX = 0.636`). Only features with a posted result are calibrated;
  everything else is still simulated from cited priors and must still pass every
  gate — it is just never tuned.
- `knob_map` — keyed by target metric, each entry
  `list(knob=<param name>, dir=<sign of d(metric)/d(knob)>, step=<initial step>, min=, max=)`.
- `scales` — optional per-metric normalizer (defaults to 1); lets metrics on
  different units share one tolerance.

## Calibration invariants (never violate)

These are what separate a real SCM simulator from a marginal-fitter dressed up
with extra forms. The loop is physically unable to touch them — they live
outside the tunable `params` — but hold them in mind when you choose knobs:

1. **Endpoints stay functionals of the trajectory** — never draw an endpoint
   independent of the simulated state.
2. **No arm -> outcome edge that bypasses the modeled mediators** — every
   treatment effect flows through labs, AEs, dose, disease state, discontinuation.
3. **No cycles** — the DAG stays acyclic; every node keeps only its declared parents.
4. **Never zero a frailty** — frailty SDs are tunable but must stay positive;
   zeroing one removes patient-level correlation entirely (a structural change).
5. **Never turn a deterministic grader into a random draw** — the CTCAE / FDA /
   RECIST grade functions are fixed; calibration tunes their *inputs*, not the rules.

## Allowed knobs by endpoint archetype

Which knobs exist depends on the endpoint; the *principle* (tune parameters,
never structure) is universal. The AE / frailty / discontinuation knobs are
area-neutral and apply whatever the archetype.

| Archetype | Endpoint-scale knobs |
|---|---|
| Time-to-event (PFS/OS) | base time-to-event **scale**; treatment-effect **HR / log-HR coefficient**; hazard shape |
| Continuous change-from-baseline (e.g. CATH) | **arm-mean** effect; natural **drift**; per-visit **residual SD** |
| Binary landmark (e.g. RAVE remission) | the intercepts/propensities of the state variables feeding the landmark criterion |

| Area-neutral knobs | Affects |
|---|---|
| AE rate | per-visit **hazard** per AE; arm relative risk; grade-≥3 share; low-grade lab **reporting probability** |
| Frailty | cluster correlation **strength** (heme, GI, …) — tunable, never zero |
| Discontinuation | baseline dropout **intercept**; AE-burden coefficient; per-patient heterogeneity |

## The loop, mapped to `calibrate()`

`calibrate()` is a **single-knob, damped coordinate descent** — deliberately
simple and auditable:

1. Simulate once (gates fail-closed) and measure the baseline marginals; record
   the max normalized error across `targets`.
2. Each iteration, find the **worst-off** metric and look up its knob in
   `knob_map`. If there is no knob for it, **stop**.
3. Nudge that one knob toward closing the gap: `step * sign(gap) * dir`, clipped
   to `[min, max]`.
4. Re-simulate the candidate (**gates fail-closed** — an error or gate break
   makes the candidate's error `Inf`).
5. If the candidate lowers the max error, **accept** it. Otherwise **revert** the
   knob and **halve** its step (damping), so a non-improving move shrinks the
   next attempt instead of oscillating.
6. Repeat up to `max_iter` (default 8) or until the max error is `<= tol`.

Only one knob moves per iteration, so attribution is never ambiguous. Because
every candidate is re-verified fail-closed, a gate-breaking parameter set can
never be shipped — it is reverted. Calibrate at a large N with a fixed seed so
sampling noise is small relative to the target gap, then ship the trial at its
normal N.

## Termination

- **SUCCESS** — max normalized error `<= tol`. `calibrate()` returns
  `status = "SUCCESS"` with the tuned `params`, the final marginals, and the
  per-iteration `history`. `sim$params` is left tuned.
- **STALLED** — `max_iter` reached (or the worst metric has no knob) without
  hitting `tol`. Returns `status = "STALLED"`. Report which metrics could not be
  hit; if a marginal is structurally unreachable with the allowed knobs, that is
  a signal to review the DAG (an unmodeled mediator), **not** to add a forbidden
  knob.

## Known limitation — many small cells

For a continuous endpoint whose target is a grid of small-cell means and SDs —
CATH reports a biomarker change per group × compartment × arm at N=82, so a cell
can be ~8 patients — **not every cell mean/SD will land inside tolerance**. The
mean and SD of an 8-person cell are simply very noisy. This is **expected** and
does **not** fail the build. In CATH, 79/83 marginals land within CI-halfwidth
tolerance and the 4 misses are small-cell noise. The deliverable verdict is
always **gates all_pass** plus marginals within the documented tolerance — never
a per-cell exact match.

## Forbidden knobs (would break causality)

- Drawing an endpoint directly from arm, bypassing the trajectory.
- Hard-coding a patient subset to a fixed outcome.
- Adding an edge from a descendant back to an ancestor (a cycle).
- Replacing a deterministic CTCAE/FDA/RECIST rule with a stochastic mapping.
- Conditioning a baseline node on a post-baseline variable.
- Setting any frailty SD to exactly 0.

Any of these is a structural change, not calibration, and must be reviewed with
the user — it is not something the loop may do on its own.
