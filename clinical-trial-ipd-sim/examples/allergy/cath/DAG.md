# CATH Causal-DAG Simulator — Model Specification

Trial: **ADVN CATH 03-01 — "Antimicrobial Response to Oral Vitamin D3 in Patients with Psoriasis"**
(substudy of ADVN CATH 03; **NCT00789880**; sponsor NIAID; protocol chair R. Gallo, UCSD). This
document maps every variable in the Step-2 CRF schema
([`odm/crf_picks.json`](odm/crf_picks.json)) to its DAG parents and the structural equation that
generates it, following the g-formula layered structure **L₀ → A → Lₜ → Yₜ**, with a fixed latent
frailty vector shared across the patient's trajectory.

This is a **short mechanistic trial**, not a survival trial: two arms (oral Vitamin D3 4000 IU/day vs
matching placebo, 21 days) crossed with three diagnostic groups (Psoriasis / Atopic Dermatitis /
Non-AD healthy control) → 6 posted result cells, N = 82. The visit grid is just **Screening (V1,
Day −7…−10) → Baseline (V2, Day 0 = randomization + first dose) → Day 21 (V3, window Day 18–27) →
Unscheduled**. There is no time-to-event endpoint. The endpoints are **change-from-baseline biomarker
deltas** (antimicrobial-peptide and TH2-cytokine mRNA in lesional vs non-lesional skin), so the
central latent state is **cutaneous antimicrobial-peptide (AMP) expression**, and the treatment acts
on it through **serum vitamin D → AMP induction**. Endpoints are read off the trajectory (the Day-21
value minus the baseline value) — never drawn directly.

## Source & Evidence columns (skill Citation format)

Each **Source** carries an origin tag; each **Evidence** cell carries the verbatim text the row rests on.

- `ctgov: <field>` — a value read from the NCT00789880 ClinicalTrials.gov record ([`intake/NCT00789880.json`](intake/NCT00789880.json)); Evidence = the exact field value/text.
- `protocol: §<x>` — the **user-supplied protocol PDF** (the user-supplied ADVN CATH 03-01 protocol PDF), the skill's required Step-1 input. This is an external, authoritative source that is **not** in the CTGov record, so it is tagged distinctly from `ctgov` (and it is not `model` — there *is* an external source). Evidence = the verbatim protocol text.
- `paperclip: <id> <url>` — a literature record gathered through the `literature-search-paperclip` skill; Evidence = the verbatim quote (copied, not paraphrased). Never asserted from model memory.
- `model: <kind>` — a modeling / sanity default with **no** external source (flagged; a knob for Steps 4/6); Evidence = the explicit assumption being made.

Paperclip records cited (quotes inline in the rows below):

- **[S1]** `paperclip: PMC2686169 https://www.ncbi.nlm.nih.gov/pmc/articles/PMC2686169/` — Liu et al., *PLoS ONE* 2009. Vitamin-D-receptor activation directly induces cathelicidin and β-defensin (DEFB4); the CAMP promoter carries three VDREs.
- **[S2]** `paperclip: 2094036101 https://doi.org/10.1056/nejmoa021481` — Ong et al., *NEJM* 2002. AMP deficiency underlies *S. aureus* susceptibility in atopic dermatitis.
- **[S3]** `paperclip: PMC10326740 https://www.ncbi.nlm.nih.gov/pmc/articles/PMC10326740/` — Szabó et al., *Acta Derm Venereol* 2023. LL-37 (cathelicidin) is impaired in lesional and non-lesional AD.
- **[S4]** `paperclip: PMC2782163 https://www.ncbi.nlm.nih.gov/pmc/articles/PMC2782163/` — Kim et al., *J Korean Med Sci* 2005. LL-37 is negligible in normal skin but markedly increased in psoriasis.
- **[S5]** `paperclip: 1528623386 https://doi.org/10.4049/jimmunol.179.2.984` — Albanesi et al., *J Immunol* 2007. IL-4 and IL-13 (TH2) negatively regulate β-defensin expression.
- **[S6]** `paperclip: 2098825396 https://doi.org/10.1111/jdv.12176` — Hata et al., *JEADV* 2014 (this trial's own main-study RCT publication; PMID 23638978). Darker skin type and higher BMI are risk factors for vitamin D deficiency in AD.
- **[S7]** `paperclip: 2128501903 https://doi.org/10.4172/2161-1165.1000148` — Jarrett, 2014 review. Oral vitamin D3 supplementation raises serum vitamin D.
- **[S8]** `paperclip: 2151400905 https://doi.org/10.1046/j.0905-6157.2003.00106.x` — Laske et al., 2004. Serum IgE and atopic-dermatitis severity.

The DAG **structure** (which node depends on which) is fixed by this document; only the **parameters**
are tunable by the calibration loop (Step 6). Because this trial posted results for only a narrow
slice (the biopsy CAMP / HBD-3 / IL-13 change endpoints, the baseline characteristics, and an
**all-zero** adverse-event table), every other collected variable is simulated from cited priors and
left **uncalibrated** (`target: null`) — it is still generated and still obeys every DAG gate. The
date/traceability behavior (#182 AE onset, #183 visit/discontinuation jitter, #184 AE↔DS
traceability) is **inherited from the shared engine** [`R/ TrialSim`](../../../R/trial_sim.R):
nominal day drives all equations; a separately-seeded per-patient jitter RNG fills recorded dates only.

## Trial design (context for the arm edge)

| Item | Value | Source | Evidence |
|---|---|---|---|
| Arms | Oral Vitamin D3 (cholecalciferol) 4000 IU/day vs matching placebo, 21 days | `ctgov: armsInterventionsModule` | "Subjects received a 21-day course of oral vitamin D3 (cholecalciferol, 4,000 international units [IU]" / "21-day course of oral vitamin D3-placebo" |
| Randomization / masking | Randomized, parallel, quadruple-blind, placebo-controlled | `ctgov: designModule/designInfo` | allocation "RANDOMIZED"; interventionModel "PARALLEL"; masking "QUADRUPLE" (participant, care provider, investigator, outcomes assessor) |
| Diagnostic groups (6-cell stratifier) | Psoriasis / Atopic Dermatitis (AD) / Non-AD healthy control, each under VitD3 and placebo | `ctgov: resultsSection/participantFlowModule` | groups "Vitamin D (Non-AD)", "Vitamin D (AD)", "Vitamin D (Psoriasis)", "Placebo (Non-AD)", "Placebo (AD)", "Placebo (Psoriasis)" |
| Primary endpoint | Change from baseline to Day 21 in CAMP (cathelicidin) and HBD-3 mRNA, lesional vs non-lesional skin, VitD3 vs placebo, per group | `ctgov: outcomesModule/primaryOutcomes` | "Change From Baseline on Day 21 in Relative Abundance of CAMP mRNA in Lesional and Non-Lesional Skin … Who Received Oral Vitamin D3 Versus Vitamin D3-Placebo" |
| Primary endpoint (protocol contrast) | Difference between lesional-change and non-lesional-change in AMP | `protocol: §7.1.1` | "Difference between the change in expression of antimicrobial peptides (hCAP18/LL-37, HBD3) from baseline to study day 21 in psoriatic subjects' LESIONAL skin biopsies and the change in non-lesional skin biopsies. [PRIMARY]" |
| Secondary endpoint | Change from baseline to Day 21 in IL-13 mRNA (TH2 cytokine); IL-4 also collected | `ctgov: outcomesModule/secondaryOutcomes` | "Change From Baseline on Day 21 in Relative Abundance of IL-13 mRNA in Lesional and Non-Lesional Skin …" |
| Eligibility (diagnosis) | Plaque psoriasis ≥6 mo (or AD / non-atopic control from main study); US residents; 18–70 y | `ctgov: eligibilityModule` | "Definitive diagnosis of typical plaque psoriasis for at least 6 months … or is an AD or non-atopic healthy control subject participating in the main protocol ADVN CATH 03." / minimumAge "18 Years", maximumAge "70 Years" |
| Eligibility (labs / excl.) | Screening calcium, PTH, creatinine within normal limits; diabetes and kidney disease excluded | `ctgov: eligibilityModule` | "Certain screening laboratory values not within normal limits, which would include calcium, serum PTH, and serum creatinine" / "Diabetes" (exclusion) |
| Dosing detail | 24 capsules dispensed; return window Day 18–27; not returning by Day 27 → discontinued/replaced; pill counts at V3 | `protocol: §9.1, §9.5` | "randomized to oral Vitamin D3 4000 IU/day OR Vitamin D3 placebo for 21 days (24 capsules dispensed). Return window Day 18-27; not returning by Day 27 => discontinued and replaced." / "unused medication returned; pill counts documented at Study Visit 3." |
| AE grading | Severity graded 1–4 (FDA Toxicity Grading Scale for Healthy Adult/Adolescent Volunteers in Preventive Vaccine Trials); relatedness 1–5 | `protocol: §12.6.1, §12.6.3` | "Severity graded 1-4 (FDA Toxicity Grading Scale … Sept 2007): Grade 1 mild, 2 moderate, 3 severe, 4 life-threatening/death." / "Relationship/attribution to study drug … 1 Unrelated, 2 Unlikely, 3 Possible, 4 Probable, 5 Definite." |
| Observed AE burden (calibration target) | Zero — no SAEs, nothing ≥5% in any of the 6 cells | `ctgov: resultsSection/adverseEventsModule` | "There were no serious adverse events. No adverse events occurred at a 5% or greater frequency threshold." |

## Layer 0 — Baseline (L₀)

Topological order: design covariates (group, demographics) → disease characterization → baseline
serum labs → **baseline cutaneous AMP / TH2 / microbial substrate** → latent frailties. The diagnostic
group `diagnosis_group` is the master baseline covariate: it shifts baseline AMP (psoriasis high, AD
low), TH2 cytokines (AD high), IgE (AD high), and colonization (AD high).

### Design covariates & demographics (DM, SCRN)

| Node | Parents | Structural equation | Source | Evidence |
|---|---|---|---|---|
| `site` (SITEID) | ∅ | $\mathrm{Uniform}(\{\text{UCSD sites}\})$ | `protocol: title page` | "PROTOCOL CHAIR: Richard Gallo, MD, PhD (UCSD). Single-center (UCSD)." |
| `country` (COUNTRY) | ∅ | $\delta(\text{USA})$ | `ctgov: baselineCharacteristicsModule (Region of Enrollment)` | "United States … 82" (all participants) |
| `diagnosis_group` (DIAGGRP) | ∅ | $\mathrm{Cat}(\text{Psoriasis},\,\text{AD},\,\text{Non-AD})$ per the 6-cell design | `ctgov: resultsSection/participantFlowModule` | groups "…(Non-AD)", "…(AD)", "…(Psoriasis)" under both Vitamin D and Placebo |
| `age` (AGE) | `diagnosis_group` | $\mathrm{clip}(\mathcal{N}(\mu_g,\,\sigma_g^2),\,18,\,70)$; $\mu\!=\!32.5$ overall, higher (~40) in psoriasis | `ctgov: baselineCharacteristicsModule ("Age, Continuous")` | Total mean 32.5 (SD 10.9); Psoriasis 40.5 (11.6) vs AD 32.2 (10.5) / 28.6 (9.8) |
| `sex` (SEX) | ∅ | $\mathrm{Bern}(F=44/82)$ | `ctgov: baselineCharacteristicsModule (Sex)` | Female 44, Male 38 (Total) |
| `race` (RACE) | ∅ | $\mathrm{Cat}(\text{White }54,\,\text{Asian }10,\,\text{Black }9,\,\text{Other }9)$ | `ctgov: baselineCharacteristicsModule (Race/Ethnicity)` | White 54, Asian 10, Black 9, Other 9 (Total = 82) |
| `ethnic` (ETHNIC) | ∅ | $\mathrm{Bern}(\text{Hispanic}=9/82)$ | `ctgov: baselineCharacteristicsModule (Ethnicity)` | Hispanic or Latino 9; Not Hispanic 73 |
| `fitzpatrick` (FITZPATRICK) | `race` | $\mathrm{Cat}(\text{I–VI})$ shifted darker with non-white `race` | `ctgov: baselineCharacteristicsModule (Fitzpatrick Skin Scale)` | Fair 20, Medium 26, Olive 22, Markedly Black 6 (etc.) |
| `bmi` (BMI) | `diagnosis_group` | $\mathrm{clip}(\mathcal{N}(\mu_g,\,\sigma_g^2),\,16,\,45)$; $\mu\!=\!25.3$ overall | `ctgov: baselineCharacteristicsModule (BMI)` | Total 25.3 (SD 4.9); Psoriasis 28.0 / 27.1 |
| `height` (HEIGHT) | `sex` | $\mathcal{N}(176\text{ M}/163\text{ F},\,7^2)$ cm | `model: make_baseline` | adult height prior by sex (not posted) |
| `weight` (WEIGHT) | `bmi`, `height` | $\mathrm{weight}=\mathrm{bmi}\cdot(\mathrm{height}/100)^2$ | `model: make_baseline` | weight back-derived so BMI matches the posted marginal |
| `icdtc`/`rfstdtc` (ICDTC, RFSTDTC) | `site` | consent date at V1; randomization/first-dose date = V2 (Day 0) | `protocol: Table 10.1, §9.1` | "Informed consent | X" at V1; "randomization to Vitamin D3 or placebo" at V2 (Day 0) |

### Disease characterization (DC, MH, SCRN)

| Node | Parents | Structural equation | Source | Evidence |
|---|---|---|---|---|
| `dx_psoriasis` (DXPSOR) | `diagnosis_group` | $\delta(\text{"plaque psoriasis"})$ if group = Psoriasis, else blank | `protocol: §8` | "definitive plaque psoriasis ≥6 months by ADVN Standard Diagnostic Criteria" |
| `psor_duration` (PSORDUR_MO) | `dx_psoriasis` | $6+\mathrm{Exp}(\text{mean}\approx72)$ months (floor 6) for psoriasis | `ctgov: eligibilityModule` / `protocol: §8` | "Definitive diagnosis of typical plaque psoriasis for at least 6 months" |
| `psor_severity` (PSORSEV) | `dx_psoriasis` | $\mathrm{Cat}(\text{mild},\text{moderate},\text{severe})$; drives baseline PASI | `protocol: §14.2.1` | "severity (mild/moderate/severe); continuous by mean/SD/median/range, categorical by counts/percent" |
| `dcdtc` (DCDTC) | `site` | diagnosis date at V1 | `protocol: Table 10.1` | "Diagnosis of Psoriasis | X" at V1 |
| `mh` (MHTERM, MHOCCUR, MHDTC) | `age` | few items (healthy population; eligibility excludes DM, kidney, autoimmune, malignancy); $\Pr(\text{item})=\sigma(-2.5+0.03\,(\mathrm{age}-40))$ | `ctgov: eligibilityModule (exclusions)` | "Diabetes"; "History of kidney disease or kidney stones"; "Having autoimmune or immunodeficiency disease" (all exclusions → sparse MH) |

### Baseline serum labs (LB, SCRN)

| Node | Parents | Structural equation | Source | Evidence |
|---|---|---|---|---|
| `vitd_bl` (VITD @ V1) | `fitzpatrick`, `bmi` | $\mathrm{clip}(\mathcal{N}(29.2,\,11.2^2)-1.5\,\mathrm{darkskin}-0.3\,(\mathrm{bmi}-25),\,5,\,80)$ ng/mL | `ctgov: baselineCharacteristicsModule` + `paperclip [S6]` | ctgov: Serum Vitamin D 25-OH Total 29.2 (SD 11.2). [S6] "darker skin types and elevated BMI are important risk factors for vitamin D deficiency in subjects with AD" |
| `calcium_bl` (CALCIUM) | ∅ | $\mathrm{clip}(\mathcal{N}(9.4,\,0.4^2),\,8.4,\,10.2)$ mg/dL (eligibility within normal limits) | `ctgov: baselineCharacteristicsModule` | Serum Calcium Total 9.4 (SD 0.4); normal range 8.4–10.2 |
| `creat_bl` (CREAT) | ∅ | $\mathrm{clip}(\mathcal{N}(0.8,\,0.2^2),\,0.4,\,1.2)$ mg/dL | `ctgov: baselineCharacteristicsModule` | Serum Creatinine Total 0.8 (SD 0.2); normal range 0.4–1.2 |
| `pth_bl` (PTH) | `vitd_bl` | $\mathrm{clip}(\mathcal{N}(34.4,\,11.4^2)-0.2\,(\mathrm{vitd}-29),\,15,\,75)$ pg/mL (inverse PTH–vitD) | `ctgov: baselineCharacteristicsModule` + `model` | ctgov: Serum PTH Total 34.4 (SD 11.4); model: physiologic inverse vitamin-D↔PTH coupling |
| `ige_bl` (IGE) | `diagnosis_group` | $\mathrm{LogNormal}$ with group median: AD ≫ Non-AD/Psoriasis | `ctgov: baselineCharacteristicsModule` + `paperclip [S8]` | ctgov: Total Serum IgE — AD 1870.1 vs Non-AD 68.4, Psoriasis 85.1 kU/L. [S8] "Does the severity of atopic dermatitis correlate with serum IgE levels?" |
| `rast` (RAST) | `ige_bl`, `diagnosis_group` | $\mathrm{Bern}(\sigma(-1.5+1.2\,\mathbb{1}[\text{AD}]+0.6\,z(\log\mathrm{IgE})))$ → positive/negative; **uncalibrated** | `paperclip [S8]` + `model` | allergen sensitization tracks IgE / atopy; no posted result (target null) |
| `serumstor` (SERUMSTOR) | `calcium_bl`, `pth_bl`, `creat_bl` | $\delta(\text{"destroyed"})$ if any screening lab out of range (→ IgE/RAST not analyzed), else "stored" | `protocol: §10.4` | "If a subject screen-fails at Visit 1 on Ca/PTH/creatinine, remaining serum is destroyed and NOT analyzed for total IgE or RAST." |
| `lbdtc`/`lbdy` (LBDTC, LBDY) | `site` | recorded blood-draw date/day = nominal V1 (and V3) + jitter | `protocol: §10.6, Table 10.1` | "Blood collection … | V1 … V3" |

### Baseline cutaneous substrate — AMP, TH2 cytokines, microbial (BX, SAL, TS, MB, SW; measured at V2)

These are the latent biological state the intervention acts on. `diagnosis_group` sets the level
(psoriasis high AMP, AD low LL-37 / high TH2 / high colonization); `lesional` vs `non-lesional`
compartment matters; frailties correlate a subject's readouts across compartments/assays.

| Node | Parents | Structural equation | Source | Evidence |
|---|---|---|---|---|
| `camp_bl` (BX.CAMP_LES, CAMP_NONLES @ V2) | `diagnosis_group`, `il13_bl`/`il4_bl`, `f_amp`, lesional | $\mathrm{CAMP}^{c}_0=\alpha_g+\lambda\,\mathbb{1}[\text{lesional}]-\theta\,\mathrm{th2}^{c}+f_{amp}+\varepsilon$; $\alpha_{Psor}>\alpha_{NonAD}>\alpha_{AD}$ | `paperclip [S3][S4][S5]` | [S4] "abundant LL-37 in the epidermis of psoriasis"; [S3] "LL-37 was the only antimicrobial peptide that was impaired in both non-lesional and lesional atopic dermatitis"; [S5] IL-4/IL-13 "Negatively Regulate … β-Defensin Expression" |
| `hbd3_bl` (BX.HBD3_LES, HBD3_NONLES @ V2) | `diagnosis_group`, `il13_bl`/`il4_bl`, `f_amp`, lesional | same form as `camp_bl`, HBD-3 intercepts | `paperclip [S4][S5]` | [S4] "Defensins and cathelicidins (LL-37) … their expression can be markedly increased in inflammatory skin disease such as psoriasis"; [S5] β-defensin down-regulated by IL-4/IL-13 |
| `il13_bl`, `il4_bl` (BX.IL13_*, IL4_* @ V2) | `diagnosis_group`, `f_th2`, lesional | $\mathrm{th2}^{c}=\tau_g+\lambda_{th2}\,\mathbb{1}[\text{lesional}]+f_{th2}+\varepsilon$; $\tau_{AD}$ highest | `paperclip [S5]` + `model` | [S5] TH2 cytokines IL-4/IL-13 are the axis suppressing AMPs (elevated in AD); `model` group intercepts |
| `sal_amp_bl` (SAL.SAL_CAMP, SAL_HBD3 @ V2) | `camp_bl`/`hbd3_bl` (subject AMP tone), `f_amp` | $\mathrm{SAL}=\beta_0+\beta_1\,\mathrm{AMP\_tone}+f_{amp}+\varepsilon$, normalized to `sal_totprot` | `protocol: §10.2` + `paperclip [S1]` | "cathelicidin abundance normalized to total protein; qRT-PCR for cathelicidin mRNA" (saliva reflects the same vitamin-D–AMP axis) |
| `sal_totprot` (SAL.SAL_TOTPROT) | ∅ | $\mathcal{N}(\text{BCA total protein})$; saliva AMP normalizer | `protocol: §10.2` | "Total protein by BCA; cathelicidin abundance normalized to total protein" |
| `ts_amp_bl` (TS.TS_CAMP_*, TS_HBD3_* @ V2) | `camp_bl`/`hbd3_bl` (biopsy is gold standard), `f_amp` | $\mathrm{TS}=\gamma_0+\gamma_1\,\mathrm{biopsy\_AMP}+f_{amp}+\varepsilon$ (Pearson-correlated with biopsy) | `protocol: §14.2.11` | "Comparison of TAPE STRIPPING vs punch biopsies — Pearson correlations, per diagnostic group" (tape strip estimates the biopsy AMP) |
| `cfu_bl` (MB.CFU_LES, CFU_NONLES @ V2) | `diagnosis_group`, `camp_bl` (lower AMP → higher CFU), `f_microbiome`, lesional | $\log\mathrm{CFU}^{c}=\kappa_g-\rho\,\mathrm{CAMP}^{c}_0+f_{micro}+\varepsilon$ | `paperclip [S2]` | [S2] "A deficiency in the expression of antimicrobial peptides may account for the susceptibility of patients with atopic dermatitis to skin infection with S. aureus." |
| `sw_flora` (SW.SWCOLLECT, SWLOC, SW_FLORA) | `diagnosis_group`, `f_microbiome` | collected on subset (≥6/group); `SWCOLLECT`∈{yes,no}, `SWLOC`∈{lesional,non-lesional}, `SW_FLORA` = profile string; **uncalibrated** (stored for future analysis) | `protocol: §10.5, §11.5.2` | "skin swabs for genomic analysis of bacterial flora collected on a subset (≥6 per diagnostic group), stored for future analysis" |
| `bxdtc`/`bxdy` (BXDTC, BXDY), `saldtc`, `tsdtc`, `mbdtc`, `swdtc`, `skdtc` | `site` | recorded assay date/day = nominal visit + jitter | `protocol: §10.6` | visit grid V2/V3/Unscheduled (§10.6) |
| `photo` (BX.PHOTO) | `diagnosis_group` | $\delta(\text{"taken"})$ of lesional biopsy site at V2/V3 | `protocol: §11.3` | "photographs of lesional skin at V2 and V3" |

### Latent frailties (drawn once per patient; the within-patient correlation mechanism)

| Node | Parents | Structural equation | Source | Evidence |
|---|---|---|---|---|
| `f_amp` | ∅ | $\mathcal{N}(0,\,\sigma_{amp}^2)$, $\sigma_{amp}\!\approx\!0.7$ | `model: draw_frailties` | shared cutaneous AMP-expression tone → correlates a subject's CAMP/HBD-3 across lesional, non-lesional, saliva, and tape-strip readouts (the primary contrast is *within-subject*, so these MUST correlate) |
| `f_th2` | ∅ | $\mathcal{N}(0,\,\sigma_{th2}^2)$ | `model: draw_frailties` | shared TH2 tone → correlates IL-13/IL-4 and (inversely) suppresses AMP |
| `f_vitd_resp` | ∅ | $\mathcal{N}(0,\,\sigma_{vd}^2)$ | `model: draw_frailties` | per-patient vitamin-D responsiveness → correlates the treatment-driven AMP change across a subject's readouts |
| `f_microbiome` | ∅ | $\mathcal{N}(0,\,\sigma_{mic}^2)$ | `model: draw_frailties` | shared colonization propensity → correlates lesional/non-lesional CFU and swab flora |
| `f_ae` | ∅ | $\mathcal{N}(0,\,\sigma_{ae}^2)$ | `model: draw_frailties` | procedural/GI AE propensity → correlates the (rare) AEs within patient (no independent-draw bug) |
| `f_dropout` | ∅ | $\mathcal{N}(0,\,\sigma_{drop}^2)$ | `model: draw_frailties` | dropout / non-return-of-drug propensity |

## Layer A — Treatment

| Node | Parents | Structural equation | Source | Evidence |
|---|---|---|---|---|
| `arm` (ARM, ARMCD) | ∅ | $\mathrm{Bern}(0.5)$ — randomized, exogenous, within each diagnostic group | `ctgov: designModule` + `protocol: §9.1` | allocation "RANDOMIZED"; "Psoriatic subjects randomized 1:1 to Vitamin D3 vs placebo" |
| `ex_regimen` (EXTRT, EXDOSE, EXDOSU, EXROUTE, EXDOSFRQ, EXSTDTC, EXENDTC, EXNDISP) | `arm` | deterministic: EXTRT = "VITAMIN D3"/"PLACEBO"; EXDOSE = 4000 if VitD else 0; EXDOSU = "IU"; EXROUTE = "ORAL"; EXDOSFRQ = "QD"; EXSTDTC = Day 0, EXENDTC ≈ Day 21; EXNDISP = 24 | `ctgov: armsInterventionsModule` + `protocol: §9.1` | "oral vitamin D3 at 4000IU"; "4000 IU/day … for 21 days (24 capsules dispensed)"; route/frequency from §9.1 |
| `ex_return` (EXNRET, EXCOMPL) | `ex_regimen`, `f_dropout` | $\mathrm{EXNRET}=\mathrm{round}(\mathrm{Binom}(24,\,q))$ with return prob $q=\sigma(-2.4+0.9\,f_{dropout})$; $\mathrm{EXCOMPL}=100\cdot(24-\mathrm{EXNRET})/21$ | `protocol: §9.5` | "unused medication returned; pill counts documented at Study Visit 3" |

## Layer Lₜ — Time-varying state (V2 baseline → V3 Day 21; recorded dates jittered, logic on nominal day)

The core mechanism is a two-timepoint AR process: **arm → serum vitamin D (Day 21) → cutaneous AMP
induction**, with TH2 suppression and microbial follow-on. Because the trial was **null/near-null**
(all posted p-values 0.12–1.0; VitD-arm AMP changes small and, in lesional AD/psoriasis, slightly
negative), the arm→AMP coefficient is small in magnitude and its sign is set by calibration to the
posted deltas (Step 6) — the *edge* (mechanistic induction) is real; the *effect size* in these
21 days is near zero.

### Drug-exposure mediator & safety labs (LB, VS, PE at V3 / Unscheduled)

| Node | Parents | Structural equation | Source | Evidence |
|---|---|---|---|---|
| `vitd_d21` (VITD @ V3) | `vitd_bl`, `arm`, `ex_return`/EXCOMPL, `f_vitd_resp` | $\mathrm{VITD}_{21}=\mathrm{vitd\_bl}+\delta_{vd}\cdot\mathbb{1}[\text{VitD3}]\cdot(\mathrm{EXCOMPL}/100)+f_{vitd\_resp}+\varepsilon$ | `paperclip [S7]` + `protocol: §11.7` | [S7] "oral supplementation and change in serum levels of vitamin D"; protocol: "vitamin D blood levels at Visits 1 and 3 to assess absorption" |
| `calcium_d21` (CALCIUM @ V3) | `calcium_bl`, `arm` | $\mathrm{clip}(0.7\,\mathrm{Ca}_0+0.3\cdot9.4+0.05\,\mathbb{1}[\text{VitD3}]+\varepsilon,\,8.4,\,10.6)$ (mild VitD rise, stays near-normal) | `protocol: Appendix II` + `model` | "serum labs creatinine, calcium (hypo/hyper)" graded; VitD3 raises calcium mildly (physiologic) |
| `creat_d21` (CREAT @ V3) | `creat_bl` | $0.8\,\mathrm{creat}_0+0.2\cdot0.8+\varepsilon$ (stable) | `model` | renal function stable over 21 days (assumption) |
| `pth_d21` (PTH @ V3) | `pth_bl`, `vitd_d21` | $\mathrm{PTH}_{21}=0.7\,\mathrm{PTH}_0-0.15\,(\mathrm{VITD}_{21}-\mathrm{vitd\_bl})+\varepsilon$ (PTH falls as vitamin D rises) | `model` | physiologic inverse vitamin-D↔PTH coupling (assumption) |
| `vitals` (VS.SYSBP, DIABP, PULSE, TEMP, RESP; VSDTC) | `age`, prior value | AR(1) around age-appropriate norms; no drug effect expected; **uncalibrated** (safety/shift tables) | `protocol: §10.1.2, §14.2.13` | "Vital signs" assessed; "vital signs + labs by descriptive stats + shift tables" |
| `pe` (PE.PEGEN, PEORAL, PEABN; PEDTC) | `diagnosis_group` | mostly "normal"; abnormal-skin flag driven by group; **uncalibrated** | `protocol: §10.1.2, Table 10.1` | "Physical and oral exam | V2 | V3" |
| `pasi` (SK.PASI @ V2, V3) | `psor_severity` (baseline), `arm` (V3) | $\mathrm{PASI}_0=f(\mathrm{psor\_severity})$ (psoriasis only); $\mathrm{PASI}_{21}=\mathrm{PASI}_0-\epsilon_{pasi}\,\mathbb{1}[\text{VitD3}]+\varepsilon$; **uncalibrated** | `protocol: §14.2.10` | "VitD3 effects on change in PASI score — 2-sample t-test" (no posted result → prior only) |
| `fitzpatrick` (SK.FITZPATRICK @ V2) | `race` | baseline-only skin-type (see L₀) | `ctgov: baselineCharacteristicsModule` | Fitzpatrick Skin Scale distribution (baseline) |

### Cutaneous AMP / cytokine at Day 21 — the endpoint substrate (BX, SAL, TS @ V3)

| Node | Parents | Structural equation | Source | Evidence |
|---|---|---|---|---|
| `camp_d21` (BX.CAMP_LES, CAMP_NONLES @ V3) | `camp_bl`, `arm`, `vitd_d21`, `il13_d21`/`il4_d21`, `diagnosis_group`, `f_vitd_resp`, `f_amp`, lesional | $\mathrm{CAMP}^{c}_{21}=\mathrm{CAMP}^{c}_0+\beta_{vd}\,\mathbb{1}[\text{VitD3}]-\theta\,\Delta\mathrm{th2}^{c}+\eta\,f_{vitd\_resp}+\varepsilon$ | `paperclip [S1][S5]` | [S1] "the cathelicidin promoter had three VDREs … VDR activation was required for expression of both antimicrobial genes" (VitD induces CAMP); [S5] IL-4/IL-13 suppress AMP |
| `hbd3_d21` (BX.HBD3_LES, HBD3_NONLES @ V3) | `hbd3_bl`, `arm`, `vitd_d21`, `il13_d21`/`il4_d21`, `f_vitd_resp`, `f_amp`, lesional | same form as `camp_d21`, HBD-3 coefficients | `paperclip [S1][S5]` | [S1] "induction of the defensin beta 4 gene (DEFB4) … VDR activation was required"; [S5] β-defensin suppressed by IL-4/IL-13 |
| `il13_d21`, `il4_d21` (BX.IL13_*, IL4_* @ V3) | `il13_bl`/`il4_bl`, `arm`, `f_th2`, lesional | $\mathrm{th2}^{c}_{21}=\mathrm{th2}^{c}_0-\phi\,\mathbb{1}[\text{VitD3}]+f_{th2}+\varepsilon$ (VitD modestly lowers TH2) | `ctgov: outcomesModule (secondary)` + `paperclip [S5]` | secondary endpoint "Change … in Relative Abundance of IL-13 mRNA"; [S5] establishes the TH2↔AMP axis |
| `sal_amp_d21` (SAL.SAL_CAMP, SAL_HBD3 @ V3) | `sal_amp_bl`, `arm`, `vitd_d21`, `f_amp` | AR update, same VitD induction term as biopsy (normalized to `sal_totprot`); **uncalibrated** | `protocol: §7.1.1, §10.2` + `paperclip [S1]` | "Expression of antimicrobial peptides (hCAP18/LL-37, HBD3) at baseline and study day 21 in psoriatic subjects' SALIVA"; [S1] VitD induction |
| `ts_amp_d21` (TS.TS_CAMP_*, TS_HBD3_* @ V3) | `ts_amp_bl`, `camp_d21`/`hbd3_d21` (biopsy gold standard), `f_amp` | $\mathrm{TS}_{21}=\gamma_0+\gamma_1\,\mathrm{biopsy\_AMP}_{21}+f_{amp}+\varepsilon$; **uncalibrated** | `protocol: §14.2.11` | "determine whether AMP levels can be accurately measured from TAPE STRIPPING (using skin punch biopsies as the gold standard)" |

### Microbial, serology, pregnancy, con-meds at Day 21 (MB, SW, LB, PT, CM @ V3)

| Node | Parents | Structural equation | Source | Evidence |
|---|---|---|---|---|
| `cfu_d21` (MB.CFU_LES, CFU_NONLES @ V3) | `cfu_bl`, `camp_d21` (higher AMP → lower CFU), `arm` (via AMP), `f_microbiome`, lesional | $\log\mathrm{CFU}^{c}_{21}=0.6\log\mathrm{CFU}^{c}_0-\rho\,\Delta\mathrm{CAMP}^{c}+f_{micro}+\varepsilon$; **uncalibrated** | `paperclip [S2]` + `protocol: §7.1.1` | [S2] AMP deficiency → *S. aureus* susceptibility; "Change in bacterial colony counts (CFU) from baseline to study day 21" |
| `sw_flora_d21` (SW.SW_FLORA @ V3) | `sw_flora`, `f_microbiome` | profile-change string; stored for future genomic analysis; **uncalibrated** | `protocol: §14.2.12` | "GENOMIC ANALYSIS of bacterial flora (skin swabs) — profile change baseline->day 21" |
| `ige_d21`, `rast_d21` (LB.IGE, RAST @ V3) | `ige_bl`/`rast`, `arm` | AR update with small VitD effect; **uncalibrated** | `protocol: §7.1.1, §14.2.9` | "Change in expression of serum total IgE and RAST from baseline and study day 21 in psoriatic subjects' serum" |
| `preg` (PT.PGRESULT, PGMETHOD, PGDTC) | `sex` | females of childbearing potential only; $\delta(\text{negative})$ (pregnancy is an exclusion) | `ctgov: eligibilityModule` + `protocol: §10.1.2` | "Pregnant or lactating females" (exclusion); "Pregnancy testing (if applicable)" |
| `cm` (CM.CMTRT, CMINDC, CMSTDTC, CMENDTC, CMONGO, CMDTC) | `mh` | monitored con-meds; many classes excluded per §9.4 → sparse; **uncalibrated** | `protocol: §9.4, §10.1.2` | "various meds withheld/excluded"; "Concomitant medications are monitored" |

### Adverse events (AE @ V2/V3/Unscheduled) — rare, low-hazard, calibrates to ZERO

| Node | Parents | Structural equation | Source | Evidence |
|---|---|---|---|---|
| `ae` (AE.AETERM, AEDECOD, AEBODSYS, AESTDTC, AEENDTC, AEDY, AESEV, AETOXGR, AEREL, AEACN, AESER, AEOUT, AEONGO) | `arm` (VitD GI class), procedures (biopsy/blood-draw/tape), `f_ae` | $\Pr(\text{AE at visit})=1-\exp(-\exp(\log h_0+f_{ae}+\log rr_{vd}\,\mathbb{1}[\text{VitD3}]+\log rr_{proc}))$ with a **very low** $h_0$; grade = FDA 1–4; AESER derived (serious only if grade 4 — none); AEREL attribution 1–5 | `ctgov: resultsSection/adverseEventsModule` + `protocol: §12, Appendix II` | ctgov: "There were no serious adverse events. No adverse events occurred at a 5% or greater frequency threshold." protocol: expected VitD3 AEs "constipation, gas, bloating"; procedural AEs "blood-draw … pain, bruising … tape … mild transient erythema … skin biopsy: pain, swelling, bleeding" |
| `ae_grade` (AETOXGR, AESEV) | `ae` | FDA Toxicity Grading Scale 1–4 (fixed function; only the underlying severity draw is a knob) | `protocol: §12.6.1` | "Severity graded 1-4 (FDA Toxicity Grading Scale … Grade 1 mild, 2 moderate, 3 severe, 4 life-threatening/death)" |

### Disposition & dose action (DS @ V3)

| Node | Parents | Structural equation | Source | Evidence |
|---|---|---|---|---|
| `disposition` (DS.DSDECOD, DSTERM, DSSTDY, DSDTC) | `f_dropout`, `ae`, `ex_return`, `serumstor` | $\Pr(\text{not completed})=\sigma(-2.6+0.8\,f_{dropout}+1.2\,\mathbb{1}[\text{drug not returned by Day 27}])$; reason ∈ {ADVERSE EVENT, PROTOCOL VIOLATION, WITHDRAWAL BY SUBJECT, SCREEN FAILURE}; else COMPLETED | `ctgov: resultsSection/participantFlowModule` + `protocol: §9.1, §14.1` | dropouts: Adverse Event 1 (Placebo AD), Protocol Violation 2, Withdrawal by Subject 3; protocol: "not returning by Day 27 => discontinued and replaced" |

## Layer Yₜ — Endpoints (deterministic from trajectory; the calibration targets)

Every endpoint is the Day-21 value minus the baseline value of a Layer-Lₜ node — never sampled
directly (calibration invariant #1). The **primary** posted endpoints are the biopsy CAMP / HBD-3
change; the **secondary** is IL-13 change; the protocol's headline contrast is *lesional-change minus
non-lesional-change* in a subject.

| Node | Parents | Structural equation | Source | Evidence |
|---|---|---|---|---|
| `d_camp` (ΔCAMP lesional & non-lesional, per group×arm) — **PRIMARY** | `camp_d21`, `camp_bl` | $\Delta\mathrm{CAMP}^{c}=\mathrm{CAMP}^{c}_{21}-\mathrm{CAMP}^{c}_0$; primary contrast $=\Delta\mathrm{CAMP}^{les}-\Delta\mathrm{CAMP}^{nonles}$ | `ctgov: outcomeMeasuresModule (primary)` | AD lesional VitD −0.4 (SD 2.8) vs placebo 0.1 (2.4), p 0.7; AD non-lesional −0.6 (2.0) vs 0.7 (2.5), p 0.12; Psoriasis lesional −0.9 (3.0) vs 0.2 (3.2) |
| `d_hbd3` (ΔHBD-3 lesional & non-lesional) — **PRIMARY** | `hbd3_d21`, `hbd3_bl` | $\Delta\mathrm{HBD3}^{c}=\mathrm{HBD3}^{c}_{21}-\mathrm{HBD3}^{c}_0$ | `ctgov: outcomeMeasuresModule (primary)` | AD lesional VitD −0.8 (2.8) vs placebo? / values per group; Non-AD 0.2 (2.8) vs 1.2 (3.2), p 0.4 |
| `d_il13` (ΔIL-13 lesional & non-lesional) — **SECONDARY** | `il13_d21`, `il13_bl` | $\Delta\mathrm{IL13}^{c}=\mathrm{IL13}^{c}_{21}-\mathrm{IL13}^{c}_0$ | `ctgov: outcomeMeasuresModule (secondary)` | AD lesional VitD −0.7 (2.8) vs placebo 1.1 (2.7), p 0.2; Psoriasis lesional −2.1 (4.6) vs −0.1 (4.1) |
| `d_il4` (ΔIL-4 lesional & non-lesional) | `il4_d21`, `il4_bl` | $\Delta\mathrm{IL4}^{c}$; **uncalibrated** (collected per objectives, not posted) | `protocol: §7.1.1` + `paperclip [S5]` | "Change in expression of TH2 cytokines IL-13 and IL-4 … in psoriatic subjects' … skin biopsies"; results posted IL-13 only |
| `d_sal_amp` (Δ saliva CAMP/HBD-3) | `sal_amp_d21`, `sal_amp_bl` | $\Delta\mathrm{SAL}$; **uncalibrated** | `protocol: §7.1.1` | "Expression of antimicrobial peptides … in psoriatic subjects' SALIVA … at baseline and study day 21" |
| `d_ts_amp` (Δ tape-strip CAMP/HBD-3) | `ts_amp_d21`, `ts_amp_bl` | $\Delta\mathrm{TS}$; **uncalibrated** (validated against biopsy via Pearson r) | `protocol: §7.1.1, §14.2.11` | "AMP … in psoriatic subjects' … skin TAPE STRIPS"; Pearson vs biopsy |
| `d_pasi` (Δ PASI) | `pasi` @ V3, @ V2 | $\Delta\mathrm{PASI}=\mathrm{PASI}_{21}-\mathrm{PASI}_0$; **uncalibrated** | `protocol: §7.1.1, §14.2.10` | "Change in PASI score from baseline and study day 21 in psoriatic subjects" |
| `d_ige`, `d_rast` (Δ IgE, ΔRAST) | `ige_d21`/`rast_d21`, `ige_bl`/`rast` | change from baseline; **uncalibrated** | `protocol: §7.1.1, §14.2.9` | "Change in expression of serum total IgE and RAST from baseline and study day 21" |
| `d_cfu` (Δ colony counts) | `cfu_d21`, `cfu_bl` | $\Delta\log\mathrm{CFU}$; **uncalibrated** | `protocol: §7.1.1, §14.2.7` | "Change in bacterial colony counts (CFU) from baseline to study day 21 in AD, non-AD, psoriatic" |
| `flora_change` (Δ swab flora profile) | `sw_flora_d21`, `sw_flora` | profile change string; **uncalibrated** (stored for future genomic analysis) | `protocol: §14.2.12` | "profile change baseline->day 21" |
| `study_disposition` (completion/analysis population) | `disposition`, trajectory | Screening / Safety / Efficacy population membership derived from disposition + presence of baseline & Day-21 biopsy | `protocol: §14.1` | "Efficacy (randomized with BOTH a baseline AND a day-21 AMP biopsy assessment)" |
| AE↔DS reconciliation | `disposition`, trajectory AEs | `sim.reconcile_ae_ds(patient)` — if disposition reason = ADVERSE EVENT, flag exactly one `AEACN="DRUG WITHDRAWN"` AE (#184) | `model: _base.TrialSim` | traceability inherited from the shared engine; keyed on the emitted DSTERM reason |

## Latent frailty roles (summary)

Shared random effects (drawn once per patient) that induce within-patient correlation across the
AMP / cytokine / assay / microbial clusters. **Origin:** all `model` — latent-effect structure;
variances are Step-6 calibration knobs (never zeroed; invariant #4).

| Frailty | Affects | Direction |
|---|---|---|
| `f_amp` | CAMP/HBD-3 across biopsy(lesional,non-lesional), saliva, tape-strip | Higher → higher baseline & post AMP across all compartments (correlates the within-subject primary contrast) |
| `f_th2` | IL-13/IL-4; inversely suppresses AMP | Higher → more TH2, lower AMP |
| `f_vitd_resp` | AMP change under VitD3 | Higher → larger cathelicidin/HBD-3 induction per unit serum vitamin D |
| `f_microbiome` | CFU lesional/non-lesional, swab flora | Higher → heavier colonization across sites |
| `f_ae` | procedural / GI adverse events | Higher → more (still rare) AEs together |
| `f_dropout` | non-completion, non-return of drug | Higher → more likely to discontinue |

## Functional notation

- $\sigma(x)=1/(1+e^{-x})$ — logistic CDF (`expit` in code); $\mathbb{1}[\cdot]$ — indicator; $\delta(\cdot)$ — point mass.
- $\mathrm{Bern}(p)$, $\mathrm{Cat}(\cdot)$, $\mathcal{N}(\mu,\sigma^2)$, $\mathrm{LogNormal}$, $\mathrm{Exp}(\cdot)$, $\mathrm{Binom}(n,p)$ — standard distributions; $\mathrm{clip}(x,a,b)$ — truncation.
- Superscript $c\in\{\text{lesional},\text{non-lesional}\}$ compartment; subscript $0$ = baseline (V2), $21$ = Day 21 (V3).
- AR(1) update: $x_{21}=\alpha\,x_0+(1-\alpha)\,\mu+\text{drug term}+\text{frailty}+\varepsilon$.
- Nominal vs recorded day: the nominal protocol day drives every equation and the change-from-baseline
  readout; the recorded (jittered) day fills date columns only, via the independent per-patient jitter
  RNG in `_base/TrialSim` (issues #182/#183).

## Field-coverage cross-check (every `crf_picks.json` field is represented)

Confirms the DAG covers the Step-2 contract row-by-row (17 forms / 106 fields). Related fields sharing
one parent set + equation form are grouped into a single node row above (mirroring the RAVE reference).

| Form | Fields | DAG node(s) |
|---|---|---|
| DM | SITEID, ARMCD, ARM, DIAGGRP, AGE, SEX, RACE, ETHNIC, COUNTRY, HEIGHT, WEIGHT, BMI, ICDTC, RFSTDTC | `site`, `arm`, `diagnosis_group`, `age`, `sex`, `race`, `ethnic`, `country`, `height`, `weight`, `bmi`, `icdtc`/`rfstdtc` |
| DC | DCDTC, DXPSOR, PSORDUR_MO, PSORSEV | `dcdtc`, `dx_psoriasis`, `psor_duration`, `psor_severity` |
| MH | MHDTC, MHTERM, MHOCCUR | `mh` |
| CM | CMDTC, CMTRT, CMINDC, CMSTDTC, CMENDTC, CMONGO | `cm` |
| EX | EXTRT, EXDOSE, EXDOSU, EXROUTE, EXDOSFRQ, EXSTDTC, EXENDTC, EXNDISP, EXNRET, EXCOMPL | `ex_regimen`, `ex_return` |
| VS | VSDTC, SYSBP, DIABP, PULSE, TEMP, RESP | `vitals` |
| PE | PEDTC, PEGEN, PEORAL, PEABN | `pe` |
| SK | SKDTC, PASI, FITZPATRICK | `pasi`, `fitzpatrick`, `skdtc` |
| PT | PGDTC, PGRESULT, PGMETHOD | `preg` |
| LB | LBDTC, LBDY, VITD, CALCIUM, CREAT, PTH, IGE, RAST, SERUMSTOR | `lbdtc`/`lbdy`, `vitd_bl`/`vitd_d21`, `calcium_bl`/`calcium_d21`, `creat_bl`/`creat_d21`, `pth_bl`/`pth_d21`, `ige_bl`/`ige_d21`, `rast`/`rast_d21`, `serumstor` |
| BX | BXDTC, BXDY, CAMP_LES, CAMP_NONLES, HBD3_LES, HBD3_NONLES, IL13_LES, IL13_NONLES, IL4_LES, IL4_NONLES, PHOTO | `camp_bl`/`camp_d21`, `hbd3_bl`/`hbd3_d21`, `il13_bl`/`il13_d21`, `il4_bl`/`il4_d21`, `photo`, `bxdtc`/`bxdy` |
| SAL | SALDTC, SAL_CAMP, SAL_HBD3, SAL_TOTPROT | `sal_amp_bl`/`sal_amp_d21`, `sal_totprot`, `saldtc` |
| TS | TSDTC, TS_CAMP_LES, TS_CAMP_NONLES, TS_HBD3_LES, TS_HBD3_NONLES | `ts_amp_bl`/`ts_amp_d21`, `tsdtc` |
| MB | MBDTC, CFU_LES, CFU_NONLES | `cfu_bl`/`cfu_d21`, `mbdtc` |
| SW | SWDTC, SWCOLLECT, SWLOC, SW_FLORA | `sw_flora`/`sw_flora_d21`, `swdtc` |
| AE | AESTDTC, AEENDTC, AEDY, AETERM, AEDECOD, AEBODSYS, AESEV, AETOXGR, AEREL, AEACN, AESER, AEOUT, AEONGO | `ae`, `ae_grade` |
| DS | DSDTC, DSDECOD, DSTERM, DSSTDY | `disposition`, `study_disposition` |
