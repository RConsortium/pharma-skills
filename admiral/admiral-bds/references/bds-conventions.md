# BDS Conventions Reference

CDISC ADaM conventions for BDS (Basic Data Structure) dataset construction.
Covers record structure, required variables, timing variables, analysis
values, baseline and change derivations, and dataset attributes. Programming-
facing compact reference — not a substitute for ADaMIG v1.3 BDS chapter.

---

## BDS Record Structure

A BDS dataset contains one record per subject per parameter per timepoint (per
analysis observation). The granularity is finer than ADSL, which has one record
per subject.

**Structural uniqueness key (typical):**

```
USUBJID + PARAMCD + AVISITN
```

Adjust per spec. Studies with positional measures (e.g. vital signs by VSPOS),
timepoint within visit (ATPTN), or method (e.g. supine vs. standing BP) require
additional key variables.

**Synthetic rows** (DTYPE != NA) are permitted duplicates by design — they are
excluded from uniqueness assertions and from change/percentage calculations.

---

## Required Variables

All BDS datasets must include:

| Variable | Type | Description |
|---|---|---|
| STUDYID | Char | Study identifier |
| USUBJID | Char | Unique subject identifier |
| PARAMCD | Char | Parameter code — short, from CT or sponsor-defined |
| PARAM | Char | Parameter description — full text, often includes units |
| PARAMN | Num | Parameter numeric code |
| ADT | Num | Analysis date (Date class) |
| AVISIT | Char | Analysis visit name |
| AVISITN | Num | Analysis visit number |
| AVAL | Num | Analysis value (numeric) |

When analysis values are character (e.g. categorical responses), use `AVALC`
instead of or alongside `AVAL`.

---

## Timing Variables

### ADT — Analysis Date

Derived from the SDTM `--DTC` variable using `derive_vars_dt()`. Never use
`as.Date()` directly on `--DTC`.

| Suffix | Variable | Meaning |
|---|---|---|
| `ADT` | Analysis date | Numeric (SAS date) |
| `ADTF` | Analysis date imputation flag | `"D"` = day, `"M"` = month/day, `"Y"` = year/month/day imputed |
| `ADY` | Analysis study day | Relative to TRTSDT; Day 1 = TRTSDT |

ADY = ADT - TRTSDT + 1 if ADT >= TRTSDT, else ADT - TRTSDT (no Day 0).
Always use `derive_vars_dy()` — never compute manually.

### AVISIT / AVISITN

Analysis visit name and number. **Not** the same as SDTM VISIT/VISITNUM:

| SDTM | ADaM |
|---|---|
| VISIT | AVISIT — may group multiple SDTM visits |
| VISITNUM | AVISITN — spec-defined numeric, not SDTM passthrough |

Unscheduled visits are typically coded as `AVISIT = "Unscheduled"` with
`AVISITN = 99` (or similar) unless the spec groups them into a specific window.

### ATPTN / ATPT — Analysis Timepoint

Used when multiple readings are taken within a single visit (e.g. PK sampling,
triplicate ECG, hourly BP). ATPT is the character description; ATPTN is the
numeric code. Derive from SDTM `--TPT` / `--TPTNUM`.

---

## Analysis Value Variables

| Variable | Type | When to use |
|---|---|---|
| `AVAL` | Num | Always for numeric analysis values |
| `AVALC` | Char | Character result — required when the parameter value is non-numeric or both forms are needed |
| `AVALU` | Char | Analysis value units — carry from `--STRESU` |

For parameters with both numeric and character forms, populate both `AVAL` and
`AVALC`. Neither should be derived from the other.

---

## Baseline Variables

### ABLFL — Baseline Flag

Flags exactly one record per USUBJID + PARAMCD (+ BASETYPE if used) as
baseline. Convention: `"Y"` or `NA`.

Baseline is typically the **last non-missing, non-excluded record on or before
TRTSDT**. Protocol may define alternative windows — always confirm from the
ADaM spec.

Use `restrict_derivation()` + `derive_var_extreme_flag()`. Never use `mutate()`
with manual `if_else()` for baseline flagging.

### BASETYPE — Baseline Type

Used when more than one baseline is needed (e.g. last pre-dose AND last
pre-treatment start). If only one baseline window is defined, `BASETYPE` is
omitted.

```r
# When BASETYPE is required, add it before ABLFL derivation
advs <- advs |>
  mutate(BASETYPE = "LAST OBSERVATION BEFORE TREATMENT")
```

### BASE / BASEC — Baseline Value

The analysis value at the baseline record. Populated on all post-baseline rows,
`NA` on pre-baseline rows that are not the baseline record itself.

| Variable | Source | Use |
|---|---|---|
| `BASE` | `AVAL` where `ABLFL == "Y"` | Numeric baseline |
| `BASEC` | `AVALC` where `ABLFL == "Y"` | Character baseline |

Derive with `derive_var_base()` — this correctly propagates baseline values
across all records for the same subject-parameter combination.

---

## Change from Baseline Variables

| Variable | Formula | Notes |
|---|---|---|
| `CHG` | `AVAL - BASE` | `NA` for baseline record and when BASE is missing |
| `PCHG` | `CHG / BASE * 100` | `NA` when BASE = 0 or BASE is missing |

Derive after BASE is populated:
```r
dataset |>
  derive_var_chg() |>
  derive_var_pchg()
```

**CHG for categorical parameters:** Omit CHG/PCHG for parameters where AVAL is
not meaningful as a numeric change (e.g. ANRIND, DTYPE categories).

---

## Analysis Flag Variables

### ANL01FL — Analysis Record Flag

Flags records included in the primary analysis. Definition is protocol-specific:
typically on-treatment non-baseline records, or records within a protocol-defined
window. Must be annotated with `# REVIEW:`.

Convention: `"Y"` or `NA`.

### DTYPE — Duplicate Type

Identifies synthetic or derived records added to the dataset that do not
correspond directly to a single SDTM observation:

| DTYPE value | Meaning |
|---|---|
| `"AVERAGE"` | Record is an average of multiple source records (e.g. triplicate BP) |
| `"LOCF"` | Last observation carried forward (avoid unless specified in SAP) |
| `"BASELINE"` | Synthetic baseline record where no actual baseline observation exists |

DTYPE rows are excluded from uniqueness checks and from CHG/PCHG derivations.

---

## ADLB-Specific Variables

### Normal Range

| Variable | Source | Description |
|---|---|---|
| `ANRLO` | LB.LBSTNRLO | Normal range low limit |
| `ANRHI` | LB.LBSTNRHI | Normal range high limit |
| `ANRIND` | Derived | Analysis reference range indicator |
| `BNRIND` | ANRIND at baseline | Baseline reference range indicator |

`ANRIND` controlled terminology (CDISC CT Codelist C78736):

| Value | Meaning |
|---|---|
| `"NORMAL"` | ANRLO ≤ AVAL ≤ ANRHI |
| `"LOW"` | AVAL < ANRLO |
| `"HIGH"` | AVAL > ANRHI |
| `"LOW LOW"` | Below critical low threshold (if defined) |
| `"HIGH HIGH"` | Above critical high threshold (if defined) |

### Toxicity Grades (CTCAE)

| Variable | Source | Description |
|---|---|---|
| `ATOXGR` | LB.LBTOXGR | Analysis toxicity grade |
| `BTOXGR` | ATOXGR at baseline | Baseline toxicity grade |

Derive BTOXGR using `derive_var_base()` the same way as BNRIND.

---

## ADVS-Specific Variables

### Position (VSPOS)

For vital signs recorded with positional context (supine, standing, sitting),
VSPOS from SDTM is typically carried into ADVS and included in the uniqueness
key.

### Triplicate/Duplicate Records

When multiple readings are taken per visit per subject (e.g. triplicate systolic
BP), three approaches are valid depending on the SAP:

1. **Retain all, flag one with ANL01FL** — keeps all records, uses flag to identify
   which record enters analysis
2. **Average and add DTYPE = "AVERAGE"** — adds a synthetic record with the mean
   value; original records are retained as non-flagged rows
3. **Drop duplicates** — rarely appropriate; confirm with statistician

---

## Dataset Attributes

### Dataset-Level

| Attribute | ADVS | ADLB |
|---|---|---|
| Dataset label | `"Vital Signs Analysis Dataset"` | `"Laboratory Data Analysis Dataset"` |
| One record per | Subject / param / visit (± position) | Subject / param / visit |

### Variable Order Convention

Recommended variable order (aligned with ADaMIG BDS appendix):

1. Identifier variables (STUDYID, USUBJID, SUBJID, SITEID)
2. Treatment variables (TRT01P, TRT01A, etc. from ADSL)
3. Population flags (SAFFL, ITTFL, etc. from ADSL)
4. Parameter variables (PARAM, PARAMCD, PARAMN, PARCAT1, etc.)
5. Timing variables (ADT, ADTF, ADY, AVISIT, AVISITN, ATPT, ATPTN)
6. Analysis values (AVAL, AVALC, AVALU)
7. Baseline variables (ABLFL, BASE, BASEC, BASETYPE)
8. Change variables (CHG, PCHG)
9. Reference range / normal range (ANRLO, ANRHI, ANRIND, BNRIND)
10. Analysis flags (ANL01FL, ANL02FL, etc.)
11. SDTM reference variables (VISITNUM, VSTESTCD, etc.)
