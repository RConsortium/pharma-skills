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
  version: "0.2"
  pharmaverse: "true"
  parent: admiral
compatibility: >
  Requires R with admiral, dplyr, lubridate, and pharmaversesdtm installed.
  Designed for use in a GxP-compliant environment with access to SDTM datasets
  and an ADaM ADSL specification.
---

# admiral-adsl

> Shared conventions (library setup, pipe style, date rules, flag convention,
> `# REVIEW:` annotations, `stopifnot()` patterns) are defined in the parent
> [`../SKILL.md`](../SKILL.md). The workflow below is ADSL-specific.

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
library(pharmaversesdtm)

# Load SDTM domains
dm  <- pharmaversesdtm::dm
ex  <- pharmaversesdtm::ex
ds  <- pharmaversesdtm::ds
# mh <- pharmaversesdtm::mh  # uncomment if in scope

# Confirm one record per USUBJID in DM before proceeding
stopifnot(nrow(dm) == n_distinct(dm$USUBJID))
```

### Step 2 — Subject spine

Start from DM. One record per USUBJID is mandatory at this step and must be
preserved throughout. Select only variables needed downstream.

```r
adsl <- dm |>
  select(
    STUDYID, USUBJID, SUBJID, SITEID,
    AGE, AGEU, SEX, RACE, ETHNIC, COUNTRY,
    ARM, ARMCD, ACTARM, ACTARMCD,
    DMDTC, RFSTDTC, RFENDTC,
    DTHFL, DTHDTC
  )
```

### Step 3 — Treatment dates (TRTSDTM, TRTSTMF, TRTEDTM, TRTETMF, TRTSDT, TRTEDT)

Derive datetimes first, then extract date-only variables. Always include
`time_imputation` arguments and always retain imputation flags (TRTSTMF,
TRTETMF) in `new_vars` — setting `flag_imputation = "auto"` without capturing
the flag variables provides no traceability benefit.

Remove DOMAIN from EX before merging to avoid variable conflicts.

```r
ex_dtm <- ex |>
  select(-DOMAIN) |>
  derive_vars_dtm(
    dtc             = EXSTDTC,
    new_vars_prefix = "EXST",
    date_imputation = "first",
    time_imputation = "first",
    flag_imputation = "auto"
  ) |>
  derive_vars_dtm(
    dtc             = EXENDTC,
    new_vars_prefix = "EXEN",
    date_imputation = "last",
    time_imputation = "last",
    flag_imputation = "auto"
  )

# TRTSDTM / TRTSTMF: first dose datetime and imputation flag
# REVIEW: The placebo filter (EXTRT == "PLACEBO") must be confirmed against the
#   protocol. In some studies EXDOSE > 0 is sufficient; in others EXDOSE = 0
#   for placebo and EXTRT must be used. Adjust condition per protocol definition.
adsl <- adsl |>
  derive_vars_merged(
    dataset_add = ex_dtm,
    by_vars     = exprs(STUDYID, USUBJID),
    new_vars    = exprs(TRTSDTM = EXSTDTM, TRTSTMF = EXSTTMF),
    order       = exprs(EXSTDTM),
    mode        = "first",
    filter_add  = (EXDOSE > 0 | EXTRT == "PLACEBO") & !is.na(EXSTDTM)
  ) |>
  # TRTEDTM / TRTETMF: last dose datetime and imputation flag
  # REVIEW: If subjects have non-contiguous EX records, TRTEDTM reflects the
  #   last administration date only. Flag for QC if exposure gaps exist.
  derive_vars_merged(
    dataset_add = ex_dtm,
    by_vars     = exprs(STUDYID, USUBJID),
    new_vars    = exprs(TRTEDTM = EXENDTM, TRTETMF = EXENTMF),
    order       = exprs(EXENDTM),
    mode        = "last",
    filter_add  = (EXDOSE > 0 | EXTRT == "PLACEBO") & !is.na(EXENDTM)
  ) |>
  mutate(
    TRTSDT = as.Date(TRTSDTM),
    TRTEDT = as.Date(TRTEDTM)
  )
```

### Step 4 — Planned and actual treatment (TRT01P, TRT01PN, TRT01A, TRT01AN)

Use `derive_vars_merged_lookup()` with a treatment lookup tibble — this is the
idiomatic admiral approach for controlled terminology mapping and is preferred
over `case_when()` or `mutate()` for treatment arm coding.

TRT01P/TRT01PN: from DM.ARMCD (planned). TRT01A/TRT01AN: from DM.ACTARMCD
(actual). These are distinct — derive independently.

```r
# REVIEW: Confirm ARMCD values, treatment labels, and numeric codes against
#   the randomisation schedule and ADaM spec before use.
arm_lookup <- tibble::tribble(
  ~ARMCD,    ~TRT01P,                   ~TRT01PN,
  "Pbo",     "Placebo",                 1L,
  "Xan_Lo",  "Xanomeline Low Dose",     2L,
  "Xan_Hi",  "Xanomeline High Dose",    3L
  # Screen failure subjects (Scrnfail) are not in the lookup — they receive NA
)

adsl <- adsl |>
  derive_vars_merged_lookup(
    dataset_add = arm_lookup,
    by_vars     = exprs(ARMCD),
    new_vars    = exprs(TRT01P, TRT01PN)
  ) |>
  derive_vars_merged_lookup(
    dataset_add = arm_lookup |>
      rename(ACTARMCD = ARMCD, TRT01A = TRT01P, TRT01AN = TRT01PN),
    by_vars     = exprs(ACTARMCD),
    new_vars    = exprs(TRT01A, TRT01AN)
  )
```

### Step 5 — Randomisation and reference dates

Use `derive_vars_dt()` for all date conversions from DM — never use
`as.Date()` directly on `--DTC` variables as this bypasses partial date
imputation handling.

```r
adsl <- adsl |>
  # RANDDT: date of randomisation from DM.DMDTC
  # REVIEW: Confirm DMDTC is the randomisation date in this study. In some
  #   studies randomisation date comes from a separate SDTM domain (e.g. RS).
  derive_vars_dt(
    dtc             = DMDTC,
    new_vars_prefix = "RAND",
    date_imputation = "first",
    flag_imputation = "auto"
  ) |>
  derive_vars_dt(
    dtc             = RFSTDTC,
    new_vars_prefix = "RFST",
    date_imputation = "first",
    flag_imputation = "auto"
  ) |>
  derive_vars_dt(
    dtc             = RFENDTC,
    new_vars_prefix = "RFEND",
    date_imputation = "last",
    flag_imputation = "auto"
  )
```

### Step 6 — Death variables

```r
adsl <- adsl |>
  derive_vars_dt(
    dtc             = DTHDTC,
    new_vars_prefix = "DTH",
    date_imputation = "first",
    flag_imputation = "auto"
  ) |>
  mutate(
    # Ensure CDISC flag convention: "Y" or NA — never "N"
    DTHFL = if_else(DTHFL == "Y", "Y", NA_character_)
  )
```

### Step 7 — Study day variables

Use `derive_vars_dy()` — do not compute manually with date subtraction.

```r
adsl <- adsl |>
  derive_vars_dy(
    reference_date = TRTSDT,
    source_vars    = exprs(RANDDT)
  )
```

### Step 8 — Treatment duration

```r
adsl <- adsl |>
  derive_var_trtdurd()
  # Requires TRTSDT and TRTEDT to be present. NA for untreated subjects.
```

### Step 9 — Disposition (EOSSTT, DCSREAS, EOSDT)

Filter DS to `DSCAT == "DISPOSITION EVENT"`. Verify uniqueness before merging.
Categorise EOSSTT **within the source dataset** before the merge — never pass
`DSDECOD` through directly to EOSSTT, as DSDECOD contains reason values
(`"ADVERSE EVENT"`, `"SCREEN FAILURE"`) not status values.

Derive DCSREAS in a separate `derive_vars_merged()` call filtered to
discontinued subjects only — this avoids a post-merge `mutate()` cleanup step.

```r
ds_eos <- ds |>
  select(-DOMAIN) |>
  filter(DSCAT == "DISPOSITION EVENT") |>
  derive_vars_dt(
    dtc             = DSDTC,
    new_vars_prefix = "DS",
    date_imputation = "last",
    flag_imputation = "auto"
  )

# Confirm one DISPOSITION EVENT record per subject
stopifnot(n_distinct(ds_eos$USUBJID) == nrow(ds_eos))

# EOSSTT: end of study status — "COMPLETED" or "DISCONTINUED" only
# REVIEW: Verify the COMPLETED/DISCONTINUED mapping covers all DSDECOD values
#   in this study's DS domain. Some protocols require a third category for
#   "STUDY TERMINATED BY SPONSOR". Confirm with the statistician.
adsl <- adsl |>
  derive_vars_merged(
    dataset_add = ds_eos |>
      mutate(
        EOSSTT = if_else(DSDECOD == "COMPLETED", "COMPLETED", "DISCONTINUED")
      ),
    by_vars  = exprs(STUDYID, USUBJID),
    new_vars = exprs(EOSSTT, EOSDT = DSDT)
  ) |>
  # DCSREAS: decoded discontinuation reason — NA for completers per CDISC convention
  # REVIEW: DCSREAS is sourced from DS.DSDECOD (decoded value). DS.DSTERM
  #   (verbatim text) belongs in DCSREASP. Do not swap these.
  derive_vars_merged(
    dataset_add = ds_eos |>
      filter(DSDECOD != "COMPLETED"),
    by_vars  = exprs(STUDYID, USUBJID),
    new_vars = exprs(DCSREAS = DSDECOD, DCSREASP = DSTERM)
  )
```

### Step 10 — Baseline demographics

Derive AGE groupings per the ADaM spec. **The example cut-points below are
placeholders only** — always replace with the study-specific values from the
ADaM spec. Do not use these defaults without explicit confirmation.

```r
# REVIEW: Age cut-points must come from the ADaM spec — they are study-specific.
#   The values below are placeholders. Replace before use.
adsl <- adsl |>
  mutate(
    AGEGR1 = case_when(
      AGE < 65              ~ "<65",     # PLACEHOLDER — confirm from spec
      AGE >= 65 & AGE <= 80 ~ "65-80",  # PLACEHOLDER — confirm from spec
      AGE > 80              ~ ">80"      # PLACEHOLDER — confirm from spec
    ),
    AGEGR1N = case_when(
      AGEGR1 == "<65"   ~ 1L,
      AGEGR1 == "65-80" ~ 2L,
      AGEGR1 == ">80"   ~ 3L
    )
  )
```

If VS is in scope, derive HEIGHTBL, WEIGHTBL, BMIBL using
`derive_vars_merged()` from the baseline VS records (VSBLFL == "Y").

### Step 11 — Population flags (SAFFL, ITTFL, PPROTFL)

**Critical:** population flag definitions are protocol-specific. The derivations
below implement standard logic but must be reviewed against the protocol and SAP
before use. Flag is `"Y"` or `NA` only — never `"N"`.

```r
# SAFFL: received at least one dose
# REVIEW: SAFFL definition is protocol-specific. The condition below includes
#   placebo subjects (EXTRT == "PLACEBO") who have EXDOSE = 0 in some studies.
#   Verify EXTRT values in EX exhaustively and confirm with the statistician.
adsl <- adsl |>
  derive_var_merged_exist_flag(
    dataset_add   = ex,
    by_vars       = exprs(STUDYID, USUBJID),
    new_var       = SAFFL,
    condition     = (EXDOSE > 0 | EXTRT == "PLACEBO") & !is.na(EXSTDTC),
    true_value    = "Y",
    false_value   = NA_character_,
    missing_value = NA_character_
  ) |>
  # ITTFL: randomised subjects — ARMCD != "Scrnfail" AND ARM != "Screen Failure"
  # REVIEW: Confirm ITTFL exclusion criteria with the statistician. The ARMCD
  #   condition is more reliable than ARM text matching — use both as a safeguard.
  mutate(
    ITTFL = if_else(
      ARMCD != "Scrnfail" & ARM != "Screen Failure",
      "Y",
      NA_character_
    )
  )
  # PPROTFL: per protocol — highly protocol-specific
  # REVIEW: Derive per SAP definition with protocol deviation exclusions.
  # mutate(PPROTFL = if_else(ITTFL == "Y" & no_major_deviations, "Y", NA_character_))
```

### Step 12 — Dataset attributes and final checks

```r
# One record per USUBJID — non-negotiable per ADaMIG; FDA will reject if violated
stopifnot(nrow(adsl) == n_distinct(adsl$USUBJID))

# Check required variables are present
required_vars <- c(
  "STUDYID", "USUBJID", "TRTSDT", "TRTEDT",
  "TRT01P", "TRT01PN", "TRT01A", "TRT01AN",
  "TRTSDTM", "TRTSTMF", "TRTEDTM", "TRTETMF",
  "EOSSTT", "SAFFL", "ITTFL"
)
missing_vars <- setdiff(required_vars, names(adsl))
if (length(missing_vars) > 0) {
  stop("Missing required ADSL variables: ", paste(missing_vars, collapse = ", "))
}

# Apply variable labels — use xportr for submission context
# adsl <- adsl |>
#   xportr_label(metacore_obj, domain = "ADSL") |>
#   xportr_type(metacore_obj, domain = "ADSL") |>
#   xportr_length(metacore_obj, domain = "ADSL") |>
#   xportr_order(metacore_obj, domain = "ADSL")
# xportr_write(adsl, "adsl.xpt", label = "Subject-Level Analysis Dataset")
#
# For non-submission contexts:
# Hmisc::label(adsl$TRTSDT) <- "Date of First Study Treatment"
# Hmisc::label(adsl$SAFFL)  <- "Safety Population Flag"
```

---

## Code quality requirements

Generated code must meet these standards for QC-readiness:

- **Comments:** Each derivation block must have a comment referencing the source
  variable (e.g. `# TRTSDT: first dose date from EX.EXSTDTC per ADaM spec §4.2`)
- **Human review flags:** Use `# REVIEW:` comments where protocol-specific
  decisions are required (population flags, disposition record selection,
  cut-points, treatment arm coding)
- **No silent failures:** Use `stopifnot()` for critical assertions (one record
  per subject at DM load, DS uniqueness before merge, required variables present)
- **Pipe style:** Use the native pipe `|>` and `exprs()` for admiral verb arguments
- **No manual date arithmetic:** Always use admiral date derivation functions

---

## Common errors to avoid

- Using `slice()`, `slice_min()`, `slice_max()`, or manual `group_by/summarise`
  instead of `derive_vars_merged()` with `mode`
- Using `as.Date()`, `as.POSIXct()`, `convert_dtc_to_date()`, or
  `convert_dtc_to_datetime()` directly on `--DTC` variables — always use
  `derive_vars_dt()` or `derive_vars_dtm()`
- Setting `flag_imputation = "date"` instead of `"auto"` — `"date"` only
  generates a date imputation flag and silently drops the time imputation flag
- Setting `flag_imputation = "auto"` without including the generated flag
  variables (e.g. TRTSTMF, TRTETMF) in `new_vars` — the flags must be
  explicitly requested to appear in the output
- Setting `date_imputation = "none"` for reference or death dates — partial
  dates will return `NA` silently; use `"first"` for start dates and `"last"`
  for end dates
- Passing `DSDECOD` directly to EOSSTT without categorisation — DSDECOD
  contains reason values (`"ADVERSE EVENT"`, `"SCREEN FAILURE"`) not status
  values; EOSSTT must be `"COMPLETED"` or `"DISCONTINUED"` only
- Mapping DCSREAS from `DSTERM` (verbatim) instead of `DSDECOD` (decoded) —
  `DCSREAS` = decoded value, `DCSREASP` = verbatim text
- Using `case_when()` for treatment arm coding when `derive_vars_merged_lookup()`
  is available — the lookup function is more idiomatic and spec-driven
- Not removing `DOMAIN` from source datasets before `derive_vars_merged()` calls
- Using `"N"` for flag variables — CDISC convention is `"Y"` or `NA`, never `"N"`
- Hardcoding AGEGR1 cut-points without a `# REVIEW:` annotation — these are
  always study-specific and must come from the ADaM spec

---

## Output checklist

Before returning code, verify:

- [ ] DM uniqueness confirmed with `stopifnot()` at load
- [ ] DS uniqueness confirmed with `stopifnot()` before disposition merge
- [ ] One record per USUBJID confirmed with `stopifnot()` at end
- [ ] All required variables present
- [ ] TRTSTMF and TRTETMF present in output and captured in `new_vars`
- [ ] All `# REVIEW:` comments placed at protocol-specific decision points
- [ ] `date_imputation` and `time_imputation` arguments explicitly set
- [ ] `flag_imputation = "auto"` used — not `"date"` or `"none"`
- [ ] EOSSTT contains only `"COMPLETED"` or `"DISCONTINUED"`
- [ ] DCSREAS is `NA` for all completers
- [ ] Population flag derivations annotated with protocol reference
- [ ] Dataset and variable labels applied