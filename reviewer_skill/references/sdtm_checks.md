# SDTM-Level Checks

Read this file when SDTM datasets are provided. Focus on analysis-impacting issues, not standards compliance.

Reviewer mindset: "Can I trust the source data used to derive populations, endpoints, exposure, safety, and efficacy?"

---

## 1.1 Subject identity, uniqueness, and trial participation

| Check | Priority | Logic |
|---|---:|---|
| Unique subject record in DM | High | One and only one DM record per USUBJID |
| Subject exists consistently across domains | High | Subjects in AE, EX, DS, LB, RS, TR, TU, QS should exist in DM |
| Randomized subjects identifiable | High | Check ARM/ARMCD, randomization DS records, and trial-specific markers |
| Treatment assignment consistency | High | Compare ARM/ARMCD with treatment in EX. Flag discrepancies without documented reason |
| Duplicate randomization records | High | Multiple randomization records in DS or inconsistent randomization dates |
| Screen failure vs randomized/exposed | Medium | Screen failures should not have exposure, efficacy assessment, or randomized disposition |

## 1.2 Death, disposition, and treatment discontinuation

For full death reconciliation procedures, see `cross_layer_workflows.md` §4.7.

| Check | Priority | Logic |
|---|---:|---|
| Death cross-domain consistency | High | Deaths reconcile across DM (DTHFL/DTHDTC), DS, AE (AEOUT=FATAL), and ADSL. See §4.7 for detailed workflow |
| AE leading to discontinuation | High | Every DS AE-discontinuation subject must have a corresponding ADAE record with AEACN=DISCONTINUED. See §4.7 detailed rule |
| Exposure after death/discontinuation | High | EX dates after death or study discontinuation unless valid follow-up logic exists |
| Completed vs deceased mismatch | High | Deceased subjects should not show DS status "Completed" |

## 1.3 Date integrity and temporal plausibility

| Check | Priority | Logic |
|---|---:|---|
| Start date after end date | High | Across AE, EX, CM, LB, VS, QS, RS, TR, TU — flag start > end |
| Assessments after death | High | Efficacy, safety, lab, PRO, tumor assessments after death (unless postmortem/admin) |
| Exposure before consent/randomization | High | EX dates before consent or randomization |
| Baseline assessment timing | High | Baseline records should be before first treatment/randomization per study rules |
| Visit chronology | Medium | Visit dates in expected order; same date mapping to conflicting visits |
| Partial dates affecting derivation | Medium | Partial dates in key variables affecting TEAE flag, PFS/OS censoring, baseline |
| Data cutoff consistency | High | No source data supporting primary analyses after the defined cutoff unless intended |
| Date anchoring consistency | High | Consent <= randomization <= first dose <= last dose <= last contact/death |

## 1.4 Adverse events

| Check | Priority | Logic |
|---|---:|---|
| Missing coded term (AEDECOD) | High | All analyzable AE records should have AEDECOD |
| Missing SOC/PT hierarchy | High | AEBODSYS, AESOC, AEDECOD completeness and consistency |
| Missing severity/toxicity grade | High | AESEV, AETOXGR completeness when required by SAP |
| Serious AE consistency | High | AESER=Y should have seriousness criteria; criteria present should have AESER flag |
| Fatal AE consistency | High | Fatal outcome, seriousness-death criterion, death date, disposition death alignment |
| AE date plausibility | High | AESTDTC <= AEENDTC; AE should not start after death |
| TEAE derivation inputs | High | AE dates sufficient to determine TEAE status relative to treatment start |
| Relatedness/action completeness | Medium | Missing AEREL, AEACN, or trial-specific causality/action variables |
| AESI identification | Medium | AE terms mapping consistently to AESI flags/categories in downstream ADaM |
| Duplicate AE records | Medium | Potential duplicates by subject, term, start date, severity, seriousness, outcome |

## 1.5 Exposure and dosing

| Check | Priority | Logic |
|---|---:|---|
| Missing dose, unit, or treatment | High | EXTRT, EXDOSE, EXDOSU, route, frequency, date completeness |
| Dose occurrence consistency | High | EXDOSE > 0 should have EXOCCUR indicating dosing; EXOCCUR=N should not have positive dose |
| Exposure date range | High | EXSTDTC <= EXENDTC |
| Exposure after death | High | EX records after death date |
| Exposure outside treatment period | High | EX dates vs randomization, treatment start/end, discontinuation |
| Treatment arm vs received treatment | High | DM.ARM/ARMCD vs actual EXTRT patterns |
| Missing infusion/administration details | Medium | Duration, rate, site, laterality for infusion/injection products |
| Dose modification traceability | Medium | Reductions, interruptions, missed doses traceable in EX with reasons |

## 1.6 Laboratory, vital signs, ECG, and safety assessments

| Check | Priority | Logic |
|---|---:|---|
| Missing standardized result | High | LBSTRESC/LBSTRESN/LBSTRESU for labs; standardized values/units for VS/EG |
| Character-to-numeric conversion risk | High | Values with <, >, ranges, text, qualifiers affecting numeric ADaM derivation |
| Missing reference ranges | High | LBSTNRLO/LBSTNRHI, abnormality flags, reference range indicators |
| Unit inconsistency | High | Same test should use consistent standard unit or have documented conversion |
| Baseline safety assessment availability | High | Baseline labs/vitals/ECGs exist for safety population when required |
| Assessment after death or cutoff | Medium | Safety assessments after death or data cutoff |
| Duplicate assessment records | Medium | Multiple records with same subject, test, visit/date/time unless expected |
| Clinically significant abnormality traceability | Medium | Abnormal flags consistent with result and reference range |
| Implausible outliers | High | Extreme values (e.g., glucose > 10000, negative where impossible, QTc > 700 ms) |

## 1.7 Oncology efficacy source domains (RS, TR, TU)

| Check | Priority | Logic |
|---|---:|---|
| Tumor assessment completeness | High | RS, TR, TU: assessment dates, visit, method, assessor, response/result fields |
| Target lesion sum consistency | High | Recalculate sum of diameters; compare with submitted result |
| New lesion vs progressive disease | High | New lesion → response records reflect progression per protocol |
| Overall response date consistency | High | RS.RSDTC aligned with lesion assessment dates and visit windows |
| BOR derivation inputs | High | Sufficient response sequence for CR/PR/SD/PD/NE and confirmed response |
| Missing or conflicting assessor | Medium | Investigator vs independent review source consistency |
| PFS event support | High | Subjects with PD have source records supporting PD date used in ADTTE |
| ORR evaluable population support | High | Response-evaluable subjects have required baseline + post-baseline assessments |

## 1.8 General efficacy source domains (beyond oncology)

Apply the relevant rows based on therapeutic area.

| Endpoint area | Priority | Logic |
|---|---:|---|
| Continuous clinical scales (QS, FT, SC) | High | Item completeness, total-score derivation inputs, date/time, visit, evaluator, instrument version |
| PRO/COA diary data | High | Diary completion, item-level missingness, recall period, scoring rule, not-done reason, valid-day/week rules |
| Cardiovascular/renal events | High | Event source domains, adjudication status, onset/event date, hospitalization dates, death linkage, component category |
| Infectious disease/vaccine | High | Baseline pathogen/serostatus, culture/PCR/viral-load dates, seroconversion, assay units, LLOQ handling, visit windows |
| Ophthalmology | High | Study eye/laterality, eye-level vs subject-level, BCVA/imaging timing, rescue procedure, inter-eye correlation |
| Dermatology/rheumatology | High | Component scores, BSA, joint counts, global assessments, rescue/escape rules, responder components |
| Neurology/psychiatry | High | Scale version, rater, timing, total/subscale scoring, rescue medication, intercurrent hospitalization |
| Biomarker/diagnostic | Medium | Sample collection timing, assay method, LLOQ/ULOQ handling, central vs local lab, biomarker-evaluable flag |

## 1.9 Concomitant medications, medical history, procedures, deviations, and PRO

| Check | Priority | Logic |
|---|---:|---|
| Missing medication/history coding | Medium | CMDECOD, MHDECOD completeness where expected |
| Concomitant medication timing | Medium | Start/end dates vs treatment period and AE onset |
| Procedure timing and laterality | Medium | Date, body site, laterality, study eye/organ if applicable |
| Protocol deviation completeness | High | Major deviations affecting populations, endpoint windows, prohibited meds, eligibility |
| PRO not-done consistency | Medium | Status NOT DONE → result should be missing, reason populated |
| PRO result completeness | Medium | Missing item/score values; visit/date alignment for key PRO endpoints |

## 1.10 Endpoint-specific evaluability support

| Check | Priority | Logic |
|---|---:|---|
| Baseline eligibility for endpoint | High | Source records support endpoint-specific eligibility: baseline measurement, measurable disease, positive pathogen, biomarker status, valid diary baseline, study eye |
| Post-baseline evaluability | High | Subjects with missing, invalid, out-of-window, not-done, or post-rescue assessments affecting denominator |
| Rescue/prohibited therapy source | High | CM, PR, EX, EC, DS for rescue/prohibited medication or procedures used in ICE handling |
| Adjudication source consistency | High | Investigator-reported vs adjudicated event, date, component classification |
| Endpoint component timing | High | Composite endpoint components have valid onset/event dates for first-event derivation |
| Analysis visit support | Medium | Source visit/date sufficient to derive planned analysis visits and windows |

## 1.11 Missing data and data quality patterns

| Check | Priority | Logic |
|---|---:|---|
| Missing key endpoint source data | High | Missing source assessments for primary/secondary endpoints by subject, visit, arm |
| Differential missingness by arm | High | Compare missingness patterns across treatment arms |
| Informative missingness indicators | High | Link missing assessments to death, discontinuation, AE, COVID, prohibited meds, withdrawal |
| Unexpected site/country patterns | Medium | Summarize major issues by site/country for operational artifacts |
| Large timing deviations | Medium | Visit-window deviations for endpoints and key safety assessments |
