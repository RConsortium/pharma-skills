# Code Snippets: Composing TrialSimulator Building Blocks

Worked combinations of TrialSimulator building blocks. Each section
states what the combination achieves, then shows the mechanism in
code. Signatures and per-argument rules live in `building_blocks.md`;
the function catalog and gotchas in `helpers.md`. This file is about
**composition** — which blocks and which argument combinations, wired
together, implement which design. The current sections center on
adaptive designs; the file is open-ended and other themes will join.

Reading conventions:

- `<...>` marks a value the design must supply (a threshold, a name,
  a literal from a boundary run). Code containing `<...>` is a
  template, not runnable as-is.
- Lines marked `## PSEUDOCODE` compress statistical detail that the
  design must specify; everything else is real API, checked against
  TrialSimulator ≥ 1.38.
- Snippets show the milestone/action layer only. The surrounding
  skeleton — endpoints, arms, `trial()`, listener, controller — is
  the standard build order and is omitted unless the recipe changes
  it.
- A recipe adapted from a package vignette cites it; vignettes are
  worked references implementing one variant of a design, not the
  only one. The remaining recipes have no vignette counterpart; each
  carries a *Precedent* line citing the literature, an actual trial,
  or design software where the design is used — the block wiring is
  checked against the package API, while the statistical rules
  (zones, priors, bounds, scaling formulas) are defaults to confirm
  with the user. Citations are author–year–venue; verify before
  quoting them in a formal report.

**Contents**

- [1. Triggering-condition algebra](#sec:1-triggering-condition-algebra)
- [2. Action-function plumbing](#sec:2-action-function-plumbing)
- [3. Group sequential: efficacy interim + non-binding futility](#sec:3-group-sequential-efficacy-interim-non-binding-futility)
- [4. Simulating a *binding* early stop: collapse remaining milestones to now](#sec:4-simulating-a-binding-early-stop-collapse-remaining-milestones-to-now)
- [5. Promising zone: conditional power → event-number reassessment → retimed final](#sec:5-promising-zone-conditional-power-event-number-reassessment-retimed-final)
- [6. Over-/under-running: recompute the final boundary per replicate](#sec:6-over-under-running-recompute-the-final-boundary-per-replicate)
- [7. Bayesian predictive probability interim (go / no-go / expand)](#sec:7-bayesian-predictive-probability-interim-go-no-go-expand)
- [8. Extending a trial when information accrues slower than planned](#sec:8-extending-a-trial-when-information-accrues-slower-than-planned)
- [9. Re-anchoring planned looks when reality drifts (trigger-type switch)](#sec:9-re-anchoring-planned-looks-when-reality-drifts-trigger-type-switch)
- [10. Information-based timing from the wrappers' `info` column](#sec:10-information-based-timing-from-the-wrappers-info-column)
- [11. Blinded sample size re-estimation (nuisance-parameter SSR)](#sec:11-blinded-sample-size-re-estimation-nuisance-parameter-ssr)
- [12. Dose selection (drop-the-loser) with follow-up options](#sec:12-dose-selection-drop-the-loser-with-follow-up-options)
- [13. MAMS: selection at more than one stage, boundaries calibrated by simulation](#sec:13-mams-selection-at-more-than-one-stage-boundaries-calibrated-by-simulation)
- [14. Seamless phase 2/3: combination test across stages](#sec:14-seamless-phase-2-3-combination-test-across-stages)
- [15. Response-adaptive randomization](#sec:15-response-adaptive-randomization)
- [16. Independent cohorts: freeze follow-up at a cohort boundary](#sec:16-independent-cohorts-freeze-follow-up-at-a-cohort-boundary)
- [17. Basket pruning](#sec:17-basket-pruning)
- [18. Adding arms mid-trial (dose-ranging expansion, platform entry)](#sec:18-adding-arms-mid-trial-dose-ranging-expansion-platform-entry)
- [19. Adaptive enrichment (population selection) — capstone composition](#sec:19-adaptive-enrichment-population-selection-capstone-composition)
- [20. Crossover opened by an interim result](#sec:20-crossover-opened-by-an-interim-result)
- [21. Accrual adaptations at a milestone](#sec:21-accrual-adaptations-at-a-milestone)
- [22. Continuous safety surveillance with accrual pauses](#sec:22-continuous-safety-surveillance-with-accrual-pauses)
- [Vignette index for cited recipes](#sec:vignette-index-for-cited-recipes)

---

## 1. Triggering-condition algebra

`calendarTime()`, `enrollment()`, and `eventNumber()` take subset
conditions (`...`, `dplyr::filter` syntax), an `arms` restriction,
and combine with `|` / `&`. Most trial timelines are expressible in
one line. Reasonable combinations:

```r
## Information-driven analysis with an administrative backstop:
## whichever comes first ends the wait.
when = eventNumber(endpoint = "os", n = 300) | calendarTime(time = 48)

## "Not before" gate — delayed-effect (NPH) designs: an event-driven
## interim that control-arm events would otherwise trigger too early
## is held until follow-up is long enough for the effect to emerge
## (routine in immuno-oncology protocols: D events AND minimum follow-up).
when = eventNumber(endpoint = "os", n = 150) & calendarTime(time = 18)

## Analysis gated on TWO information streams: both must be met
## (final waits for the overall event target AND the stage-1
## cohort's own gate — keeps stage 1 before stage 2).
when = eventNumber(endpoint = "pfs", n = 240) &
       eventNumber(endpoint = "pfs", n = 65, patient_id <= 80)

## Subgroup-driven interim: count events in biomarker-positives only.
when = eventNumber(endpoint = "pfs", n = 100, biomarker == 1)

## Enrollment milestone with exposure requirement: fires when 500 are
## randomized AND each has >= 6 months on treatment — "analysis 6
## months after LPI".
when = enrollment(n = 500, min_treatment_duration = 6)

## Count on specific arms only (e.g., the confirmatory comparison,
## ignoring an exploratory arm).
when = eventNumber(endpoint = "os", n = 150, arms = c("placebo", "high dose"))

## Cohort boundary: an event-driven marker milestone (no analysis, or
## a stop_followup — see §16) splitting the trial into cohorts.
when = enrollment(n = 80)

## Safety/monitoring look at a fixed time, with a severity-count
## secondary trigger.
when = calendarTime(time = 12) | eventNumber(endpoint = "ae", n = 30, grade >= 3)
```

After a data-driven `remove_arms()`, the three `arms` counting
patterns (current arms via `NULL`, all design arms, runtime-dependent
subset via `update_milestone()`) are in `building_blocks.md`
§Triggering Conditions.

## 2. Action-function plumbing

Patterns for moving information between milestones and keeping
actions reusable. **Each block below is an independent pattern** —
they do not form one program.

**One action shared by several milestones** — per-milestone
configuration arrives through `milestone()`'s `...`:

```r
stage_action <- function(trial, milestone_name) {
  locked_data <- trial$get_locked_data(milestone_name = milestone_name)
  ## ... same analysis at every stage ...
}
m1 <- milestone(name = "stage 1", when = enrollment(n = 100),
                action = stage_action, milestone_name = "stage 1")
m2 <- milestone(name = "stage 2", when = enrollment(n = 200),
                action = stage_action, milestone_name = "stage 2")
```

**Scalar state across milestones** — save in the earlier milestone's
action, read in a later one's; the value also lands as a column in
`controller$get_output()` (audit trail):

```r
## inside the action of the earlier milestone
trial$save(value = p_interim, name = "p_interim")

## inside the action of a later milestone
p1 <- trial$get_output("p_interim")
```

**Read-only constants for every replicate** — design parameters,
boundary tables, template objects of testing procedures: register
once at setup, read in any action. Entries can never be modified;
R6 objects and data.tables are copied on every read, so a template
comes back as a fresh independent copy per replicate:

```r
tr <- trial(..., global_data = list(planned_D = 300, fwer = 0.025))

## inside any action
planned_D <- trial$get_global_data(name = "planned_D")
```

**Gate-and-skip** — a later action early-returns on a saved
decision. **Automatic NA-filling is a code-simplifying feature**: a
column saved in only some replicates is NA-filled when
`controller$run()` row-binds the replicate outputs (verified by
test), so a branched action saves only what its branch computes —
no defensive `trial$save(value = NA, ...)` bookkeeping across
branches (explicit NA saves, as some vignettes show, are harmless
but unnecessary):

```r
final_action <- function(trial, ...) {
  if (trial$get_output("decision") == "futility") {
    return(invisible(NULL))
  }
  ## ... full analysis, with trial$save() as usual ...
}
```

**Non-tabular state** (fitted model, list, data.frame) — custom data
is strictly replicate-local: every replicate starts empty, and
`get()` on a name not saved earlier in the same replicate is an
error (`NULL` cannot be stored). `overwrite = TRUE` is needed only
when a later milestone of the same replicate re-saves the name:

```r
## inside the action that fits the model
trial$save_custom_data(value = cox_fit, name = "cox_model")

## inside a later milestone's action
model <- trial$get(name = "cox_model")

## if the fit happens only in some branches, gate the read on a flag
## saved alongside it:
if (trial$get_output("model_fitted") == 1L) {
  model <- trial$get(name = "cox_model")
}
```

**Row-binding similar data.frames across milestones** (one per look),
retrieved once at the final analysis:

```r
## inside each look's action
trial$bind(value = data.frame(look = k, z = fit$z), name = "z_path")

## inside the final action
z_path <- trial$get(name = "z_path")
```

## 3. Group sequential: efficacy interim + non-binding futility

One interim with an efficacy boundary and a futility flag, then the
final analysis. Boundaries are computed once outside the simulation
(rpact/gsDesign; see SKILL.md "Testing and multiplicity") and
hardcoded. The simulation never stops the trial — decisions are saved
flags, composed into stopping-aware operating characteristics
afterwards.

```r
action_interim <- function(trial, ...) {
  data <- trial$get_locked_data(milestone_name = "interim")
  fit <- fitLogrank(Surv(os, os_event) ~ arm, placebo = "control",
                    data = data, alternative = "less")

  ## Efficacy: z vs hardcoded boundary (asOF, IF = 150/300, boundaries.R)
  trial$save(value = as.integer(fit$z <= -2.963), name = "reject_interim")

  ## Non-binding futility flag: crossing is recorded, nothing altered.
  trial$save(value = as.integer(fit$z > -0.5), name = "futile_interim")
}

action_final <- function(trial, ...) {
  data <- trial$get_locked_data(milestone_name = "final")
  fit <- fitLogrank(Surv(os, os_event) ~ arm, placebo = "control",
                    data = data, alternative = "less")
  trial$save(value = as.integer(fit$z <= -1.969), name = "reject_final")
}

m_interim <- milestone(name = "interim",
                       when = eventNumber(endpoint = "os", n = 150),
                       action = action_interim)
m_final   <- milestone(name = "final",
                       when = eventNumber(endpoint = "os", n = 300),
                       action = action_final)
```

```r
## Post-processing: one simulation scores several stopping policies.
out <- controller$get_output()

## Policy A — efficacy stopping only
power_A    <- mean(out$reject_interim | out$reject_final)
duration_A <- mean(ifelse(out$reject_interim == 1,
                          out$milestone_time_interim,
                          out$milestone_time_final))

## Policy B — efficacy + binding futility (same run, new composition)
power_B <- mean(out$reject_interim |
                (out$futile_interim == 0 & out$reject_final))

## Expected sample size under policy A: the enrolled count at each
## milestone is auto-saved (pattern n_events_<milestone>_<patient_id>,
## see helpers.md "Auto-saved milestone columns") — no manual save.
expN_A <- mean(ifelse(out$reject_interim == 1,
                      out$n_events_interim_patient_id,
                      out$n_events_final_patient_id))
```

Variations: futility on conditional power instead of z (compute
`trial$conditionalPower(...)$cp` in the interim action and flag
`cp < <threshold>`); two interims (two hardcoded boundaries, one more
milestone in chronological order); binary endpoint (swap in
`fitFarringtonManning`, `alternative = "greater"`).

## 4. Simulating a *binding* early stop: collapse remaining milestones to now

When the design truly stops (binding futility, failed gate), later
milestones must still fire — TrialSimulator runs every milestone. The
vignette-sanctioned trick: move every remaining milestone to the
current time; their actions see the saved decision and skip (§2
gate-and-skip). Auto-saved `milestone_time_*` columns then reflect
the *realized* stop time directly. (From the `enrichmentDesign`
vignette.)

```r
if (decision == "futility") {
  now <- trial$get_current_time()
  trial$update_milestone(name = "stage 1 analysis",
                         when = calendarTime(time = now))
  trial$update_milestone(name = "final",
                         when = calendarTime(time = now))
}
```

Milestones still trigger in registration order (both fire "at now",
in order), and the as-designed triggers are restored for the next
replicate. Use this when realized-time columns should reflect the
stop; use flag-composition (§3) when one run must score several
stopping policies.

## 5. Promising zone: conditional power → event-number reassessment → retimed final

At an interim, compute conditional power at the planned final event
count; in the promising zone, re-estimate the event target to recover
power and postpone the final analysis accordingly. Core of the
`conditionalPower` vignette (read it before using; it also derives
the statistics and discusses type I error).

```r
action_interim <- function(trial, ...) {
  planned_D <- 300; lower_cp <- 0.30; target_cp <- 0.90; D_cap <- 600

  ## CP at the planned final target. effect: 'trend' (interim
  ## estimate), a fixed hazard ratio (design assumption), or 'null'.
  ## alpha is the one-sided nominal level of the planned FINAL
  ## boundary, not the total design alpha.
  cp <- trial$conditionalPower(
    milestone = "interim", Surv(pfs, pfs_event) ~ arm,
    placebo = "pbo", alternative = "less",
    alpha = 0.022, D = planned_D, effect = 0.75)$cp

  selected_D <- planned_D
  if (cp >= lower_cp && cp < target_cp) {           # promising zone
    re <- trial$eventNumberReestimationFromConditionalPower(
      milestone = "interim", Surv(pfs, pfs_event) ~ arm,
      placebo = "pbo", alternative = "less",
      alpha = 0.022, target_cp = target_cp, effect = 0.75, D_cap = D_cap)
    ## Increase-only policy; cap as fallback when no solution in range.
    selected_D <- if (re$target_reached && re$D > planned_D) re$D else D_cap
  }

  if (selected_D > planned_D) {
    trial$update_milestone(
      name = "final",
      when = eventNumber(endpoint = "pfs", n = selected_D,
                         arms = c("pbo", "trt")))
  }

  trial$save(value = cp,         name = "cp_at_planned_D")
  trial$save(value = selected_D, name = "selected_final_D")
}
```

Parameter combinations worth knowing:

- `effect = 'trend'` scores the observed interim effect;
  `effect = <HR>` scores a fixed design assumption (converted
  internally using the allocation ratio); `'null'` gives the
  futility-style CP under H0 (not accepted by the re-estimation
  method).
- Subset conditions restrict both methods to a cohort or subgroup:
  `trial$conditionalPower(..., patient_id <= 80 & biomarker == 1)`.
- Pair with `trial$resize()` when more events require more patients
  (§19 does both).
- Design constants (`planned_D`, the zone bounds, `D_cap`) can be
  registered once via `trial(global_data = list(...))` and read with
  `trial$get_global_data()` (§2) instead of re-typing them in each
  action.

## 6. Over-/under-running: recompute the final boundary per replicate

The one sanctioned per-replicate boundary computation (SKILL.md
"Computing boundaries"): the protocol prescribes recomputing the
final critical value from the information actually observed at the
final data lock, keeping the alpha already spent at the interim. The
interim boundary stays a precomputed literal.

*Precedent:* over- and under-running are treated in Whitehead (1992,
Controlled Clinical Trials) and Jennison & Turnbull (2000, ch. 7);
recomputing the final boundary from realized information via error
spending is standard practice, implemented by EAST and rpact.

```r
action_interim <- function(trial, ...) {
  data <- trial$get_locked_data(milestone_name = "interim")
  fit <- fitLogrank(Surv(os, os_event) ~ arm, placebo = "control",
                    data = data, alternative = "less")
  trial$save(value = as.integer(fit$z <= -2.963), name = "reject_interim")
  trial$save(value = sum(data$os_event),          name = "d_interim")
}

action_final <- function(trial, ...) {
  data  <- trial$get_locked_data(milestone_name = "final")
  d1    <- trial$get_output("d_interim")
  d2    <- sum(data$os_event)      # observed final events (over/under-run)

  ## Final boundary at realized information, holding the interim
  ## spend fixed: alpha actually spent at the interim is a literal
  ## from boundaries.R (asOF at the PLANNED interim fraction).
  design <- rpact::getDesignGroupSequential(
    kMax = 2, alpha = 0.025, sided = 1,
    typeOfDesign = "asUser",
    userAlphaSpending = c(0.0015, 0.025),       # <- literals from boundaries.R
    informationRates  = c(d1 / d2, 1))
  c_final <- design$criticalValues[2]

  fit <- fitLogrank(Surv(os, os_event) ~ arm, placebo = "control",
                    data = data, alternative = "less")
  trial$save(value = as.integer(fit$z <= -c_final), name = "reject_final")
  trial$save(value = c_final,                       name = "final_boundary")
}
```

Accept the per-replicate rpact cost at the final milestone only;
never inside interim actions whose information fraction is fixed by
design.

## 7. Bayesian predictive probability interim (go / no-go / expand)

Binary endpoint, conjugate Beta model: at an interim, the posterior
predictive probability of success at the planned final analysis
drives a three-zone decision — stop accrual investment when PPoS is
hopeless, expand when it is promising, continue when favorable.

*Precedent:* predictive-probability monitoring per Lee & Liu (2008,
Clinical Trials); I-SPY 2 graduates and drops regimens on Bayesian
predictive probability of phase-3 success (Barker et al. 2009, Clin
Pharmacol Ther); FACTS implements PPoS interim rules natively. Zones
and priors remain design choices.

```r
action_pp <- function(trial, ...) {
  data <- trial$get_locked_data(milestone_name = "pp interim")
  n_final <- 150                      # planned per-arm final size

  x_t <- sum(data$response[data$arm == "treatment"])
  n_t <- sum(data$arm == "treatment")
  x_c <- sum(data$response[data$arm == "control"])
  n_c <- sum(data$arm == "control")

  ## Posterior (Beta(0.5, 0.5) priors) -> predictive draws of the
  ## REMAINING patients -> final-analysis pooled z, vectorized.
  B   <- 5000                         # MC precision vs per-replicate cost
  p_t <- rbeta(B, 0.5 + x_t, 0.5 + n_t - x_t)
  p_c <- rbeta(B, 0.5 + x_c, 0.5 + n_c - x_c)
  y_t <- x_t + rbinom(B, n_final - n_t, p_t)
  y_c <- x_c + rbinom(B, n_final - n_c, p_c)
  ph_t <- y_t / n_final; ph_c <- y_c / n_final
  pbar <- (y_t + y_c) / (2 * n_final)
  z    <- (ph_t - ph_c) / sqrt(pbar * (1 - pbar) * 2 / n_final)
  ppos <- mean(z > qnorm(0.975))      # one-sided 0.025 final test

  zone <- if (ppos < 0.10) "no-go" else if (ppos < 0.60) "expand" else "go"
  if (zone == "expand") {
    trial$resize(n_patients = 2 * 200)              # expand to 200/arm
    trial$update_milestone(name = "final",
                           when = enrollment(n = 2 * 200,
                                             min_treatment_duration = <readout>))
  }
  ## "no-go": flag only (§3), or collapse remaining milestones (§4).

  trial$save(value = ppos, name = "ppos")
  trial$save(value = zone, name = "pp_zone")
}
```

The same skeleton scores any Bayesian monitoring rule: swap the
predictive quantity (posterior probability of superiority, predictive
probability of meeting a landmark) without touching the
milestone/adaptation wiring.

## 8. Extending a trial when information accrues slower than planned

Interim looks at *blinded* pooled information; if short, the final
analysis is postponed. Two variants differing in what happens to
follow-up (cf. "Extend a trial" in the `actionFunctions` vignette).

```r
## Variant A — simple re-timing: let follow-up continue, move the
## final analysis from its planned calendar time to an information
## target (or a later calendar time).
action_check <- function(trial, ...) {
  data <- trial$get_locked_data(milestone_name = "accrual check")
  pooled_events <- sum(data$os_event)          # blinded: no arm split
  if (pooled_events < <planned_events_at_check>) {
    trial$update_milestone(name = "final",
                           when = eventNumber(endpoint = "os", n = <D_final>))
    trial$save(value = 1L, name = "extended")
  } else {
    trial$save(value = 0L, name = "extended")
  }
}

## Variant B — extend the analysis date but FREEZE follow-up at the
## originally planned end, so patients enrolled by now keep exactly
## their planned exposure (the classical "extend without extending
## exposure" design):
planned_end <- <original final calendar time>   # known by design
trial$stop_followup(additional_followup = planned_end - trial$get_current_time())
trial$update_milestone(name = "final",
                       when = calendarTime(time = <new_end>))
```

## 9. Re-anchoring planned looks when reality drifts (trigger-type switch)

DSMB looks are often protocol-scheduled on the calendar, but their
*intent* is an information fraction. A cheap monitoring milestone
checks progress and rewrites the look's trigger — switching its type
entirely (`update_milestone` replaces the condition as a whole).

*Precedent:* calendar- versus information-time scheduling is Lan &
DeMets (1989, Statistics in Medicine); projecting when an event
target will be reached is the event-prediction problem (Bagiella &
Heitjan 2001, Statistics in Medicine; R package eventPred).

```r
## Design: interim planned at month 12, intended to be ~150 events.
action_monitor <- function(trial, ...) {
  data <- trial$get_locked_data(milestone_name = "progress check")
  e0   <- sum(data$os_event)

  if (e0 < <events expected by now>) {
    ## Behind plan: make the look event-driven so it fires at the
    ## intended information, whenever that happens...
    trial$update_milestone(name = "interim",
                           when = eventNumber(endpoint = "os", n = 150))
  } else if (e0 >= 150) {
    ## ...ahead of plan: hold the look until operations can support
    ## it (not before month 10), information already met.
    trial$update_milestone(name = "interim",
                           when = eventNumber(endpoint = "os", n = 150) &
                                  calendarTime(time = 10))
  }
  trial$save(value = e0, name = "events_at_check")
}

m_check   <- milestone(name = "progress check",
                       when = calendarTime(time = 6),
                       action = action_monitor)
m_interim <- milestone(name = "interim",
                       when = calendarTime(time = 12),     # as planned
                       action = action_interim)
```

Registration order still binds: the monitoring milestone must be
registered before the look it rewrites, and the new trigger must not
make the look fire before any earlier-registered milestone.

## 10. Information-based timing from the wrappers' `info` column

For non-TTE endpoints "information" is not an event count. Every
analysis wrapper returns an `info` column (observed statistical
information); comparing it with the design's target information turns
any look into an information-based one — the error-spending analogue
for continuous/binary endpoints.

*Precedent:* information-based monitoring with a fixed
maximum-information target and a floating sample size is Mehta &
Tsiatis (2001, Drug Information Journal), with a worked hypothetical
in the paper; EAST ships it as its information-based design module.

```r
action_info_check <- function(trial, ...) {
  data <- trial$get_locked_data(milestone_name = "info check")
  fit  <- fitLinear(chg ~ arm + baseline, placebo = "control",
                    data = data, alternative = "less")

  IF_obs <- fit$info / <I_planned>     # planned total information, from design
  if (IF_obs < <target IF at this look>) {
    ## Scale the final enrollment target by the information shortfall.
    n_now <- nrow(data)
    trial$update_milestone(
      name = "final",
      when = enrollment(n = ceiling(n_now * <target IF> / IF_obs),  ## PSEUDOCODE scaling
                        min_treatment_duration = <readout>))
  }
  trial$save(value = IF_obs, name = "observed_IF")
}
```

## 11. Blinded sample size re-estimation (nuisance-parameter SSR)

The classical Gould–Shih composition for a continuous endpoint: at an
interim, re-estimate the nuisance parameter (pooled SD) from blinded
data, recompute the sample size for the design's effect, and resize.
No unblinded look, no alpha penalty.

*Precedent:* Gould & Shih (1992, Communications in Statistics A);
Kieser & Friede (2003, Statistics in Medicine) show the type I error
is untouched; the FDA adaptive-designs guidance (2019) treats blinded
SSR as generally acceptable without alpha adjustment; nQuery and
rpact support it.

```r
action_ssr <- function(trial, ...) {
  data <- trial$get_locked_data(milestone_name = "ssr look")

  sd_pool <- sd(data$chg, na.rm = TRUE)   # blinded pooled SD
  ## n per arm for one-sided alpha = 0.025, power 0.9, effect delta:
  n_arm <- ceiling(2 * (qnorm(0.975) + qnorm(0.9))^2 * sd_pool^2 / <delta>^2)
  n_new <- max(2 * n_arm, <planned N>)     # increase-only policy

  if (n_new > <planned N>) {
    trial$resize(n_patients = n_new)
    trial$update_milestone(name = "final",
                           when = enrollment(n = n_new,
                                             min_treatment_duration = <readout>))
  }
  trial$save(value = sd_pool, name = "blinded_sd")
  trial$save(value = n_new,   name = "reassessed_n")
}

m_ssr <- milestone(name = "ssr look",
                   when = enrollment(n = <N/2>, min_treatment_duration = <readout>),
                   action = action_ssr)
```

Binary analogue: re-estimate the pooled response rate and plug it
into the proportion-test formula. Unblinded SSR on conditional power
is §5 — prefer the built-in re-estimation there.

## 12. Dose selection (drop-the-loser) with follow-up options

A surrogate-endpoint look selects the better dose; the loser stops
enrolling. `additional_followup` (mandatory, no default) states what
happens to the dropped arm's patients — a visible design decision.
(From the `adaptiveDesign` vignette, action 1.)

```r
action_select <- function(trial, ...) {
  data <- trial$get_locked_data(milestone_name = "dose selection")
  fit <- fitFarringtonManning(endpoint = "surrogate", placebo = "placebo",
                              data = data, alternative = "greater")
  z_l <- fit$z[fit$arm == "low dose"]
  z_h <- fit$z[fit$arm == "high dose"]

  if (z_l > 1.28) {
    trial$remove_arms(arms_name = "high dose", additional_followup = 0)
    trial$save(value = "low", name = "kept_arm")
  } else if (z_h > 1.28) {
    trial$remove_arms(arms_name = "low dose", additional_followup = 0)
    trial$save(value = "high", name = "kept_arm")
  } else {
    trial$save(value = "both", name = "kept_arm")  # no removal: guard your calls
  }
}
```

`additional_followup` combinations:

```r
trial$remove_arms(arms_name = "low dose", additional_followup = 0)    # censor at selection
trial$remove_arms(arms_name = "low dose", additional_followup = 12)   # 12 more months (OS/safety)
trial$remove_arms(arms_name = "low dose", additional_followup = Inf)  # follow to trial end
## Different follow-up per arm: one call per arm.
trial$remove_arms(arms_name = "mid dose", additional_followup = Inf)
```

Later milestones that must count the dropped dose's patients (e.g.
total enrollment of 1000 across all randomized) list every design arm
explicitly — see `building_blocks.md` §Triggering Conditions for the
three patterns, including rewriting a later condition from inside
this action via `update_milestone()` when the subset depends on which
arm was dropped.

## 13. MAMS: selection at more than one stage, boundaries calibrated by simulation

Multi-arm multi-stage: several treatments against one control, with
arms dropped at each stage and efficacy claimed at the end. The
selection boundaries (c1, c2, c_final) jointly control FWER; instead
of deriving them analytically, calibrate them by simulating under the
global null — a simulation-native workflow this package makes cheap.

*Precedent:* MRC STAMPEDE ran as a multi-arm multi-stage trial (Sydes
et al. 2009, Trials); generalized-Dunnett MAMS boundaries are Magirr,
Jaki & Whitehead (2012, Biometrika), implemented in the MAMS R
package (Jaki, Pallmann & Magirr 2019, J Stat Software). Establishing
type I error of a bespoke selection rule by simulation under the
global null is the workflow the FDA adaptive-designs guidance (2019)
expects when no analytic argument is available.

```r
action_stage <- function(trial, milestone_name, drop_bound) {
  data <- trial$get_locked_data(milestone_name = milestone_name)
  fit <- fitLogrank(Surv(pfs, pfs_event) ~ arm, placebo = "control",
                    data = data, alternative = "less")

  ## Drop every arm whose z fails the stage bound; -z so "better" is larger.
  losers <- fit$arm[-fit$z < drop_bound]
  ## Keep the trial two-armed at worst: never drop the current best.
  losers <- setdiff(losers, fit$arm[which.max(-fit$z)])
  if (length(losers) > 0) {
    trial$remove_arms(arms_name = losers, additional_followup = 0)
  }
  trial$save(value = paste(losers, collapse = ";"),
             name = paste0("dropped_at_", gsub(" ", "_", milestone_name)))
}

action_final <- function(trial, ...) {
  data <- trial$get_locked_data(milestone_name = "final")
  fit <- fitLogrank(Surv(pfs, pfs_event) ~ arm, placebo = "control",
                    data = data, alternative = "less")
  ## One row per surviving arm; c_final from the calibration run below.
  trial$save(value = as.integer(any(fit$z <= -<c_final>)), name = "reject_any")
  trial$save(value = max(-fit$z),                          name = "max_z_final")
}

m1 <- milestone(name = "stage 1", when = eventNumber(endpoint = "pfs", n = 120),
                action = action_stage, milestone_name = "stage 1", drop_bound = 0)
m2 <- milestone(name = "stage 2", when = eventNumber(endpoint = "pfs", n = 240),
                action = action_stage, milestone_name = "stage 2", drop_bound = 0.8)
m3 <- milestone(name = "final",   when = eventNumber(endpoint = "pfs", n = 360),
                action = action_final)
```

```r
## Calibration: run the SAME design under the global null (all arms'
## generators equal control), save max_z_final, and choose c_final as
## the empirical FWER quantile. Hardcode the literal back into
## action_final, then run the alternative scenarios.
out0    <- controller$get_output()               # global-null run, n = 10000+
c_final <- quantile(out0$max_z_final, probs = 1 - 0.025)
```

The `arms = NULL` default makes every stage's event target count the
surviving arms automatically; list all design arms instead if the
protocol counts dropped arms' events (§12).

## 14. Seamless phase 2/3: combination test across stages

After dose selection (§12), the confirmatory test combines stage-wise
evidence with Dunnett's test over the closed family; PFS and OS each
get a share of alpha with their own group-sequential spending. (From
the `adaptiveDesign` vignette, action 3 — read it before building
this; the milestones vectors and `planned_info` are easiest from the
worked example.)

```r
action_final <- function(trial, ...) {
  ## PFS tested at interim + final, alpha share 0.005, asOF spending
  dt_pfs <- trial$dunnettTest(Surv(pfs, pfs_event) ~ arm, placebo = "placebo",
                              treatments = c("high dose", "low dose"),
                              milestones = c("dose selection", "interim", "final"),
                              alternative = "less", planned_info = "default")
  ct_pfs <- trial$closedTest(dt_pfs, treatments = c("high dose", "low dose"),
                             milestones = c("interim", "final"),
                             alpha = 0.005, alpha_spending = "asOF")

  ## OS tested at final only, alpha share 0.02
  dt_os <- trial$dunnettTest(Surv(os, os_event) ~ arm, placebo = "placebo",
                             treatments = c("high dose", "low dose"),
                             milestones = c("dose selection", "final"),
                             alternative = "less", planned_info = "default")
  ct_os <- trial$closedTest(dt_os, treatments = c("high dose", "low dose"),
                            milestones = "final",
                            alpha = 0.02, alpha_spending = "asOF")

  trial$save(value = ct_pfs$decision[ct_pfs$arm == "high dose"],
             name = "pfs_high_decision")
  trial$save(value = ct_os$decision[ct_os$arm == "high dose"],
             name = "os_high_decision")
}
```

Note the composition with §12: `dunnettTest` automatically stops
testing an arm removed before a listed milestone; the `milestones`
vector names the data locks whose increments enter the combination.

## 15. Response-adaptive randomization

Repeated looks re-weight allocation toward better-performing doses;
one shared action (§2 pattern) serves every look. (From the
`responseAdaptive` vignette.)

```r
stage_action <- function(trial, milestone_name) {
  data <- trial$get_locked_data(milestone_name = milestone_name)

  ## PSEUDOCODE: any allocation rule — posterior probabilities,
  ## RSIHR, play-the-winner — mapping observed data to weights,
  ## usually keeping a fixed floor on the control share.
  new_ratio <- <allocation rule>(data)       # e.g. c(0.2, rest proportional)

  trial$update_sample_ratio(
    arm_names     = c("0.0", "20.0", "25.0", "30.0", "35.0"),
    sample_ratios = new_ratio)
  trial$save(value = paste(round(new_ratio, 2), collapse = "/"),
             name = paste0("ratio_after_", milestone_name))
}

looks <- lapply(c(100, 200, 300), function(n)
  milestone(name = paste0("look_", n), when = enrollment(n = n),
            action = stage_action, milestone_name = paste0("look_", n)))
```

Fractional ratios are allowed (without stratification factors; a
warning otherwise). Combine with `remove_arms()` for drop-the-loser
RAR hybrids.

## 16. Independent cohorts: freeze follow-up at a cohort boundary

Combination tests need independent stage statistics. Freezing the
earlier cohort's follow-up at (or a fixed time after) an event-driven
boundary milestone makes later data-lock increments independent of
the cohort's statistic.

```r
## At the stage-1 analysis milestone: stop following the stage-1 cohort.
trial$stop_followup(patient_id <= 80, additional_followup = 0)

## Variants:
trial$stop_followup(patient_id <= 80, additional_followup = 6)   # fixed 6-month tail
trial$stop_followup(additional_followup = 0)                     # everyone enrolled so far
trial$stop_followup(biomarker == 0, additional_followup = 3)     # de-selected subgroup,
                                                                 # 3-month follow-up tail
```

Selected patients' TTE endpoints are censored at the stopping time
and non-TTE readouts beyond it are set missing; patients enrolled
later are unaffected.

## 17. Basket pruning

One trial, K indication baskets as arms, each compared with the same
historical control rate p0 (no concurrent control). An interim prunes
hopeless baskets; the final analysis reports per-basket decisions.
The pruning statistic below is a plain per-basket posterior — replace
it with hierarchical borrowing (BHM/EXNEX) without touching the
wiring.

*Precedent:* the vemurafenib basket study pruned cohorts at interim
futility looks (Hyman et al. 2015, NEJM); Bayesian hierarchical
borrowing across baskets is Berry et al. (2013, Clinical Trials),
robustified as EXNEX (Neuenschwander et al. 2016, Pharmaceutical
Statistics); the R packages `basket` / `bhmbasket` and FACTS
implement these designs.

```r
action_prune <- function(trial, ...) {
  data <- trial$get_locked_data(milestone_name = "prune")
  baskets <- trial$get_arms_name()

  post_go <- vapply(baskets, function(b) {
    x <- sum(data$response[data$arm == b]); n <- sum(data$arm == b)
    1 - pbeta(<p0>, 0.5 + x, 0.5 + n - x)   # P(p_b > p0 | data)
    ## PSEUDOCODE: swap in BHM/EXNEX borrowing across baskets here
  }, numeric(1))

  drop <- baskets[post_go < 0.10]
  drop <- setdiff(drop, baskets[which.max(post_go)])  # keep at least one
  if (length(drop) > 0) {
    trial$remove_arms(arms_name = drop, additional_followup = 0)
  }
  trial$save(value = paste(drop, collapse = ";"), name = "pruned_baskets")
}

## Final: per-basket posterior with a success bound calibrated under
## the null (same calibration workflow as §13).
```

`arms = NULL` in later triggering conditions tracks the surviving
baskets automatically; `trial$get_arms_name()` keeps the action
agnostic to how many baskets remain.

## 18. Adding arms mid-trial (dose-ranging expansion, platform entry)

`endpoint()` / `arm()` are not setup-only: construct the new arm
inside the action, then `trial$add_arms()`. Registration is
transactional and a removed arm's name cannot be reused. (From the
`doseRanging` vignette: a two-arm stage expands to five arms after a
positive signal.)

```r
action_expand <- function(trial, ...) {
  data <- trial$get_locked_data(milestone_name = "interim")
  fit <- fitLogistic(ep ~ arm, placebo = "dose = 0.0", data = data,
                     alternative = "greater", scale = "risk difference")
  trial$save(value = ifelse(fit$z > 1.64, "add dose arms", "stop trial"),
             name = "interim_decision")

  ## Build the new arms here — generators carry each dose's assumption.
  ep1 <- endpoint(name = "ep", type = "non-tte", readout = c(ep = 1),
                  generator = rbinom, size = 1, prob = 0.112)
  trt1 <- arm(name = "dose = 0.5"); trt1$add_endpoints(ep1)
  ep2 <- endpoint(name = "ep", type = "non-tte", readout = c(ep = 1),
                  generator = rbinom, size = 1, prob = 0.208)
  trt2 <- arm(name = "dose = 1.5"); trt2$add_endpoints(ep2)

  ## New arms enter the randomization from now on, at the given
  ## weights relative to the existing arms' current ratios.
  trial$add_arms(sample_ratio = c(2, 2), trt1, trt2)
}
```

Platform variation: one `add_arms` action per `calendarTime()`
milestone models staggered entry of new treatments; pair each with a
later `remove_arms()` when its comparison matures (§12), and restrict
each comparison to concurrent controls with a subset condition on a
saved baseline enrollment variable
(`fitLogrank(..., enroll_time >= <arm entry time>)`).

## 19. Adaptive enrichment (population selection) — capstone composition

A biomarker subgroup may carry the effect. At the interim,
conditional power for the full population and the subgroup drives a
five-zone decision; enrichment restricts future enrollment to
biomarker-positive patients. One action composes six adaptation
methods. (From the `enrichmentDesign` vignette — one variant of a
flexible design family; stages, zones, combination and intersection
tests are design choices. Read it with the `conditionalPower`
vignette.)

```r
interim_action <- function(trial, ...) {
  data <- trial$get_locked_data(milestone_name = "interim")

  cp_full <- trial$conditionalPower(
    milestone = "interim", Surv(pfs, pfs_event) ~ arm, placebo = "pbo",
    alternative = "less", alpha = 0.025, D = 240, effect = "trend",
    patient_id <= 80)$cp
  cp_sub <- trial$conditionalPower(
    milestone = "interim", Surv(pfs, pfs_event) ~ arm, placebo = "pbo",
    alternative = "less", alpha = 0.025, D = 150, effect = "trend",
    patient_id <= 80 & biomarker == 1)$cp

  decision <- if (cp_full < .01 && cp_sub < .01) "futility"
    else if (cp_full < .2 && cp_sub < .6)        "unfavorable"
    else if (cp_full < .2)                       "enrichment"
    else if (cp_full < .9)                       "promising"
    else                                         "favorable"

  if (decision == "futility") {
    now <- trial$get_current_time()                      # §4: stop now
    trial$update_milestone(name = "stage 1 analysis",
                           when = calendarTime(time = now))
    trial$update_milestone(name = "final", when = calendarTime(time = now))

  } else if (decision == "enrichment") {
    re <- trial$eventNumberReestimationFromConditionalPower(
      milestone = "interim", Surv(pfs, pfs_event) ~ arm, placebo = "pbo",
      alternative = "less", alpha = 0.025, target_cp = 0.95,
      effect = "trend", patient_id <= 80 & biomarker == 1, D_cap = 200)

    trial$resize(n_patients = <enrolled + remaining subgroup budget>)
    trial$update_accrual_rate(                    # screening slows down
      accrual_rate = data.frame(end_time = Inf, piecewise_rate = 5))
    ## Future patients are biomarker-positive only: same joint
    ## generator, prevalence pushed to 1. Enrolled patients untouched.
    trial$update_generator(arm_name = "pbo",
                           endpoint_name = c("pfs", "biomarker"),
                           generator = rng, median0 = 6, median1 = 6,
                           prevalence = 1.0)
    trial$update_generator(arm_name = "trt",
                           endpoint_name = c("pfs", "biomarker"),
                           generator = rng, median0 = 6.5, median1 = 10,
                           prevalence = 1.0)
    trial$update_milestone(                        # §1: & keeps stage order
      name = "final",
      when = eventNumber(endpoint = "pfs",
                         n = max(ifelse(re$target_reached, re$D, 200), 50),
                         biomarker == 1) &
             eventNumber(endpoint = "pfs", n = 65, patient_id <= 80))

  } else if (decision == "promising") {            # §5 inside the zone
    re <- trial$eventNumberReestimationFromConditionalPower(
      milestone = "interim", Surv(pfs, pfs_event) ~ arm, placebo = "pbo",
      alternative = "less", alpha = 0.025, target_cp = 0.95,
      effect = "trend", patient_id <= 80, D_cap = 400)
    trial$resize(n_patients = 480)
    trial$update_milestone(
      name = "final",
      when = eventNumber(endpoint = "pfs",
                         n = ifelse(re$target_reached, re$D, 400)) &
             eventNumber(endpoint = "pfs", n = 65, patient_id <= 80))
  }
  ## "unfavorable" and "favorable": no adaptation.

  trial$save(value = decision, name = "decision")
  trial$save(value = cp_full,  name = "cp_full")
  trial$save(value = cp_sub,   name = "cp_subgroup")
}
```

Downstream, stage 1 freezes its cohort for independence (§16), each
stage's p-values come from subset-filtered wrappers
(`fitLogrank(..., patient_id > 80 & biomarker == 1)`), and the final
action combines stages by the inverse normal method with a closed
Simes test — a few lines of arithmetic on values passed via
`trial$save()` / `trial$get_output()` (§2). Full program in the
vignette.

Partial-enrichment variation: `prevalence = 0.8` instead of `1.0`
keeps a trickle of biomarker-negative patients — enrich while
preserving some full-population information.

## 20. Crossover opened by an interim result

An efficacy signal at the interim opens crossover for control
patients still on study; OS is analyzed with switching contamination.
Must follow the `crossoverAtMilestone` vignette (one of the three
switching designs — see SKILL.md "Crossover and treatment switching"
for which vignette matches which design).

```r
action_interim <- function(trial, ...) {
  data <- trial$get_locked_data(milestone_name = "interim")
  fit <- fitLogrank(Surv(pfs, pfs_event) ~ arm, placebo = "control",
                    data = data, alternative = "less")

  if (fit$z <= <efficacy boundary>) {
    ## who switches: control patients still at risk at the opening time
    what_fn <- function(patient_data) {
      sw <- subset(patient_data, arm == "control")   ## PSEUDOCODE: + at-risk guard
      data.frame(patient_id = sw$patient_id, new_treatment = "experimental")
    }
    ## how outcomes change after the switch: post-switch values only
    how_fn <- function(patient_data) {
      ## PSEUDOCODE: e.g. residual OS drawn under the experimental hazard
      data.frame(patient_id = <switchers>, os = <updated>, os_event = <updated>)
    }
    ## opening time = milestone time + delay (delay = 2: implementation lag)
    trial$crossover(what = what_fn, how = how_fn, delay = 0)
    trial$save(value = 1L, name = "crossover_opened")
  } else {
    trial$save(value = 0L, name = "crossover_opened")
  }
}
```

Locked data afterwards carries `n_switches` and `regimen_trajectory`
(expand with `expandRegimen()`) for switch-rate operating
characteristics — see `helpers.md` §Action-function utilities.

## 21. Accrual adaptations at a milestone

`update_accrual_rate()` replaces the remaining recruitment curve;
`end_time` is measured **from the milestone** ("from now on"), and a
leading `piecewise_rate = 0` window is a pause. Pre-planned pauses
belong in `trial()`'s `accrual_rate` instead (`helpers.md`
§Enroller).

```r
## Pause 3 months for a safety review, then resume at the old rate.
trial$update_accrual_rate(
  accrual_rate = data.frame(end_time = c(3, Inf), piecewise_rate = c(0, 30)))

## Slow to a trickle after enrichment (screening for biomarker+ only).
trial$update_accrual_rate(
  accrual_rate = data.frame(end_time = Inf, piecewise_rate = 5))

## Accelerate after a positive interim: add sites, ramp over 6 months.
trial$update_accrual_rate(
  accrual_rate = data.frame(end_time = c(6, Inf), piecewise_rate = c(30, 60)))
```

Composes naturally with `resize()` (more patients to recruit) and
`update_milestone()` (re-timed analyses under the new curve).

## 22. Continuous safety surveillance with accrual pauses

A ladder of enrollment-driven looks shares one action (§2); each look
tests whether the pooled severe-AE rate exceeds a tolerance, with a
one-sided exact lower bound so early looks don't trip on noise.
Breaching pauses accrual (§21) and raises a flag the report composes
into "probability of at least one safety pause". Requires an `ae` /
severity endpoint in the generators.

*Precedent:* continuous toxicity-monitoring boundaries are Ivanova,
Qaqish & Schell (2005, Biometrics); staggered enrolment with
pause-and-review criteria is mandated by the EMA first-in-human
guideline (2017 revision) and routine in DSMB charters.

```r
safety_action <- function(trial, milestone_name) {
  data <- trial$get_locked_data(milestone_name = milestone_name)
  x <- sum(data$grade3plus); n <- nrow(data)

  ## One-sided 95% exact (Clopper-Pearson) lower bound on the AE rate.
  lb <- if (x == 0) 0 else qbeta(0.05, x, n - x + 1)

  if (lb > <tolerable rate>) {
    trial$update_accrual_rate(   # 3-month enrollment hold, then resume
      accrual_rate = data.frame(end_time = c(3, Inf),
                                piecewise_rate = c(0, <resume rate>)))
    trial$save(value = 1L, name = paste0("pause_at_", milestone_name))
  } else {
    trial$save(value = 0L, name = paste0("pause_at_", milestone_name))
  }
}

safety_looks <- lapply(c(50, 100, 200), function(n)
  milestone(name = paste0("safety_", n), when = enrollment(n = n),
            action = safety_action, milestone_name = paste0("safety_", n)))
```

```r
## OC: probability of >= 1 pause, and its cost in trial duration.
out <- controller$get_output()
mean(out$pause_at_safety_50 | out$pause_at_safety_100 | out$pause_at_safety_200)
```

---

## Vignette index for cited recipes

| Recipe | Vignette |
|---|---|
| §4, §19, §16 | https://zhangh12.github.io/TrialSimulator/articles/enrichmentDesign.html |
| §5 | https://zhangh12.github.io/TrialSimulator/articles/conditionalPower.html |
| §12, §14 | https://zhangh12.github.io/TrialSimulator/articles/adaptiveDesign.html |
| §15 | https://zhangh12.github.io/TrialSimulator/articles/responseAdaptive.html |
| §18 | https://zhangh12.github.io/TrialSimulator/articles/doseRanging.html |
| §20 | https://zhangh12.github.io/TrialSimulator/articles/crossoverAtMilestone.html |
| adaptation overview | https://zhangh12.github.io/TrialSimulator/articles/actionFunctions.html |

§6, §7, §9, §10, §11, §13, §17, §22 have no vignette counterpart;
each cites the literature, trial, or software precedent for its
design inline (*Precedent* lines).
