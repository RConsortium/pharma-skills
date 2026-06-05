# Calibration Sub-Skill — Causality-Preserving Marginal Tuning

This document describes the iterative calibration loop invoked from the
main `clinical-trial-ipd-sim` skill. It can also be run standalone when
the user has an existing simulator and wants to tune marginal stats
toward a fresh CTGov target.

## Purpose

Reduce the discrepancy between simulated marginal statistics and the
empirical results (ClinicalTrials.gov + published trial paper) **without
breaking the causal DAG**.

## Inputs

- `R/` — R modules implementing the g-formula simulator
- `dag_spec.md` — formal DAG specification (variables, parents, equations)
- `targets.json` — the empirical results to calibrate against:
  ```json
  {
    "median_pfs_months": {"combo": 25.5, "mono": 16.7},
    "hr": {"point": 0.62, "ci_low": 0.49, "ci_high": 0.79},
    "ae_any_pct": {"combo": 100, "mono": 97},
    "ae_gr3plus_pct": {"combo": 64, "mono": 27},
    "ae_sae_pct": {"combo": 38, "mono": 19},
    "ae_disc_pct": {"combo": 47, "mono": 6},
    "top_ae_combo": {"NEUTROPENIA": 31, "ANEMIA": 23, ...}
  }
  ```
- `tolerance.json` — per-metric tolerance band (default ±20% relative or 1
  CI-width absolute, whichever is tighter)

## DAG gates (must pass at every iteration)

Before a parameter update can be accepted, the simulator must satisfy:

| Gate | Test | Pass criterion |
|---|---|---|
| AE-lab linkage | mean ANC at visits with Neutropenia AE | < 1.5 ×10⁹/L |
| AE-lab linkage | mean HGB at visits with Anemia AE | < 11.0 g/dL |
| AE-AE correlation | within-patient r among GI AEs (combo) | > 0.20 |
| AE-AE correlation | within-patient r among heme AEs (combo) | > 0 (signed) |
| PFS↔trajectory | corr(PFS_DAYS, longitudinal progression day) | > 0.95 |
| Stratifier sign | TP53 mutant vs WT median PFS | mutant < WT |
| Stratifier sign | EGFR Ex19del vs L858R median PFS | Ex19del ≥ L858R (per literature) |
| Topology | no cycles in DAG; every variable has only its declared parents | static check on `dag_spec.md` |

Gates are coded in `R/verify_dag_gates.R` or
`tests/testthat/test-dag-gates.R` and run as boolean tests. If any gate
fails after a proposed update, **revert the update and log a causality
regression**.

## Algorithm

```r
calibrate <- function(params, targets, tol, max_iter = 8) {
  history <- list()

  for (it in seq_len(max_iter)) {
    outputs <- run_simulation(params)
    metrics <- compute_metrics(outputs)
    gates <- verify_dag_gates(outputs)

    history[[it]] <- list(
      iter = it,
      params = params,
      metrics = metrics,
      gates = gates
    )

    stopifnot(all(unlist(gates)))

    if (max_relative_error(metrics, targets) < tol) {
      return(list(params = params, history = history))
    }

    proposed <- propose_update(params, metrics, targets)
    trial_outputs <- run_simulation(proposed)

    if (all(unlist(verify_dag_gates(trial_outputs)))) {
      params <- proposed
    } else {
      history[[it]]$rejected <- proposed
      params <- back_off(params, proposed)
    }
  }

  list(params = params, history = history)
}
```

## Allowed parameter knobs

These are the only parameters the loop may modify. Anything else
constitutes a structural change and must be reviewed by the user.

### Time-to-event scale knobs

| Knob | Affects | Increase to … |
|---|---|---|
| `BASE_TIME_TO_RESISTANCE_DAYS` | Mono-arm PFS scale | Lengthen mono median PFS |
| `LOG_HR_ARM` | Combo-arm multiplicative scale | Strengthen treatment effect (HR ↓) |
| `WEIBULL_SHAPE` | Spread of time-to-resistance | Tighter shape → narrower CI |
| `POST_RESIST_GROWTH_RATE` | SLD regrowth speed | Shorter PFS-after-resistance lag |

### AE rate knobs

| Knob | Affects | Increase to … |
|---|---|---|
| `BASE_HAZ_<AE>` | Per-visit hazard for that AE while on treatment | Inflate any-grade rate of that AE |
| `COMBO_RR_<AE>` | Combo-arm relative risk | Widen mono/combo gap for that AE |
| `P_SEVERE_<AE>` | P(grade ≥3 ∣ event) | Inflate Gr ≥3 share without changing any-grade |
| `P_REPORT_LOWGRADE` | Reporting probability for lab Gr 1–2 events | Inflate any-grade lab AE rate |
| `OFF_TREATMENT_HAZARD_DOWNSCALE` | Multiplier for AE hazard after EOT | Decrease post-EOT AE inflation |

### Lab dynamics knobs

| Knob | Affects | Increase to … |
|---|---|---|
| `AR_COEF_<LAB>` (α) | Within-patient autocorrelation | Stronger cascade of low values |
| `CHEMO_DRAG_<LAB>` | Mean nadir depth during chemo | Deeper nadirs |
| `CHEMO_DRAG_FRAILTY_<LAB>` | Frailty multiplier on nadir | Wider patient-level variation |
| `LAB_NOISE_<LAB>` | σ of per-visit residual | Bigger random shocks |

### Frailty knobs

| Knob | Affects | Increase to … |
|---|---|---|
| `SIGMA_F_HEME` | Heme cluster correlation strength | Stronger ANC/HGB/PLT shared variation |
| `SIGMA_F_GI` | GI cluster correlation | Stronger nausea/vomiting/diarrhea correlation |
| `SIGMA_F_<...>` | Other clusters | Same |

### Discontinuation knobs

| Knob | Affects | Increase to … |
|---|---|---|
| `DISC_INTERCEPT` | Baseline discontinuation hazard | More dropout overall |
| `DISC_AE_BURDEN_COEF` | AE-driven discontinuation | More AE-related dropout |
| `DISC_FRAILTY_COEF` | Patient-level dropout heterogeneity | More heterogeneous dropout |

## Forbidden knobs (would break causality)

- ❌ Direct PFS time draw conditional on arm (bypasses trajectory)
- ❌ Hard-coding a specific patient subset to have a particular outcome
- ❌ Adding a new edge from a descendant back to an ancestor
- ❌ Replacing a deterministic CTCAE/RECIST rule with a stochastic mapping
- ❌ Conditioning a baseline node on a post-baseline variable
- ❌ Setting any `SIGMA_F_*` to exactly 0 (use a small positive value
  if you need to dampen, but full removal eliminates patient-level
  correlation entirely)

## Update proposal heuristics

Prefer in this order:

1. **Single-knob, large-effect changes first.** If median PFS is off by
   30%, change `BASE_TIME_TO_RESISTANCE_DAYS` alone. Don't simultaneously
   tweak the post-resistance growth rate — you'll lose attribution.
2. **Match log-scale targets log-linearly.** For HR: if current HR is
   `h_now` and target is `h*`, propose `LOG_HR_ARM_new = LOG_HR_ARM_old + ln(h*/h_now)`.
3. **AE rates: tune `base_haz` first, `p_severe` second.** Any-grade rate
   tells you about hazard; severe-grade share tells you about `p_severe`.
4. **Move at most 2 knobs per iteration.** More than 2 simultaneous
   changes makes diagnosis impossible if a gate breaks.
5. **Cap relative parameter changes at ×1.5 per iteration.** Prevents
   oscillation.

## Termination criteria

- All marginal metrics within tolerance: SUCCESS
- All gates passing but discrepancies plateau across 3 iterations:
  STALLED — report which metrics could not be hit and which knobs were
  exhausted; suggest a structural review of the DAG (e.g., maybe the
  trial's discontinuation pattern requires a non-modeled mediator).
- Any gate broken: HALT — report which gate, which knob caused it,
  and roll back to the last valid parameter set.

## Example log

```
iter 0: PFS_combo=18.0 (target 24.0), HR=0.88 (target 0.65)
        gates OK. Proposed: bump LOG_HR_ARM by +0.30, BASE_TTR by ×1.25
iter 1: PFS_combo=22.8, HR=0.67
        gates OK. Within tolerance. STOP.
```

## Output

After the loop terminates, write a calibration report:

```markdown
# Calibration report — NCT{NCTID}

## Final marginals vs targets
| Metric | Target | Final | Δ% |
|---|---|---|---|
| Median PFS, combo | 24.0 mo | 22.8 mo | -5.0% |
| HR | 0.65 | 0.67 | +3.1% |
| ... | ... | ... | ... |

## DAG gates (final)
- AE↔lab linkage: PASS (ANC@Neut = 0.52)
- ...

## Parameter trajectory
[per-iteration param snapshots]

## Knobs exhausted (if STALLED)
- ...
```

This report is the artifact the user reviews before accepting the simulated
CRFs as final.

For R builds, also emit machine-readable calibration history under
`params/` as JSON/CSV and include SDTM/ADaM/TLG/export validation status in
the final report. Export validation should use the same final accepted
parameter set and must not introduce fresh randomness.
