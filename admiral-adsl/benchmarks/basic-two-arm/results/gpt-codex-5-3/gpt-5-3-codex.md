# Benchmark Result: basic-two-arm

## Run Metadata

| Field | Value |
|---|---|
| **Date** | 2026-05-14 |
| **Agent** | GitHub Copilot (VS Code) |
| **Model** | GPT-5.3-Codex |
| **Skill version** | admiral-adsl v0.1 (initial merge) |
| **admiral version** | confirm with `packageVersion("admiral")` |
| **pharmaversesdtm version** | confirm with `packageVersion("pharmaversesdtm")` |
| **pharmaverseadam version** | confirm with `packageVersion("pharmaverseadam")` |
| **Generated code** | `results/gpt-5-3-codex/adsl.R` |
| **Skill loading method** | Auto-discovered by GitHub Copilot from repo directory |
| **Branch** | Created from commit `57d0968` to exclude prior Claude Code results |

---

## Score Summary

| Dimension | Max | Score |
|---|---|---|
| 1. Correctness | 40 | 28 |
| 2. admiral Idioms | 25 | 18 |
| 3. CDISC Conformance | 20 | 13 |
| 4. QC Readiness | 10 | 6 |
| 5. Completeness | 5 | 2 |
| **Total** | **100** | **67** |

**Result: FAIL** (threshold: ≥ 70 with no zero in any dimension)

---

## Dimension 1: Correctness (28/40)

### Structural integrity (10/10)

```r
nrow(adsl_gpt) == n_distinct(adsl_gpt$USUBJID)  # TRUE — 306 subjects
```

All 306 USUBJID values present. No duplicates.

### Treatment dates (10/10)

Comparison against `pharmaverseadam::adsl` after `haven::zap_labels()`:

```r
# A tibble: 1 × 6
  trtsdt_match trtedt_match trt01p_match trt01a_match eosstt_match saffl_match
         <dbl>        <dbl>        <dbl>        <dbl>        <dbl>       <dbl>
1            1            1            1            1            1           1
```

100% agreement on TRTSDT, TRTEDT, TRT01P, TRT01A, EOSSTT, SAFFL.

### Treatment variables (6/10)

TRT01P and TRT01A correct. TRT01PN/TRT01AN present but coded as `numeric`
rather than `integer` — minor class difference, not a correctness failure.
TRTDURD computed manually (`TRTEDT - TRTSDT + 1L`) rather than via
`derive_var_trtdurd()` — result is correct for this dataset but anti-pattern.
**-4 points:** TRTDURD manual computation and numeric/integer class mismatch.

### Disposition (2/10)

EOSSTT 100% correct. However:

**DCSREAS — 46 differences:** GPT mapped `DSTERM` (verbatim text) to `DCSREAS`
instead of `DSDECOD` (decoded value). `DCSREAS` should contain the CDISC
decoded discontinuation reason; `DSTERM` is the verbatim text that belongs in
`DCSREASP`. Examples:

| Subject | Expected (DSDECOD) | GPT output (DSTERM) |
|---|---|---|
| Row 4 | `STUDY TERMINATED BY SPONSOR` | `SPONSOR DECISION (STUDY OR PAT...)` |
| Row 29 | `WITHDRAWAL BY SUBJECT` | `WITHDRAW CONSENT` |
| Row 39 | `PHYSICIAN DECISION` | `PMD DECISION DUE TO AE'S` |

**-8 points:** DCSREAS sourced from wrong DS variable.

---

## Dimension 2: admiral Idioms (18/25)

### Function selection (9/15)

| Check | Result |
|---|---|
| `derive_vars_merged()` used for treatment date derivations | ✅ |
| `derive_vars_dtm()` used for `--DTC` to datetime conversion | ✅ |
| `exprs()` used correctly for admiral verb arguments | ✅ |
| `derive_vars_dt()` used for date conversions | ✅ |
| `derive_var_merged_exist_flag()` used for SAFFL | ✅ |
| `derive_var_trtdurd()` used for TRTDURD | ❌ Manual: `as.integer(TRTEDT - TRTSDT + 1L)` |
| `derive_vars_merged()` used for LSTALVDT | ❌ `group_by/summarise` + `left_join` + `rowwise/mutate` |
| `derive_vars_dy()` used for study day variables | ❌ Not derived at all (RANDDY missing) |

### Pipe style (5/5)

Native pipe `|>` throughout. ✅

### filter_add correctness (4/5)

Placebo filter correct in principle. However, `suppressWarnings(as.numeric(EXDOSE))`
is fragile — EXDOSE should already be numeric in admiral-processed EX data.
Applied in both filter step and SAFFL derivation. **-1 point.**

---

## Dimension 3: CDISC Conformance (13/20)

### Flag variable convention (8/8)

SAFFL, ITTFL, DTHFL all use `"Y"` or `NA_character_` only. ✅

Note: SAFFL has a redundant `mutate(SAFFL = if_else(SAFFL == "Y", "Y", NA_character_))`
after `derive_var_merged_exist_flag()` — unnecessary but harmless.

### Date imputation (3/7)

| Check | Result |
|---|---|
| `date_imputation = "first"` for start dates | ✅ |
| `time_imputation = "last"` for end datetimes | ✅ |
| `flag_imputation = "auto"` for both | ❌ Uses `"date"` — critical failure |

**`flag_imputation = "date"` is the primary failure of this run.**

`"date"` generates only a date imputation flag, silently dropping the time
imputation flag. `"auto"` generates both date and time flags as required by
ADaM traceability conventions. Result: TRTSTMF and TRTETMF are `NA` for 254
and 252 subjects respectively where `"H"` (time imputed) is expected.

This error is non-obvious — `"date"` is a valid argument value that runs
without error, producing output that appears correct until compared against
a reference. It would not be caught by execution alone.

**-4 points:** imputation flag traceability broken for majority of subjects.

### Dataset structure (2/5)

`select(-any_of("DOMAIN"))` correctly applied to EX. AGEGR1 cut-points correct.
AGEGR1N present. **-3 points:** `select(-DOMAIN)` not applied to DS before
merge (though no error resulted for this dataset).

---

## Dimension 4: QC Readiness (6/10)

### REVIEW annotations (4/6)

| Location | Present |
|---|---|
| SAFFL derivation | ✅ |
| ITTFL derivation | ✅ |
| DS record selection | ✅ |
| Placebo filter | ✅ |
| AGEGR1 cut-points | ❌ |
| TRTDURD manual computation | ❌ |

### Derivation comments (2/4)

Step comments present but less systematic than required. No ADaMIG version
references. DCSREAS/DCSREASP distinction not commented — the source of the
primary correctness failure. **-2 points.**

---

## Dimension 5: Completeness (2/5)

`stopifnot()` assertion present and passes. Labels applied to all selected
variables. Dataset label `"Subject-Level Analysis Dataset"` applied via `attr()`.

**8 required variables missing from output:**
`ARM`, `ARMCD`, `ACTARM`, `ACTARMCD`, `RFSTDT`, `RFENDDT`, `RANDDY`,
`DCSREASP`

Note: `ARM` and `ARMCD` were present in the subject spine but dropped in the
final `select()`. `ACTARMCD` was never carried forward from DM. `DCSREASP`
was merged as `DSTERM_EOS` but not retained in output. **-3 points.**

---

## Comparison with Claude Code (claude-sonnet-4-6)

| Dimension | Claude Code | GPT-5.3-Codex | Delta |
|---|---|---|---|
| 1. Correctness | 40 | 28 | -12 |
| 2. admiral Idioms | 25 | 18 | -7 |
| 3. CDISC Conformance | 20 | 13 | -7 |
| 4. QC Readiness | 10 | 6 | -4 |
| 5. Completeness | 5 | 2 | -3 |
| **Total** | **100** | **67** | **-33** |

---

## Key Failure Analysis

### 1. `flag_imputation = "date"` instead of `"auto"` (Dimension 3)

The most consequential error. A valid admiral argument with the wrong value —
runs without error, produces subtly incorrect output. `"auto"` generates date
and time imputation flags; `"date"` generates only the date flag. Result:
TRTSTMF and TRTETMF are `NA` for 254/252 of 306 subjects.

This would not be caught by code review without specific admiral knowledge,
and not caught by execution without comparison to a reference dataset.

### 2. DCSREAS sourced from DSTERM instead of DSDECOD (Dimensions 1 and 3)

`DCSREAS` should contain the CDISC-decoded value from `DS.DSDECOD`.
`DCSREASP` contains the verbatim text from `DS.DSTERM`. GPT reversed the
mapping — 46 subjects affected. The variable names are present and correctly
labelled, but the source variables are swapped.

### 3. LSTALVDT via rowwise/summarise instead of derive_vars_merged() (Dimension 2)

Used `group_by/summarise` + `left_join` + `rowwise/mutate` — the anti-pattern
explicitly warned against in the skill. Produces a different (later) result
for 42 subjects, likely because it includes DS dates not included in the
Claude Code derivation. Logic is defensible but non-idiomatic.

### 4. Missing variables (Dimension 5)

ARM/ARMCD/ACTARMCD were available in the spine but not retained. RANDDY was
never derived. DCSREASP was merged but dropped in final select.

---

## Benchmark Integrity Note

An initial run was attempted with GPT-5.3-Codex on the main benchmark branch
which contained the Claude Code generated `adsl.R` in `results/`. That run was
invalidated as the model appeared to locate and reproduce the existing output.

This run was conducted on a clean branch created from commit `57d0968`
(prompt and rubric files only, no prior results) to ensure benchmark integrity.

**Recommendation:** Add to `rubric.md` protocol: always run benchmarks on a
branch that does not contain prior results directories.

---

## Recommended Skill Updates

Based on this run, the following additions to the skill are recommended:

1. **SKILL.md Common Errors** — add `flag_imputation = "date"` as an explicit
   named pitfall; `"auto"` is always correct for ADSL derivations
2. **admiral-functions.md** — add `flag_imputation` argument explanation to
   the `derive_vars_dtm()` section; distinguish `"auto"`, `"date"`, `"time"`,
   `"none"`
3. **adsl-conventions.md** — add explicit note that `DCSREAS` = `DSDECOD`
   (decoded) and `DCSREASP` = `DSTERM` (verbatim); this is a common confusion
   point
4. **rubric.md** — add `flag_imputation = "date"` as an explicit fail
   condition in Dimension 3; add benchmark integrity protocol note
