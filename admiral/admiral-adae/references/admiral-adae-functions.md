# admiral Function Reference for ADAE

This reference covers the admiral functions most relevant to ADAE derivation.
It is structured around **decision guidance** — which function to use in a given
situation and why — not as a comprehensive API reference. For full signatures
and examples see the [admiral documentation](https://pharmaverse.github.io/admiral/).

---

## The Core Decision Framework

ADAE derivation has three phases with distinct function families:

| Phase | Task | Functions |
|---|---|---|
| **Setup** | Merge ADSL variables onto AE records | `derive_vars_merged()` |
| **Date infrastructure** | Convert DTC to analysis dates; compute study days | `derive_vars_dt()`, `derive_vars_dtm()`, `derive_vars_dy()` |
| **Analysis variables** | TEAE flag, severity, existence flags, grouping | `derive_var_trtemfl()`, `derive_var_extreme_flag()`, `derive_var_merged_exist_flag()`, `derive_vars_query()` |

The TEAE flag (TRTEMFL) must be derived **after** date infrastructure is
complete and **before** any flag that filters on TRTEMFL (e.g. AMAXSEVFL).

---

## Function Selection Guide

### `derive_vars_merged()` — ADSL merge and value carry-across

Use when:
- Merging ADSL variables onto every AE record (one ADSL row per subject, many AE rows)
- Bringing across a specific value from a source domain where the selection
  depends only on the source dataset

```r
# Merge selected ADSL variables onto AE records
adae <- adae |>
  derive_vars_merged(
    dataset_add = adsl |> select(!!!adsl_vars),
    by_vars     = exprs(STUDYID, USUBJID)
  )
```

**Key difference from ADSL usage:** In ADAE the merge is one-to-many (one ADSL
record expands across many AE rows), so no `order` or `mode` arguments are
needed. The join is a simple left merge on STUDYID and USUBJID.

**Do NOT use `derive_vars_merged()` when:**
- The selection filter involves variables from both AE and the additional
  dataset simultaneously — use `derive_vars_joined()` instead.

---

### `derive_vars_joined()` — when filter references both datasets

Use when:
- The record selection condition involves variables from **both** ADAE and the
  additional dataset at the same time (`filter_join` argument)
- Typical ADAE example: assigning period variables where AE onset date must fall
  within an ADSL period window

```r
# Assign period variable (AP01SDT / AP01EDT from ADSL) to each AE
adae <- adae |>
  derive_vars_joined(
    dataset_add = adsl |> select(STUDYID, USUBJID, AP01SDT, AP01EDT),
    by_vars     = exprs(STUDYID, USUBJID),
    filter_join = ASTDT >= AP01SDT & ASTDT <= AP01EDT,
    new_vars    = exprs(APERIOD = 1L)   # example period indicator
  )
```

---

### `derive_vars_dt()` — analysis date from `--DTC`

Use when:
- Converting AESTDTC or AEENDTC to analysis Date variables (ASTDT, AENDT)
- Handling partial dates with imputation and retaining imputation flags

```r
adae <- adae |>
  derive_vars_dt(
    dtc             = AESTDTC,
    new_vars_prefix = "AST",      # creates ASTDT and ASTDTF
    date_imputation = "first",    # start dates: impute to earliest
    flag_imputation = "auto"
  ) |>
  derive_vars_dt(
    dtc             = AEENDTC,
    new_vars_prefix = "AEN",      # creates AENDT and AENDTF
    date_imputation = "last",     # end dates: impute to latest
    flag_imputation = "auto"
  )
```

**Never** use `as.Date()` directly on DTC variables. It silently returns `NA`
for partial dates (e.g. `"2023-06"`) without any warning.

**Always** retain the imputation flag variables (ASTDTF, AENDTF) in the output
dataset — they are required by ADaM specification.

---

### `derive_vars_dtm()` — analysis datetime from `--DTC`

Use when:
- The AE record contains time information and the TEAE flag uses datetime
  precision (TRTSDTM, TRTEDTM from ADSL)

```r
adae <- adae |>
  derive_vars_dtm(
    dtc              = AESTDTC,
    new_vars_prefix  = "AST",
    date_imputation  = "first",
    time_imputation  = "first",   # "00:00:00"
    flag_imputation  = "auto"
  )
```

For most ADAE derivations, date-level precision (ASTDT) is sufficient for
TRTEMFL. Use datetime only when the protocol and SAP explicitly require it.

---

### `derive_vars_dy()` — study day calculation

Use when:
- Computing ASTDY and AENDY (study day of AE onset and resolution) relative
  to TRTSDT
- **Always use this function** — never compute manually with date subtraction

```r
adae <- adae |>
  derive_vars_dy(
    reference_date = TRTSDT,
    source_vars    = exprs(ASTDT, AENDT)
    # creates ASTDY and AENDY automatically
  )
```

CDISC study day convention: day 1 is the reference date; there is no day 0.
Manual subtraction (`ASTDT - TRTSDT`) produces off-by-one errors for all pre-
treatment events.

---

### `derive_var_trtemfl()` — treatment-emergent adverse event flag

Use when:
- Deriving TRTEMFL (treatment-emergent flag) — the central ADAE derivation

```r
# REVIEW: end_window is protocol-specific. Confirm from the SAP before use.
adae <- adae |>
  derive_var_trtemfl(
    new_var                 = TRTEMFL,
    start_date              = ASTDT,
    end_date                = AENDT,
    trt_start_date          = TRTSDT,
    trt_end_date            = TRTEDT,
    end_window              = 30,       # PLACEHOLDER — confirm from SAP
    ignore_time_for_trt_end = TRUE
  )
```

**Arguments to review for every study:**

| Argument | What to confirm |
|---|---|
| `end_window` | Days post-last-dose still considered treatment-emergent; 0, 7, 28, or 30 are common; always from SAP |
| `ignore_time_for_trt_end` | Set TRUE if TRTEDTM is missing or unreliable; confirm with data manager |
| `start_date` / `end_date` | Usually ASTDT / AENDT; confirm if datetime precision is needed |

**Do NOT derive TRTEMFL manually** with date comparisons. The function handles
the Day 1 = first dose, end_window, and missing date edge cases correctly.

---

### `derive_var_merged_exist_flag()` — existence flag from single source

Use when:
- Setting PREFL = "Y" if a subject has at least one MH record matching the
  AE term

```r
# PREFL: pre-existing condition flag
# REVIEW: Confirm match strategy (AEDECOD = MHDECOD vs AEBODSYS = MHBODSYS)
adae <- adae |>
  derive_var_merged_exist_flag(
    dataset_add   = mh_terms,   # pre-filtered MH
    by_vars       = exprs(STUDYID, USUBJID, AEDECOD = MHDECOD),
    new_var       = PREFL,
    condition     = TRUE,
    true_value    = "Y",
    false_value   = NA_character_,
    missing_value = NA_character_
  )
```

---

### `derive_var_extreme_flag()` via `restrict_derivation()` — worst-case flag

Use when:
- Flagging the most severe TEAE per subject (AMAXSEVFL)
- The flag applies only to a subset of records (TRTEMFL = "Y")

```r
# AMAXSEVFL: most severe treatment-emergent AE per subject
# REVIEW: Confirm whether worst-severity flag applies to TEAE only or all AEs.
adae <- adae |>
  restrict_derivation(
    derivation = derive_var_extreme_flag,
    args = params(
      by_vars    = exprs(STUDYID, USUBJID),
      order      = exprs(desc(AESEVN), ASTDT, AESEQ),
      new_var    = AMAXSEVFL,
      mode       = "first"
    ),
    filter = TRTEMFL == "Y"
  )
```

`restrict_derivation()` applies a derivation to a filtered subset of records,
leaving other records unchanged. Use this pattern whenever a flag should be
computed over only a portion of the dataset.

---

### `derive_vars_query()` — SMQ and grouping flags

Use when:
- Deriving sponsor-defined or MedDRA SMQ grouping flags from a query dataset
- Query dataset is structured per the admiral query format

```r
# REVIEW: SMQ membership lists must be confirmed against the ADaM ADAE spec
#   and the correct MedDRA version. Obtain query_smq from the medical reviewer.
adae <- adae |>
  derive_vars_query(
    dataset_queries = queries_smq   # data frame in admiral query format
  )
```

For query dataset structure, see `admiral::queries_mednav` as a reference.
SMQ scope (narrow/broad) is always study-specific and requires `# REVIEW:`.

---

### `derive_var_obs_number()` — sequence number

Use when:
- The spec requires a re-derived within-subject sequence number (AESEQ)
- Do not use if AE.AESEQ from SDTM can be carried through directly

```r
adae <- adae |>
  derive_var_obs_number(
    new_var    = AESEQ,
    by_vars    = exprs(STUDYID, USUBJID),
    order      = exprs(ASTDT, AETERM),
    check_type = "warning"
  )
```

---

## Common Pitfalls

### 1. Merging all of ADSL onto ADAE

```r
# WRONG — merges 100+ ADSL variables, creates variable conflicts
adae <- adae |> left_join(adsl, by = c("STUDYID", "USUBJID"))

# CORRECT — select only variables needed per the ADAE spec
adsl_vars <- exprs(STUDYID, USUBJID, TRTSDT, TRTEDT, TRT01P, TRT01PN, SAFFL)
adae <- adae |>
  derive_vars_merged(
    dataset_add = adsl |> select(!!!adsl_vars),
    by_vars     = exprs(STUDYID, USUBJID)
  )
```

### 2. Using `as.Date()` on DTC variables

```r
# WRONG — returns NA for partial dates without warning
adae <- adae |> mutate(ASTDT = as.Date(AESTDTC))

# CORRECT
adae <- adae |>
  derive_vars_dt(
    dtc = AESTDTC, new_vars_prefix = "AST",
    date_imputation = "first", flag_imputation = "auto"
  )
```

### 3. Dropping imputation flags

```r
# WRONG — imputation flags are ADaM-required; omitting them creates findings
adae <- adae |> select(-ASTDTF, -AENDTF)

# CORRECT — retain all imputation flag variables in the output
```

### 4. Hardcoding `end_window` without `# REVIEW:`

```r
# WRONG — silently applies an arbitrary window
adae |> derive_var_trtemfl(..., end_window = 30)

# CORRECT — always annotate
# REVIEW: end_window = 30 days is a placeholder. Confirm from SAP before use.
adae |> derive_var_trtemfl(..., end_window = 30)
```

### 5. Using `"N"` for TRTEMFL, AESER, AESDTH, PREFL

```r
# WRONG — violates CDISC ADaM flag convention
mutate(TRTEMFL = if_else(is_emergent, "Y", "N"))

# CORRECT — "Y" or NA only
mutate(TRTEMFL = if_else(is_emergent, "Y", NA_character_))
```

### 6. Not removing DOMAIN from AE before merges

```r
# WRONG — DOMAIN variable conflict causes derive_vars_merged() to error
adae |> derive_vars_merged(dataset_add = ae, ...)

# CORRECT
ae <- ae |> select(-DOMAIN)
```

### 7. Computing study days manually

```r
# WRONG — off-by-one for pre-treatment events; ignores CDISC day 1 convention
mutate(ASTDY = as.numeric(ASTDT - TRTSDT) + 1)

# CORRECT
derive_vars_dy(reference_date = TRTSDT, source_vars = exprs(ASTDT, AENDT))
```

### 8. Deriving AMAXSEVFL before AESEVN exists

`AMAXSEVFL` depends on `AESEVN` for ordering. Always derive AESEVN in the
severity step (Step 7) before running `restrict_derivation()` for AMAXSEVFL.

---

## Quick Reference Card

| Situation | Function |
|---|---|
| Merge ADSL variables onto AE rows | `derive_vars_merged()` |
| Filter on variables from both AE and ADSL | `derive_vars_joined()` |
| Convert `AESTDTC`/`AEENDTC` to Date | `derive_vars_dt()` |
| Convert `AESTDTC` to Datetime | `derive_vars_dtm()` |
| Study day (ASTDY, AENDY) | `derive_vars_dy()` |
| Treatment-emergent flag (TRTEMFL) | `derive_var_trtemfl()` |
| Pre-existing condition flag (PREFL) | `derive_var_merged_exist_flag()` |
| Worst-case severity flag (AMAXSEVFL) | `restrict_derivation()` + `derive_var_extreme_flag()` |
| SMQ / grouping flags | `derive_vars_query()` |
| Within-subject sequence number (re-derived) | `derive_var_obs_number()` |
