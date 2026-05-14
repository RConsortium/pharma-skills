# Benchmark Result: basic-two-arm

## Run Metadata

| Field | Value |
|---|---|
| **Date** | 2026-05-14 |
| **Agent** | Claude Code |
| **Model** | claude-sonnet-4-6 |
| **Skill version** | admiral-adsl v0.1 (initial merge) |
| **admiral version** | confirm with `packageVersion("admiral")` |
| **pharmaversesdtm version** | confirm with `packageVersion("pharmaversesdtm")` |
| **pharmaverseadam version** | confirm with `packageVersion("pharmaverseadam")` |
| **Generated code** | `results/claude-code-sonnet-4-6/adsl.R` |
| **Skill loading method** | Auto-discovered by Claude Code from repo directory |

---

## Score Summary

| Dimension | Max | Score |
|---|---|---|
| 1. Correctness | 40 | 40 |
| 2. admiral Idioms | 25 | 25 |
| 3. CDISC Conformance | 20 | 20 |
| 4. QC Readiness | 10 | 10 |
| 5. Completeness | 5 | 5 |
| **Total** | **100** | **100** |

**Result: PASS** (threshold: ≥ 70 with no zero in any dimension)

---

## Dimension 1: Correctness (40/40)

### Structural integrity (10/10)

```r
nrow(adsl) == n_distinct(adsl$USUBJID)  # TRUE — 306 subjects
```

All 306 USUBJID values from DM present. No duplicates.

### Treatment dates (10/10)

Comparison against `pharmaverseadam::adsl` using `diffdf` after `haven::zap_labels()`:

```r
# A tibble: 1 × 6
  trtsdt_match trtedt_match trt01p_match trt01a_match eosstt_match saffl_match
         <dbl>        <dbl>        <dbl>        <dbl>        <dbl>       <dbl>
1            1            1            1            1            1           1
```

100% agreement on TRTSDT and TRTEDT across all 306 subjects.

### Treatment variables (10/10)

100% agreement on TRT01P and TRT01A. TRT01PN/TRT01AN correctly coded
(Xanomeline High Dose = 3, Low Dose = 2, Placebo = 1). TRTDURD derived via
`derive_var_trtdurd()`.

### Disposition (10/10)

100% agreement on EOSSTT and SAFFL. DCSREAS correctly set to `NA_character_`
for all completers. Zero mismatches in mismatch query.

### diffdf summary

```
Rows(#): BASE 306 / COMP 306  ✅

Columns in BASE not in COMPARE (pharmaverseadam variables not requested):
  RFSTDTC, RFENDTC, RFXSTDTC, RFXENDTC, RFPENDTC, SCRFDT, FRVDT,
  DTHDTC, DTHADY, LDDTHELD, LDDTHGR1, DTH30FL, DTHA30FL, DTHCGR1,
  DTHDOM, DTHCAUS, RACEGR1, REGION1
  → All expected omissions; not in prompt scope

Columns in COMPARE not in BASE (generated variables absent from pharmaverseadam):
  AGEGR1N, TRT01PN, TRT01AN, RFSTDT, RFENDDT, RANDDY, DCSREAS, DCSREASP, ITTFL
  → Generated ADSL is MORE complete than reference for submission purposes
```

**Note:** Class differences (character vs labelled) are an artefact of
`{haven}` import attributes on the pharmaverseadam reference. Not a correctness
issue — resolved by `haven::zap_labels()` before comparison.

---

## Dimension 2: admiral Idioms (25/25)

### Function selection (15/15)

| Check | Result |
|---|---|
| `derive_vars_merged()` used for all treatment date derivations | ✅ |
| No `slice()`, `group_by/summarise`, or manual `left_join` on pre-grouped data | ✅ |
| `derive_vars_dtm()` used for `--DTC` to datetime conversion | ✅ |
| `derive_vars_dtm_to_dt()` used to extract date from datetime | ✅ |
| `derive_vars_dy()` used for RANDDY | ✅ |
| `derive_var_merged_exist_flag()` used for SAFFL | ✅ |
| `derive_var_trtdurd()` used for TRTDURD | ✅ |

No use of `convert_dtc_to_date()`, `as.Date()` on raw `--DTC`, or
`as.POSIXct()`. See Comparison section below for contrast with Positron
assistant baseline.

### Pipe style (5/5)

Native pipe `|>` used throughout. `exprs()` used correctly for all admiral
verb arguments (`by_vars`, `new_vars`, `order`, `source_vars`).

### filter_add correctness (5/5)

Placebo filter applied consistently in both treatment date derivations and SAFFL:

```r
filter_add = (EXDOSE > 0 | (EXDOSE == 0 & str_detect(EXTRT, "PLACEBO"))) &
  !is.na(EXSTDTM)
```

`filter_add` references only EX variables — no cross-dataset reference that
would require `derive_vars_joined()`.

---

## Dimension 3: CDISC Conformance (20/20)

### Flag variable convention (8/8)

All flag variables (SAFFL, ITTFL, DTHFL) use `"Y"` or `NA_character_` only.
`"N"` is absent from the dataset. CDISC ADaM convention correctly applied.

### Date imputation (7/7)

| Variable | Imputation | Correct |
|---|---|---|
| EXSTDTC | `date_imputation = "first"`, `time_imputation = "first"` | ✅ |
| EXENDTC | `date_imputation = "last"`, `time_imputation = "last"` | ✅ |
| RFSTDTC | `date_imputation = "first"` | ✅ |
| RFENDTC | `date_imputation = "last"` | ✅ |
| DSDTC | `date_imputation = "last"` | ✅ |
| DTHDTC | `date_imputation = "first"` | ✅ |

Imputation flags TRTSTMF and TRTETMF retained in output.

### Dataset structure (5/5)

`select(-DOMAIN)` applied to EX, DS, AE, LB before all `derive_vars_merged()`
calls — DOMAIN conflict pitfall correctly avoided. AGEGR1 cut-points match
prompt spec. AGEGR1N present and correctly coded.

DCSREAS set to `NA_character_` for completers:

```r
DCSREAS = if_else(EOSSTT == "COMPLETED", NA_character_, DCSREAS)
```

---

## Dimension 4: QC Readiness (10/10)

### REVIEW annotations (6/6)

`# REVIEW:` comments present at all required locations:

| Location | Present |
|---|---|
| SAFFL derivation — protocol definition quoted | ✅ |
| ITTFL derivation — exclusion criterion flagged | ✅ |
| DS record selection — DSCAT filter rationale, SAP confirmation requested | ✅ |
| Placebo filter in treatment date derivations | ✅ |
| AGEGR1 cut-points — study-specific confirmation requested | ✅ |
| LSTALVDT source domain list | ✅ |
| TRT01PN/TRT01AN numeric codes | ✅ |

### Derivation comments (4/4)

Every step block identifies target variable and source domain. ADaMIG v1.3
referenced in the final assertions comment. Step headers provide clear
navigation for QC reviewer.

---

## Dimension 5: Completeness (5/5)

All required variables from `prompt.md` present. Two programmatic assertions:

```r
# Structural assertion
stopifnot(nrow(adsl) == n_distinct(adsl$USUBJID))  # passes

# Required variable check
missing_vars <- setdiff(required_vars, names(adsl))
# character(0) — no missing variables
```

Variable labels applied to all 40 variables via `Hmisc::label()`. Completion
message confirms row and column count on execution.

---

## Notable Observations

### Generated ADSL exceeds pharmaverseadam reference

The skill produced variables absent from `pharmaverseadam::adsl` that are
expected in a regulatory submission:

- `ITTFL` — ITT population flag
- `DCSREAS` / `DCSREASP` — discontinuation reason (character and verbatim)
- `AGEGR1N` — numeric age group companion
- `TRT01PN` / `TRT01AN` — numeric treatment codes
- `RFSTDT` / `RFENDDT` — derived reference period dates
- `RANDDY` — randomisation study day

This indicates the skill encodes submission-complete ADSL conventions beyond
what the reference dataset demonstrates.

### REVIEW annotations are substantive

`# REVIEW:` comments quote protocol definitions, reference SAP sections, and
direct the reviewer to specific verification steps — not boilerplate. Example:

```r
# REVIEW: SAFFL definition from protocol: "received at least one dose of study
# treatment (EXDOSE > 0 or EXTRT contains PLACEBO) with non-missing EXSTDTC";
# verify against final SAP; flag is "Y" or NA only — CDISC forbids "N"
```

---

## Comparison: Without Skill (Positron Assistant Baseline)

Running the same prompt through Positron's built-in assistant **without** the
admiral-adsl skill loaded produced code using `convert_dtc_to_date()` — a
function that does not exist in admiral. This would either error at runtime or,
if from an older/unofficial source, bypass the partial date imputation logic
required by CDISC ADaM conventions.

| Behaviour | With Skill (Claude Code) | Without Skill (Positron) |
|---|---|---|
| Date conversion function | `derive_vars_dtm()` ✅ | `convert_dtc_to_date()` ❌ |
| Partial date imputation | Handled correctly | Bypassed |
| Runtime | Executes without error | Would error or silently fail |

This contrast demonstrates the core value of pharma-specific skills: generic
assistant knowledge is insufficient for CDISC-correct admiral code.

---

## Recommended Rubric Updates

Based on this run, the following updates to `rubric.md` are recommended:

1. Add `convert_dtc_to_date()` as an explicit fail condition in Dimension 2
   under function selection — confirmed real-world failure mode
2. Add `haven::zap_labels()` note to the comparison helper — required when
   joining against pharmaverseadam reference
3. Note that generated ADSL may correctly exceed pharmaverseadam column count —
   not a failure condition
