# Benchmark Prompt: basic-two-arm

## Context

You are deriving an ADaM Subject-Level Analysis Dataset (ADSL) for a Phase III
clinical trial. The study is a two-arm parallel group design comparing an active
treatment against placebo. SDTM data is available from the CDISC Pilot Study
(provided via `{pharmaversesdtm}`).

Follow the `admiral-adsl` skill throughout. Apply `# REVIEW:` annotations at
every protocol-specific decision point.

---

## Study Information

- **Study design:** Two-arm parallel group (Active vs. Placebo)
- **Treatment arms:** `"Xanomeline High Dose"`, `"Xanomeline Low Dose"`, `"Placebo"`
- **ARMCD values:** `"Xan_Hi"`, `"Xan_Lo"`, `"Placebo"`
- **Planned treatment variable:** TRT01P — from DM.ARM
- **Actual treatment variable:** TRT01A — from DM.ACTARM

## Population Flag Definitions

Apply the following definitions for this study:

- **SAFFL:** Received at least one dose of study treatment (EXDOSE > 0 or
  EXTRT contains "PLACEBO") with a non-missing EXSTDTC
- **ITTFL:** Randomised — ARMCD is not `"Scrnfail"` and ARM is not
  `"Screen Failure"`

## Required Variables

Derive the following variables at minimum:

**Identifiers:** STUDYID, USUBJID, SUBJID, SITEID

**Demographics:** AGE, AGEU, SEX, RACE, ETHNIC, COUNTRY

**Age grouping** (from ADaM spec):
- AGEGR1: `"<65"` / `"65-80"` / `">80"`
- AGEGR1N: `1` / `2` / `3`

**Treatment:**
- TRT01P, TRT01A (character, from DM)
- TRT01PN, TRT01AN (numeric: Xanomeline High Dose = 3, Xanomeline Low Dose = 2,
  Placebo = 1)
- TRTSDTM, TRTSTMF (first dose datetime and imputation flag)
- TRTEDTM, TRTETMF (last dose datetime and imputation flag)
- TRTSDT, TRTEDT (date versions of above)
- TRTDURD (total treatment duration in days)

**Disposition:**
- EOSSTT (`"COMPLETED"` or `"DISCONTINUED"`)
- EOSDT (end of study date)
- DCSREAS (reason for discontinuation — `NA` for completers)
- RANDDT (date of randomisation from DM.DMDTC)

**Survival/safety:**
- DTHFL, DTHDT (death flag and date — from DM)
- LSTALVDT (last known alive date)

**Population flags:** SAFFL, ITTFL

## Input Data

Load from `{pharmaversesdtm}`:

```r
library(pharmaversesdtm)

dm  <- pharmaversesdtm::dm
ex  <- pharmaversesdtm::ex
ds  <- pharmaversesdtm::ds
ae  <- pharmaversesdtm::ae   # for LSTALVDT
lb  <- pharmaversesdtm::lb   # for LSTALVDT
```

## Output Requirements

1. A complete ADSL dataset with one record per USUBJID
2. Executable R code using `{admiral}` following pharmaverse idioms
3. `# REVIEW:` comments at all protocol-specific decision points
4. A programmatic assertion confirming one record per USUBJID
5. Variable labels applied (via `{xportr}` or `Hmisc::label()`)
