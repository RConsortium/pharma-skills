---
name: admiral-adae
description: >
  Derives an ADaM Adverse Events Analysis Dataset (ADAE) using the {admiral}
  R package and pharmaverse ecosystem. Use when a user needs to create ADAE
  from SDTM AE and supporting domains, derive standard adverse event analysis
  variables (severity, seriousness, treatment-emergent flags, study day
  variables, baseline flags), or generate QC-ready R code following CDISC
  ADaM conventions. Requires SDTM input data, ADSL, and an ADaM spec.
license: MIT
metadata:
  author: Navitas Data Sciences
  version: "0.1"
  pharmaverse: "true"
compatibility: >
  Requires R with admiral, dplyr, lubridate, and pharmaversesdtm installed.
  Designed for use in a GxP-compliant environment with access to SDTM datasets,
  a completed ADSL dataset, and an ADaM ADAE specification.
---

# admiral-adae

Derives a CDISC-conformant ADAE dataset using {admiral}. Outputs executable,
QC-ready R code with derivation logic traceable to the ADaM specification.

The primary design challenge in ADAE is the treatment-emergent adverse event
(TEAE) flag (TRTEMFL) and its supporting date infrastructure. All date and study
day derivations must flow from this before any analysis variables are added.

---

## Inputs

Before generating code, confirm the following are available or explicitly noted
as absent:

| Input | Required | Notes |
|---|---|---|
| AE | Yes | One record per AE per subject; subject spine for ADAE |
| ADSL | Yes | Provides TRTSDT, TRTEDT, TRT01P/A, population flags |
| MH | No | Medical history; needed for pre-existing condition flag (PREFL) |
| CM | No | Concomitant medications; sometimes linked to AE causality |
| ADaM ADAE spec | Yes | Variable list, derivation rules, TEAE definition, grading rules |
| Study context | Yes | TEAE window definition, SMQ/grouping flag scope, severity scale |

If AE or ADSL are absent, stop and request them. If optional domains are
absent, omit the corresponding derivations and note this in code comments.

**Note on pharmaversesdtm test data:** The `pharmaversesdtm::ae` dataset does
not contain `AETOXGR`. Users running this skill against pharmaverse test data
should skip the AETOXGR derivation in Step 7. The derivation is retained in
the skill for use with real study data where NCI CTCAE grading was collected.

**Critical ADSL dependency:** ADAE must merge a defined set of ADSL variables
onto every AE record. Confirm with the statistician which ADSL variables are
required — at minimum: TRTSDT, TRTEDT, TRTSDTM, TRT01P, TRT01PN, TRT01A,
TRT01AN, and all population flags in scope (SAFFL, ITTFL).

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
ae   <- pharmaversesdtm::ae
adsl <- adsl  # assumed derived upstream; replace with path/load as needed
# mh <- pharmaversesdtm::mh  # uncomment if pre-existing condition flag in scope

# Remove DOMAIN from AE to avoid variable conflicts in merges
ae <- ae |> select(-DOMAIN)

# Confirm AE has at least one record
stopifnot(nrow(ae) > 0)
```

### Step 2 — Subject spine from AE

ADAE is a one-record-per-AE dataset; the subject spine is AE itself. Start
here and add ADSL variables in the next step.

```r
adae <- ae
```

### Step 3 — Merge ADSL variables

Merge a controlled subset of ADSL variables onto every AE record. Do not merge
all of ADSL — select only variables referenced in the ADAE derivation logic
and required for the output dataset per the ADaM spec.

```r
# REVIEW: Confirm which ADSL variables are required per the ADAE spec.
#   The list below covers the minimum set for TEAE flag derivation and treatment
#   labelling. Extend with population flags and other ADSL variables as needed.
adsl_vars <- exprs(
  STUDYID, USUBJID,
  TRTSDT, TRTEDT, TRTSDTM,
  TRT01P, TRT01PN, TRT01A, TRT01AN,
  SAFFL, ITTFL
)

adae <- adae |>
  derive_vars_merged(
    dataset_add = adsl |> select(!!!adsl_vars),
    by_vars     = exprs(STUDYID, USUBJID)
  )
```

### Step 4 — AE date variables (ASTDT, ASTDTF, AENDT, AENDTF)

Derive analysis start and end dates from AE.AESTDTC and AE.AEENDTC. Always
use `derive_vars_dt()` — never `as.Date()` directly on DTC variables.

Use `date_imputation = "first"` for start dates and `"last"` for end dates per
CDISC convention. Always retain imputation flag variables (ASTDTF, AENDTF).

```r
adae <- adae |>
  derive_vars_dt(
    dtc             = AESTDTC,
    new_vars_prefix = "AST",
    date_imputation = "first",
    flag_imputation = "auto"
  ) |>
  derive_vars_dt(
    dtc             = AEENDTC,
    new_vars_prefix = "AEN",
    date_imputation = "last",
    flag_imputation = "auto"
  )
```

### Step 5 — Study day variables (ASTDY, AENDY)

Use `derive_vars_dy()` relative to TRTSDT from ADSL. Do not compute study days
manually with date subtraction — this bypasses the Day 1 = first dose date
offset logic required by ADaM.

```r
adae <- adae |>
  derive_vars_dy(
    reference_date = TRTSDT,
    source_vars    = exprs(ASTDT, AENDT)
  )
```

### Step 6 — Treatment-emergent flag (TRTEMFL)

This is the central derivation in ADAE. TRTEMFL = "Y" when:
- AE onset date (ASTDT) >= first dose date (TRTSDT), **and**
- AE onset date (ASTDT) <= last dose date (TRTEDT) + study-specific window

The `derive_var_trtemfl()` function handles this logic. The `end_window`
parameter defines how many days post-last-dose an AE is still considered
treatment-emergent — this is study- and protocol-specific.

```r
# REVIEW: end_window is protocol-specific. Common values are 30 days post-last
#   dose for SAEs and 7 days for non-serious AEs, but always confirm from the
#   SAP. If the protocol does not specify a post-treatment window, set end_window
#   to 0 to include only AEs on or before the last dose date.
#   The ignore_time_for_trt_end argument should be TRUE if TRTEDTM is not
#   reliable for all subjects — confirm with the data manager.
adae <- adae |>
  derive_var_trtemfl(
    new_var                    = TRTEMFL,
    start_date                 = ASTDT,
    end_date                   = AENDT,
    trt_start_date             = TRTSDT,
    trt_end_date               = TRTEDT,
    end_window                 = 30,        # PLACEHOLDER — confirm from SAP
    ignore_time_for_trt_end    = TRUE
  )
```

### Step 7 — Severity and grade variables (AESEV, AETOXGR)

Map AESEV from AE.AESEV (already decoded in SDTM) and AETOXGR from AE.AETOXGR
if NCI CTCAE grading is used. If only AESEV is in scope, skip AETOXGR.

```r
adae <- adae |>
  mutate(
    # AESEV: severity — use decoded AESEV directly from AE; no transformation required
    AESEV = AESEV,
    # AESEVN: optional numeric mapping for sorting
    # REVIEW: Confirm severity ordering and numeric mapping against the ADaM spec.
    AESEVN = case_when(
      AESEV == "MILD"     ~ 1L,
      AESEV == "MODERATE" ~ 2L,
      AESEV == "SEVERE"   ~ 3L
    )
  )

# AETOXGR: CTCAE numeric grade — carry through from AE if grading was collected
# Uncomment if in scope per ADaM spec:
# adae <- adae |>
#   mutate(AETOXGR = AETOXGR)
```

### Step 8 — Seriousness and outcome variables (AESER, AEOUT, AESDTH)

These variables typically carry through from AE SDTM with controlled
terminology alignment. If the ADaM spec requires recoding, apply `case_when()`
with explicit `# REVIEW:` annotations.

```r
adae <- adae |>
  mutate(
    # AESER: serious AE flag — "Y" or NA only; never "N" per CDISC convention
    AESER = if_else(AESER == "Y", "Y", NA_character_),
    # AESDTH: AE resulted in death — "Y" or NA
    AESDTH = if_else(AESDTH == "Y", "Y", NA_character_),
    # AEOUT: outcome — verify CDISC CT values in spec
    # REVIEW: Confirm AEOUT coded values align with the CDISC AE outcome codelist
    #   (RECOVER, NOT RECOVERED/NOT RESOLVED, RECOVERING/RESOLVING, etc.)
    AEOUT = AEOUT
  )
```

### Step 9 — Causality and action taken (AEREL, AEACN)

Carry through from AE, applying `if_else()` for flag recoding to `"Y"`/NA
convention where applicable.

```r
adae <- adae |>
  mutate(
    # AEREL: relationship to study treatment — usually "RELATED" / "NOT RELATED"
    # REVIEW: Some studies use "POSSIBLE", "PROBABLE" — confirm CT per spec.
    AEREL = AEREL,
    # AERELN: numeric causality code for sorting/analysis if required by spec
    AERELN = case_when(
      AEREL == "NOT RELATED" ~ 1L,
      AEREL == "RELATED"     ~ 2L
    ),
    # AERELNST: causality to non-study treatment if applicable
    # Uncomment if in scope: AERELNST = AERELNST
    #
    # AEACN: action taken with study treatment
    AEACN = AEACN
  )
```

### Step 10 — Pre-existing condition flag (PREFL)

PREFL = "Y" when the AE term (AEDECOD) is present in MH prior to treatment
start. Requires MH domain. If MH is absent, comment out this section.

```r
# PREFL: pre-existing condition flag from MH
# REVIEW: The matching logic below uses AEDECOD = MHDECOD. Confirm the
#   match strategy with the medical reviewer — some specs require AEBODSYS
#   matching or a more specific term hierarchy.
# Requires: mh <- pharmaversesdtm::mh |> select(-DOMAIN)
#
# mh_terms <- mh |>
#   filter(MHSTAT != "HISTORY OF") |>   # REVIEW: filter condition is study-specific
#   distinct(STUDYID, USUBJID, MHDECOD)
#
# adae <- adae |>
#   derive_var_merged_exist_flag(
#     dataset_add   = mh_terms,
#     by_vars       = exprs(STUDYID, USUBJID, AEDECOD = MHDECOD),
#     new_var       = PREFL,
#     condition     = TRUE,
#     true_value    = "Y",
#     false_value   = NA_character_,
#     missing_value = NA_character_
#   )
```

### Step 11 — Maximum severity flag (AESEQ, grouping flags)

If the spec requires a worst-case severity flag per subject (AMAXSEVFL) or
cumulative AE counts, derive using `derive_var_extreme_flag()`.

```r
# AMAXSEVFL: flag for the most severe AE per subject within TRTEMFL == "Y"
# REVIEW: Confirm whether worst-severity flag applies to TEAE only or all AEs.
adae <- adae |>
  restrict_derivation(
    derivation = derive_var_extreme_flag,
    args = params(
      by_vars   = exprs(STUDYID, USUBJID),
      order     = exprs(desc(AESEVN), ASTDT, AESEQ),
      new_var   = AMAXSEVFL,
      mode      = "first"
    ),
    filter = TRTEMFL == "Y"
  )
```

### Step 12 — SMQ and grouping flags (optional)

If the spec includes standardised MedDRA queries (SMQs) or custom AE grouping
flags, derive using `derive_vars_query()` with a query dataset constructed from
the specification.

```r
# SMQ / grouping flags via derive_vars_query()
# REVIEW: SMQ membership lists are sponsor-defined; confirm the query dataset
#   structure and variable names against the ADaM ADAE spec and MedDRA version.
# Requires: queries_smq — a data frame in admiral query format
#   (see admiral::queries_mednav for structure reference)
#
# adae <- adae |>
#   derive_vars_query(
#     dataset_queries = queries_smq
#   )
```

### Step 13 — Sequence number (AESEQ)

Assign a within-subject sequence number. AE.AESEQ from SDTM is typically
carried through to ADaM — do not re-derive unless the spec explicitly requires
a different ordering.

```r
# REVIEW: If AESEQ from AE SDTM is the correct sequence variable per spec,
#   carry it through directly. If the spec requires a re-derived sequence,
#   use derive_var_obs_number() instead.
# adae <- adae |>
#   derive_var_obs_number(
#     new_var  = AESEQ,
#     by_vars  = exprs(STUDYID, USUBJID),
#     order    = exprs(ASTDT, AETERM),
#     check_type = "warning"
#   )
```

### Step 14 — Dataset attributes and final checks

```r
# Required variable check
required_vars <- c(
  "STUDYID", "USUBJID",
  "AETERM", "AEDECOD", "AEBODSYS",
  "ASTDT", "ASTDTF", "AENDT", "AENDTF",
  "ASTDY", "AENDY",
  "AESEV", "AESER",
  "TRTEMFL",
  "TRT01P", "TRT01A"
)
missing_vars <- setdiff(required_vars, names(adae))
if (length(missing_vars) > 0) {
  stop("Missing required ADAE variables: ", paste(missing_vars, collapse = ", "))
}

# Record count sanity check — ADAE should have at least as many records as AE
stopifnot(nrow(adae) >= nrow(ae))

# Apply variable labels — use xportr for submission context
# adae <- adae |>
#   xportr_label(metacore_obj, domain = "ADAE") |>
#   xportr_type(metacore_obj, domain = "ADAE") |>
#   xportr_length(metacore_obj, domain = "ADAE") |>
#   xportr_order(metacore_obj, domain = "ADAE")
# xportr_write(adae, "adae.xpt", label = "Adverse Events Analysis Dataset")
```

---

## Code quality requirements

Generated code must meet these standards for QC-readiness:

- **Comments:** Each derivation block must have a comment referencing the source
  variable (e.g. `# ASTDT: AE onset analysis date from AE.AESTDTC`)
- **Human review flags:** Use `# REVIEW:` comments where protocol-specific
  decisions are required (TEAE window, causality coding, SMQ membership,
  PREFL matching logic, severity ordering)
- **No silent failures:** Use `stopifnot()` for critical assertions (AE not
  empty, required variables present, row count preserved after merge)
- **Pipe style:** Use the native pipe `|>` and `exprs()` for admiral verb arguments
- **No manual date arithmetic:** Always use admiral date derivation functions

---

## Common errors to avoid

- Merging all ADSL variables onto ADAE — select only the variables needed; full
  ADSL merge inflates the dataset and introduces variable naming conflicts
- Using `as.Date()` on `AESTDTC` or `AEENDTC` — always use `derive_vars_dt()`
  to handle partial dates with proper imputation
- Setting `flag_imputation = "auto"` without including ASTDTF and AENDTF in the
  output — imputation flags must appear in the dataset per ADaM specification
- Hardcoding `end_window` in `derive_var_trtemfl()` without a `# REVIEW:`
  annotation — this is always protocol-specific and must come from the SAP
- Using `AESER == "N"` comparisons — SDTM AE.AESER is `"Y"` or `""` (blank),
  not `"Y"` or `"N"`; align to ADaM convention of `"Y"` or `NA` in output
- Computing study days manually (e.g. `ASTDT - TRTSDT + 1`) — use
  `derive_vars_dy()` to ensure correct ADaM study day offset logic
- Passing AE.AESEV directly as a numeric severity without a lookup — AESEV is
  character; derive AESEVN separately with an explicit `case_when()` lookup
- Using `"N"` for any flag variable (TRTEMFL, AESER, AESDTH, PREFL) — CDISC
  convention is `"Y"` or `NA`, never `"N"`
- Deriving TRTEMFL without confirming `end_window` against the SAP — an
  incorrect window silently miscategorises AEs with major safety implications
- Not removing DOMAIN from AE before `derive_vars_merged()` calls — causes
  variable conflict errors

---

## Output checklist

Before returning code, verify:

- [ ] AE row count confirmed non-zero with `stopifnot()` at load
- [ ] DOMAIN removed from AE before processing
- [ ] ADSL variables merged selectively — not `select(everything())`
- [ ] ASTDT and AENDT derived via `derive_vars_dt()` with imputation arguments explicit
- [ ] ASTDTF and AENDTF present in output
- [ ] ASTDY and AENDY derived via `derive_vars_dy()` not manual arithmetic
- [ ] TRTEMFL derived via `derive_var_trtemfl()` with `end_window` annotated with `# REVIEW:`
- [ ] AESER and AESDTH recoded to `"Y"` / `NA` convention
- [ ] All `# REVIEW:` comments placed at protocol-specific decision points
- [ ] Required variables presence check with `stop()` on failure
- [ ] xportr block present (commented) for submission context
