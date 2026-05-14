# Evaluation Rubric: basic-two-arm

## Overview

This rubric evaluates agent-generated ADSL code and output against five
dimensions. Each dimension is scored independently. A passing submission must
achieve **≥ 70% of total points** with no zero score in any single dimension.

**Ground truth:** `pharmaverseadam::adsl` — the reference ADSL derived from
the same `{pharmaversesdtm}` CDISC Pilot inputs using admiral.

**Total points: 100**

---

## Dimension 1: Correctness (40 points)

Evaluate whether key derived variables match the reference `pharmaverseadam::adsl`.
Run the generated code and compare output using:

```r
library(pharmaverseadam)
ref <- pharmaverseadam::adsl
```

### 1a. Structural integrity (10 points)

| Check | Points |
|---|---|
| One record per USUBJID (`nrow(adsl) == n_distinct(adsl$USUBJID)`) | 4 |
| All USUBJIDs from DM are present in ADSL | 3 |
| No USUBJIDs in ADSL absent from DM | 3 |

### 1b. Treatment dates (10 points)

Compare TRTSDT and TRTEDT against reference for all subjects:

| Check | Points |
|---|---|
| TRTSDT matches reference for ≥ 95% of treated subjects | 5 |
| TRTEDT matches reference for ≥ 95% of treated subjects | 5 |

TRTSDT and TRTEDT should be `NA` for screen failure subjects (ARMCD = `"Scrnfail"`).

### 1c. Treatment variables (10 points)

| Check | Points |
|---|---|
| TRT01P matches DM.ARM for all subjects | 3 |
| TRT01A matches DM.ACTARM for all subjects | 3 |
| TRT01PN and TRT01AN correctly coded (High=3, Low=2, Placebo=1) | 2 |
| TRTDURD = TRTEDT - TRTSDT + 1 for all treated subjects | 2 |

### 1d. Disposition (10 points)

| Check | Points |
|---|---|
| EOSSTT is `"COMPLETED"` or `"DISCONTINUED"` for all non-screen-failure subjects | 4 |
| DCSREAS is `NA` for all subjects where EOSSTT = `"COMPLETED"` | 3 |
| DCSREAS is non-missing for ≥ 90% of subjects where EOSSTT = `"DISCONTINUED"` | 3 |

---

## Dimension 2: admiral Idioms (25 points)

Evaluate whether the generated code uses admiral correctly and follows
pharmaverse conventions.

### 2a. Function selection (15 points)

| Check | Points |
|---|---|
| `derive_vars_merged()` used for treatment date derivations (not `slice()`, `group_by/summarise`, or `left_join` on pre-grouped data) | 5 |
| `derive_vars_dtm()` used for `--DTC` to datetime conversion (not `as.POSIXct()` or `lubridate::ymd_hms()` directly on `--DTC`) | 4 |
| `derive_vars_dtm_to_dt()` or `as.Date()` used to extract date from datetime (not `as.Date(strptime(...))` on raw `--DTC`) | 3 |
| `derive_vars_dy()` used for study day derivations if present (not manual subtraction) | 3 |

### 2b. Pipe style and structure (5 points)

| Check | Points |
|---|---|
| Native pipe `|>` used throughout (not `%>%` — acceptable but non-preferred) | 2 |
| `exprs()` used for admiral verb arguments (`by_vars`, `new_vars`, `order`) | 3 |

### 2c. filter_add correctness (5 points)

| Check | Points |
|---|---|
| Treatment date derivations include placebo filter: `EXDOSE > 0 \| (EXDOSE == 0 & str_detect(EXTRT, "PLACEBO"))` or equivalent | 3 |
| `filter_add` does not reference variables from the input dataset (that would require `derive_vars_joined()`) | 2 |

---

## Dimension 3: CDISC Conformance (20 points)

### 3a. Flag variable convention (8 points)

| Check | Points |
|---|---|
| SAFFL uses `"Y"` or `NA` only — `"N"` is absent | 4 |
| ITTFL uses `"Y"` or `NA` only — `"N"` is absent | 4 |

### 3b. Date imputation (7 points)

| Check | Points |
|---|---|
| `date_imputation = "first"` used for start dates (EXSTDTC) | 3 |
| `time_imputation = "last"` used for end datetimes (EXENDTC) | 2 |
| Imputation flags (TRTSTMF, TRTETMF) retained in output | 2 |

### 3c. Dataset structure (5 points)

| Check | Points |
|---|---|
| DOMAIN variable removed from EX before `derive_vars_merged()` (or absence confirmed not to cause conflict) | 2 |
| AGEGR1 values match expected cut-points (`"<65"`, `"65-80"`, `">80"`) | 2 |
| AGEGR1N present and correctly coded alongside AGEGR1 | 1 |

---

## Dimension 4: QC Readiness (10 points)

### 4a. REVIEW annotations (6 points)

`# REVIEW:` comments must be present at each of the following:

| Location | Points |
|---|---|
| SAFFL derivation | 2 |
| ITTFL derivation | 2 |
| DS record selection for EOSSTT (DSCAT filter rationale) | 2 |

### 4b. Derivation comments (4 points)

| Check | Points |
|---|---|
| Each major derivation block has a comment identifying the target variable and source (e.g. `# TRTSDT: first dose date from EX.EXSTDTC`) | 2 |
| At least one comment references the ADaM spec or protocol (e.g. `# per SAP section X` or `# ADaM spec`) | 2 |

---

## Dimension 5: Completeness (5 points)

| Check | Points |
|---|---|
| All required variables listed in prompt.md are present in output | 3 |
| Programmatic assertion confirming one record per USUBJID is present and would not error on the output dataset | 2 |

---

## Scoring Summary

| Dimension | Max Points |
|---|---|
| 1. Correctness | 40 |
| 2. admiral Idioms | 25 |
| 3. CDISC Conformance | 20 |
| 4. QC Readiness | 10 |
| 5. Completeness | 5 |
| **Total** | **100** |

**Pass threshold:** ≥ 70 points with no zero in any dimension.

---

## Comparison Helper

Use the following to compare key variables against the reference:

```r
library(pharmaverseadam)
library(dplyr)

ref <- pharmaverseadam::adsl |>
  select(USUBJID, TRTSDT, TRTEDT, TRT01P, TRT01A, EOSSTT, DCSREAS, SAFFL)

comparison <- adsl |>
  select(USUBJID, TRTSDT, TRTEDT, TRT01P, TRT01A, EOSSTT, DCSREAS, SAFFL) |>
  left_join(ref, by = "USUBJID", suffix = c("_agent", "_ref"))

# Check treatment date agreement
comparison |>
  summarise(
    trtsdt_match = mean(TRTSDT_agent == TRTSDT_ref, na.rm = TRUE),
    trtedt_match = mean(TRTEDT_agent == TRTEDT_ref, na.rm = TRUE)
  )

# Flag mismatches for review
comparison |>
  filter(TRTSDT_agent != TRTSDT_ref | TRTEDT_agent != TRTEDT_ref) |>
  select(USUBJID, TRTSDT_agent, TRTSDT_ref, TRTEDT_agent, TRTEDT_ref)
```

---

## Known Reference Deviations

The following deviations from `pharmaverseadam::adsl` are acceptable and should
not be penalised:

- Variable order differences (XPT order is enforced separately by `{xportr}`)
- Label text differences where the agent label is a reasonable description of
  the variable
- LSTALVDT derivation differences — this variable depends on multiple source
  domains (AE, LB, DS) and implementations vary; evaluate logic rather than
  exact values
- Minor datetime precision differences in TRTSDTM/TRTEDTM where the underlying
  imputation choice is defensible and documented with `# REVIEW:`
