---
name: admiral-adsl
description: >
  Derives an ADaM Subject-Level Analysis Dataset (ADSL) using the {admiral}
  R package and pharmaverse ecosystem. Use when a user needs to create ADSL
  from SDTM domains, derive standard subject-level variables (treatment dates,
  disposition, demographics, population flags), or generate QC-ready R code
  following CDISC ADaM conventions. Requires SDTM input data and an ADaM spec.
license: MIT
metadata:
  author: Navitas Data Sciences
  version: "0.1"
  pharmaverse: "true"
compatibility: >
  Requires R with admiral, dplyr, lubridate, and pharmaversesdtm installed.
  Designed for use in a GxP-compliant environment with access to SDTM datasets
  and an ADaM ADSL specification.
---

# admiral-adsl

Derives a CDISC-conformant ADSL dataset using {admiral}. Outputs executable,
QC-ready R code with derivation logic traceable to the ADaM specification.

See [admiral-functions reference](references/admiral-functions.md) for function
selection guidance. See [adsl-conventions reference](references/adsl-conventions.md)
for CDISC variable conventions.

---

## Inputs

Before generating code, confirm the following are available or explicitly noted
as absent:

| Input | Required | Notes |
|---|---|---|
| DM | Yes | Subject spine; one record per USUBJID |
| EX | Yes | Exposure; needed for treatment dates and SAFFL |
| DS | Yes | Disposition; needed for EOSSTT, DCSREAS |
| MH | No | Medical history flags if protocol requires |
| VS | No | HEIGHTBL, WEIGHTBL, BMIBL if in scope |
| ADaM ADSL spec | Yes | Variable list, derivation rules, grouping cut-points |
| Study context | Yes | Treatment arm names, population flag definitions |

If required domains are absent, stop and request them. If optional domains are
absent, omit the corresponding derivations and note this in code comments.

---

## Workflow

Follow these steps in order. Generate code section by section, not as a single
block.

### Step 1 — Setup and domain loading

```r
library(admiral)
library(dplyr)
library(lubridate)

# Load SDTM domains
dm  <- pharmaversesdtm::dm
ex  <- pharmaversesdtm::ex
ds  <- pharmaversesdtm::ds
# mh <- pharmaversesdtm::mh  # uncomment if in scope
```

### Step 2 — Subject spine

Start from DM. One record per USUBJID is mandatory at this step and must be
preserved throughout.

```r
adsl <- dm |>
  select(STUDYID, USUBJID, SUBJID, SITEID, AGE, AGEU, SEX, RACE, ETHNIC,
         COUNTRY, ARM, ARMCD, ACTARM, ACTARMCD, DMDTC, RFSTDTC, RFENDTC)
```

Only select variables needed downstream. Do not carry all of DM forward.

### Step 3 — Treatment dates (TRTSDT, TRTEDT)

Derive from EX. TRTSDT = first dose date; TRTEDT = last dose date per subject.
Use `derive_vars_merged()` with `order` and `mode` — do not use `slice()` or
manual `group_by/summarise` approaches as these lose admiral traceability.

```r
ex_dt <- ex |>
  derive_vars_dtm(
    dtc = EXSTDTC,
    new_vars_prefix = "EXST",
    date_imputation = "first",
    flag_imputation = "auto"
  ) |>
  derive_vars_dtm(
    dtc = EXENDTC,
    new_vars_prefix = "EXEN",
    date_imputation = "last",
    flag_imputation = "auto"
  )

adsl <- adsl |>
  derive_vars_merged(
    dataset_add = ex_dt,
    by_vars = exprs(STUDYID, USUBJID),
    new_vars = exprs(TRTSDTM = EXSTDTM),
    order = exprs(EXSTDTM),
    mode = "first",
    filter_add = !is.na(EXSTDTM)
  ) |>
  derive_vars_merged(
    dataset_add = ex_dt,
    by_vars = exprs(STUDYID, USUBJID),
    new_vars = exprs(TRTEDTM = EXENDTM),
    order = exprs(EXENDTM),
    mode = "last",
    filter_add = !is.na(EXENDTM)
  ) |>
  mutate(
    TRTSDT = as.Date(TRTSDTM),
    TRTEDT = as.Date(TRTEDTM)
  )
```

**Flag for human review:** If subjects have gaps in exposure (multiple EX
records with non-contiguous dates), TRTEDT may not reflect the true end of
treatment. Add a comment and flag for QC.

### Step 4 — Planned and actual treatment (TRT01P, TRT01A)

TRT01P comes from DM.ARM (randomised treatment). TRT01A comes from EX
(actual treatment received). These are distinct and must not be conflated.

```r
adsl <- adsl |>
  mutate(
    TRT01P  = ARM,
    TRT01A  = ACTARM,
    TRT01CD = ARMCD,
    TRT01CA = ACTARMCD
  )
```

If the study has multiple periods, derive TRT02P/TRT02A etc. from EX using
period-specific filtering. Note this in code comments if applicable.

### Step 5 — Randomisation and reference dates

```r
adsl <- adsl |>
  derive_vars_dt(
    dtc = RFSTDTC,
    new_vars_prefix = "RFST"
  ) |>
  derive_vars_dt(
    dtc = RFENDTC,
    new_vars_prefix = "RFEND"
  ) |>
  mutate(RANDDT = as.Date(DMDTC))
```

### Step 6 — Study day variables

Use `derive_vars_dy()` — do not compute manually with date subtraction.

```r
adsl <- adsl |>
  derive_vars_dy(
    reference_date = TRTSDT,
    source_vars = exprs(RANDDT)
  )
```

### Step 7 — Disposition (EOSSTT, DCSREAS, DCSREASP)

Filter DS to `DSCAT == "DISPOSITION EVENT"`. If multiple records exist per
subject, select the primary disposition record per protocol. This is a common
source of error — check the protocol definition and add a comment.

```r
ds_eos <- ds |>
  filter(DSCAT == "DISPOSITION EVENT") |>
  derive_vars_dt(
    dtc = DSDTC,
    new_vars_prefix = "DS"
  )

adsl <- adsl |>
  derive_vars_disposition_status(
    dataset_ds    = ds_eos,
    new_var       = EOSSTT,
    status_var    = DSDECOD,
    filter_ds     = DSCAT == "DISPOSITION EVENT"
    # REVIEW: verify EOSSTT values match protocol-defined categories (e.g. "COMPLETED", "DISCONTINUED")
    # If the built-in formatter does not fit, swap to derive_vars_merged() with manual new_vars.
  ) |>
  derive_vars_merged(
    dataset_add = ds_eos,
    by_vars = exprs(STUDYID, USUBJID),
    new_vars = exprs(DCSREAS = DSDECOD, DCSREASP = DSTERM, EOSDT = DSDT),
    order = exprs(DSDT),
    mode = "last"
  )
```

**Protocol-specific note:** EOSSTT values (e.g. "COMPLETED", "DISCONTINUED")
must match the protocol-defined categories. Review with the statistician before
finalising.

### Step 8 — Baseline demographics

Derive AGE groupings and other categorisations per the ADaM spec. The cut
points for AGEGR1 must come from the spec — do not assume standard cut points.

```r
adsl <- adsl |>
  mutate(
    # Replace cut points with those defined in the ADaM spec
    AGEGR1 = case_when(
      AGE < 18             ~ "<18",
      AGE >= 18 & AGE < 65 ~ "18-<65",
      AGE >= 65            ~ ">=65"
    ),
    AGEGR1N = case_when(
      AGEGR1 == "<18"   ~ 1,
      AGEGR1 == "18-<65"~ 2,
      AGEGR1 == ">=65"  ~ 3
    )
  )
```

If VS is in scope, derive HEIGHTBL, WEIGHTBL, BMIBL using
`derive_vars_merged()` from the baseline VS records (VSBLFL == "Y").

### Step 9 — Population flags (SAFFL, ITTFL, PPROTFL, ENRLFL)

**Critical:** population flag definitions are protocol-specific. The derivations
below implement standard logic but must be reviewed against the protocol and SAP
before use.

```r
adsl <- adsl |>
  # SAFFL: received at least one dose
  derive_var_merged_exist_flag(
    dataset_add = ex,
    by_vars = exprs(STUDYID, USUBJID),
    new_var = SAFFL,
    condition = !is.na(EXSTDTC)
  ) |>
  # ITTFL: randomised (in DM with ARM assigned)
  mutate(
    ITTFL = if_else(!is.na(ARM) & ARM != "Screen Failure", "Y", NA_character_)
  ) |>
  # ENRLFL: enrolled (all subjects in DM)
  mutate(ENRLFL = "Y")
  # PPROTFL: per protocol — highly protocol-specific, derive per SAP definition
```

**Flag for human review:** PPROTFL derivation requires protocol-specific
exclusion criteria (e.g. major protocol deviations). Insert a placeholder and
require statistician input.

### Step 10 — Dataset attributes and final checks

```r
# Verify one record per USUBJID
stopifnot(nrow(adsl) == n_distinct(adsl$USUBJID))

# Check required variables are present
required_vars <- c("STUDYID", "USUBJID", "TRTSDT", "TRTEDT",
                   "TRT01P", "TRT01A", "EOSSTT", "SAFFL", "ITTFL")
missing_vars <- setdiff(required_vars, names(adsl))
if (length(missing_vars) > 0) {
  stop("Missing required ADSL variables: ", paste(missing_vars, collapse = ", "))
}

# Apply dataset and variable attributes from the ADaM spec (xportr recommended for submission)
# Replace metacore_obj with your loaded metacore object derived from the ADaM spec.
# adsl <- adsl |>
#   xportr_label(metacore_obj, domain = "ADSL") |>
#   xportr_type(metacore_obj, domain = "ADSL") |>
#   xportr_length(metacore_obj, domain = "ADSL") |>
#   xportr_order(metacore_obj, domain = "ADSL")
# xportr_write(adsl, "adsl.xpt", label = "Subject-Level Analysis Dataset")
#
# For non-submission contexts, apply labels directly:
# Hmisc::label(adsl$TRTSDT) <- "Date of First Study Treatment"
# Hmisc::label(adsl$SAFFL)  <- "Safety Population Flag"
```

Apply variable labels using `Hmisc::label()` or `haven::write_xpt()` attributes
per the ADaM spec metadata. Dataset label should be "Subject-Level Analysis Dataset".

---

## Code quality requirements

Generated code must meet these standards for QC-readiness:

- **Comments:** Each derivation block must have a comment referencing the source
  variable (e.g. `# TRTSDT: first dose date from EX.EXSTDTC per ADaM spec §4.2`)
- **Human review flags:** Use `# REVIEW:` comments where protocol-specific
  decisions are required (population flags, disposition record selection, cut points)
- **No silent failures:** Use `stopifnot()` or `cli::cli_abort()` for critical
  assertions (one record per subject, required variables present)
- **Pipe style:** Use the native pipe `|>` and `exprs()` for admiral verb arguments
- **No manual date arithmetic:** Always use admiral date derivation functions

---

## Common errors to avoid

- Using `slice(1)` or manual `group_by/summarise` instead of `derive_vars_merged()` with `mode`
- Setting `date_imputation = "none"` when partial dates are present in SDTM
- Conflating TRT01P (planned, from DM.ARM) with TRT01A (actual, from EX)
- Assuming DS has one record per subject — always filter to the correct DSCAT
- Using `"N"` for flag variables — CDISC convention is `"Y"` or `NA`, never `"N"`
- Hardcoding AGEGR1 cut points — always take these from the ADaM spec

---

## Output checklist

Before returning code, verify:

- [ ] One record per USUBJID confirmed with `stopifnot()`
- [ ] All required variables present
- [ ] All `# REVIEW:` comments placed at protocol-specific decision points
- [ ] Date imputation arguments explicitly set (not left as defaults)
- [ ] Population flag derivations annotated with protocol reference
- [ ] Dataset and variable labels applied
