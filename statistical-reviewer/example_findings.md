# Example Statistical Reviewer Findings

These are realistic findings a statistical reviewer would produce when auditing a clinical trial submission package. Each illustrates a common class of error with enough detail for an AI agent to recognize similar patterns. Findings span oncology, metabolic, CNS, cardiovascular, PRO/COA, and respiratory therapeutic areas. Some include optional fields (`traceability_path`, `reported_value`/`expected_value`, `reviewer_question`) to demonstrate their use.

---

### F-001: ITT population N mismatch across efficacy tables
- **Severity:** High
- **Type:** Reproducibility
- **Dataset/Output:** Table 14.1.1 (Disposition) vs. Table 14.2.1 (Primary Endpoint)
- **Finding:** The ITT population in the disposition summary (N=450 total: 225 active, 225 placebo) differs from the primary endpoint table header (N=448 total: 224 active, 224 placebo) with no documented exclusion criteria for the 2-subject difference.
- **Evidence:** Table 14.1.1 reports 225 randomized subjects per arm. Table 14.2.1 header shows N=224 per arm. No footnote explains the exclusion. ADSL shows ITTFL="Y" for 450 subjects, but the ADTTE analysis dataset contains 448 records.
- **Impact:** Two subjects' primary endpoint data are silently excluded. If both were events in the active arm, the hazard ratio shifts from 0.72 to 0.70 — a small but non-trivial difference that must be explained. Unexplained population exclusions undermine the ITT principle and raise data integrity concerns during regulatory review.
- **Recommended follow-up:** Identify the 2 excluded subjects by USUBJID. Document the reason for exclusion (e.g., no post-randomization assessment). If exclusion is justified, add a footnote to Table 14.2.1. If unjustified, rerun the analysis with all 450 subjects.
- **traceability_path:** Table 14.2.1 header N → ADTTE record count → ADSL ITTFL → DM randomization
- **reviewer_question:** Please provide the USUBJIDs excluded from the primary analysis and the documented reason for each exclusion.

**Why this matters:** Denominator mismatches are the most common high-severity finding in statistical reviews. A reviewer builds a "population registry" — a single reference table of Ns by population — and checks every table header against it. Even a 1-subject discrepancy requires documentation because it signals either a derivation error or an undocumented analysis decision.

---

### F-002: Treatment-emergent AE flag misclassified for 12 subjects
- **Severity:** High
- **Type:** Reproducibility
- **Dataset/Output:** ADAE, Table 14.3.1 (Overall AE Summary)
- **Finding:** 12 subjects have AEs flagged as treatment-emergent (TRTEMFL="Y") despite onset dates preceding the first dose of study drug by 2–14 days. This inflates the TEAE incidence in the active arm.
- **Evidence:** ADAE records for USUBJID IN (S-001-042, S-003-108, ..., S-012-291) show ASTDT < TRTSDT (from ADSL). Example: S-001-042 has ASTDT=2023-03-01 and TRTSDT=2023-03-15, a 14-day pre-treatment onset, yet TRTEMFL="Y". Ten of 12 subjects are in the active arm. The affected AEs include headache (4), nausea (3), fatigue (3), diarrhea (2).
- **Impact:** The "Any TEAE" rate in the active arm drops from 78.2% (176/225) to 73.8% (166/225) after correction. Several PT-level incidence rates also decrease. This misclassification overstates the safety burden of the active treatment and could affect benefit-risk interpretation and labeling language.
- **Recommended follow-up:** Review the TRTEMFL derivation program. Correct TRTEMFL for these 12 subjects. Regenerate all safety summary tables. Verify that the TEAE window logic (onset >= TRTSDT and onset <= TRTEDT + safety follow-up) is implemented correctly.

**Why this matters:** TRTEMFL is a critical safety derivation. Pre-treatment AEs classified as treatment-emergent artificially increase the apparent toxicity of the study drug. Reviewers cross-check ASTDT against TRTSDT for a sample of TEAE records — systematic misclassification suggests a programming error in the derivation rather than isolated data entry issues.

---

### F-003: PFS censoring rule does not match SAP
- **Severity:** High
- **Type:** Conclusion-impacting
- **Dataset/Output:** ADTTE (PFS endpoint), SAP Section 5.2.1
- **Finding:** The SAP specifies censoring at the date of last adequate tumor assessment for subjects without progression or death. The ADTTE dataset instead censors at the date of last contact (from DM.RFPENDTC), resulting in inflated censoring times for 38 subjects who discontinued treatment early without a final scan.
- **Evidence:** SAP Section 5.2.1 states: "Subjects without documented progression or death will be censored at the date of last adequate radiographic assessment." ADTTE records for 38 subjects show ADT = DM.RFPENDTC (last contact) rather than the date of their last tumor scan (from ADRS/TU). Median difference: 47 days (range: 8–142 days). Example: S-007-155 had last scan on 2023-06-15 but last contact on 2023-10-05; ADTTE uses the later date, adding 112 censored days.
- **Impact:** Using last contact instead of last adequate assessment inflates censoring times, which can bias PFS results. The effect depends on the distribution of early discontinuations across arms. If more subjects discontinued early in the control arm (common with active comparators), this could artificially narrow the treatment difference. The primary PFS analysis should be reproduced with correct censoring.
- **Recommended follow-up:** Rederive the PFS censoring date using last adequate tumor assessment per SAP. Rerun the primary PFS analysis (Cox model, KM estimates, log-rank test). Compare results to assess sensitivity to the censoring rule.

**Why this matters:** PFS censoring rules are one of the most scrutinized aspects of oncology trials. FDA reviewers routinely reproduce PFS analyses with different censoring schemes. A mismatch between SAP-specified and implemented censoring rules is a major finding because it calls into question whether the reported PFS result reflects the pre-specified analysis.

---

### F-004: Hazard ratio CI inconsistent with reported p-value
- **Severity:** High
- **Type:** Reproducibility
- **Dataset/Output:** Table 14.2.1 (Primary PFS Analysis)
- **Finding:** The reported HR = 0.74, 95% CI (0.56, 0.98), p = 0.0089 is internally inconsistent. A CI upper bound of 0.98 (barely excluding 1.0) corresponds to a p-value near 0.035–0.04, not 0.0089.
- **Evidence:** For a Cox model HR of 0.74 with 95% CI (0.56, 0.98), the Wald-based two-sided p-value is approximately 2 * (1 - Phi(|log(0.74)| / SE)) where SE = (log(0.98) - log(0.56)) / (2 * 1.96) ≈ 0.142. This yields p ≈ 0.034. The reported p = 0.0089 would require a narrower CI, approximately (0.56, 0.93). Either the CI or the p-value is incorrect.
- **Impact:** If the p-value is correct (p=0.0089), the CI is misprinted and should be narrower. If the CI is correct, the true p-value (~0.034) is still significant at alpha=0.05 but the margin of significance is much thinner than reported. This directly affects the strength of the efficacy claim and could change the interpretation of key secondary endpoints gated behind this primary test.
- **Recommended follow-up:** Rerun the Cox proportional hazards model and report the exact HR, CI, and p-value from the model output. Verify whether the issue is a reporting error (misaligned rows in the output) or a programming error.
- **reported_value:** HR=0.74, 95% CI (0.56, 0.98), p=0.0089
- **expected_value:** If CI is correct → p ≈ 0.034; if p is correct → CI ≈ (0.56, 0.93)
- **reviewer_question:** Please provide the SAS/R log output from the Cox model used for Table 14.2.1, including the exact HR, CI, and p-value as output by the procedure.

**Why this matters:** Reviewers routinely cross-check HR/CI/p-value consistency using the relationship: p ≈ 2 * Phi(-|log(HR)|/SE) where SE is estimated from the CI width. A mismatch usually indicates either (a) a cut-and-paste error from the wrong model run, (b) CI and p-value from different models (e.g., stratified vs. unstratified), or (c) a programming error. Any of these requires resolution before the result can be accepted.

---

### F-005: Key secondary endpoint reported as "significant" despite primary gate failure
- **Severity:** High
- **Type:** Conclusion-impacting
- **Dataset/Output:** Table 14.2.3 (ORR Analysis), CSR Section 11.3
- **Finding:** The CSR states "ORR was significantly higher in the active arm (42.3% vs. 28.1%, p=0.002)." However, ORR is the second endpoint in the fixed-sequence testing hierarchy, gated behind PFS. The primary PFS analysis yielded p=0.034 against a pre-specified interim-spending-adjusted boundary of alpha=0.025 (one-sided), meaning the PFS gate did not formally open.
- **Evidence:** SAP Section 3.1 specifies a fixed-sequence hierarchy: PFS (primary) → ORR (key secondary) → OS (key secondary). The PFS one-sided p-value of 0.017 (two-sided p=0.034) exceeds the O'Brien-Fleming boundary of alpha=0.015 at this interim analysis. The ORR result therefore cannot be declared statistically significant under the pre-specified multiplicity strategy, regardless of its nominal p-value.
- **Impact:** Reporting ORR as "significant" in the CSR is a multiplicity violation. This could lead to incorrect labeling claims and would be flagged by FDA statistical reviewers. The ORR result should be reported as "nominal p=0.002" with a footnote clarifying that the hierarchical gate was not met.
- **Recommended follow-up:** Revise CSR language to present ORR as a descriptive/nominal result. Update all tables and figures to remove significance indicators (asterisks, "significant" labels) from ORR results. Review whether any other downstream endpoints are similarly affected.

**Why this matters:** Multiplicity violations are among the most consequential regulatory findings. They can delay approval, require advisory committee discussion, or result in more conservative labeling. Reviewers map the full testing hierarchy from the SAP and verify each gate sequentially. Sponsors sometimes present nominal p-values for gated endpoints without adequately noting the gate failure — a reviewer must catch this.

---

### F-006: Baseline value derived from post-dose assessment for 23 subjects
- **Severity:** Medium
- **Type:** Traceability
- **Dataset/Output:** ADLB (HbA1c endpoint), ADSL
- **Finding:** For 23 subjects, the baseline HbA1c value (BASE in ADLB, PARAMCD="HBA1C") corresponds to a lab sample collected 1–5 days after the first dose, not the last pre-dose value as specified in the SAP.
- **Evidence:** SAP Section 4.3.1: "Baseline is defined as the last non-missing assessment on or before the date of first dose." For 23 subjects, ADLB.ADT for the baseline record (ABLFL="Y") is after ADSL.TRTSDT. Example: S-004-067 has TRTSDT=2023-04-01 and baseline HbA1c dated 2023-04-03. In 18 of 23 cases, the pre-dose HbA1c value exists in the source data but was not selected as baseline.
- **Impact:** Post-dose baseline values can incorporate early drug effect, artificially reducing the change from baseline and biasing the efficacy estimate. For HbA1c, even 1–5 days of treatment unlikely changes values meaningfully, but the derivation error may affect other endpoints using the same baseline logic. The direction of bias (toward or away from the drug) depends on whether the drug improves or worsens the lab parameter quickly.
- **Recommended follow-up:** Correct the baseline derivation to select the last pre-dose value. Rerun the primary HbA1c analysis. Audit other ADaM datasets (ADVS, ADEG, ADQS) for the same baseline timing error, as they likely use the same macro.

**Why this matters:** Baseline derivation errors are systematic — they typically come from a shared macro applied across datasets. Finding the error in one dataset (ADLB) means every other dataset using that macro needs checking. The SAP usually specifies "last non-missing on or before first dose," and reviewers verify this by comparing ABLFL-flagged records against TRTSDT. Even if the bias is small for one parameter, the pattern erodes confidence in all derived endpoints.

---

### F-007: Death count discrepancy across domains
- **Severity:** High
- **Type:** Traceability
- **Dataset/Output:** DM, DS, AE (SDTM); ADSL (ADaM); Table 14.1.2 (Disposition), Table 14.3.1 (AE Summary)
- **Finding:** Death counts are inconsistent: DM.DTHFL="Y" for 34 subjects, DS shows 31 subjects with disposition of death, AE shows 29 fatal AEs (AEOUT="FATAL"), ADSL.DTHFL="Y" for 33 subjects, the disposition table reports 32 deaths, and the AE summary reports 28 deaths leading to death.
- **Evidence:** Reconciliation by USUBJID: 28 subjects are consistently dead across all sources. 3 subjects are dead in DM but have no fatal AE (plausible — deaths can occur without an AE record if unrelated to study). 2 subjects are dead in DM/ADSL but show "Completed" in DS (error). 1 subject has a fatal AE but DTHFL="N" in DM (error). The disposition table appears to count DS deaths (31) plus 1 ADSL-only death but misses 2 DM-only deaths.
- **Impact:** Inconsistent death counts raise data integrity concerns and directly affect OS analysis (if applicable), overall mortality reporting in the safety database, and CSR/labeling statements about treatment-related deaths. Every death must be reconciled across all data sources.
- **Recommended follow-up:** Produce a subject-level death reconciliation listing showing the death status across DM, DS, AE, and ADSL for all subjects flagged as dead in any source. Resolve each discrepancy. Update all affected datasets and regenerate tables.

**Why this matters:** Deaths are the most carefully scrutinized data point in any clinical trial. Regulatory reviewers expect perfect reconciliation across domains. A subject marked as dead in DM but "Completed" in DS suggests a data management error. A subject with a fatal AE but no death flag suggests the AE was miscoded or the death flag was never updated. These are not cosmetic issues — they indicate gaps in the death reconciliation process that could mean other deaths were missed entirely.

---

### F-008: Per-protocol population includes subjects with major protocol deviations
- **Severity:** Medium
- **Type:** Interpretability
- **Dataset/Output:** ADSL, DV (SDTM), Table 14.2.5 (Per-Protocol Sensitivity Analysis)
- **Finding:** 14 subjects flagged with major protocol deviations in the DV domain (DVCAT="MAJOR") have PPROTFL="Y" in ADSL and are included in the per-protocol analysis.
- **Evidence:** DV domain lists 14 subjects with DVCAT="MAJOR" and DVDECOD values including "Received prohibited concomitant medication" (6), "Missed >2 consecutive scheduled doses" (5), and "Entered study with exclusion criterion met" (3). All 14 have PPROTFL="Y" in ADSL. The SAP (Section 2.1.3) defines the per-protocol population as "all ITT subjects without major protocol deviations."
- **Impact:** Including these subjects in the per-protocol population violates the SAP definition. For the primary endpoint, the per-protocol analysis is a sensitivity analysis supporting the ITT result. If the per-protocol result is used to support the robustness claim, including deviant subjects weakens that argument. The 3 subjects who entered with an exclusion criterion met are particularly concerning — they may not have the disease under study.
- **Recommended follow-up:** Correct PPROTFL for these 14 subjects. Rerun the per-protocol sensitivity analysis. Separately, review the 3 subjects who entered with an exclusion criterion to determine whether they truly have the target condition.

**Why this matters:** The per-protocol population is specifically designed to exclude subjects who may dilute the treatment effect. Including subjects with major deviations defeats its purpose and can mislead reviewers about the robustness of the primary result. This finding also raises the question of whether the sponsor's deviation classification process is working — if major deviations don't lead to PP exclusion, what does?

---

### F-009: Shift table row totals do not equal column totals
- **Severity:** Medium
- **Type:** Reproducibility
- **Dataset/Output:** Table 14.3.7.1 (ALT Shift Table — Active Arm)
- **Finding:** In the ALT shift table for the active arm, the sum of the "Baseline Normal" row (N=180) does not match the sum of subjects in the Normal column at baseline when reading down (N=178). Two subjects appear in neither the post-baseline Normal, Grade 1, Grade 2, nor Grade 3+ columns.
- **Evidence:** Baseline Normal row: Normal→Normal (142) + Normal→Grade 1 (28) + Normal→Grade 2 (8) + Normal→Grade 3+ (2) = 180. But reading the "Baseline: Normal" column header shows N=178. The 2-subject discrepancy suggests 2 subjects have a baseline value but no post-baseline value and are either omitted from the column total or double-counted in the row total.
- **Impact:** Shift tables should be symmetric (every subject with a baseline value and a post-baseline value appears exactly once). The discrepancy indicates either missing post-baseline data that isn't handled consistently, or a programming error in the shift table macro. While this doesn't directly change the efficacy conclusion, it undermines the reliability of the liver safety assessment. If the 2 missing subjects had Grade 3+ ALT elevations post-baseline, the safety profile looks different.
- **Recommended follow-up:** Identify the 2 subjects. Determine whether they are missing post-baseline ALT values (and should be excluded from both row and column totals) or have values that were not classified. Verify the shift table program logic for handling subjects with baseline but no post-baseline data.

**Why this matters:** Shift tables are deceptively simple and frequently contain errors. The symmetry check (row totals must equal column totals for the same baseline category) is a fast, reliable audit. Asymmetry always means either missing data is handled inconsistently or subjects are misclassified. Liver lab shift tables are especially important because of Hy's Law monitoring.

---

### F-010: Subgroup Ns do not sum to overall N
- **Severity:** Medium
- **Type:** Interpretability
- **Dataset/Output:** Figure 14.2.2 (PFS Forest Plot by Subgroup)
- **Finding:** The sum of subgroup Ns for the "Region" subgroup (North America: 180, Europe: 195, Asia-Pacific: 62 = 437) does not match the overall ITT N (N=450). Thirteen subjects are unaccounted for.
- **Evidence:** The forest plot shows three region categories with Ns summing to 437. The overall analysis N at the top of the plot is 450. No "Other" or "Missing" region category is shown. ADSL.REGION1 shows 13 subjects with REGION1="" (missing). These subjects contribute to the overall analysis but drop out of the subgroup breakdown.
- **Impact:** Readers comparing subgroup results to the overall result expect the subgroups to be exhaustive. Missing subjects can bias subgroup interpretations if they are non-randomly distributed across treatment arms. In this case, if 10 of the 13 missing-region subjects are in the active arm and had events, the overall HR includes them but no subgroup does — the forest plot appears cleaner than reality.
- **Recommended follow-up:** Assign the 13 subjects to their correct region (query the clinical database) or add an "Other/Missing" category to the forest plot. Verify all other subgroup variables (age, sex, biomarker status) for the same issue.

**Why this matters:** The "subgroup Ns must sum to overall N" check is a basic reviewer audit. It catches both data quality issues (missing subgroup variables) and programming errors (subjects dropped by a merge). Regulatory reviewers use subgroup analyses to assess consistency of treatment effect — if the subgroups don't account for all subjects, the consistency assessment is incomplete.

---

### F-011: MMRM model specification differs from SAP
- **Severity:** Medium
- **Type:** Conclusion-impacting
- **Dataset/Output:** Table 14.2.2 (Change from Baseline in MADRS — Primary Analysis), SAP Section 5.1
- **Finding:** The SAP specifies an MMRM model with treatment, visit, treatment-by-visit interaction, baseline score, and stratification factors (region, baseline severity category) as covariates, using an unstructured covariance matrix. The reported analysis omits the baseline severity category from the model.
- **Evidence:** SAP Section 5.1: "The primary analysis model will include fixed effects for treatment, visit, treatment-by-visit interaction, baseline MADRS total score (continuous), region, and baseline severity category (moderate vs. severe)." Table 14.2.2 footnote states: "MMRM model includes treatment, visit, treatment-by-visit, baseline MADRS score, and region." Baseline severity category is absent from the footnote. Reproducing the analysis from ADQS with and without baseline severity yields a treatment difference of -3.2 (with) vs. -3.5 (without), p=0.008 vs. p=0.004.
- **Impact:** Omitting a pre-specified covariate from the primary model is a protocol deviation in the statistical analysis. In this case, the result is significant either way, but the point estimate and p-value differ. The pre-specified model (with severity) should be the primary, and the model without severity should be a sensitivity analysis. Presenting the non-pre-specified model as primary inflates the apparent treatment effect slightly.
- **Recommended follow-up:** Rerun the primary analysis with the full SAP-specified model. Present the pre-specified model as primary and the current model as a sensitivity analysis. Update the CSR accordingly.

**Why this matters:** Deviations from the pre-specified statistical model — even seemingly minor ones like omitting a covariate — are a red flag for regulators. The pre-specified model was agreed upon before unblinding, so any departure raises the question of whether the change was motivated by seeing the data. Reviewers systematically compare every model footnote against the SAP to catch these discrepancies.

---

### F-012: Exposure-adjusted AE incidence rates use incorrect person-time denominator
- **Severity:** Medium
- **Type:** Reproducibility
- **Dataset/Output:** Table 14.3.2 (AE Incidence Rates per 100 Patient-Years)
- **Finding:** The exposure-adjusted incidence rates (EAIRs) use total study duration (randomization to data cutoff) rather than actual treatment duration (first dose to last dose + 30-day safety window) as the person-time denominator. This underestimates event rates in both arms but disproportionately in the control arm where earlier discontinuations occur.
- **Evidence:** Table 14.3.2 reports person-years of 412.5 (active) and 398.7 (control). Using ADSL TRTSDT/TRTEDT + 30 days, the correct person-years are 387.2 (active) and 342.1 (control). The control arm has more early discontinuations (median treatment duration 8.2 vs. 10.1 months), so using total study time inflates the control denominator more. The reported "Any TEAE" EAIR is 156.4 (active) and 148.2 (control) per 100 PY. Using correct denominators: 166.7 (active) and 172.8 (control) per 100 PY — the direction of difference reverses.
- **Impact:** The incorrect denominator makes the active arm appear to have a higher event rate than the control, when the opposite is true after correction. This affects the safety narrative and could influence benefit-risk assessment. Exposure-adjusted rates are specifically designed to account for differential follow-up, and using the wrong denominator defeats their purpose.
- **Recommended follow-up:** Recalculate all EAIRs using treatment duration + safety follow-up window as the person-time denominator, consistent with ICH E9 guidance. Regenerate Table 14.3.2 and any CSR text that references exposure-adjusted rates.

**Why this matters:** Exposure-adjusted incidence rates are the correct metric when treatment durations differ between arms (which they almost always do). Using study duration instead of treatment duration is a common error that systematically biases the comparison. Reviewers check the person-time denominator against the exposure summary table — if median treatment durations differ substantially between arms but person-years are similar, the denominator is likely wrong.

---

### F-013: MACE composite event double-counts a CV death component
- **Severity:** High
- **Type:** Reproducibility
- **Dataset/Output:** ADTTE (MACE endpoint), Table 14.2.1 (Primary CV Outcome)
- **Finding:** The MACE composite (CV death, non-fatal MI, non-fatal stroke) counts 5 subjects with both a non-fatal MI and subsequent CV death as two separate first events. These subjects appear in both the MI component count and the CV death component count. The composite event count (187) exceeds the number of unique subjects with any MACE event (182).
- **Evidence:** ADTTE PARAMCD="MACE" has 187 records with CNSR=0. However, 5 subjects have two ADTTE event records — one for MI and one for CV death. Example: S-002-319 has MI on 2023-07-10 and CV death on 2023-07-12. In a first-event composite, only the MI should count (it is the first qualifying event). The ADT for the composite should be 2023-07-10, not 2023-07-12. Four of 5 subjects are in the active arm.
- **Impact:** The composite event count is inflated by 5 (187 vs 182). More importantly, the event date for these 5 subjects may be wrong (using death date instead of MI date), affecting the time-to-event analysis. Since 4 of 5 are in the active arm, correcting this could narrow the between-arm difference.
- **Recommended follow-up:** Ensure the MACE composite uses the first qualifying component event per subject. Reconcile component counts: CV death (unique) + non-fatal MI (unique, excluding those who also had prior CV death) + non-fatal stroke (unique, excluding those who also had prior CV death or MI) should equal the composite count. Rerun the Cox model with corrected event dates.
- **traceability_path:** Table 14.2.1 composite N → ADTTE MACE records → ADTTE component PARAMs → adjudication source

**Why this matters:** Composite endpoints are the backbone of cardiovascular outcome trials. The "first event" rule is fundamental — each subject contributes exactly one event to the composite, dated at their first qualifying component. Adjudicated CV death occurring after an MI should not generate a second composite event. Reviewers reconcile composite vs component counts as a standard check; composite N should always ≤ sum of component Ns, with the gap explained by subjects counted in only the first component that occurred.

---

### F-014: PRO responder analysis uses wrong MID threshold for EORTC QLQ-C30 global health
- **Severity:** High
- **Type:** Interpretability
- **Dataset/Output:** ADQS (PRO endpoint), Table 14.2.4 (PRO Responder Analysis)
- **Finding:** The responder analysis for EORTC QLQ-C30 Global Health Status/QoL uses a ≥5-point improvement threshold. The validated MID for this scale is ≥10 points (Osoba et al., 1998; EORTC scoring manual v3). The SAP Section 5.3.2 specifies a ≥10-point threshold.
- **Evidence:** ADQS records with PARAMCD="QLQGH" and CRIT1=">=5 point improvement" flag 142/225 (63.1%) active-arm subjects as responders vs 118/225 (52.4%) placebo. Using the SAP-specified ≥10-point threshold: 98/225 (43.6%) active vs 89/225 (39.6%) placebo. The responder rate difference drops from 10.7% (p=0.021) to 4.0% (p=0.38).
- **Impact:** Using a lower-than-validated MID inflates the apparent PRO benefit. With the correct threshold, the PRO responder result is no longer statistically significant. If PRO is a key secondary endpoint or supports labeling language about patient-reported improvement, this changes the strength of that claim. The use of a non-SAP threshold also represents a deviation from the pre-specified analysis.
- **Recommended follow-up:** Rerun the responder analysis with the ≥10-point threshold per SAP. Present the ≥5-point analysis as exploratory if desired. Verify that other PRO instruments (EQ-5D, symptom subscales) use their validated MIDs.
- **reviewer_question:** Please confirm the intended MID threshold for EORTC QLQ-C30 Global Health responder analysis and provide the reference supporting this choice.

**Why this matters:** PRO responder analyses are only as credible as the threshold used to define a responder. Validated MIDs exist for most established instruments, and using a lower threshold inflates responder rates. This is a frequent finding because MID thresholds vary by instrument, population, and anchor method — sponsors sometimes use a more favorable threshold without adequate justification. Reviewers verify the threshold against the SAP and published validation studies.

---

### F-015: Exacerbation rate analysis excludes run-in exacerbations from baseline rate calculation
- **Severity:** Medium
- **Type:** Conclusion-impacting
- **Dataset/Output:** ADTTE (exacerbation endpoint), Table 14.2.1 (Annualized Exacerbation Rate), SAP Section 5.1
- **Finding:** The negative binomial model for annualized moderate-to-severe COPD exacerbation rate includes prior exacerbation history as a covariate, but the covariate uses only the 12-month pre-screening history from medical records. The protocol includes a 2-week run-in period during which 18 subjects (9 active, 9 placebo) experienced qualifying exacerbations. These run-in events are excluded from both the baseline covariate and the on-treatment event count.
- **Evidence:** SAP Section 5.1: "Prior exacerbation history (0, 1, ≥2 in the 12 months before screening) will be included as a covariate." The run-in period (Day -14 to Day 1) is part of the study but before randomized treatment. ADAE and medical history show 18 run-in exacerbations. These are absent from ADSL.EXACHIST (baseline covariate) and from the on-treatment event count. ADSL.EXACHIST for 7 of these 18 subjects shows "0" prior exacerbations — meaning their run-in event is their only recent exacerbation, and they are misclassified in the baseline stratum.
- **Impact:** Excluding run-in exacerbations from the baseline covariate misclassifies 7 subjects as having no prior exacerbation history when they demonstrably had one within weeks of randomization. This affects the covariate adjustment. Excluding run-in events from the outcome count may be appropriate (they are pre-treatment), but the baseline covariate should reflect all recent exacerbation history including the run-in. Sensitivity analysis including run-in events in the baseline count should be performed.
- **Recommended follow-up:** Update EXACHIST to include run-in exacerbations in the "prior exacerbation" count. Rerun the primary negative binomial model. Compare rate ratios with and without the correction to assess sensitivity.

**Why this matters:** Exacerbation trials in COPD and asthma rely heavily on accurate baseline exacerbation history for covariate adjustment and stratification. The run-in period is a gray zone — events during run-in are pre-treatment but post-enrollment, and excluding them from baseline history can misclassify subjects into the wrong stratum. Reviewers check whether the baseline covariate captures all relevant history, including the run-in, because misclassification biases the adjusted rate ratio.
