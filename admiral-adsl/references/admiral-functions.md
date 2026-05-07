# admiral Function Reference for ADSL

This reference covers the admiral functions most relevant to ADSL derivation.
It is structured around **decision guidance** — which function to use in a given
situation and why — not as a comprehensive API reference. For full signatures
and examples see the [admiral documentation](https://pharmaverse.github.io/admiral/).

---

## The Core Decision Framework

admiral's generic derivation functions follow three properties:

| Property | What it means | Functions |
|---|---|---|
| **Selection** | Select records (e.g. first dose, baseline) | `derive_vars_merged()`, `derive_vars_joined()` |
| **Summary** | Summarise values (e.g. count, concatenate) | `derive_var_merged_summary()` |
| **Computation** | Compute from multiple values (e.g. BMI) | `derive_vars_computed()` |

For ADSL, **selection** is the dominant pattern. Almost every derivation involves
selecting a specific record from a source domain and merging variables across.

---

## Function Selection Guide

### `derive_vars_merged()` — the workhorse

Use when:
- Merging variables from another domain where the selection logic depends **only
  on the source dataset** (not on variables in both datasets simultaneously)
- Selecting first or last record per subject (with `order` + `mode`)
- Checking for the existence of a record (with `exist_flag`)
- Handling one-to-one or many-to-one relationships from source to ADSL

**Signature (key arguments):**
```r
derive_vars_merged(
  dataset,                 # ADSL being built
  dataset_add,             # source domain (EX, DS, VS, etc.)
  by_vars   = exprs(...),  # join keys, e.g. exprs(STUDYID, USUBJID)
  new_vars  = exprs(...),  # variables to bring across, with optional rename
  order     = exprs(...),  # sort order for record selection
  mode      = "first"      # "first" or "last" — which record to take
  filter_add = ...,        # filter applied to dataset_add before selection
  missing_values = list(), # values to use when no match found
  check_type = "warning"   # "warning", "error", or "none" for duplicate handling
)
```

**ADSL examples:**

```r
# TRTSDT: first non-zero dose date per subject
adsl <- adsl |>
  derive_vars_merged(
    dataset_add = ex_dt,
    by_vars     = exprs(STUDYID, USUBJID),
    new_vars    = exprs(TRTSDT = EXSTDT),
    order       = exprs(EXSTDT),
    mode        = "first",
    filter_add  = EXDOSE > 0 & !is.na(EXSTDT)
  )

# TRTEDT: last non-zero dose date per subject
adsl <- adsl |>
  derive_vars_merged(
    dataset_add = ex_dt,
    by_vars     = exprs(STUDYID, USUBJID),
    new_vars    = exprs(TRTEDT = EXENDT),
    order       = exprs(EXENDT),
    mode        = "last",
    filter_add  = EXDOSE > 0 & !is.na(EXENDT)
  )

# HEIGHTBL: baseline height from VS
adsl <- adsl |>
  derive_vars_merged(
    dataset_add = vs,
    by_vars     = exprs(STUDYID, USUBJID),
    new_vars    = exprs(HEIGHTBL = VSSTRESN),
    filter_add  = VSTESTCD == "HEIGHT" & VSBLFL == "Y"
  )
```

**Do NOT use `derive_vars_merged()` when:**
- The record selection condition references variables from **both** the input
  dataset and the source dataset simultaneously — use `derive_vars_joined()` instead
- Example of the wrong pattern: assigning period variables to ADAE where you need
  to compare AESTDT against ADSL period start/end dates

---

### `derive_vars_joined()` — when both datasets inform selection

Use when:
- The filter or selection condition involves variables from **both** the input
  dataset and the additional dataset at the same time (`filter_join` argument)
- Typical ADSL use cases are rare; more common in ADAE, ADEX, BDS datasets
- In ADSL context: selecting a DS record where the date must fall within a
  window defined by ADSL variables

**Key difference from `derive_vars_merged()`:**

```r
# derive_vars_merged: filter applies only to dataset_add
filter_add = EXDOSE > 0              # only looks at EX variables

# derive_vars_joined: filter_join can reference both datasets
filter_join = EXSTDT <= ASTDT        # ASTDT is from the input dataset (ADAE)
                                     # EXSTDT is from the source (EX)
```

**When you see yourself doing a merge then a filter on the result**, that is a
signal to use `derive_vars_joined()` instead.

---

### `derive_var_merged_exist_flag()` — existence flags

Use when:
- Adding a flag (`"Y"` / `NA`) indicating whether a subject has **at least one**
  record meeting a condition in another domain
- Standard pattern for SAFFL, and for any flag driven by presence/absence

```r
# SAFFL: received at least one dose
adsl <- adsl |>
  derive_var_merged_exist_flag(
    dataset_add = ex,
    by_vars     = exprs(STUDYID, USUBJID),
    new_var     = SAFFL,
    condition   = EXDOSE > 0 & !is.na(EXSTDTC),
    true_value  = "Y",
    false_value = NA_character_,   # CDISC: never "N"
    missing_value = NA_character_  # subjects absent from EX get NA
  )
```

Note: `derive_var_merged_exist_flag()` is a convenience wrapper around
`derive_vars_merged()`. For flags driven by **multiple source domains** (e.g. a
flag that is `"Y"` if a record exists in CM **or** PR), use the more powerful
`derive_var_merged_ef_msrc()` instead.

---

### `derive_var_merged_ef_msrc()` — existence flags from multiple sources

Use when:
- A flag is `"Y"` if a condition is met in **any** of several source datasets
- Common for prior therapy flags, comorbidity flags spanning multiple domains

```r
# ANYTRTFL: received any anti-cancer treatment (CM or PR)
adsl <- adsl |>
  derive_var_merged_ef_msrc(
    by_vars    = exprs(STUDYID, USUBJID),
    new_var    = ANYTRTFL,
    flag_events = list(
      flag_event(dataset_name = "cm", condition = CMCAT == "ANTI-CANCER"),
      flag_event(dataset_name = "pr")   # all PR records count
    ),
    source_datasets = list(cm = cm, pr = pr)
  )
```

---

### `derive_vars_dt()` — date derivation from `--DTC`

Use when:
- Converting an SDTM character date (`--DTC`) to a SAS/R Date variable
- Need to handle partial dates with imputation

```r
ds_dt <- ds |>
  derive_vars_dt(
    dtc              = DSDTC,
    new_vars_prefix  = "DS",          # creates DSDT and DSDTF
    date_imputation  = "last",        # "first", "last", "mid", or "none"
    flag_imputation  = "auto"         # auto-creates imputation flag
  )
```

**Never** use `as.Date()` directly on `--DTC` variables. It will silently return
`NA` for partial dates (e.g. `"2023-06"`) without any warning.

**Imputation rules for ADSL:**
- Start date variables (TRTSDT, RANDDT): `date_imputation = "first"`
- End date variables (TRTEDT, EOSDT): `date_imputation = "last"`
- Reference dates from DM (RFSTDTC, RFENDTC): follow the protocol definition

---

### `derive_vars_dtm()` — datetime derivation from `--DTC`

Use when:
- The source variable contains datetime information (`--DTC` with time component)
- Creating TRTSTM / TRTENDTM before deriving date-only variables

```r
ex_dtm <- ex |>
  derive_vars_dtm(
    dtc              = EXSTDTC,
    new_vars_prefix  = "EXST",
    date_imputation  = "first",
    time_imputation  = "first",     # "first" = 00:00:00, "last" = 23:59:59
    flag_imputation  = "auto"
  )
```

For ADSL, derive the datetime first, then extract the date:
```r
adsl <- adsl |>
  mutate(TRTSDT = as.Date(TRTSTM))
```

---

### `derive_vars_dy()` — study day calculation

Use when:
- Computing `--DY` variables (study day relative to a reference date)
- **Always use this function** — never compute manually with date subtraction

```r
adsl <- adsl |>
  derive_vars_dy(
    reference_date = TRTSDT,
    source_vars    = exprs(RANDDT, EOSDT)
    # creates RANDDY and EOSDY automatically
  )
```

CDISC study day convention: day 1 is the reference date; there is no day 0.
This function handles that correctly. Manual subtraction (`date2 - date1`) does not.

---

### `derive_var_trtdurd()` — treatment duration

Use when:
- Deriving TRTDURD (total treatment duration in days)

```r
adsl <- adsl |>
  derive_var_trtdurd()
  # Requires TRTSDT and TRTEDT to already be present
```

---

### `derive_vars_disposition_status()` — disposition variables

Use when:
- Deriving EOSSTT (end of study status) from DS
- Handles multiple DS records per subject and category filtering

```r
adsl <- adsl |>
  derive_vars_disposition_status(
    dataset_ds      = ds_dt,
    new_var         = EOSSTT,
    status_var      = DSSCAT,
    filter_ds       = DSCAT == "DISPOSITION EVENT",
    format_new_var  = format_eossttu   # built-in formatter
  )
```

If your study's DS structure does not map cleanly to the built-in formatter,
fall back to `derive_vars_merged()` with explicit `filter_add` and manual
`new_vars` specification. Add a `# REVIEW:` comment explaining the deviation.

---

### `derive_vars_merged_lookup()` — controlled terminology mapping

Use when:
- Mapping a coded value to a decode using a lookup table
- Applying CDISC CT or study-specific controlled terminology

```r
# Example: mapping ARMCD to numeric treatment code
arm_lookup <- tibble::tribble(
  ~ARMCD,  ~TRT01PN,
  "A",     1,
  "B",     2,
  "P",     99
)

adsl <- adsl |>
  derive_vars_merged_lookup(
    dataset_add = arm_lookup,
    by_vars     = exprs(ARMCD),
    new_vars    = exprs(TRT01PN)
  )
```

---

### `derive_vars_cat()` — categorisation variables

Use when:
- Deriving `--CAT` variables (e.g. AGEGR1, BMI category) from a definition table
- Preferred over `case_when()` for any categorisation that will be reused or
  needs to be spec-driven

```r
# Age grouping from a definition tibble
agegr1_lookup <- exprs(
  ~condition,       ~AGEGR1,   ~AGEGR1N,
  AGE < 18,         "<18",     1,
  AGE < 65,         "18-<65",  2,
  TRUE,             ">=65",    3
)

adsl <- adsl |>
  derive_vars_cat(
    definition = agegr1_lookup,
    by_vars    = exprs(AGE)
  )
```

Cut points **must** come from the ADaM specification. Do not hardcode.

---

## Common Pitfalls

### 1. Using `slice()` instead of `derive_vars_merged()` with `mode`

```r
# WRONG — loses admiral traceability, fragile to sort order
ex |>
  group_by(USUBJID) |>
  slice(1) |>
  select(USUBJID, EXSTDT) |>
  left_join(adsl, by = "USUBJID")

# CORRECT
adsl |>
  derive_vars_merged(
    dataset_add = ex,
    by_vars     = exprs(USUBJID),
    new_vars    = exprs(TRTSDT = EXSTDT),
    order       = exprs(EXSTDT),
    mode        = "first",
    filter_add  = EXDOSE > 0
  )
```

### 2. Using `"N"` for flag variables

```r
# WRONG — violates CDISC ADaM convention
mutate(SAFFL = if_else(has_dose, "Y", "N"))

# CORRECT — "Y" or NA only
mutate(SAFFL = if_else(has_dose, "Y", NA_character_))
```

### 3. Forgetting `filter_add = EXDOSE > 0` for treatment dates

Subjects may have zero-dose EX records (e.g. dose not given, dose omitted).
TRTSDT must reflect actual drug exposure. Always filter `EXDOSE > 0` (or the
protocol-equivalent condition) when deriving treatment start/end dates.

### 4. Conflating TRT01P and TRT01A

| Variable | Source | Meaning |
|---|---|---|
| TRT01P / TRT01PA | DM.ARM / DM.ACTARM | Planned treatment (randomisation) |
| TRT01A | EX | Actual treatment received |

These are different. In most studies they match, but they diverge for subjects
who receive wrong treatment or cross over. Derive them independently.

### 5. Missing `DOMAIN` variable conflicts in `derive_vars_merged()`

If the source domain retains its `DOMAIN` variable and ADSL also has `DOMAIN`,
admiral will error. Remove it from the source before merging:

```r
adsl |>
  derive_vars_merged(
    dataset_add = select(ex, -DOMAIN),
    ...
  )
```

### 6. Not setting `check_type`

By default `check_type = "warning"` — duplicate by-group records in `dataset_add`
produce a warning but proceed. For ADSL derivations this should usually be
`"error"` when you expect one record per subject, or ensure `filter_add` + `order`
+ `mode` guarantee uniqueness before the merge.

---

## Quick Reference Card

| Situation | Function |
|---|---|
| Merge value from another domain (one record per subject) | `derive_vars_merged()` |
| Select first/last record per subject | `derive_vars_merged()` with `order` + `mode` |
| Selection depends on variables in both datasets | `derive_vars_joined()` |
| Flag: subject has ≥1 record meeting condition (single source) | `derive_var_merged_exist_flag()` |
| Flag: subject has ≥1 record meeting condition (multiple sources) | `derive_var_merged_ef_msrc()` |
| Convert `--DTC` to Date | `derive_vars_dt()` |
| Convert `--DTC` to Datetime | `derive_vars_dtm()` |
| Study day calculation | `derive_vars_dy()` |
| Treatment duration | `derive_var_trtdurd()` |
| Disposition status from DS | `derive_vars_disposition_status()` |
| Controlled terminology mapping | `derive_vars_merged_lookup()` |
| Categorisation variables (AGEGR1 etc.) | `derive_vars_cat()` |
| Numeric summary (count, sum) | `derive_var_merged_summary()` |
