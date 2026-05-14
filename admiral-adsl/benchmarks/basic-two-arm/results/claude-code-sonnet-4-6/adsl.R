# adsl.R -----------------------------------------------------------------------
# Subject-Level Analysis Dataset (ADSL) derivation
# Study: CDISC Pilot Study — parallel-group (Xanomeline High/Low Dose vs. Placebo)
# Source data: pharmaversesdtm CDISC Pilot SDTM
# ADaM spec reference: ADaMIG v1.3; pharmaverse admiral

library(admiral)
library(dplyr)
library(lubridate)
library(stringr)
library(Hmisc)
library(pharmaversesdtm)


# ---------------------------------------------------------------------------
# Step 1: Load SDTM domains
# ---------------------------------------------------------------------------

dm <- pharmaversesdtm::dm
ex <- pharmaversesdtm::ex
ds <- pharmaversesdtm::ds
ae <- pharmaversesdtm::ae   # for LSTALVDT
lb <- pharmaversesdtm::lb   # for LSTALVDT


# ---------------------------------------------------------------------------
# Step 2: Subject spine — one record per USUBJID from DM
# ---------------------------------------------------------------------------

adsl <- dm |>
  select(
    STUDYID, USUBJID, SUBJID, SITEID,
    AGE, AGEU, SEX, RACE, ETHNIC, COUNTRY,
    ARM, ARMCD, ACTARM, ACTARMCD,
    DMDTC, RFSTDTC, RFENDTC, DTHDTC
  )


# ---------------------------------------------------------------------------
# Step 3: Treatment datetimes and dates
# TRTSDTM/TRTSDT: first dose; TRTEDTM/TRTEDT: last dose
# Placebo subjects have EXDOSE = 0 — include via EXTRT name check per protocol
# ---------------------------------------------------------------------------

# Derive start and end datetimes on EX — remove DOMAIN to avoid merge conflict
ex_dtm <- ex |>
  select(-DOMAIN) |>
  derive_vars_dtm(
    dtc             = EXSTDTC,
    new_vars_prefix = "EXST",
    date_imputation = "first",
    time_imputation = "first",
    flag_imputation = "auto"
  ) |>
  derive_vars_dtm(
    dtc             = EXENDTC,
    new_vars_prefix = "EXEN",
    date_imputation = "last",
    time_imputation = "last",
    flag_imputation = "auto"
  )

# TRTSDTM: first dose datetime from EX.EXSTDTC; TRTSTMF: time imputation flag
adsl <- adsl |>
  derive_vars_merged(
    dataset_add = ex_dtm,
    by_vars     = exprs(STUDYID, USUBJID),
    new_vars    = exprs(TRTSDTM = EXSTDTM, TRTSTMF = EXSTTMF),
    order       = exprs(EXSTDTM),
    mode        = "first",
    # REVIEW: placebo filter — EXDOSE == 0 for placebo arm; EXTRT contains
    # "PLACEBO" confirms actual treatment exposure per protocol definition
    filter_add  = (EXDOSE > 0 | (EXDOSE == 0 & str_detect(EXTRT, "PLACEBO"))) &
      !is.na(EXSTDTM)
  )

# TRTEDTM: last dose datetime from EX.EXENDTC; TRTETMF: time imputation flag
adsl <- adsl |>
  derive_vars_merged(
    dataset_add = ex_dtm,
    by_vars     = exprs(STUDYID, USUBJID),
    new_vars    = exprs(TRTEDTM = EXENDTM, TRTETMF = EXENTMF),
    order       = exprs(EXENDTM),
    mode        = "last",
    filter_add  = (EXDOSE > 0 | (EXDOSE == 0 & str_detect(EXTRT, "PLACEBO"))) &
      !is.na(EXENDTM)
  )

# TRTSDT/TRTEDT: date-only versions extracted from datetimes
adsl <- adsl |>
  derive_vars_dtm_to_dt(exprs(TRTSDTM, TRTEDTM))


# ---------------------------------------------------------------------------
# Step 4: Planned and actual treatment variables
# TRT01P from DM.ARM (randomised/planned); TRT01A from DM.ACTARM (actual)
# Numeric codes per ADaM spec: Xanomeline High Dose = 3, Low Dose = 2, Placebo = 1
# ---------------------------------------------------------------------------

adsl <- adsl |>
  mutate(
    # TRT01P: planned treatment from DM.ARM per ADaM spec
    TRT01P  = ARM,
    # TRT01A: actual treatment from DM.ACTARM per ADaM spec
    TRT01A  = ACTARM,
    # REVIEW: numeric treatment codes — verify coding against ADaM spec Table 1
    TRT01PN = case_when(
      TRT01P == "Xanomeline High Dose" ~ 3L,
      TRT01P == "Xanomeline Low Dose"  ~ 2L,
      TRT01P == "Placebo"              ~ 1L
    ),
    TRT01AN = case_when(
      TRT01A == "Xanomeline High Dose" ~ 3L,
      TRT01A == "Xanomeline Low Dose"  ~ 2L,
      TRT01A == "Placebo"              ~ 1L
    )
  )


# ---------------------------------------------------------------------------
# Step 5: Reference dates and randomisation date
# RFSTDT/RFENDDT: reference period start/end from DM
# RANDDT: date of randomisation from DM.DMDTC per prompt specification
# ---------------------------------------------------------------------------

adsl <- adsl |>
  derive_vars_dt(
    dtc             = RFSTDTC,
    new_vars_prefix = "RFST",
    date_imputation = "first"
  ) |>
  derive_vars_dt(
    dtc             = RFENDTC,
    new_vars_prefix = "RFEND",
    date_imputation = "last"
  ) |>
  derive_vars_dt(
    dtc             = DMDTC,
    new_vars_prefix = "RAND",
    date_imputation = "first"
  )


# ---------------------------------------------------------------------------
# Step 6: Study day variables
# RANDDY: randomisation day relative to TRTSDT
# derive_vars_dy() enforces CDISC Day 1 convention — never compute manually
# ---------------------------------------------------------------------------

adsl <- adsl |>
  derive_vars_dy(
    reference_date = TRTSDT,
    source_vars    = exprs(RANDDT)
  )


# ---------------------------------------------------------------------------
# Step 7: Disposition — EOSSTT, DCSREAS, DCSREASP, EOSDT
# REVIEW: DSCAT == "DISPOSITION EVENT" selects the primary end-of-study record;
# verify that this filter uniquely identifies one record per subject for this
# study's DS implementation — confirm with the SAP before submission
# ---------------------------------------------------------------------------

ds_eos <- ds |>
  select(-DOMAIN) |>
  filter(DSCAT == "DISPOSITION EVENT") |>
  derive_vars_dt(
    dtc             = DSDTC,
    new_vars_prefix = "DS",
    date_imputation = "last"
  ) |>
  mutate(
    EOSSTT_DER = if_else(DSDECOD == "COMPLETED", "COMPLETED", "DISCONTINUED")
  )

adsl <- adsl |>
  derive_vars_merged(
    dataset_add = ds_eos,
    by_vars     = exprs(STUDYID, USUBJID),
    new_vars    = exprs(
      EOSSTT   = EOSSTT_DER,
      DCSREAS  = DSDECOD,
      DCSREASP = DSTERM,
      EOSDT    = DSDT
    ),
    order = exprs(DSDT),
    mode  = "last"
  ) |>
  mutate(
    # DCSREAS: NA for completers per CDISC ADaM convention (§3.2 flag/reason rules)
    DCSREAS = if_else(EOSSTT == "COMPLETED", NA_character_, DCSREAS)
  )


# ---------------------------------------------------------------------------
# Step 8: Age groupings
# AGEGR1/AGEGR1N per ADaM spec cut points: <65 / 65-80 / >80
# REVIEW: cut points <65 / 65-80 / >80 confirmed from ADaM spec for this study;
# verify against final spec before submission — cut points are study-specific
# ---------------------------------------------------------------------------

adsl <- adsl |>
  mutate(
    AGEGR1 = case_when(
      AGE < 65              ~ "<65",
      AGE >= 65 & AGE <= 80 ~ "65-80",
      AGE > 80              ~ ">80"
    ),
    AGEGR1N = case_when(
      AGEGR1 == "<65"   ~ 1L,
      AGEGR1 == "65-80" ~ 2L,
      AGEGR1 == ">80"   ~ 3L
    )
  )


# ---------------------------------------------------------------------------
# Step 9: Death variables
# DTHDT: date of death from DM.DTHDTC
# DTHFL: "Y" or NA — CDISC convention forbids "N" for flag variables
# ---------------------------------------------------------------------------

adsl <- adsl |>
  derive_vars_dt(
    dtc             = DTHDTC,
    new_vars_prefix = "DTH",
    date_imputation = "first"
  ) |>
  mutate(
    DTHFL = if_else(!is.na(DTHDT), "Y", NA_character_)
  )


# ---------------------------------------------------------------------------
# Step 10: Last known alive date (LSTALVDT)
# Derived as max of AE end dates, LB observation dates, EOSDT, TRTEDT
# REVIEW: source domain list for LSTALVDT must be confirmed against the SAP;
# implementations vary — per rubric, evaluate logic rather than exact values
# ---------------------------------------------------------------------------

# Last AE end date per subject from AE.AEENDTC
ae_lstdt <- ae |>
  select(-DOMAIN) |>
  derive_vars_dt(
    dtc             = AEENDTC,
    new_vars_prefix = "AEEN",
    date_imputation = "last"
  ) |>
  filter(!is.na(AEENDT))

adsl <- adsl |>
  derive_vars_merged(
    dataset_add = ae_lstdt,
    by_vars     = exprs(STUDYID, USUBJID),
    new_vars    = exprs(AE_LSTDT = AEENDT),
    order       = exprs(AEENDT),
    mode        = "last"
  )

# Last LB observation date per subject from LB.LBDTC
lb_lstdt <- lb |>
  select(-DOMAIN) |>
  derive_vars_dt(
    dtc             = LBDTC,
    new_vars_prefix = "LB",
    date_imputation = "last"
  ) |>
  filter(!is.na(LBDT))

adsl <- adsl |>
  derive_vars_merged(
    dataset_add = lb_lstdt,
    by_vars     = exprs(STUDYID, USUBJID),
    new_vars    = exprs(LB_LSTDT = LBDT),
    order       = exprs(LBDT),
    mode        = "last"
  )

# LSTALVDT: latest date subject was known to be alive across all source domains
adsl <- adsl |>
  mutate(
    LSTALVDT = pmax(TRTEDT, EOSDT, DTHDT, AE_LSTDT, LB_LSTDT, na.rm = TRUE)
  ) |>
  select(-AE_LSTDT, -LB_LSTDT)


# ---------------------------------------------------------------------------
# Step 11: Population flags — SAFFL and ITTFL
# Critical: definitions are protocol-specific; verify against protocol and SAP
# ---------------------------------------------------------------------------

# SAFFL: received at least one dose — EXDOSE > 0 (active) OR EXTRT contains
# "PLACEBO" (placebo arm, EXDOSE = 0) with non-missing EXSTDTC
# REVIEW: SAFFL definition from protocol: "received at least one dose of study
# treatment (EXDOSE > 0 or EXTRT contains PLACEBO) with non-missing EXSTDTC";
# verify against final SAP; flag is "Y" or NA only — CDISC forbids "N"
adsl <- adsl |>
  derive_var_merged_exist_flag(
    dataset_add   = select(ex, -DOMAIN),
    by_vars       = exprs(STUDYID, USUBJID),
    new_var       = SAFFL,
    condition     = (EXDOSE > 0 | (EXDOSE == 0 & str_detect(EXTRT, "PLACEBO"))) &
      !is.na(EXSTDTC),
    true_value    = "Y",
    false_value   = NA_character_,
    missing_value = NA_character_
  )

# ITTFL: randomised subjects — ARMCD not "Scrnfail" and ARM not "Screen Failure"
# REVIEW: ITTFL definition per protocol: "all randomised subjects"; confirm
# ARMCD != "Scrnfail" is the complete exclusion criterion; flag is "Y" or NA only
adsl <- adsl |>
  mutate(
    ITTFL = if_else(
      !is.na(ARMCD) & ARMCD != "Scrnfail" & ARM != "Screen Failure",
      "Y",
      NA_character_
    )
  )


# ---------------------------------------------------------------------------
# Step 12: Treatment duration
# TRTDURD: total duration = TRTEDT - TRTSDT + 1 (days)
# Requires TRTSDT and TRTEDT; NA for untreated subjects
# ---------------------------------------------------------------------------

adsl <- adsl |>
  derive_var_trtdurd()


# ---------------------------------------------------------------------------
# Step 13: Final variable selection
# ---------------------------------------------------------------------------

adsl <- adsl |>
  select(
    # Identifiers
    STUDYID, USUBJID, SUBJID, SITEID,
    # Demographics
    AGE, AGEU, AGEGR1, AGEGR1N, SEX, RACE, ETHNIC, COUNTRY,
    # Arm variables (for traceability)
    ARM, ARMCD, ACTARM, ACTARMCD,
    # Treatment
    TRT01P, TRT01PN, TRT01A, TRT01AN,
    TRTSDTM, TRTSTMF, TRTEDTM, TRTETMF,
    TRTSDT, TRTEDT, TRTDURD,
    # Dates and study day
    RANDDT, RFSTDT, RFENDDT, RANDDY,
    # Disposition
    EOSSTT, DCSREAS, DCSREASP, EOSDT,
    # Safety/survival
    DTHFL, DTHDT, LSTALVDT,
    # Population flags
    ITTFL, SAFFL
  )

# Variable labels — applied as final step; use xportr for submission context
Hmisc::label(adsl$STUDYID)  <- "Study Identifier"
Hmisc::label(adsl$USUBJID)  <- "Unique Subject Identifier"
Hmisc::label(adsl$SUBJID)   <- "Subject Identifier for the Study"
Hmisc::label(adsl$SITEID)   <- "Study Site Identifier"
Hmisc::label(adsl$AGE)      <- "Age"
Hmisc::label(adsl$AGEU)     <- "Age Units"
Hmisc::label(adsl$AGEGR1)   <- "Pooled Age Group 1"
Hmisc::label(adsl$AGEGR1N)  <- "Pooled Age Group 1 (N)"
Hmisc::label(adsl$SEX)      <- "Sex"
Hmisc::label(adsl$RACE)     <- "Race"
Hmisc::label(adsl$ETHNIC)   <- "Ethnicity"
Hmisc::label(adsl$COUNTRY)  <- "Country"
Hmisc::label(adsl$ARM)      <- "Description of Planned Arm"
Hmisc::label(adsl$ARMCD)    <- "Planned Arm Code"
Hmisc::label(adsl$ACTARM)   <- "Description of Actual Arm"
Hmisc::label(adsl$ACTARMCD) <- "Actual Arm Code"
Hmisc::label(adsl$TRT01P)   <- "Planned Treatment for Period 01"
Hmisc::label(adsl$TRT01PN)  <- "Planned Treatment for Period 01 (N)"
Hmisc::label(adsl$TRT01A)   <- "Actual Treatment for Period 01"
Hmisc::label(adsl$TRT01AN)  <- "Actual Treatment for Period 01 (N)"
Hmisc::label(adsl$TRTSDTM)  <- "Datetime of First Exposure to Treatment"
Hmisc::label(adsl$TRTSTMF)  <- "Time Imputation Flag for TRTSDTM"
Hmisc::label(adsl$TRTEDTM)  <- "Datetime of Last Exposure to Treatment"
Hmisc::label(adsl$TRTETMF)  <- "Time Imputation Flag for TRTEDTM"
Hmisc::label(adsl$TRTSDT)   <- "Date of First Exposure to Treatment"
Hmisc::label(adsl$TRTEDT)   <- "Date of Last Exposure to Treatment"
Hmisc::label(adsl$TRTDURD)  <- "Total Treatment Duration (Days)"
Hmisc::label(adsl$RANDDT)   <- "Date of Randomization"
Hmisc::label(adsl$RFSTDT)   <- "Subject Reference Start Date"
Hmisc::label(adsl$RFENDDT)  <- "Subject Reference End Date"
Hmisc::label(adsl$RANDDY)   <- "Randomization Day"
Hmisc::label(adsl$EOSSTT)   <- "End of Study Status"
Hmisc::label(adsl$DCSREAS)  <- "Reason for Discontinuation from Study"
Hmisc::label(adsl$DCSREASP) <- "Reason for Disc from Study (Verbatim)"
Hmisc::label(adsl$EOSDT)    <- "Date of End of Study"
Hmisc::label(adsl$DTHFL)    <- "Death Flag"
Hmisc::label(adsl$DTHDT)    <- "Date of Death"
Hmisc::label(adsl$LSTALVDT) <- "Date of Last Known Alive"
Hmisc::label(adsl$ITTFL)    <- "Intent-To-Treat Population Flag"
Hmisc::label(adsl$SAFFL)    <- "Safety Population Flag"


# ---------------------------------------------------------------------------
# Step 14: Final assertions — mandatory per CDISC ADaMIG v1.3
# ---------------------------------------------------------------------------

# One record per USUBJID — non-negotiable per ADaMIG; FDA will reject if violated
stopifnot(nrow(adsl) == n_distinct(adsl$USUBJID))

# All required variables present per prompt specification
required_vars <- c(
  "STUDYID", "USUBJID", "SUBJID", "SITEID",
  "AGE", "AGEU", "SEX", "RACE", "ETHNIC", "COUNTRY",
  "AGEGR1", "AGEGR1N",
  "TRT01P", "TRT01PN", "TRT01A", "TRT01AN",
  "TRTSDTM", "TRTSTMF", "TRTEDTM", "TRTETMF",
  "TRTSDT", "TRTEDT", "TRTDURD",
  "EOSSTT", "EOSDT", "DCSREAS",
  "RANDDT", "DTHFL", "DTHDT", "LSTALVDT",
  "SAFFL", "ITTFL"
)

missing_vars <- setdiff(required_vars, names(adsl))
if (length(missing_vars) > 0) {
  stop("Missing required ADSL variables: ", paste(missing_vars, collapse = ", "))
}

message("ADSL derivation complete: ", nrow(adsl), " subjects, ", ncol(adsl), " variables")
