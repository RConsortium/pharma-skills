# SCM Specification — {TRIAL_NAME} (NCT{NCTID})

This template enforces the level of rigor required for an identified
g-formula causal simulation. Every variable must have its **role** in the
DAG, its **mechanistic justification**, its **structural equation with
full distributional specification**, and its **identifiability
assumptions** documented. Skipping fields produces shallow SCMs that
cannot support causal claims.

> **Rule of thumb:** if the entry for a variable is shorter than three
> bullets and lacks an evidence citation, the SCM for that variable is
> not yet specified.

---

## 0 · Global causal framing

Before listing variables, document the trial-level causal question:

| Field | Specification |
|---|---|
| Target estimand | the trial's endpoint archetype — **binary** (event at a landmark), **time-to-event** (PFS/OS; the oncology archetype), or **continuous-change** (change-from-baseline at a landmark). e.g. ATE on that endpoint, ITT vs per-protocol, intercurrent-event handling per ICH E9(R1) |
| Causal contrast | `E[Y(A=1) − Y(A=0)]` for which population and time horizon |
| Identifying assumptions | (1) Consistency — `Y = Y(a)` for the assigned arm. (2) Exchangeability — `Y(a) ⊥ A ∣ L₀` (randomization). (3) Positivity — `0 < P(A=a∣L₀) < 1`. (4) No interference between subjects (SUTVA). State which are by-design vs. assumed. |
| Time-varying confounding | Are there post-baseline `Lₜ` that affect both subsequent treatment decisions (e.g., dose modifications) AND the outcome? If yes, g-formula structure is mandatory; document the recursive identification. |
| Selection / censoring mechanism | Coarsening assumption (typically MAR given observed `Lₜ`); document any informative censoring (e.g., death after treatment discontinuation in PFS analysis) |
| Effect modification of interest | Stratifiers from the protocol (TP53, EGFR type, race, etc.) — which subgroup contrasts must be reproduced |
| Sensitivity analyses planned | E-value benchmarks; tipping-point analysis for unmeasured confounders |

---

## 1 · Variable taxonomy

For every variable in the CRF, classify it on **all** axes below. The
roles cascade into the structural equation form.

| Axis | Possible values |
|---|---|
| Causal role | Exposure / Outcome / Confounder / Mediator / Collider / Instrument / Intermediate (time-varying) / Latent (frailty/random effect) |
| Time index | Baseline (t=0) / Time-varying (t≥1) / Endpoint (Yₜ) / Static latent |
| Observability | Observed / Partially observed / Latent |
| Distributional support | Continuous / Count / Binary / Categorical / Ordinal / Time-to-event |
| Measurement model | Direct / Derived (deterministic from parents) / Reported with detection probability |
| Missingness mechanism | MCAR / MAR / MNAR (with the conditioning set required) |
| Treatment effect pathway | On the causal pathway from A→Y? Direct vs mediated effect? |

---

## 2 · DAG specification — per-variable dossier

For **every** variable, complete this template. Vague entries
("standard distribution", "drug effect") fail review.

### Template

```
### Variable: <NAME>

- **Layer**: L₀ / A / Lₜ / Yₜ / latent
- **Role**: <from taxonomy>
- **Domain**: <support, units>
- **Parents (DAG)**: <complete list — direct causes only>
  - <parent1>: justification and edge type (causal / definitional / measurement)
  - <parent2>: ...
- **Non-parents that might naively look like parents**: <variables that
  share an unmeasured common cause but do NOT have a direct edge here>
  - e.g. ANC and HGB share `f_heme` but neither is a direct parent of the
    other; they are sibling effects of the chemo×frailty interaction.
- **Mechanistic justification**: <2–4 sentences with biological /
  pharmacological reasoning>
- **Functional form**:
  - Link function: <identity / log / logit / log-log / probit / softmax>
  - Equation:
    ```
    NAME[t] = link⁻¹( β₀ + Σ βᵢ·parentᵢ + γ·interaction + frailty + εₜ )
    εₜ ~ <distribution>(scale parameters)
    ```
  - Alternative parameterizations considered and rejected (with reason)
- **Parameter priors** (with full distributional spec):
  | Parameter | Prior distribution | Central value | 95% range | Source |
  |---|---|---|---|---|
  | β₀ | `Normal(μ, σ²)` | x | [a, b] | `[S1]` / CTGov field path |
  | β_arm | `Normal(...)` | x | [a, b] | `[S2]` (meta-analytic HR) |
  | σ_residual | `HalfNormal(...)` | x | [a, b] | `[S3]` (repeated-measures variance) |

  Each `[S<n>]` resolves to a link and the verbatim quote in the **Evidence dossier**
  (§10); a CTGov field path stands on its own. (See the project Citation format.)
- **Time-varying parents (if any)**:
  - List `Lₜ₋₁` parents
  - Lag structure: AR(1) / AR(p) / kernel
  - Parameter ID for autoregressive coefficient α
- **Latent frailty contribution**:
  - Which `f_*` enters this equation
  - Loading coefficient (with prior)
- **Deterministic constraints / clipping**:
  - Lower/upper bounds, monotonicity, conservation laws
- **Detection / reporting model** (if applicable):
  - `P(reported ∣ value, parents)` — reporting probability schedule
  - This is a separate causal node from the underlying value
- **Effect modification**:
  - Which other variables modify the effect of parents on this node
  - Interaction terms in the equation
- **Identifiability check**:
  - Is the full conditional distribution `P(NAME ∣ pa(NAME))` identified
    from the observed data plus the assumed structure?
  - If not, what additional assumptions or auxiliary data are required?
- **d-separation implications**:
  - Backdoor paths through this variable that must be blocked for the
    target estimand
  - Conditioning sets that introduce collider bias
- **Validation gate** (post-simulation):
  - Marginal distribution check
  - Conditional check vs parents
  - Sensitivity check vs alternative parameterizations
- **Evidence dossier** (≥2 citations for non-trivial edges):
  | Claim | Source | Effect size | Population | Limitation |
  |---|---|---|---|---|
  | Edge X→Y exists | `[S1]` | HR=1.4 | NSCLC adv. | Retrospective |

  where `[S1]` resolves below to `<author> <year>, <venue> — <url>` and the verbatim quote
  (≤2–3 sentences) the effect size came from.
```

---

## 3 · Layer L₀ — Baseline (one block per variable)

Use the template above. Required L₀ variables for **any** trial:

- Demographics: `age`, `sex`, `race`, `country` (parents to disease and labs)
- Disease characterization: the protocol's diagnosis / severity covariates
  (parents to the disease process and stratifiers)
- Stratification biomarkers / factors from the randomization design
- Comorbidities (parents to baseline labs and clinical status): age-driven
- Baseline labs: `ANC₀`, `HGB₀`, `PLT₀`, `ALT₀`, `CREAT₀`, etc.
- Baseline clinical-status / severity score (disease-specific)
- **Latent frailties** (mandatory section — see §5)

**Oncology-only additions** (include only for oncology trials):

- Disease: `histology`, `stage`, `metastatic_sites` (parents to tumor burden)
- Biomarkers from stratification: e.g. `EGFR_type`, `TP53_status`, `PD-L1`
- Baseline tumor: `baseline_SLD`, `n_target_lesions`
- Baseline performance: `ECOG₀`
- **Time-to-resistance** (a baseline-drawn latent that drives the entire
  longitudinal tumor process; document its parents on stratifiers)

> **Identifiability note**: every L₀ variable that is not directly
> measured must either be marginalized over or set to a defensible
> empirical Bayes prior. Document which.

---

## 4 · Layer A — Treatment assignment

```
### Variable: arm

- Layer: A
- Role: Exposure
- Domain: one of the protocol's `k` arms `{a₁, …, a_k}` — a reference arm plus
  `k−1` comparators. A two-arm trial is the special case `k=2`.
- Parents: ∅ (by randomization design)
- Mechanistic justification: stratified randomization per protocol §X, at the
  protocol's allocation ratio (equal OR unequal)
- Functional form: `arm ~ Categorical(p₁, …, p_k)` independently across patients,
  where `(p₁, …, p_k)` is the protocol's allocation ratio normalized to sum 1
  (1:1 → `(0.5, 0.5)`; 2:1 → `(0.667, 0.333)`; a 2×2 factorial → one cell per
  factor combination, its probability the product of the two factors' marginal
  allocations). A two-arm equal split reduces to `Bern(0.5)`.
- Treatment coefficient(s): encode arm with `k−1` dummy indicators against the
  reference arm and give **each non-reference arm its OWN coefficient** in every
  downstream equation it enters (its own log-HR / mean-effect / hazard shift) —
  never a single shared active-vs-control knob when `k>2`. Calibrate each arm's
  coefficient against that arm's published contrast.
- Identifiability: by-design exchangeability conditional on stratifiers
- Stratification factors (must be conditioned on for ITT analysis):
  - <list from CTGov design module>
```

---

## 5 · Latent frailties — mandatory rigor section

Latent frailties are the most error-prone part of the SCM. They induce
within-patient correlation across AE types and lab values that no purely
arm-conditioned model can reproduce. Specify them with the same rigor as
observed variables.

For **each** frailty:

```
### Frailty: f_<NAME>

- Cluster: <which AE types or lab values share this latent>
- Distribution: `Normal(0, σ²)` — justify assumption of zero mean
  (re-centering of fixed effects) and homoscedasticity
- σ prior: <distribution and reference for the variance>
- Loading on each child variable: <coefficient with prior>
- Identifiability:
  - Is σ identified from the observed within-patient correlation alone?
  - What is the minimum number of repeated measures per patient needed?
  - Is there confounding with measurement error?
- Joint structure across frailties: are `f_heme`, `f_GI`, etc. modeled
  as independent or with a covariance? Justify.
- Equivalence to alternative formulations: GLMM random intercept, copula,
  factor model — note which is being implemented and why.
```

> **Frailty trap**: setting σ = 0 to "remove a correlation" is a
> structural change, not a calibration. It eliminates the correlation
> entirely rather than tuning its strength. The SCM must declare which
> frailty variances are tunable parameters and which are structurally
> required to be > 0.

---

## 6 · Layer Lₜ — Time-varying state

Per-variable dossier (template in §2). Required dossiers:

> **Visit timing — nominal vs recorded (issues #182/#183).** The NOMINAL SoA day
> drives every Lₜ equation, exposure window, and endpoint readout. Emitted `*DTC`/`*DY`
> columns carry per-subject, per-visit scheduling jitter (default SD ≈ 3 days, clamped
> inside the visit window) drawn from an **independent RNG stream** seeded from
> `(run_seed, subject_index)` — so the main draw order, and thus every marginal/gate, is
> unchanged. Jitter the recorded date only; never the VISIT key or the nominal logic day.

### 6.1 Lab values (AR(p) with treatment effects + frailty)

For each lab (`ANC`, `HGB`, `PLT`, `ALT`, `CREAT`, `QTcF`, …):

- Document the **steady-state value during chemo** with frailty=0:
  `x* = baseline − drag/(1−α)` for AR(1). The team must verify this
  steady state is biologically plausible *before* running the simulator.
- Document the lag structure and any deterministic resets at cycle start.
- Specify the **measurement error** separately from the **process noise**.

### 6.2 Tumor / RECIST — oncology / time-to-event trials only

> Skip this whole section for a non-oncology trial. It models the tumor
> process that a time-to-event (PFS/OS) endpoint is derived from.

- `SLD[t]` mechanistic model: shrinkage kinetics (rate constant `k`),
  asymptotic depth of response (per arm), time-to-resistance switch,
  post-resistance growth rate `g`. All parameters require priors.
- Resistance kinetics: hazard model for time-to-resistance (Weibull
  shape and scale), parents (arm, biomarkers, tumor frailty). The
  Weibull shape governs whether resistance is approximately memoryless
  (k≈1) or accelerating (k>1) — choose based on biology.
- New-lesion process: separate Poisson / Bernoulli per visit with arm-
  and resistance-dependent intensity.
- Response classification (RECIST 1.1): **deterministic function** of
  SLD trajectory and new lesions. This is part of the SCM but never
  tuned — only the inputs to it are.
- Confirmation rule: requires consecutive scans for CR/PR; document
  how confirmation latency affects PFS timing.

### 6.3 Adverse events

> **AE grading scale.** CTCAE is the **oncology** standard; other therapeutic
> areas grade on the protocol's own toxicity scale (e.g. an FDA toxicity
> grading scale for a vaccine/autoimmune trial). Either way the grading map
> is a **fixed function** — only its inputs (the underlying lab/symptom
> values) are tunable knobs. Wherever this section says "CTCAE thresholds",
> read "the protocol's grading thresholds".

For **every** AE preferred term in the published trial table:

- **Generation mechanism**: deterministic from a state variable (lab-grade)
  or hazard-driven (frailty + arm).
- For deterministic AEs (Neutropenia, Anemia, Thrombocytopenia, hepatic):
  - The CTCAE thresholds are fixed (do not parameterize).
  - The reporting probability schedule `P(reported ∣ grade)` IS a parameter.
  - Document the assumed reporting model — most trials under-report Gr 1.
- For hazard-driven AEs (rash, diarrhea, ILD, etc.):
  - Per-visit hazard `λ(parents) = exp(log_haz_base + β_arm + f_cluster + β_recurrence)`
  - Each coefficient needs a prior.
  - Document the exposure window (on-treatment vs follow-up).
  - Document recurrence: is the AE absorbing (ILD), recurrent (rash), or
    transient (acute nausea)?
- **Severity given event**: a separate parameter `p_severe` per AE. Do
  not collapse "incidence" and "severity" into one knob — they have
  different mechanistic determinants.
- **Action taken**: dose-modification action is downstream of grade; do
  not let it be a fresh random draw uncorrelated with grade.
- **Treatment-discontinuation traceability**: when an AE causes treatment
  withdrawal, that AE's `AEACN` is `DRUG WITHDRAWN` and the Disposition reason
  is the AE-attributable category (`DSTERM` = "ADVERSE EVENT"). Reconcile the
  two domains deterministically at projection time — exactly one `DRUG WITHDRAWN`
  AE per AE-discontinued patient, chosen as the most recent serious AE on/before
  last contact. This realizes the existing AE→withdrawal→discontinuation edge; it
  is a projection, not a fresh draw. Add the AE↔DS set-equality validation gate from
  `templates/verify_realism.py`, run on the EMITTED CSVs and keyed on the reason field
  (`DSTERM`): a patient who discontinues for an AE and later dies keeps `DSTERM` = "ADVERSE EVENT"
  (the disposition *code* may be DEATH), so the emit layer must preserve that reason or the gate
  correctly fails.
  Source: `model: CDISC AEACN codelist (C66767)` · Evidence: "DRUG WITHDRAWN is the
  controlled term for withdrawing study drug in response to an adverse event."
- **AE onset vs reporting visit (issue #182)**: distinguish the AE *onset day* (when it
  began — for symptomatic/hazard-driven AEs this may fall between scheduled visits, and is
  what `AESTDTC`/`AEDY` record) from the *reporting visit* (the VISIT captured at the next
  visit, on which the AE↔lab gate joins). Lab-detected CTCAE AEs onset at the visit (the
  assessment detects them). Sample symptomatic onset in (previous visit, current visit];
  the AE↔DS reconciliation cutoff stays on the visit coordinate so it remains consistent.
- **Causality assessment — AEREL (issue #179)**: `AEREL` is an *investigator assessment*, not
  ground truth. In a blinded trial it is conditionally independent of the true arm given AE type
  and temporal pattern — never assign `RELATED` by arm (that collapses treatment-related AEs to
  *all* AEs in the active arm and zero in control). Model `P(RELATED | AE_type, onset)` with
  type-specific priors applied to **both** arms: immune-mediated (thyroid, colitis, hepatitis)
  ≈ 0.80; general AEs with a known drug signal (fatigue, rash) ≈ 0.70; high-background AEs
  (arthralgia, headache) ≈ 0.50. Slight arm modulation (`+0.10` active / `−0.05` control) is
  allowed **only** in open-label trials. This keeps treatment-related AEs a proper subset of all
  AEs. Source: `model: blinding principle (issue #179)` · Evidence: "in a double-blind trial,
  investigators assess causality without knowing assignment."

### 6.4 Dose modifications

- Strictly rule-based per protocol's dose-mod table. Dose modifications
  are descendants of AEs; never make them parents of AEs.
- Document the protocol's hold/resume/withdraw thresholds.

### 6.5 ECOG performance status — oncology trials only

> Skip for a non-oncology trial (use the disease-specific clinical-status
> score in its place, modeled the same way).

- Bivariate transition model `ECOG[t] ∣ ECOG[t−1], recent_g3, progressed`
- ECOG is on the causal pathway from AE burden to discontinuation.

### 6.6 Discontinuation

- Hazard model with parents: recent severe AEs, ILD, progression,
  ECOG decline, frailty `f_dropout`.
- When `reason = ADVERSE EVENT`, that reason is the projection of the triggering
  AE's withdrawal action (`AEACN = DRUG WITHDRAWN`); see §6.3. Disease-attributable
  reasons (flare, progression) have no such edge and carry zero `DRUG WITHDRAWN` AEs.
- **Continuous-time event (issue #183)**: discontinuation does not snap to visit days.
  When the per-visit hazard fires, sample the exact day within the preceding inter-visit
  interval for the recorded `DSSTDY` / last-contact date; the nominal visit day remains
  the logic and AE↔DS reconcile coordinate. For an **AE-attributable** exit, floor that
  date at the triggering AE's onset — a discontinuation cannot predate the event that
  caused it (the disposition date and its `DRUG WITHDRAWN` AE are independent draws in the
  same interval, so without this floor ~10% land out of order).
- Document the censoring model: administrative cutoff vs. early
  discontinuation. PFS analyses typically continue follow-up post
  treatment discontinuation; OS analyses always do.

---

## 7 · Layer Yₜ — Endpoints (deterministic from trajectory)

Endpoints are **never** independently sampled. They are deterministic
functionals of the trajectory. Your trial has **one endpoint archetype** —
pick the matching pattern below and specify it. All three DERIVE the
endpoint from the already-simulated trajectory; none draws it directly.

### 7.1 Binary endpoint (event / no-event at a landmark visit)

e.g. RAVE complete remission at 6 months.

```
### Endpoint: <NAME> (binary)

- Definition: `Y = 1{ criterion( trajectory at the landmark visit ) }` — a
  deterministic threshold on the Lₜ state at the landmark (e.g. remission =
  BVAS==0 AND prednisone==0 at month 6).
- Structural-equation pattern: the criterion reads the already-simulated
  trajectory; there is no separate outcome draw.
    Y_i = 1 if all(criteria(L_i[landmark])) else 0
- Identifiability: by construction from the trajectory.
- Validation gate: the marginal event rate matches the published proportion
  per arm; every Y=1 patient meets the criterion at the landmark visit.
```

### 7.2 Time-to-event endpoint (the oncology archetype: PFS / OS)

```
### Endpoint: PFS_DAY (time-to-event)

- Definition: `min(progression_day, death_day, ADMIN_CENSOR_DAY)`
- Where `progression_day` = first scan visit at which RECIST PD criteria
  met (per the simulated SLD trajectory and new-lesion process)
- Where `death_day` = if simulated within follow-up; otherwise None
- ADMIN_CENSOR_DAY: data-cutoff date from CTGov results record (see §7.4)
- Identifiability: by construction; no additional assumption beyond the
  trajectory's identifying structure
- Validation gate: corr(PFS_DAY, progression_day) = 1.0 for patients with
  observed progression; events strictly before censor mean PFS_EVENT=1
```

### 7.3 Continuous-change endpoint (change-from-baseline at a landmark visit)

e.g. CATH Day-21 biomarker mean change, possibly reported per subgroup/cell.

```
### Endpoint: <NAME>_CHG (continuous-change)

- Definition: `Δ_i = measure_i[landmark] − measure_i[baseline]` — the change
  in a continuous state variable already on the trajectory.
- Structural-equation pattern: the measure at each visit is an ordinary Lₜ
  node with an identity/additive link (baseline + drift + arm effect +
  frailty + residual); the endpoint is just its landmark-minus-baseline
  difference.
    measure_i[t] = baseline_i + drift·t + arm_effect·1{active} + f_i + ε_it
    Δ_i          = measure_i[landmark] − measure_i[baseline]
- Reported per cell: if the publication reports the mean change per subgroup,
  the calibration target is the per-cell mean (and SD).
- Identifiability: by construction from the trajectory.
- Validation gate: per-arm (per-cell) mean change matches the published
  value; Δ equals the emitted measure's landmark-minus-baseline.
```

Any deviation from these rules (e.g., drawing the time-to-event `PFS_TIME`
from a Weibull conditioned only on arm, or drawing a binary outcome from a
per-arm Bernoulli, or sampling `Δ` from a per-arm Normal) collapses the SCM
to a marginal model and forfeits all causal claims. Document explicitly that
this is not done.

### 7.4 Administrative censoring with enrollment stagger (issue #180)

`ADMIN_CENSOR_DAY` is **patient-specific**, not a single constant — otherwise every censored
patient shares an identical follow-up time, a point mass that is both an obvious synthetic
fingerprint and a distortion of the KM tail.

```
enrollment_offset_i ~ f(enrollment_pattern)
ADMIN_CENSOR_DAY_i  = data_cutoff_date − enrollment_start − enrollment_offset_i
```

Enrollment-pattern options (read from the protocol / CTGov):
- `Uniform(0, enrollment_window)` — simplest; adequate for most trials
- piecewise-linear (ramp-up · plateau · wind-down) — more realistic
- directly from CTGov "Study Start" and "Primary Completion" dates

Calibration: the **median** of `ADMIN_CENSOR_DAY_i` should equal the published median follow-up;
its range should span `[min_followup, max_followup]` from the publication.

Scope: this applies to **calendar-cutoff** designs (e.g. oncology OS/PFS). Trials whose endpoints
are anchored to each patient's own randomization with a fixed follow-up duration (as in RAVE) have
no such point mass and may keep a constant administrative cap. Source: `model: staggered-enrollment
design (issue #180)` · Evidence: "all censored patients having identical follow-up time is
structurally incorrect."

---

## 8 · Time-varying confounding diagram (mandatory)

Draw the per-time-step DAG showing how `Lₜ` influences subsequent
treatment decisions and outcomes. For a typical trial with time-varying treatment:

```
A ──→ L₁ ──→ L₂ ──→ ... ──→ Y
│      │      │              │
└──────┴──────┴──────────────┘  (direct A → Lₜ for each t)
       │      │
       └──→ Aₜ (dose modifications)  ← time-varying treatment
              │
              └──→ Lₜ₊₁
```

Document:
- Which `Lₜ` nodes affect dose modifications (`Aₜ`, t≥1) — these are
  time-varying confounders requiring g-formula adjustment.
- Whether the per-protocol estimand requires inverse-probability
  weighting for treatment changes, or whether intention-to-treat
  ignores them.
- Whether the dropout process is conditional on observed `Lₜ` (MAR;
  g-formula handles this) or on unobserved factors (MNAR; sensitivity
  analysis required).

---

## 9 · Effect-modification specification

For each pre-specified subgroup analysis in the trial:

| Subgroup variable | Expected effect modification | Mechanism | Reference |
|---|---|---|---|
| `tp53_status` | TP53-mut: HR vs combo attenuated by ≈0.1 | TP53 alters response duration | `[S1]` |
| `egfr_type` | Ex19del: deeper response than L858R | Ligand-binding affinity | `[S2]` |
| `cns_mets` | CNS+: shorter PFS | CNS sanctuary, drug penetration | `[S3]` |

The SCM must reproduce these subgroup contrasts with effect sizes within
the published 95% CIs.

---

## 10 · Evidence dossier

Every non-trivial edge requires multiple sources where possible. This section is where each
`[S<n>]` tag used above is defined — give it a resolvable link and the verbatim quote, so the
tag in any table resolves to its source and exact text.

For each edge `X → Y`:

| Field | Required content |
|---|---|
| Edge | `X → Y` |
| Effect direction & magnitude | sign, point estimate, range |
| Mechanism | biological / pharmacological / measurement |
| Primary source | `[S<n>]` — `<first author> <year>, <venue>`, first-class evidence (RCT or large registry) |
| Link | resolvable `url` for the `[S<n>]` source |
| Verbatim quote | the exact text (≤2–3 sentences) the effect size came from — copied, not paraphrased |
| Secondary sources | confirmatory `[S<n>]` citations (each with its own link + quote) |
| Effect-size variability | range across populations |
| Limitations | confounding in source studies, generalizability |

---

## 11 · Identifiability summary

At the end of specification, produce a checklist:

- [ ] **Consistency**: counterfactual outcome equals observed outcome
  under the assigned arm — ensured by the SCM by construction.
- [ ] **Exchangeability**: `Y(a) ⊥ A ∣ stratifiers` — ensured by the
  randomization model in §4.
- [ ] **Positivity**: `0 < P(A=a ∣ L₀) < 1` — verify that no L₀ stratum
  has all patients on one arm.
- [ ] **No interference / SUTVA** — patients are independent draws.
- [ ] **Time-varying exchangeability**: `Y(ā) ⊥ Aₜ ∣ L̄ₜ, Āₜ₋₁` for the
  per-protocol estimand if applicable.
- [ ] **Coarsening at random / MAR for missingness** — given the
  conditioning set documented per variable.
- [ ] **No hidden direct edges from A to Y** that bypass the modeled
  mediators.

If any item is unchecked, document why (e.g., "violation expected; will
include sensitivity analysis").

---

## 12 · Pre-simulation review checklist

Before running step 5 (forward simulation), verify:

- [ ] Every variable has a complete dossier per §2
- [ ] DAG is acyclic (run `networkx.is_directed_acyclic_graph`)
- [ ] All parameter priors have ≥1 cited source — a `[S<n>]` resolving to a link + verbatim
      quote, or a CTGov field path
- [ ] All deterministic rules (CTCAE thresholds, RECIST 1.1) are coded
      as functions, not parameters
- [ ] Latent frailties have non-zero variance priors
- [ ] No endpoint is sampled directly from a parent's distribution
- [ ] Time-varying confounding diagram (§8) is drawn and matches code
- [ ] Identifiability checklist (§11) is signed off
- [ ] Nominal day drives all logic + endpoints; a separate per-patient jitter RNG produces the
      recorded day, and symptomatic-AE onsets fall between visits (issues #182/#183)
- [ ] The four date/traceability gates are wired from `templates/verify_realism.py` (visit-date
      variance #183, AE-onset dispersion #182, continuous-time discontinuation + coherence #183,
      AE↔DS traceability #184) and run against the WRITTEN CSVs — never internal engine state
- [ ] AE-driven discontinuation reason (`DSTERM` = "ADVERSE EVENT") is preserved on the emitted
      disposition even when the disposition code is DEATH (discontinued-for-AE-then-died patients),
      so the AE↔DS gate holds
