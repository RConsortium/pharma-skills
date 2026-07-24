# Turn a simulated patient trajectory into CRF row tables (tibbles), one per form. Mirrors
# rave_emit.py. Just reshapes what's already there — no new random draws. 12 forms; EX has a row
# for every visit where a drug was given.

.rave_d <- function(p, day) format(rave_visit_date(p$baseline_date, day), "%Y-%m-%d")

rave_emit_DM <- function(p) tibble::tibble(
  USUBJID = p$patient_id, SITEID = p$site, ARMCD = if (p$is_rtx) "RTX" else "CYC",
  ARM = p$arm, AGE = p$age, SEX = p$sex, RACE = p$race, COUNTRY = p$country,
  WEIGHT = round(p$weight_kg, 1), RFSTDTC = .rave_d(p, 1)
)

rave_emit_DC <- function(p) tibble::tibble(
  USUBJID = p$patient_id, DIAGTYPE = p$diagnosis_type, ANCATYPE = p$anca_type,
  ANCASTAT = "POSITIVE", NEWDX = if (p$new_diagnosis) "NEW" else "RELAPSING",
  RENAL = if (p$renal_involvement) "Y" else "N",
  BVASWG_BL = round(p$baseline_bvaswg, 1), VDI_BL = p$baseline_vdi
)

rave_emit_DA <- function(p) {
  rows <- list()
  for (r in p$trajectory) if (r$visit_key %in% c("V5","V6","V7","V8","V9","V10","V11","V12"))
    rows[[length(rows)+1L]] <- tibble::tibble(
      USUBJID = p$patient_id, VISIT = r$visit_key, VISITNUM = r$visit_num,
      DADTC = .rave_d(p, r$actual_day), DADY = r$actual_day,
      BVASWG = r$bvaswg, REMISSION = if (r$remission) "Y" else "N",
      FLARE = r$flare, GCFREE = if (r$prednisone_dose == 0) "Y" else "N")
  if (length(rows)) dplyr::bind_rows(rows) else tibble::tibble()
}

rave_emit_VDI <- function(p) {
  rows <- list()
  for (r in p$trajectory) if (r$visit_key %in% VDI_VISITS)
    rows[[length(rows)+1L]] <- tibble::tibble(USUBJID = p$patient_id, VISIT = r$visit_key, VDIDY = r$actual_day, VDI = r$vdi)
  if (length(rows)) dplyr::bind_rows(rows) else tibble::tibble()
}

rave_emit_LB_HEM <- function(p) {
  rows <- lapply(p$trajectory, function(r) tibble::tibble(
    USUBJID = p$patient_id, VISIT = r$visit_key, VISITNUM = r$visit_num,
    LBDTC = .rave_d(p, r$actual_day), LBDY = r$actual_day,
    WBC = r$wbc, ANC = r$anc, HGB = r$hgb, PLT = r$plt, ESR = r$esr))
  if (length(rows)) dplyr::bind_rows(rows) else tibble::tibble()
}

rave_emit_LB_CHEM <- function(p) {
  rows <- lapply(p$trajectory, function(r) tibble::tibble(
    USUBJID = p$patient_id, VISIT = r$visit_key, LBDTC = .rave_d(p, r$actual_day),
    BUN = r$bun, CREAT = r$creat, CRP = r$crp))
  if (length(rows)) dplyr::bind_rows(rows) else tibble::tibble()
}

rave_emit_LB_UA <- function(p) {
  hmap <- c("NEGATIVE", "+", "++", "+++")   # hematuria score 0..3 -> label; R is 1-indexed, so hmap[h+1]
  rows <- lapply(p$trajectory, function(r) tibble::tibble(
    USUBJID = p$patient_id, VISIT = r$visit_key, LBDTC = .rave_d(p, r$actual_day),
    HEMATURIA = hmap[r$hematuria + 1L]))
  if (length(rows)) dplyr::bind_rows(rows) else tibble::tibble()
}

rave_emit_GC <- function(p) {
  keep <- c("V1","V2","V3","V4","V5","V6","V7","V8","V9","V10","V11","V12")
  rows <- list()
  for (r in p$trajectory) if (r$visit_key %in% keep)
    rows[[length(rows)+1L]] <- tibble::tibble(
      USUBJID = p$patient_id, VISIT = r$visit_key, GCDTC = .rave_d(p, r$actual_day),
      PREDDOSE = r$prednisone_dose, CUMGC = r$cum_gc, GCFREE = if (r$prednisone_dose == 0) "Y" else "N")
  if (length(rows)) dplyr::bind_rows(rows) else tibble::tibble()
}

rave_emit_EX <- function(p) {
  rows <- list()
  for (r in p$trajectory) {
    if (r$rtx_infusion)
      rows[[length(rows)+1L]] <- tibble::tibble(USUBJID = p$patient_id, VISIT = r$visit_key,
        EXTRT = if (p$is_rtx) "RITUXIMAB" else "RITUXIMAB PLACEBO", EXDOSE = 375, EXDOSU = "mg/m2",
        EXROUTE = "IV", EXSTDTC = .rave_d(p, r$actual_day), EXACN = r$dose_action)
    if (r$cyc_active)
      rows[[length(rows)+1L]] <- tibble::tibble(USUBJID = p$patient_id, VISIT = r$visit_key,
        EXTRT = if (!p$is_rtx) "CYCLOPHOSPHAMIDE" else "CYCLOPHOSPHAMIDE PLACEBO", EXDOSE = 2, EXDOSU = "mg/kg/day",
        EXROUTE = "ORAL", EXSTDTC = .rave_d(p, r$actual_day), EXACN = r$dose_action)
    else if (r$aza_active)
      rows[[length(rows)+1L]] <- tibble::tibble(USUBJID = p$patient_id, VISIT = r$visit_key,
        EXTRT = if (!p$is_rtx) "AZATHIOPRINE" else "AZATHIOPRINE PLACEBO", EXDOSE = 2, EXDOSU = "mg/kg/day",
        EXROUTE = "ORAL", EXSTDTC = .rave_d(p, r$actual_day), EXACN = r$dose_action)
  }
  if (length(rows)) dplyr::bind_rows(rows) else tibble::tibble()
}

.rave_ae_row <- function(a) tibble::tibble(
  USUBJID = a$USUBJID, VISIT = a$VISIT, VISITLBL = a$VISITLBL, VISITNUM = a$VISITNUM,
  AEDY = a$AEDY, AESTDTC = a$AESTDTC, AETERM = a$AETERM, AEDECOD = a$AEDECOD, AEBODSYS = a$AEBODSYS,
  AESEV = a$AESEV, AETOXGR = a$AETOXGR, AEREL = a$AEREL, AEACN = a$AEACN, AESER = a$AESER,
  AEOUT = a$AEOUT, AEENDTC = a$AEENDTC)

rave_emit_AE <- function(p) {
  rows <- list()
  for (r in p$trajectory) for (a in r$aes) rows[[length(rows)+1L]] <- .rave_ae_row(a)
  if (length(rows)) dplyr::bind_rows(rows) else tibble::tibble()
}

rave_emit_DS <- function(p) tibble::tibble(
  USUBJID = p$patient_id, ARMCD = if (p$is_rtx) "RTX" else "CYC",
  DSDECOD = p$disposition, DSTERM = p$discontinuation_reason %||% "COMPLETED STUDY",
  DSSTDY = p$last_contact_day, CROSSOVER = if (!is.null(p$crossover_day)) "Y" else "N",
  CROSSDY = .or_blank(p$crossover_day))

rave_emit_RE <- function(p) tibble::tibble(
  USUBJID = p$patient_id, ARMCD = if (p$is_rtx) "RTX" else "CYC",
  ANCATYPE = p$anca_type, NEWDX = if (p$new_diagnosis) "NEW" else "RELAPSING",
  CR6MO = p$cr_6mo,
  TTREM_DAY = .or_blank(p$time_to_remission_day), TTCR_DAY = .or_blank(p$time_to_cr_day),
  FLARE_EVENT = p$flare_event, FLARE_DAY = .or_blank(p$flare_day),
  REMDUR_DAY = .or_blank(p$remission_duration_day),
  SERIOUS_AE = p$serious_ae, DEATH = if (!is.null(p$death_day)) 1L else 0L,
  DISPOSITION = p$disposition)

RAVE_EMITTERS <- list(
  DM = rave_emit_DM, DC = rave_emit_DC, DA = rave_emit_DA, VDI = rave_emit_VDI,
  LB_HEM = rave_emit_LB_HEM, LB_CHEM = rave_emit_LB_CHEM, LB_UA = rave_emit_LB_UA,
  GC = rave_emit_GC, EX = rave_emit_EX, AE = rave_emit_AE, DS = rave_emit_DS, RE = rave_emit_RE
)
