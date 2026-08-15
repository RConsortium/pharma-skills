# Turn a simulated CathPatient trajectory into CRF row tibbles, one per form. Ported from
# cath_emit.py. Read-only: it only reshapes existing data. 17 forms; columns match
# odm/crf_picks.json exactly. EX is written for EVERY subject (dose 0 for placebo), with the end day
# cut off at the discontinuation day.

.cd <- function(p, day) format(cath_visit_date(p$baseline_date, day), "%Y-%m-%d")
.crows <- function(p, keys) Filter(function(r) r$visit_key %in% keys, p$trajectory)
.has <- function(r, key) !is.null(r$data[[key]])

cath_emit_DM <- function(p) {
  scrn <- cath_row(p, "SCRN"); consent_day <- if (!is.null(scrn)) scrn$actual_day else -7L
  tibble::tibble(USUBJID = p$patient_id, SITEID = p$site,
    ARMCD = if (p$is_vitd) "VITD" else "PBO", ARM = p$arm, DIAGGRP = p$diagnosis_group,
    AGE = p$age, SEX = p$sex, RACE = p$race, ETHNIC = p$ethnic, COUNTRY = p$country,
    HEIGHT = round(p$height_cm, 1), WEIGHT = round(p$weight_kg, 1), BMI = round(p$bmi, 1),
    ICDTC = .cd(p, consent_day), RFSTDTC = .cd(p, 0))
}

cath_emit_DC <- function(p) {
  scrn <- cath_row(p, "SCRN")
  tibble::tibble(USUBJID = p$patient_id, DCDTC = .cd(p, if (!is.null(scrn)) scrn$actual_day else -7L),
    DXPSOR = p$dx_psoriasis,
    PSORDUR_MO = .or_blank(if (!is.null(p$psor_duration_mo)) round(p$psor_duration_mo, 1) else NULL),
    PSORSEV = p$psor_severity)
}

cath_emit_MH <- function(p) {
  scrn <- cath_row(p, "SCRN"); day <- if (!is.null(scrn)) scrn$actual_day else -7L
  if (!length(p$mh_items)) return(tibble::tibble())
  dplyr::bind_rows(lapply(p$mh_items, function(it) tibble::tibble(
    USUBJID = p$patient_id, MHDTC = .cd(p, day), MHTERM = it$MHTERM, MHOCCUR = it$MHOCCUR)))
}

cath_emit_CM <- function(p) {
  scrn <- cath_row(p, "SCRN"); day <- if (!is.null(scrn)) scrn$actual_day else -7L
  if (!length(p$cm_items)) return(tibble::tibble())
  dplyr::bind_rows(lapply(p$cm_items, function(it) tibble::tibble(
    USUBJID = p$patient_id, CMDTC = .cd(p, day), CMTRT = it$CMTRT, CMINDC = it$CMINDC,
    CMSTDTC = .cd(p, -it$CMSTOFFSET), CMENDTC = "", CMONGO = it$CMONGO)))
}

cath_emit_EX <- function(p) {
  end_day <- if (p$not_completed && !is.null(p$discontinuation_day)) p$discontinuation_day else 21L
  tibble::tibble(USUBJID = p$patient_id, EXTRT = if (p$is_vitd) "VITAMIN D3" else "PLACEBO",
    EXDOSE = if (p$is_vitd) 4000L else 0L, EXDOSU = "IU", EXROUTE = "ORAL", EXDOSFRQ = "QD",
    EXSTDTC = .cd(p, 0), EXENDTC = .cd(p, end_day),
    EXNDISP = p$ex_ndisp, EXNRET = p$ex_nret, EXCOMPL = round(p$ex_compliance, 1))
}

.cath_visit_form <- function(p, keys, need, build) {
  rows <- list()
  for (r in .crows(p, keys)) if (.has(r, need)) rows[[length(rows) + 1L]] <- build(r)
  if (length(rows)) dplyr::bind_rows(rows) else tibble::tibble()
}

cath_emit_VS <- function(p) .cath_visit_form(p, c("BL", "D21"), "SYSBP", function(r) tibble::tibble(
  USUBJID = p$patient_id, VISIT = r$visit_key, VISITNUM = r$visit_num, VSDTC = .cd(p, r$actual_day),
  SYSBP = r$data$SYSBP, DIABP = r$data$DIABP, PULSE = r$data$PULSE, TEMP = r$data$TEMP, RESP = r$data$RESP))

cath_emit_PE <- function(p) .cath_visit_form(p, c("BL", "D21"), "PEGEN", function(r) tibble::tibble(
  USUBJID = p$patient_id, VISIT = r$visit_key, PEDTC = .cd(p, r$actual_day),
  PEGEN = r$data$PEGEN, PEORAL = r$data$PEORAL, PEABN = r$data$PEABN))

cath_emit_SK <- function(p) .cath_visit_form(p, c("BL", "D21"), "PASI", function(r) tibble::tibble(
  USUBJID = p$patient_id, VISIT = r$visit_key, SKDTC = .cd(p, r$actual_day),
  PASI = as.character(r$data$PASI %||% ""), FITZPATRICK = as.character(r$data$FITZPATRICK %||% "")))

cath_emit_PT <- function(p) {
  if (p$sex != "F") return(tibble::tibble())
  rows <- lapply(.crows(p, c("SCRN", "BL", "D21")), function(r) tibble::tibble(
    USUBJID = p$patient_id, VISIT = r$visit_key, PGDTC = .cd(p, r$actual_day),
    PGRESULT = "NEGATIVE", PGMETHOD = "URINE"))
  if (length(rows)) dplyr::bind_rows(rows) else tibble::tibble()
}

cath_emit_LB <- function(p) .cath_visit_form(p, c("SCRN", "D21"), "VITD", function(r) tibble::tibble(
  USUBJID = p$patient_id, VISIT = r$visit_key, LBDTC = .cd(p, r$actual_day), LBDY = r$actual_day,
  VITD = r$data$VITD, CALCIUM = r$data$CALCIUM, CREAT = r$data$CREAT, PTH = r$data$PTH,
  IGE = r$data$IGE, RAST = r$data$RAST, SERUMSTOR = r$data$SERUMSTOR))

cath_emit_BX <- function(p) .cath_visit_form(p, c("BL", "D21"), "CAMP_LES", function(r) tibble::tibble(
  USUBJID = p$patient_id, VISIT = r$visit_key, BXDTC = .cd(p, r$actual_day), BXDY = r$actual_day,
  CAMP_LES = r$data$CAMP_LES, CAMP_NONLES = r$data$CAMP_NONLES, HBD3_LES = r$data$HBD3_LES, HBD3_NONLES = r$data$HBD3_NONLES,
  IL13_LES = r$data$IL13_LES, IL13_NONLES = r$data$IL13_NONLES, IL4_LES = r$data$IL4_LES, IL4_NONLES = r$data$IL4_NONLES,
  PHOTO = r$data$PHOTO))

cath_emit_SAL <- function(p) .cath_visit_form(p, c("BL", "D21"), "SAL_CAMP", function(r) tibble::tibble(
  USUBJID = p$patient_id, VISIT = r$visit_key, SALDTC = .cd(p, r$actual_day),
  SAL_CAMP = r$data$SAL_CAMP, SAL_HBD3 = r$data$SAL_HBD3, SAL_TOTPROT = r$data$SAL_TOTPROT))

cath_emit_TS <- function(p) .cath_visit_form(p, c("BL", "D21"), "TS_CAMP_LES", function(r) tibble::tibble(
  USUBJID = p$patient_id, VISIT = r$visit_key, TSDTC = .cd(p, r$actual_day),
  TS_CAMP_LES = r$data$TS_CAMP_LES, TS_CAMP_NONLES = r$data$TS_CAMP_NONLES,
  TS_HBD3_LES = r$data$TS_HBD3_LES, TS_HBD3_NONLES = r$data$TS_HBD3_NONLES))

cath_emit_MB <- function(p) .cath_visit_form(p, c("BL", "D21"), "CFU_LES", function(r) tibble::tibble(
  USUBJID = p$patient_id, VISIT = r$visit_key, MBDTC = .cd(p, r$actual_day),
  CFU_LES = r$data$CFU_LES, CFU_NONLES = r$data$CFU_NONLES))

cath_emit_SW <- function(p) .cath_visit_form(p, c("BL", "D21"), "SWCOLLECT", function(r) tibble::tibble(
  USUBJID = p$patient_id, VISIT = r$visit_key, SWDTC = .cd(p, r$actual_day),
  SWCOLLECT = r$data$SWCOLLECT, SWLOC = r$data$SWLOC, SW_FLORA = r$data$SW_FLORA))

cath_emit_AE <- function(p) {
  rows <- list()
  for (r in p$trajectory) for (a in r$aes) rows[[length(rows) + 1L]] <- tibble::tibble(
    USUBJID = a$USUBJID, VISIT = a$VISIT, VISITNUM = a$VISITNUM, AESTDTC = a$AESTDTC, AEENDTC = a$AEENDTC,
    AEDY = a$AEDY, AETERM = a$AETERM, AEDECOD = a$AEDECOD, AEBODSYS = a$AEBODSYS, AESEV = a$AESEV,
    AETOXGR = a$AETOXGR, AEREL = a$AEREL, AEACN = a$AEACN, AESER = a$AESER, AEOUT = a$AEOUT, AEONGO = a$AEONGO)
  if (length(rows)) dplyr::bind_rows(rows) else tibble::tibble()
}

cath_emit_DS <- function(p) tibble::tibble(
  USUBJID = p$patient_id, DSDTC = .cd(p, p$last_contact_day), DSDECOD = p$disposition,
  DSTERM = p$discontinuation_reason %||% "COMPLETED STUDY", DSSTDY = p$last_contact_day)

CATH_EMITTERS <- list(
  DM = cath_emit_DM, DC = cath_emit_DC, MH = cath_emit_MH, CM = cath_emit_CM, EX = cath_emit_EX,
  VS = cath_emit_VS, PE = cath_emit_PE, SK = cath_emit_SK, PT = cath_emit_PT, LB = cath_emit_LB,
  BX = cath_emit_BX, SAL = cath_emit_SAL, TS = cath_emit_TS, MB = cath_emit_MB, SW = cath_emit_SW,
  AE = cath_emit_AE, DS = cath_emit_DS
)
