# Benchmark Result: basic-two-arm

## Run Metadata

| Field | Value |
|---|---|
| **Date** | 2026-05-14 |
| **Agent** | Claude Sonnet 4.6 (VS Code) |
| **Model** | claude-sonnet-4-6 |
| **Skill version** | admiral-adsl v0.1 (initial merge) |
| **admiral version** | confirm with `packageVersion("admiral")` |
| **pharmaversesdtm version** | confirm with `packageVersion("pharmaversesdtm")` |
| **pharmaverseadam version** | confirm with `packageVersion("pharmaverseadam")` |
| **Generated code** | `results/claude-sonnet-4-6-vscode/adsl.R` |
| **Skill loading method** | confirm — auto-discovered or manually provided |
| **Branch** | Created from commit `57d0968` to exclude prior results |
| **Note** | Same model as Claude Code run; different agent infrastructure |

---

## Score Summary

| Dimension | Max | Score |
|---|---|---|
| 1. Correctness | 40 | 37 |
| 2. admiral Idioms | 25 | 20 |
| 3. CDISC Conformance | 20 | 17 |
| 4. QC Readiness | 10 | 8 |
| 5. Completeness | 5 | 3 |
| **Total** | **100** | **85** |

**Result: PASS** (threshold: ≥ 70 with no zero in any dimension)

---

## Dimension 1: Correctness (37/40)

### Structural integrity (10/10)

```r
nrow(adsl_cl) == n_distinct(adsl_cl$USUBJID)  # TRUE — 306 subjects
```

All 306 USUBJID values present. No duplicates.

### Treatment dates (10/10)

Comparison against `pharmaverseadam::adsl` after `haven::zap_labels()`:

100% agreement on TRTSDT, TRTEDT, TRT01P, TRT01A, EOSSTT, SAFFL.
No differences in key correctness variables.

### Treatment variables (10/10)

TRT01P and TRT01A correct. TRT01PN/TRT01AN correctly coded against actual
pharmaversesdtm ARMCD values (Xanomeline High Dose = 3, Low Dose = 2,
Placebo = 1). TRTDURD computed manually but produces correct values for
this dataset.

### Disposition (7/10)

EOSSTT correctly categorised to `"COMPLETED"` / `"DISCONTINUED"` via
`case_when()` after merging `DSDECOD` — the primary failure mode in
Positron avoided here. DCSREAS correctly set to `NA_character_` for
completers.

**LSTALVDT — 52 differences:** Values are `NA` in this run where Claude Code
has dates. The derivation uses `group_by/summarise` + `left_join` + `pmax()`
rather than `derive_vars_merged()` with `mode = "last"`. Per the rubric,
LSTALVDT implementation differences are an acceptable deviation — however
52 `NA` values suggests an incomplete source domain list or a gap in the
`pmax()` logic rather than a different-but-valid approach. **-3 points.**

---

## Dimension 2: admiral Idioms (20/25)

### Function selection (12/15)

| Check | Result |
|---|---|
| `derive_vars_merged()` used for treatment date derivations | ✅ |
| `derive_vars_dtm()` used for `--DTC` to datetime conversion | ✅ |
| `flag_imputation = "auto"` set AND flags in `new_vars` | ✅ Correct — fixes Positron partial-compliance pattern |
| `derive_vars_dt()` used for reference date conversions | ✅ |
| `derive_var_merged_exist_flag()` used for SAFFL | ✅ |
| `exprs()` used correctly for all admiral verb arguments | ✅ |
| Placebo filter in SAFFL derivation | ✅ `grepl("PLACEBO", EXTRT, ignore.case = TRUE)` |
| `derive_var_trtdurd()` used for TRTDURD | ❌ Manual: `as.integer(TRTEDT - TRTSDT) + 1L` |
| `derive_vars_dy()` used for RANDDY | ❌ Not derived |
| `derive_vars_merged()` used for LSTALVDT | ❌ `group_by/summarise` + `left_join` + `pmax()` |

### Pipe style (5/5)

Native pipe `|>` throughout. `exprs()` used correctly. ✅

### filter_add correctness (3/5)

Placebo filter present in SAFFL derivation. However placebo filter absent
from treatment date derivations — `filter_add = !is.na(EXSTDTM)` only,
without the `EXDOSE > 0 | grepl("PLACEBO")` condition. **-2 points.**

---

## Dimension 3: CDISC Conformance (17/20)

### Flag variable convention (8/8)

SAFFL, ITTFL, DTHFL all use `"Y"` or `NA_character_` only.
DTHFL correctly re-coded from DM with `if_else(DTHFL == "Y", "Y", NA_character_)`. ✅

### Date imputation (6/7)

| Variable | Imputation | Correct |
|---|---|---|
| EXSTDTC | `date_imputation = "first"`, `time_imputation = "first"` | ✅ |
| EXENDTC | `date_imputation = "last"`, `time_imputation = "last"` | ✅ |
| RFSTDTC | `date_imputation = "none"` | ❌ Should be `"first"` |
| RFENDTC | `date_imputation = "none"` | ❌ Should be `"last"` |
| DTHDTC  | `date_imputation = "none"` | ❌ Should be `"first"` |

`date_imputation = "none"` means partial dates (e.g. `"2023-06"`) will
return `NA` rather than being imputed. For reference and death dates, partial
dates should be imputed to earliest/latest as appropriate. This is a latent
risk that may not affect the pharmaversesdtm data but would affect real study
data. **-1 point.**

Imputation flags TRTSTMF and TRTETMF correctly generated and retained. ✅

### Dataset structure (3/5)

AGEGR1 cut-points match prompt spec exactly (`"<65"` / `"65-80"` / `">80"`). ✅
AGEGR1N present and correctly coded. ✅
`DOMAIN` not removed from EX before `derive_var_merged_exist_flag()` — no
error in this run but a latent risk flagged in `admiral-functions.md`. **-2 points.**

---

## Dimension 4: QC Readiness (8/10)

### REVIEW annotations (6/6)

`# REVIEW:` comments present at all required locations:

| Location | Present |
|---|---|
| SAFFL — placebo condition explained | ✅ |
| ITTFL — statistician sign-off requested | ✅ |
| EOSSTT/DS record selection | ✅ |
| AGEGR1 cut-points | ✅ |
| LSTALVDT source priority hierarchy | ✅ |
| TRTDURD inclusive/exclusive question | ✅ |
| TRT01PN/TRT01AN coding | ✅ |

### Derivation comments (2/4)

Every step has a structured header comment with target variable and source.
CDISC ADaM IG v1.3 referenced in file header. XPT export pipeline shown
(commented out) with correct `{xportr}` approach. **-1 point:** `date_imputation = "none"`
on reference dates lacks a `# REVIEW:` annotation — a real decision that
should be flagged. **-1 point:** EOSSTT two-step derivation (merge then
`case_when` correction) uncommented — confusing pattern without explanation.

---

## Dimension 5: Completeness (3/5)

- ✅ `stopifnot()` with descriptive error message
- ✅ Required variable check present (9 variables)
- ✅ All 34 selected variables labelled via `Hmisc::label()`
- ✅ XPT export pipeline shown (commented) with `{xportr}` and `{metacore}`
- ❌ 6 required variables missing from output: `ARM`, `ARMCD`, `ACTARM`,
  `ACTARMCD`, `RANDDY`, `DCSREASP` — carried in spine but dropped in `select()`
- ❌ Required variable check only tests 9 of the prompt's full required list

**-2 points.**

---

## Four-Way Comparison

| Dimension | Claude Code | Claude Sonnet VS Code | GPT-5.3-Codex | Positron |
|---|---|---|---|---|
| 1. Correctness | 40 | 37 | 28 | 18 |
| 2. admiral Idioms | 25 | 20 | 18 | 17 |
| 3. CDISC Conformance | 20 | 17 | 13 | 7 |
| 4. QC Readiness | 10 | 8 | 6 | 5 |
| 5. Completeness | 5 | 3 | 2 | 1 |
| **Total** | **100** | **85** | **67** | **48** |
| **Result** | **PASS** | **PASS** | **FAIL** | **FAIL** |

---

## Key Observations

### 1. Same model, different infrastructure — 15-point gap

Claude Code (100) and Claude Sonnet 4.6 in VS Code (85) use the same
underlying model. The 15-point gap is attributable to three specific issues:
TRTDURD manual computation, LSTALVDT anti-pattern, and missing variables
in the final `select()`. Claude Code's agentic infrastructure — file system
access, iterative execution, multi-step planning — produces more complete
and idiomatic output for a derivation of this complexity.

### 2. EOSSTT correctly handled — primary Positron failure avoided

The two-step pattern (merge `DSDECOD` then `case_when` categorisation) is
slightly unusual — `DSDECOD` is initially set as EOSSTT and DCSREAS in
`new_vars`, then immediately overwritten in `mutate()`. The result is correct
but the pattern is confusing without a comment. A cleaner approach would
derive EOSSTT inline:

```r
new_vars = exprs(
  EOSSTT_RAW = DSDECOD,   # temporary — overwritten below
  DCSREAS    = DSDECOD,
  EOSDT      = DSDT
)
# then mutate EOSSTT from EOSSTT_RAW
```

### 3. `flag_imputation = "auto"` with flags in new_vars — improvement over GPT

Unlike GPT-5.3-Codex (`flag_imputation = "date"`) and Positron (flags not
in `new_vars`), this run correctly sets `flag_imputation = "auto"` and
includes TRTSTMF/TRTETMF in `new_vars`. TRTSTMF and TRTETMF are present
and correct in the output.

### 4. `date_imputation = "none"` — latent risk

Three date derivations use `date_imputation = "none"`: RFSTDTC, RFENDTC,
DTHDTC. This is safe for pharmaversesdtm (complete dates) but would silently
return `NA` for partial dates in real study data. Should be `"first"` for
start/death dates and `"last"` for end dates.

### 5. Pass/fail splits on model family

Both Claude runs pass; both non-Claude runs fail. The consistent failure
modes across GPT and Positron — EOSSTT categorisation, imputation flag
handling, missing variables — suggest these are systematic gaps in how
non-Claude models apply the skill rather than random errors.

---

## Recommended Skill Updates

Updates common to multiple runs are highest priority:

1. **SKILL.md Step 3** — strengthen instruction to include TRTSTMF/TRTETMF
   explicitly in `new_vars`; add a note that setting `flag_imputation`
   without capturing the flag variables provides no traceability benefit
2. **SKILL.md Step 7** — add explicit warning that `DSDECOD` must be
   categorised to `"COMPLETED"`/`"DISCONTINUED"` for EOSSTT — never passed
   through directly; this was the primary failure for Positron and a
   near-miss here
3. **SKILL.md Step 5** — change `date_imputation = "none"` example for
   reference dates to `"first"/"last"` with a note on when `"none"` is
   appropriate
4. **SKILL.md Common Errors** — add `date_imputation = "none"` as a named
   pitfall for reference and death date derivations
5. **SKILL.md Final select** — strengthen the instruction to retain
   `ARM`, `ARMCD`, `ACTARM`, `ACTARMCD` for traceability; these are dropped
   in all non-Claude Code runs
