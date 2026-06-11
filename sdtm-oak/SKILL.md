---
name: sdtm-oak
description: >
  Derives CDISC SDTM domains from raw clinical (EDC/eCRF) data using the
  {sdtm.oak} R package. Use when a user needs to map raw study data to SDTM
  Events (AE, CM, MH), Findings (VS, LB, EG), or Interventions (EX) domains
  following the sdtm.oak algorithm framework. Produces executable, submission-
  ready R code with controlled terminology recoding, ISO 8601 date derivation,
  sequence numbering, and study day calculation.
license: MIT
metadata:
  author: pharma-skills contributors
  version: "0.1"
  pharmaverse: "true"
compatibility: >
  Requires R with sdtm.oak (>= 0.2.0), dplyr, and tibble installed.
  Requires raw EDC/eCRF data and a controlled terminology (CT) specification
  CSV. Designed for use in a GxP-compliant environment.
---

# sdtm-oak

Derives CDISC SDTM domains from raw clinical data using the {sdtm.oak}
algorithm framework. Outputs executable R code with full derivation traceability.

See [`references/oak-functions.md`](references/oak-functions.md) for the full
function reference.

---

## Inputs

Before generating code, confirm:

| Input | Required | Notes |
|---|---|---|
| Raw EDC dataset | Yes | e.g. `ae_raw`, `vs_raw` — raw CRF form data |
| CT specification | Yes | CSV in CDISC codelist format; load via `read_ct_spec()` |
| Domain specification | Yes | Variable list, CT codelists per variable, date formats |
| DM domain | For study day / BLFL | Provides RFSTDTC for `derive_study_day()` and `derive_blfl()` |

**Always inspect the raw dataset first** — raw column names vary by EDC system
and study. Print `names(raw_dat)` and `head(raw_dat)` before writing any
derivations.

---

## Core algorithms

sdtm.oak provides six mapping algorithms. Choose based on whether the target
variable has controlled terminology (CT) and whether the value is derived from
raw data or hardcoded.

| Algorithm | CT? | Source | Use for |
|---|---|---|---|
| `assign_no_ct()` | No | Raw column | Free-text variables: AETERM, CMTRT, VSORRES |
| `assign_ct()` | Yes | Raw column | CT-mapped from raw: AESEV, AESER, SEX, RACE |
| `hardcode_no_ct()` | No | Fixed value | Study-constant free-text: STUDYID, custom flags |
| `hardcode_ct()` | Yes | Fixed value | Domain constants validated against CT: DOMAIN |
| `assign_datetime()` | — | Raw date col(s) | Any `--DTC` variable: AESTDTC, VSDTC, EXSTDTC |
| `condition_add()` | — | Condition expr | Gate any of the above to a row subset |

All six functions share the same `id_vars` join key (default: `oak_id_vars()`)
and the same `tgt_dat` pipe pattern — pass the growing SDTM dataset as
`tgt_dat` to accumulate variables.

---

## Workflow

Follow these steps in order. Write code section by section, not as a single block.

### Step 1 — Setup and data inspection

```r
library(sdtm.oak)
library(dplyr)

# Load raw data — replace with actual source
ae_raw <- <load raw AE data>   # e.g. sdtm.oak::ae_raw for the package example

# ALWAYS inspect before writing derivations
cat("Columns:\n"); print(names(ae_raw))
cat("Rows:", nrow(ae_raw), "\n")
print(head(ae_raw, 3))
```

### Step 2 — Generate oak ID variables

`generate_oak_id_vars()` adds three key columns used as join keys throughout
all subsequent derivations. Call this once on the raw dataset.

```r
# REVIEW: Set pat_var to the column holding the subject/patient identifier
#   in this raw dataset. Set raw_src to a stable label for the CRF form.
ae_oak <- generate_oak_id_vars(
  raw_dat = ae_raw,
  pat_var = "patient_number",   # confirm column name from Step 1 inspection
  raw_src = "AE_FORM"           # stable label for this raw source
)
# Adds: oak_id (row key), raw_source (form label), patient_number (subj ID)
```

### Step 3 — Load controlled terminology

```r
# REVIEW: Replace path with the study CT spec CSV.
#   For the sdtm.oak package example data, use read_ct_spec_example().
ct_spec <- read_ct_spec_example()   # or: read_ct_spec("path/to/ct_spec.csv")

# Validate before use
assert_ct_spec(ct_spec)
```

### Step 4 — Hardcode domain constants

Fixed values that apply to every record in the domain. Use `hardcode_ct()` for
values validated against CT (DOMAIN); use `hardcode_no_ct()` for free-text constants.

```r
ae_domain <- ae_oak |>
  # DOMAIN is a CT-controlled variable — use hardcode_ct
  hardcode_ct(
    tgt_var  = "DOMAIN",
    tgt_val  = "AE",
    raw_dat  = ae_raw,
    raw_var  = "AETERM",   # presence filter: only rows with a non-NA AE term
    ct_spec  = ct_spec,
    ct_clst  = "DOMAIN"
  )
```

### Step 5 — Assign free-text variables (assign_no_ct)

Use for variables with no CT restriction — raw text carried directly.

```r
ae_domain <- ae_domain |>
  assign_no_ct(
    tgt_var = "AETERM",
    raw_dat = ae_raw,
    raw_var = "ae_term"   # REVIEW: confirm raw column name
  ) |>
  assign_no_ct(
    tgt_var = "AELOC",
    raw_dat = ae_raw,
    raw_var = "ae_location"
  )
```

### Step 6 — Assign CT-mapped variables (assign_ct)

Use for variables whose values must be recoded to CDISC controlled terminology.
Supply `ct_clst` matching the codelist name in your CT spec.

```r
# REVIEW: Confirm ct_clst names match the codelist_code column in ct_spec.
#   Wrong ct_clst silently returns the uppercased raw value — verify outputs.
ae_domain <- ae_domain |>
  assign_ct(
    tgt_var = "AESEV",
    raw_dat = ae_raw,
    raw_var = "severity",
    ct_spec = ct_spec,
    ct_clst = "AESEV"
  ) |>
  assign_ct(
    tgt_var  = "AESER",
    raw_dat  = ae_raw,
    raw_var  = "serious_ae",
    ct_spec  = ct_spec,
    ct_clst  = "NY"
  ) |>
  assign_ct(
    tgt_var  = "AEREL",
    raw_dat  = ae_raw,
    raw_var  = "causality",
    ct_spec  = ct_spec,
    ct_clst  = "AEREL"
  ) |>
  assign_ct(
    tgt_var  = "AEOUT",
    raw_dat  = ae_raw,
    raw_var  = "outcome",
    ct_spec  = ct_spec,
    ct_clst  = "AEOUT"
  )
```

### Step 7 — Assign datetime variables (assign_datetime)

Use for all `--DTC` variables. Never use `as.Date()`, `as.POSIXct()`, or
string manipulation for SDTM dates — always use `assign_datetime()`.

```r
# REVIEW: raw_fmt must exactly match the date format in the raw data.
#   Use "y-m-d" for ISO (2024-03-15), "d/m/y" for European (15/03/2024),
#   "m/d/y" for US (03/15/2024). Check format from Step 1 inspection.
#   Supply a list of alternatives if the format is inconsistent across records.
ae_domain <- ae_domain |>
  assign_datetime(
    tgt_var = "AESTDTC",
    raw_dat = ae_raw,
    raw_var = "onset_date",
    raw_fmt = "d-m-y"      # REVIEW: confirm raw date format
  ) |>
  assign_datetime(
    tgt_var = "AEENDTC",
    raw_dat = ae_raw,
    raw_var = "resolution_date",
    raw_fmt = "d-m-y"      # REVIEW: confirm raw date format
  )
```

For combined date-time (e.g. separate date and time columns):

```r
ae_domain <- ae_domain |>
  assign_datetime(
    tgt_var = "AESTDTC",
    raw_dat = ae_raw,
    raw_var = c("onset_date", "onset_time"),   # two columns
    raw_fmt = c("d-m-y", "H:M")               # one format per column
  )
```

### Step 8 — Conditional derivations (condition_add)

Use `condition_add()` to restrict a derivation to a subset of records. Wrap
the target dataset in `condition_add()`, then pass it as `tgt_dat`.

```r
# REVIEW: condition_add() criteria must reflect the study protocol.
#   Document the business rule the condition implements.
ae_domain <- ae_domain |>
  # Example: derive AEDTHFL only for fatal outcome records
  (\(dat) assign_ct(
    tgt_dat = condition_add(dat, AEOUT == "FATAL"),
    tgt_var = "AEDTHFL",
    raw_dat = ae_raw,
    raw_var = "death_flag",
    ct_spec = ct_spec,
    ct_clst = "NY"
  ))()
```

### Step 9 — Add STUDYID and USUBJID

Derive subject-level identifiers after domain variables are built.

```r
ae_domain <- ae_domain |>
  hardcode_no_ct(
    tgt_var = "STUDYID",
    tgt_val = "CDISCPILOT01",   # REVIEW: replace with actual study ID
    raw_dat = ae_raw,
    raw_var = "patient_number"
  ) |>
  assign_no_ct(
    tgt_var = "USUBJID",
    raw_dat = ae_raw,
    raw_var = "patient_number"   # REVIEW: confirm USUBJID construction rule
  )
```

### Step 10 — Study day derivation

Requires DM domain (provides RFSTDTC).

```r
# REVIEW: Confirm which DTC variable is the reference date for this domain
#   (RFSTDTC for most event domains; RFXSTDTC for findings relative to dosing).
ae_domain <- derive_study_day(
  sdtm_in      = ae_domain,
  dm_domain    = dm,
  tgdt         = "AESTDTC",
  refdt        = "RFSTDTC",
  study_day_var = "AESTDY"
) |>
  derive_study_day(
    sdtm_in      = _,
    dm_domain    = dm,
    tgdt         = "AEENDTC",
    refdt        = "RFSTDTC",
    study_day_var = "AEENDY"
  )
```

### Step 11 — Sequence number

```r
ae_domain <- derive_seq(
  sdtm_in = ae_domain,
  tgt_var = "AESEQ"
)
```

### Step 12 — Supplemental domain (SUPP--)

If the study collects non-standard variables, split them to SUPPAE.

```r
# REVIEW: Confirm which variables belong in SUPPAE vs the main domain.
#   Non-standard variables must not appear in the parent domain.
result <- generate_sdtm_supp(
  sdtm_dataset  = ae_domain,
  idvar         = "AESEQ",
  supp_qual_info = supp_spec,    # dataframe: QNAM, QLABEL, QORIG per variable
  qnam_var      = "QNAM",
  label_var     = "QLABEL",
  orig_var      = "QORIG"
)
ae_final   <- result$sdtm
suppae     <- result$supp
```

### Step 13 — Final checks

```r
# Required SDTM variables for AE domain
required_vars <- c("STUDYID", "DOMAIN", "USUBJID", "AESEQ",
                   "AETERM", "AESTDTC")
missing_vars <- setdiff(required_vars, names(ae_final))
if (length(missing_vars) > 0) {
  stop("Missing required AE variables: ", paste(missing_vars, collapse = ", "))
}

# No duplicate sequence numbers
stopifnot(
  ae_final |>
    count(STUDYID, USUBJID, AESEQ) |>
    filter(n > 1) |>
    nrow() == 0
)

cat("AE domain: ", nrow(ae_final), "records,",
    n_distinct(ae_final$USUBJID), "subjects\n")
```

---

## Findings domains (VS, LB, EG)

Findings domains (one record per subject per test per visit) follow a different
stacking pattern — derive each TESTCD separately, then `bind_rows()`.

```r
# REVIEW: Each parameter block must align with the CT codelist for VSTESTCD.
#   Stack only parameters in scope for this study per the CRF and SAP.

# Parameter 1: Systolic Blood Pressure
sysbp <- generate_oak_id_vars(vs_raw, pat_var = "patient_number",
                               raw_src = "VS_FORM") |>
  hardcode_ct(tgt_var = "VSTESTCD", tgt_val = "SYSBP",
              raw_dat  = vs_raw, raw_var = "SYSBP_result",
              ct_spec  = ct_spec, ct_clst = "VSTESTCD") |>
  hardcode_no_ct(tgt_var = "VSTEST", tgt_val = "Systolic Blood Pressure",
                 raw_dat = vs_raw, raw_var = "SYSBP_result") |>
  assign_no_ct(tgt_var = "VSORRES", raw_dat = vs_raw, raw_var = "SYSBP_result") |>
  assign_no_ct(tgt_var = "VSORRESU", raw_dat = vs_raw, raw_var = "SYSBP_unit") |>
  assign_datetime(tgt_var = "VSDTC", raw_dat = vs_raw,
                  raw_var = "visit_date", raw_fmt = "d-m-y")

# Parameter 2: Diastolic Blood Pressure — same pattern, different raw_var
diabp <- generate_oak_id_vars(vs_raw, pat_var = "patient_number",
                               raw_src = "VS_FORM") |>
  hardcode_ct(tgt_var = "VSTESTCD", tgt_val = "DIABP", ...) |>
  ...

# Stack all parameters
vs_domain <- bind_rows(sysbp, diabp, pulse, weight, height, temp) |>
  hardcode_ct(tgt_var = "DOMAIN", tgt_val = "VS",
              raw_dat = vs_raw, raw_var = "patient_number",
              ct_spec = ct_spec, ct_clst = "DOMAIN") |>
  derive_seq(tgt_var = "VSSEQ")
```

For findings, also derive **VSBLFL** (baseline flag) when applicable:

```r
# REVIEW: Confirm baseline visit name(s) from the protocol.
vs_domain <- derive_blfl(
  sdtm_in          = vs_domain,
  dm_domain        = dm,
  tgt_var          = "VSBLFL",
  ref_var          = "VSDTC",
  baseline_visits  = c("BASELINE", "DAY 1")   # REVIEW: protocol-specific
)
```

---

## `# REVIEW:` annotation rules

Place a `# REVIEW:` comment whenever a derivation contains a protocol-specific
decision that a QC reviewer must verify. Required locations:

| Location | What to annotate |
|---|---|
| `generate_oak_id_vars()` | `pat_var` column name and `raw_src` label |
| Every `assign_datetime()` | `raw_fmt` format string — must match actual raw data |
| Every `assign_ct()` | `ct_clst` codelist name — wrong codelist silently miscodes |
| Every `condition_add()` | The business rule the condition implements |
| `derive_blfl()` `baseline_visits` | Protocol baseline visit definition |
| `derive_study_day()` `refdt` | Reference date choice (RFSTDTC vs RFXSTDTC) |
| Any hardcoded `tgt_val` | Confirm value is correct for this study |

---

## Common errors to avoid

- Using `as.Date()`, `substr()`, or `format()` on raw date columns instead of
  `assign_datetime()` — ISO 8601 partial date handling and unknown-date
  placeholders (`"UN"`, `"UNK"`) are only correctly handled by `assign_datetime()`
- Skipping `generate_oak_id_vars()` — all `assign_*` and `hardcode_*` functions
  require `oak_id`, `raw_source`, and `patient_number` columns to be present as
  join keys; the dataset will silently return wrong results without them
- Passing the wrong `raw_dat` to an `assign_*` call — `raw_dat` must always be
  the **original raw dataset**, not the growing `tgt_dat`; mixing them causes
  incorrect joins
- Using `mutate()` or `rename()` for variable mapping instead of `assign_no_ct()`
  — `mutate` bypasses the oak traceability framework and does not respect `id_vars`
  join semantics
- Using `assign_no_ct()` for CT-mapped variables — values will not be recoded
  to CDISC terminology; use `assign_ct()` whenever a codelist applies
- Using `assign_ct()` with the wrong `ct_clst` — no error is raised; unmatched
  values are silently uppercased; always verify output distribution after derivation
- Skipping `assert_ct_spec()` before first use — malformed CT specs produce
  silent miscoding
- Not calling `derive_seq()` — `--SEQ` is required for all SDTM domains; do not
  derive it manually with `row_number()`
- Mixing up `hardcode_ct()` vs `hardcode_no_ct()` for DOMAIN — DOMAIN must use
  `hardcode_ct()` (validated against the DOMAIN codelist); using `hardcode_no_ct()`
  will accept any string
- For findings domains: building the full stacked dataset with `bind_rows()`
  **before** adding common variables (DOMAIN, USUBJID, study day) — add per-test
  variables in each parameter block, then add common variables after stacking

---

## Output checklist

Before returning code, verify:

- [ ] Raw dataset inspected (`names()` + `head()`) before first derivation
- [ ] `generate_oak_id_vars()` called first with correct `pat_var` and `raw_src`
- [ ] CT spec loaded and validated with `assert_ct_spec()`
- [ ] DOMAIN hardcoded with `hardcode_ct()` — not `hardcode_no_ct()`
- [ ] All `--DTC` variables derived with `assign_datetime()` — not `as.Date()`
- [ ] Every `assign_datetime()` has a `# REVIEW:` on `raw_fmt`
- [ ] Every `assign_ct()` has a `# REVIEW:` on `ct_clst`
- [ ] Every `condition_add()` has a `# REVIEW:` on the business rule
- [ ] `raw_dat` in each `assign_*` call is the **original raw dataset**
- [ ] `derive_seq()` called to generate `--SEQ`
- [ ] `derive_study_day()` called for event/finding date study days (requires DM)
- [ ] Required domain variables present (`stopifnot()` or `stop()` guard)
- [ ] No duplicate `--SEQ` values (`stopifnot()` check)
- [ ] Findings domains: per-test blocks stacked with `bind_rows()` before
      adding common variables
