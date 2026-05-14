# ADSL Derivation using admiral and pharmaversesdtm
# 
# This script derives a CDISC-conformant ADSL dataset from pharmaversesdtm
# source domains following ADaM conventions and the admiral workflow.

# Setup and Load Packages -----------------------------------------------

library(admiral)
library(dplyr)
library(lubridate)

# Load SDTM Domains -----------------------------------------------------

# Load from pharmaversesdtm package
dm <- pharmaversesdtm::dm
ex <- pharmaversesdtm::ex
ds <- pharmaversesdtm::ds
# vs <- pharmaversesdtm::vs  # Uncomment if baseline vitals needed

# Subject Spine from DM --------------------------------------------------

# Start with DM - one record per USUBJID
adsl <- dm |>
  select(
    STUDYID, USUBJID, SUBJID, SITEID, 
    AGE, AGEU, SEX, RACE, ETHNIC, COUNTRY,
    ARM, ARMCD, ACTARM, ACTARMCD,
    RFSTDTC, RFENDTC, DMDTC
  )

# Treatment Dates from EX ------------------------------------------------

# TRTSDT: first dose date; TRTEDT: last dose date per subject
# Derive datetime variables first, then extract dates

ex_dt <- ex |>
  derive_vars_dtm(
    dtc = EXSTDTC,
    new_vars_prefix = "EXST",
    date_imputation = "first",
    flag_imputation = "auto"
  ) |>
  derive_vars_dtm(
    dtc = EXENDTC,
    new_vars_prefix = "EXEN",
    date_imputation = "last",
    flag_imputation = "auto"
  )

adsl <- adsl |>
  # First dose date
  derive_vars_merged(
    dataset_add = ex_dt,
    by_vars = exprs(STUDYID, USUBJID),
    new_vars = exprs(TRTSDTM = EXSTDTM),
    order = exprs(EXSTDTM),
    mode = "first",
    filter_add = !is.na(EXSTDTM)
  ) |>
  # Last dose date
  derive_vars_merged(
    dataset_add = ex_dt,
    by_vars = exprs(STUDYID, USUBJID),
    new_vars = exprs(TRTEDTM = EXENDTM),
    order = exprs(EXENDTM),
    mode = "last",
    filter_add = !is.na(EXENDTM)
  ) |>
  # Extract date-only variables
  mutate(
    TRTSDT = as.Date(TRTSDTM),
    TRTEDT = as.Date(TRTEDTM)
  )

# Planned and Actual Treatment -------------------------------------------

# TRT01P from DM.ARM (randomised); TRT01A from DM.ACTARM (actual received)
adsl <- adsl |>
  mutate(
    TRT01P  = ARM,
    TRT01A  = ACTARM,
    TRT01PN = case_when(
      ARMCD == "Pbo"    ~ 0,
      ARMCD == "ARM A"  ~ 1,
      ARMCD == "ARM B"  ~ 2,
      ARMCD == "ARM C"  ~ 3
    ),
    TRT01AN = case_when(
      ACTARMCD == "Pbo"    ~ 0,
      ACTARMCD == "ARM A"  ~ 1,
      ACTARMCD == "ARM B"  ~ 2,
      ACTARMCD == "ARM C"  ~ 3
    )
  )

# Randomisation and Reference Dates --------------------------------------

adsl <- adsl |>
  derive_vars_dt(
    dtc = RFSTDTC,
    new_vars_prefix = "RFST"
  ) |>
  derive_vars_dt(
    dtc = RFENDTC,
    new_vars_prefix = "RFEND"
  ) |>
  mutate(RANDDT = as.Date(DMDTC))

# Study Day Variables ----------------------------------------------------

adsl <- adsl |>
  derive_vars_dy(
    reference_date = TRTSDT,
    source_vars = exprs(RANDDT)
  )

# Disposition Variables --------------------------------------------------

# EOSSTT: end of study status from DS
# DCSREAS: discontinuation reason
# REVIEW: Verify EOSSTT values match protocol-defined categories

ds_dt <- ds |>
  filter(DSCAT == "DISPOSITION EVENT") |>
  derive_vars_dt(
    dtc = DSDTC,
    new_vars_prefix = "DS"
  )

adsl <- adsl |>
  derive_vars_merged(
    dataset_add = ds_dt,
    by_vars = exprs(STUDYID, USUBJID),
    new_vars = exprs(
      EOSSTT = DSDECOD,
      DCSREAS = DSDECOD,
      EOSDT = DSDT
    ),
    order = exprs(DSDT),
    mode = "last"
  )

# Baseline Demographics --------------------------------------------------

# REVIEW: Age grouping cut points must come from ADaM specification
adsl <- adsl |>
  mutate(
    AGEGR1 = case_when(
      AGE < 18             ~ "<18",
      AGE >= 18 & AGE < 65 ~ "18-<65",
      AGE >= 65            ~ ">=65"
    ),
    AGEGR1N = case_when(
      AGEGR1 == "<18"    ~ 1,
      AGEGR1 == "18-<65" ~ 2,
      AGEGR1 == ">=65"   ~ 3
    )
  )

# Baseline vitals (if VS is in scope, uncomment below):
# adsl <- adsl |>
#   derive_vars_merged(
#     dataset_add = vs,
#     by_vars = exprs(STUDYID, USUBJID),
#     new_vars = exprs(HEIGHTBL = VSSTRESN),
#     filter_add = VSTESTCD == "HEIGHT" & VSBLFL == "Y"
#   ) |>
#   derive_vars_merged(
#     dataset_add = vs,
#     by_vars = exprs(STUDYID, USUBJID),
#     new_vars = exprs(WEIGHTBL = VSSTRESN),
#     filter_add = VSTESTCD == "WEIGHT" & VSBLFL == "Y"
#   ) |>
#   mutate(BMIBL = WEIGHTBL / (HEIGHTBL / 100)^2)

# Population Flags -------------------------------------------------------

# REVIEW: Population flag definitions are protocol-specific
# Verify against protocol and SAP before finalizing

adsl <- adsl |>
  # SAFFL: received at least one dose
  derive_var_merged_exist_flag(
    dataset_add = ex,
    by_vars = exprs(STUDYID, USUBJID),
    new_var = SAFFL,
    condition = !is.na(EXSTDTC)
  ) |>
  # ITTFL: randomised (in DM with ARM assigned)
  mutate(
    ITTFL = if_else(!is.na(ARM) & ARM != "Screen Failure", "Y", NA_character_)
  ) |>
  # ENRLFL: enrolled (all subjects in DM)
  mutate(ENRLFL = "Y")

# PPROTFL: per-protocol - highly protocol-specific
# REVIEW: Derive per SAP definition with protocol deviation exclusions
# adsl <- adsl |>
#   mutate(PPROTFL = if_else(ITTFL == "Y" & no_major_deviations, "Y", NA_character_))

# Treatment Duration -----------------------------------------------------

adsl <- adsl |>
  derive_var_trtdurd()

# Final Checks and Validation --------------------------------------------

# Verify one record per USUBJID
stopifnot(nrow(adsl) == n_distinct(adsl$USUBJID))

# Check required variables are present
required_vars <- c(
  "STUDYID", "USUBJID", "TRTSDT", "TRTEDT",
  "TRT01P", "TRT01A", "SAFFL", "ITTFL"
)
missing_vars <- setdiff(required_vars, names(adsl))
if (length(missing_vars) > 0) {
  stop("Missing required ADSL variables: ", paste(missing_vars, collapse = ", "))
}

# Apply Variable Labels (using Hmisc for simple labeling) ---------------

# For submission-ready datasets, use xportr with metacore object:
# adsl |>
#   xportr_label(metacore_obj, domain = "ADSL") |>
#   xportr_type(metacore_obj, domain = "ADSL") |>
#   xportr_length(metacore_obj, domain = "ADSL") |>
#   xportr_order(metacore_obj, domain = "ADSL") |>
#   xportr_write("adsl.xpt", label = "Subject-Level Analysis Dataset")

# For non-submission work, apply key labels:
Hmisc::label(adsl$STUDYID)  <- "Study Identifier"
Hmisc::label(adsl$USUBJID)  <- "Unique Subject Identifier"
Hmisc::label(adsl$TRTSDT)   <- "Date of First Study Treatment"
Hmisc::label(adsl$TRTEDT)   <- "Date of Last Study Treatment"
Hmisc::label(adsl$TRT01P)   <- "Planned Treatment for Period 01"
Hmisc::label(adsl$TRT01A)   <- "Actual Treatment for Period 01"
Hmisc::label(adsl$SAFFL)    <- "Safety Population Flag"
Hmisc::label(adsl$ITTFL)    <- "Intent-to-Treat Population Flag"
Hmisc::label(adsl$AGEGR1)   <- "Age Group 1"
Hmisc::label(adsl$RANDDT)   <- "Date of Randomisation"
Hmisc::label(adsl$EOSSTT)   <- "End of Study Status"
Hmisc::label(adsl$DCSREAS)  <- "Reason for Discontinuation"
Hmisc::label(adsl$TRTDURD)  <- "Total Treatment Duration (Days)"

# Print summary
cat("\nADSL Dataset Summary:\n")
cat("Total subjects:", nrow(adsl), "\n")
cat("Treatment groups:\n")
print(table(adsl$TRT01A, useNA = "ifany"))
cat("\nSafety population:\n")
print(table(adsl$SAFFL, useNA = "ifany"))
cat("\nITT population:\n")
print(table(adsl$ITTFL, useNA = "ifany"))

# Return the ADSL dataset
adsl