# CRF Schema — {TRIAL_NAME} (NCT{NCTID})

Derived from the protocol's Schedule of Activities (SoA). Each form
documents its visit grid, variable set with CDISC-aligned naming, source
in the protocol, and how the form's variables map onto the SCM.

For R builds, this schema is also the source for pharmaverse metadata:
`metadata/sdtm_spec.csv`, `metadata/adam_spec.csv`, and
`metadata/export_spec.csv`. Keep derivation rules explicit enough for
`sdtm.oak`, `admiral`, `xportr`, and `datasetjson` steps to be generated
without reverse-engineering procedural code.

## Trial-level visit grid

| Visit code | Visit number | Study day | Description | Source |
|---|---|---|---|---|
| SCREENING | 1 | -28 to -1 | Screening | Protocol §X |
| C1D1 | 2 | 1 | Cycle 1 Day 1 | Protocol §X |
| ... | ... | ... | ... | ... |
| FU_W{n} | ... | every 6 weeks (q6w) | Follow-up assessment | Protocol §X |
| EOT | 99 | variable | End of Treatment | Protocol §X |
| ADMIN_CENSOR | — | from CTGov data cutoff | Administrative censor | CTGov record |

Document any **stratified randomization** factors that shape the visit
grid (e.g., different scan schedule for CNS-mets subgroup).

## Form inventory

For each form, complete the dossier below.

### Template

```
### Form: <NAME>

- **Domain (CDISC)**: e.g. DM, AE, LB, EX, EG, VS, RS, DS, SU
- **Source in protocol**: §X.Y, page Z
- **Visit grid**: list of visit codes where this form is collected
- **Trigger conditions** (if not collected at every listed visit):
  - e.g., Disease Progression form only when RECIST PD observed
  - e.g., CNS Assessment only when CNS_METS=Y at baseline
- **Variables** (table below)
- **SCM mapping**: for each variable, which SCM node generates it; for
  derived columns (e.g., LBSTRESN), document the projection rule
- **Edit checks** (data-quality constraints that the simulator must
  satisfy):
  - e.g., LBDTC must be within ±3 days of visit window
  - e.g., AESTDTC ≤ AEENDTC when both present
- **Missingness model**: which fields are conditionally missing and on
  what
- **Mock row**: one realistic example row to anchor the schema
```

### Per-variable columns

| CDISC name | Type | Allowed values / units | Source SCM node | Derivation | Required? | Notes |
|---|---|---|---|---|---|---|
| USUBJID | char | study-site-subject ID | Patient ID | identity | yes | |
| VISIT | char | visit label | Visit grid | identity | yes | |
| LBDTC | date ISO 8601 | YYYY-MM-DD | `visit_day → date` | `baseline_date + visit_day - 1` | yes | |
| LBORRES | numeric | per-test units | SCM lab node | identity | yes | |
| LBSTRESC | char | normalized | LBORRES | unit conversion | yes | |
| LBNRIND | char | NORMAL / HIGH / LOW | LBSTRESC + reference range | rule-based | optional | |
| ... | ... | ... | ... | ... | ... | ... |

---

## Required forms (oncology trial baseline)

Complete dossier for each:

1. **Demographics (DM)** — once at screening; parents to baseline labs and ECOG
2. **Inclusion/Exclusion (IE)** — declares the eligibility filter; constrains the L₀ support
3. **Medical History (MH)** — comorbidities; parents to baseline labs and ECOG
4. **Cancer/Disease History** — disease characterization; parents to baseline tumor and stratifiers
5. **Biomarker Testing** — stratifier biomarkers (e.g., EGFR, TP53, PD-L1)
6. **Prior Therapy (PR)** — prior systemic / radiation / surgery exposures
7. **Physical Exam (PE)** — per protocol's SoA frequency
8. **Vital Signs (VS)** — per SoA
9. **WHO/ECOG Performance Status** — at every clinical visit
10. **Lab Hematology (LB)** — frequency from SoA; emits ANC/HGB/PLT/WBC/LYMPH per visit
11. **Lab Chemistry (LB)** — ALT/AST/CREAT/TBIL/ALB/electrolytes
12. **Lab Urinalysis (LB)** — if in SoA
13. **ECG (EG)** — per SoA; emits QTcF
14. **Patient-Reported Outcomes** — QLQ-C30 and disease-specific module; documents the time grid
15. **Drug Administration (EX)** — one per investigational drug
16. **Concomitant Medications (CM)** — supportive care; causally downstream of AEs
17. **Dose Modifications** — descendant of AEs, never a parent
18. **Adverse Events (AE)** — per CTCAE; one row per AE event with grade, severity, action
19. **Serious AE (SAE)** — subset of AEs meeting seriousness criteria
20. **Tumor Assessment (RS)** — RECIST 1.1 schedule (typically q6w → q12w)
21. **CNS Assessment** — if applicable; MRI brain at baseline and per SoA
22. **Disease Progression** — emitted at the first PD assessment
23. **Disposition (DS)** — randomization milestone + EOT event
24. **End of Treatment Assessment** — summary at EOT
25. **Subsequent Therapy (SU)** — post-progression treatment received
26. **Survival Follow-Up** — PFS / OS endpoint emission

Add or remove forms based on the trial's SoA. Document additions with
their protocol-section reference.

---

## CDISC compliance notes

- USUBJID: unique across study; use `{STUDY}-{SITE}-{SUBJ:04d}`
- Date format: ISO 8601 (`YYYY-MM-DD`)
- Visit numbering: integer monotone in study day
- ARMCD: short code (≤8 chars); ARM: full text
- Use SDTM-style domain prefixes for variable names where possible
- R implementation:
  - Generate source CRFs first, then derive SDTM/ADaM deterministically.
  - Use `sdtm.oak` patterns for source-to-SDTM mappings where possible.
  - Use `admiral` for ADaM derivations from SDTM/source domains.
  - Use `xportr` and/or `datasetjson` only after final datasets pass DAG
    and standards validation.

---

## SoA-to-form crosswalk (one row per visit × form combination)

| Visit | Demographics | Cancer Hx | Vitals | ECG | Labs Heme | Labs Chem | ECOG | Tumor Assess | AE | Conmeds | EX | RS | DS |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| SCREENING | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |  | ✓ |  |  | ✓ |
| C1D1 |  |  | ✓ | ✓ | ✓ | ✓ | ✓ |  | ✓ | ✓ | ✓ |  |  |
| C1D8 |  |  | ✓ |  | ✓ |  |  |  | ✓ | ✓ | ✓ |  |  |
| ... | ... | ... | ... | ... | ... | ... | ... | ... | ... | ... | ... | ... | ... |

This crosswalk is the deliverable that drives the simulator's per-visit
form generation logic.
