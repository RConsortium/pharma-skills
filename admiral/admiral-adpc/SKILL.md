---
name: admiral-adpc
description: >
  Derives an ADaM Pharmacokinetic Concentrations Analysis Dataset (ADPC, also
  called ADNCA when used as non-compartmental analysis input) using the
  {admiral} R package. Use when a user needs to create ADPC from SDTM PC and
  EX, derive nominal and actual relative time variables (NFRLT, AFRLT, NRRLT,
  ARRLT), expand dosing records, handle BLQ concentrations, or prepare PK
  concentration data for NCA tools such as PKNCA. Requires SDTM PC and EX, a
  completed ADSL, and an ADaM ADPC specification.
license: MIT
metadata:
  author: Navitas Data Sciences
  version: "0.1"
  pharmaverse: "true"
  parent: admiral
compatibility: >
  Requires R with admiral (>= 1.4), dplyr, lubridate, and pharmaversesdtm
  installed. Requires a completed ADSL dataset with TRTSDT and TRTSDTM.
  Designed for use in a GxP-compliant environment with access to SDTM PC and
  EX data and an ADaM ADPC specification.
---

# admiral-adpc

> Shared conventions (library setup, pipe style, date rules, flag convention,
> `# REVIEW:` annotations, `stopifnot()` patterns) are defined in the parent
> [`../SKILL.md`](../SKILL.md). The workflow below is ADPC-specific.

Derives a CDISC-conformant ADPC (ADNCA) dataset using {admiral}. Outputs
executable, QC-ready R code that follows admiral's `ad_adpc.R` template and the
`pk_adnca` vignette, and produces analysis-ready input for NCA tools.

The primary design challenge in ADPC is **dose-relative time**. Every
concentration needs its time from the first dose and from the most recent dose,
both nominal (planned) and actual. Getting the "most recent dose" right on
multiple-dose data requires matching each sample to dosing records by
datetime — never by row order. Use admiral's join functions for this; never
`lag()`, `lead()`, or `difftime()`.

This skill builds ADPC only. Computing NCA parameters (Cmax, AUC, half-life)
and building ADPP is the job of {PKNCA} or {aNCA}; see
[`references/pknca-handoff.md`](references/pknca-handoff.md).

---

## Inputs

Before generating code, confirm the following are available or explicitly noted
as absent:

| Input | Required | Notes |
|---|---|---|
| PC | Yes | Concentrations: PCTESTCD, PCSPEC, PCSTRESN/PCSTRESC, PCLLOQ, PCDTC, PCTPT, VISITDY |
| EX | Yes | Dosing: EXDOSE, EXDOSU, EXDOSFRQ, EXSTDTC, EXENDTC, VISITDY |
| ADSL | Yes | TRTSDT, TRTSDTM, TRT01P, TRT01A, population flags |
| VS | Optional | Baseline height and weight for covariates (HTBL, WTBL, BMIBL) |
| ADaM ADPC spec | Yes | PARAMCD/PARAM per analyte, planned dose by arm, BLQ rule, analysis flags |
| Study context | Yes | Single or multiple dose, dosing frequency, nominal sampling schedule |

If PC or EX is absent, stop and request it. Do not substitute synthetic
concentration or dosing data.

---

## Workflow

Follow these steps in order. Generate code section by section, not as a single
block. The steps build on each other: later steps use variables created earlier.

### Step 1 — Setup and domain loading

Remove DOMAIN at load (parent convention). SRCDOM is set explicitly in Step 9.

```r
library(admiral)
library(dplyr)
library(lubridate)
library(stringr)
library(pharmaversesdtm)
library(pharmaverseadam)

pc   <- pharmaversesdtm::pc   |> convert_blanks_to_na() |> select(-DOMAIN)
ex   <- pharmaversesdtm::ex   |> convert_blanks_to_na() |> select(-DOMAIN)
vs   <- pharmaversesdtm::vs   |> convert_blanks_to_na() |> select(-DOMAIN)
adsl <- pharmaverseadam::adsl  # assumed derived upstream

stopifnot(nrow(pc) > 0, nrow(ex) > 0)
stopifnot(all(c("TRTSDT", "TRTSDTM") %in% names(adsl)))
```

### Step 2 — Parameter lookup

One row per analyte, plus a DOSE row for dosing records.

```r
# REVIEW: PARAMCD, PARAM and PARAMN must match the ADaM ADPC spec. Add one row
#   per analyte (and per metabolite) in PCTESTCD.
param_lookup <- tibble::tribble(
  ~PCTESTCD, ~PARAMCD, ~PARAM,                                         ~PARAMN,
  "XAN",     "XAN",    "Pharmacokinetic concentration of Xanomeline",  1,
  "DOSE",    "DOSE",   "Xanomeline Patch Dose",                        2
)

adsl_vars <- exprs(TRTSDT, TRTSDTM, TRT01P, TRT01A)
```

### Step 3 — Concentration dates and nominal time (NFRLT)

Derive the sample datetime with `derive_vars_dtm()`, then nominal time from
first dose with `derive_var_nfrlt()`, which parses PCTPT text ("Pre-dose",
"1h Post-dose", "5 Min Post-dose") and combines it with VISITDY. Never map
PCTPT strings to hours with a hand-written `case_when()`.

```r
pc_dates <- pc |>
  derive_vars_merged(
    dataset_add = adsl,
    new_vars    = adsl_vars,
    by_vars     = exprs(STUDYID, USUBJID)
  ) |>
  derive_vars_dtm(
    new_vars_prefix     = "A",
    dtc                 = PCDTC,
    time_imputation     = "00:00:00",
    flag_imputation     = "auto",
    ignore_seconds_flag = FALSE
  ) |>
  derive_vars_dtm_to_dt(exprs(ADTM)) |>
  derive_vars_dtm_to_tm(exprs(ADTM)) |>
  derive_vars_dy(reference_date = TRTSDT, source_vars = exprs(ADT)) |>
  mutate(EVID = 0, DRUG = PCTEST) |>
  # REVIEW: Nominal time is derived from PCTPT and VISITDY. Confirm against the
  #   protocol sampling schedule: range_method for ranged timepoints
  #   (e.g. "0-6h Post-dose"), treatment_duration for infusions, and any
  #   unscheduled or end-of-study visits, which should get NA via
  #   set_values_to_na rather than a derived nominal time.
  derive_var_nfrlt(
    new_var            = NFRLT,
    new_var_unit       = FRLTU,
    out_unit           = "HOURS",
    tpt_var            = PCTPT,
    visit_day          = VISITDY,
    treatment_duration = 0,
    range_method       = "midpoint"
  )
```

### Step 4 — Dosing records

Build dosing records from EX with the same date logic. Records with a zero dose
(placebo) are dropped, which removes never-dosed subjects from ADPC in Step 6.

```r
ex_dates <- ex |>
  derive_vars_merged(
    dataset_add = adsl,
    new_vars    = adsl_vars,
    by_vars     = exprs(STUDYID, USUBJID)
  ) |>
  # REVIEW: Only nonzero doses are kept, so placebo and never-dosed subjects
  #   are excluded from ADPC. Confirm with the SAP whether they should instead
  #   be kept with an analysis flag.
  filter(EXDOSE > 0) |>
  # REVIEW: EXSTDTC/EXENDTC may be date-only (no dose time). Missing times are
  #   imputed to 00:00:00, so actual relative times (AFRLT, ARRLT) are
  #   approximate. Confirm whether dose times are available from another
  #   source (e.g. EC or eCRF dosing time) before using ARRLT for NCA.
  derive_vars_dtm(
    new_vars_prefix = "AST",
    dtc             = EXSTDTC,
    time_imputation = "00:00:00",
    flag_imputation = "auto"
  ) |>
  derive_vars_dtm(
    new_vars_prefix = "AEN",
    dtc             = EXENDTC,
    time_imputation = "00:00:00",
    flag_imputation = "auto"
  ) |>
  mutate(EVID = 1) |>
  derive_var_nfrlt(
    new_var      = NFRLT,
    new_var_unit = FRLTU,
    out_unit     = "HOURS",
    visit_day    = VISITDY
  ) |>
  mutate(AENDTM = if_else(is.na(AENDTM), ASTDTM, AENDTM)) |>
  derive_vars_dtm_to_dt(exprs(ASTDTM)) |>
  derive_vars_dtm_to_dt(exprs(AENDTM))
```

### Step 5 — Expand dosing intervals into single doses

EX records often cover an interval ("QD from Day 1 to Day 14"). Expand them to
one record per dose with `create_single_dose_dataset()`, which also advances
NFRLT for each dose.

```r
ex_exp <- ex_dates |>
  create_single_dose_dataset(
    dose_freq      = EXDOSFRQ,
    start_date     = ASTDT,
    start_datetime = ASTDTM,
    end_date       = AENDT,
    end_datetime   = AENDTM,
    nominal_time   = NFRLT,
    lookup_table   = dose_freq_lookup,
    lookup_column  = CDISC_VALUE,
    keep_source_vars = exprs(
      STUDYID, USUBJID, EVID, EXDOSFRQ, EXDOSFRM, NFRLT, FRLTU,
      EXDOSE, EXDOSU, EXTRT, ASTDT, ASTDTM, AENDT, AENDTM,
      VISIT, VISITNUM, VISITDY, EXSEQ, !!!adsl_vars
    )
  ) |>
  mutate(
    AVISITN = NFRLT %/% 24 + 1,
    AVISIT  = paste("Day", AVISITN),
    ADTM    = ASTDTM,
    DRUG    = EXTRT
  ) |>
  derive_vars_dtm_to_dt(exprs(ADTM)) |>
  derive_vars_dtm_to_tm(exprs(ADTM)) |>
  derive_vars_dy(reference_date = TRTSDT, source_vars = exprs(ADT))
```

### Step 6 — First dose per subject

Merge the first dose datetime (FANLDTM) onto concentration records. Subjects
with no dose drop out here.

```r
adpc_first_dose <- pc_dates |>
  derive_vars_merged(
    dataset_add = ex_exp,
    filter_add  = EXDOSE > 0 & !is.na(ADTM),
    new_vars    = exprs(FANLDTM = ADTM),
    order       = exprs(ADTM, EXSEQ),
    mode        = "first",
    by_vars     = exprs(STUDYID, USUBJID, DRUG)
  ) |>
  filter(!is.na(FANLDTM)) |>
  mutate(
    AVISITN = NFRLT %/% 24 + 1,
    AVISIT  = paste("Day", AVISITN)
  )
```

### Step 7 — Previous and next dose for each sample

Find the dose before each sample (actual and nominal) and the dose after it
with `derive_vars_joined()`. The join condition compares datetimes, so it works
regardless of row order and on any number of doses.

```r
adpc_doses <- adpc_first_dose |>
  # Previous dose (actual datetime)
  derive_vars_joined(
    dataset_add = ex_exp,
    by_vars     = exprs(USUBJID),
    order       = exprs(ADTM),
    new_vars    = exprs(
      ADTM_prev = ADTM, EXDOSE_prev = EXDOSE,
      AVISIT_prev = AVISIT, AENDTM_prev = AENDTM
    ),
    join_vars   = exprs(ADTM),
    join_type   = "all",
    filter_join = ADTM > ADTM.join,
    mode        = "last",
    check_type  = "none"
  ) |>
  # Next dose (actual datetime)
  derive_vars_joined(
    dataset_add = ex_exp,
    by_vars     = exprs(USUBJID),
    order       = exprs(ADTM),
    new_vars    = exprs(
      ADTM_next = ADTM, EXDOSE_next = EXDOSE,
      AVISIT_next = AVISIT, AENDTM_next = AENDTM
    ),
    join_vars   = exprs(ADTM),
    join_type   = "all",
    filter_join = ADTM <= ADTM.join,
    mode        = "first",
    check_type  = "none"
  ) |>
  # Previous dose (nominal time)
  derive_vars_joined(
    dataset_add = ex_exp,
    by_vars     = exprs(USUBJID),
    order       = exprs(NFRLT),
    new_vars    = exprs(NFRLT_prev = NFRLT),
    join_vars   = exprs(NFRLT),
    join_type   = "all",
    filter_join = NFRLT > NFRLT.join,
    mode        = "last",
    check_type  = "none"
  ) |>
  # Next dose (nominal time)
  derive_vars_joined(
    dataset_add = ex_exp,
    by_vars     = exprs(USUBJID),
    order       = exprs(NFRLT),
    new_vars    = exprs(NFRLT_next = NFRLT),
    join_vars   = exprs(NFRLT),
    join_type   = "all",
    filter_join = NFRLT <= NFRLT.join,
    mode        = "first",
    check_type  = "none"
  )
```

### Step 8 — Combine with dosing records and derive relative times

Stack concentration and dosing records, keep doses up to the last sample date,
and derive actual times with `derive_vars_duration(out_unit = "HOURS")`.

```r
adpc_rel <- bind_rows(adpc_doses, ex_exp) |>
  group_by(USUBJID, DRUG) |>
  mutate(
    FANLDTM   = min(FANLDTM, na.rm = TRUE),
    min_NFRLT = min(NFRLT_prev, na.rm = TRUE),
    maxdate   = max(ADT[EVID == 0], na.rm = TRUE),
    .after = USUBJID
  ) |>
  arrange(USUBJID, ADTM) |>
  ungroup() |>
  filter(ADT <= maxdate) |>
  # Actual relative time from first dose
  derive_vars_duration(
    new_var    = AFRLT,
    start_date = FANLDTM,
    end_date   = ADTM,
    out_unit   = "HOURS",
    floor_in   = FALSE,
    add_one    = FALSE
  ) |>
  # Actual relative time from most recent (reference) dose
  derive_vars_duration(
    new_var      = ARRLT,
    new_var_unit = RRLTU,
    start_date   = ADTM_prev,
    end_date     = ADTM,
    out_unit     = "HOURS",
    floor_in     = FALSE,
    add_one      = FALSE
  ) |>
  # Actual relative time to next dose (temporary, for pre-dose samples)
  derive_vars_duration(
    new_var    = AXRLT,
    start_date = ADTM_next,
    end_date   = ADTM,
    out_unit   = "HOURS",
    floor_in   = FALSE,
    add_one    = FALSE
  ) |>
  mutate(
    ARRLT = case_when(
      EVID == 1    ~ 0,
      is.na(ARRLT) ~ AXRLT,
      TRUE         ~ ARRLT
    ),
    # ARRLT filled from the dose record or next dose has no unit yet
    RRLTU = if_else(!is.na(ARRLT), "HOURS", NA_character_),
    PCRFTDTM = case_when(
      EVID == 1         ~ ADTM,
      is.na(ADTM_prev)  ~ ADTM_next,
      TRUE              ~ ADTM_prev
    ),
    # Nominal relative time from reference dose
    NRRLT = case_when(
      EVID == 1         ~ 0,
      is.na(NFRLT_prev) ~ NFRLT - min_NFRLT,
      TRUE              ~ NFRLT - NFRLT_prev
    ),
    NXRLT = case_when(
      EVID == 1 ~ 0,
      TRUE      ~ NFRLT - NFRLT_next
    )
  ) |>
  derive_vars_dtm_to_dt(exprs(FANLDTM)) |>
  derive_vars_dtm_to_tm(exprs(FANLDTM)) |>
  derive_vars_dtm_to_dt(exprs(PCRFTDTM)) |>
  derive_vars_dtm_to_tm(exprs(PCRFTDTM))
```

### Step 9 — Analysis variables

```r
adpc_aval <- adpc_rel |>
  mutate(
    PARCAT1 = PCSPEC,
    ATPTN   = if_else(EVID == 1, 0, PCTPTNUM),
    ATPT    = if_else(EVID == 1, "Dose", PCTPT),
    ATPTREF = case_when(
      EVID == 1           ~ AVISIT,
      is.na(AVISIT_prev)  ~ AVISIT_next,
      TRUE                ~ AVISIT_prev
    ),
    BASETYPE = paste(ATPTREF, "Baseline"),
    DOSEA = case_when(
      EVID == 1           ~ EXDOSE,
      is.na(EXDOSE_prev)  ~ EXDOSE_next,
      TRUE                ~ EXDOSE_prev
    ),
    # REVIEW: Planned dose (DOSEP) by treatment arm must come from the
    #   protocol. The values below are for the CDISC pilot xanomeline arms.
    DOSEP = case_when(
      TRT01P == "Xanomeline High Dose" ~ 81,
      TRT01P == "Xanomeline Low Dose"  ~ 54
    ),
    DOSEU    = "mg",
    PARAMCD  = coalesce(PCTESTCD, "DOSE"),
    ALLOQ    = PCLLOQ,
    AVAL     = if_else(EVID == 1, EXDOSE, PCSTRESN),
    AVALU    = if_else(EVID == 1, EXDOSU, PCSTRESU),
    AVALCAT1 = if_else(PCSTRESC == "<BLQ", PCSTRESC, prettyNum(signif(AVAL, digits = 3))),
    SRCDOM   = if_else(EVID == 1, "EX", "PC"),
    SRCVAR   = "SEQ",
    SRCSEQ   = coalesce(PCSEQ, EXSEQ)
  )
```

### Step 10 — BLQ imputation as derived records

Keep each BLQ record as is (AVALCAT1 = "<BLQ") and add a derived record
carrying the imputed value. Never overwrite AVAL on the original record.

Only BLQ records with a missing numeric result get a derived record. Pre-dose
BLQ samples often arrive with PCSTRESN = 0 already (as in the CDISC pilot),
so they keep AVAL = 0 and are not imputed.

```r
# REVIEW: BLQ values with missing PCSTRESN are imputed as LLOQ/2 on derived
#   records (DTYPE = "HALFLLOQ"); pre-dose BLQ records with PCSTRESN = 0 keep
#   AVAL = 0. Confirm the BLQ rule with the SAP and pharmacokineticist.
#   NCA-specific rules (0 before Tmax, exclude trailing BLQ) belong in the NCA
#   tool configuration, not in ADPC.
adpc_lloq <- adpc_aval |>
  derive_extreme_records(
    dataset_add   = adpc_aval,
    by_vars       = exprs(USUBJID, PARAMCD, PARCAT1, AVISITN, AVISIT, ADTM, PCSEQ),
    order         = exprs(ADTM, BASETYPE, EVID, ATPTN, PARCAT1),
    mode          = "last",
    filter_add    = PCSTRESC == "<BLQ" & is.na(AVAL),
    set_values_to = exprs(
      AVAL  = ALLOQ * 0.5,
      DTYPE = "HALFLLOQ"
    )
  )
```

### Step 11 — Pre-dose copy records

A sample taken just before a dose is post-dose for the previous dose and
pre-dose for the next. Copy it so it appears in both profiles.

```r
dtype_copy <- adpc_lloq |>
  filter(NFRLT > 0 & NXRLT == 0 & EVID == 0 & !is.na(AVISIT_next)) |>
  select(-PCRFTDT, -PCRFTTM) |>
  mutate(
    ATPTREF  = AVISIT_next,
    ARRLT    = AXRLT,
    NRRLT    = NXRLT,
    PCRFTDTM = ADTM_next,
    DOSEA    = EXDOSE_next,
    BASETYPE = paste(AVISIT_next, "Baseline"),
    ATPT     = "Pre-dose",
    ATPTN    = -0.5,
    DTYPE    = if_else(is.na(DTYPE), "COPY", "COPY/HALFLLOQ")
  ) |>
  derive_vars_dtm_to_dt(exprs(PCRFTDTM)) |>
  derive_vars_dtm_to_tm(exprs(PCRFTDTM))
```

### Step 12 — Flags, baseline and change from baseline

```r
adpc_base <- bind_rows(adpc_lloq, dtype_copy) |>
  arrange(STUDYID, USUBJID, BASETYPE, ADTM, NFRLT) |>
  # REVIEW: ABLFL marks pre-dose records per reference dose. ANL01FL keeps all
  #   records; ANL02FL excludes derived (DTYPE) records. Confirm analysis flag
  #   definitions with the SAP.
  mutate(
    ABLFL   = if_else(ATPT == "Pre-dose" & !is.na(AVAL), "Y", NA_character_),
    MRRLT   = if_else(ARRLT < 0, 0, ARRLT),
    ANL01FL = "Y",
    ANL02FL = if_else(is.na(DTYPE), "Y", NA_character_)
  ) |>
  derive_var_base(
    by_vars    = exprs(STUDYID, USUBJID, PARAMCD, PARCAT1, BASETYPE),
    source_var = AVAL,
    new_var    = BASE,
    filter     = ABLFL == "Y"
  ) |>
  restrict_derivation(
    derivation = derive_var_chg,
    filter     = AVISITN > 0
  )
```

### Step 13 — ASEQ, parameter labels and clean-up

`check_type = "error"` makes ASEQ derivation fail on duplicate sort keys
instead of silently numbering them.

```r
adpc_aseq <- adpc_base |>
  derive_var_obs_number(
    new_var    = ASEQ,
    by_vars    = exprs(STUDYID, USUBJID),
    order      = exprs(ADTM, BASETYPE, EVID, AVISITN, ATPTN, PARCAT1, DTYPE),
    check_type = "error"
  ) |>
  select(
    -PCSEQ, -starts_with("min"), -starts_with("max"), -starts_with("EX"),
    -ends_with("next"), -ends_with("prev"), -DRUG, -EVID, -AXRLT, -NXRLT
  ) |>
  derive_vars_merged(
    dataset_add = select(param_lookup, -PCTESTCD),
    by_vars     = exprs(PARAMCD)
  )
```

### Step 14 — Covariates and remaining ADSL variables

```r
adpc <- adpc_aseq |>
  derive_vars_merged(
    dataset_add = vs,
    filter_add  = VSTESTCD == "HEIGHT",
    by_vars     = exprs(STUDYID, USUBJID),
    new_vars    = exprs(HTBL = VSSTRESN, HTBLU = VSSTRESU)
  ) |>
  derive_vars_merged(
    dataset_add = vs,
    filter_add  = VSTESTCD == "WEIGHT" & VSBLFL == "Y",
    by_vars     = exprs(STUDYID, USUBJID),
    new_vars    = exprs(WTBL = VSSTRESN, WTBLU = VSSTRESU)
  ) |>
  mutate(
    BMIBL  = compute_bmi(height = HTBL, weight = WTBL),
    BMIBLU = "kg/m^2"
  ) |>
  derive_vars_merged(
    dataset_add = select(adsl, !!!negate_vars(adsl_vars)),
    by_vars     = exprs(STUDYID, USUBJID)
  )
```

### Step 15 — Verification

Print record counts and assert structure before finalising.

```r
# Record counts by parameter, specimen and derived-record type
print(count(adpc, PARAMCD, PARCAT1, DTYPE))
cat("Subjects:", n_distinct(adpc$USUBJID), "\n")

# ASEQ unique within subject
stopifnot(!any(duplicated(adpc[, c("USUBJID", "ASEQ")])))

# Dose records sit at ARRLT = 0
stopifnot(all(adpc$ARRLT[adpc$PARAMCD == "DOSE"] == 0, na.rm = TRUE))

# Original BLQ records are never imputed in place: AVAL is missing, or 0 for
# pre-dose BLQ supplied as 0 in SDTM. Imputed values only on HALFLLOQ records.
blq_orig_aval <- adpc$AVAL[adpc$AVALCAT1 %in% "<BLQ" & is.na(adpc$DTYPE)]
stopifnot(all(is.na(blq_orig_aval) | blq_orig_aval == 0))
stopifnot(all(!is.na(adpc$AVAL[adpc$DTYPE %in% "HALFLLOQ"])))

# ANL02FL only on original (non-derived) records
stopifnot(all(is.na(adpc$DTYPE[adpc$ANL02FL %in% "Y"])))

# Time units populated where times are present
stopifnot(all(adpc$FRLTU[!is.na(adpc$NFRLT)] == "HOURS"))
stopifnot(all(adpc$RRLTU[!is.na(adpc$ARRLT)] == "HOURS"))
```

---

## Common errors to avoid

- **Matching doses with `lag()` / `lead()`** — row order is not dose order once
  PC and EX are combined; on multiple-dose data the "previous row" is often a
  sample, not a dose. Use `derive_vars_joined()` with a datetime condition.
- **Computing times with `difftime()` or date subtraction** — use
  `derive_vars_duration(out_unit = "HOURS")` so units are explicit and match
  FRLTU/RRLTU.
- **Mapping PCTPT to hours with `case_when()`** — `derive_var_nfrlt()` parses
  timepoint text consistently; hand-written maps miss variants like
  "5 Min Post-dose".
- **Using only the first dose for ARRLT** — ARRLT is time since the most recent
  dose, not the first; on multiple-dose data the two differ for every sample
  after the second dose.
- **Overwriting BLQ values in AVAL** — keep the original record and add a
  `DTYPE = "HALFLLOQ"` record; overwriting loses traceability.
- **Imputing 0 or LLOQ/2 by NCA position (before/after Tmax) in ADPC** — that
  rule belongs to the NCA tool; ADPC carries one documented imputation.
- **Treating imputed dose times as actual** — date-only EX means dose time is
  00:00 by imputation; flag it with `# REVIEW:` and the imputation flags.
- **Forgetting dosing records** — NCA tools need dose amount and time; keep
  PARAMCD = "DOSE" records alongside concentrations.
- **`left_join()` for ADSL or VS merges** — use `derive_vars_merged()`.

---

## Output checklist

Before returning code, verify:

- [ ] DOMAIN removed from PC, EX and VS at load (Step 1)
- [ ] `# REVIEW:` at PARAMCD/PARAM lookup (Step 2)
- [ ] ADTM derived with `derive_vars_dtm()` from PCDTC (Step 3)
- [ ] NFRLT derived with `derive_var_nfrlt()`, with `# REVIEW:` (Step 3)
- [ ] Zero-dose filter with `# REVIEW:` on excluded subjects (Step 4)
- [ ] `# REVIEW:` on imputed dose times (Step 4)
- [ ] Dosing intervals expanded with `create_single_dose_dataset()` (Step 5)
- [ ] Previous/next dose found with `derive_vars_joined()` (Step 7)
- [ ] AFRLT and ARRLT derived with `derive_vars_duration(out_unit = "HOURS")` (Step 8)
- [ ] `# REVIEW:` at DOSEP planned dose mapping (Step 9)
- [ ] BLQ handled with `DTYPE = "HALFLLOQ"` derived records, with `# REVIEW:` (Step 10)
- [ ] Pre-dose COPY records created (Step 11)
- [ ] `# REVIEW:` at ABLFL/ANL01FL/ANL02FL definitions (Step 12)
- [ ] ASEQ derived with `check_type = "error"` (Step 13)
- [ ] ADSL and VS merged with `derive_vars_merged()` (Step 14)
- [ ] Record counts printed by PARAMCD, PARCAT1 and DTYPE (Step 15)
- [ ] Structural assertions present (Step 15)
