# TLF-Level Checks

Read this file for every review. TLF checks apply even when you only have TLF outputs and no underlying data. These are the highest-yield review activities.

Reviewer mindset: "Do the reported numbers tell the same story across the submission, and can I reproduce them?"

---

## 3.1 Cross-table population and denominator consistency

This is the single most common source of high-severity findings.

| Check | Priority | Logic |
|---|---:|---|
| Randomized N consistency | High | Same N across disposition, ADSL, demographics, baseline, efficacy, CONSORT-style outputs |
| Safety N consistency | High | Safety N matches exposure, AE, death, lab/vital/ECG denominators |
| Efficacy N consistency | High | ITT/FAS/evaluable N matches primary efficacy tables and figures |
| ORR vs PFS population | High | Response-evaluable denominator explainable relative to PFS/ITT population |
| Subgroup denominator consistency | High | Subgroup Ns sum correctly when mutually exclusive; missing categories visible |
| Visit-level denominator | Medium | N at each visit aligns across endpoint, PRO, lab, summary tables using same population/window |
| Table denominator footnotes | Medium | Footnotes clearly define denominator used for percentages |

**Back-calculation check:** For each percentage, compute n = round(% × N / 100). If the back-calculated n doesn't yield an integer consistent with the reported %, flag it.

## 3.2 Disposition, protocol deviations, and exposure TLFs

| Check | Priority | Logic |
|---|---:|---|
| Disposition flow coherence | High | Randomized, treated, completed, discontinued, ongoing, deaths form coherent subject flow |
| Discontinuation reason hierarchy | High | No double-counting unless table explicitly allows multiple reasons |
| Discontinuation due to AE | High | Counts match ADAE/ADSL flags and DS source logic |
| Major protocol deviation counts | High | Deviations affecting analysis population match ADSL flags and SAP exclusion |
| Exposure summary N | High | Safety population; matches subjects with exposure records |
| Treatment duration summary | Medium | Mean/median/range reproduces from ADaM duration variables |
| Dose intensity/compliance | Medium | Categories and summaries reproduce from exposure ADaM |

## 3.3 Primary and key secondary efficacy TLFs

| Check | Priority | Logic |
|---|---:|---|
| Primary endpoint population | High | Population matches SAP and ADSL flag |
| Primary endpoint estimate | High | Reproduce treatment effect estimate, CI, p-value, model covariates, strata |
| Multiplicity logic | High | Testing hierarchy, alpha allocation, gatekeeping, p-value interpretation across endpoints/arms |
| Model specification | High | Model matches SAP: covariates, strata, link, estimand, transformation, missing data |
| Sensitivity analysis consistency | High | Sensitivity results differ for explainable reasons |
| Subgroup analyses | Medium | Forest plot Ns, estimates, CIs, interaction p-values reproduce from ADaM |
| Endpoint directionality | High | Favorable direction consistently represented across tables, figures, text |
| Analysis cutoff | High | All efficacy outputs use correct data cutoff |

**HR/CI/p-value consistency check:** For a Cox model, verify: p ≈ 2 × Phi(-|log(HR)| / SE) where SE = (log(CI_upper) - log(CI_lower)) / (2 × 1.96). Flag gross inconsistencies.

## 3.4 Time-to-event TLFs

| Check | Priority | Logic |
|---|---:|---|
| Event and censor count | High | KM table event/censor counts reproduce from ADTTE |
| Median and CI | High | Reproduce median survival/PFS and CI method |
| Hazard ratio and CI | High | Reproduce Cox model HR, CI, covariates, strata, tie-handling |
| Log-rank p-value | High | Check stratified/unstratified method against SAP |
| Numbers at risk | High | Numbers at risk reproduce from event/censor times at each time point |
| Landmark rates | Medium | Reproduce 6/12/18/24-month rates and CIs |
| Censoring footnotes | High | Rules clearly described and match ADTTE derivation |
| KM figure vs table consistency | High | HR, median, event counts, at-risk counts match between figure and table |
| Event + censored = N | High | For each arm, events + censored subjects should equal analysis N |

## 3.5 Oncology response TLFs

| Check | Priority | Logic |
|---|---:|---|
| ORR numerator and denominator | High | Responder flag matches response-evaluable or ITT denominator per SAP |
| BOR distribution | High | CR + PR + SD + PD + NE = analysis denominator |
| Confirmed vs unconfirmed | High | Table states whether confirmation required; counts match ADaM |
| DCR / CBR derivation | Medium | Correct BOR categories and minimum duration rules |
| DOR analysis set | High | DOR denominator = responders only unless otherwise specified |
| Waterfall plot consistency | Medium | Percent change values reproduce from ADTR/ADRS and align with BOR labels |
| Swimmer plot consistency | Medium | Response timing, treatment duration, progression, death, censoring match ADaM |

## 3.6 Safety TLFs

| Check | Priority | Logic |
|---|---:|---|
| Overall AE summary | High | Any AE, TEAE, SAE, Grade ≥3, related, leading to discontinuation, death counts reproduce from ADAE |
| Subject vs event count | High | Verify whether each table reports subjects, events, or both |
| SOC/PT hierarchy | High | Each subject counted once per SOC/PT at maximum severity where appropriate |
| Severity grade table | High | Max grade counts <= overall AE counts; mutually consistent |
| Related AE table | Medium | Related AEs are subset of TEAEs unless definition differs |
| SAE and fatal AE consistency | High | SAE/death tables align with disposition, death summary, narratives |
| AESI table | Medium | AESI categories match ADaM mapping and medical review definitions |
| Exposure-adjusted rates | Medium | Person-time denominator reproduces from exposure duration — use treatment duration + safety window, not study duration |
| AE sorting | Low | Sorting by frequency, SOC/PT, arm, or clinical importance matches specification |

**Safety reconciliation checks:**
- Deaths: disposition table vs AE table vs death listing vs narratives
- SAEs: AE summary vs SAE listing
- Discontinuations due to AE: disposition vs AE table
- "Any TEAE" N ≤ Safety population N
- Subjects with multiple AEs per SOC/PT counted once (not per event)
- "Leading to discontinuation", "leading to death", SAE counts are subsets of "Any TEAE"

**CQ/SMQ vs TRAE cross-table reconciliation:**

When the same preferred term (PT) appears in both a treatment-related AE table (e.g., Table S5 / "TRAE >=5%") and a custom-query or SMQ-based table (e.g., IMAE, AESI, hepatic events), perform these checks:

| Check | Priority | Logic |
|---|---:|---|
| Count difference explained by relatedness filter | High | If TRAE table shows N₁ and CQ/SMQ table shows N₂ for same PT, the difference (N₂ - N₁) should equal subjects with that PT classified as NOT RELATED but included in the CQ/SMQ search |
| Conceptual consistency | High | Flag if events in the CQ/SMQ table (e.g., "immune-mediated") are simultaneously classified as NOT RELATED — this is a definitional contradiction for mechanism-based categories |
| Footnote documentation | Medium | Both tables must have footnotes clearly defining their inclusion criteria (TRAE = relatedness filter; CQ/SMQ = term-based search regardless of causality, or requiring causality — which one?) |
| Denominator clarity | Medium | If CQ/SMQ table has a different denominator than TRAE table, explain why (e.g., restricted to subjects with baseline assessment, or safety population) |

## 3.7 Lab, vital sign, ECG, and shift TLFs

| Check | Priority | Logic |
|---|---:|---|
| Baseline and post-baseline N | High | Denominators match subjects with valid baseline + post-baseline assessments |
| Shift table symmetry | High | Row totals = column totals for same baseline category. Diagonal + off-diagonal = total |
| Worst grade table | High | Worst CTCAE grade reproduces from ADaM |
| Change from baseline summaries | Medium | Mean, SD, median, min, max reproduce from ADaM |
| PCS abnormality counts | Medium | Criteria match SAP and ADaM flags |
| Unit and test naming | Medium | Consistent across tables and listings |
| Hy's Law | High | ALT > 3×ULN + bilirubin > 2×ULN (without alk phos elevation) cases identified; narratives provided |
| Cardiac safety | High | QTc correction (Fridericia preferred per ICH E14); outlier counts (>450, >480, >500 ms; change >30, >60 ms) |
| Lab-test-specific denominator | High | Denominators often differ by test — verify baseline and post-baseline availability per test |

## 3.8 PRO/COA TLFs

| Check | Priority | Logic |
|---|---:|---|
| Compliance/completion rates | High | Match what's stated in methods |
| Responder threshold | High | Matches validated MID for the instrument |
| Missing data handling | High | Observed case, MMRM, pattern-mixture, NRI matches SAP |
| PRO completion denominator | High | Distinguish enrolled/randomized N from valid-completion N |
| Score reproduction | Medium | Reproduce from item-level data where available |

## 3.9 Broader endpoint-specific TLF checks

| TLF type | Priority | Logic |
|---|---:|---|
| Continuous endpoint table | High | Reproduce N, mean, SD, SE, median, min/max, LS mean, treatment difference, CI, p-value, model covariates. Check baseline and change-from-baseline denominators |
| Binary responder table | High | Reproduce n, N, %, risk difference/ratio/OR, CI, p-value, NRI logic |
| Ordinal/shift table | High | Row and column totals match; categories clinically and statistically correct |
| Composite endpoint table | High | Composite event count reconciles with first-component-event counts; distinguish first vs ever event |
| Recurrent-event/rate table | High | Event counts, subject counts, exposure time, rate, rate ratio, CI, offset, inclusion rule |
| Multiplicity summary table | High | Endpoint order, alpha control, adjusted vs nominal p-values, which claims are formally controlled |

## 3.10 Listings, narratives, and subject-level traceability

For full death and AE-discontinuation reconciliation procedures, see `cross_layer_workflows.md` §4.7.

| Check | Priority | Logic |
|---|---:|---|
| Death/SAE/discontinuation listings | High | Listing counts reconcile with summary tables. See `cross_layer_workflows.md` §4.7 for detailed workflow |
| Key efficacy event listing | High | PFS/OS/DOR event and censoring listings support summary tables and KM |
| Narrative consistency | Medium | CSR text does not contradict table counts, listings, or ADaM values |

## 3.11 CSR/label/cross-output consistency

| Check | Priority | Logic |
|---|---:|---|
| CSR text vs source tables | High | Every efficacy claim has supporting table with matching numbers |
| Safety claims supported | High | Every safety claim supported by corresponding safety tables |
| Significance outside hierarchy | High | No results presented as "statistically significant" outside pre-specified hierarchy |
| Cross-document number scan | High | Same metric matches across CSR body, synopsis, tables, figures, appendices, narratives, label, briefing docs |

## 3.12 Formatting and traceability

| Check | Priority | Logic |
|---|---:|---|
| Percent calculation | Medium | Correct denominator used; back-calculate n from % × N to verify integer consistency |
| Output traceability | High | Each TLF maps to a source ADaM dataset, parameter, population flag, and analysis flag — no "orphan" tables with unclear provenance |

## 3.13 FDA-style reviewer challenge questions

Ask these explicitly when reviewing key outputs:

1. Does the denominator match the intended population?
2. Are excluded subjects clearly accounted for?
3. Can the primary endpoint be reproduced from ADaM using the SAP method?
4. Do event counts, censor counts, and numbers at risk tell a coherent story?
5. Do safety counts align across AE, SAE, death, discontinuation, and narrative outputs?
6. Are missing data and ICEs handled consistently across primary, sensitivity, and supportive analyses?
7. Are subgroup results based on credible and consistent subgroup definitions?
8. Are table footnotes sufficient for independent interpretation?
9. Are differences between SDTM, ADaM, and TLF explainable by documented derivation rules?
10. If you trace one subject from TLF → ADaM → SDTM, is the lineage clear?

### Reviewer questions by output type

| Output type | Key questions |
|---|---|
| Disposition | Randomized + treated + completed + discontinued + death + follow-up = coherent flow? Reasons mutually exclusive? |
| Baseline | N matches stated population? Key model covariates present and consistent with subgroup tables? |
| Primary endpoint | Exact estimate, CI, p-value, denominator, method, missing-data rule reproducible? |
| Key secondaries | Tested in correct hierarchy? Only interpreted as confirmatory when multiplicity controlled? |
| Sensitivity | Differ for explainable reasons? ICE strategies implemented consistently? |
| Subgroups | Ns reconcile with ADSL? Missing categories visible? Interaction tests clearly nominal unless controlled? |
| Safety | AE/SAE/death/discontinuation counts reconcile across summaries, listings, narratives, disposition? |
| Labs/vitals/ECG | Denominators test-specific? Shift/outlier cells sum correctly? |
| PRO/COA | Completion and scoring rules reflected in denominator? Item-level missingness handled correctly? |
