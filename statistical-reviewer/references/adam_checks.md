# ADaM-Level Checks

Read this file when ADaM datasets are provided. Focus on whether derivations correctly implement the SAP, are traceable to SDTM, and produce reproducible results.

Reviewer mindset: "Can I independently reproduce the analysis population, endpoint, estimand, event/censoring, and key safety results?"

---

## 2.1 ADSL: subject-level analysis backbone

ADSL is the single most important dataset. Errors here propagate everywhere.

| Check | Priority | Logic |
|---|---:|---|
| One record per subject | High | ADSL has one record per USUBJID |
| Population flags vs SDTM | High | ITTFL, SAFFL, EFFFL, FASFL, response-evaluable, per-protocol flags trace to randomization, exposure, eligibility, deviations |
| Randomized N consistency | High | Randomized population matches DM/DS randomization evidence |
| Safety N consistency | High | SAFFL=Y matches subjects with any treatment exposure or SAP-defined safety criteria |
| Treatment variables | High | TRT01P/TRT01A, TRTSDT, TRTEDT, duration agree with DM and EX |
| Stratification variables | High | Randomization strata match IVRS/IWRS or source strata and TLF subgroup/stratified analyses |
| Baseline covariates | High | Key covariates used in adjusted models and subgroups are non-missing and traceable |
| Region/site/country | Medium | Consistency with SDTM site/country and planned regional subgroup definitions |
| Protocol deviation flags | High | Major deviation and exclusion flags traceable to DV or reviewer-specified data |
| Subgroup variables | High | AGE categories, sex, race, region, biomarker status, disease stage correctly derived with no unexpected missing |
| Key dates | High | TRTSDT = DM.RFSTDTC; TRTEDT, RANDDT, DTHDT verified against SDTM |

## 2.2 Treatment exposure analysis datasets

| Check | Priority | Logic |
|---|---:|---|
| Treatment start/end consistency | High | ADaM treatment dates match derived exposure period from EX/EC |
| Treatment duration | High | Recalculate duration; compare with submitted ADaM variables |
| Cumulative dose | Medium | Recalculate from source exposure records |
| Dose intensity/compliance | Medium | Numerator, denominator, planned dose, missed dose, interruption logic |
| Exposure categories | Medium | Duration categories in TLFs are mutually exclusive and exhaustive |
| Exposure after discontinuation/death | High | No invalid post-death or post-discontinuation exposure unless justified |

## 2.3 ADAE and safety event derivations

| Check | Priority | Logic |
|---|---:|---|
| TRTEMFL derivation | High | Recalculate using AE start date, treatment start, treatment end, and risk window |
| AE severity hierarchy | High | Maximum severity/grade per subject/SOC/PT used correctly in summary tables |
| Serious AE derivation | High | AESER, seriousness criteria, and ADaM SAE flags aligned |
| Related AE derivation | High | Relationship variables and treatment-related flag logic |
| AE leading to discontinuation | High | ADaM flags match AEACN, DS, and treatment discontinuation records |
| Death AE derivation | High | Fatal AE, death outcome, seriousness-death, death date, death summary aligned |
| AESI category mapping | Medium | PT/SMQ/custom concepts → AESI categories correctly mapped |
| Duplicate AE handling | Medium | Duplicate source AEs do not inflate subject/event counts |
| AE duration | Low | Recalculate when used in listings or summaries |

## 2.4 Laboratory, vital signs, ECG, and shift analyses

| Check | Priority | Logic |
|---|---:|---|
| Baseline flag (ABLFL) | High | Last valid pre-treatment assessment unless SAP specifies otherwise |
| Post-baseline flag | High | Excludes pre-treatment records and invalid assessments |
| Change from baseline | High | Recalculate CHG = AVAL - BASE and PCHG = (AVAL - BASE) / BASE * 100 |
| Worst post-baseline value | High | Worst/highest/lowest by test, subject, period correctly derived |
| Toxicity grade derivation | High | Recalculate CTCAE or lab grading where applicable |
| Shift table categories | High | Baseline and post-baseline categories match TLF shift-table cells |
| Unit conversion | High | Standardized units consistent across subjects and sites |
| PCS abnormality | Medium | Flags match thresholds and source data |
| Normal range sourcing | High | ANRHI/ANRLO correctly sourced; used consistently for shift derivations |

## 2.5 Time-to-event endpoints (ADTTE)

| Check | Priority | Logic |
|---|---:|---|
| Endpoint-specific event definition | High | PARAM/PARAMCD, CNSR, AVAL, ADT, EVNTDESC match SAP definition |
| PFS event derivation | High | PFS event supported by PD or death with correct event date |
| OS event derivation | High | OS death event supported by death source and correct date |
| Censoring reason and date | High | Recalculate censoring date and reason per SAP rules |
| New anticancer therapy censoring | High | Subsequent therapy affects PFS censoring as specified (oncology) |
| Missed assessment rules | High | PFS censoring/event rules around missing or delayed tumor assessments |
| Data cutoff handling | High | Event/censor dates do not exceed cutoff unless specified |
| Treatment arm and strata | High | Treatment and stratification variables match planned Cox/log-rank model |
| Risk-set consistency | High | Numbers at risk in KM outputs reproduce from ADTTE |
| Multiple endpoint consistency | Medium | PFS, DOR, TTD, TTNT, EFS, RFS, OS use coherent dates and censoring |
| STARTDT verification | High | Time origin (usually randomization date) matches SAP |
| CNSR coding direction | High | 0 = event, 1 = censored (confirm convention) |
| Immortal time bias | Medium | Subjects unable to experience event early due to assessment schedules |

## 2.6 Response and tumor endpoints (ADRS / ADTR)

| Check | Priority | Logic |
|---|---:|---|
| Baseline measurable disease | High | ORR response-evaluable subjects have required baseline disease status |
| Response sequence derivation | High | CR/PR/SD/PD/NE sequence follows source RS/TR/TU records |
| Confirmed response | High | Confirmation window and subsequent assessment rules applied |
| BOR derivation | High | Recalculate best overall response; compare with submitted ADRS |
| ORR flag | High | Responder flag matches BOR or confirmed response rule |
| DOR start and event date | High | DOR starts at first response, ends at PD/death or censoring per SAP |
| PFS vs response consistency | High | Subjects with PD should have corresponding PFS event or censoring rationale |
| Independent vs investigator review | High | Primary assessor source consistently used in primary endpoint derivation |
| Lesion-level traceability | Medium | ADTR lesion sums and percent changes trace to TR/TU |

## 2.7 General endpoint derivation archetypes

These make the skill therapeutic-area-independent. Recognize the archetype and apply the appropriate logic.

| Archetype | Priority | Logic |
|---|---:|---|
| Continuous longitudinal | High | Recalculate baseline, analysis visit/window, observed value, change from baseline, percent change, imputed value, model-ready flag. Examples: HbA1c, body weight, eGFR, BP, pain score, BCVA, ADAS-Cog, PANSS |
| Binary responder | High | Recalculate responder flag from component(s), threshold, visit, missing-data rule, rescue rule, ICE handling. Examples: ACR20, PASI75, >=5% weight loss, HbA1c <7%, remission |
| Ordinal/shift | High | Category ordering, baseline vs post-baseline category, shift derivation, responder dichotomization, worst/best category |
| Time-to-first-event | High | Event flag, event date, time-to-event, censor date/reason, first-event rule, component. Examples: MACE, renal composite, relapse, hospitalization, flare, death |
| Composite | High | Composite event = first qualifying component; reconcile component counts vs composite counts; no double-counting |
| Recurrent-event/count | High | Event count, observation/exposure time, offset, inclusion rules, rate denominator. Examples: exacerbations, hospitalizations, infections |
| PRO/COA | High | Score from item-level data, valid assessment rules, missing item handling, MID threshold, completion-based denominator |
| Safety | High | TEAE, SAE, AESI, grade, discontinuation due to AE, lab shift, PCS abnormality, ECG outlier, exposure-adjusted rate |
| Biomarker/subgroup | Medium | Subgroup flag source, cutoff, assay, missing/unknown category, consistency across efficacy/safety outputs |

## 2.8 Missing data, intercurrent events, and estimand implementation

| Check | Priority | Logic |
|---|---:|---|
| Missing endpoint values | High | Missing primary/secondary endpoint records by arm, visit, reason |
| Imputation flag traceability | High | Imputed values flagged and traceable to imputation source/rule |
| ICE handling | High | Death, discontinuation, rescue, prohibited med, COVID, new therapy handled per estimand |
| Treatment policy vs hypothetical strategy | High | ADaM variables support the chosen estimand strategy |
| Sensitivity analysis datasets | High | Differ from primary only as specified |
| Tipping point / MI reproducibility | Medium | Imputation seeds, model variables, classes, missingness assumptions |
| Differential missingness | High | >15% missing in either arm or >5% absolute difference between arms for primary endpoint |
| Informative censoring | Medium | Compare baseline characteristics of censored vs non-censored |

## 2.9 ADaM reproducibility

| Check | Priority | Logic |
|---|---:|---|
| Reproducibility from ADaM only | High | Key TLFs (primary endpoint, AE summary, disposition) reproducible from ADaM datasets without hidden derivations, external lookups, or undocumented filtering |

## 2.10 Population, estimand, and denominator registry

Build registries before reviewing TLFs. Templates and detailed instructions are in `cross_layer_workflows.md` §4.2–4.6. Use those templates; this section lists what to capture from ADaM specifically.

| ADaM source | What to extract for the registry |
|---|---|
| ADSL population flags | All flags (ITTFL, SAFFL, FASFL, EFFFL, PPROTFL, endpoint-evaluable, biomarker-evaluable, PRO-evaluable, lab-evaluable) with Ns per arm |
| Endpoint ADaM analysis flags | ANL01FL, CRIT1FL, responder flags — verify each flag's denominator matches the corresponding TLF |
| ADSL + SAP | ICE handling rules, missing-data methods, model specifications, multiplicity hierarchy — populate the registries in `cross_layer_workflows.md` §4.5–4.6 |

## 2.11 Reviewer challenge analyses

| Check | Priority | Logic |
|---|---:|---|
| All-randomized/all-treated rerun | High | If primary excludes subjects, rerun in broader population; list excluded subjects/reasons |
| Alternative strata rerun | Medium | Compare randomization strata vs eCRF/source strata when discrepancies exist |
| Alternative window rerun | Medium | Rerun with stricter and wider visit windows to assess sensitivity |
| Alternative missing-data rerun | High | Compare primary method with observed case, NRI/worst case, return-to-baseline, tipping point |
| Alternative censoring rerun | High | Compare censoring around missed visits, rescue/switching, lost follow-up, post-discontinuation events |
| Subject influence check | Medium | Whether primary/key result changes materially when small number of discrepant subjects are corrected or excluded |
