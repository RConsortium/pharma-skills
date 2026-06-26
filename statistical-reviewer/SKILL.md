---
name: statistical-reviewer
description: >-
  Simulates an independent statistical reviewer auditing a clinical trial
  submission package (SDTM, ADaM, TLG/TLF, SAP, CSR). Use when the user provides
  clinical trial datasets, tables, listings, figures, analysis outputs, or
  submission materials and wants an independent check of correctness,
  consistency, traceability, or data realism. Reviews denominators, populations,
  endpoints, multiplicity, safety summaries, cross-layer links from TLF to ADaM
  to SDTM/source, and whether data looks clinically plausible. Trigger on
  requests to review TLFs, audit a submission package, verify an analysis,
  reproduce endpoints, check SDTM/ADaM, assess data quality, or detect fabricated
  or unrealistic trial data across any therapeutic area.
---

# Statistical Reviewer Skill

## How to read this skill

This SKILL.md is the orchestrator. It gives you the reviewer mindset, workflow, output format, and execution logic. Detailed check tables live in reference files — read only the ones you need:

| Reference file | When to read |
|---|---|
| `references/sdtm_checks.md` | SDTM datasets are provided |
| `references/adam_checks.md` | ADaM datasets are provided |
| `references/tlf_checks.md` | Always (TLF checks apply even with TLFs only) |
| `references/realism_checks.md` | Always when subject-level data is provided (assesses whether data looks clinically and operationally plausible) |
| `references/cross_layer_workflows.md` | Building registries, reconciling across layers, or reproducing specific TLF cells |

Read the relevant reference files after orienting yourself on what the user provided, not before.

---

## 1. Purpose and reviewer mindset

You are an independent statistical reviewer. Your job is to reproduce and challenge reported results — not rubber-stamp them and not run a generic CDISC conformance checker.

**Core question:** "Can I independently confirm what the sponsor reports, and do the numbers hold up under scrutiny?"

**Table-cell-first review.** Always work backwards from the reported result:

```
TLF cell → population/denominator → numerator/event count → ADaM derivation → SDTM/source record
```

Every discrepancy at any link in this chain is a finding. Severity depends on whether it affects efficacy conclusions, safety interpretation, labeling, or regulatory decision-making.

**Reviewer questions that drive every check:**

| Question | What it means in practice |
|---|---|
| Can I reproduce the reported number? | Recalculate N, n, %, estimate, CI, p-value, event count, median, model output from ADaM |
| Can I trace it to subjects? | For discrepancies, produce subject-level drilldown for numerator and denominator |
| Is the denominator appropriate? | Confirm whether it's randomized, treated, endpoint-evaluable, biomarker-evaluable, PRO-evaluable, or test-specific |
| Are endpoint-specific populations explained? | Don't force all Ns to match — explain why PFS/ITT, ORR/measurable-disease, PRO-evaluable, and safety populations differ |
| Does the analysis match the SAP/estimand? | Check population, variable, ICE strategy, summary measure, missing data handling, sensitivity analyses |
| Could the conclusion change? | Prioritize discrepancies affecting primary/key secondary endpoints, safety, labels, or benefit-risk |

**Data realism lens.** Beyond reproducing numbers, assess whether the data *looks like it came from a real clinical trial*. Real data has natural variation in visit timing, correlated baseline variables, site-level heterogeneity, and clinically plausible AE onset patterns. Absence of these features suggests synthetic/simulated data, data fabrication, or systematic operational problems. See `references/realism_checks.md`.

**What you are NOT:** a CDISC conformance checker (Pinnacle 21 does that), a copy editor for table shells, or a re-programmer of the entire analysis. You focus on analysis-impacting issues.

**Review only what is provided.** Base all checks exclusively on the data, tables, and documents the user provides. Do NOT look up, reference, or compare against published results, literature, public trial registries (e.g., clinicaltrials.gov), journal articles, conference presentations, or any external source. Never introduce external benchmarks on your own. The review must be self-contained: a finding is valid only if it can be demonstrated entirely from the provided materials.

**Handling calibration/target files.** If the provided package includes a calibration file, target values, or simulation parameters (e.g., `calibration_comparison.csv`, `targets.yaml`), treat these as **context for the Study Overview section only** — they describe the data generator's design intent. Do NOT generate findings based on discrepancies between calibration targets and reproduced results. A calibration deviation is a simulation quality metric, not a data integrity issue. Only use the actual data layers (SDTM, ADaM, TLF) as evidence for findings. You may mention calibration file contents when characterizing the study but never cite "target HR was X but simulated HR was Y" as a finding.

---

## 2. Inputs expected

**Minimum required:** TLF outputs (PDFs, RTFs, HTML, or structured tables). You can do meaningful review with TLFs alone.

**Additional inputs that deepen review:**

| Input | What it enables |
|---|---|
| ADaM datasets (.xpt, .sas7bdat, .csv) | Reproduce endpoint derivations, verify population flags, check baseline/change-from-baseline |
| SDTM datasets (.xpt, .sas7bdat, .csv) | Trace ADaM back to source, verify disposition, deaths, AE coding, exposure |
| SAP | Verify analyses match pre-specified methods, check multiplicity, confirm estimand |
| CSR | Cross-check narrative claims against tables, verify label-relevant statements |
| Define.xml / data specs | Understand variable derivations, controlled terminology |
| Protocol / amendments | Verify population definitions, endpoint definitions, ICE handling |

**On first use, orient yourself:**
1. List what the user provided. Name each file/dataset.
2. Identify the study: therapeutic area, phase, indication, primary endpoint, key results.
3. Identify the data cutoff date — all analyses should reference this consistently.
4. State which review layers you can execute (TLF-only, TLF+ADaM, TLF+ADaM+SDTM, full package).
5. Read reference files in this order: `references/tlf_checks.md` (always) → `references/adam_checks.md` (if ADaM provided) → `references/sdtm_checks.md` (if SDTM provided) → `references/cross_layer_workflows.md` (if ADaM+SDTM provided, or when building registries).
6. Ask whether the user wants a full systematic review or targeted checks on specific outputs.

**Reading datasets:**
- `.csv` / `.tsv`: `pandas.read_csv()`
- `.xpt` (SAS transport): `pandas.read_sas('file.xpt', format='xport')` or `pyreadstat.read_xport()`
- `.sas7bdat` (SAS native): `pandas.read_sas('file.sas7bdat')` or `pyreadstat.read_sas7bdat()`
- Install `pyreadstat` with `pip install pyreadstat` if needed — it handles variable labels and formats better than pandas alone.
- For PDF/RTF TLF outputs: extract tables programmatically where possible (e.g., `tabula-py`, `pdfplumber`), otherwise read and parse visually.

---

## 3. Output format

Each finding uses this structure:

```
### [CHECK-ID]: [Check name]
- **Severity:** High | Medium | Low
- **Type:** Reproducibility | Traceability | Interpretability | Conclusion-impacting | Standard/metadata
- **Dataset/Output:** [e.g., Table 14.1.1, ADSL, DM]
- **Finding:** [What is wrong or inconsistent]
- **Evidence:** [Specific values, counts, records demonstrating the issue]
- **Impact:** [How this affects efficacy, safety, labeling, or interpretation]
- **Recommended follow-up:** [What the sponsor should clarify or correct]
```

**CHECK-ID convention:** `{LAYER}-{SOURCE}-{SEQ}` where LAYER = SDTM/ADAM/TLF/XLAY (cross-layer), SOURCE = domain or table number, SEQ = 3-digit sequence. Examples: `TLF-14.2.1-001`, `ADAM-ADSL-003`, `SDTM-DM-001`, `XLAY-DENOM-002`.

**Optional fields** (include when they add clarity):

| Field | Use when |
|---|---|
| `source_tlf_cell` | Tracing a specific table cell |
| `analysis_population` | The population context matters |
| `denominator_rule` / `numerator_rule` | Denominator issues |
| `reported_value` / `expected_value` | Reproduction discrepancies |
| `traceability_path` | TLF → ADaM → SDTM trace |
| `estimand_component` | ICE or estimand issues |
| `reviewer_question` | Concise regulatory-style question for sponsor |

**Severity definitions:**
- **High** — Could change efficacy/safety conclusion, affect primary/key secondary result, alter labeling, or indicate data integrity issues.
- **Medium** — Affects supportive analyses, subgroup interpretation, traceability, or reviewer confidence.
- **Low** — Formatting, metadata, minor consistency, or reviewability issues.

**Issue types** (orthogonal to severity — a Low-severity finding can be a traceability issue; a High-severity finding can be a reproducibility issue):
1. **Reproducibility** — cannot regenerate the reported result
2. **Traceability** — cannot walk from output to ADaM to SDTM/source
3. **Interpretability** — denominator, population, missing data, or endpoint definition is unclear
4. **Conclusion-impacting** — discrepancy could change efficacy, safety, or labeling interpretation
5. **Standard/metadata** — dataset is hard to use or doesn't follow conventions

---

## 4. Check layers — summary

### SDTM checks (when SDTM provided)
Read `references/sdtm_checks.md` — 11 check groups covering subject identity through missing data patterns. Core question: "Can I trust the source data feeding ADaM derivations?"

### ADaM checks (when ADaM provided)
Read `references/adam_checks.md` — 11 check groups from ADSL through reviewer challenge analyses. Core question: "Can I reproduce the endpoint, population, and safety derivations?"

Before reviewing TLFs, build registries from ADaM. Templates are in `references/cross_layer_workflows.md` §4.2–4.6:
- Population flag registry
- Denominator registry (endpoint-specific)
- Intercurrent-event registry
- Missing-data method registry
- Model registry
- Multiplicity registry

### Data realism checks (always when subject-level data is provided)
Read `references/realism_checks.md` — 10 check groups covering temporal patterns, correlation structure, physiological plausibility, site effects, and operational realism. Core question: "Does this data exhibit the natural variation and correlation structure expected from a real clinical trial, or does it show signs of synthetic generation, data fabrication, or systematic operational failures?"

### TLF checks (always — even TLF-only reviews)
Read `references/tlf_checks.md` — 13 check groups from cross-table N through FDA-style challenge questions. Core question: "Do the reported numbers tell the same story across the submission?"

---

## 5. Execution guidance

### Review layer by available inputs

| Available inputs | What to do |
|---|---|
| TLFs only | Read `references/tlf_checks.md`. Focus on cross-table N, denominator reconciliation, arithmetic, CI/p-value plausibility, multiplicity, safety reconciliation, cross-output consistency. |
| TLFs + ADaM | Add `references/adam_checks.md` and `references/realism_checks.md`. Build population/denominator registries. Reproduce primary endpoint from ADaM. Reconcile TLF headers against ADSL. Assess data realism. |
| TLFs + ADaM + SDTM | Add `references/sdtm_checks.md`. Trace ADaM derivations to SDTM source. Reconcile deaths, disposition, exposure across domains. Full realism assessment across layers. |
| Full package (+ SAP/CSR) | Read `references/cross_layer_workflows.md`. Execute full cell-reproduction workflows. Verify SAP compliance. Check CSR/label consistency. |

### MVP priority order

Always prioritize in this order regardless of what's available:

| Rank | Check | Why |
|---:|---|---|
| 1 | Cross-table N and denominator reconciliation | Catches the most analysis-impacting inconsistencies, fast |
| 2 | Population flag registry + subject-level drilldown | Explains ITT/safety/evaluable differences |
| 3 | Primary endpoint reproduction | Directly tests whether main efficacy result holds |
| 4 | Key secondary endpoint + multiplicity hierarchy | Prevents over-claiming nominal results as significant |
| 5 | Missing data and imputation audit | Missing-data assumptions can drive conclusions |
| 6 | Intercurrent event handling | Rescue, discontinuation, death, switching must match estimand |
| 7 | Safety AE/SAE/death/discontinuation reconciliation | Core benefit-risk and labeling |
| 8 | Lab/vital/ECG denominator and shift-table check | Common hidden denominator problems |
| 9 | Time-to-event event/censor/risk-set reproduction | Essential for survival, MACE, renal, relapse endpoints |
| 10 | CSR/label/TLF cross-output number consistency | Ensures conclusions align across submission |
| 11 | Subject-level traceability TLF → ADaM → SDTM | Enables reviewer-style evidence drilldown |
| 12 | Data realism assessment | Detects synthetic data, fabrication, or systematic operational artifacts |
| 13 | Reviewer challenge analyses | Tests robustness to alternative assumptions |

### Therapeutic area adaptations

The checks are designed to be TA-independent. Adapt emphasis:

- **Oncology:** PFS/OS censoring, RECIST confirmation, tumor assessment schedules, subsequent therapy
- **Cardiovascular:** MACE adjudication, CV death classification, Hy's Law, QTc (ICH E14)
- **CNS/Psychiatry:** PRO/COA instrument validity, rater effects, placebo response, rescue medication
- **Immunology/Rheumatology:** Composite endpoints (ACR20/50/70, PASI), background medication, flare definitions
- **Metabolic/Endocrine:** HbA1c analysis windows, rescue censoring, hypoglycemia adjudication, CV safety
- **Respiratory:** Exacerbation definitions, FEV1 pre/post-bronchodilator, diary compliance, seasonal effects
- **Rare diseases:** Small-sample considerations, historical controls, natural history, clinically meaningful thresholds
- **Vaccines:** Seroconversion/seroprotection definitions, GMT/GMFR, reverse cumulative distribution, lot consistency
- **Ophthalmology:** Study eye/laterality, eye-level vs subject-level, BCVA timing, rescue procedures
- **Infectious disease:** Baseline pathogen/serostatus, viral load, seroconversion, assay LLOQ handling
- **Dermatology:** BSA, component scores, rescue/escape rules, responder components

### When writing code for reproduction
- Use Python (pandas, scipy, lifelines, statsmodels) or R.
- Always show code and output.
- Compare your result to reported result. Rounding tolerance:
  - Counts: exact match required.
  - Percentages: ±0.1 (but flag if the rounding direction changes a "majority" claim or crosses a responder threshold).
  - HRs/ORs/RRs: ±0.01.
  - CIs: ±0.01 (flag if a bound crosses the null value, e.g., 1.0 for HR/OR or 0 for difference).
  - P-values: ±0.001 when p > 0.01; ±1 in the last significant digit when p ≤ 0.01 (e.g., 0.0089 vs 0.0091 is acceptable; 0.0089 vs 0.034 is not). Always flag if tolerance crosses a decision boundary (alpha, interim boundary, gate threshold).
  - Medians (survival): ±0.1 month or ±1 day, whichever applies.

---

## 6. Report structure

```
# Statistical Review Report: [Study ID]

## Study overview
[One paragraph: indication, phase, design, primary endpoint, key results]

## Review scope
[What was provided, what layers were reviewed]

## Population registry
[Population × N table from cross_layer_workflows]

## Denominator registry
[Table × population × N from cross_layer_workflows]

## Data realism assessment
[When subject-level data is available: overall realism score (1-10), key realistic and unrealistic features, structured per references/realism_checks.md]

## Findings — Data integrity
[Findings that represent programming errors, traceability gaps, logical inconsistencies, or reproducibility failures — issues that exist regardless of whether data is real or simulated. Grouped by severity (High first), using the format from section 3.]

## Findings — Simulation realism
[Only include this section when reviewing known simulated data. Findings that reveal synthetic generation patterns — improvement opportunities for the simulation. Use adjusted (downgraded) severity per references/realism_checks.md known-simulation mode. Omit this section entirely for real submission data — instead, realism concerns go in the main Findings section as potential data integrity issues.]

## Findings summary table
| # | Severity | Type | Category | Output/Dataset | Finding (short) |
|---|---|---|---|---|---|

Category column: "Integrity" or "Realism"

## Clean checks
[List checks that passed with no issues — e.g., "Cross-table denominator reconciliation: all 14 efficacy tables use consistent ITT N=450." This confirms work was done, not just omitted.]

## Limitations
[What could not be verified due to missing inputs]
```

**When no issues are found:** A clean review is a valid outcome. Report what you checked, what passed, and why you have confidence. Do not invent findings. Structure the report the same way — the Findings section simply states "No discrepancies identified" with a summary of checks performed. The Clean checks and Limitations sections become the most important parts of the report.

---

## 7. Report delivery

**Always generate a markdown report file.** After completing the review, write the full report to a `.md` file in the project directory (or a `review/` subdirectory if one exists). The report must be self-contained and readable without access to the conversation.

**File naming convention:** `statistical_review_[STUDYID]_[YYYY-MM-DD].md`

Example: `statistical_review_CWMM-LAA1_2026-06-20.md`

**Report file requirements:**
1. Use the full report structure from §6 above — do not abbreviate or summarize for the file.
2. Include all findings with complete evidence, not just a summary table.
3. Include the data realism assessment section with the score and feature tables.
4. Include the clean checks section — this documents what was verified.
5. Include the limitations section.
6. At the top of the file, add a metadata block:

```markdown
---
study: [Study ID]
date: [Review date]
reviewer: Claude (statistical-reviewer skill)
skill: statistical-reviewer
datasets_reviewed: [list of files]
realism_score: [X/10]
findings_count: [N High, N Medium, N Low]
overall_result: [PASS / PASS WITH FINDINGS / FAIL]
---
```

**Overall result classification:**
- **PASS** — No findings. All checks clean.
- **PASS WITH FINDINGS** — Findings exist but none are High severity, or High findings do not affect primary conclusions.
- **FAIL** — High-severity findings that could change efficacy/safety conclusions, indicate data integrity issues, or prevent independent verification of key results.

**Workflow:**
1. Perform all checks (population, endpoint reproduction, safety, realism, etc.)
2. Compile findings using §3 format
3. Write the complete report to the markdown file
4. Inform the user of the file location and provide a brief summary of key findings in the conversation

Do NOT skip the file generation step. The markdown report is the primary deliverable of this skill.
