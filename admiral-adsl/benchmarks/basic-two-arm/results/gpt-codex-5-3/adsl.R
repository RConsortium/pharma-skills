library(admiral)
library(dplyr)
library(stringr)
library(pharmaversesdtm)
library(Hmisc)

# Load SDTM domains from pharmaversesdtm
dm <- pharmaversesdtm::dm
ex <- pharmaversesdtm::ex
ds <- pharmaversesdtm::ds
ae <- pharmaversesdtm::ae
lb <- pharmaversesdtm::lb

# Subject spine: one record per subject from DM
adsl <- dm |>
  select(
    STUDYID, USUBJID, SUBJID, SITEID,
    AGE, AGEU, SEX, RACE, ETHNIC, COUNTRY,
    ARM, ARMCD, ACTARM, DMDTC, RFENDTC, DTHDTC, DTHFL
  )

# TRTSDTM/TRTEDTM: derive first/last treatment datetimes from EX.EXSTDTC/EX.EXENDTC
ex_dt <- ex |>
  select(-any_of("DOMAIN")) |>
  derive_vars_dtm(
    dtc = EXSTDTC,
    new_vars_prefix = "EXST",
    date_imputation = "first",
    time_imputation = "first",
    flag_imputation = "date"
  ) |>
  derive_vars_dtm(
    dtc = EXENDTC,
    new_vars_prefix = "EXEN",
    date_imputation = "last",
    time_imputation = "last",
    flag_imputation = "date"
  )

# REVIEW: Confirm placebo dosing logic (EXDOSE == 0 with EXTRT containing PLACEBO) matches protocol SAFFL definition.
ex_treated <- ex_dt |>
  mutate(EXDOSE_NUM = suppressWarnings(as.numeric(EXDOSE))) |>
  filter(
    !is.na(EXSTDTM) &
      (
        EXDOSE_NUM > 0 |
          (EXDOSE_NUM == 0 & str_detect(str_to_upper(EXTRT), "PLACEBO"))
      )
  )

adsl <- adsl |>
  derive_vars_merged(
    dataset_add = ex_treated,
    by_vars = exprs(STUDYID, USUBJID),
    new_vars = exprs(TRTSDTM = EXSTDTM, TRTSTMF = EXSTDTF),
    order = exprs(EXSTDTM),
    mode = "first",
    filter_add = !is.na(EXSTDTM)
  ) |>
  derive_vars_merged(
    dataset_add = ex_treated,
    by_vars = exprs(STUDYID, USUBJID),
    new_vars = exprs(TRTEDTM = EXENDTM, TRTETMF = EXENDTF),
    order = exprs(EXENDTM),
    mode = "last",
    filter_add = !is.na(EXENDTM)
  ) |>
  mutate(
    TRTSDT = as.Date(TRTSDTM),
    TRTEDT = as.Date(TRTEDTM),
    TRTDURD = if_else(!is.na(TRTSDT) & !is.na(TRTEDT), as.integer(TRTEDT - TRTSDT + 1L), NA_integer_)
  )

# TRT01P/TRT01A and treatment coding from DM
adsl <- adsl |>
  mutate(
    TRT01P = ARM,
    TRT01A = ACTARM,
    TRT01PN = case_when(
      TRT01P == "Xanomeline High Dose" ~ 3,
      TRT01P == "Xanomeline Low Dose" ~ 2,
      TRT01P == "Placebo" ~ 1,
      TRUE ~ NA_real_
    ),
    TRT01AN = case_when(
      TRT01A == "Xanomeline High Dose" ~ 3,
      TRT01A == "Xanomeline Low Dose" ~ 2,
      TRT01A == "Placebo" ~ 1,
      TRUE ~ NA_real_
    )
  )

# RANDDT and DTHDT from DM date strings
adsl <- adsl |>
  derive_vars_dt(dtc = DMDTC, new_vars_prefix = "RAND") |>
  derive_vars_dt(dtc = DTHDTC, new_vars_prefix = "DTH") |>
  mutate(DTHFL = if_else(!is.na(DTHDT), "Y", NA_character_))

# EOSSTT/EOSDT/DCSREAS from DS disposition events
# REVIEW: Verify this DS selection rule (DSCAT == "DISPOSITION EVENT", latest DSDTC) against protocol/SAP.
ds_eos <- ds |>
  filter(DSCAT == "DISPOSITION EVENT") |>
  derive_vars_dt(dtc = DSDTC, new_vars_prefix = "DS")

adsl <- adsl |>
  derive_vars_merged(
    dataset_add = ds_eos,
    by_vars = exprs(STUDYID, USUBJID),
    new_vars = exprs(DSDECOD_EOS = DSDECOD, DSTERM_EOS = DSTERM, EOSDT = DSDT),
    order = exprs(DSDT),
    mode = "last"
  ) |>
  mutate(
    EOSSTT = case_when(
      is.na(DSDECOD_EOS) ~ NA_character_,
      str_to_upper(DSDECOD_EOS) == "COMPLETED" ~ "COMPLETED",
      TRUE ~ "DISCONTINUED"
    ),
    DCSREAS = if_else(EOSSTT == "DISCONTINUED", DSTERM_EOS, NA_character_)
  )

# LSTALVDT: last known alive date using AE/LB/DS and treatment/reference dates
ae_last <- ae |>
  derive_vars_dt(dtc = AESTDTC, new_vars_prefix = "AES") |>
  group_by(STUDYID, USUBJID) |>
  summarise(AELDT = if (all(is.na(AESDT))) as.Date(NA) else max(AESDT, na.rm = TRUE), .groups = "drop")

lb_last <- lb |>
  derive_vars_dt(dtc = LBDTC, new_vars_prefix = "LB") |>
  group_by(STUDYID, USUBJID) |>
  summarise(LBLDT = if (all(is.na(LBDT))) as.Date(NA) else max(LBDT, na.rm = TRUE), .groups = "drop")

ds_last <- ds |>
  derive_vars_dt(dtc = DSDTC, new_vars_prefix = "DS") |>
  group_by(STUDYID, USUBJID) |>
  summarise(DSLDT = if (all(is.na(DSDT))) as.Date(NA) else max(DSDT, na.rm = TRUE), .groups = "drop")

adsl <- adsl |>
  derive_vars_dt(dtc = RFENDTC, new_vars_prefix = "RFEND") |>
  left_join(ae_last, by = c("STUDYID", "USUBJID")) |>
  left_join(lb_last, by = c("STUDYID", "USUBJID")) |>
  left_join(ds_last, by = c("STUDYID", "USUBJID")) |>
  rowwise() |>
  mutate(
    LSTALVDT = {
      candidate_dates <- c(TRTEDT, AELDT, LBLDT, DSLDT, RFENDDT)
      candidate_dates <- candidate_dates[!is.na(candidate_dates)]
      if (length(candidate_dates) == 0L) as.Date(NA) else as.Date(max(candidate_dates), origin = "1970-01-01")
    }
  ) |>
  ungroup()

# AGEGR1/AGEGR1N per ADaM spec cut-points in the benchmark prompt
adsl <- adsl |>
  mutate(
    AGEGR1 = case_when(
      AGE < 65 ~ "<65",
      AGE <= 80 ~ "65-80",
      AGE > 80 ~ ">80",
      TRUE ~ NA_character_
    ),
    AGEGR1N = case_when(
      AGEGR1 == "<65" ~ 1,
      AGEGR1 == "65-80" ~ 2,
      AGEGR1 == ">80" ~ 3,
      TRUE ~ NA_real_
    )
  )

# REVIEW: Confirm SAFFL derivation exactly matches protocol wording for dose and EXSTDTC completeness.
adsl <- adsl |>
  derive_var_merged_exist_flag(
    dataset_add = ex,
    by_vars = exprs(STUDYID, USUBJID),
    new_var = SAFFL,
    condition = !is.na(EXSTDTC) &
      (
        suppressWarnings(as.numeric(EXDOSE)) > 0 |
          (
            suppressWarnings(as.numeric(EXDOSE)) == 0 &
              str_detect(str_to_upper(EXTRT), "PLACEBO")
          )
      )
  ) |>
  mutate(SAFFL = if_else(SAFFL == "Y", "Y", NA_character_))

# REVIEW: Confirm ITTFL randomization definition exclusions for screen failures are aligned with SAP.
adsl <- adsl |>
  mutate(
    ITTFL = if_else(ARMCD != "Scrnfail" & ARM != "Screen Failure", "Y", NA_character_)
  )

adsl <- adsl |>
  select(
    STUDYID, USUBJID, SUBJID, SITEID,
    AGE, AGEU, SEX, RACE, ETHNIC, COUNTRY,
    AGEGR1, AGEGR1N,
    TRT01P, TRT01PN, TRT01A, TRT01AN,
    TRTSDTM, TRTSTMF, TRTEDTM, TRTETMF,
    TRTSDT, TRTEDT, TRTDURD,
    EOSSTT, EOSDT, DCSREAS,
    RANDDT, DTHFL, DTHDT, LSTALVDT,
    SAFFL, ITTFL
  )

# Programmatic assertion: one record per USUBJID
stopifnot(nrow(adsl) == dplyr::n_distinct(adsl$USUBJID))

# Variable labels
label(adsl$STUDYID) <- "Study Identifier"
label(adsl$USUBJID) <- "Unique Subject Identifier"
label(adsl$SUBJID) <- "Subject Identifier for the Study"
label(adsl$SITEID) <- "Study Site Identifier"
label(adsl$AGE) <- "Age"
label(adsl$AGEU) <- "Age Units"
label(adsl$SEX) <- "Sex"
label(adsl$RACE) <- "Race"
label(adsl$ETHNIC) <- "Ethnicity"
label(adsl$COUNTRY) <- "Country"
label(adsl$AGEGR1) <- "Age Group 1"
label(adsl$AGEGR1N) <- "Age Group 1 (N)"
label(adsl$TRT01P) <- "Planned Treatment for Period 01"
label(adsl$TRT01PN) <- "Planned Treatment for Period 01 (N)"
label(adsl$TRT01A) <- "Actual Treatment for Period 01"
label(adsl$TRT01AN) <- "Actual Treatment for Period 01 (N)"
label(adsl$TRTSDTM) <- "Datetime of First Study Treatment"
label(adsl$TRTSTMF) <- "Datetime of First Study Treatment Imputation Flag"
label(adsl$TRTEDTM) <- "Datetime of Last Study Treatment"
label(adsl$TRTETMF) <- "Datetime of Last Study Treatment Imputation Flag"
label(adsl$TRTSDT) <- "Date of First Study Treatment"
label(adsl$TRTEDT) <- "Date of Last Study Treatment"
label(adsl$TRTDURD) <- "Total Treatment Duration (Days)"
label(adsl$EOSSTT) <- "End of Study Status"
label(adsl$EOSDT) <- "End of Study Date"
label(adsl$DCSREAS) <- "Reason for Discontinuation"
label(adsl$RANDDT) <- "Date of Randomization"
label(adsl$DTHFL) <- "Death Flag"
label(adsl$DTHDT) <- "Date of Death"
label(adsl$LSTALVDT) <- "Date Last Known Alive"
label(adsl$SAFFL) <- "Safety Population Flag"
label(adsl$ITTFL) <- "Intent-to-Treat Population Flag"

# Dataset label for ADaM-style output
attr(adsl, "label") <- "Subject-Level Analysis Dataset"

print(adsl)
