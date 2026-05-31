# ADAE Conventions Reference

CDISC ADaM conventions for ADAE dataset construction. This reference covers
dataset structure, variable requirements, naming rules, controlled terminology,
flag conventions, and define.xml metadata expectations. It is a compact,
programming-facing reference — not a substitute for ADaMIG v1.3 or the OCCDS
guidance.

---

## Structure Rule: One Record Per AE Per Subject

ADAE contains one record per adverse event per subject (one record per unique
USUBJID × AESEQ combination). This is the defining structural property of the
OCCDS (Occurrence Data Structure) dataset type.

Verify programmatically before delivery:

```r
stopifnot(nrow(adae) >= nrow(ae))   # no AE records lost in derivation
stopifnot(!any(duplicated(adae[, c("STUDYID", "USUBJID", "AESEQ")])))
```

Unlike ADSL (one row per subject), ADAE rows are subject to record-level
derivations (TRTEMFL, AESEV, AEREL) rather than subject-level aggregations.

---

## Required Variables

Variables that must be included in every ADAE — the subset carried from AE SDTM
or derived during the workflow:

| Variable | Type | Source | Notes |
|---|---|---|---|
| STUDYID | Char | AE / ADSL | Study identifier |
| USUBJID | Char | AE | Unique subject identifier |
| AESEQ | Num | AE | Sequence number within subject — primary key with USUBJID |
| AETERM | Char | AE | Original reported AE term |
| AEDECOD | Char | AE | MedDRA preferred term (coded) |
| AEBODSYS | Char | AE | MedDRA system organ class |
| AESTDTC | Char | AE | AE start date/time (SDTM DTC) |
| ASTDT | Num | Derived | Analysis start date (Date class) |
| ASTDTF | Char | Derived | Imputation flag for ASTDT |
| AENDT | Num | Derived | Analysis end date (Date class) |
| AENDTF | Char | Derived | Imputation flag for AENDT |
| ASTDY | Num | Derived | Study day of AE onset |
| AENDY | Num | Derived | Study day of AE resolution |
| AESEV | Char | AE | Severity (MILD / MODERATE / SEVERE) |
| AESER | Char | AE → recoded | Serious AE flag (`"Y"` or `NA`) |
| TRTEMFL | Char | Derived | Treatment-emergent flag (`"Y"` or `NA`) |
| TRTSDT | Num | ADSL | First dose date (from ADSL merge) |
| TRTEDT | Num | ADSL | Last dose date (from ADSL merge) |
| TRT01P | Char | ADSL | Planned treatment label |
| TRT01A | Char | ADSL | Actual treatment label |

---

## Conditionally Required Variables

| Variable | Required when | Notes |
|---|---|---|
| AETOXGR | NCI CTCAE grading in scope | CTCAE grade 1–5 |
| AESDTH | Death from AE is a safety endpoint | `"Y"` or `NA` |
| AEOUT | Outcome in scope | CDISC CT values |
| AEREL | Causality assessment collected | Relationship to study treatment |
| AEACN | Action taken in scope | Action taken with study treatment |
| PREFL | Medical history comparison required | Pre-existing condition flag |
| TRT01PN | Numeric companion to TRT01P | Required if used in subgroup analysis |
| TRT01AN | Numeric companion to TRT01A | Required if used in subgroup analysis |

---

## Flag Value Convention

**Critical:** CDISC ADaM convention for all flag variables is `"Y"` or `NA`.
Never use `"N"`.

```r
# CORRECT — "Y" or NA
mutate(TRTEMFL = if_else(is_emergent, "Y", NA_character_))
mutate(AESER   = if_else(AESER == "Y", "Y", NA_character_))
mutate(AESDTH  = if_else(AESDTH == "Y", "Y", NA_character_))
mutate(PREFL   = if_else(has_mh_match, "Y", NA_character_))

# WRONG — violates CDISC ADaM convention
mutate(TRTEMFL = if_else(is_emergent, "Y", "N"))
```

**Note on AE SDTM source:** AE.AESER in SDTM is `"Y"` or `""` (blank), not
`"Y"` or `"N"`. When recoding to ADaM convention, test `== "Y"`, not `!= "N"`.

---

## Treatment-Emergent Adverse Event (TEAE) Definition

An AE is treatment-emergent when:

1. AE onset date (ASTDT) ≥ first dose date (TRTSDT), **and**
2. AE onset date (ASTDT) ≤ last dose date (TRTEDT) + protocol-defined
   post-treatment window (`end_window` days)

The post-treatment window is **always protocol-specific** and must be confirmed
from the SAP. Common values:

| Window | Typical context |
|---|---|
| 0 days | On-treatment only; AE must start on or before TRTEDT |
| 7 days | Short-acting drugs; some oncology protocols |
| 28 days | Many general medicine protocols |
| 30 days | SAE-specific window in some submissions |
| Until end of follow-up | Long-term safety studies |

Always annotate `end_window` with `# REVIEW:` and the SAP reference.

---

## Severity Variables

### AESEV — Verbatim Severity

Carried from AE.AESEV. CDISC CT values (Codelist C66769):

| Value | Meaning |
|---|---|
| `"MILD"` | Awareness of sign or symptom, but easily tolerated |
| `"MODERATE"` | Enough discomfort to cause interference with usual activity |
| `"SEVERE"` | Incapacitating; prevents usual activity |
| `"LIFE THREATENING"` | Some studies add this; check CT version |

### AESEVN — Numeric Severity (derived)

Numeric companion for sorting and analysis. Derive with an explicit `case_when()`
mapped against the ADaM spec:

```r
AESEVN = case_when(
  AESEV == "MILD"     ~ 1L,
  AESEV == "MODERATE" ~ 2L,
  AESEV == "SEVERE"   ~ 3L
)
```

Cut-points must come from the ADaM spec. Add `# REVIEW:` if the spec includes
non-standard values.

### AETOXGR — NCI CTCAE Grade

Integer 1–5 carried from AE.AETOXGR when NCI CTCAE grading is used. Not
present in `pharmaversesdtm::ae` — see DESIGN.md for handling.

---

## Causality and Outcome Variables

### AEREL — Relationship to Study Treatment

Carried from AE.AEREL. Common CDISC CT values (Codelist C66726):

| Value |
|---|
| `"RELATED"` |
| `"NOT RELATED"` |
| `"POSSIBLY RELATED"` |

**Always review:** some studies use `"PROBABLE"`, `"POSSIBLE"`, `"UNLIKELY"` —
confirm the controlled terminology version used for the study.

### AERELN — Numeric Causality

Numeric companion for AEREL, derived via `case_when()`. Values must be
spec-defined — never hardcode without a `# REVIEW:` annotation.

### AEOUT — Outcome

Carried from AE.AEOUT. Common CDISC CT values (Codelist C66727):

| Value |
|---|
| `"RECOVERED/RESOLVED"` |
| `"RECOVERING/RESOLVING"` |
| `"NOT RECOVERED/NOT RESOLVED"` |
| `"RECOVERED/RESOLVED WITH SEQUELAE"` |
| `"FATAL"` |
| `"UNKNOWN"` |

### AEACN — Action Taken with Study Treatment

Carried from AE.AEACN. Common CDISC CT values (Codelist C66728):

| Value |
|---|
| `"DOSE REDUCED"` |
| `"DRUG INTERRUPTED"` |
| `"DRUG WITHDRAWN"` |
| `"NOT APPLICABLE"` |
| `"NONE"` |
| `"DOSE INCREASED"` |
| `"DOSE NOT CHANGED"` |
| `"UNKNOWN"` |

---

## Date Variable Conventions

### Types

| Admiral type | R class | XPT export | When to use |
|---|---|---|---|
| Date (`_DT`) | `Date` | Numeric (SAS date) | Date only — no time component |
| Datetime (`_DTM`) | `POSIXct` | Numeric (SAS datetime) | When time component is present in SDTM |

### Imputation Rules

| Variable type | Imputation rule | admiral argument |
|---|---|---|
| Start dates (ASTDT) | Impute to **earliest** possible date | `date_imputation = "first"` |
| End dates (AENDT) | Impute to **latest** possible date | `date_imputation = "last"` |
| Time (when absent) | Start: `"00:00:00"`, End: `"23:59:59"` | `time_imputation = "first"` / `"last"` |

Always retain imputation flag variables (ASTDTF, AENDTF). Never suppress them.

### Study Day Convention

CDISC study day: the reference date is Day 1. There is no Day 0. ASTDY and
AENDY are computed relative to TRTSDT from ADSL.

Always use `derive_vars_dy()`. Never compute manually.

---

## Dataset Attributes

### Dataset-Level

| Attribute | Value |
|---|---|
| Dataset label | `"Adverse Events Analysis Dataset"` |
| Dataset name | `ADAE` |
| One record per | Adverse event per subject (USUBJID × AESEQ) |
| Dataset type | OCCDS (Occurrence Data Structure) |

Apply in R using `{xportr}` with `{metacore}` for spec-driven attribute
application in submission context:

```r
adae |>
  xportr_label(metacore_obj, domain = "ADAE") |>
  xportr_type(metacore_obj, domain = "ADAE") |>
  xportr_length(metacore_obj, domain = "ADAE") |>
  xportr_order(metacore_obj, domain = "ADAE") |>
  xportr_write("adae.xpt", label = "Adverse Events Analysis Dataset")
```

### Variable-Level Attributes

Every variable must have:
- **Label** — from the ADaM spec; max 40 characters
- **Type** — character or numeric
- **Length** — from the ADaM spec

Apply labels as a final step. Derivation steps may strip attributes.

---

## Variable Order Convention

ADAE variable order in the XPT file should follow the ADaM spec column order.
Use `xportr_order()` to enforce this programmatically.

Standard grouping convention:

1. Identifiers (STUDYID, USUBJID, AESEQ)
2. ADSL variables merged in (TRTSDT, TRTEDT, TRT01P, TRT01PN, TRT01A, TRT01AN,
   population flags)
3. Source AE variables (AETERM, AEDECOD, AEBODSYS, AESTDTC, AEENDTC, …)
4. Analysis dates and study days (ASTDT, ASTDTF, AENDT, AENDTF, ASTDY, AENDY)
5. Analysis flags (TRTEMFL, PREFL, AMAXSEVFL)
6. Severity and grade (AESEV, AESEVN, AETOXGR)
7. Seriousness and outcome (AESER, AESDTH, AEOUT)
8. Causality and action (AEREL, AERELN, AEACN)
9. Grouping/SMQ flags

---

## Common Reviewer Findings (to Avoid)

| Finding | Rule violated | Fix |
|---|---|---|
| `TRTEMFL = "N"` present | Flag convention: `"Y"` or `NA` only | Replace `"N"` with `NA_character_` |
| `AESER = "N"` present | Same flag convention | Recode AE.AESER blank to `NA_character_` |
| ASTDTF / AENDTF absent from dataset | ADaM traceability requirement | Retain imputation flags |
| ASTDY computed as `ASTDT - TRTSDT + 1` | Study day offset; misses Day 1 convention | Use `derive_vars_dy()` |
| `end_window` in TRTEMFL not from SAP | Protocol-specific parameter silently applied | Add `# REVIEW:` and confirm with statistician |
| All ADSL variables merged onto ADAE | Dataset inflation, variable conflicts | Merge only spec-required ADSL variables |
| AEDECOD / AEBODSYS absent from output | Required OCCDS variables | Carry through from AE source |
| Variables not in spec order in XPT | Submission expectation | Apply `xportr_order()` |
| AESEQ duplicated within USUBJID | Key constraint violated | Investigate source AE AESEQ |
