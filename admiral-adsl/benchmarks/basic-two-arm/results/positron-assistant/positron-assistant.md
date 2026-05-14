# Benchmark Result: basic-two-arm

## Run Metadata

| Field | Value |
|---|---|
| **Date** | 2026-05-14 |
| **Agent** | Positron Assistant |
| **Model** | confirm model name |
| **Skill version** | admiral-adsl v0.1 (initial merge) |
| **admiral version** | confirm with `packageVersion("admiral")` |
| **pharmaversesdtm version** | confirm with `packageVersion("pharmaversesdtm")` |
| **pharmaverseadam version** | confirm with `packageVersion("pharmaverseadam")` |
| **Generated code** | `results/positron-assistant/adsl.R` |
| **Skill loading method** | confirm — manually provided or auto-discovered |
| **Branch** | Created from commit `57d0968` to exclude prior results |

---

## Score Summary

| Dimension | Max | Score |
|---|---|---|
| 1. Correctness | 40 | 18 |
| 2. admiral Idioms | 25 | 17 |
| 3. CDISC Conformance | 20 | 7 |
| 4. QC Readiness | 10 | 5 |
| 5. Completeness | 5 | 1 |
| **Total** | **100** | **48** |

**Result: FAIL** (threshold: ≥ 70 with no zero in any dimension)

---

## Dimension 1: Correctness (18/40)

### Structural integrity (10/10)

```r
nrow(adsl_pos) == n_distinct(adsl_pos$USUBJID)  # TRUE — 306 subjects
```

All 306 USUBJID values present. No duplicates.

### Treatment dates (10/10)

Comparison against `pharmaverseadam::adsl` after `haven::zap_labels()`:

TRTSDT and TRTEDT are 100% correct — treatment date derivation is sound.
TRT01P and TRT01A match reference. SAFFL matches reference.

### Treatment variables (4/10)

TRT01P and TRT01A correct. However TRT01PN and TRT01AN are coded against
incorrect ARMCD values (`"Pbo"`, `"ARM A"`, `"ARM B"`, `"ARM C"`) which do
not exist in pharmaversesdtm — the actual values are `"Xan_Hi"`, `"Xan_Lo"`,
`"Placebo"`. All subjects will have `NA` for TRT01PN and TRT01AN.
TRTDURD correctly derived via `derive_var_trtdurd()`. **-6 points.**

### Disposition (−6/10)

**EOSSTT — 196 differences:** Critical failure. Both EOSSTT and DCSREAS are
mapped directly from `DSDECOD`:

```r
new_vars = exprs(
  EOSSTT = DSDECOD,
  DCSREAS = DSDECOD
)
```

`DSDECOD` contains discontinuation reason values (`"ADVERSE EVENT"`,
`"SCREEN FAILURE"`, `"COMPLETED"`) which were passed through directly to
EOSSTT. EOSSTT must be categorised as `"COMPLETED"` or `"DISCONTINUED"` —
the agent missed the transformation step entirely.

**DCSREAS — 110 differences:** A direct consequence of the EOSSTT error.
Since both variables are set to `DSDECOD`, DCSREAS contains `"COMPLETED"`
for completers instead of `NA`. **-10 points.**

---

## Dimension 2: admiral Idioms (17/25)

### Function selection (10/15)

| Check | Result |
|---|---|
| `derive_vars_merged()` used for treatment date derivations | ✅ |
| `derive_vars_dtm()` used for `--DTC` to datetime conversion | ✅ |
| `derive_vars_dy()` used for RANDDY | ✅ |
| `derive_var_merged_exist_flag()` used for SAFFL | ✅ |
| `derive_var_trtdurd()` used for TRTDURD | ✅ |
| `exprs()` used correctly for admiral verb arguments | ✅ |
| Placebo filter in treatment date derivations | ❌ Absent — `filter_add = !is.na(EXSTDTM)` only |
| TRTSTMF/TRTETMF merged into ADSL | ❌ `flag_imputation = "auto"` set but flags never in `new_vars` |
| `derive_vars_dt()` used for RANDDT | ❌ `as.Date(DMDTC)` used directly |

### Pipe style (5/5)

Native pipe `|>` throughout. `exprs()` used correctly. ✅

### filter_add correctness (2/5)

Placebo filter absent from both treatment date derivations. Only
`filter_add = !is.na(EXSTDTM)` applied — placebo subjects with `EXDOSE == 0`
may not be captured correctly depending on data structure. **-3 points.**

---

## Dimension 3: CDISC Conformance (7/20)

### Flag variable convention (6/8)

SAFFL and ITTFL correctly use `"Y"` or `NA_character_`. ✅

`ENRLFL = "Y"` set for all subjects — not in prompt scope but not incorrect.

DTHFL absent from output — not derived. **-2 points.**

### Date imputation (4/7)

`flag_imputation = "auto"` set correctly in `derive_vars_dtm()` — better than
GPT-5.3-Codex. However imputation flags (TRTSTMF, TRTETMF) never appear in
`new_vars` and are therefore absent from ADSL. Setting `flag_imputation`
without retaining the flags provides no traceability benefit. **-2 points.**

`as.Date(DMDTC)` used directly for RANDDT — bypasses `derive_vars_dt()` and
loses partial date imputation handling. **-1 point.**

### Dataset structure (−3/5)

**AGEGR1 — 306 differences (every subject):** Agent used SKILL.md default
cut-points (`"<18"` / `"18-<65"` / `">=65"`) rather than the prompt-specified
cut-points (`"<65"` / `"65-80"` / `">80"`). A `# REVIEW:` comment is present
but the agent did not apply the study-specific values from the prompt.

```r
# Agent output (wrong — SKILL.md defaults):
AGE < 18             ~ "<18",
AGE >= 18 & AGE < 65 ~ "18-<65",
AGE >= 65            ~ ">=65"

# Correct (per prompt specification):
AGE < 65             ~ "<65",
AGE >= 65 & AGE <= 80 ~ "65-80",
AGE > 80             ~ ">80"
```

`DOMAIN` not removed from EX before merge — no error in this run but
a latent risk. Raw DTC variables (RFSTDTC, RFENDTC, DMDTC) retained in
output instead of derived date variables. **-5 points total.**

---

## Dimension 4: QC Readiness (5/10)

### REVIEW annotations (3/6)

| Location | Present |
|---|---|
| EOSSTT/disposition | ✅ |
| AGEGR1 cut-points | ✅ (present but not acted upon) |
| Population flags | ✅ |
| SAFFL placebo filter | ❌ — filter is missing, no annotation |
| TRT01PN/TRT01AN coding | ❌ — wrong ARMCD values, no annotation |
| DS record selection rationale | ❌ |

Note: The AGEGR1 `# REVIEW:` annotation correctly signals that cut-points
must come from the ADaM spec, but the agent then used SKILL.md defaults
rather than the prompt values. The annotation fired; the agent did not act.

### Derivation comments (2/4)

Step headers present. No ADaMIG version references. No source variable
citations (e.g. `# TRTSDT: from EX.EXSTDTC`). EOSSTT/DCSREAS derivation
has no comment explaining the completed/discontinued categorisation logic —
the source of the primary correctness failure. **-2 points.**

---

## Dimension 5: Completeness (1/5)

`stopifnot()` assertion present and passes. ✅

Required variable check tests only 8 variables (a subset of the prompt's full
list) — passes but provides minimal coverage. ❌

Labels applied to only 13 of 38 variables — the majority are unlabelled. ❌

**6 required variables missing:**
`TRTSTMF`, `TRTETMF`, `DCSREASP`, `DTHFL`, `DTHDT`, `LSTALVDT`

**Raw DTC variables present instead of derived dates:**
`RFSTDTC`, `RFENDTC`, `DMDTC` carried forward from DM spine; `RFSTDT`,
`RFENDDT` absent. ❌

---

## Three-Way Comparison

| Dimension | Claude Code | GPT-5.3-Codex | Positron |
|---|---|---|---|
| 1. Correctness | 40 | 28 | 18 |
| 2. admiral Idioms | 25 | 18 | 17 |
| 3. CDISC Conformance | 20 | 13 | 7 |
| 4. QC Readiness | 10 | 6 | 5 |
| 5. Completeness | 5 | 2 | 1 |
| **Total** | **100** | **67** | **48** |

---

## Key Failure Analysis

### 1. EOSSTT mapped directly from DSDECOD (Dimensions 1 and 3)

The most consequential error — 196 of 306 subjects affected. The agent
correctly identified DS as the source and applied the right filter
(`DSCAT == "DISPOSITION EVENT"`), but passed `DSDECOD` through directly
to EOSSTT without the required categorisation:

```r
# Wrong — passes reason values directly to status variable
new_vars = exprs(EOSSTT = DSDECOD, DCSREAS = DSDECOD)

# Correct — categorise DSDECOD into COMPLETED/DISCONTINUED for EOSSTT
EOSSTT = if_else(DSDECOD == "COMPLETED", "COMPLETED", "DISCONTINUED")
# and separately map DCSREAS from DSDECOD (decoded reason)
```

Additionally, both EOSSTT and DCSREAS are mapped to the same source variable,
making them identical — which is never correct.

### 2. AGEGR1 cut-points from SKILL.md defaults ignored prompt specification

The `# REVIEW:` annotation correctly fired but the agent used SKILL.md default
cut-points rather than the study-specific values in the prompt. All 306
subjects have wrong AGEGR1 values. This suggests the agent weighted its
training data (pharmaverse ADSL vignette cut-points) over the prompt
instruction when both were present.

### 3. TRTSTMF/TRTETMF: flag_imputation set but flags not retained

`flag_imputation = "auto"` is correctly specified — an improvement over the
GPT run — but the generated flag variables (EXSTTMF, EXENTMF) are never
included in `new_vars` when merging into ADSL. Setting the argument without
capturing the output provides no traceability benefit.

### 4. TRT01PN/TRT01AN coded against non-existent ARMCD values

ARMCD values `"Pbo"`, `"ARM A"`, `"ARM B"`, `"ARM C"` do not exist in the
pharmaversesdtm DM domain. Actual values are `"Xan_Hi"`, `"Xan_Lo"`,
`"Placebo"`, `"Scrnfail"`. All TRT01PN and TRT01AN values will be `NA`.

### 5. Placebo filter absent from treatment date derivations

The SAFFL derivation condition uses only `!is.na(EXSTDTC)` — placebo subjects
(EXDOSE == 0) will only be included if they happen to have a non-missing
EXSTDTC, which may not be reliable without the explicit placebo EXTRT check.

---

## Recommended Skill Updates

Based on this run, the following additions to the skill are recommended:

1. **SKILL.md Step 7** — add explicit code example showing the
   `DSDECOD → "COMPLETED"/"DISCONTINUED"` categorisation for EOSSTT; this is
   the most consequential failure across both non-Claude agents tested
2. **SKILL.md Step 3** — strengthen the instruction to include TRTSTMF/TRTETMF
   in `new_vars` when merging treatment datetimes; setting `flag_imputation`
   without retaining the flags is a common partial-compliance pattern
3. **SKILL.md Step 8** — add explicit instruction that AGEGR1 cut-points must
   be taken from the prompt/spec, overriding any SKILL.md examples; the
   example cut-points in the skill should be clearly labelled as placeholders
4. **admiral-functions.md** — add note that `flag_imputation = "auto"` requires
   the generated flag variables to be explicitly named in `new_vars` to appear
   in the output dataset
5. **adsl-conventions.md** — strengthen the EOSSTT entry: `"COMPLETED"` or
   `"DISCONTINUED"` only — never a reason value from DSDECOD
