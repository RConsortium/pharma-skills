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
| Target estimand | e.g. ATE on PFS, ITT vs per-protocol, intercurrent-event handling per ICH E9(R1) |
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
  | β₀ | `Normal(μ, σ²)` | x | [a, b] | PMID / CTGov field path |
  | β_arm | `Normal(...)` | x | [a, b] | meta-analytic HR |
  | σ_residual | `HalfNormal(...)` | x | [a, b] | repeated-measures variance estimate |
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
  | Edge X→Y exists | PMID xxx | HR=1.4 | NSCLC adv. | Retrospective |
```

---

## 3 · Layer L₀ — Baseline (one block per variable)

Use the template above. Required L₀ variables for any oncology trial:

- Demographics: `age`, `sex`, `race`, `country` (parents to disease and labs)
- Disease: `histology`, `stage`, `metastatic_sites` (parents to tumor burden)
- Biomarkers from stratification: e.g. `EGFR_type`, `TP53_status`, `PD-L1`
- Comorbidities (parents to baseline labs and ECOG): age-driven
- Baseline labs: `ANC₀`, `HGB₀`, `PLT₀`, `ALT₀`, `CREAT₀`, etc.
- Baseline tumor: `baseline_SLD`, `n_target_lesions`
- Baseline performance: `ECOG₀`
- **Latent frailties** (mandatory section — see §5)
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
- Domain: {0=mono, 1=combo} (or per-protocol arms)
- Parents: ∅ (by randomization design)
- Mechanistic justification: 1:1 stratified randomization per protocol §X
- Functional form: `arm ~ Bern(p_combo = 0.5)` independently across patients
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

### 6.1 Lab values (AR(p) with treatment effects + frailty)

For each lab (`ANC`, `HGB`, `PLT`, `ALT`, `CREAT`, `QTcF`, …):

- Document the **steady-state value during chemo** with frailty=0:
  `x* = baseline − drag/(1−α)` for AR(1). The team must verify this
  steady state is biologically plausible *before* running the simulator.
- Document the lag structure and any deterministic resets at cycle start.
- Specify the **measurement error** separately from the **process noise**.

### 6.2 Tumor / RECIST

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

### 6.4 Dose modifications

- Strictly rule-based per protocol's dose-mod table. Dose modifications
  are descendants of AEs; never make them parents of AEs.
- Document the protocol's hold/resume/withdraw thresholds.

### 6.5 ECOG performance status

- Bivariate transition model `ECOG[t] ∣ ECOG[t−1], recent_g3, progressed`
- ECOG is on the causal pathway from AE burden to discontinuation.

### 6.6 Discontinuation

- Hazard model with parents: recent severe AEs, ILD, progression,
  ECOG decline, frailty `f_dropout`.
- Document the censoring model: administrative cutoff vs. early
  discontinuation. PFS analyses typically continue follow-up post
  treatment discontinuation; OS analyses always do.

---

## 7 · Layer Yₜ — Endpoints (deterministic from trajectory)

Endpoints are **never** independently sampled. They are deterministic
functionals of the trajectory.

```
### Endpoint: PFS_DAY

- Definition: `min(progression_day, death_day, ADMIN_CENSOR_DAY)`
- Where `progression_day` = first scan visit at which RECIST PD criteria
  met (per the simulated SLD trajectory and new-lesion process)
- Where `death_day` = if simulated within follow-up; otherwise None
- ADMIN_CENSOR_DAY: data-cutoff date from CTGov results record
- Identifiability: by construction; no additional assumption beyond the
  trajectory's identifying structure
- Validation gate: corr(PFS_DAY, progression_day) = 1.0 for patients with
  observed progression; events strictly before censor mean PFS_EVENT=1
```

Any deviation from this rule (e.g., drawing PFS_TIME from a Weibull
conditioned on arm) collapses the SCM to a marginal model and forfeits
all causal claims. Document explicitly that this is not done.

---

## 8 · Time-varying confounding diagram (mandatory)

Draw the per-time-step DAG showing how `Lₜ` influences subsequent
treatment decisions and outcomes. For a typical oncology trial:

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
| `tp53_status` | TP53-mut: HR vs combo attenuated by ≈0.1 | TP53 alters response duration | PMID xxx |
| `egfr_type` | Ex19del: deeper response than L858R | Ligand-binding affinity | PMID xxx |
| `cns_mets` | CNS+: shorter PFS | CNS sanctuary, drug penetration | PMID xxx |

The SCM must reproduce these subgroup contrasts with effect sizes within
the published 95% CIs.

---

## 10 · Evidence dossier

Every non-trivial edge requires multiple sources where possible.

For each edge `X → Y`:

| Field | Required content |
|---|---|
| Edge | `X → Y` |
| Effect direction & magnitude | sign, point estimate, range |
| Mechanism | biological / pharmacological / measurement |
| Primary source | PMID with first-class evidence (RCT or large registry) |
| Secondary sources | confirmatory citations |
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
- [ ] All parameter priors have ≥1 cited source
- [ ] All deterministic rules (CTCAE thresholds, RECIST 1.1) are coded
      as functions, not parameters
- [ ] Latent frailties have non-zero variance priors
- [ ] No endpoint is sampled directly from a parent's distribution
- [ ] Time-varying confounding diagram (§8) is drawn and matches code
- [ ] Identifiability checklist (§11) is signed off
