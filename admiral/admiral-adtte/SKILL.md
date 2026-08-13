---
name: admiral-adtte
description: >
  Derives an ADaM Time-to-Event Analysis Dataset (ADTTE) using the {admiral}
  R package. Use when a user needs to create ADTTE from SDTM event domains
  (AE, DS, CE) and ADSL, define event and censoring conditions, derive AVAL
  in days, and generate QC-ready R code following CDISC ADaM BDS-TTE
  conventions. Requires SDTM source domains, a completed ADSL, and an ADaM
  ADTTE specification that defines the event and censoring rules.
license: MIT
metadata:
  author: Navitas Data Sciences
  version: "0.1"
  pharmaverse: "true"
  parent: admiral
compatibility: >
  Requires R with admiral, dplyr, lubridate, and pharmaversesdtm installed.
  Requires a completed ADSL dataset with TRTSDT and TRTEDT. Designed for use
  in a GxP-compliant environment with access to SDTM event domain data and an
  ADaM ADTTE specification defining event and censoring rules.
---

# admiral-adtte

> Shared conventions (library setup, pipe style, date rules, flag convention,
> `# REVIEW:` annotations, `stopifnot()` patterns) are defined in the parent
> [`../SKILL.md`](../SKILL.md). The workflow below is ADTTE-specific.

Derives a CDISC-conformant ADTTE time-to-event dataset using {admiral}. Outputs
executable, QC-ready R code with event and censoring logic fully traceable to
the ADaM specification.

The primary design challenge in ADTTE is the **event and censoring hierarchy**:
the correct event date, censoring date, and censoring reason depend entirely on
the protocol-specified rules. These must be defined as named `event_source()` and
`censor_source()` objects — never as inline expressions — so they can be
reviewed, tested, and reused independently.

---

## Inputs

Before generating code, confirm the following are available or explicitly noted
as absent:

| Input | Required | Notes |
|---|---|---|
| AE / DS / CE | Yes | Event source domain(s); which domain depends on the endpoint (AE for safety TTE, DS for EFS/PFS, CE for clinical events) |
| ADSL | Yes | Provides TRTSDT (start date), TRTEDT (censoring date fallback), population flags |
| ADaM ADTTE spec | Yes | Event definition, censoring hierarchy, PARAMCD/PARAM, CNSDTDSC controlled terminology |
| Study context | Yes | Post-treatment window for safety TTE, censoring date priority order, analysis population |

If ADSL is absent, stop and request it. If the event source domain is absent,
stop and request it — do not substitute synthetic dates.

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
library(pharmaverseadam)

# Load event source domain(s) — substitute with the domain(s) relevant to the endpoint
ae   <- pharmaversesdtm::ae
adsl <- pharmaverseadam::adsl  # assumed derived upstream

stopifnot(nrow(ae) > 0)
```

### Step 2 — DOMAIN removal

Remove DOMAIN from every event source domain **before** passing it to
`derive_param_tte()`. admiral errors when DOMAIN exists in both the dataset
and a `source_datasets` entry.

```r
ae <- ae |> select(-DOMAIN)
# Repeat for every source domain used in event_source() or censor_source() calls
```

### Step 3 — Merge ADSL backbone variables

Bring required ADSL variables into the event dataset. At minimum: TRTSDT
(start date for ADTTE), TRTEDT (fallback censoring date), and population flags.
Always use `derive_vars_merged()` — not `left_join()`.

```r
# REVIEW: Confirm which ADSL variables are required per the ADTTE spec.
#   TRTSDT is the conventional STARTDT for most TTE parameters. If the endpoint
#   uses randomization date instead, use RANDDT. Add population flags as needed.
adtte <- ae |>
  derive_vars_merged(
    dataset_add = adsl,
    by_vars     = exprs(STUDYID, USUBJID),
    new_vars    = exprs(TRTSDT, TRTEDT, TRT01P, TRT01PN, TRT01A, TRT01AN,
                        SAFFL, ITTFL)
  )
```

### Step 4 — Derive event dates on source domain

Convert DTC dates in the source domain to analysis dates using `derive_vars_dt()`
before referencing them in `event_source()` or `censor_source()`. Never use
`as.Date()` on DTC variables.

```r
adtte <- adtte |>
  derive_vars_dt(
    dtc             = AESTDTC,
    new_vars_prefix = "AST",
    date_imputation = "first",
    flag_imputation = "auto"
  )
```

### Step 5 — Define event source objects

Define event conditions as named `event_source()` objects. **Never define them
inline** inside `derive_param_tte()` — named objects are independently testable
and reviewable.

```r
# REVIEW: The event filter below (AESER == "Y") is the most common definition
#   for a time-to-first-serious-AE endpoint. Confirm the exact event definition
#   from the ADaM ADTTE spec and SAP:
#   - Which AE terms or flags qualify? (AESER, AETOXGR >= 3, specific AEDECOD terms)
#   - Does the event require onset during treatment only, or ever?
#   - What is the event date — onset (ASTDT) or report date?
ttae_event <- event_source(
  dataset_name  = "ae",
  filter        = AESER == "Y",          # PLACEHOLDER — confirm from SAP
  date          = ASTDT,
  set_values_to = exprs(
    EVNTDESC = "Serious adverse event",
    SRCDOM   = "AE",
    SRCVAR   = "AESTDTC",
    SRCSEQ   = AESEQ
  )
)
```

### Step 6 — Define censoring source objects

Define censoring conditions as named `censor_source()` objects in priority order
(first entry wins when multiple dates are available for a subject).

```r
# REVIEW: The censoring date below (TRTEDT + 30) is a common proxy for
#   "30 days post last dose" TTE endpoints. Confirm the censoring hierarchy
#   from the ADaM ADTTE spec and SAP:
#   - What is the primary censoring date? (last contact, last dose + window, LSDT)
#   - Is the post-treatment window 30, 28, or another number of days?
#   - What is CNSDTDSC for each censoring type? Confirm against define.xml CT.
ttae_censor <- censor_source(
  dataset_name  = "adsl",
  date          = TRTEDT + 30,           # PLACEHOLDER — confirm from SAP
  set_values_to = exprs(
    EVNTDESC = NA_character_,
    # REVIEW: CNSDTDSC must match define.xml controlled terminology exactly.
    #   Common values: "Last dose date + 30 days", "Last known alive date",
    #   "End of study". Confirm the full list and exact strings from the spec.
    CNSDTDSC = "Last dose date + 30 days",   # PLACEHOLDER — confirm CT from spec
    SRCDOM   = "ADSL",
    SRCVAR   = "TRTEDT"
  )
)
```

### Step 7 — Derive ADTTE parameter

Call `derive_param_tte()` with the named source objects. Pass all source domains
referenced by event or censor sources in `source_datasets`.

```r
# REVIEW: PARAMCD and PARAM must match the ADaM ADTTE spec exactly.
adtte <- derive_param_tte(
  dataset_adsl      = adsl,
  source_datasets   = list(adsl = adsl, ae = ae),
  start_date        = TRTSDT,
  event_conditions  = list(ttae_event),
  censor_conditions = list(ttae_censor),
  set_values_to     = exprs(
    PARAMCD = "TTAE",
    PARAM   = "Time to First Serious Adverse Event"
  )
)
```

### Step 8 — Derive AVAL (duration in days)

AVAL is the time from STARTDT to the event or censoring date (ADT) in days.
Use `derive_vars_duration()`. CDISC convention requires AVAL ≥ 1: a subject
who events on Day 1 has AVAL = 1, not 0 (`add_one = TRUE`).

```r
adtte <- adtte |>
  derive_vars_duration(
    new_var      = AVAL,
    start_date   = STARTDT,
    end_date     = ADT,
    out_unit     = "days",
    add_one      = TRUE,    # CDISC: AVAL = 1 when event/censoring on start date
    trunc_out    = FALSE
  )
```

### Step 9 — Verification and structural assertions

Print event and censoring counts and assert structural requirements before
finalising the dataset.

```r
# Print event/censor summary — inspect for implausible counts before proceeding
event_summary <- adtte |>
  count(PARAMCD, CNSR)
print(event_summary)

# CNSR must be integer 0 (event) or 1 (censored) — never logical or character
stopifnot(all(adtte$CNSR %in% c(0L, 1L)))

# AVAL must be strictly positive — CDISC requires >= 1 day
stopifnot(all(adtte$AVAL >= 1, na.rm = TRUE))

# CNSDTDSC must be non-missing for every censored subject
stopifnot(!any(adtte$CNSR == 1L & is.na(adtte$CNSDTDSC)))

# EVNTDESC must be non-missing for every subject with an event
stopifnot(!any(adtte$CNSR == 0L & is.na(adtte$EVNTDESC)))
```

### Step 10 — Final checks

```r
# Uniqueness: one record per subject per PARAMCD
dup_check <- adtte |>
  count(STUDYID, USUBJID, PARAMCD) |>
  filter(n > 1)
if (nrow(dup_check) > 0) {
  stop("Duplicate subject-PARAMCD records found:\n",
       paste(paste(dup_check$USUBJID, dup_check$PARAMCD), collapse = "\n"))
}

# Required variable presence check
required_vars <- c(
  "STUDYID", "USUBJID", "PARAMCD", "PARAM",
  "AVAL", "CNSR", "CNSDTDSC", "EVNTDESC",
  "ADT", "STARTDT"
)
missing_vars <- setdiff(required_vars, names(adtte))
if (length(missing_vars) > 0) {
  stop("Missing required ADTTE variables: ", paste(missing_vars, collapse = ", "))
}
```

---

## Multiple TTE parameters

When the spec requires more than one TTE parameter (e.g., TTAE and TTFAE —
time-to-first AE, any grade), repeat Steps 5–7 for each parameter with its
own named source objects. Keep naming consistent: `{param}_event` and
`{param}_censor`.

```r
# Example: adding a second parameter (time to any AE, grade ≥ 3)
ttae3_event <- event_source(
  dataset_name  = "ae",
  filter        = AETOXGR >= 3,         # REVIEW — confirm grading threshold from SAP
  date          = ASTDT,
  set_values_to = exprs(
    EVNTDESC = "Grade 3+ adverse event",
    SRCDOM = "AE", SRCVAR = "AESTDTC", SRCSEQ = AESEQ
  )
)

adtte <- adtte |>
  derive_param_tte(
    dataset_adsl      = adsl,
    source_datasets   = list(adsl = adsl, ae = ae),
    start_date        = TRTSDT,
    event_conditions  = list(ttae3_event),
    censor_conditions = list(ttae_censor),   # reuse common censoring rule
    set_values_to     = exprs(
      PARAMCD = "TTAE3",
      PARAM   = "Time to First Grade 3+ Adverse Event"
    )
  )
```

---

## Common errors to avoid

- **Using `left_join()` for the ADSL merge** instead of `derive_vars_merged()` —
  `left_join()` does not apply admiral's key-variable validation and can silently
  produce a many-to-many join if ADSL has unexpected duplicates
- **Defining event and censor sources inline** inside `derive_param_tte()` —
  inline definitions cannot be unit-tested or reused across parameters; always
  define as named objects
- **Not removing DOMAIN from source domains** before `derive_param_tte()` —
  causes variable conflict errors; remove in Step 2, before any derivation
- **Hardcoding the censoring date** (e.g., `TRTEDT + 30`) without a `# REVIEW:`
  comment — the censoring window is protocol-specific and must come from the SAP
- **Using `CNSR = TRUE/FALSE`** instead of `CNSR = 0L/1L` — CDISC requires
  integer; logical values will fail downstream QC checks and define.xml validation
- **AVAL = 0 for same-day events** — `add_one = TRUE` in `derive_vars_duration()`
  is required to meet the CDISC ≥1 day constraint; never omit it
- **Hardcoding CNSDTDSC text** without a `# REVIEW:` comment — the exact string
  must match define.xml controlled terminology; a mismatch causes submission review findings
- **Not printing event/censor counts** — if all subjects are censored due to
  a misconfigured date expression, the dataset looks structurally valid but the
  analysis is wrong; always print counts before finalising
- **Using `as.Date()` on DTC variables** in event source filters — use
  `derive_vars_dt()` first; `as.Date()` silently returns `NA` for partial dates

---

## Output checklist

Before returning code, verify:

- [ ] DOMAIN removed from every source domain before `derive_param_tte()` (Step 2)
- [ ] ADSL merged with `derive_vars_merged()`, not `left_join()` (Step 3)
- [ ] Event date derived with `derive_vars_dt()` before use in `event_source()` (Step 4)
- [ ] Event and censor conditions defined as named objects, not inline (Steps 5–6)
- [ ] `# REVIEW:` at event filter condition (Step 5)
- [ ] `# REVIEW:` at censoring date expression (Step 6)
- [ ] `# REVIEW:` at CNSDTDSC text (Step 6)
- [ ] `# REVIEW:` at PARAMCD/PARAM (Step 7)
- [ ] AVAL derived with `derive_vars_duration()` with `add_one = TRUE` (Step 8)
- [ ] Event/censor counts printed to console (Step 9)
- [ ] `stopifnot(all(CNSR %in% c(0L, 1L)))` present (Step 9)
- [ ] `stopifnot(all(AVAL >= 1))` present (Step 9)
- [ ] CNSDTDSC non-missing where CNSR == 1 assertion present (Step 9)
- [ ] EVNTDESC non-missing where CNSR == 0 assertion present (Step 9)
- [ ] Uniqueness assertion per USUBJID × PARAMCD (Step 10)
- [ ] Required variable presence check (Step 10)
