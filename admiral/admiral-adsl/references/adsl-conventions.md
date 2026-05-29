# ADSL Conventions Reference

CDISC ADaM conventions for ADSL dataset construction. This reference covers
variable requirements, naming rules, controlled terminology, flag conventions,
dataset attributes, and define.xml metadata expectations. It is intended as a
compact, programming-facing reference — not a substitute for the ADaMIG v1.3.

---

## Structure Rule: One Record Per Subject

ADSL contains one record per subject. This is
non-negotiable and must be verified programmatically before delivery:

```r
stopifnot(nrow(adsl) == n_distinct(adsl$USUBJID))
```

The FDA has explicitly refused ADSL structures with more than one record per
unique subject. Any multi-period or integrated analysis requirements must be
handled through additional datasets (ADPL, period-specific BDS variables), not
by adding rows to ADSL.

---

## Required Variables

Required variables that must be included in every ADSL — all can be taken
directly from the DM dataset:

| Variable | Type | Source | Notes |
|---|---|---|---|
| STUDYID | Char | DM | Study identifier |
| USUBJID | Char | DM | Unique subject identifier — primary key |
| SUBJID | Char | DM | Subject identifier within site |
| SITEID | Char | DM | Study site identifier |
| AGE | Num | DM | Age at study entry |
| AGEU | Char | DM | Age units — usually `"YEARS"` |
| SEX | Char | DM | CDISC CT: `"M"`, `"F"`, `"U"`, `"UNDIFFERENTIATED"` |
| RACE | Char | DM | CDISC CT — see Race CT section below |

When carrying SDTM variables into ADSL without modification, the variable name
**and all attributes** (label, format, length) must be preserved unchanged.

---

## Conditionally Required Variables

These variables are required when the concept applies to the study:

| Variable | Required when | Notes |
|---|---|---|
| TRT01P | Randomised study | Planned treatment period 1 |
| TRT01A | Randomised study | Actual treatment period 1 |
| TRTSDT | Subject received treatment | First treatment start date |
| TRTEDT | Subject received treatment | Last treatment end date |
| RANDDT | Randomised study | Date of randomisation |
| DTHFL | Death is an endpoint or safety concern | Death flag |
| DTHDT | DTHFL = "Y" | Date of death |

For multi-period studies, period-specific variables (TRT02P, TRT02A, TR02SDT,
TR02EDT, etc.) follow the same pattern with incrementing period numbers.

---

## Common Permissible Variables

These are not required by CDISC but are expected in most submissions:

**Demographics and baseline:**

| Variable | Type | Derivation source | Notes |
|---|---|---|---|
| ETHNIC | Char | DM | CDISC CT |
| COUNTRY | Char | DM | ISO 3166 alpha-3 |
| BRTHDTC | Char | DM | Birth date character |
| AGEGR1 | Char | Derived from AGE | Cut points from ADaM spec |
| AGEGR1N | Num | Derived from AGEGR1 | Numeric version |
| HEIGHTBL | Num | VS (VSBLFL="Y") | Baseline height |
| WEIGHTBL | Num | VS (VSBLFL="Y") | Baseline weight |
| BMIBL | Num | Derived | kg/m² — use `derive_vars_computed()` |
| RACE1 | Char | DM or suppDM | For multi-race capture |

**Treatment:**

| Variable | Type | Source | Notes |
|---|---|---|---|
| TRT01PN | Num | Derived | Numeric code for TRT01P |
| TRT01AN | Num | Derived | Numeric code for TRT01A |
| TRTSEQP | Char | DM.ARMCD | Planned treatment sequence (crossover) |
| TRTSEQA | Char | EX | Actual treatment sequence (crossover) |
| TRTDURD | Num | Derived | Total treatment duration (days) |

**Disposition:**

| Variable | Type | Source | Notes |
|---|---|---|---|
| EOSSTT | Char | DS | End of study status |
| DCSREAS | Char | DS | Reason for discontinuation (decoded) |
| DCSREASP | Char | DS | Reason for discontinuation (verbatim) |
| EOSDT | Num | DS | End of study date |
| EOSDY | Num | Derived | End of study day relative to TRTSDT |

**Dates and days:**

| Variable | Type | Notes |
|---|---|---|
| TRTSDT | Num | First dose date — Date class |
| TRTEDT | Num | Last dose date — Date class |
| TRTSDTM | Num | First dose datetime — POSIXct if time in EX |
| TRTEDTM | Num | Last dose datetime — POSIXct if time in EX |
| RANDDT | Num | Randomisation date |
| RANDDY | Num | Randomisation day (relative to TRTSDT) |

---

## Population Flag Variables

Character flags are needed for each analysis population defined
in the SAP, and at least one must be present for each trial. Standard flags
include ENRLFL (enrolled), RANDFL (randomised), SAFFL (safety), ITTFL (ITT),
and FASFL (full analysis set).

### Flag Value Convention

**Critical:** CDISC ADaM convention for flag variables is `"Y"` or `NA`.
Never use `"N"`.

```r
# CORRECT
mutate(SAFFL = if_else(has_dose, "Y", NA_character_))

# WRONG — violates CDISC ADaM convention
mutate(SAFFL = if_else(has_dose, "Y", "N"))
```

This applies to ALL flag variables in ADSL: population flags (`--FL`), baseline
flags (`ABLFL`), and any other indicator variable.

### Standard Population Flags

| Flag | Label | Typical definition |
|---|---|---|
| ENRLFL | Enrolled Population Flag | All subjects who signed informed consent |
| RANDFL | Randomised Population Flag | All subjects who were randomised (DM.ARM not null/screen failure) |
| SAFFL | Safety Population Flag | Received at least one dose of study treatment (EXDOSE > 0) |
| ITTFL | Intent-to-Treat Population Flag | Randomised; definition varies — verify against protocol |
| FASFL | Full Analysis Set Flag | Protocol-defined; often same as ITTFL or broader |
| PPROTFL | Per-Protocol Population Flag | Highly protocol-specific — always requires statistician input |
| COMPLFL | Completers Flag | Completed the study per protocol |

**Every population flag derivation must be reviewed against the protocol and SAP.**
The definitions above are starting points only. Add `# REVIEW:` comments for
each flag and document the protocol reference.

### Numeric Companion Variables

For any flag used in subgroup analysis, a numeric version is often needed for
sorting and TLF production:

```r
mutate(
  SAFFL  = if_else(has_dose, "Y", NA_character_),
  SAFFLN = if_else(SAFFL == "Y", 1, NA_real_)
)
```

---

## Naming Conventions

### Treatment Period Variables

For multi-period studies, variables follow a strict naming pattern:

| Pattern | Meaning | Example |
|---|---|---|
| `TRT0xP` | Planned treatment, period x | TRT01P, TRT02P |
| `TRT0xA` | Actual treatment, period x | TRT01A, TRT02A |
| `TRT0xPN` | Numeric code for planned treatment | TRT01PN |
| `TRT0xAN` | Numeric code for actual treatment | TRT01AN |
| `TR0xSDT` | Treatment start date, period x | TR01SDT |
| `TR0xEDT` | Treatment end date, period x | TR01EDT |
| `AP0xSDT` | Analysis period start date | AP01SDT |
| `AP0xEDT` | Analysis period end date | AP01EDT |

### Baseline Variables

Baseline values carried into ADSL follow the pattern `{test}BL`:

| Example | Meaning |
|---|---|
| HEIGHTBL | Baseline height |
| WEIGHTBL | Baseline weight |
| BMIBL | Baseline BMI |
| CREATBL | Baseline creatinine |

### Categorisation Variables

Grouping/categorisation variables follow `{var}GR{n}` and `{var}GR{n}N`:

| Example | Meaning |
|---|---|
| AGEGR1 | Age group 1 (character) |
| AGEGR1N | Age group 1 numeric |
| BMIGRP1 | BMI group 1 |

The `N` suffix always denotes the numeric version of a character variable.
Both must be present if used in analysis.

---

## Controlled Terminology

### SEX

From CDISC CT (SDTM Codelist C66731):

| Code | Decode |
|---|---|
| `"F"` | Female |
| `"M"` | Male |
| `"U"` | Unknown |
| `"UNDIFFERENTIATED"` | Undifferentiated |

### RACE

From CDISC CT (SDTM Codelist C74457). Standard values:

- `"AMERICAN INDIAN OR ALASKA NATIVE"`
- `"ASIAN"`
- `"BLACK OR AFRICAN AMERICAN"`
- `"NATIVE HAWAIIAN OR OTHER PACIFIC ISLANDER"`
- `"WHITE"`
- `"MULTIPLE"`
- `"OTHER"`
- `"NOT REPORTED"`
- `"UNKNOWN"`

When subjects select multiple races, RACE is typically set to `"MULTIPLE"` in
DM and individual selections are captured in suppDM or a separate variable
(RACE1, RACE2, etc.).

### ETHNIC

From CDISC CT (SDTM Codelist C66790):

| Code |
|---|
| `"HISPANIC OR LATINO"` |
| `"NOT HISPANIC OR LATINO"` |
| `"NOT REPORTED"` |
| `"UNKNOWN"` |

### EOSSTT (End of Study Status)

Common values — verify against study protocol and DS controlled terminology:

| Value | Meaning |
|---|---|
| `"COMPLETED"` | Completed the study |
| `"DISCONTINUED"` | Discontinued before completion |

### DCSREAS (Discontinuation Reason)

Derived from DS.DSDECOD. Common values from CDISC CT (Codelist C66727) include:

- `"ADVERSE EVENT"`
- `"DEATH"`
- `"LACK OF EFFICACY"`
- `"LOST TO FOLLOW-UP"`
- `"PHYSICIAN DECISION"`
- `"PROTOCOL DEVIATION"`
- `"SPONSOR DECISION"`
- `"SUBJECT DECISION"`
- `"WITHDRAWAL BY SUBJECT"`

---

## Date Variable Conventions

### Types

| Admiral type | R class | XPT export | When to use |
|---|---|---|---|
| Date (`_DT`) | `Date` | Numeric (SAS date) | Date only — no time component |
| Datetime (`_DTM`) | `POSIXct` | Numeric (SAS datetime) | When time component is present in SDTM |

### Imputation Rules

When SDTM `--DTC` values are partial (e.g. `"2023-06"`, `"2023"`):

| Variable type | Imputation rule | admiral argument |
|---|---|---|
| Start dates (TRTSDT, RANDDT) | Impute to **earliest** possible date | `date_imputation = "first"` |
| End dates (TRTEDT, EOSDT) | Impute to **latest** possible date | `date_imputation = "last"` |
| Time (when time absent) | Start: `"00:00:00"`, End: `"23:59:59"` | `time_imputation = "first"` / `"last"` |

Imputation flags are auto-generated by admiral (`--DTF`, `--TMF`) and should be
retained in the dataset. Never suppress imputation flags.

### Study Day Convention

CDISC study day: the reference date is Day 1. There is no Day 0.

| Day | Meaning |
|---|---|
| 1 | Reference date (e.g. TRTSDT) |
| 2 | Day after reference |
| -1 | Day before reference |

Always use `derive_vars_dy()`. Never compute manually.

---

## Dataset Attributes

### Dataset-Level

| Attribute | Value |
|---|---|
| Dataset label | `"Subject-Level Analysis Dataset"` |
| Dataset name | `ADSL` |
| One record per | Subject (USUBJID) |

Apply in R using `haven::write_xpt()` with `label` argument, or via `{metacore}`
and `{xportr}` for spec-driven attribute application:

```r
# Using xportr (recommended for submission)
adsl |>
  xportr_label(metacore, domain = "ADSL") |>
  xportr_type(metacore, domain = "ADSL") |>
  xportr_length(metacore, domain = "ADSL") |>
  xportr_order(metacore, domain = "ADSL") |>
  xportr_write("adsl.xpt", label = "Subject-Level Analysis Dataset")
```

### Variable-Level Attributes

Every variable must have:
- **Label** — from the ADaM spec; max 40 characters
- **Type** — character or numeric (SAS conventions: Char = `$`, Num = 8-byte float)
- **Length** — from the ADaM spec; character variables have explicit lengths

Apply labels before export, not during derivation. Derivation steps may strip
attributes; always apply as a final step.

```r
# Using Hmisc (simple alternative for non-submission work)
Hmisc::label(adsl$TRTSDT) <- "Date of First Study Treatment"
Hmisc::label(adsl$SAFFL)  <- "Safety Population Flag"
```

---

## define.xml Expectations

ADSL metadata submitted in define.xml must include for each variable:

- Variable name, label, type, length
- Origin (`Derived`, `Assigned`, or the SDTM source domain/variable)
- Codelist reference (for variables with controlled terminology)
- Derivation/comment (derivation logic in plain language)
- Core status (Required / Conditionally Required / Permissible)

Variables taken directly from SDTM (e.g. AGE, SEX from DM) should have
origin `"Predecessor"` referencing the SDTM variable, not `"Derived"`.

---

## Variable Order Convention

ADSL variable order in the XPT file should follow the ADaM spec column order.
Use `xportr_order()` from `{xportr}` to enforce this programmatically from the
spec metadata. Do not rely on the order variables were added during derivation.

Standard grouping convention (not enforced by CDISC but widely expected):

1. Identifiers (STUDYID, USUBJID, SUBJID, SITEID)
2. Demographics (AGE, AGEU, AGEGR1, AGEGR1N, SEX, RACE, ETHNIC, COUNTRY)
3. Treatment (TRT01P, TRT01PN, TRT01A, TRT01AN, TRTSEQP, TRTSEQA)
4. Dates (RANDDT, TRTSDT, TRTEDT, TRTDURD)
5. Disposition (EOSSTT, DCSREAS, DCSREASP, EOSDT)
6. Population flags (ENRLFL, RANDFL, ITTFL, FASFL, SAFFL, PPROTFL)
7. Stratification variables
8. Baseline values
9. Study-specific variables

---

## Common Reviewer Findings (to Avoid)

| Finding | Rule violated | Fix |
|---|---|---|
| `SAFFL = "N"` present | Flag convention: `"Y"` or `NA` only | Replace `"N"` with `NA_character_` |
| ADSL has >1 record per USUBJID | One record per subject | Identify and resolve duplicate |
| Variable label >40 chars | SAS XPT label length limit | Truncate; align with spec |
| TRTSDT missing for treated subjects | Required when treatment given | Check EX filter logic |
| DCSREAS populated for completers | Should be `NA` for subjects who completed | Add `EOSSTT == "DISCONTINUED"` filter |
| Imputation flag absent | ADaM traceability requirement | Retain `--DTF`/`--TMF` variables |
| Variables not in spec order in XPT | Submission expectation | Apply `xportr_order()` |
| TRT01P ≠ DM.ARM for randomised subject | Source mismatch | TRT01P must come from DM.ARM |
