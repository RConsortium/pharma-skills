# CRF Schema — {TRIAL_NAME} (NCT{NCTID})

Derived from the protocol's Schedule of Activities (SoA). Each form
documents its visit grid, variable set with CDISC-aligned naming, source
in the protocol, and how the form's variables map onto the SCM.

## Trial-level visit grid

| Visit code | Visit number | Study day | Description | Source |
|---|---|---|---|---|
| SCREENING | 1 | -28 to -1 | Screening | Protocol §X |
| BASELINE | 2 | 1 | Baseline / randomization | Protocol §X |
| VISIT_{n} | ... | per SoA | On-treatment visit | Protocol §X |
| FU_{n} | ... | per SoA | Follow-up assessment | Protocol §X |
| EOT | 99 | variable | End of Treatment | Protocol §X |
| ADMIN_CENSOR | — | from CTGov data cutoff | Administrative censor (time-to-event endpoints only) | CTGov record |

Use the visit codes the protocol's SoA actually defines. The cycle-based
grid (`C1D1`, `C1D8`, q6w scans) is the **oncology** pattern — use it when
the protocol schedules by treatment cycle; otherwise the generic
Screening / Baseline / on-treatment / Follow-up grid above is the default.
The `ADMIN_CENSOR` row applies **only to time-to-event endpoints** (a
calendar data-cutoff); a binary or continuous-change landmark endpoint has
no administrative censor.

Document any **stratified randomization** factors that shape the visit
grid (e.g., a different assessment schedule for a stratified subgroup).

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

## Core trial-conduct forms (all therapeutic areas)

These forms appear in most interventional trials regardless of therapeutic
area. This is the **default** form set. Complete a dossier for each.

1. **Demographics (DM)** — once at screening; parents to baseline labs and clinical status
2. **Inclusion/Exclusion (IE)** — declares the eligibility filter; constrains the L₀ support
3. **Medical History (MH)** — comorbidities; parents to baseline labs and clinical status
4. **Prior Therapy (PR)** — prior treatments / procedures the patient received
5. **Physical Exam (PE)** — per protocol's SoA frequency
6. **Vital Signs (VS)** — per SoA
7. **Lab Hematology (LB)** — frequency from SoA; emits ANC/HGB/PLT/WBC/LYMPH per visit
8. **Lab Chemistry (LB)** — ALT/AST/CREAT/TBIL/ALB/electrolytes
9. **ECG (EG)** — per SoA; emits QTcF
10. **Patient-Reported Outcomes** — instrument depends on therapeutic area; documents the time grid
11. **Drug Administration (EX)** — one per investigational drug
12. **Concomitant Medications (CM)** — supportive care; causally downstream of AEs
13. **Dose Modifications** — descendant of AEs, never a parent
14. **Adverse Events (AE)** — one row per AE event with grade, severity, action; graded on the
    protocol's toxicity scale (CTCAE for oncology, the protocol scale otherwise — see the DAG template)
15. **Serious AE (SAE)** — subset of AEs meeting seriousness criteria; often implemented as AESER column on the AE form rather than a separate CRF page — check protocol
16. **Disposition (DS)** — randomization milestone + EOT event
17. **End of Treatment Assessment** — summary at EOT

## Oncology module — include only for oncology trials

Add these forms for oncology trials. Skip the whole module for a
non-oncology trial, and skip any individual form the protocol's SoA does
not include.

1. **Cancer/Disease History** — disease characterization; parents to baseline tumor and stratifiers
2. **Biomarker Testing** — stratifier biomarkers (e.g., EGFR, TP53, PD-L1)
3. **Tumor Assessment (RS)** — RECIST 1.1 schedule (typically q6w → q12w)
4. **CNS Assessment** — if applicable; MRI brain at baseline and per SoA
5. **Disease Progression** — emitted at the first PD assessment
6. **WHO/ECOG Performance Status** — at every clinical visit
7. **Subsequent Therapy (CM)** — post-progression anti-cancer treatment received (SDTM code is `CM`; **not** `SU` — `SU` is Substance Use, i.e. tobacco/alcohol)
8. **Survival Follow-Up** — time-to-event (PFS / OS) endpoint emission
9. **Oncology PRO instruments** — QLQ-C30 and disease-specific module (e.g., QLQ-LC13 for lung)

Add or remove forms based on the trial's SoA. Document additions with
their protocol-section reference.

---

## CDISC SDTM completeness — the standard-domain floor

Reference the CDISC SDTM domain model (the
[SDTM model](https://www.cdisc.org/standards/foundational/sdtm) and the
[SDTMIG](https://www.cdisc.org/standards/foundational/sdtmig)) to confirm the form set is
**standard-complete**, then map each form to its domain. **SDTM is collection-driven, not a fixed
roster:** the only universally mandatory domain is **DM (Demographics)** — *"Each study must
include ... the Demographics domain"* — while every other domain is included **only if the trial
actually collected it** — *"A sponsor should only submit domain datasets that were actually
collected."* So this is not "add N mandatory forms"; it is "give every collected thing a form under
the right standard code, and don't silently drop a standard domain the SoA collects."

**Rule 1 — every form declares its SDTM 2-letter domain code, and the code must MATCH the domain's
actual definition** (the `Domain (CDISC)` line in each dossier). A plausible-looking 2-letter label
is not enough — map by *content*, because a CRF form's own name is not its SDTM code. Watch for
**collisions** where a form's label reuses a real domain's letters for something else: a
disease-activity form named `DA` is **not** SDTM `DA` = Drug Accountability; a tape-stripping form
named `TS` is **not** `TS` = Trial Summary. Flag any form whose code is neither a standard SDTM
domain used for its true meaning nor an explicitly declared **custom** code, and **record each such
mismatch as an explicit finding** — a *mis-coded / collision* note naming the form, the code it
wrongly carries, and its true domain. A present-but-mis-coded domain is a distinct problem from a
missing one, so report it alongside (never folded into) the gap list — a clean gap list does **not**
mean the coding is clean. DM must exist.

**Rule 2 — collected-domain sweep.** Walk the standard collected-class domains below; for each ask
*"did the SoA collect this? → is there a form for it?"* The point is to catch the standard domains a
hand-built CRF list quietly omits:

| Class | Standard collected-class domains (code — name) |
|---|---|
| Special-Purpose | **DM** Demographics *(mandatory)* · CO Comments |
| Interventions | EX Exposure · EC Exposure as Collected · CM Concomitant/Prior/**subsequent** Meds *(subsequent anti-cancer therapy is CM)* · SU Substance Use *(tobacco/alcohol)* · PR Procedures · AG Procedure Agents · ML Meal Data |
| Events | AE Adverse Events · DS Disposition · MH Medical History · CE Clinical Events · **DV** Protocol Deviations · **HO** Healthcare Encounters |
| Findings | LB Labs · VS Vital Signs · EG ECG · PE Physical Exam · QS Questionnaires · IE Incl/Excl Not Met · **DA** Drug Accountability · **DD** Death Details · **SC** Subject Characteristics · **SS** Subject Status · plus PK (PC/PP), microbiology (MB/MS), tumor (RS/TR/TU), immunogenicity (**IS** — e.g. vaccine/ELISPOT assays), genetics/pharmacogenomics (**PF** — e.g. EGFR/TP53 biomarker results), and organ-system findings as the SoA collects |
| Findings About | FA Findings About · SR Skin Response |

The **bold** domains (DV, HO, DA, DD, SC, SS, CO) are the ones most often missing from a hand-built
list — check the SoA for each before finalizing. The full catalog lives on the CDISC site; the rows
above are the ones a CRF build actually touches.

**A collected concept may ride on a related standard form — that is not a gap.** Drug-accountability
pill counts commonly live on the `EX` form, a subject characteristic like skin type on the relevant
findings form, and so on. Only call a domain a **gap** when the SoA genuinely collects it *and* it
has no home on any form. A ride-along counts as a home only if it is **lossless**: if the fold drops
states or levels the trial actually collected — e.g. only *former* smokers get an MH row while
*never* / *current* are silently dropped — the domain is **still a gap**, because the collected
information is not fully represented. Conversely, **disease-specific clinical indices have no dedicated SDTM
domain** — BVAS/WG and the Vasculitis Damage Index, PASI, EASI, and the like. Place them in a
**sponsor-defined Findings** domain (or an `RS` clinical-classification) and declare that custom code
explicitly; their absence from the standard roster is expected, not a miss.

**Rule 3 — the non-CRF submission scaffolding is out of scope.** A *complete SDTM template* also
carries the **trial-design** domains (TS Trial Summary, TA Trial Arms, TE Trial Elements, TV Trial
Visits, TI Trial Incl/Excl), the **derived** special-purpose domains (SE Subject Elements, SV
Subject Visits), and the **relationship** domains (SUPP--, RELREC). These are study-level metadata
or derived timing — **not forms a subject fills** — so they are **not** CRF forms, and **this skill
does not generate them: we do not convert to SDTM.** They are listed here only to mark the boundary
of what a full SDTM template would add on top of these CRFs.

---

## CDISC compliance notes

- USUBJID: unique across study; use `{STUDY}-{SITE}-{SUBJ:04d}`
- Date format: ISO 8601 (`YYYY-MM-DD`)
- Visit numbering: integer monotone in study day
- ARMCD: short code (≤8 chars); ARM: full text
- Use SDTM-style domain prefixes for variable names where possible

---

## SoA-to-form crosswalk (one row per visit × form combination)

Rows = the visit grid above; **columns = your trial's forms** (the core
set, plus the oncology module only if this is an oncology trial). Cell = ✓
where that form is collected at that visit. The example below uses a
generic grid; substitute your trial's visit codes and form columns.

| Visit | Demographics | Med Hx | Vitals | ECG | Labs Heme | Labs Chem | AE | Conmeds | EX | DS |
|---|---|---|---|---|---|---|---|---|---|---|
| SCREENING | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |  | ✓ |  | ✓ |
| BASELINE |  |  | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |  |
| VISIT_2 |  |  | ✓ |  | ✓ |  | ✓ | ✓ | ✓ |  |
| ... | ... | ... | ... | ... | ... | ... | ... | ... | ... | ... |

This crosswalk is the deliverable that drives the simulator's per-visit
form generation logic.
