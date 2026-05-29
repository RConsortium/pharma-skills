---
name: admiral
description: >
  Parent skill for the admiral ADaM derivation family. Covers shared
  conventions used across all admiral child skills: library setup, pipe
  style, date derivation rules, flag variable conventions, and QC patterns.
  Route to a child skill for dataset-specific derivation workflows.
license: MIT
metadata:
  author: Navitas Data Sciences
  version: "0.1"
  pharmaverse: "true"
---

# admiral (parent skill)

This skill defines the shared conventions that apply across all admiral ADaM
derivation skills in this family. When a child skill is loaded, this parent
provides the foundation — child skills reference these conventions rather than
repeating them.

---

## Skill Routing

Choose the child skill that matches the target ADaM dataset type:

| Dataset type | Child skill | Description |
|---|---|---|
| ADSL — Subject-Level | `admiral/admiral-adsl` | Treatment dates, disposition, population flags |
| BDS — Findings (ADVS, ADLB) | `admiral/admiral-bds` | Parameters, baseline, change from baseline |
| OCCDS — Adverse Events | `admiral/admiral-adae` | *(planned)* |
| TTE — Time to Event | `admiral/admiral-adtte` | *(planned)* |

ADSL must be derived before any BDS or OCCDS dataset — population flags and
treatment variables from ADSL are merged into all downstream datasets.

---

## Shared Library Setup

Every admiral derivation script begins with this setup block. Add dataset-specific
libraries (e.g. `metatools`, `tfrmt`) per child skill requirements.

```r
library(admiral)
library(dplyr)
library(lubridate)

# For submission-ready output
library(metacore)
library(xportr)

# For benchmark reproducibility
library(pharmaversesdtm)
library(pharmaverseadam)
```

---

## Pipe and Expression Style

**Always use the native pipe `|>`** — not the magrittr pipe `%>%`. admiral
functions accept `|>` and it is the pharmaverse standard for new code.

**Always use `exprs()` for admiral verb arguments** that accept variable lists.
The `exprs()` wrapper is required for `by_vars`, `new_vars`, `order`, and
`source_vars` arguments in admiral functions. Bare variable names or character
strings will not work.

```r
# CORRECT
derive_vars_merged(
  by_vars  = exprs(STUDYID, USUBJID),
  new_vars = exprs(TRTSDT = EXSTDT),
  order    = exprs(EXSTDT)
)

# WRONG — does not work with admiral
derive_vars_merged(
  by_vars  = c("STUDYID", "USUBJID"),
  new_vars = c(TRTSDT = EXSTDT)
)
```

---

## Date Derivation Rules

**Never use `as.Date()`, `as.POSIXct()`, or `convert_dtc_to_date()` directly
on `--DTC` variables.** These silently return `NA` for partial dates (e.g.
`"2023-06"`, `"2023"`) without any warning.

Always use the admiral date functions:

| Goal | Function |
|---|---|
| `--DTC` → Date variable | `derive_vars_dt()` |
| `--DTC` → Datetime variable | `derive_vars_dtm()` |
| Study day from dates | `derive_vars_dy()` |
| Treatment duration | `derive_var_trtdurd()` |

### Imputation direction

| Date type | Rule | admiral argument |
|---|---|---|
| Start dates (TRTSDT, ADT for start events) | Impute to earliest | `date_imputation = "first"` |
| End dates (TRTEDT, EOSDT) | Impute to latest | `date_imputation = "last"` |
| Time when absent — start | `"00:00:00"` | `time_imputation = "first"` |
| Time when absent — end | `"23:59:59"` | `time_imputation = "last"` |

**Always use `flag_imputation = "auto"`** — this auto-generates `--DTF` and
`--TMF` imputation flag variables. Never suppress imputation flags.

```r
# Correct date derivation pattern
source_dt <- source_domain |>
  derive_vars_dt(
    dtc             = XXDTC,
    new_vars_prefix = "XX",
    date_imputation = "first",
    flag_imputation = "auto"
  )
```

### Study day convention

CDISC study day: Day 1 is the reference date; there is no Day 0. Always use
`derive_vars_dy()`. Never compute manually with `date2 - date1`.

---

## Flag Variable Convention

**Flag variables must be `"Y"` or `NA` — never `"N"`.**

This applies to all flag types: population flags (`--FL`), baseline flags
(`ABLFL`), analysis flags (`ANL01FL`), and any other indicator variable.

```r
# CORRECT
mutate(SAFFL = if_else(has_dose, "Y", NA_character_))

# WRONG — violates CDISC ADaM convention
mutate(SAFFL = if_else(has_dose, "Y", "N"))
```

When using `derive_var_merged_exist_flag()`, always set both:
- `true_value    = "Y"`
- `false_value   = NA_character_`
- `missing_value = NA_character_`

---

## DOMAIN Variable Removal

Remove `DOMAIN` from source datasets before passing to `derive_vars_merged()`.
admiral errors if a variable exists in both the input dataset and the source.

```r
# Pattern for ADSL and all BDS derivations
adsl <- adsl |>
  derive_vars_merged(
    dataset_add = select(ex, -DOMAIN),
    by_vars     = exprs(STUDYID, USUBJID),
    ...
  )
```

This applies to all SDTM source domains — EX, DS, VS, LB, AE, etc.

---

## QC Patterns

### Uniqueness assertions

Use `stopifnot()` to assert structural assumptions before proceeding. These
catch data quality issues early and prevent misleading downstream results.

```r
# Assert one record per subject in DM
stopifnot(nrow(dm) == n_distinct(dm$USUBJID))

# Assert uniqueness in a source dataset before merging
stopifnot(n_distinct(ds_eos$USUBJID) == nrow(ds_eos))

# Assert required structure at end of derivation
stopifnot(nrow(adsl) == n_distinct(adsl$USUBJID))
```

### `# REVIEW:` annotations

Every protocol-specific decision point in generated code must have a `# REVIEW:`
comment. This is a required output dimension evaluated in all benchmarks.

Required locations:
- Population flag definitions (SAFFL, ITTFL, PPROTFL, ANL01FL)
- Disposition record selection logic
- Age/BMI/lab categorisation cut-points
- Treatment arm coding and numeric assignments
- Baseline window definitions
- Any filter condition that may need protocol-specific adjustment

```r
# REVIEW: SAFFL definition is protocol-specific. Confirm EXTRT values in EX
#   and verify placebo handling against the protocol and SAP before use.
adsl <- adsl |>
  derive_var_merged_exist_flag(
    dataset_add   = ex,
    new_var       = SAFFL,
    condition     = (EXDOSE > 0 | EXTRT == "PLACEBO") & !is.na(EXSTDTC),
    ...
  )
```

---

## Shared References

The following reference files are shared across the admiral skill family:

| Reference | Location | Content |
|---|---|---|
| Function selection guide | `admiral-adsl/references/admiral-functions.md` | `derive_vars_merged`, date/flag functions, common pitfalls |
| ADSL variable conventions | `admiral-adsl/references/adsl-conventions.md` | Required variables, CT, naming rules |
| BDS variable conventions | `admiral-bds/references/bds-conventions.md` | BDS structure, parameter/timing/analysis variables |
