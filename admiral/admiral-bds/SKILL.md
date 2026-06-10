---
name: admiral-bds
description: >
  Derives ADaM Basic Data Structure (BDS) datasets using the {admiral} R package.
  Initial scope covers ADVS (vital signs) and ADLB (laboratory values). Use when
  a user needs to create a BDS findings dataset from SDTM domains, derive
  parameter assignments, baseline values, change from baseline, visit windowing,
  or analysis flags, following CDISC ADaM conventions. Requires SDTM input data,
  an ADaM BDS specification, and a completed ADSL.
license: MIT
metadata:
  author: Navitas Data Sciences
  version: "0.1"
  pharmaverse: "true"
  parent: admiral
compatibility: >
  Requires R with admiral, dplyr, lubridate, and pharmaversesdtm installed.
  Requires a completed ADSL dataset. Designed for use in a GxP-compliant
  environment with access to SDTM datasets and an ADaM BDS specification.
---

# admiral-bds

> Shared conventions (library setup, pipe style, date rules, flag convention,
> `# REVIEW:` annotations, `stopifnot()` patterns) are defined in the parent
> [`../SKILL.md`](../SKILL.md). The workflow below is BDS-specific.

Derives CDISC-conformant BDS findings datasets using {admiral}. Outputs
executable, QC-ready R code for ADVS and ADLB with full derivation traceability.

See [bds-conventions reference](references/bds-conventions.md) for BDS variable
conventions and record structure. See
[`../admiral-adsl/references/admiral-functions.md`](../admiral-adsl/references/admiral-functions.md)
for function selection guidance shared across the admiral family.

---

## Inputs

Before generating code, confirm the following are available or explicitly noted
as absent:

| Input | Required | Notes |
|---|---|---|
| VS or LB | Yes | Source SDTM domain for ADVS or ADLB respectively |
| ADSL | Yes | Provides TRTSDT, TRTEDT, treatment variables, and population flags |
| ADaM BDS spec | Yes | Parameter list, derivation rules, visit windows, baseline definition |
| Study context | Yes | Baseline window, analysis flag definitions, visit map |

If ADSL is absent, stop and request it. ADSL variables are required before
baseline flagging and analysis flags can be derived.

---

## Workflow

Follow these steps in order. Generate code section by section, not as a single block.

### Step 1 — Setup and domain loading

```r
library(admiral)
library(dplyr)
library(lubridate)
library(pharmaversesdtm)

# Load source domain — replace with vs/lb per dataset being derived
vs  <- pharmaversesdtm::vs
adsl <- <loaded ADSL dataset>

# Remove DOMAIN to avoid conflicts in derive_vars_merged() calls
vs <- select(vs, -DOMAIN)
```

### Step 2 — Merge ADSL backbone variables

Bring required ADSL variables into the source dataset before any derivations.
At minimum: TRTSDT, TRTEDT, population flags used as analysis set criteria.

```r
# REVIEW: Confirm which population flags and ADSL variables are required by
#   the ADaM spec for this dataset. Add or remove from new_vars accordingly.
advs <- vs |>
  derive_vars_merged(
    dataset_add = adsl,
    by_vars     = exprs(STUDYID, USUBJID),
    new_vars    = exprs(TRTSDT, TRTEDT, TRT01P, TRT01PN, TRT01A, TRT01AN,
                        SAFFL, ITTFL)
  )
```

### Step 3 — Parameter assignment

Map SDTM test codes to ADaM parameters. Use `derive_vars_merged_lookup()` with a
lookup table driven by the ADaM spec. Do **not** use `derive_vars_merged()` here —
it is not a lookup function and will not correctly handle unmatched records. Do not use `case_when()` or
hardcoded `if_else()` chains.

```r
# REVIEW: PARAMCD mapping must match the ADaM spec parameter list exactly.
#   Confirm VSTESTCD values in VS and align with ADaM PARAMCD conventions.
#   Remove parameters not in scope for this study.
param_lookup <- tibble::tribble(
  ~VSTESTCD, ~PARAMCD, ~PARAM,                    ~PARAMN,
  "SYSBP",   "SYSBP",  "Systolic Blood Pressure",  1L,
  "DIABP",   "DIABP",  "Diastolic Blood Pressure",  2L,
  "PULSE",   "PULSE",  "Pulse Rate",                3L,
  "WEIGHT",  "WEIGHT", "Weight",                    4L,
  "HEIGHT",  "HEIGHT", "Height",                    5L,
  "TEMP",    "TEMP",   "Temperature",               6L
)

advs <- advs |>
  derive_vars_merged_lookup(
    dataset_add = param_lookup,
    by_vars     = exprs(VSTESTCD),
    new_vars    = exprs(PARAMCD, PARAM, PARAMN)
  ) |>
  filter(!is.na(PARAMCD))   # drop records for out-of-scope tests
```

For ADLB, map from LBTESTCD. Include units in PARAM text per ADaM spec.

### Step 4 — Analysis value (AVAL, AVALC)

AVAL is the numeric analysis value. AVALC is the character analysis value.
Derive from the SDTM result variables, applying unit conversions if required.

```r
advs <- advs |>
  mutate(
    AVAL  = VSSTRESN,    # numeric result in standard units
    AVALC = VSSTRESC,    # character result (for non-numeric or verbatim)
    AVALU = VSSTRESU     # analysis value units
  )
```

For ADLB, use LBSTRESN and LBSTRESC. If unit standardisation is required
(e.g. converting mg/dL to mmol/L), apply before AVAL assignment and add a
`# REVIEW:` comment referencing the protocol-specified units.

### Step 5 — Date derivation (ADT, ADTF, ADY)

```r
advs <- advs |>
  # ADT: analysis date from VSDTC
  derive_vars_dt(
    dtc             = VSDTC,
    new_vars_prefix = "A",
    date_imputation = "first",
    flag_imputation = "auto"
  ) |>
  # ADY: study day relative to TRTSDT
  derive_vars_dy(
    reference_date = TRTSDT,
    source_vars    = exprs(ADT)
  )
```

For ADLB, replace `VSDTC` with `LBDTC`.

### Step 6 — Visit assignment (AVISIT, AVISITN)

Map SDTM VISIT/VISITNUM to ADaM AVISIT/AVISITN. Use the visit map from the
ADaM spec — do not pass VISIT through directly to AVISIT.

```r
# REVIEW: Visit map must come from the ADaM spec. The example below is
#   illustrative. Confirm VISIT names and AVISITN codes against the study CRF
#   and ADaM spec before use.
visit_map <- tibble::tribble(
  ~VISIT,        ~AVISIT,       ~AVISITN,
  "SCREENING 1", "Screening",   -1L,
  "BASELINE",    "Baseline",     0L,
  "WEEK 2",      "Week 2",       2L,
  "WEEK 4",      "Week 4",       4L,
  "WEEK 8",      "Week 8",       8L,
  "WEEK 16",     "Week 16",     16L,
  "WEEK 26",     "Week 26",     26L
)

advs <- advs |>
  derive_vars_merged_lookup(
    dataset_add = visit_map,
    by_vars     = exprs(VISIT),
    new_vars    = exprs(AVISIT, AVISITN)
  )
```

For studies with date-driven visit windowing (ADT-based assignment), use
`derive_vars_joined()` with a window table that maps ADY ranges to analysis
visits instead of the direct VISIT lookup above.

### Step 7 — Baseline flagging (ABLFL)

The baseline record is the **last non-missing, non-excluded record on or before
TRTSDT** for each subject-parameter combination. Use `restrict_derivation()` +
`derive_var_extreme_flag()` — do not flag baseline with `mutate()` or `filter()`.

```r
# REVIEW: Baseline window definition is protocol-specific. Confirm whether
#   the baseline is the last pre-dose record (ADT <= TRTSDT), last on-or-before
#   treatment start, or a specific visit (e.g. DAY 1 only). Adjust filter below.
advs <- advs |>
  restrict_derivation(
    derivation = derive_var_extreme_flag,
    args = params(
      by_vars  = exprs(STUDYID, USUBJID, PARAMCD, BASETYPE),
      order    = exprs(ADT, AVISITN),
      new_var  = ABLFL,
      mode     = "last"
    ),
    filter = ADT <= TRTSDT & !is.na(AVAL)
  )
```

If multiple baseline definitions apply (e.g. last pre-dose and last
pre-treatment), add a `BASETYPE` variable to distinguish them before flagging.

### Step 8 — Baseline values (BASE, BASEC)

Derive BASE and BASEC from the flagged baseline records.

```r
advs <- advs |>
  derive_var_base(
    by_vars  = exprs(STUDYID, USUBJID, PARAMCD, BASETYPE),
    source_var = AVAL,
    new_var    = BASE
  ) |>
  derive_var_base(
    by_vars    = exprs(STUDYID, USUBJID, PARAMCD, BASETYPE),
    source_var = AVALC,
    new_var    = BASEC
  )
```

### Step 9 — Change from baseline (CHG, PCHG)

Derive after BASE is present. CHG and PCHG are `NA` for the baseline record itself
and for any post-baseline record where BASE is `NA`.

```r
advs <- advs |>
  derive_var_chg() |>    # CHG = AVAL - BASE
  derive_var_pchg()      # PCHG = CHG / BASE * 100; NA if BASE = 0 or NA
```

If CHG is not in scope per the ADaM spec (e.g. for categorical parameters),
omit these calls and add a note in the code.

### Step 10 — Analysis flags (ANL01FL)

`ANL01FL` flags the records used in primary analysis. The definition is
protocol- and study-specific. Derive with `restrict_derivation()`.

```r
# REVIEW: ANL01FL definition is protocol-specific. The condition below
#   (on-treatment, non-baseline) is a common starting point. Confirm against
#   the SAP before use.
advs <- advs |>
  restrict_derivation(
    derivation = derive_var_extreme_flag,
    args = params(
      by_vars  = exprs(STUDYID, USUBJID, PARAMCD),
      order    = exprs(ADT, AVISITN),
      new_var  = ANL01FL,
      mode     = "last"
    ),
    filter = ADT >= TRTSDT & !is.na(AVAL) & is.na(DTYPE)
  )
```

### Step 11 — Dataset-specific: ADVS

Additional derivations specific to vital signs:

**VSTEST mapping for PARAM units:** Include units in PARAM text per spec (e.g.
`"Systolic Blood Pressure (mmHg)"`). Confirm unit conventions from VSSTRESU.

**Position variable (VSPOS):** If VSPOS is in scope, carry through from VS and
include in uniqueness assertions — ADVS uniqueness is typically per
USUBJID + PARAMCD + AVISIT + VSPOS.

```r
# Uniqueness assertion — adjust key variables per spec
stopifnot(
  advs |>
    filter(is.na(DTYPE)) |>
    count(STUDYID, USUBJID, PARAMCD, AVISITN, VSPOS) |>
    filter(n > 1) |>
    nrow() == 0
)
```

**Duplicate records:** If multiple VS records exist for the same
subject-parameter-visit (e.g. triplicate BP measurements), decide with the
statistician whether to: (a) average them and add `DTYPE = "AVERAGE"`, (b) flag
only one using `ANL01FL`, or (c) retain all. Add a `# REVIEW:` comment with
the chosen approach.

### Step 12 — Dataset-specific: ADLB

Additional derivations specific to laboratory values:

**Normal ranges:** Carry LBSTNRLO and LBSTNRHI from LB as ANRLO and ANRHI.

```r
adlb <- adlb |>
  derive_vars_merged(
    dataset_add = lb |> select(-DOMAIN),
    by_vars     = exprs(STUDYID, USUBJID, LBTESTCD, VISIT),
    new_vars    = exprs(ANRLO = LBSTNRLO, ANRHI = LBSTNRHI)
  )
```

**Reference range indicator (ANRIND):** Map to controlled terminology values
(`"LOW"`, `"NORMAL"`, `"HIGH"`, `"LOW LOW"`, `"HIGH HIGH"`).

```r
# REVIEW: ANRIND derivation rules may be protocol-specific if the study
#   uses non-standard normal range definitions.
adlb <- adlb |>
  mutate(
    ANRIND = case_when(
      AVAL < ANRLO  ~ "LOW",
      AVAL > ANRHI  ~ "HIGH",
      !is.na(AVAL)  ~ "NORMAL"
    )
  )
```

**Baseline reference range indicator (BNRIND):** Carry ANRIND where ABLFL == "Y".

```r
adlb <- adlb |>
  derive_var_base(
    by_vars    = exprs(STUDYID, USUBJID, PARAMCD, BASETYPE),
    source_var = ANRIND,
    new_var    = BNRIND
  )
```

**Toxicity grades:** If CTCAE grading is in scope, derive ATOXGR from LB.LBTOXGR
using `derive_vars_merged()` and carry BTOXGR from baseline.

### Step 13 — Dataset attributes and final checks

```r
# Key uniqueness check — adjust by_vars per dataset and spec
key_vars <- c("STUDYID", "USUBJID", "PARAMCD", "AVISITN")
dup_check <- advs |>
  filter(is.na(DTYPE)) |>
  count(across(all_of(key_vars))) |>
  filter(n > 1)
if (nrow(dup_check) > 0) {
  stop("Duplicate records found: ", paste(key_vars, collapse = ", "))
}

# Check required BDS variables are present
required_vars <- c(
  "STUDYID", "USUBJID", "PARAM", "PARAMCD", "PARAMN",
  "ADT", "ADY", "AVISIT", "AVISITN",
  "AVAL", "BASE", "CHG", "ABLFL", "ANL01FL"
)
missing_vars <- setdiff(required_vars, names(advs))
if (length(missing_vars) > 0) {
  stop("Missing required BDS variables: ", paste(missing_vars, collapse = ", "))
}

# Apply variable labels and export via xportr — see adsl-conventions.md for pattern
```

---

## Common BDS errors to avoid

- Using `filter()` + `mutate()` to flag baselines instead of
  `restrict_derivation()` + `derive_var_extreme_flag()` — the admiral functions
  are required for reproducibility and traceability
- Not adding `BASETYPE` before `restrict_derivation()` when multiple baseline
  definitions exist — results in incorrect BASE values for subjects with more
  than one baseline window
- Deriving CHG before BASE is populated — `derive_var_chg()` depends on BASE
  being present; sequence matters
- Passing VISIT directly to AVISIT — AVISIT is an ADaM-defined grouping, not an
  SDTM passthrough; always map via spec-driven visit table
- Not scoping CHG/PCHG to on-treatment records before summary — ANL01FL or an
  equivalent filter must be applied in analysis programs
- Asserting uniqueness without accounting for DTYPE rows — exclude
  `DTYPE != NA` records from uniqueness checks (synthetic rows are intentional
  duplicates by USUBJID + PARAMCD + AVISITN)
- Using `derive_vars_merged()` instead of `derive_vars_merged_lookup()` for
  PARAMCD/PARAM/PARAMN assignment — `derive_vars_merged()` is primarily used for ADSL
  backbone merges; parameter code mappings must use `derive_vars_merged_lookup()`
  so that unmatched records are retained and filterable via `filter(!is.na(PARAMCD))`
- Using `"N"` for ABLFL or ANL01FL — flag convention is `"Y"` or `NA` only
- Deriving ANRIND from AVAL without a `# REVIEW:` comment — normal range logic
  is almost always protocol-specific

---

## Output checklist

Before returning code, verify:

- [ ] ADSL variables (TRTSDT, population flags) merged before baseline derivation
- [ ] DOMAIN removed from source domain before `derive_vars_merged()` calls
- [ ] PARAMCD/PARAM/PARAMN assigned with `derive_vars_merged_lookup()` — not `derive_vars_merged()`, not `case_when()`
- [ ] ADT derived with `derive_vars_dt()`, not `as.Date()` on VSDTC/LBDTC
- [ ] ADY derived with `derive_vars_dy()`
- [ ] AVISIT assigned from spec-driven visit map
- [ ] ABLFL flagged with `restrict_derivation()` + `derive_var_extreme_flag()`
- [ ] BASE derived with `derive_var_base()`
- [ ] CHG/PCHG derived with `derive_var_chg()` / `derive_var_pchg()`
- [ ] ANL01FL annotated with `# REVIEW:` referencing SAP definition
- [ ] Uniqueness assertion excludes DTYPE rows
- [ ] All `# REVIEW:` comments placed at protocol-specific decision points
- [ ] `flag_imputation = "auto"` used for date derivations
- [ ] ABLFL and ANL01FL are `"Y"` or `NA`, never `"N"`
- [ ] Dataset and variable labels applied before export
