# Lt — steps each patient forward visit by visit for CATH. Ported from cath_longitudinal.py.
# Baseline (V2, Day 0) and Day 21 (V3) drive the endpoints. Main mechanism:
#   arm -> serum vitamin D (Day 21) -> skin AMP goes up, with TH2 suppressed and microbes following.
# The dropout decision happens AFTER baseline and BEFORE Day 21, so a dropout has NO Day-21 data
# (and is left out of the efficacy population). Endpoints are NOT computed here.

cath_visitrow <- function(key, num, day, actual) ct_rec(visit_key = key, visit_num = num, visit_day = day, actual_day = actual, data = list(), aes = list())
.merge <- function(row, kv) row$data <- modifyList(row$data, kv)

.change_cell <- function(change_dict, group, comp) {
  cell <- tryCatch(change_dict[[group]][[comp]], error = function(e) NULL)
  if (is.null(cell)) list(placebo_drift = 0.0, beta_vd = 0.0, sd_placebo = 2.5, sd_vitd = 2.5) else cell
}

.amp_change <- function(cell, is_vitd, f_vitd_resp, P) {
  drift <- cell$placebo_drift; beta <- cell$beta_vd
  if (is_vitd) {
    eta <- P$amp_change_resp_coef
    resid_var <- max(cell$sd_vitd^2 - (eta * P$sigma_f_vitd_resp)^2, 0.25)
    drift + beta + eta * f_vitd_resp + np_normal(0, sqrt(resid_var))
  } else drift + np_normal(0, cell$sd_placebo)
}

.il13_change <- function(cell, is_vitd, f_th2, P) {
  drift <- cell$placebo_drift; beta <- cell$beta_vd
  mean_ <- drift + (if (is_vitd) beta else 0.0)
  k <- P$il13_th2_coupling
  sd <- if (is_vitd) cell$sd_vitd else cell$sd_placebo
  resid_var <- max(sd^2 - (k * P$sigma_f_th2)^2, 0.25)
  mean_ + k * f_th2 + np_normal(0, sqrt(resid_var))
}

.vitals <- function(patient, P, prior = NULL) {
  out <- list()
  for (name in names(P$vitals_norms)) {
    ms <- P$vitals_norms[[name]]; mu <- ms[1]; sd <- ms[2]
    base <- mu + (if (name == "SYSBP") P$vitals_age_slope_sysbp * (patient$age - 40) else 0.0)
    val <- if (is.null(prior)) np_normal(base, sd) else P$vitals_ar * prior[[name]] + (1 - P$vitals_ar) * base + np_normal(0, sd * 0.5)
    out[[name]] <- if (name == "TEMP") round(val, 1) else as.integer(round(val))
  }
  out
}

.pe <- function(patient, P) {
  p_abn <- P$pe_abnormal_skin_prob_by_group[[patient$diagnosis_group]]
  if (np_random() < p_abn) {
    finding <- switch(patient$diagnosis_group, Psor = "Erythematous scaling plaques",
                      AD = "Eczematous excoriated lesions", NonAD = "Xerosis")
    list(PEGEN = "ABNORMAL", PEORAL = "NORMAL", PEABN = finding)
  } else list(PEGEN = "NORMAL", PEORAL = "NORMAL", PEABN = "None")
}

.pasi <- function(patient, P, baseline = NULL) {
  if (patient$diagnosis_group != "Psor" || !nzchar(patient$psor_severity)) return("")
  val <- if (is.null(baseline)) P$pasi_by_severity[[patient$psor_severity]] + np_normal(0, P$pasi_noise_sd)
         else baseline + (if (patient$is_vitd) P$pasi_vitd_delta else 0.0) + np_normal(0, P$pasi_noise_sd)
  round(max(0.0, val), 1)
}

.cath_ae <- function(patient, term, severe, onset_day, visit, related, action = "DOSE NOT CHANGED") {
  spec <- CATH_AE_CATALOG[[term]]
  grade <- cath_fda_grade(severe)
  onset <- as.integer(onset_day)
  dur <- np_integers(1L, 6L)
  end_day <- min(onset + dur, CATH_ADMIN_CENSOR_DAY)
  ct_rec(
    USUBJID = patient$patient_id, VISIT = visit$visit_key, VISITNUM = visit$visit_num,
    AESTDTC = format(cath_visit_date(patient$baseline_date, onset), "%Y-%m-%d"),
    AEENDTC = format(cath_visit_date(patient$baseline_date, end_day), "%Y-%m-%d"),
    AEDY = onset, AETERM = term, AEDECOD = spec$decod, AEBODSYS = spec$sys,
    AESEV = CATH_SEV_WORD[grade], AETOXGR = grade, AEREL = related, AEACN = action,
    AESER = if (cath_is_serious(grade)) "Y" else "N", AEOUT = "RECOVERED", AEONGO = "N"
  )
}

.routine_aes <- function(sim, patient, P, jit, row, prev_day) {
  fr <- patient$frailties
  log_hp <- log(P$ae_base_haz_procedural) + P$ae_frailty_coef * fr$f_ae
  if (np_random() < 1 - exp(-exp(log_hp))) {
    term <- CATH_PROC_TERMS[np_integers(0L, length(CATH_PROC_TERMS)) + 1L]
    row$aes[[length(row$aes) + 1L]] <- .cath_ae(patient, term, np_random() < P$ae_p_severe,
                                                onset_day = row$actual_day, visit = row, related = "UNRELATED")
  }
  if (identical(row$visit_key, "D21")) {   # VitD3 GI side effects are reported at Day 21
    log_hg <- log(P$ae_base_haz_vd_gi) + P$ae_frailty_coef * fr$f_ae + log(P$ae_rr_vd) * (if (patient$is_vitd) 1 else 0)
    if (np_random() < 1 - exp(-exp(log_hg))) {
      term <- CATH_GI_TERMS[np_integers(0L, length(CATH_GI_TERMS)) + 1L]
      onset <- sim$between(jit, prev_day, row$visit_day)
      related <- if (patient$is_vitd) "POSSIBLE" else "UNLIKELY"
      row$aes[[length(row$aes) + 1L]] <- .cath_ae(patient, term, np_random() < P$ae_p_severe,
                                                  onset_day = onset, visit = row, related = related)
    }
  }
  invisible(row)
}

.biopsy_row <- function(camp, hbd3, il13, il4, photo) list(
  CAMP_LES = round(camp[["lesional"]], 2), CAMP_NONLES = round(camp[["nonlesional"]], 2),
  HBD3_LES = round(hbd3[["lesional"]], 2), HBD3_NONLES = round(hbd3[["nonlesional"]], 2),
  IL13_LES = round(il13[["lesional"]], 2), IL13_NONLES = round(il13[["nonlesional"]], 2),
  IL4_LES = round(il4[["lesional"]], 2), IL4_NONLES = round(il4[["nonlesional"]], 2), PHOTO = photo)

.swab_row <- function(patient, P, flora) {
  if (np_random() < P$swcollect_prob) {
    loc <- if (patient$diagnosis_group != "NonAD" && np_random() < 0.5) "LESIONAL" else "NON-LESIONAL"
    list(SWCOLLECT = "YES", SWLOC = loc, SW_FLORA = flora)
  } else list(SWCOLLECT = "NO", SWLOC = "", SW_FLORA = "")
}

.discontinue <- function(sim, patient, P, jit, bl) {
  keys <- names(P$disc_reason_probs); probs <- as.numeric(unlist(P$disc_reason_probs)); probs <- probs / sum(probs)
  reason <- np_choice(keys, prob = probs)
  patient$not_completed <- TRUE; patient$efficacy_population <- FALSE
  patient$discontinuation_reason <- reason; patient$discontinuation_visit_day <- 21L
  disc_day <- as.integer(ceiling(jit$draw(function() np_uniform(1, CATH_ADMIN_CENSOR_DAY))))
  if (identical(reason, "ADVERSE EVENT")) {
    onset <- sim$between(jit, 0L, patient$discontinuation_visit_day)
    term <- if (patient$is_vitd) CATH_GI_TERMS[np_integers(0L, length(CATH_GI_TERMS)) + 1L]
            else CATH_PROC_TERMS[np_integers(0L, length(CATH_PROC_TERMS)) + 1L]
    related <- if (patient$is_vitd) "POSSIBLE" else "UNLIKELY"
    bl$aes[[length(bl$aes) + 1L]] <- .cath_ae(patient, term, severe = FALSE, onset_day = onset,
                                              visit = bl, related = related, action = "DRUG WITHDRAWN")
    disc_day <- max(disc_day, onset)
  }
  patient$discontinuation_day <- disc_day
  invisible(patient)
}

cath_simulate_trajectory <- function(sim, patient, jit) {
  P <- sim$params; fr <- patient$frailties
  day_of <- setNames(lapply(CATH_SCHED, function(s) s$day), vapply(CATH_SCHED, function(s) s$key, ""))
  num_of <- setNames(lapply(CATH_SCHED, function(s) s$visitnum), vapply(CATH_SCHED, function(s) s$key, ""))

  # ---- V1 Screening: serum labs ----
  scrn_day <- day_of$SCRN
  scrn <- cath_visitrow("SCRN", num_of$SCRN, scrn_day,
                        sim$clamp_actual_day(jit, scrn_day, scrn_day - 1L, day_of$BL - 1L, P$visit_jitter_sd_day))
  .merge(scrn, list(VITD = round(patient$vitd_bl, 1), CALCIUM = round(patient$calcium_bl, 2),
                    CREAT = round(patient$creat_bl, 2), PTH = round(patient$pth_bl, 1),
                    IGE = round(patient$ige_bl, 1), RAST = patient$rast_bl, SERUMSTOR = patient$serumstor))
  patient$trajectory[[length(patient$trajectory) + 1L]] <- scrn

  # ---- V2 Baseline (Day 0): skin substrate + vitals + physical exam + PASI ----
  bl <- cath_visitrow("BL", num_of$BL, 0L, 0L)   # Day 0 anchor, never jittered
  photo_bl <- if (P$photo_taken && patient$diagnosis_group != "NonAD") "TAKEN" else "N/A"
  .merge(bl, .biopsy_row(patient$camp_bl, patient$hbd3_bl, patient$il13_bl, patient$il4_bl, photo_bl))
  .merge(bl, list(SAL_CAMP = round(patient$sal_bl$SAL_CAMP, 2), SAL_HBD3 = round(patient$sal_bl$SAL_HBD3, 2),
                  SAL_TOTPROT = round(patient$sal_bl$SAL_TOTPROT, 2)))
  .merge(bl, lapply(patient$ts_bl, function(x) round(x, 2)))
  .merge(bl, list(CFU_LES = as.integer(round(exp(patient$cfu_bl$lesional))),
                  CFU_NONLES = as.integer(round(exp(patient$cfu_bl$nonlesional)))))
  .merge(bl, .swab_row(patient, P, patient$sw_flora_bl))
  vitals_bl <- .vitals(patient, P); .merge(bl, vitals_bl)
  .merge(bl, .pe(patient, P))
  pasi_bl <- .pasi(patient, P)
  bl$data$PASI <- pasi_bl; bl$data$FITZPATRICK <- patient$fitzpatrick
  .routine_aes(sim, patient, P, jit, bl, prev_day = 0L)
  patient$trajectory[[length(patient$trajectory) + 1L]] <- bl

  # ---- disposition: does the patient exit before Day 21, at an off-grid day ----
  p_disc <- expit(P$disc_logit_intercept + P$disc_dropout_coef * fr$f_dropout
                  + P$disc_drugreturn_coef * (if (patient$drug_not_returned) 1 else 0))
  if (np_random() < p_disc) {
    .discontinue(sim, patient, P, jit, bl)
    return(invisible(patient))   # a dropout has no Day-21 assessment
  }

  # ---- V3 Day 21: mediator (serum VitD), Day-21 substrate, labs ----
  d21_day <- day_of$D21
  d21 <- cath_visitrow("D21", num_of$D21, d21_day,
                       sim$clamp_actual_day(jit, d21_day, bl$actual_day, CATH_ADMIN_CENSOR_DAY + 1L, P$visit_jitter_sd_day))
  vitd_d21 <- clip(patient$vitd_bl
                   + P$vitd_d21_delta_full_compliance * (if (patient$is_vitd) 1 else 0) * (patient$ex_compliance / 100.0)
                   + (if (patient$is_vitd) P$vitd_d21_resp_coef * fr$f_vitd_resp else 0.0)
                   + np_normal(0, P$vitd_d21_noise_sd), 5, 120)
  calcium_d21 <- clip(P$calcium_d21_ar * patient$calcium_bl + (1 - P$calcium_d21_ar) * 9.4
                      + (if (patient$is_vitd) P$calcium_d21_vitd_bump else 0.0) + np_normal(0, 0.2), 8.4, 10.6)
  creat_d21 <- clip(P$creat_d21_ar * patient$creat_bl + (1 - P$creat_d21_ar) * 0.8 + np_normal(0, 0.08), 0.4, 1.5)
  pth_d21 <- clip(P$pth_d21_ar * patient$pth_bl + (1 - P$pth_d21_ar) * 34.0
                  + P$pth_d21_vitd_coupling * (vitd_d21 - patient$vitd_bl) + np_normal(0, 4.0), 10, 90)
  ige_d21 <- clip(exp(log(patient$ige_bl) + np_normal(0, P$ige_change_noise_sd)), 1, 20000)
  rast_d21 <- patient$rast_bl
  if (np_random() < P$rast_d21_flip_prob) rast_d21 <- if (patient$rast_bl == "POSITIVE") "NEGATIVE" else "POSITIVE"
  .merge(d21, list(VITD = round(vitd_d21, 1), CALCIUM = round(calcium_d21, 2), CREAT = round(creat_d21, 2),
                   PTH = round(pth_d21, 1), IGE = round(ige_d21, 1), RAST = rast_d21, SERUMSTOR = patient$serumstor))

  camp_d21 <- list(); hbd3_d21 <- list(); il13_d21 <- list(); il4_d21 <- list()
  for (c in c("lesional", "nonlesional")) {
    camp_d21[[c]] <- max(0.0, patient$camp_bl[[c]] + .amp_change(.change_cell(P$camp_change, patient$diagnosis_group, c), patient$is_vitd, fr$f_vitd_resp, P))
    hbd3_d21[[c]] <- max(0.0, patient$hbd3_bl[[c]] + .amp_change(.change_cell(P$hbd3_change, patient$diagnosis_group, c), patient$is_vitd, fr$f_vitd_resp, P))
    il13_d21[[c]] <- max(0.0, patient$il13_bl[[c]] + .il13_change(.change_cell(P$il13_change, patient$diagnosis_group, c), patient$is_vitd, fr$f_th2, P))
    il4_d21[[c]]  <- max(0.0, patient$il4_bl[[c]] + (if (patient$is_vitd) P$il4_change_vitd_delta else 0.0) + np_normal(0, P$il4_change_sd))
  }
  photo_d21 <- if (P$photo_taken && patient$diagnosis_group != "NonAD") "TAKEN" else "N/A"
  .merge(d21, .biopsy_row(camp_d21, hbd3_d21, il13_d21, il4_d21, photo_d21))

  .merge(d21, list(
    SAL_CAMP = round(max(0.0, patient$sal_bl$SAL_CAMP + (if (patient$is_vitd) P$sal_amp_vitd_delta else 0.0)
                        + (if (patient$is_vitd) 0.3 * fr$f_vitd_resp else 0.0) + np_normal(0, P$substrate_noise_sd)), 2),
    SAL_HBD3 = round(max(0.0, patient$sal_bl$SAL_HBD3 + (if (patient$is_vitd) P$sal_amp_vitd_delta else 0.0)
                        + np_normal(0, P$substrate_noise_sd)), 2),
    SAL_TOTPROT = round(clip(np_normal(P$sal_totprot_mean_sd[1], P$sal_totprot_mean_sd[2]), 0.2, 3.0), 2)))
  g0 <- P$ts_amp_gamma$gamma0; g1 <- P$ts_amp_gamma$gamma1
  .merge(d21, list(
    TS_CAMP_LES    = round(max(0.0, g0 + g1 * camp_d21$lesional    + 0.3 * fr$f_amp + np_normal(0, P$substrate_noise_sd)), 2),
    TS_CAMP_NONLES = round(max(0.0, g0 + g1 * camp_d21$nonlesional + 0.3 * fr$f_amp + np_normal(0, P$substrate_noise_sd)), 2),
    TS_HBD3_LES    = round(max(0.0, g0 + g1 * hbd3_d21$lesional    + 0.3 * fr$f_amp + np_normal(0, P$substrate_noise_sd)), 2),
    TS_HBD3_NONLES = round(max(0.0, g0 + g1 * hbd3_d21$nonlesional + 0.3 * fr$f_amp + np_normal(0, P$substrate_noise_sd)), 2)))

  cfu_d21 <- list()
  for (c in c("lesional", "nonlesional")) {
    dcamp <- camp_d21[[c]] - patient$camp_bl[[c]]
    cfu_d21[[c]] <- P$cfu_d21_ar * patient$cfu_bl[[c]] - P$cfu_amp_change_coef * dcamp + 0.3 * fr$f_microbiome + np_normal(0, P$cfu_noise_sd)
  }
  .merge(d21, list(CFU_LES = as.integer(round(exp(cfu_d21$lesional))), CFU_NONLES = as.integer(round(exp(cfu_d21$nonlesional)))))
  sw_d21 <- patient$sw_flora_bl
  if (np_random() < P$sw_flora_change_prob) sw_d21 <- if (patient$sw_flora_bl == "S. aureus predominant") "Mixed commensal flora" else "S. aureus predominant"
  .merge(d21, .swab_row(patient, P, sw_d21))
  .merge(d21, .vitals(patient, P, prior = vitals_bl))
  .merge(d21, .pe(patient, P))
  d21$data$PASI <- .pasi(patient, P, baseline = if (nzchar(as.character(pasi_bl))) pasi_bl else NULL)
  d21$data$FITZPATRICK <- ""
  .routine_aes(sim, patient, P, jit, d21, prev_day = bl$visit_day)
  patient$trajectory[[length(patient$trajectory) + 1L]] <- d21
  invisible(patient)
}
