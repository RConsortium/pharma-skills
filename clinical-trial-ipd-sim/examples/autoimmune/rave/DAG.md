# RAVE Causal-DAG Simulator — Model Specification

Trial: **RAVE — Rituximab for ANCA-Associated Vasculitis** (ITN021AI / **NCT00104299**; Stone et al.,
*NEJM* 2010;363:221–232). This document maps every node in the simulator to its DAG parents and the
structural equation that generates it, following the g-formula layered structure
**L₀ → A → Lₜ → … → Yₜ**, with a fixed latent frailty vector shared across the patient's trajectory.

**Source & Evidence columns** follow the skill's Citation format. Each **Source** carries an origin tag:
- `ctgov: <field>` — a value read from the NCT00104299 ClinicalTrials.gov record (design / baseline / results).
- `paperclip: <PMC> <url>` — a literature record (verbatim quote in the Evidence column).
- `model: <kind>` — a modeling / calibration choice with no external source (flagged; a knob for Step 6).

The DAG *structure* (which node depends on which) is fixed; only the parameters in
[`rave_params.R`](rave_params.R) are tunable by the calibration loop (Step 6). The date/traceability behavior
(#182 AE onset, #183 visit + discontinuation jitter, #184 AE↔DS traceability) is **inherited from the
shared engine** [`R/ TrialSim`](../../../R/trial_sim.R) — the trial code calls
`sim.between` / `sim.clamp_actual_day` / `sim.reconcile_ae_ds`; the recorded-date jitter uses an
independent per-patient RNG, so it never perturbs the main draw order.

Node/parent/equation content is read directly from the code:
[`dag_state.R`](dag_state.R), [`rave_baseline.R`](rave_baseline.R),
[`rave_longitudinal.R`](rave_longitudinal.R), [`rave_outcomes.R`](rave_outcomes.R),
with parameter values + provenance in [`rave_params.R`](rave_params.R).

## Trial design (context for the arm edge)

| Item | Value | Source | Evidence |
|---|---|---|---|
| Arms | Rituximab 375 mg/m² weekly ×4 vs daily oral cyclophosphamide 2 mg/kg; both + glucocorticoid taper; control switches CYC→AZA at months 3–6 | `ctgov: protocolSection/armsInterventionsModule` | "rituximab (375 mg/m2, four weekly infusions) and glucocorticoids in the induction of complete remission… The control arm will receive CYC (2 mg/kg, with doses modified for renal dysfunction)… The control arm will switch from daily CYC to AZA (2 mg/kg/day)." |
| Randomization | 1:1 | `ctgov: designModule` | "randomized in a 1:1 ratio to the experimental arm or the control arm" |
| Primary endpoint | BVAS/WG = 0 AND off glucocorticoids at 6 months | `ctgov: outcomesModule` | "The percentage of participants who have a BVAS/WG of 0 and have successfully completed the glucocorticoid taper at 6 months after randomization." |
| Eligibility (ANCA / diagnosis) | PR3- or MPO-ANCA positive; WG(GPA) or MPA | `ctgov: eligibilityModule` | "They must be positive for either PR3-ANCA or MPO-ANCA at the screening"; "diagnosed with WG or MPA according to the definitions of the Chapel Hill Consensus Conference" |
| Eligibility (labs) | WBC ≥ 4,000/mm³; platelets ≥ 120,000/mm³ | `ctgov: eligibilityModule` | "a white blood cell count that is less than 4,000/mm3" / "a platelet count that is less than 120,000/mm3" (exclusion) |

## Layer 0 — Baseline (L₀)

Generated in [`rave_baseline.R:make_baseline`](rave_baseline.R). Topological order:
demographics → disease type (GPA/MPA, PR3/MPO, new/relapsing) → renal involvement → disease activity →
comorbidities → frailties → baseline labs → arm → latent remission propensity.

| Node | Parents | Structural equation | Source | Evidence |
|---|---|---|---|---|
| `site` | ∅ | `Uniform({SITE001…SITE030})` | `model: make_baseline` | Multicenter (US + NL); synthetic site labels |
| `country` | ∅ | `Bern(USA = 0.92)` else NLD | `ctgov: baselineCharacteristicsModule (region)` | 181/197 US participants |
| `race` | ∅ | `Cat(WHITE 0.85; else BLACK/ASIAN/OTHER)` | `model: make_baseline` | Predominantly white AAV population (assumption) |
| `sex` | ∅ | `Bern(F = 0.492)` | `ctgov: baselineCharacteristicsModule` | 97/197 female |
| `age` | ∅ | `Normal(52.8, 15.5²)` truncated [15, 90] | `ctgov: baselineCharacteristicsModule ("Age, Continuous")` | mean 52.8 (SD 15.5) |
| `weight_kg` | `sex` | `Normal(80 if M else 68, 16²)` truncated [40, 140] | `model: make_baseline` | Adult weight prior (assumption) |
| `diagnosis_type` | ∅ | `Bern(GPA = 0.75)` else MPA | `ctgov: protocolSection (WG/GPA vs MPA)` | ~75% GPA in RAVE (MPA capped at 50% by protocol) |
| `anca_type` | ∅ | `Bern(PR3 = 0.66)` else MPO | `ctgov: designModule (stratification factor)` | ANCA type ~2:1 PR3:MPO; a randomization stratifier |
| `new_diagnosis` | ∅ | `Bern(0.50)` | `ctgov: designModule (stratification factor)` | new vs relapsing stratifier |
| `renal_involvement` | `anca_type`, `diagnosis_type` | `Bern(σ(−0.2 + 0.5·1{MPO} + 0.4·1{MPA}))` | `model: make_baseline` | MPO/MPA more renal-predominant (assumption) |
| `baseline_bvaswg` | ∅ | `Normal(8.0, 3.1²)` truncated [3, 30] | `ctgov: baselineCharacteristicsModule` | baseline BVAS/WG ~8 |
| `baseline_vdi` | ∅ | `Normal(1.2, 1.7²)` truncated [0, 8] | `model: make_baseline` | low baseline damage index (assumption) |
| `htn` | `age` | `Bern(σ(−2.5 + 0.05·(age−60)))` | `model: make_baseline` | HTN prevalence rises with age (assumption) |
| `dm` | `age` | `Bern(σ(−2.8 + 0.04·(age−60)))` | `model: make_baseline` | DM prevalence rises with age (assumption) |
| `f_heme, f_infect, f_GI, f_relapse, f_steroid, f_dropout` | ∅ | iid `Normal(0, σ²)`, σ ∈ {0.5–0.8} | `model: dag_state.draw_frailties` | Latent susceptibilities; variances are calibration knobs |
| `baseline_wbc` | `f_heme` | `Normal(8.0, 2.2²) + 0.4·f_heme`, floor 4.0 | `ctgov: eligibilityModule (WBC ≥ 4000)` | WBC floor = eligibility cut |
| `baseline_anc` | `baseline_wbc` | `0.6·WBC + N(0, 0.8²)` truncated [1.5, 10] | `model: make_baseline` | ANC ≈ 0.6×WBC (assumption) |
| `baseline_hgb` | `sex`, `renal`, `f_heme` | `Normal(13.5 M/12.3 F, 1.3²) − 0.8·1{renal} + 0.3·f_heme` | `model: make_baseline` | Sex/renal-adjusted Hgb (assumption) |
| `baseline_plt` | ∅ | `Normal(300, 80²)` truncated, floor 120 | `ctgov: eligibilityModule (PLT ≥ 120000)` | platelet floor = eligibility cut |
| `baseline_creat` | `renal`, `age` | `Normal(0.9 + 0.8·1{renal}, 0.3²) + 0.004·(age−55)` | `model: make_baseline` | Higher creatinine with renal involvement (assumption) |
| `baseline_bun` | `renal` | `Normal(15 + 12·1{renal}, 6²)` | `model: make_baseline` | Renal function proxy (assumption) |
| `baseline_crp` | `baseline_bvaswg` | `Normal(2.0 + 0.5·BVAS, 4²)` | `model: make_baseline` | Inflammatory marker tracks activity (assumption) |
| `baseline_esr` | `baseline_bvaswg` | `Normal(20 + 2.5·BVAS, 18²)` | `model: make_baseline` | Inflammatory marker tracks activity (assumption) |
| `remit_propensity` | `is_rtx`, `new_diagnosis`, `anca_type`, `baseline_bvaswg` | `logit = 0.62 + 0.46·rtx − 0.30·1{relapsing} − 0.10·1{PR3} − 0.05·(BVAS−8)` | `ctgov: resultsSection` (targets) | Calibrated to complete-remission rates RTX 63.6% vs CYC 53.1% |

## Layer A — Treatment

| Node | Parents | Structural equation | Source | Evidence |
|---|---|---|---|---|
| `is_rtx` (ARM) | ∅ | `Bern(0.5)` — randomized, exogenous | `ctgov: designModule` | "randomized in a 1:1 ratio" |

## Layer Lₜ — Time-varying state (per visit, propagated forward)

Generated in [`rave_longitudinal.R:simulate_trajectory(sim, …)`](rave_longitudinal.R) over the protocol
visit grid `SCHED` (screening, V1 baseline, weekly V2–V4, months 1/2/4/6/9/12/15/18). Each visit is
computed in this order. The **recorded** visit day is `sim.clamp_actual_day(...)` (nominal + jitter,
issue #183a); all logic below runs on the **nominal** day.

### Drug exposure indicators (deterministic)

| Node | Parents | Equation | Source | Evidence |
|---|---|---|---|---|
| `rtx_infusion[t]` | `is_rtx`, `visit` | `is_rtx ∧ visit ∈ {V1,V2,V3,V4}` (4 weekly infusions) | `ctgov: armsInterventionsModule` | "four weekly infusions" of rituximab |
| `cyc_active[t]` | `is_rtx`, `day` | `¬is_rtx ∧ 1 ≤ day ≤ 90` (oral CYC induction) | `ctgov: armsInterventionsModule` | daily oral CYC induction before AZA switch |
| `aza_active[t]` | `is_rtx`, `day` | `¬is_rtx ∧ day > 90` (AZA maintenance) | `ctgov: armsInterventionsModule` | "switch from daily CYC to AZA (2 mg/kg/day)" |
| `prednisone[t]` | `day`, `weight`, `cr6_latent` | ~1 mg/kg/day tapering to 0 by day 180 if heading to complete remission, else residual 7.5 mg | `ctgov: protocolSection` | "prednisone will be tapered so that by month 6 all participants in clinical remission will be off glucocorticoids" |

### Lab values (AR(1) with treatment drag + heme frailty)

| Node | Parents | Equation | Source | Evidence |
|---|---|---|---|---|
| `WBC[t]` | `WBC[t−1]`, `baseline_wbc`, `cyc_active`, `rtx_infusion/is_rtx`, `aza_active`, `f_heme` | `0.5·WBC[t−1] + 0.5·base − drag + N(0, 0.7²)`; `drag = 1.7 + 0.7·f_heme` (CYC), `0.6 + 0.4·f_heme` (RTX late), `0.6 + 0.3·f_heme` (AZA) | `paperclip: PMC5880843 https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5880843/` (CYC); `paperclip: PMC3539507 https://www.ncbi.nlm.nih.gov/pmc/articles/PMC3539507/` (RTX) | CYC: "During the first 12 months, neutropenia of ≤ 0.5 × 10⁹/L occurred in 9 (16%) PO and 0 (0%) IV cyclophosphamide patients (P = 0.003)." RTX: "Most studies reported an incidence [of rituximab-associated neutropenia] ranging from 0.02% to 6% … as high as 25%." |
| `ANC[t]` | `WBC[t]` | `0.6·WBC + N(0, 0.45²)` truncated | `model: simulate_trajectory` | ANC ≈ 0.6×WBC (assumption) |
| `HGB[t]` | `HGB[t−1]`, `baseline_hgb`, `cyc_active`, `f_heme` | `0.5·HGB[t−1] + 0.5·base − (0.5 + 0.2·f_heme)·1{cyc} + N(0, 0.5²)` | `model: _next` (CYC myelosuppression) | Oral-CYC marrow toxicity (same PMC5880843 basis) |
| `PLT[t]` | `PLT[t−1]`, `baseline_plt`, `cyc_active`, `rtx_infusion`, `f_heme` | `0.5·PLT[t−1] + 0.5·base − (18 + 8·f_heme)·1{cyc} − 10·1{rtx_inf} + N(0, 22²)` | `model: _next` | CYC/RTX thrombocytopenia (assumption; CYC per PMC5880843) |
| `CREAT[t]`, `BUN[t]` | prior, baseline, `in_remission` | `0.7·prev + 0.3·base − 0.10·1{remission} + noise` (renal improves as activity falls) | `model: simulate_trajectory` | Renal recovery with disease control (assumption) |
| `CRP[t]`, `ESR[t]` | prior, `bvaswg` | `0.5·prev + 0.5·(f(BVAS)) + noise` | `model: simulate_trajectory` | Inflammatory markers track BVAS/WG (assumption) |
| `hematuria[t]` | `bvaswg`, `renal_involvement` | `round((BVAS/4)·(1.5 if renal else 0.6) + N(0,0.3))` ∈ [0,3] | `model: simulate_trajectory` | Active renal vasculitis → hematuria (assumption) |

### BVAS/WG disease-activity + flare process

| Node | Parents | Equation | Source | Evidence |
|---|---|---|---|---|
| `cr6_latent` | `remit_propensity` | `Bern(σ(remit_propensity)) ∧ remit_ever(0.93)` | `ctgov: resultsSection` (targets) | Calibrated to CR-at-6mo RTX 63.6% / CYC 53.1% |
| `remission_day` | `remit_ever` | `clip(exp(Normal(log 45, 0.55²)), 8, 175)` | `model: params (remit_day_median)` | Median time-to-remission ~43–57 d (calibration target) |
| `bvaswg[t]` | `bvaswg[t−1]`, `baseline_bvaswg`, `remission_day`, `day` | Linear decline to 0 by `remission_day` if remitting; else plateau at `0.45·baseline`; `=0` once in remission | `ctgov: outcomesModule` | BVAS/WG = 0 defines remission |
| `flare[t]` | `is_rtx`, `anca_type`, `new_diagnosis`, `prednisone`, `f_relapse`, `in_remission`, `day` | `Bern(min(0.6, exp(log 0.045 − 0.20·rtx + 0.62·1{PR3} + 0.35·1{relapsing} − 0.020·pred + 1.0·f_relapse)))`, post-6mo only | `paperclip: PMC8407598 https://www.ncbi.nlm.nih.gov/pmc/articles/PMC8407598/`; `paperclip: PMC4520074 https://www.ncbi.nlm.nih.gov/pmc/articles/PMC4520074/` | "anti-PR3 ANCA positivity [HR 1.69 (95% CI 1.46, 1.94)]" for relapse; "the relapse rate in MPO-ANCA positive cases was lower than that of PR3-ANCA positive cases (17 % and 56 %, respectively)." |
| `vdi[t]` | `vdi[t−1]`, `flare` | `+1` on a severe flare w.p. 0.4 (monotone non-decreasing damage) | `model: simulate_trajectory` | Damage accrues, never reverses (assumption) |

### Adverse events

Lab AEs are the CTCAE grade of the lab value (deterministic grade, stochastic reporting), onset on the
(jittered) blood-draw day. Symptomatic AEs draw onset **between visits** via `sim.between(...)` (#182).

| Node | Parents | Equation | Source | Evidence |
|---|---|---|---|---|
| `Leukopenia / Neutropenia / Anaemia / Thrombocytopenia [t]` | `WBC/ANC/HGB/PLT[t]`, `cyc_active`, `aza_active` | Grade = CTCAE(lab); reported w.p. `{1:.20–.25, 2:.55–.85, 3:.95–.97, 4:1.0}`; serious only at Gr 4 | `ctgov: resultsSection (AE table)` | Leukopenia any-grade RTX 13.1% vs CYC 39.8% (CYC arm drives the myelosuppression signal) |
| `Infection[t]` | `is_rtx`, `cyc/aza_active`, `prednisone`, `f_infect` | `Bern(min(0.6, exp(log 0.050 + 1.0·f_infect + 0.12·rtx + 0.004·pred)))`; serious fraction 0.30 | `paperclip: PMC5570101 https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5570101/` | "17 (57%) patients developed a total of 23 infections… Four (13%) patients developed eight infections requiring hospitalizations." |
| `Vasculitis-related serious event[t]` | `is_rtx`, `f_relapse` | `Bern(0.014·exp(0.5·f_relapse + 0.65·rtx))`, serious | `ctgov: resultsSection (serious AE table)` | Disease-related serious events (Wegener's granulomatosis) contribute to the SAE table beyond cytopenias |
| `Infusion related reaction[t]` | `rtx_infusion` | `Bern(0.02)` on RTX infusion visits | `model: params (infusion_rxn_haz)` | Infusion-reaction hazard on RTX infusions (assumption) |
| `Steroid AEs (Hyperglycaemia/Cushingoid/Insomnia)[t]` | `prednisone`, `f_steroid` | hazard `∝ 0.0016·pred·exp(0.8·f_steroid)` | `model: params (steroid_ae_per_mg)` | Glucocorticoid-toxicity ∝ current dose (assumption) |
| `Non-lab AE cluster (Nausea/Vomiting/Diarrhoea/Alopecia/Rash/Arthralgia/Fatigue/Headache/Cough)[t]` | `cyc/aza_active`, `is_rtx`, frailty (`f_GI`/`f_relapse`/`f_infect`), history | `Bern(1 − exp(−exp(log base_haz + frailty + log_rr_cyc·1{cyc/aza} + log_rr_rtx·1{rtx} + 0.3·1{prior})))` | `model: params (ae_nonlab)` | Per-visit hazards calibrated (Step 6); Alopecia CYC-specific (`log_rr_rtx = −2.0`); shared frailty makes the cluster within-patient correlated |

CTCAE v3.0 thresholds (FIXED, never tuned): Leukopenia WBC ≥4→0, ≥3→1, ≥2→2, ≥1→3, <1→4 · Neutropenia
ANC ≥1.5/1.0/0.5/0.2 · Anaemia HGB ≥10/8/6.5 · Thrombocytopenia PLT ≥75/50/25.

### Dose modification, crossover, discontinuation

| Node | Parents | Equation | Source | Evidence |
|---|---|---|---|---|
| `dose_action[t]` | `cyc/aza_active`, `WBC/ANC`, `rtx_infusion` | Reduce CYC/AZA if Gr≥3 leukopenia/neutropenia; withhold infusion if pre-infusion WBC < 3.0 | `ctgov: protocolSection` | Dose modified for cytopenia / pre-infusion WBC (protocol) |
| `crossover[t]` | `remit_ever`, `visit` | Non-remitters may cross over in V5–V8 w.p. 0.10 | `ctgov: protocolSection (blinded crossover)` | Protocol allowed crossover for treatment failures |
| `discontinuation_day` | `f_dropout`, `serious_ae`, `flare` | `Bern(σ(−5.2 + 0.5·f_dropout + 0.7·1{serious_ae} + 1.5·1{severe flare}))`; day sampled **continuously** in (prev visit, this visit], **floored at the triggering serious-AE onset** (#183b) | `ctgov: resultsSection`; `model: _base.TrialSim` | Non-completion RTX 9.1% / CYC 10.2% (target); continuous-time + cause-floored exit inherited from TrialSim |

## Layer Yₜ — Endpoints (deterministic from trajectory)

Generated in [`rave_outcomes.R:derive_endpoints(sim, …)`](rave_outcomes.R). Endpoints are read off the
trajectory — never drawn directly.

| Node | Parents | Equation | Source | Evidence |
|---|---|---|---|---|
| `cr_6mo` (PRIMARY) | trajectory at day 180 | `1{ BVAS/WG = 0 AND prednisone = 0 at the month-6 (V8) visit }` | `ctgov: outcomesModule` | "BVAS/WG of 0 and have successfully completed the glucocorticoid taper at 6 months" |
| `time_to_cr_day` | trajectory | first day with `BVAS/WG = 0 ∧ prednisone = 0` | `model: derive_endpoints` | First complete-remission visit (definitional) |
| `flare_event`, `flare_day` | flare process | first post-remission flare (else censored) | `ctgov: outcomesModule (duration of remission / time to flare)` | secondary endpoint = time to limited/severe flare |
| `remission_duration_day` | `remission_day`, `flare_day` | `flare_day − remission_day` (else to last visit / month 18) | `model: derive_endpoints` | Duration of complete remission (definitional) |
| `death_day` | `serious_ae` | `Bern(0.020 + 0.03·1{serious_ae})`; day in [disc/60, 545] | `model: params (death_base)` | ~2 deaths/arm over 18 mo (assumption; rare) |
| `disposition`, `last_contact_day` | `death_day`, `discontinuation_day` | `DEATH` if death else `DISCONTINUED` if exit else `COMPLETED`; reason preserved | `model: derive_endpoints` | Disposition from trajectory (definitional) |
| AE↔DS reconciliation | `disposition`, trajectory AEs | `sim.reconcile_ae_ds(patient)` — flag exactly one `AEACN="DRUG WITHDRAWN"` when reason = ADVERSE EVENT (#184) | `model: _base.TrialSim` | Traceability inherited from the shared engine; keyed on the emitted reason (death-override safe) |

## Latent frailty roles

Shared random effects (drawn once per patient) that induce realistic within-patient correlation across
AE types and labs. **Origin:** all `model` — latent-effect structure; variances are Step-6 calibration knobs.

| Frailty | Affects | Direction |
|---|---|---|
| `f_heme` | WBC/ANC/HGB/PLT drag on CYC/RTX/AZA | Higher → deeper cytopenias across all heme labs → correlated heme AEs |
| `f_infect` | infection hazard, Cough | Higher → more infections |
| `f_GI` | Nausea/Vomiting/Diarrhoea/Rash/Alopecia/Fatigue/Headache | Higher → more of the GI/constitutional cluster together |
| `f_relapse` | flare hazard, vasculitis serious event | Higher → earlier/more flares |
| `f_steroid` | glucocorticoid-toxicity AEs | Higher → more steroid AEs at a given prednisone dose |
| `f_dropout` | discontinuation hazard | Higher → faster dropout independent of AE/flare |

## Functional notation

- `σ(x) = 1 / (1 + exp(−x))` — logistic CDF (`expit` in code)
- `Bern(p)`, `Cat(…)`, `Normal(μ, σ²)` — standard distributions; `1{·}` — indicator
- AR(1): `x[t] = α·x[t−1] + (1−α)·baseline − drag + noise`
- Nominal vs recorded day: nominal drives all equations/endpoints; the recorded (jittered) day fills date
  columns only, via the independent per-patient jitter RNG in `_base/TrialSim` (issues #182/#183).
