# Cross-Layer Reviewer Workflows

Read this file when building registries, reconciling across layers, or reproducing specific TLF cells. These workflows tie the individual layer checks together.

---

## 4.1 TLF cell reproduction workflow

For each key cell in a TLF/TLG, execute these steps:

| Step | Action |
|---|---|
| 1. Parse cell context | Identify table, row, column, treatment arm, visit/timepoint, endpoint, population, cutoff, method |
| 2. Reproduce denominator | Use ADSL + endpoint-specific ADaM flags to produce denominator subject list |
| 3. Reproduce numerator/estimate | Use endpoint ADaM to compute numerator, event count, summary statistic, or model estimate |
| 4. Compare reported vs reproduced | Compare count, %, estimate, CI, p-value, median, HR, OR, RR, LS mean, or rate |
| 5. Drill down discrepancies | List subjects in reported-not-reproduced and reproduced-not-reported sets with reasons |
| 6. Trace to SDTM/source | For each discrepant subject, identify source domains/records driving inclusion/exclusion |
| 7. Classify impact | Determine whether discrepancy affects primary/key secondary, safety, labeling, or interpretation |
| 8. Generate finding | Produce finding with evidence, impact, recommended follow-up |

---

## 4.2 Population registry template

Build this first. Every downstream check references it.

| Population | Definition | N (ADSL) | N (DM/DS) | N (Table 14.1.1) | Consistent? | Notes |
|---|---|---|---|---|---|---|
| Screened | | | | | | |
| Enrolled | | | | | | |
| Randomized | | | | | | |
| ITT / FAS | | | | | | |
| mITT | | | | | | |
| Safety | | | | | | |
| Per-Protocol | | | | | | |
| Evaluable (endpoint-specific) | | | | | | |
| Biomarker-positive subset | | | | | | |
| PRO-evaluable | | | | | | |
| Lab-evaluable (per test) | | | | | | |
| Responder-only (DOR etc.) | | | | | | |

---

## 4.3 Denominator registry template

For every reported table, record:

| Output | Population used | Header N | Reproduced N | Difference | Subject-level reason categories |
|---|---|---:|---:|---:|---|
| Demographics | ITT | | | | |
| Primary efficacy | ITT/FAS/mITT | | | | |
| Key secondary (responder) | Endpoint evaluable | | | | No baseline, no valid post-baseline, rescue before visit, missing endpoint |
| PRO endpoint | PRO evaluable | | | | Missing diary, insufficient valid days, not done, incomplete items |
| Lab shift | Safety + test-evaluable | | | | Missing baseline, missing post-baseline, nonnumeric, unit issue |
| AE summary | Safety | | | | No exposure, invalid TEAE window, duplicate handling |
| Death summary | Randomized or safety | | | | Death source discrepancy, cutoff, follow-up status |

---

## 4.4 Endpoint evaluability reconciliation

Common legitimate N differences and how to verify them:

| Situation | What to verify |
|---|---|
| Primary continuous endpoint N < baseline table N | Missing baseline, missing endpoint visit, imputed values, ICEs, model inclusion rules |
| Responder endpoint N ≠ continuous endpoint N | Observed vs imputed vs NRI vs endpoint-evaluable only |
| PRO endpoint N < ITT N | Diary completion, valid scoring, valid-day/week rules, language/instrument availability |
| Lab shift N differs by test | Per-test baseline and post-baseline availability, unit/result validity |
| Composite component counts > composite count | First-event vs ever-event counting |
| AE event count > subject count | Event-level vs subject-level counting |
| Subgroup levels don't sum to parent N | Missing/unknown category, overlapping categories, non-mutually-exclusive definition |

---

## 4.5 Missing data and ICE registry template

| Endpoint | N evaluable | N with event | N censored/missing | % missing | Arm difference | Reason for missingness | ICE handling per SAP |
|---|---|---|---|---|---|---|---|

Flag endpoints where:
- Missingness > 15% in either arm
- Absolute arm difference in missingness > 5%
- Missing data correlated with treatment (informative censoring/dropout)

---

## 4.6 Multiplicity and hierarchy check

Document the testing hierarchy as a decision tree:

```
1. Primary endpoint → p = ?, boundary = ? → Gate: OPEN / CLOSED
   2. Key secondary 1 → p = ?, boundary = ? → Gate: OPEN / CLOSED
      3. Key secondary 2 → p = ?, boundary = ? → Gate: OPEN / CLOSED
         ...
```

Verify each gate against reported p-values. Flag any secondary endpoint reported as "significant" when a prior gate failed. Flag any endpoint with alpha spending at interim that exceeds the boundary.

---

## 4.7 Safety reconciliation workflow

Cross-check these safety outputs against each other:

| Check | Sources to reconcile |
|---|---|
| Deaths | Disposition table, AE table (fatal), death listing, narratives, DM.DTHFL, DS death records |
| SAEs | AE summary SAE row, SAE listing, narratives |
| Discontinuations due to AE | Disposition table, AE table (leading to d/c), DS records — see detailed rule below |
| Exposure | Mean/median duration in exposure table vs CSR text |
| Liver safety (Hy's Law) | ALT/bilirubin tables, Hy's Law evaluation, narratives |
| Cardiac safety | QTc tables, ECG outlier counts, cardiac AE terms |

**AE discontinuation traceability rule (detailed):**

This is one of the most common high-severity cross-layer findings. Execute this exact reconciliation:

| Source | What to count | Expected relationship |
|---|---|---|
| DS: DSDECOD = 'ADVERSE EVENT' (or equivalent) | Subjects who discontinued treatment due to AE per disposition | **Authoritative source** — this is the definitive list |
| ADSL: DCSREAS = 'ADVERSE EVENT' (or equivalent) | Subjects flagged in ADaM as AE-discontinued | Must equal DS count exactly |
| ADAE: AEACN = 'DISCONTINUED' (unique subjects) | Subjects with at least one AE record flagged as causing discontinuation | Must equal DS count exactly |
| TLF: "AE leading to discontinuation" row | Reported count in AE summary table | Must equal ADAE count (which must equal DS count) |

**Reconciliation steps:**
1. Extract subject lists from all 4 sources.
2. Verify DS = ADSL (exact subject-set match).
3. Verify ADAE DISCONTINUED subjects = DS subjects (exact match).
4. If gap exists (DS > ADAE): identify subjects in DS but missing from ADAE. Check if they have AE records at all. Check their AEACN values.
5. If gap exists (ADAE > DS): identify subjects with AEACN=DISCONTINUED but DS shows COMPLETED or other status.
6. Every discrepancy is a High-severity traceability finding.

**Common failure modes:**
- Simulation/programming error: DS flags AE discontinuation correctly but the AEACN field in ADAE is never updated for some subjects (most common).
- Multiple AEs near discontinuation: the "causative" AE is ambiguous and none gets flagged.
- Timing mismatch: AE resolved before discontinuation date, so AEACN is not set despite DS recording AE as reason.

---

## 4.8 Label/CSR/TLF consistency check

If CSR or proposed labeling is available:

| Check | Logic |
|---|---|
| Efficacy claims | Every number in CSR text matches its source table exactly |
| "Statistically significant" language | Only used for results within the controlled multiplicity hierarchy |
| Safety claims | "No clinically meaningful QTc prolongation" or similar supported by QTc data |
| Benefit-risk | Conclusions supported by both efficacy and safety data as presented |
| Cross-document scan | Same metric across CSR body, synopsis, tables, figures, appendices, label, briefing docs |

